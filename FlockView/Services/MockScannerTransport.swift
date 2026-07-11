import Foundation

final class MockScannerTransport: ScannerTransport {
    private let observationPipe = AsyncStream<ScannerObservation>.makeStream()
    private let statusPipe = AsyncStream<ScannerStatus>.makeStream()
    private let connectionPipe = AsyncStream<ScannerConnectionState>.makeStream()
    private let responsePipe = AsyncStream<ScannerCommandResponse>.makeStream()
    private let errorPipe = AsyncStream<ScannerTransportError>.makeStream()
    private let diagnosticsPipe = AsyncStream<ScannerDiagnostics>.makeStream()

    private var cameras: [CameraDetection] = []
    private var status: ScannerStatus = .test
    private var updateTask: Task<Void, Never>?
    private weak var settings: AppSettings?
    private var diagnostics = ScannerDiagnostics(connectionStateDescription: "Test Mode", firmwareVersion: "test", board: "mock")
    private var nextGeneratedCameraNumber = 100
    private var lastScheduledDetectionAt: Date?
    private var lastRSSIUpdateAt: Date?

    var observationStream: AsyncStream<ScannerObservation> { observationPipe.stream }
    var statusStream: AsyncStream<ScannerStatus> { statusPipe.stream }
    var connectionStream: AsyncStream<ScannerConnectionState> { connectionPipe.stream }
    var responseStream: AsyncStream<ScannerCommandResponse> { responsePipe.stream }
    var errorStream: AsyncStream<ScannerTransportError> { errorPipe.stream }
    var diagnosticsStream: AsyncStream<ScannerDiagnostics> { diagnosticsPipe.stream }

    init(settings: AppSettings) {
        self.settings = settings
    }

    deinit {
        updateTask?.cancel()
    }

    func availableDevices() async -> [SerialDevice] { [] }

    func connect(to device: SerialDevice) async throws {
        cameras = []
        nextGeneratedCameraNumber = 100
        lastScheduledDetectionAt = nil
        lastRSSIUpdateAt = nil
        status = .test
        connectionPipe.continuation.yield(.testMode)
        statusPipe.continuation.yield(status)
        diagnosticsPipe.continuation.yield(diagnostics)
    }

    func disconnect() async {
        try? await stopScan()
        connectionPipe.continuation.yield(.disconnected)
    }

    func startScan() async throws {
        lastScheduledDetectionAt = nil
        lastRSSIUpdateAt = nil
        status.state = "scanning"
        status.phase = "wifi"
        status.trackedDevices = cameras.count
        status.matchingDevices = cameras.count
        statusPipe.continuation.yield(status)
        let settingsSnapshot = await MainActor.run {
            (
                detectionInterval: settings?.testDetectionInterval ?? 10,
                emissionMode: settings?.testDetectionEmissionMode ?? .single,
                batchCount: settings?.testBatchCameraCount ?? 3
            )
        }
        emitScheduledDetectionsIfNeeded(
            now: Date(),
            interval: settingsSnapshot.detectionInterval,
            mode: settingsSnapshot.emissionMode,
            batchCount: settingsSnapshot.batchCount
        )
        status.trackedDevices = cameras.count
        status.matchingDevices = cameras.count
        statusPipe.continuation.yield(status)
        startUpdateLoopIfNeeded()
    }

    func stopScan() async throws {
        status.state = "stopped"
        updateTask?.cancel()
        updateTask = nil
        statusPipe.continuation.yield(status)
        responsePipe.continuation.yield(ScannerCommandResponse(command: "STOP", ok: true, message: "test stopped"))
    }

    func send(_ command: ScannerCommand) async throws {
        switch command {
        case .start:
            try await startScan()
        case .stop:
            try await stopScan()
        case .setMode(let mode):
            status.mode = mode
            statusPipe.continuation.yield(status)
        case .clear:
            resetDetections()
        default:
            break
        }
        responsePipe.continuation.yield(ScannerCommandResponse(command: command.responseCommand, ok: true, message: "test"))
    }

    private func resetDetections() {
        cameras.removeAll()
        nextGeneratedCameraNumber = 100
        lastScheduledDetectionAt = nil
        lastRSSIUpdateAt = nil
        status.trackedDevices = 0
        status.matchingDevices = 0
        statusPipe.continuation.yield(status)
    }

    private func startUpdateLoopIfNeeded() {
        guard updateTask == nil else {
            return
        }

        updateTask = Task { [weak self] in
            await self?.runUpdates()
        }
    }

    private func runUpdates() async {
        while !Task.isCancelled {
            let settingsSnapshot = await MainActor.run {
                (
                    updateSpeed: settings?.mockUpdateSpeed ?? 3,
                    pauseSimulation: settings?.pauseSimulation ?? false,
                    detectionInterval: settings?.testDetectionInterval ?? 10,
                    emissionMode: settings?.testDetectionEmissionMode ?? .single,
                    batchCount: settings?.testBatchCameraCount ?? 3
                )
            }
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            } catch {
                break
            }

            guard !Task.isCancelled, status.isScanning, !settingsSnapshot.pauseSimulation else {
                continue
            }

            let now = Date()
            let rssiUpdateSpeed = max(2, min(4, settingsSnapshot.updateSpeed))
            if lastRSSIUpdateAt == nil || now.timeIntervalSince(lastRSSIUpdateAt ?? now) >= rssiUpdateSpeed {
                lastRSSIUpdateAt = now
                for index in cameras.indices {
                    let delta = Int.random(in: -4...4)
                    let adjusted = min(-38, max(-96, cameras[index].rssi + delta))
                    cameras[index].applyRSSI(adjusted, at: now)
                    emit(camera: cameras[index], reason: "rssi-update")
                }
            }

            emitScheduledDetectionsIfNeeded(
                now: now,
                interval: settingsSnapshot.detectionInterval,
                mode: settingsSnapshot.emissionMode,
                batchCount: settingsSnapshot.batchCount
            )

            if Int.random(in: 0..<100) < 7 {
                status.droppedObservations += 1
            }

            status.uptimeMilliseconds += 1_000
            status.trackedDevices = cameras.count
            status.matchingDevices = cameras.count
            statusPipe.continuation.yield(status)
        }
    }

    private func emitScheduledDetectionsIfNeeded(
        now: Date,
        interval: Double,
        mode: TestDetectionEmissionMode,
        batchCount: Int
    ) {
        let clampedInterval = max(3, min(60, interval))
        if let previous = lastScheduledDetectionAt {
            guard now.timeIntervalSince(previous) >= clampedInterval else {
                return
            }
        }

        lastScheduledDetectionAt = now
        let newCameraCount = mode == .multiple ? max(2, min(8, batchCount)) : 1
        for _ in 0..<newCameraCount {
            let camera = makeUniqueRandomTestDetection(now: now)
            cameras.insert(camera, at: 0)
            emit(camera: camera, reason: mode == .multiple ? "scheduled-batch-test-detection" : "scheduled-test-detection")
        }
    }

    private func makeUniqueRandomTestDetection(now: Date) -> CameraDetection {
        for _ in 0..<10 {
            nextGeneratedCameraNumber += 1
            let camera = CameraDetection.makeRandomTestDetection(sequence: nextGeneratedCameraNumber, now: now)
            if !cameras.contains(where: { $0.macAddress.caseInsensitiveCompare(camera.macAddress) == .orderedSame }) {
                return camera
            }
        }

        nextGeneratedCameraNumber += 1
        return CameraDetection.makeRandomTestDetection(sequence: nextGeneratedCameraNumber, now: now)
    }

    private func emit(camera: CameraDetection, reason: String) {
        let rawEvent = Self.rawEvent(reason: reason, camera: camera)
        let observation = ScannerObservation(
            protocolType: camera.protocolType,
            deviceID: camera.deviceID.isEmpty ? "\(camera.protocolType.normalizedID):\(camera.macAddress)" : camera.deviceID,
            macAddress: camera.macAddress,
            name: camera.name,
            channel: camera.channel,
            frequencyMHz: camera.frequencyMHz,
            rssi: camera.rssi,
            smoothedRSSI: Double(camera.rssi),
            peakRSSI: camera.peakRSSI,
            averageRSSI: camera.averageRSSI,
            proximity: camera.proximity(),
            confidence: 80,
            confidenceLabel: .high,
            detectionMethods: ["test", reason],
            observationCount: UInt64(camera.observationCount),
            uptimeMilliseconds: status.uptimeMilliseconds,
            rawEvent: rawEvent
        )
        observationPipe.continuation.yield(observation)
    }

    private static func rawEvent(reason: String, camera: CameraDetection) -> String {
        """
        {"schema_version":1,"event":"detection","source":"test","reason":"\(reason)","vendor":"Flock Safety","device_type":"camera","protocol":"\(camera.protocolType.normalizedID)","device_id":"\(camera.protocolType.normalizedID):\(camera.macAddress)","mac_address":"\(camera.macAddress)","name":"\(camera.name)","channel":\(camera.channel ?? 0),"frequency_mhz":\(camera.frequencyMHz ?? 0),"rssi":\(camera.rssi),"confidence":80,"confidence_label":"HIGH","detection_methods":["test"],"observation_count":\(camera.observationCount),"uptime_ms":0}
        """
    }
}
