import Foundation

struct RSSISample: Identifiable, Codable, Hashable {
    let id: UUID
    var timestamp: Date
    var rssi: Int

    init(id: UUID = UUID(), timestamp: Date, rssi: Int) {
        self.id = id
        self.timestamp = timestamp
        self.rssi = rssi
    }
}

enum CameraType: String, Codable {
    case camera = "Camera"
}

enum ProtocolType: String, Codable, CaseIterable, Identifiable {
    case wifi = "Wi-Fi"
    case ble = "BLE"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self).lowercased()
        switch value {
        case "wifi", "wi-fi":
            self = .wifi
        case "ble":
            self = .ble
        default:
            self = .wifi
        }
    }

    var normalizedID: String {
        switch self {
        case .wifi:
            "wifi"
        case .ble:
            "ble"
        }
    }

    var symbolName: String {
        switch self {
        case .wifi:
            "wifi"
        case .ble:
            "wave.3.right"
        }
    }
}

enum ProximityLevel: String, Codable, Hashable {
    case close = "Close"
    case medium = "Medium"
    case far = "Far"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self).lowercased() {
        case "close":
            self = .close
        case "medium":
            self = .medium
        case "far":
            self = .far
        default:
            self = .medium
        }
    }

    var signalLabel: String {
        switch self {
        case .close:
            "Strong Signal"
        case .medium:
            "Moderate Signal"
        case .far:
            "Weak Signal"
        }
    }
}

struct CameraDetection: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var type: CameraType
    var macAddress: String
    var protocolType: ProtocolType
    var channel: Int?
    var frequencyMHz: Int?
    var rssi: Int
    var peakRSSI: Int
    var averageRSSI: Double
    var observationCount: Int
    var firstSeen: Date
    var lastSeen: Date
    var secondsSinceSeen: Int
    var marked: Bool
    var note: String
    var noteUpdatedAt: Date?
    var rssiHistory: [RSSISample]
    var deviceID: String = ""
    var confidence: Int = 0
    var confidenceLabel: ConfidenceLabel = .possible
    var detectionMethods: [String] = []
    var rawEvent: String = ""
    var sessionSource: SessionDataSource = .test
    var smoothedRSSI: Double?
    var rssiTrend: RSSITrend?

    func proximity(closeThreshold: Int = -59, mediumThreshold: Int = -74, farThreshold: Int = -75) -> ProximityLevel {
        if rssi >= closeThreshold {
            return .close
        }

        if rssi <= farThreshold {
            return .far
        }

        if rssi >= mediumThreshold {
            return .medium
        }

        return .medium
    }

    var channelDescription: String {
        if let channel, let frequencyMHz {
            return "CH \(channel) (\(frequencyMHz) MHz)"
        }

        if let channel {
            return "CH \(channel)"
        }

        if let frequencyMHz {
            return "\(frequencyMHz) MHz"
        }

        return "Advertising"
    }

    var exportSummary: String {
        [
            name,
            "MAC: \(macAddress)",
            protocolType.rawValue,
            channelDescription,
            "\(rssi) dBm",
            "\(observationCount) observations"
        ].joined(separator: " | ")
    }

    mutating func applyRSSI(_ newRSSI: Int, at timestamp: Date) {
        let previousTotal = averageRSSI * Double(max(observationCount, 1))
        observationCount += 1
        rssi = newRSSI
        peakRSSI = max(peakRSSI, newRSSI)
        averageRSSI = (previousTotal + Double(newRSSI)) / Double(observationCount)
        lastSeen = timestamp
        secondsSinceSeen = 0
        rssiHistory.append(RSSISample(timestamp: timestamp, rssi: newRSSI))
        rssiHistory.removeAll { timestamp.timeIntervalSince($0.timestamp) > 120 }
    }

    mutating func applyObservation(_ observation: ScannerObservation, at timestamp: Date) {
        rssi = observation.rssi
        smoothedRSSI = observation.smoothedRSSI
        peakRSSI = max(peakRSSI, observation.peakRSSI ?? observation.rssi)
        averageRSSI = observation.averageRSSI ?? averageRSSI
        observationCount = max(observationCount, Int(observation.observationCount))
        channel = observation.channel ?? channel
        frequencyMHz = observation.frequencyMHz ?? frequencyMHz
        confidence = observation.confidence
        confidenceLabel = observation.confidenceLabel
        detectionMethods = Array(Set(detectionMethods).union(observation.detectionMethods)).sorted()
        rssiTrend = observation.rssiTrend
        rawEvent = observation.rawEvent
        // Clamp to prevent a future date from ever being assigned.
        // The caller should already pass a host receipt time, but this
        // defends the invariant: camera.lastSeen <= current host time.
        lastSeen = min(timestamp, Date())
        secondsSinceSeen = 0
        if rssiHistory.last?.timestamp != timestamp {
            rssiHistory.append(RSSISample(timestamp: timestamp, rssi: observation.rssi))
        }
        rssiHistory.removeAll { timestamp.timeIntervalSince($0.timestamp) > 120 }
        if rssiHistory.count > 180 {
            rssiHistory.removeFirst(rssiHistory.count - 180)
        }
    }

    mutating func refreshRelativeTime(now: Date = Date()) {
        secondsSinceSeen = max(0, Int(now.timeIntervalSince(lastSeen)))
    }
}

extension CameraDetection {
    static func makeMockDetections(now: Date = Date()) -> [CameraDetection] {
        let definitions: [(id: String, name: String, mac: String, proto: ProtocolType, channel: Int?, frequency: Int?, rssi: Int, peak: Int, average: Double, observations: Int, secondsAgo: Int)] = [
            ("18F0B279-5EF0-4E88-8369-95C78DB69B11", "Flock Safety Camera", "98:3B:16:7A:2C:1D", .wifi, 6, 2437, -51, -45, -57, 142, 4),
            ("679DD738-91C8-4F12-8A6D-97AF49292086", "Flock Safety Camera", "A4:5E:60:9B:22:7F", .wifi, 11, 2462, -67, -56, -66, 118, 8),
            ("02D9A6E5-0EB5-4468-A38C-F51333517091", "Flock Falcon LPR", "1C:6F:65:AA:11:2B", .wifi, 1, 2412, -82, -73, -81, 84, 12),
            ("9C23E62B-6B68-4B12-B051-F59314227EB7", "Flock Safety Solar", "60:38:E0:31:9A:BC", .wifi, 6, 2437, -88, -76, -84, 69, 22),
            ("B1911498-AC75-4F59-94F4-0C0E8982E1B8", "Flock Safety Camera", "78:31:CB:14:6D:2A", .wifi, 6, 2437, -71, -60, -70, 103, 27),
            ("D7D2B217-1A18-4EAB-9779-D58A941F7C24", "Flock Raven Audio", "3C:84:6A:4D:9E:10", .ble, 37, 2402, -58, -49, -59, 96, 31),
            ("96371565-9337-458D-A105-37D07B59193C", "Flock Safety Camera", "C8:7B:23:52:E9:F4", .wifi, 11, 2462, -63, -52, -64, 131, 39),
            ("D1B16D08-994B-4C72-A3D5-097579AFC9D6", "Flock Intersection Node", "B0:4A:39:7C:42:91", .wifi, 1, 2412, -76, -68, -75, 77, 45),
            ("2DE968B4-270A-4841-A8EF-543C688E533B", "Flock Safety Camera", "F4:12:FA:80:0D:33", .ble, 38, 2426, -54, -47, -55, 158, 51),
            ("6B3211C4-2897-4067-8AC7-0202AB22788B", "Flock Falcon LPR", "88:D7:F6:19:3C:5E", .wifi, 6, 2437, -69, -58, -68, 90, 64),
            ("C8C88DC9-72FB-40A7-8714-CE833BEF8FC1", "Flock Safety Camera", "04:7C:16:FA:09:EE", .ble, 39, 2480, -79, -66, -78, 61, 73),
            ("768C5541-C655-4F8F-8E4C-D0A9BA0D8204", "Flock Safety Portable", "40:91:51:21:AB:70", .wifi, 11, 2462, -56, -48, -58, 147, 81)
        ]

        return definitions.enumerated().map { index, definition in
            makeDetection(
                id: stableUUID(definition.id),
                name: definition.name,
                mac: definition.mac,
                proto: definition.proto,
                channel: definition.channel,
                frequency: definition.frequency,
                rssi: definition.rssi,
                peak: definition.peak,
                average: definition.average,
                observations: definition.observations,
                secondsAgo: definition.secondsAgo,
                firstSeenOffset: TimeInterval((index + 3) * 380),
                now: now
            )
        }
    }

    static func makeSimulatedDetection(number: Int, now: Date = Date()) -> CameraDetection {
        let suffix = String(format: "%02X", number + 30)
        return makeDetection(
            id: UUID(),
            name: "Flock Safety Camera",
            mac: "AC:27:5F:64:\(suffix):\(String(format: "%02X", number + 74))",
            proto: number.isMultiple(of: 2) ? .wifi : .ble,
            channel: number.isMultiple(of: 2) ? 6 : 37,
            frequency: number.isMultiple(of: 2) ? 2437 : 2402,
            rssi: -62,
            peak: -62,
            average: -62,
            observations: 1,
            secondsAgo: 0,
            firstSeenOffset: 0,
            now: now
        )
    }

    static func makeRandomTestDetection(sequence: Int, now: Date = Date()) -> CameraDetection {
        let names = [
            "Flock Safety Camera",
            "Flock Falcon LPR",
            "Flock Safety Portable",
            "Flock Safety Solar",
            "Flock Intersection Camera"
        ]
        let wifiChannels = [(1, 2412), (6, 2437), (11, 2462)]
        let bleChannels = [(37, 2402), (38, 2426), (39, 2480)]
        let prefixes = ["98:3B:16", "A4:5E:60", "70:C9:4E", "AC:27:5F", "C8:7B:23"]
        let protocolType: ProtocolType = Bool.random() ? .wifi : .ble
        let channelPair = protocolType == .wifi
            ? wifiChannels[Int.random(in: 0..<wifiChannels.count)]
            : bleChannels[Int.random(in: 0..<bleChannels.count)]
        let prefix = prefixes[Int.random(in: 0..<prefixes.count)]
        let rssi = Int.random(in: -86 ... -45)
        let sequenceByte = sequence & 0xFF
        let mac = String(
            format: "%@:%02X:%02X:%02X",
            prefix,
            Int.random(in: 0...255),
            sequenceByte,
            Int.random(in: 0...255)
        )

        return makeDetection(
            id: UUID(),
            name: names[Int.random(in: 0..<names.count)],
            mac: mac,
            proto: protocolType,
            channel: channelPair.0,
            frequency: channelPair.1,
            rssi: rssi,
            peak: rssi,
            average: Double(rssi),
            observations: 1,
            secondsAgo: 0,
            firstSeenOffset: 0,
            now: now
        )
    }

    private static func makeDetection(
        id: UUID,
        name: String,
        mac: String,
        proto: ProtocolType,
        channel: Int?,
        frequency: Int?,
        rssi: Int,
        peak: Int,
        average: Double,
        observations: Int,
        secondsAgo: Int,
        firstSeenOffset: TimeInterval,
        now: Date
    ) -> CameraDetection {
        let lastSeen = now.addingTimeInterval(-TimeInterval(secondsAgo))
        return CameraDetection(
            id: id,
            name: name,
            type: .camera,
            macAddress: mac,
            protocolType: proto,
            channel: channel,
            frequencyMHz: frequency,
            rssi: rssi,
            peakRSSI: peak,
            averageRSSI: average,
            observationCount: observations,
            firstSeen: now.addingTimeInterval(-firstSeenOffset),
            lastSeen: lastSeen,
            secondsSinceSeen: secondsAgo,
                marked: false,
                note: "",
                noteUpdatedAt: nil,
                rssiHistory: makeHistory(endingAt: lastSeen, currentRSSI: rssi)
        )
    }

    private static func makeHistory(endingAt endDate: Date, currentRSSI: Int) -> [RSSISample] {
        stride(from: 120, through: 0, by: -4).enumerated().map { offset, secondsBack in
            let wave = ((offset % 7) - 3)
            let microFade = ((offset % 4) - 2)
            return RSSISample(
                timestamp: endDate.addingTimeInterval(-TimeInterval(secondsBack)),
                rssi: min(-35, max(-105, currentRSSI + wave + microFade))
            )
        }
    }

    private static func stableUUID(_ string: String) -> UUID {
        UUID(uuidString: string) ?? UUID()
    }
}

struct CameraUserMetadata: Codable, Equatable, Sendable {
    var marked: Bool = false
    var note: String = ""
    var noteUpdatedAt: Date?
}
