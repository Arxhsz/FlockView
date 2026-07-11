import Foundation

enum ScannerTransportError: LocalizedError, Equatable, Sendable {
    case noDeviceSelected
    case deviceUnavailable
    case permissionDenied
    case openFailed(String)
    case configureFailed(String)
    case handshakeTimeout
    case incompatibleFirmware(String)
    case connectionLost
    case writeFailed(String)
    case malformedJSON(String)
    case oversizedSerialLine
    case commandTimeout(String)
    case commandRejected(String)

    var errorDescription: String? {
        switch self {
        case .noDeviceSelected:
            "No serial device selected."
        case .deviceUnavailable:
            "The selected serial device is unavailable."
        case .permissionDenied:
            "FlockView does not have permission to open this serial device."
        case .openFailed(let message):
            "Unable to open serial device: \(message)"
        case .configureFailed(let message):
            "Unable to configure serial device: \(message)"
        case .handshakeTimeout:
            "Serial device found, but it is not responding as FlockViewScanner."
        case .incompatibleFirmware(let message):
            "Incompatible scanner firmware: \(message)"
        case .connectionLost:
            "The scanner connection was lost."
        case .writeFailed(let message):
            "Unable to write to scanner: \(message)"
        case .malformedJSON(let line):
            "Malformed scanner JSON: \(line)"
        case .oversizedSerialLine:
            "Scanner emitted an oversized serial line."
        case .commandTimeout(let command):
            "Scanner command timed out: \(command)"
        case .commandRejected(let message):
            "Scanner rejected command: \(message)"
        }
    }
}

protocol ScannerTransport: AnyObject {
    var observationStream: AsyncStream<ScannerObservation> { get }
    var statusStream: AsyncStream<ScannerStatus> { get }
    var connectionStream: AsyncStream<ScannerConnectionState> { get }
    var responseStream: AsyncStream<ScannerCommandResponse> { get }
    var errorStream: AsyncStream<ScannerTransportError> { get }
    var diagnosticsStream: AsyncStream<ScannerDiagnostics> { get }

    func availableDevices() async -> [SerialDevice]
    func connect(to device: SerialDevice) async throws
    func disconnect() async
    func startScan() async throws
    func stopScan() async throws
    func send(_ command: ScannerCommand) async throws
}

enum ScannerCommand: Equatable, Sendable {
    case ping
    case status
    case start
    case stop
    case clear
    case setMode(ScanMode)
    case setWiFiDwell(milliseconds: Int)
    case setBLEWindow(milliseconds: Int)
    case setMinimumRSSI(Int)
    case setDebug(Bool)

    var serialString: String {
        switch self {
        case .ping:
            "PING\n"
        case .status:
            "STATUS\n"
        case .start:
            "START\n"
        case .stop:
            "STOP\n"
        case .clear:
            "CLEAR\n"
        case .setMode(let mode):
            "MODE \(mode.commandValue)\n"
        case .setWiFiDwell(let milliseconds):
            "SET WIFI DWELL \(milliseconds)\n"
        case .setBLEWindow(let milliseconds):
            "SET BLE WINDOW \(milliseconds)\n"
        case .setMinimumRSSI(let value):
            "SET RSSI MIN \(value)\n"
        case .setDebug(let enabled):
            "SET DEBUG \(enabled ? "ON" : "OFF")\n"
        }
    }

    var responseCommand: String {
        switch self {
        case .setWiFiDwell:
            "SET WIFI DWELL"
        case .setBLEWindow:
            "SET BLE WINDOW"
        case .setMinimumRSSI:
            "SET RSSI MIN"
        default:
            serialString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

struct ScannerCommandResponse: Decodable, Equatable, Sendable {
    var schemaVersion: Int
    var event: String
    var command: String
    var ok: Bool
    var message: String
    var uptimeMilliseconds: UInt64

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case event
        case command
        case ok
        case success
        case message
        case uptimeMilliseconds = "uptime_ms"
    }

    init(schemaVersion: Int = 1, event: String = "command_response", command: String, ok: Bool, message: String, uptimeMilliseconds: UInt64 = 0) {
        self.schemaVersion = schemaVersion
        self.event = event
        self.command = command
        self.ok = ok
        self.message = message
        self.uptimeMilliseconds = uptimeMilliseconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        event = try container.decode(String.self, forKey: .event)
        command = try container.decode(String.self, forKey: .command)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
            ?? container.decodeIfPresent(Bool.self, forKey: .success)
            ?? false
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        uptimeMilliseconds = try container.decodeIfPresent(UInt64.self, forKey: .uptimeMilliseconds) ?? 0
    }
}

struct PendingScannerCommand: Identifiable, Sendable {
    var id = UUID()
    var command: ScannerCommand
    var sentAt: Date
    var timeout: Duration
}
