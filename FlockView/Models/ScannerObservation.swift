import Foundation

enum ConfidenceLabel: String, Codable, Sendable {
    case possible = "POSSIBLE"
    case likely = "LIKELY"
    case high = "HIGH"
    case confirmed = "CONFIRMED"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self).uppercased()
        self = ConfidenceLabel(rawValue: rawValue) ?? .possible
    }
}

enum RSSITrend: String, Codable, Sendable {
    case rising
    case stable
    case falling

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = RSSITrend(rawValue: try container.decode(String.self).lowercased()) ?? .stable
    }
}

struct ScannerObservation: Identifiable, Codable, Hashable, Sendable {
    var id: String { deviceID }
    var schemaVersion: Int
    var event: String
    var vendor: String
    var deviceType: String
    var protocolType: ProtocolType
    var deviceID: String
    var macAddress: String
    var name: String?
    var bssid: String?
    var ssid: String?
    var addressType: String?
    var manufacturerID: String?
    var serviceUUIDs: [String]
    var frameSubtype: String?
    var channel: Int?
    var frequencyMHz: Int?
    var rssi: Int
    var smoothedRSSI: Double?
    var peakRSSI: Int?
    var averageRSSI: Double?
    var proximity: ProximityLevel?
    var rssiTrend: RSSITrend?
    var confidence: Int
    var confidenceLabel: ConfidenceLabel
    var detectionMethods: [String]
    var observationCount: UInt64
    var firstSeenMilliseconds: UInt64?
    var lastSeenMilliseconds: UInt64?
    var uptimeMilliseconds: UInt64
    var rawEvent: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case event
        case vendor
        case deviceType = "device_type"
        case protocolType = "protocol"
        case deviceID = "device_id"
        case macAddress = "mac_address"
        case name
        case bssid
        case ssid
        case addressType = "address_type"
        case manufacturerID = "manufacturer_id"
        case serviceUUIDs = "service_uuids"
        case frameSubtype = "frame_subtype"
        case channel
        case frequencyMHz = "frequency_mhz"
        case rssi
        case smoothedRSSI = "smoothed_rssi"
        case peakRSSI = "peak_rssi"
        case averageRSSI = "average_rssi"
        case proximity
        case rssiTrend = "rssi_trend"
        case confidence
        case confidenceLabel = "confidence_label"
        case detectionMethods = "detection_methods"
        case observationCount = "observation_count"
        case firstSeenMilliseconds = "first_seen_ms"
        case lastSeenMilliseconds = "last_seen_ms"
        case uptimeMilliseconds = "uptime_ms"
    }

    init(
        schemaVersion: Int = 1,
        event: String = "detection",
        vendor: String = "Flock Safety",
        deviceType: String = "camera",
        protocolType: ProtocolType,
        deviceID: String,
        macAddress: String,
        name: String? = nil,
        bssid: String? = nil,
        ssid: String? = nil,
        addressType: String? = nil,
        manufacturerID: String? = nil,
        serviceUUIDs: [String] = [],
        frameSubtype: String? = nil,
        channel: Int? = nil,
        frequencyMHz: Int? = nil,
        rssi: Int,
        smoothedRSSI: Double? = nil,
        peakRSSI: Int? = nil,
        averageRSSI: Double? = nil,
        proximity: ProximityLevel? = nil,
        rssiTrend: RSSITrend? = nil,
        confidence: Int = 0,
        confidenceLabel: ConfidenceLabel = .possible,
        detectionMethods: [String] = [],
        observationCount: UInt64 = 1,
        firstSeenMilliseconds: UInt64? = nil,
        lastSeenMilliseconds: UInt64? = nil,
        uptimeMilliseconds: UInt64 = 0,
        rawEvent: String
    ) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.vendor = vendor
        self.deviceType = deviceType
        self.protocolType = protocolType
        self.deviceID = deviceID
        self.macAddress = macAddress
        self.name = name
        self.bssid = bssid
        self.ssid = ssid
        self.addressType = addressType
        self.manufacturerID = manufacturerID
        self.serviceUUIDs = serviceUUIDs
        self.frameSubtype = frameSubtype
        self.channel = channel
        self.frequencyMHz = frequencyMHz
        self.rssi = rssi
        self.smoothedRSSI = smoothedRSSI
        self.peakRSSI = peakRSSI
        self.averageRSSI = averageRSSI
        self.proximity = proximity
        self.rssiTrend = rssiTrend
        self.confidence = confidence
        self.confidenceLabel = confidenceLabel
        self.detectionMethods = detectionMethods
        self.observationCount = observationCount
        self.firstSeenMilliseconds = firstSeenMilliseconds
        self.lastSeenMilliseconds = lastSeenMilliseconds
        self.uptimeMilliseconds = uptimeMilliseconds
        self.rawEvent = rawEvent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        event = try container.decode(String.self, forKey: .event)
        vendor = try container.decodeIfPresent(String.self, forKey: .vendor) ?? ""
        deviceType = try container.decodeIfPresent(String.self, forKey: .deviceType) ?? ""
        protocolType = try container.decode(ProtocolType.self, forKey: .protocolType)
        deviceID = try container.decodeIfPresent(String.self, forKey: .deviceID)
            ?? "\(protocolType.normalizedID):\(try container.decode(String.self, forKey: .macAddress))"
        macAddress = try container.decode(String.self, forKey: .macAddress)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        bssid = try container.decodeIfPresent(String.self, forKey: .bssid)
        ssid = try container.decodeIfPresent(String.self, forKey: .ssid)
        addressType = try container.decodeIfPresent(String.self, forKey: .addressType)
        manufacturerID = try container.decodeIfPresent(String.self, forKey: .manufacturerID)
        serviceUUIDs = try container.decodeIfPresent([String].self, forKey: .serviceUUIDs) ?? []
        frameSubtype = try container.decodeIfPresent(String.self, forKey: .frameSubtype)
        channel = try container.decodeIfPresent(Int.self, forKey: .channel)
        frequencyMHz = try container.decodeIfPresent(Int.self, forKey: .frequencyMHz)
        rssi = try container.decode(Int.self, forKey: .rssi)
        smoothedRSSI = try container.decodeIfPresent(Double.self, forKey: .smoothedRSSI)
        peakRSSI = try container.decodeIfPresent(Int.self, forKey: .peakRSSI)
        averageRSSI = try container.decodeIfPresent(Double.self, forKey: .averageRSSI)
        proximity = try container.decodeIfPresent(ProximityLevel.self, forKey: .proximity)
        rssiTrend = try container.decodeIfPresent(RSSITrend.self, forKey: .rssiTrend)
        confidence = try container.decodeIfPresent(Int.self, forKey: .confidence) ?? 0
        confidenceLabel = try container.decodeIfPresent(ConfidenceLabel.self, forKey: .confidenceLabel) ?? .possible
        detectionMethods = try container.decodeIfPresent([String].self, forKey: .detectionMethods) ?? []
        observationCount = try container.decodeIfPresent(UInt64.self, forKey: .observationCount) ?? 1
        firstSeenMilliseconds = try container.decodeIfPresent(UInt64.self, forKey: .firstSeenMilliseconds)
        lastSeenMilliseconds = try container.decodeIfPresent(UInt64.self, forKey: .lastSeenMilliseconds)
        uptimeMilliseconds = try container.decode(UInt64.self, forKey: .uptimeMilliseconds)
        rawEvent = ""
    }

    var isSupportedDetection: Bool {
        event == "detection"
            && vendor.localizedCaseInsensitiveContains("Flock")
            && deviceType.localizedCaseInsensitiveContains("camera")
    }

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }

        if deviceType.localizedCaseInsensitiveContains("accessory") {
            return "Flock Camera Accessory"
        }

        return "Flock Safety Camera"
    }
}
