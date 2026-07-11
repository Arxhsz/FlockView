import Foundation

enum ScannerSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case hardware
    case macNative
    case test
    case recorded

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self).lowercased() {
        case "macnative", "mac_native", "mac", "native", "mac scanner", "mac scanner mode":
            self = .macNative
        case "test", "demo":
            self = .test
        case "recorded":
            self = .recorded
        default:
            self = .hardware
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var displayName: String {
        switch self {
        case .hardware:
            "Hardware"
        case .macNative:
            "Mac Scanner"
        case .test:
            "Test Mode"
        case .recorded:
            "Recorded Playback"
        }
    }

    var requiresScannerConnection: Bool {
        self == .hardware || self == .macNative
    }

    var isLiveScanner: Bool {
        self == .hardware || self == .macNative
    }
}

enum SessionDataSource: String, Codable, Sendable {
    case hardware
    case macNative
    case test
    case recorded
}

struct SerialDevice: Identifiable, Hashable, Codable, Sendable {
    var id: String
    var path: String
    var displayName: String
    var vendorID: Int?
    var productID: Int?
    var serialNumber: String?
    var usbManufacturer: String?
    var usbProduct: String?

    var isLikelyESP32: Bool {
        let haystack = [
            path,
            displayName,
            serialNumber ?? "",
            usbManufacturer ?? "",
            usbProduct ?? ""
        ].joined(separator: " ").lowercased()

        return ["cp210", "ch340", "ch341", "ftdi", "usb serial", "uart", "silicon labs", "wchusbserial", "usbserial"].contains {
            haystack.contains($0)
        }
    }

    var isHardwareSerialPort: Bool {
        path.hasPrefix("/dev/cu.") || path.hasPrefix("/dev/tty.")
    }
}

extension SerialDevice {
    static let nativeMacScanner = SerialDevice(
        id: "mac-native",
        path: "mac://ble-wifi",
        displayName: "Mac BLE + Wi-Fi Scanner",
        vendorID: nil,
        productID: nil,
        serialNumber: nil,
        usbManufacturer: "Apple",
        usbProduct: "CoreBluetooth/CoreWLAN"
    )
}

struct ScannerCapabilities: Equatable, Codable, Sendable {
    var firmware: String
    var firmwareVersion: String
    var board: String
    var passiveOnly: Bool
    var wifiBands: [String]
    var bleSupported: Bool

    static let unknown = ScannerCapabilities(
        firmware: "FlockViewScanner",
        firmwareVersion: "0.1.0",
        board: "esp32-wroom-32",
        passiveOnly: true,
        wifiBands: ["2.4GHz"],
        bleSupported: true
    )
}

enum ScannerConnectionState: Equatable, Sendable {
    case disconnected
    case discovering
    case connecting(SerialDevice)
    case handshaking(SerialDevice)
    case connected(SerialDevice, ScannerCapabilities)
    case reconnecting(attempt: Int)
    case failed(message: String)
    case testMode
    case recordedMode

    var visibleStatus: String {
        switch self {
        case .connected:
            "Connected"
        case .discovering:
            "Discovering"
        case .connecting:
            "Connecting"
        case .handshaking:
            "Handshaking"
        case .reconnecting(let attempt):
            "Reconnect \(attempt)"
        case .failed:
            "Failed"
        case .testMode:
            "Test Mode"
        case .recordedMode:
            "Recorded"
        case .disconnected:
            "Disconnected"
        }
    }

    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }

    var connectedDevice: SerialDevice? {
        if case .connected(let device, _) = self {
            return device
        }
        return nil
    }

    var capabilities: ScannerCapabilities? {
        if case .connected(_, let capabilities) = self {
            return capabilities
        }
        return nil
    }
}

enum ScanMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case bleOnly = "BLE Only"
    case wifiOnly = "Wi-Fi Only"
    case dual = "Dual"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self).lowercased() {
        case "ble", "ble only":
            self = .bleOnly
        case "wifi", "wi-fi", "wifi only", "wi-fi only":
            self = .wifiOnly
        default:
            self = .dual
        }
    }

    var displayValue: String {
        switch self {
        case .bleOnly:
            "BLE Only"
        case .wifiOnly:
            "Wi-Fi Only"
        case .dual:
            "DUAL (BLE + Wi-Fi)"
        }
    }

    var commandValue: String {
        switch self {
        case .bleOnly:
            "BLE"
        case .wifiOnly:
            "WIFI"
        case .dual:
            "DUAL"
        }
    }
}

enum WiFiChannelSetting: String, Codable, CaseIterable, Identifiable, Sendable {
    case autoHop = "Auto Hop"
    case channel1 = "Channel 1"
    case channel6 = "Channel 6"
    case channel11 = "Channel 11"

    var id: String { rawValue }

    var displayValue: String {
        switch self {
        case .autoHop:
            "Channel Hopping"
        case .channel1:
            "1 (2412 MHz)"
        case .channel6:
            "6 (2437 MHz)"
        case .channel11:
            "11 (2462 MHz)"
        }
    }

    static func live(channel: Int?) -> String {
        guard let channel else {
            return "Channel Hopping"
        }

        return "Current Channel \(channel)"
    }
}

enum BLEScanState: String, Codable, CaseIterable, Identifiable, Sendable {
    case active = "Active"
    case waiting = "Waiting"
    case paused = "Paused"
    case disabled = "Disabled"
    case unavailable = "Unavailable"

    var id: String { rawValue }
}

struct ScannerStatus: Codable, Equatable, Sendable {
    var schemaVersion: Int
    var state: String
    var mode: ScanMode
    var phase: String?
    var wifiChannel: Int?
    var wifiFramesSeen: UInt64
    var bleAdvertisementsSeen: UInt64
    var queueDepth: Int
    var queueHighWatermark: Int?
    var droppedObservations: UInt64
    var trackedDevices: Int?
    var matchingDevices: Int?
    var freeHeap: Int?
    var uptimeMilliseconds: UInt64
    var firmwareVersion: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state
        case mode
        case phase
        case wifiChannel = "wifi_channel"
        case wifiFramesSeen = "wifi_frames_seen"
        case bleAdvertisementsSeen = "ble_advertisements_seen"
        case queueDepth = "queue_depth"
        case queueHighWatermark = "queue_high_watermark"
        case droppedObservations = "dropped_observations"
        case trackedDevices = "tracked_devices"
        case matchingDevices = "matching_devices"
        case freeHeap = "free_heap"
        case uptimeMilliseconds = "uptime_ms"
        case firmwareVersion = "firmware_version"
    }

    static let disconnected = ScannerStatus(
        schemaVersion: 1,
        state: "disconnected",
        mode: .dual,
        phase: nil,
        wifiChannel: nil,
        wifiFramesSeen: 0,
        bleAdvertisementsSeen: 0,
        queueDepth: 0,
        queueHighWatermark: nil,
        droppedObservations: 0,
        trackedDevices: nil,
        matchingDevices: nil,
        freeHeap: nil,
        uptimeMilliseconds: 0,
        firmwareVersion: nil
    )

    static let test = ScannerStatus(
        schemaVersion: 1,
        state: "stopped",
        mode: .dual,
        phase: "wifi",
        wifiChannel: 6,
        wifiFramesSeen: 0,
        bleAdvertisementsSeen: 0,
        queueDepth: 0,
        queueHighWatermark: 0,
        droppedObservations: 0,
        trackedDevices: 12,
        matchingDevices: 12,
        freeHeap: nil,
        uptimeMilliseconds: 0,
        firmwareVersion: "test"
    )

    var isScanning: Bool {
        state == "scanning"
    }

    var bleScanState: BLEScanState {
        guard mode != .wifiOnly else {
            return .disabled
        }
        guard isScanning else {
            return .paused
        }
        return phase == "ble" ? .active : .waiting
    }

    var wifiChannelDisplay: String {
        WiFiChannelSetting.live(channel: wifiChannel)
    }
}
