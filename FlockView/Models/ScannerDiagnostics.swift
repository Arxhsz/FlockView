import Foundation

struct ScannerDiagnostics: Equatable, Sendable {
    var connectionStateDescription: String = "Disconnected"
    var selectedDevice: SerialDevice?
    var baudRate: Int = 115200
    var firmwareVersion: String?
    var board: String?
    var schemaVersion: Int?
    var lastValidEventDate: Date?
    var validJSONLineCount: Int = 0
    var malformedLineCount: Int = 0
    var unknownEventCount: Int = 0
    var commandCount: Int = 0
    var commandTimeoutCount: Int = 0
    var bytesReceived: UInt64 = 0
    var reconnectAttempts: Int = 0
    var queueDepth: Int = 0
    var droppedFirmwareObservations: UInt64 = 0
    var freeHeap: Int?
    var recentEvents: [DiagnosticEvent] = []

    mutating func append(_ event: DiagnosticEvent) {
        recentEvents.append(event)
        if recentEvents.count > 100 {
            recentEvents.removeFirst(recentEvents.count - 100)
        }
    }
}

struct DiagnosticEvent: Identifiable, Equatable, Sendable {
    let id = UUID()
    var date: Date
    var kind: String
    var summary: String
    var raw: String?
}
