import Combine
import Foundation

enum CameraSortOption: String, CaseIterable, Identifiable {
    case lastDetected = "Last Detected"
    case signalStrength = "Signal Strength"
    case closest = "Closest"
    case farthest = "Farthest"
    case name = "Name"
    case observationCount = "Observation Count"

    var id: String { rawValue }
}

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    var text: String
    var symbolName: String
}

struct RawEvent: Identifiable {
    let id = UUID()
    var cameraName: String
    var text: String
}

@MainActor
final class ScannerViewModel: ObservableObject {
    @Published var cameras: [CameraDetection] = []
    @Published var status: ScannerStatus = .disconnected
    @Published var connectionState: ScannerConnectionState = .disconnected
    @Published var scannerSource: ScannerSource
    @Published var availableSerialDevices: [SerialDevice] = []
    @Published var selectedSerialDevice: SerialDevice?
    @Published var lastConnectionError: String?
    @Published var diagnostics = ScannerDiagnostics()
    @Published var searchText: String = ""
    @Published var sortOption: CameraSortOption = .lastDetected
    @Published var selectedCameraID: CameraDetection.ID?
    @Published var isInspectorVisible: Bool = true
    @Published var isDetailSheetPresented: Bool = false
    @Published var isDiagnosticsPresented: Bool = false
    @Published var toast: ToastMessage?
    @Published var rawEvent: RawEvent?
    @Published private(set) var sessionDuration: TimeInterval = 0
    @Published private(set) var scanControlState: ScanControlState = .stopped

    private let settings: AppSettings
    private let exportService: ExportService
    private let clipboardService: ClipboardService
    private let hardwareTransport = SerialScannerTransport()
    private let nativeMacTransport = NativeMacScannerTransport()
    private lazy var mockTransport = MockScannerTransport(settings: settings)
    private lazy var recordedTransport = RecordedScannerTransport()
    private let persistence = ConnectionPersistenceService()

    private var transport: ScannerTransport
    private var observationTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var responseTask: Task<Void, Never>?
    private var errorTask: Task<Void, Never>?
    private var diagnosticsTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var streamGeneration = 0
    private var accumulatedSessionDuration: TimeInterval = 0
    private var lastScanStartDate: Date?
    private var hiddenCameraIDs = Set<UUID>()
    private var deviceIDToCameraID: [String: UUID] = [:]
    private var lastRawEvents: [UUID: String] = [:]
    private var hostConnectionDate: Date?
    private var firmwareUptimeAtConnection: UInt64?
    private var lastSeenFirmwareUptime: UInt64?
    private var sessionSource: SessionDataSource
    private var sessionStartedAt = Date()
    private var sessionDetections: [UUID: CameraDetection] = [:]
    private var userMetadata: [String: CameraUserMetadata] = [:]
    private var wasConnectionEstablished = false
    private var acceptsLiveDetections = true
    private var lastToastSignature: String?

    init(
        transport: ScannerTransport? = nil,
        settings: AppSettings,
        exportService: ExportService = ExportService(),
        clipboardService: ClipboardService = ClipboardService()
    ) {
        self.settings = settings
        self.exportService = exportService
        self.clipboardService = clipboardService
        scannerSource = settings.scannerSource
        sessionSource = settings.scannerSource.sessionDataSource
        self.transport = transport ?? hardwareTransport
        startStreamTasks(for: self.transport)
        startClock()

        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    deinit {
        observationTask?.cancel()
        statusTask?.cancel()
        connectionTask?.cancel()
        responseTask?.cancel()
        errorTask?.cancel()
        diagnosticsTask?.cancel()
        clockTask?.cancel()
        toastTask?.cancel()
        reconnectTask?.cancel()
    }

    var visibleCameras: [CameraDetection] {
        sortedCameras(from: cameras.filter { camera in
            !hiddenCameraIDs.contains(camera.id) && matchesSearch(camera)
        })
    }

    var totalVisibleCameraCount: Int {
        cameras.count
    }

    var activeCameraCount: Int {
        visibleCameras.count
    }

    var exportCameras: [CameraDetection] {
        var merged = sessionDetections
        for camera in cameras {
            merged[camera.id] = camera
        }
        return sortedCameras(from: Array(merged.values))
    }

    var selectedCamera: CameraDetection? {
        guard let selectedCameraID else {
            return nil
        }
        return cameras.first { $0.id == selectedCameraID && !hiddenCameraIDs.contains($0.id) }
    }

    var formattedSessionDuration: String {
        Self.durationFormatter.string(from: sessionDuration) ?? "00:00:00"
    }

    var sessionSourceLabel: String {
        switch sessionSource {
        case .hardware:
            "LIVE HARDWARE"
        case .macNative:
            "MAC SCANNER"
        case .test:
            "TEST DATA"
        case .recorded:
            "RECORDED DATA"
        }
    }

    var canUseHardwareChannelMenu: Bool {
        scannerSource != .hardware && scannerSource != .macNative
    }

    func bootstrap() async {
        await refreshDevices()
        guard scannerSource == .hardware else {
            await switchSource(scannerSource)
            return
        }

        connectionState = availableSerialDevices.isEmpty ? .disconnected : .discovering
        status = .disconnected
        guard settings.autoReconnect else {
            return
        }

        if let saved = persistence.loadDevice(), let match = matchSavedDevice(saved) {
            await connectToDevice(match)
        } else if let likely = availableSerialDevices.first(where: \.isLikelyESP32) {
            await connectToDevice(likely)
        }
    }

    func refreshDevices() async {
        availableSerialDevices = await hardwareTransport.availableDevices()
        selectedSerialDevice = Self.resolvedHardwareSelection(
            current: selectedSerialDevice,
            availableDevices: availableSerialDevices
        )
    }

    nonisolated static func resolvedHardwareSelection(
        current: SerialDevice?,
        availableDevices: [SerialDevice]
    ) -> SerialDevice? {
        if
            let current,
            current.isHardwareSerialPort,
            availableDevices.contains(where: { $0.matchesHardwareIdentity(of: current) })
        {
            return current
        }

        return availableDevices.first(where: \.isLikelyESP32) ?? availableDevices.first
    }

    func select(_ camera: CameraDetection) {
        selectedCameraID = camera.id
        isInspectorVisible = true
    }

    func switchSource(_ source: ScannerSource) async {
        guard scannerSource != source || source != .hardware else {
            return
        }

        let previousTransport = transport
        stopStreamTasks()
        reconnectTask?.cancel()
        await previousTransport.disconnect()
        scannerSource = source
        settings.scannerSource = source
        sessionSource = source.sessionDataSource
        clearSessionLocally()

        switch source {
        case .hardware:
            transport = hardwareTransport
            acceptsLiveDetections = false
            status = .disconnected
            connectionState = .disconnected
            resetDiagnosticsForSource(.hardware, selectedDevice: selectedSerialDevice)
            startStreamTasks(for: transport)
            await refreshDevices()
            resetDiagnosticsForSource(.hardware, selectedDevice: selectedSerialDevice)
            if let device = selectedSerialDevice {
                await connectToDevice(device)
            }
        case .macNative:
            transport = nativeMacTransport
            acceptsLiveDetections = false
            status = .disconnected
            connectionState = .disconnected
            resetDiagnosticsForSource(.macNative, selectedDevice: .nativeMacScanner)
            startStreamTasks(for: transport)
            do {
                try await transport.connect(to: .nativeMacScanner)
                showToast("Mac Scanner ready", symbolName: "macbook.and.iphone")
            } catch {
                lastConnectionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                connectionState = .failed(message: lastConnectionError ?? "Mac Scanner unavailable")
                showToast(lastConnectionError ?? "Mac Scanner unavailable", symbolName: "exclamationmark.triangle")
            }
        case .test:
            transport = mockTransport
            acceptsLiveDetections = true
            startStreamTasks(for: transport)
            do {
                try await transport.connect(to: .testDevice)
                try await transport.startScan()
                showToast("Test Mode active", symbolName: "play.rectangle")
            } catch {
                showToast("Unable to start Test Mode", symbolName: "exclamationmark.triangle")
            }
        case .recorded:
            transport = recordedTransport
            startStreamTasks(for: transport)
            do {
                try await transport.connect(to: .recordedDevice)
                try await transport.startScan()
                showToast("Recorded playback active", symbolName: "recordingtape")
            } catch {
                showToast("Unable to start playback", symbolName: "exclamationmark.triangle")
            }
        }
    }

    func connectToDevice(_ device: SerialDevice, isAutoReconnect: Bool = false) async {
        await switchToHardwareTransportIfNeeded()

        let targetDevice: SerialDevice
        if device.isHardwareSerialPort {
            targetDevice = device
        } else {
            await refreshDevices()
            guard let replacement = selectedSerialDevice, replacement.isHardwareSerialPort else {
                lastConnectionError = "Select an ESP32 serial device before connecting."
                connectionState = .failed(message: lastConnectionError ?? "Connection failed")
                if !isAutoReconnect {
                    showToast(lastConnectionError ?? "Connection failed", symbolName: "exclamationmark.triangle")
                }
                return
            }
            targetDevice = replacement
        }

        selectedSerialDevice = targetDevice
        lastConnectionError = nil
        do {
            try await hardwareTransport.connect(to: targetDevice)
            persistence.save(device: targetDevice)
            resetUptimeMapping()
        } catch {
            lastConnectionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            connectionState = .failed(message: lastConnectionError ?? "Connection failed")
            if !isAutoReconnect {
                showToast(lastConnectionError ?? "Connection failed", symbolName: "exclamationmark.triangle")
            }
        }
    }

    func disconnectHardware() async {
        if scannerSource == .macNative {
            await disconnectCurrentScanner()
            return
        }
        reconnectTask?.cancel()
        await hardwareTransport.disconnect()
        connectionState = .disconnected
        status = .disconnected
        stopSessionClock()
    }

    func reconnectHardware() async {
        if scannerSource == .macNative {
            await reconnectCurrentScanner()
            return
        }
        if let selectedSerialDevice {
            await connectToDevice(selectedSerialDevice)
        } else {
            await refreshDevices()
            if let device = availableSerialDevices.first {
                await connectToDevice(device)
            }
        }
    }

    func toggleScan() async {
        guard !scanControlState.isBusy else {
            return
        }

        if status.isScanning || scanControlState == .scanning {
            scanControlState = .stopping
            do {
                try await transport.stopScan()
                acceptsLiveDetections = false
                stopSessionClock()
                scanControlState = .stopped
                showToastOnce("Scan stopped", symbolName: "stop.fill")
            } catch {
                if status.isScanning {
                    scanControlState = .scanning
                    showToastOnce("Unable to stop scan", symbolName: "exclamationmark.triangle")
                } else {
                    acceptsLiveDetections = false
                    stopSessionClock()
                    scanControlState = .stopped
                    showToastOnce("Scan stopped", symbolName: "stop.fill")
                }
            }
        } else {
            scanControlState = .starting
            do {
                try await transport.startScan()
                acceptsLiveDetections = true
                startSessionClock()
                scanControlState = .scanning
                showToastOnce("Scan started", symbolName: "play.fill")
            } catch {
                if status.isScanning {
                    acceptsLiveDetections = true
                    startSessionClock()
                    scanControlState = .scanning
                } else {
                    scanControlState = .failed("Unable to start scan")
                    showToastOnce("Unable to start scan", symbolName: "exclamationmark.triangle")
                }
            }
        }
    }

    func setScanMode(_ mode: ScanMode) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await transport.send(.setMode(mode))
                status.mode = mode
                showToast("Scan mode: \(mode.displayValue)", symbolName: "antenna.radiowaves.left.and.right")
            } catch {
                showToast("Mode rejected", symbolName: "exclamationmark.triangle")
            }
        }
    }

    func setWiFiChannel(_ channel: WiFiChannelSetting) {
        guard scannerSource != .hardware else {
            showToast("Hardware scanner uses channel hopping", symbolName: "wifi")
            return
        }
        guard scannerSource != .macNative else {
            showToast("Mac Scanner uses CoreWLAN scans", symbolName: "wifi")
            return
        }

        switch channel {
        case .channel1:
            status.wifiChannel = 1
        case .channel6:
            status.wifiChannel = 6
        case .channel11:
            status.wifiChannel = 11
        case .autoHop:
            status.wifiChannel = nil
        }
    }

    func setBLEScanState(_ state: BLEScanState) {
        guard scannerSource != .hardware else {
            showToast("BLE state follows firmware phase", symbolName: "wave.3.right")
            return
        }
        guard scannerSource != .macNative else {
            showToast("BLE state follows Mac Scanner mode", symbolName: "wave.3.right")
            return
        }
        status.phase = state == .active ? "ble" : nil
    }

    func disconnectCurrentScanner() async {
        reconnectTask?.cancel()
        await transport.disconnect()
        connectionState = .disconnected
        status = .disconnected
        stopSessionClock()
    }

    func reconnectCurrentScanner() async {
        switch scannerSource {
        case .hardware:
            await reconnectHardware()
        case .macNative:
            do {
                try await nativeMacTransport.connect(to: .nativeMacScanner)
                connectionState = .connected(.nativeMacScanner, connectionState.capabilities ?? ScannerCapabilities(
                    firmware: "FlockViewMacScanner",
                    firmwareVersion: "macOS-native",
                    board: ProcessInfo.processInfo.operatingSystemVersionString,
                    passiveOnly: false,
                    wifiBands: ["2.4GHz", "5GHz", "6GHz"],
                    bleSupported: true
                ))
            } catch {
                lastConnectionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                connectionState = .failed(message: lastConnectionError ?? "Mac Scanner unavailable")
            }
        case .test, .recorded:
            await switchSource(scannerSource)
        }
    }

    func toggleInspector() {
        isInspectorVisible.toggle()
        isDetailSheetPresented = isInspectorVisible && isDetailSheetPresented
    }

    func toggleMarked(cameraID: UUID) {
        guard let index = cameras.firstIndex(where: { $0.id == cameraID }) else {
            return
        }

        cameras[index].marked.toggle()
        persistMetadata(for: cameras[index])
        showToastOnce(cameras[index].marked ? "Camera marked" : "Camera unmarked", symbolName: cameras[index].marked ? "star.fill" : "star")
    }

    func saveNote(cameraID: UUID, note: String) {
        guard let index = cameras.firstIndex(where: { $0.id == cameraID }) else {
            return
        }

        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        cameras[index].note = trimmed
        cameras[index].noteUpdatedAt = trimmed.isEmpty ? nil : Date()
        persistMetadata(for: cameras[index])
        showToastOnce("Note saved", symbolName: "note.text")
    }

    func copyMACAddress(for camera: CameraDetection) {
        clipboardService.copy(camera.macAddress)
        showToast("MAC address copied", symbolName: "doc.on.doc")
    }

    func copyCameraDetails(for camera: CameraDetection) {
        clipboardService.copy(camera.exportSummary)
        showToast("Camera details copied", symbolName: "doc.on.doc")
    }

    func presentRawEvent(for camera: CameraDetection) {
        rawEvent = RawEvent(
            cameraName: camera.name,
            text: prettyPrintedJSON(lastRawEvents[camera.id] ?? camera.rawEvent)
        )
    }

    func removeFromCurrentView(_ camera: CameraDetection) {
        hiddenCameraIDs.insert(camera.id)
        if selectedCameraID == camera.id {
            selectedCameraID = visibleCameras.first?.id
        }
        showToast("Camera hidden from current view", symbolName: "eye.slash")
    }

    func clearSession() async {
        do {
            try await transport.send(.clear)
        } catch {
            if scannerSource == .hardware {
                showToast("Firmware clear failed", symbolName: "exclamationmark.triangle")
            }
        }
        clearSessionLocally()
        showToast("Current session cleared", symbolName: "trash")
    }

    func resetTestData() async {
        guard scannerSource == .test else {
            showToast("Enable Test Mode in Settings first", symbolName: "slider.horizontal.3")
            return
        }

        do {
            try await transport.send(.clear)
            clearSessionLocally()
            try await transport.startScan()
            acceptsLiveDetections = true
            startSessionClock()
            scanControlState = .scanning
            showToast("Test data reset", symbolName: "arrow.clockwise")
        } catch {
            showToast("Unable to reset Test Mode", symbolName: "exclamationmark.triangle")
        }
    }

    func simulateDetection() {
        guard scannerSource == .test else {
            showToast("Simulated detections are Test Mode only", symbolName: "plus.circle")
            return
        }

        let camera = CameraDetection.makeRandomTestDetection(sequence: cameras.count + Int(Date().timeIntervalSince1970))
        let raw = camera.rawEvent.isEmpty ? Self.rawEvent(for: camera) : camera.rawEvent
        let observation = ScannerObservation(
            protocolType: camera.protocolType,
            deviceID: "\(camera.protocolType.normalizedID):\(camera.macAddress)",
            macAddress: camera.macAddress,
            name: camera.name,
            channel: camera.channel,
            frequencyMHz: camera.frequencyMHz,
            rssi: camera.rssi,
            confidence: 70,
            confidenceLabel: .high,
            detectionMethods: ["manual_test"],
            rawEvent: raw
        )
        handle(observation)
        showToast("Test detection added", symbolName: "plus.circle")
    }

    func exportJSON() async {
        await export(format: .json)
    }

    func exportCSV() async {
        await export(format: .csv)
    }

    func sendPing() {
        Task {
            do {
                try await transport.send(.ping)
                diagnostics.append(DiagnosticEvent(date: Date(), kind: "ping_success", summary: "manual ping", raw: nil))
            } catch {
                diagnostics.append(DiagnosticEvent(date: Date(), kind: "ping_failed", summary: error.localizedDescription, raw: nil))
            }
        }
    }

    func requestStatus() {
        Task {
            do {
                try await transport.send(.status)
            } catch {
                diagnostics.append(DiagnosticEvent(date: Date(), kind: "status_failed", summary: error.localizedDescription, raw: nil))
            }
        }
    }

    func copyDiagnostics() {
        let text = diagnosticsSummary()
        clipboardService.copy(text)
        showToast("Diagnostics copied", symbolName: "doc.on.doc")
    }

    func clearDiagnostics() {
        diagnostics.recentEvents.removeAll()
        showToast("Diagnostics cleared", symbolName: "trash")
    }

    private func switchToHardwareTransportIfNeeded() async {
        guard scannerSource != .hardware || transport !== hardwareTransport else {
            return
        }
        let previousTransport = transport
        stopStreamTasks()
        reconnectTask?.cancel()
        await previousTransport.disconnect()
        scannerSource = .hardware
        settings.scannerSource = .hardware
        sessionSource = .hardware
        clearSessionLocally()
        transport = hardwareTransport
        status = .disconnected
        connectionState = .disconnected
        resetDiagnosticsForSource(.hardware, selectedDevice: selectedSerialDevice)
        startStreamTasks(for: transport)
        await refreshDevices()
        resetDiagnosticsForSource(.hardware, selectedDevice: selectedSerialDevice)
    }

    private func startStreamTasks(for transport: ScannerTransport) {
        streamGeneration += 1
        let generation = streamGeneration

        observationTask = Task { [weak self, weak transport] in
            guard let self else { return }
            guard let transport else { return }
            for await observation in transport.observationStream {
                guard isCurrentStream(transport: transport, generation: generation) else { return }
                handle(observation)
            }
        }

        statusTask = Task { [weak self, weak transport] in
            guard let self else { return }
            guard let transport else { return }
            for await nextStatus in transport.statusStream {
                guard isCurrentStream(transport: transport, generation: generation) else { return }
                apply(nextStatus)
            }
        }

        connectionTask = Task { [weak self, weak transport] in
            guard let self else { return }
            guard let transport else { return }
            for await nextState in transport.connectionStream {
                guard isCurrentStream(transport: transport, generation: generation) else { return }
                apply(nextState)
            }
        }

        responseTask = Task { [weak self, weak transport] in
            guard let self else { return }
            guard let transport else { return }
            for await response in transport.responseStream {
                guard isCurrentStream(transport: transport, generation: generation) else { return }
                diagnostics.append(DiagnosticEvent(date: Date(), kind: "response", summary: "\(response.command): \(response.ok)", raw: nil))
            }
        }

        errorTask = Task { [weak self, weak transport] in
            guard let self else { return }
            guard let transport else { return }
            for await error in transport.errorStream {
                guard isCurrentStream(transport: transport, generation: generation) else { return }
                handle(error)
            }
        }

        diagnosticsTask = Task { [weak self, weak transport] in
            guard let self else { return }
            guard let transport else { return }
            for await nextDiagnostics in transport.diagnosticsStream {
                guard isCurrentStream(transport: transport, generation: generation) else { return }
                diagnostics = nextDiagnostics
            }
        }
    }

    private func stopStreamTasks() {
        streamGeneration += 1
        observationTask?.cancel()
        statusTask?.cancel()
        connectionTask?.cancel()
        responseTask?.cancel()
        errorTask?.cancel()
        diagnosticsTask?.cancel()
        observationTask = nil
        statusTask = nil
        connectionTask = nil
        responseTask = nil
        errorTask = nil
        diagnosticsTask = nil
    }

    private func isCurrentStream(transport streamTransport: ScannerTransport, generation: Int) -> Bool {
        generation == streamGeneration && streamTransport === transport
    }

    private func resetDiagnosticsForSource(_ source: ScannerSource, selectedDevice: SerialDevice?) {
        switch source {
        case .hardware:
            diagnostics = ScannerDiagnostics(
                connectionStateDescription: connectionState.visibleStatus,
                selectedDevice: selectedDevice?.isHardwareSerialPort == true ? selectedDevice : nil,
                baudRate: 115200
            )
        case .macNative:
            diagnostics = ScannerDiagnostics(
                connectionStateDescription: connectionState.visibleStatus,
                selectedDevice: .nativeMacScanner,
                baudRate: 0,
                firmwareVersion: "macOS-native",
                board: ProcessInfo.processInfo.operatingSystemVersionString,
                schemaVersion: 1
            )
        case .test:
            diagnostics = ScannerDiagnostics(connectionStateDescription: "Test Mode", baudRate: 0, firmwareVersion: "test", board: "mock")
        case .recorded:
            diagnostics = ScannerDiagnostics(connectionStateDescription: "Recorded", baudRate: 0)
        }
    }

    private func startClock() {
        clockTask?.cancel()
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                guard let self else { return }
                self.refreshClock(now: Date())
            }
        }
    }

    private func handle(_ observation: ScannerObservation) {
        guard observation.isSupportedDetection else {
            return
        }

        if scannerSource.isLiveScanner, !acceptsLiveDetections, !status.isScanning {
            return
        }

        // Use host Mac receipt time as the authoritative live timestamp.
        // Firmware uptime is NOT a wall-clock value and converting it can
        // place lastSeen in the future, which prevents stale-camera expiration
        // and freezes the "Detected X sec ago" display at 0.
        let receivedAt = Date()

        let identity = normalizedIdentity(for: observation)
        let id = deviceIDToCameraID[identity] ?? UUID()
        deviceIDToCameraID[identity] = id
        let metadata = userMetadata[identity] ?? CameraUserMetadata()

        // Track firmware uptime for reboot detection but never for live timestamps
        if observation.uptimeMilliseconds > 0 {
            lastSeenFirmwareUptime = observation.uptimeMilliseconds
        }

        diagnostics.append(DiagnosticEvent(
            date: receivedAt,
            kind: "detection_received",
            summary: "\(observation.deviceID) host=\(receivedAt) firmwareUptime=\(observation.uptimeMilliseconds)",
            raw: observation.rawEvent
        ))

        if let index = cameras.firstIndex(where: { $0.id == id }) {
            var updated = cameras[index]
            updated.applyObservation(observation, at: receivedAt)
            updated.marked = metadata.marked
            updated.note = metadata.note
            updated.noteUpdatedAt = metadata.noteUpdatedAt
            cameras[index] = updated
            sessionDetections[id] = updated
            lastRawEvents[id] = observation.rawEvent
        } else {
            let firstSeenDate = safeFirstSeenDate(
                observation: observation,
                receivedAt: receivedAt
            )
            let camera = CameraDetection(
                id: id,
                name: observation.displayName,
                type: .camera,
                macAddress: normalizedMAC(observation.macAddress),
                protocolType: observation.protocolType,
                channel: observation.channel,
                frequencyMHz: observation.frequencyMHz,
                rssi: observation.rssi,
                peakRSSI: observation.peakRSSI ?? observation.rssi,
                averageRSSI: observation.averageRSSI ?? Double(observation.rssi),
                observationCount: Int(observation.observationCount),
                firstSeen: firstSeenDate,
                lastSeen: receivedAt,
                secondsSinceSeen: 0,
                marked: metadata.marked,
                note: metadata.note,
                noteUpdatedAt: metadata.noteUpdatedAt,
                rssiHistory: [RSSISample(timestamp: receivedAt, rssi: observation.rssi)],
                deviceID: identity,
                confidence: observation.confidence,
                confidenceLabel: observation.confidenceLabel,
                detectionMethods: observation.detectionMethods,
                rawEvent: observation.rawEvent,
                sessionSource: sessionSource,
                smoothedRSSI: observation.smoothedRSSI,
                rssiTrend: observation.rssiTrend
            )
            cameras.insert(camera, at: 0)
            sessionDetections[id] = camera
            lastRawEvents[id] = observation.rawEvent
            NotificationService.shared.notifyNewCamera(camera, settings: settings)
            if selectedCameraID == nil {
                selectedCameraID = id
            }
        }

        ensureSelection()
    }

    /// Estimate firstSeen relative to the detection event without converting
    /// firmware uptime into a host absolute timestamp.
    private func safeFirstSeenDate(
        observation: ScannerObservation,
        receivedAt: Date
    ) -> Date {
        guard
            let firstSeenMs = observation.firstSeenMilliseconds,
            let eventUptimeMs = observation.uptimeMilliseconds as UInt64?,
            eventUptimeMs >= firstSeenMs
        else {
            return receivedAt
        }
        let ageMilliseconds = eventUptimeMs - firstSeenMs
        let maximumReasonableAgeMilliseconds: UInt64 = 24 * 60 * 60 * 1_000
        guard ageMilliseconds <= maximumReasonableAgeMilliseconds else {
            return receivedAt
        }
        let estimated = receivedAt.addingTimeInterval(
            -TimeInterval(ageMilliseconds) / 1_000
        )
        return min(estimated, receivedAt)
    }

    private func apply(_ nextStatus: ScannerStatus) {
        let wasScanning = status.isScanning
        status = nextStatus
        if nextStatus.firmwareVersion == nil, let firmwareVersion = connectionState.capabilities?.firmwareVersion {
            status.firmwareVersion = firmwareVersion
        }
        if nextStatus.uptimeMilliseconds < (lastSeenFirmwareUptime ?? 0), scannerSource == .hardware {
            handleFirmwareRestart()
        }
        lastSeenFirmwareUptime = nextStatus.uptimeMilliseconds
        updateClockTransition(wasScanning: wasScanning, isScanning: nextStatus.isScanning)

        if nextStatus.isScanning {
            acceptsLiveDetections = true
            scanControlState = scanControlState.isBusy ? scanControlState : .scanning
        } else if !scanControlState.isBusy {
            scanControlState = .stopped
        }
    }

    private func apply(_ state: ScannerConnectionState) {
        let wasConnected = connectionState.isConnected
        connectionState = state
        diagnostics.connectionStateDescription = state.visibleStatus
        switch state {
        case .connected(let device, let capabilities):
            if scannerSource == .hardware, device.isHardwareSerialPort {
                selectedSerialDevice = device
            }
            status.firmwareVersion = capabilities.firmwareVersion
            hostConnectionDate = Date()
            firmwareUptimeAtConnection = lastSeenFirmwareUptime ?? 0
            lastConnectionError = nil
            if !wasConnected {
                showToastOnce(scannerSource == .macNative ? "Mac Scanner connected" : "ESP32 connected", symbolName: scannerSource == .macNative ? "macbook.and.iphone" : "cpu")
            }
            wasConnectionEstablished = true
        case .disconnected:
            stopSessionClock()
            if wasConnected {
                showToastOnce(scannerSource == .macNative ? "Mac Scanner disconnected" : "ESP32 disconnected", symbolName: scannerSource == .macNative ? "macbook.and.iphone" : "cpu")
            }
            wasConnectionEstablished = false
        case .failed:
            stopSessionClock()
            if wasConnected {
                showToastOnce(scannerSource == .macNative ? "Mac Scanner disconnected" : "ESP32 disconnected", symbolName: scannerSource == .macNative ? "macbook.and.iphone" : "cpu")
            }
            wasConnectionEstablished = false
            if case .failed(let message) = state {
                lastConnectionError = message
                maybeStartReconnect()
            }
        default:
            break
        }
    }

    private func handle(_ error: ScannerTransportError) {
        lastConnectionError = error.localizedDescription
        diagnostics.append(DiagnosticEvent(date: Date(), kind: "transport_error", summary: error.localizedDescription, raw: nil))
        if error == .connectionLost {
            connectionState = .failed(message: error.localizedDescription)
            stopSessionClock()
            maybeStartReconnect()
        }
    }

    private func maybeStartReconnect() {
        guard scannerSource == .hardware, settings.autoReconnect, reconnectTask == nil else {
            return
        }

        reconnectTask = Task { [weak self] in
            guard let self else { return }
            for attempt in 1...20 {
                if Task.isCancelled { return }
                connectionState = .reconnecting(attempt: attempt)
                let delay = min(pow(2.0, Double(attempt - 1)), 10.0)
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                await refreshDevices()
                if let device = selectedSerialDevice ?? availableSerialDevices.first(where: \.isLikelyESP32) {
                    await connectToDevice(device, isAutoReconnect: true)
                    if connectionState.isConnected {
                        reconnectTask = nil
                        return
                    }
                }
            }
            reconnectTask = nil
        }
    }

    private func matchSavedDevice(_ saved: SerialDevice) -> SerialDevice? {
        availableSerialDevices.first { candidate in
            candidate.serialNumber == saved.serialNumber && saved.serialNumber != nil
        } ?? availableSerialDevices.first { $0.id == saved.id } ?? availableSerialDevices.first { $0.path == saved.path }
    }

    private func clearSessionLocally() {
        cameras.removeAll()
        sessionDetections.removeAll()
        hiddenCameraIDs.removeAll()
        deviceIDToCameraID.removeAll()
        lastRawEvents.removeAll()
        selectedCameraID = nil
        accumulatedSessionDuration = 0
        lastScanStartDate = nil
        sessionDuration = 0
        sessionStartedAt = Date()
        acceptsLiveDetections = !scannerSource.isLiveScanner
        scanControlState = .stopped
        resetUptimeMapping()
    }

    private func resetUptimeMapping() {
        hostConnectionDate = Date()
        firmwareUptimeAtConnection = lastSeenFirmwareUptime ?? 0
    }

    private func handleFirmwareRestart() {
        resetUptimeMapping()
        showToast("ESP32 restarted", symbolName: "arrow.clockwise")
        Task {
            try? await transport.send(.setMode(status.mode))
            if status.isScanning {
                try? await transport.startScan()
            }
        }
    }

    private func hostDate(forFirmwareUptime uptime: UInt64) -> Date {
        let now = Date()
        guard let hostConnectionDate, let firmwareUptimeAtConnection else {
            self.hostConnectionDate = now
            self.firmwareUptimeAtConnection = uptime
            return now
        }

        if uptime + 1_000 < firmwareUptimeAtConnection {
            self.hostConnectionDate = now
            self.firmwareUptimeAtConnection = uptime
            return now
        }

        let delta = TimeInterval(Int64(uptime) - Int64(firmwareUptimeAtConnection)) / 1000.0
        return hostConnectionDate.addingTimeInterval(delta)
    }

    private func normalizedIdentity(for observation: ScannerObservation) -> String {
        if !observation.deviceID.isEmpty {
            return observation.deviceID.lowercased()
        }
        return "\(observation.protocolType.normalizedID):\(normalizedMAC(observation.macAddress))".lowercased()
    }

    private func normalizedMAC(_ mac: String) -> String {
        mac.uppercased()
    }

    private func ensureSelection() {
        if selectedCameraID == nil || selectedCamera == nil {
            selectedCameraID = visibleCameras.first?.id
        }
    }

    private func matchesSearch(_ camera: CameraDetection) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return true
        }

        let fields = [
            camera.name,
            camera.macAddress,
            camera.protocolType.rawValue,
            camera.channel.map { "CH \($0)" } ?? "",
            camera.channel.map(String.init) ?? "",
            camera.frequencyMHz.map { "\($0) MHz" } ?? ""
        ]

        return fields.contains { $0.lowercased().contains(query) }
    }

    private func sortedCameras(from cameras: [CameraDetection]) -> [CameraDetection] {
        switch sortOption {
        case .lastDetected:
            cameras.sorted { $0.lastSeen > $1.lastSeen }
        case .signalStrength, .closest:
            cameras.sorted { $0.rssi > $1.rssi }
        case .farthest:
            cameras.sorted { $0.rssi < $1.rssi }
        case .name:
            cameras.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .observationCount:
            cameras.sorted { $0.observationCount > $1.observationCount }
        }
    }

    private func startSessionClock() {
        if lastScanStartDate == nil {
            lastScanStartDate = Date()
        }
    }

    private func stopSessionClock() {
        if let lastScanStartDate {
            accumulatedSessionDuration += Date().timeIntervalSince(lastScanStartDate)
        }
        self.lastScanStartDate = nil
        refreshClock()
    }

    private func updateClockTransition(wasScanning: Bool, isScanning: Bool) {
        if wasScanning, !isScanning {
            stopSessionClock()
            clearActiveCamerasAfterStop()
        } else if !wasScanning, isScanning {
            startSessionClock()
        }
        refreshClock()
    }

    /// Preserve session history but remove all active camera rows when scanning stops.
    private func clearActiveCamerasAfterStop() {
        for camera in cameras {
            sessionDetections[camera.id] = camera
        }
        cameras.removeAll()
        selectedCameraID = nil
    }

    private func refreshClock(now: Date = Date()) {
        if status.isScanning, let lastScanStartDate {
            sessionDuration = accumulatedSessionDuration + now.timeIntervalSince(lastScanStartDate)
        } else {
            sessionDuration = accumulatedSessionDuration
        }

        // Force an array-level publication so SwiftUI re-renders every row.
        // In-place index mutation does not always trigger @Published updates.
        cameras = cameras.map { camera in
            var updated = camera
            updated.refreshRelativeTime(now: now)
            return updated
        }

        expireStaleCameras(now: now)
    }

    private func expireStaleCameras(now: Date) {
        let timeout = settings.activeDetectionTimeout
        guard timeout > 0 else {
            return
        }

        let expiredIDs = Set(
            cameras
                .filter { camera in
                    let age = now.timeIntervalSince(camera.lastSeen)
                    return age >= timeout
                }
                .map(\.id)
        )
        guard !expiredIDs.isEmpty else {
            return
        }

        for camera in cameras where expiredIDs.contains(camera.id) {
            sessionDetections[camera.id] = camera
            diagnostics.append(
                DiagnosticEvent(
                    date: now,
                    kind: "detection_expired",
                    summary: camera.deviceID,
                    raw: nil
                )
            )
        }

        cameras.removeAll { expiredIDs.contains($0.id) }

        if let selectedCameraID, expiredIDs.contains(selectedCameraID) {
            self.selectedCameraID = cameras.first?.id
        }
    }

    private func persistMetadata(for camera: CameraDetection) {
        guard !camera.deviceID.isEmpty else {
            return
        }

        userMetadata[camera.deviceID] = CameraUserMetadata(
            marked: camera.marked,
            note: camera.note,
            noteUpdatedAt: camera.noteUpdatedAt
        )
        sessionDetections[camera.id] = camera
    }

    private func export(format: ExportFormat) async {
        do {
            let metadata = ExportSessionMetadata(
                dataSource: sessionSource,
                firmwareVersion: connectionState.capabilities?.firmwareVersion ?? status.firmwareVersion,
                connectedDevice: connectionState.connectedDevice,
                appVersion: "1.0.0",
                sessionStart: sessionStartedAt,
                sessionEnd: Date(),
                scannerMode: status.mode.displayValue,
                wifiChannel: status.wifiChannelDisplay,
                bleState: status.bleScanState.rawValue
            )
            if let url = try await exportService.export(cameras: exportCameras, metadata: metadata, format: format) {
                showToastOnce("Exported \(url.lastPathComponent)", symbolName: "square.and.arrow.up")
            }
        } catch {
            showToastOnce("Export failed", symbolName: "exclamationmark.triangle")
        }
    }

    private func showToastOnce(_ text: String, symbolName: String) {
        let signature = "\(text)|\(symbolName)"
        guard lastToastSignature != signature else {
            return
        }
        lastToastSignature = signature
        showToast(text, symbolName: symbolName)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if self?.lastToastSignature == signature {
                self?.lastToastSignature = nil
            }
        }
    }

    private func showToast(_ text: String, symbolName: String) {
        toast = ToastMessage(text: text, symbolName: symbolName)
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_200_000_000)
            } catch {
                return
            }
            self?.toast = nil
        }
    }

    func performExpiryCheck(now: Date = Date()) {
        expireStaleCameras(now: now)
    }

    private func prettyPrintedJSON(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else {
            return raw
        }
        return string
    }

    private func diagnosticsSummary() -> String {
        """
        FlockView Diagnostics
        Connection: \(connectionState.visibleStatus)
        Source: \(sessionSourceLabel)
        Device: \(selectedSerialDevice?.displayName ?? "None")
        Path: \(selectedSerialDevice?.path ?? "None")
        Firmware: \(connectionState.capabilities?.firmwareVersion ?? status.firmwareVersion ?? "Unknown")
        Valid lines: \(diagnostics.validJSONLineCount)
        Malformed lines: \(diagnostics.malformedLineCount)
        Unknown events: \(diagnostics.unknownEventCount)
        Bytes received: \(diagnostics.bytesReceived)
        Dropped firmware observations: \(diagnostics.droppedFirmwareObservations)
        Free heap: \(diagnostics.freeHeap.map(String.init) ?? "Unknown")
        """
    }

    private static func rawEvent(for camera: CameraDetection) -> String {
        """
        {"schema_version":1,"event":"detection","source":"manual_test","vendor":"Flock Safety","device_type":"camera","protocol":"\(camera.protocolType.normalizedID)","device_id":"\(camera.protocolType.normalizedID):\(camera.macAddress)","mac_address":"\(camera.macAddress)","rssi":\(camera.rssi),"confidence":70,"confidence_label":"HIGH","detection_methods":["manual_test"],"observation_count":\(camera.observationCount),"uptime_ms":0}
        """
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]
        return formatter
    }()
}

private extension ScannerSource {
    var sessionDataSource: SessionDataSource {
        switch self {
        case .hardware:
            .hardware
        case .macNative:
            .macNative
        case .test:
            .test
        case .recorded:
            .recorded
        }
    }
}

private extension SerialDevice {
    static let testDevice = SerialDevice(id: "test", path: "test://local", displayName: "Test Scanner")
    static let recordedDevice = SerialDevice(id: "recorded", path: "recorded://fixture", displayName: "Recorded Fixture")

    func matchesHardwareIdentity(of other: SerialDevice) -> Bool {
        if let serialNumber, let otherSerialNumber = other.serialNumber, !serialNumber.isEmpty {
            return serialNumber == otherSerialNumber
        }
        return id == other.id || path == other.path
    }
}
