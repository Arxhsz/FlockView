import Foundation

final class RecordedScannerTransport: ScannerTransport {
    private let observationPipe = AsyncStream<ScannerObservation>.makeStream()
    private let statusPipe = AsyncStream<ScannerStatus>.makeStream()
    private let connectionPipe = AsyncStream<ScannerConnectionState>.makeStream()
    private let responsePipe = AsyncStream<ScannerCommandResponse>.makeStream()
    private let errorPipe = AsyncStream<ScannerTransportError>.makeStream()
    private let diagnosticsPipe = AsyncStream<ScannerDiagnostics>.makeStream()
    private let decoder = ScannerEventDecoder()
    private var replayTask: Task<Void, Never>?
    private var isRunning = false

    var observationStream: AsyncStream<ScannerObservation> { observationPipe.stream }
    var statusStream: AsyncStream<ScannerStatus> { statusPipe.stream }
    var connectionStream: AsyncStream<ScannerConnectionState> { connectionPipe.stream }
    var responseStream: AsyncStream<ScannerCommandResponse> { responsePipe.stream }
    var errorStream: AsyncStream<ScannerTransportError> { errorPipe.stream }
    var diagnosticsStream: AsyncStream<ScannerDiagnostics> { diagnosticsPipe.stream }

    deinit {
        replayTask?.cancel()
    }

    func availableDevices() async -> [SerialDevice] { [] }

    func connect(to device: SerialDevice) async throws {
        connectionPipe.continuation.yield(.recordedMode)
        statusPipe.continuation.yield(.test)
    }

    func disconnect() async {
        replayTask?.cancel()
        replayTask = nil
        isRunning = false
        connectionPipe.continuation.yield(.disconnected)
    }

    func startScan() async throws {
        isRunning = true
        replayTask?.cancel()
        replayTask = Task { [weak self] in
            await self?.replay()
        }
    }

    func stopScan() async throws {
        isRunning = false
        replayTask?.cancel()
        replayTask = nil
    }

    func send(_ command: ScannerCommand) async throws {
        let response = ScannerCommandResponse(command: command.responseCommand, ok: true, message: "recorded")
        responsePipe.continuation.yield(response)
    }

    private func replay() async {
        let lines = Self.fixtureLines
        while isRunning && !Task.isCancelled {
            for line in lines {
                guard isRunning, !Task.isCancelled else { return }
                do {
                    switch try decoder.decode(line: line) {
                    case .detection(let observation):
                        observationPipe.continuation.yield(observation)
                    case .status(let status, _):
                        statusPipe.continuation.yield(status)
                    case .commandResponse(let response, _):
                        responsePipe.continuation.yield(response)
                    default:
                        break
                    }
                } catch {
                    errorPipe.continuation.yield(.malformedJSON(line))
                }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }

    private static let fixtureLines = [
        #"{"schema_version":1,"event":"scanner_status","state":"scanning","mode":"dual","phase":"wifi","wifi_channel":6,"wifi_frames_seen":15420,"ble_advertisements_seen":942,"queue_depth":3,"queue_high_watermark":18,"dropped_observations":0,"tracked_devices":16,"matching_devices":3,"free_heap":161240,"uptime_ms":184392}"#,
        #"{"schema_version":1,"event":"detection","vendor":"Flock Safety","device_type":"camera","protocol":"wifi","device_id":"wifi:70:C9:4E:12:34:56","mac_address":"70:C9:4E:12:34:56","bssid":"11:22:33:44:55:66","ssid":"","frame_subtype":"probe_request","channel":6,"frequency_mhz":2437,"rssi":-61,"smoothed_rssi":-63.4,"peak_rssi":-55,"average_rssi":-66.2,"proximity":"medium","rssi_trend":"rising","confidence":80,"confidence_label":"HIGH","detection_methods":["known_wifi_oui","wifi_wildcard_probe","multiple_signals"],"observation_count":14,"first_seen_ms":12420,"last_seen_ms":184392,"uptime_ms":184392}"#
    ]
}
