import Foundation

enum ScannerEventType: String, Decodable, Sendable {
    case boot
    case detection
    case scannerStatus = "scanner_status"
    case commandResponse = "command_response"
    case error
    case debug
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = ScannerEventType(rawValue: try container.decode(String.self)) ?? .unknown
    }
}

struct ScannerEventEnvelope: Decodable, Sendable {
    var schemaVersion: Int
    var event: ScannerEventType

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case event
    }
}

struct ScannerBootEvent: Decodable, Equatable, Sendable {
    var schemaVersion: Int
    var event: String
    var firmware: String
    var firmwareVersion: String
    var board: String
    var passiveOnly: Bool
    var wifiBands: [String]
    var bleSupported: Bool
    var uptimeMilliseconds: UInt64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case event
        case firmware
        case firmwareVersion = "firmware_version"
        case board
        case passiveOnly = "passive_only"
        case wifiBands = "wifi_bands"
        case bleSupported = "ble_supported"
        case uptimeMilliseconds = "uptime_ms"
    }

    var capabilities: ScannerCapabilities {
        ScannerCapabilities(
            firmware: firmware,
            firmwareVersion: firmwareVersion,
            board: board,
            passiveOnly: passiveOnly,
            wifiBands: wifiBands,
            bleSupported: bleSupported
        )
    }
}

struct ScannerFirmwareErrorEvent: Decodable, Equatable, Sendable {
    var schemaVersion: Int
    var event: String
    var component: String
    var code: String
    var message: String
    var uptimeMilliseconds: UInt64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case event
        case component
        case code
        case message
        case uptimeMilliseconds = "uptime_ms"
    }
}

struct ScannerDebugEvent: Decodable, Equatable, Sendable {
    var schemaVersion: Int
    var event: String
    var component: String
    var message: String
    var uptimeMilliseconds: UInt64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case event
        case component
        case message
        case uptimeMilliseconds = "uptime_ms"
    }
}

enum ScannerDecodedEvent: Sendable {
    case boot(ScannerBootEvent, raw: String)
    case detection(ScannerObservation)
    case status(ScannerStatus, raw: String)
    case commandResponse(ScannerCommandResponse, raw: String)
    case firmwareError(ScannerFirmwareErrorEvent, raw: String)
    case debug(ScannerDebugEvent, raw: String)
    case unknown(event: String, raw: String)
}

struct ScannerEventDecoder {
    private let jsonDecoder = JSONDecoder()

    func decode(line: String) throws -> ScannerDecodedEvent {
        guard let data = line.data(using: .utf8) else {
            throw ScannerTransportError.malformedJSON(line)
        }

        let envelope = try jsonDecoder.decode(ScannerEventEnvelope.self, from: data)
        switch envelope.event {
        case .boot:
            return .boot(try jsonDecoder.decode(ScannerBootEvent.self, from: data), raw: line)
        case .detection:
            var observation = try jsonDecoder.decode(ScannerObservation.self, from: data)
            observation.rawEvent = line
            return .detection(observation)
        case .scannerStatus:
            return .status(try jsonDecoder.decode(ScannerStatus.self, from: data), raw: line)
        case .commandResponse:
            return .commandResponse(try jsonDecoder.decode(ScannerCommandResponse.self, from: data), raw: line)
        case .error:
            return .firmwareError(try jsonDecoder.decode(ScannerFirmwareErrorEvent.self, from: data), raw: line)
        case .debug:
            return .debug(try jsonDecoder.decode(ScannerDebugEvent.self, from: data), raw: line)
        case .unknown:
            return .unknown(event: "unknown", raw: line)
        }
    }
}
