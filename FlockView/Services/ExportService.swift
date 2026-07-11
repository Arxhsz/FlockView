import AppKit
import Foundation
import UniformTypeIdentifiers

enum ExportFormat {
    case json
    case csv

    var fileExtension: String {
        switch self {
        case .json:
            "json"
        case .csv:
            "csv"
        }
    }

    var contentType: UTType {
        switch self {
        case .json:
            .json
        case .csv:
            .commaSeparatedText
        }
    }
}

struct ExportSessionMetadata: Codable {
    var dataSource: SessionDataSource
    var firmwareVersion: String?
    var connectedDevice: SerialDevice?
    var appVersion: String
    var sessionStart: Date
    var sessionEnd: Date
    var scannerMode: String
    var wifiChannel: String
    var bleState: String
}

private struct ExportPayload: Codable {
    var metadata: ExportSessionMetadata
    var cameras: [CameraDetection]
}

final class ExportService {
    @MainActor
    func export(cameras: [CameraDetection], metadata: ExportSessionMetadata, format: ExportFormat) async throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export FlockView Session"
        panel.canCreateDirectories = true
        let source = metadata.dataSource.rawValue.capitalized
        panel.nameFieldStringValue = "FlockView-\(source)-Session.\(format.fileExtension)"
        panel.allowedContentTypes = [format.contentType]

        let response = await panel.beginAsync()
        guard response == .OK, let url = panel.url else {
            return nil
        }

        let data: Data
        switch format {
        case .json:
            data = try Self.makeJSONData(cameras: cameras, metadata: metadata)
        case .csv:
            data = Self.makeCSVData(cameras: cameras, metadata: metadata)
        }

        try data.write(to: url, options: .atomic)
        return url
    }

    static func makeJSONData(cameras: [CameraDetection], metadata: ExportSessionMetadata) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(ExportPayload(metadata: metadata, cameras: cameras))
    }

    static func makeCSVData(cameras: [CameraDetection], metadata: ExportSessionMetadata) -> Data {
        let formatter = ISO8601DateFormatter()
        let rows = cameras.map { camera in
            [
                metadata.dataSource.rawValue,
                metadata.firmwareVersion ?? "",
                metadata.connectedDevice?.displayName ?? "",
                metadata.connectedDevice?.path ?? "",
                metadata.scannerMode,
                metadata.wifiChannel,
                metadata.bleState,
                camera.name,
                camera.type.rawValue,
                camera.macAddress,
                camera.protocolType.rawValue,
                camera.channel.map(String.init) ?? "",
                camera.frequencyMHz.map(String.init) ?? "",
                String(camera.rssi),
                String(camera.peakRSSI),
                String(format: "%.1f", camera.averageRSSI),
                String(camera.observationCount),
                formatter.string(from: camera.firstSeen),
                formatter.string(from: camera.lastSeen),
                String(camera.marked),
                camera.note
            ].map(Self.csvEscape).joined(separator: ",")
        }

        let header = [
            "Data Source",
            "Firmware Version",
            "Serial Device",
            "Serial Path",
            "Scanner Mode",
            "Wi-Fi Channel",
            "BLE State",
            "Name",
            "Type",
            "MAC Address",
            "Protocol",
            "Channel",
            "Frequency MHz",
            "RSSI",
            "Peak RSSI",
            "Average RSSI",
            "Observation Count",
            "First Seen",
            "Last Seen",
            "Marked",
            "Note"
        ].joined(separator: ",")

        let metadataRows = [
            "# FlockView export",
            "# App Version,\(Self.csvEscape(metadata.appVersion))",
            "# Session Start,\(Self.csvEscape(formatter.string(from: metadata.sessionStart)))",
            "# Session End,\(Self.csvEscape(formatter.string(from: metadata.sessionEnd)))"
        ]

        return (metadataRows + [header] + rows).joined(separator: "\n").data(using: .utf8) ?? Data()
    }

    private static func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\n") || escaped.contains("\"") {
            return "\"\(escaped)\""
        }

        return escaped
    }
}

private extension NSSavePanel {
    func beginAsync() async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            begin { response in
                continuation.resume(returning: response)
            }
        }
    }
}
