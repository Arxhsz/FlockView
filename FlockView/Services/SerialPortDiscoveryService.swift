import Foundation
import IOKit
import IOKit.serial

final class SerialPortDiscoveryService {
    func availableDevices() -> [SerialDevice] {
        var devicesByID: [String: SerialDevice] = [:]

        for device in iokitDevices() + filesystemDevices() {
            let key = dedupeKey(for: device)
            if let existing = devicesByID[key] {
                devicesByID[key] = preferredDevice(existing, device)
            } else {
                devicesByID[key] = device
            }
        }

        return devicesByID.values.sorted { lhs, rhs in
            if lhs.isLikelyESP32 != rhs.isLikelyESP32 {
                return lhs.isLikelyESP32 && !rhs.isLikelyESP32
            }
            if lhs.path.hasPrefix("/dev/cu.") != rhs.path.hasPrefix("/dev/cu.") {
                return lhs.path.hasPrefix("/dev/cu.")
            }
            return lhs.displayName.localizedStandardCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func iokitDevices() -> [SerialDevice] {
        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else {
            return []
        }

        let matchingDictionary = matching as NSMutableDictionary
        matchingDictionary[kIOSerialBSDTypeKey as String] = kIOSerialBSDAllTypes

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matchingDictionary, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [SerialDevice] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else {
                break
            }
            defer { IOObjectRelease(service) }

            guard let path = stringProperty(kIOCalloutDeviceKey as CFString, from: service) else {
                continue
            }

            let baseName = baseName(from: path)
            let ttyName = stringProperty(kIOTTYDeviceKey as CFString, from: service) ?? baseName
            let metadata = usbMetadata(for: service)
            let displayName = metadata.product ?? displayName(for: ttyName)

            devices.append(
                SerialDevice(
                    id: metadata.serialNumber ?? baseName,
                    path: path,
                    displayName: displayName,
                    vendorID: metadata.vendorID,
                    productID: metadata.productID,
                    serialNumber: metadata.serialNumber ?? serialNumberGuess(from: baseName),
                    usbManufacturer: metadata.manufacturer ?? manufacturerGuess(from: baseName),
                    usbProduct: metadata.product ?? productGuess(from: baseName)
                )
            )
        }

        return devices
    }

    private func filesystemDevices() -> [SerialDevice] {
        let devURL = URL(fileURLWithPath: "/dev", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: devURL.path())) ?? []
        return names
            .filter { $0.hasPrefix("cu.") || $0.hasPrefix("tty.") }
            .map { name in
                let path = "/dev/\(name)"
                let baseName = baseName(from: path)
                return SerialDevice(
                    id: baseName,
                    path: path,
                    displayName: displayName(for: baseName),
                    vendorID: nil,
                    productID: nil,
                    serialNumber: serialNumberGuess(from: baseName),
                    usbManufacturer: manufacturerGuess(from: baseName),
                    usbProduct: productGuess(from: baseName)
                )
            }
    }

    private func usbMetadata(for service: io_registry_entry_t) -> (vendorID: Int?, productID: Int?, serialNumber: String?, manufacturer: String?, product: String?) {
        var vendorID: Int?
        var productID: Int?
        var serialNumber: String?
        var manufacturer: String?
        var product: String?

        var current: io_registry_entry_t = service
        var parent: io_registry_entry_t = 0
        while IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent) == KERN_SUCCESS {
            if current != service {
                IOObjectRelease(current)
            }
            current = parent

            vendorID = vendorID ?? numberProperty("idVendor" as CFString, from: current)
            productID = productID ?? numberProperty("idProduct" as CFString, from: current)
            serialNumber = serialNumber
                ?? stringProperty("USB Serial Number" as CFString, from: current)
                ?? stringProperty("kUSBSerialNumberString" as CFString, from: current)
                ?? stringProperty("Serial Number" as CFString, from: current)
            manufacturer = manufacturer
                ?? stringProperty("USB Vendor Name" as CFString, from: current)
                ?? stringProperty("USB Manufacturer" as CFString, from: current)
                ?? stringProperty("Manufacturer" as CFString, from: current)
            product = product
                ?? stringProperty("USB Product Name" as CFString, from: current)
                ?? stringProperty("USB Product" as CFString, from: current)
                ?? stringProperty("Product Name" as CFString, from: current)

            if vendorID != nil, productID != nil, serialNumber != nil, manufacturer != nil, product != nil {
                break
            }
        }

        if current != service {
            IOObjectRelease(current)
        }

        return (vendorID, productID, serialNumber, manufacturer, product)
    }

    private func stringProperty(_ key: CFString, from entry: io_registry_entry_t) -> String? {
        guard let retained = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0) else {
            return nil
        }
        return retained.takeRetainedValue() as? String
    }

    private func numberProperty(_ key: CFString, from entry: io_registry_entry_t) -> Int? {
        guard let retained = IORegistryEntryCreateCFProperty(entry, key, kCFAllocatorDefault, 0) else {
            return nil
        }

        let value = retained.takeRetainedValue()
        if let number = value as? NSNumber {
            return number.intValue
        }
        if let intValue = value as? Int {
            return intValue
        }
        return nil
    }

    private func preferredDevice(_ lhs: SerialDevice, _ rhs: SerialDevice) -> SerialDevice {
        if lhs.path.hasPrefix("/dev/cu.") != rhs.path.hasPrefix("/dev/cu.") {
            return lhs.path.hasPrefix("/dev/cu.") ? lhs : rhs
        }
        if lhs.vendorID == nil, rhs.vendorID != nil {
            return rhs
        }
        return lhs
    }

    private func dedupeKey(for device: SerialDevice) -> String {
        if let serialNumber = device.serialNumber, !serialNumber.isEmpty {
            return "serial:\(serialNumber)"
        }
        return "base:\(baseName(from: device.path))"
    }

    private func baseName(from path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
            .replacingOccurrences(of: "cu.", with: "")
            .replacingOccurrences(of: "tty.", with: "")
    }

    private func displayName(for baseName: String) -> String {
        if baseName.localizedCaseInsensitiveContains("usbserial") {
            return "USB Serial (\(baseName))"
        }
        if baseName.localizedCaseInsensitiveContains("wchusbserial") {
            return "CH340/CH341 USB Serial (\(baseName))"
        }
        if baseName.localizedCaseInsensitiveContains("slab") || baseName.localizedCaseInsensitiveContains("cp210") {
            return "Silicon Labs CP210x (\(baseName))"
        }
        return baseName
    }

    private func manufacturerGuess(from baseName: String) -> String? {
        let lowercased = baseName.lowercased()
        if lowercased.contains("slab") || lowercased.contains("cp210") {
            return "Silicon Labs"
        }
        if lowercased.contains("wch") || lowercased.contains("ch340") || lowercased.contains("ch341") {
            return "WCH"
        }
        if lowercased.contains("ftdi") || lowercased.contains("usbserial") {
            return "FTDI or USB Serial"
        }
        return nil
    }

    private func productGuess(from baseName: String) -> String? {
        let lowercased = baseName.lowercased()
        if lowercased.contains("cp210") || lowercased.contains("slab") {
            return "CP210x USB-UART"
        }
        if lowercased.contains("ch340") || lowercased.contains("ch341") || lowercased.contains("wch") {
            return "CH340/CH341 USB-UART"
        }
        if lowercased.contains("usbserial") {
            return "USB Serial"
        }
        return nil
    }

    private func serialNumberGuess(from baseName: String) -> String? {
        let parts = baseName.split(separator: "-")
        guard parts.count > 1 else {
            return nil
        }
        return String(parts.last ?? "")
    }
}
