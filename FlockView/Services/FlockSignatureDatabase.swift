import Foundation

enum FlockEvidenceTier: UInt8 {
    case communityObserved = 1
    case corroborated = 2
    case stronglyCorroborated = 3

    var ouiOnlyConfidenceScore: Int {
        switch self {
        case .stronglyCorroborated:
            35
        case .corroborated:
            30
        case .communityObserved:
            20
        }
    }
}

enum FlockRadioScope {
    case wifi
    case ble
    case wifiAndBle

    func includes(_ protocolType: ProtocolType) -> Bool {
        switch (self, protocolType) {
        case (.wifiAndBle, _):
            true
        case (.wifi, .wifi):
            true
        case (.ble, .ble):
            true
        default:
            false
        }
    }
}

struct FlockOuiRecord: Equatable {
    var prefix: String
    var tier: FlockEvidenceTier
    var scope: FlockRadioScope
    var source: String
    var notes: String
}

enum FlockDetectionMethod: String {
    case knownWifiOui = "known_wifi_oui"
    case knownBleOui = "known_ble_oui"
    case wifiSsidPattern = "wifi_ssid_pattern"
    case wifiSsidFormat = "wifi_ssid_format"
    case wifiWildcardProbe = "wifi_wildcard_probe"
    case bleNamePattern = "ble_name_pattern"
    case bleManufacturerId = "ble_manufacturer_id"
    case bleServiceUuid = "ble_service_uuid"
    case bleStaticAddress = "ble_static_address"
    case multipleSignals = "multiple_signals"
}

struct FlockClassificationResult: Equatable {
    var matched: Bool = false
    var confidence: Int = 0
    var confidenceLabel: ConfidenceLabel = .possible
    var vendor: String = "Flock Safety"
    var deviceType: String = "camera"
    var detectionMethods: [String] = []
}

struct FlockDeviceClassifier {
    static let bleManufacturerID: UInt16 = 0x09C8

    func classifyWiFi(
        macAddress: String,
        ssid: String?,
        frameSubtype: String? = nil
    ) -> FlockClassificationResult {
        var result = FlockClassificationResult(deviceType: "camera")

        if let record = Self.matchOui(macAddress: macAddress, protocolType: .wifi) {
            addMethod(.knownWifiOui, score: record.tier.ouiOnlyConfidenceScore, to: &result)
        }

        if let ssid, !ssid.isEmpty {
            if Self.isFlockSsidFormat(ssid) {
                addMethod(.wifiSsidFormat, score: 70, to: &result)
            } else if Self.matchesWiFiSSIDPattern(ssid) {
                addMethod(.wifiSsidPattern, score: 45, to: &result)
            }
        }

        if result.detectionMethods.contains(FlockDetectionMethod.knownWifiOui.rawValue),
           frameSubtype == "probe_request",
           ssid == "" {
            addMethod(.wifiWildcardProbe, score: 35, to: &result)
        }

        addMultipleSignalsIfNeeded(to: &result)
        finalize(&result)
        return result
    }

    func classifyBLE(
        displayAddress: String,
        name: String?,
        manufacturerID: UInt16?,
        serviceUUIDs: [String],
        addressType: String?
    ) -> FlockClassificationResult {
        var result = FlockClassificationResult(deviceType: "camera_accessory")

        if let record = Self.matchOui(macAddress: displayAddress, protocolType: .ble) {
            addMethod(.knownBleOui, score: record.tier.ouiOnlyConfidenceScore, to: &result)
        }

        if let name, Self.matchesBLENamePattern(name) {
            addMethod(.bleNamePattern, score: 45, to: &result)
        }

        if manufacturerID == Self.bleManufacturerID {
            addMethod(.bleManufacturerId, score: 60, to: &result)
        }

        if serviceUUIDs.contains(where: Self.matchesBLEServiceUUID) {
            addMethod(.bleServiceUuid, score: 70, to: &result)
        }

        if let addressType, Self.isStaticBLEAddressLabel(addressType), !result.detectionMethods.isEmpty {
            addMethod(.bleStaticAddress, score: 10, to: &result)
        }

        addMultipleSignalsIfNeeded(to: &result)
        finalize(&result)
        return result
    }

    static func matchOui(macAddress: String, protocolType: ProtocolType) -> FlockOuiRecord? {
        guard let prefix = normalizedPrefix(macAddress) else {
            return nil
        }

        return ouiRecords.first { record in
            record.prefix == prefix && record.scope.includes(protocolType)
        }
    }

    static func matchesWiFiSSIDPattern(_ ssid: String) -> Bool {
        wifiSSIDPatterns.contains { containsCaseInsensitive(ssid, $0) }
    }

    static func matchesBLENamePattern(_ name: String) -> Bool {
        bleNamePatterns.contains { containsCaseInsensitive(name, $0) }
    }

    static func matchesBLEServiceUUID(_ uuid: String) -> Bool {
        bleServiceUUIDs.contains { $0.caseInsensitiveCompare(uuid) == .orderedSame }
    }

    static func isFlockSsidFormat(_ ssid: String) -> Bool {
        let lowercased = ssid.lowercased()
        guard lowercased.contains("flock-") else {
            return false
        }

        let characters = Array(lowercased)
        guard characters.count >= 10 else {
            return false
        }

        for start in characters.indices where start + 6 <= characters.count {
            guard String(characters[start..<min(start + 6, characters.count)]) == "flock-" else {
                continue
            }

            var hexCount = 0
            var cursor = start + 6
            while cursor < characters.count, characters[cursor].isHexDigit {
                hexCount += 1
                cursor += 1
            }
            return hexCount >= 4 && hexCount <= 8
        }

        return false
    }

    static func isStaticBLEAddressLabel(_ addressType: String) -> Bool {
        ["public", "random_static", "static"].contains {
            $0.caseInsensitiveCompare(addressType) == .orderedSame
        }
    }

    private func addMethod(
        _ method: FlockDetectionMethod,
        score: Int,
        to result: inout FlockClassificationResult
    ) {
        guard !result.detectionMethods.contains(method.rawValue) else {
            return
        }

        result.detectionMethods.append(method.rawValue)
        result.confidence = min(100, result.confidence + score)
    }

    private func addMultipleSignalsIfNeeded(to result: inout FlockClassificationResult) {
        guard result.detectionMethods.count >= 2 else {
            return
        }
        addMethod(.multipleSignals, score: 20, to: &result)
    }

    private func finalize(_ result: inout FlockClassificationResult) {
        result.matched = !result.detectionMethods.isEmpty
        result.confidenceLabel = Self.label(forConfidence: result.confidence)
    }

    private static func label(forConfidence confidence: Int) -> ConfidenceLabel {
        if confidence >= 85 {
            return .confirmed
        }
        if confidence >= 70 {
            return .high
        }
        if confidence >= 40 {
            return .likely
        }
        return .possible
    }

    private static func containsCaseInsensitive(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func normalizedPrefix(_ macAddress: String) -> String? {
        let hex = macAddress
            .filter(\.isHexDigit)
            .uppercased()
        guard hex.count == 12 else {
            return nil
        }
        let start = hex.startIndex
        let first = hex[start..<hex.index(start, offsetBy: 2)]
        let second = hex[hex.index(start, offsetBy: 2)..<hex.index(start, offsetBy: 4)]
        let third = hex[hex.index(start, offsetBy: 4)..<hex.index(start, offsetBy: 6)]
        return "\(first):\(second):\(third)"
    }

    static let wifiSSIDPatterns = [
        "flock",
        "FS Ext Battery",
        "Penguin",
        "Pigvision",
        "FlockOS",
        "flocksafety",
        "FS_",
        "test_flck"
    ]

    static let bleNamePatterns = [
        "FS Ext Battery",
        "Penguin",
        "Flock",
        "Pigvision",
        "FlockCam",
        "FS-"
    ]

    static let bleServiceUUIDs: [String] = []

    static let ouiRecords: [FlockOuiRecord] = [
        FlockOuiRecord(prefix: "70:C9:4E", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "3C:91:80", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "D8:F3:BC", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "80:30:49", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "B8:35:32", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "14:5A:FC", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "74:4C:A1", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "08:3A:88", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Known false-positive risk; module vendor is broadly used."),
        FlockOuiRecord(prefix: "9C:2F:9D", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "C0:35:32", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "94:08:53", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "E4:AA:EA", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "F4:6A:DD", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "F8:A2:D6", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "24:B2:B9", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "00:F4:8D", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "D0:39:57", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "E8:D0:FC", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "E0:4F:43", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "B8:1E:A4", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "70:08:94", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "58:8E:81", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "EC:1B:BD", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "3C:71:BF", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "58:00:E3", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "90:35:EA", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "5C:93:A2", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "64:6E:69", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "48:27:EA", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "A4:CF:12", tier: .communityObserved, scope: .wifiAndBle, source: "NitekryDPaul/flock-you", notes: "Observed in Flock-related infrastructure; not exclusive."),
        FlockOuiRecord(prefix: "82:6B:F2", tier: .corroborated, scope: .wifi, source: "DeFlockJoplin/flock-you", notes: "31st prefix added from DeFlock Joplin observations."),
        FlockOuiRecord(prefix: "B4:1E:52", tier: .stronglyCorroborated, scope: .wifiAndBle, source: "FlockViewScanner/FlockSignatures.h", notes: "Additional Flock Safety registered OUI documented by ESP32 scanner signatures."),
        FlockOuiRecord(prefix: "CC:CC:CC", tier: .communityObserved, scope: .ble, source: "FlockViewScanner/FlockSignatures.h", notes: "FS Ext Battery BLE prefix from ESP32 scanner signatures."),
        FlockOuiRecord(prefix: "04:0D:84", tier: .communityObserved, scope: .ble, source: "FlockViewScanner/FlockSignatures.h", notes: "FS Ext Battery BLE prefix from ESP32 scanner signatures."),
        FlockOuiRecord(prefix: "F0:82:C0", tier: .communityObserved, scope: .ble, source: "FlockViewScanner/FlockSignatures.h", notes: "FS Ext Battery BLE prefix from ESP32 scanner signatures."),
        FlockOuiRecord(prefix: "1C:34:F1", tier: .communityObserved, scope: .ble, source: "FlockViewScanner/FlockSignatures.h", notes: "FS Ext Battery BLE prefix from ESP32 scanner signatures."),
        FlockOuiRecord(prefix: "38:5B:44", tier: .communityObserved, scope: .ble, source: "FlockViewScanner/FlockSignatures.h", notes: "FS Ext Battery BLE prefix from ESP32 scanner signatures."),
        FlockOuiRecord(prefix: "94:34:69", tier: .communityObserved, scope: .ble, source: "FlockViewScanner/FlockSignatures.h", notes: "FS Ext Battery BLE prefix from ESP32 scanner signatures."),
        FlockOuiRecord(prefix: "B4:E3:F9", tier: .communityObserved, scope: .ble, source: "FlockViewScanner/FlockSignatures.h", notes: "FS Ext Battery BLE prefix from ESP32 scanner signatures.")
    ]
}
