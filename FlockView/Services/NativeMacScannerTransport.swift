import CoreBluetooth
import CoreLocation
import CoreWLAN
import Foundation

final class NativeMacScannerTransport: NSObject, ScannerTransport, @unchecked Sendable {
    private let observationPipe = AsyncStream<ScannerObservation>.makeStream()
    private let statusPipe = AsyncStream<ScannerStatus>.makeStream()
    private let connectionPipe = AsyncStream<ScannerConnectionState>.makeStream()
    private let responsePipe = AsyncStream<ScannerCommandResponse>.makeStream()
    private let errorPipe = AsyncStream<ScannerTransportError>.makeStream()
    private let diagnosticsPipe = AsyncStream<ScannerDiagnostics>.makeStream()

    private let classifier = FlockDeviceClassifier()
    private let bluetoothQueue = DispatchQueue(label: "com.flockview.native-mac-scanner.bluetooth")
    private let stateQueue = DispatchQueue(label: "com.flockview.native-mac-scanner.state")

    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private var wifiScanTask: Task<Void, Never>?
    private var statusTask: Task<Void, Never>?
    private var records: [String: NativeDeviceRecord] = [:]
    private var status = ScannerStatus.nativeMac
    private var diagnostics = ScannerDiagnostics(
        connectionStateDescription: "Disconnected",
        selectedDevice: .nativeMacScanner,
        baudRate: 0,
        firmwareVersion: NativeMacScannerTransport.capabilities.firmwareVersion,
        board: NativeMacScannerTransport.capabilities.board
    )
    private var isConnected = false
    private var isScanning = false
    private var startDate = Date()
    private var rssiMinimum = -95
    private var wifiScanIntervalNanoseconds: UInt64 = 4_000_000_000
    private var droppedObservations: UInt64 = 0
    private var wifiNetworksSeen: UInt64 = 0
    private var bleAdvertisementsSeen: UInt64 = 0
    private var hasReportedWiFiScanFailure = false
    private var hasReportedBluetoothUnavailable = false

    var observationStream: AsyncStream<ScannerObservation> { observationPipe.stream }
    var statusStream: AsyncStream<ScannerStatus> { statusPipe.stream }
    var connectionStream: AsyncStream<ScannerConnectionState> { connectionPipe.stream }
    var responseStream: AsyncStream<ScannerCommandResponse> { responsePipe.stream }
    var errorStream: AsyncStream<ScannerTransportError> { errorPipe.stream }
    var diagnosticsStream: AsyncStream<ScannerDiagnostics> { diagnosticsPipe.stream }

    deinit {
        wifiScanTask?.cancel()
        statusTask?.cancel()
        bluetoothQueue.sync {
            centralManager?.stopScan()
        }
    }

    func availableDevices() async -> [SerialDevice] {
        [.nativeMacScanner]
    }

    func connect(to device: SerialDevice) async throws {
        startDate = Date()
        isConnected = true
        hasReportedWiFiScanFailure = false
        hasReportedBluetoothUnavailable = false

        requestLocationAuthorizationIfNeeded()
        ensureBluetoothManager()

        updateStatus { status in
            status = Self.makeStatus(
                state: "stopped",
                mode: status.mode,
                phase: nil,
                uptimeMilliseconds: uptimeMilliseconds,
                wifiNetworksSeen: wifiNetworksSeen,
                bleAdvertisementsSeen: bleAdvertisementsSeen,
                trackedDevices: records.count,
                matchingDevices: records.count,
                droppedObservations: droppedObservations
            )
        }

        updateDiagnostics { diagnostics in
            diagnostics.connectionStateDescription = "Connected"
            diagnostics.selectedDevice = device
            diagnostics.baudRate = 0
            diagnostics.firmwareVersion = Self.capabilities.firmwareVersion
            diagnostics.board = Self.capabilities.board
            diagnostics.schemaVersion = 1
            diagnostics.append(
                DiagnosticEvent(
                    date: Date(),
                    kind: "native_connect",
                    summary: "Mac BLE + Wi-Fi scanner ready",
                    raw: nil
                )
            )
        }

        connectionPipe.continuation.yield(.connected(device, Self.capabilities))
        statusPipe.continuation.yield(snapshotStatus())
    }

    func disconnect() async {
        isConnected = false
        isScanning = false
        wifiScanTask?.cancel()
        wifiScanTask = nil
        statusTask?.cancel()
        statusTask = nil
        bluetoothQueue.async { [weak self] in
            self?.centralManager?.stopScan()
        }
        updateStatus { status in
            status.state = "disconnected"
            status.phase = nil
        }
        updateDiagnostics { diagnostics in
            diagnostics.connectionStateDescription = "Disconnected"
        }
        connectionPipe.continuation.yield(.disconnected)
        statusPipe.continuation.yield(snapshotStatus())
    }

    func startScan() async throws {
        if !isConnected {
            try await connect(to: .nativeMacScanner)
        }

        isScanning = true
        updateStatus { status in
            status.state = "scanning"
            status.phase = Self.phase(for: status.mode)
            status.uptimeMilliseconds = uptimeMilliseconds
        }
        responsePipe.continuation.yield(
            ScannerCommandResponse(command: "START", ok: true, message: "native scanner started", uptimeMilliseconds: uptimeMilliseconds)
        )
        statusPipe.continuation.yield(snapshotStatus())
        startRadioTasks()
        startStatusTask()
    }

    func stopScan() async throws {
        isScanning = false
        wifiScanTask?.cancel()
        wifiScanTask = nil
        statusTask?.cancel()
        statusTask = nil
        bluetoothQueue.async { [weak self] in
            self?.centralManager?.stopScan()
        }
        updateStatus { status in
            status.state = "stopped"
            status.phase = nil
            status.uptimeMilliseconds = uptimeMilliseconds
        }
        responsePipe.continuation.yield(
            ScannerCommandResponse(command: "STOP", ok: true, message: "native scanner stopped", uptimeMilliseconds: uptimeMilliseconds)
        )
        statusPipe.continuation.yield(snapshotStatus())
    }

    func send(_ command: ScannerCommand) async throws {
        switch command {
        case .ping:
            responsePipe.continuation.yield(
                ScannerCommandResponse(command: command.responseCommand, ok: true, message: "pong", uptimeMilliseconds: uptimeMilliseconds)
            )
        case .status:
            statusPipe.continuation.yield(snapshotStatus())
            responsePipe.continuation.yield(
                ScannerCommandResponse(command: command.responseCommand, ok: true, message: "status emitted", uptimeMilliseconds: uptimeMilliseconds)
            )
        case .start:
            try await startScan()
        case .stop:
            try await stopScan()
        case .clear:
            stateQueue.sync {
                records.removeAll()
                status.trackedDevices = 0
                status.matchingDevices = 0
            }
            responsePipe.continuation.yield(
                ScannerCommandResponse(command: command.responseCommand, ok: true, message: "native session cleared", uptimeMilliseconds: uptimeMilliseconds)
            )
            statusPipe.continuation.yield(snapshotStatus())
        case .setMode(let mode):
            updateStatus { status in
                status.mode = mode
                status.phase = status.isScanning ? Self.phase(for: mode) : nil
            }
            responsePipe.continuation.yield(
                ScannerCommandResponse(command: command.responseCommand, ok: true, message: "native mode updated", uptimeMilliseconds: uptimeMilliseconds)
            )
            if isScanning {
                startRadioTasks()
            }
            statusPipe.continuation.yield(snapshotStatus())
        case .setWiFiDwell(let milliseconds):
            let clampedMilliseconds = max(1_000, min(30_000, milliseconds))
            wifiScanIntervalNanoseconds = UInt64(clampedMilliseconds) * 1_000_000
            responsePipe.continuation.yield(
                ScannerCommandResponse(command: command.responseCommand, ok: true, message: "native wifi scan interval updated", uptimeMilliseconds: uptimeMilliseconds)
            )
        case .setBLEWindow:
            responsePipe.continuation.yield(
                ScannerCommandResponse(command: command.responseCommand, ok: true, message: "native ble scan is continuous while enabled", uptimeMilliseconds: uptimeMilliseconds)
            )
        case .setMinimumRSSI(let value):
            rssiMinimum = max(-127, min(0, value))
            responsePipe.continuation.yield(
                ScannerCommandResponse(command: command.responseCommand, ok: true, message: "native minimum rssi updated", uptimeMilliseconds: uptimeMilliseconds)
            )
        case .setDebug:
            responsePipe.continuation.yield(
                ScannerCommandResponse(command: command.responseCommand, ok: true, message: "native debug accepted", uptimeMilliseconds: uptimeMilliseconds)
            )
        }
        updateDiagnostics { diagnostics in
            diagnostics.commandCount += 1
            diagnostics.append(
                DiagnosticEvent(
                    date: Date(),
                    kind: "command_response",
                    summary: "\(command.responseCommand): true",
                    raw: nil
                )
            )
        }
    }

    private func requestLocationAuthorizationIfNeeded() {
        guard locationManager == nil else {
            return
        }
        let manager = CLLocationManager()
        locationManager = manager
        manager.requestWhenInUseAuthorization()
    }

    private func ensureBluetoothManager() {
        bluetoothQueue.sync {
            if centralManager == nil {
                centralManager = CBCentralManager(
                    delegate: self,
                    queue: bluetoothQueue,
                    options: [CBCentralManagerOptionShowPowerAlertKey: true]
                )
            }
        }
    }

    private func startRadioTasks() {
        wifiScanTask?.cancel()
        wifiScanTask = nil
        bluetoothQueue.async { [weak self] in
            self?.centralManager?.stopScan()
        }

        let mode = snapshotStatus().mode
        if mode != .bleOnly {
            wifiScanTask = Task { [weak self] in
                await self?.runWiFiScanLoop()
            }
        }

        if mode != .wifiOnly {
            startBluetoothScanIfAvailable()
        }
    }

    private func startStatusTask() {
        guard statusTask == nil else {
            return
        }

        statusTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
                self?.publishStatusSnapshot()
            }
        }
    }

    private func runWiFiScanLoop() async {
        while !Task.isCancelled {
            await scanWiFiOnce()
            let interval = stateQueue.sync { wifiScanIntervalNanoseconds }
            do {
                try await Task.sleep(nanoseconds: interval)
            } catch {
                return
            }
        }
    }

    private func scanWiFiOnce() async {
        guard isConnected, isScanning, snapshotStatus().mode != .bleOnly else {
            return
        }

        guard let interface = CWWiFiClient.shared().interface() else {
            reportWiFiScanFailure("No CoreWLAN Wi-Fi interface is available.")
            return
        }

        do {
            let networks = try interface.scanForNetworks(withSSID: nil)
            hasReportedWiFiScanFailure = false
            stateQueue.sync {
                wifiNetworksSeen += UInt64(networks.count)
            }
            for network in networks {
                process(network: network)
            }
            publishStatusSnapshot()
        } catch {
            reportWiFiScanFailure(error.localizedDescription)
        }
    }

    private func reportWiFiScanFailure(_ message: String) {
        let shouldReport = stateQueue.sync { () -> Bool in
            if hasReportedWiFiScanFailure {
                return false
            }
            hasReportedWiFiScanFailure = true
            return true
        }
        updateDiagnostics { diagnostics in
            diagnostics.append(
                DiagnosticEvent(
                    date: Date(),
                    kind: "wifi_scan_failed",
                    summary: message,
                    raw: nil
                )
            )
        }
        if shouldReport {
            errorPipe.continuation.yield(.openFailed("Mac Wi-Fi scan failed: \(message)"))
        }
    }

    private func process(network: CWNetwork) {
        guard let bssid = network.bssid?.uppercased(), !bssid.isEmpty else {
            return
        }

        let rssi = network.rssiValue
        guard rssi >= rssiMinimum else {
            return
        }

        let ssid = network.ssid
        let classification = classifier.classifyWiFi(
            macAddress: bssid,
            ssid: ssid,
            frameSubtype: "beacon"
        )
        guard classification.matched else {
            return
        }

        let channel = network.wlanChannel?.channelNumber
        let candidate = NativeScanCandidate(
            protocolType: .wifi,
            deviceID: "wifi:\(bssid)",
            displayAddress: bssid,
            name: nil,
            bssid: bssid,
            ssid: ssid,
            addressType: nil,
            manufacturerID: nil,
            serviceUUIDs: [],
            frameSubtype: "beacon",
            channel: channel,
            frequencyMHz: channel.map(Self.frequencyMHz(forWiFiChannel:)),
            rssi: rssi
        )

        emitIfNeeded(candidate: candidate, classification: classification)
    }

    private func startBluetoothScanIfAvailable() {
        bluetoothQueue.async { [weak self] in
            guard let self, self.shouldScanBluetooth else {
                return
            }

            guard let centralManager else {
                return
            }

            switch centralManager.state {
            case .poweredOn:
                centralManager.scanForPeripherals(
                    withServices: nil,
                    options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
                )
                stateQueue.sync {
                    self.hasReportedBluetoothUnavailable = false
                }
            case .unsupported, .unauthorized, .poweredOff:
                self.reportBluetoothUnavailable(centralManager.state)
            default:
                break
            }
        }
    }

    private var shouldScanBluetooth: Bool {
        stateQueue.sync {
            isConnected && isScanning && status.mode != .wifiOnly
        }
    }

    private func reportBluetoothUnavailable(_ state: CBManagerState) {
        let shouldReport = stateQueue.sync { () -> Bool in
            if hasReportedBluetoothUnavailable {
                return false
            }
            hasReportedBluetoothUnavailable = true
            return true
        }
        guard shouldReport else {
            return
        }
        updateDiagnostics { diagnostics in
            diagnostics.append(
                DiagnosticEvent(
                    date: Date(),
                    kind: "ble_unavailable",
                    summary: Self.bluetoothStateDescription(state),
                    raw: nil
                )
            )
        }
        errorPipe.continuation.yield(.openFailed("Mac BLE unavailable: \(Self.bluetoothStateDescription(state))"))
    }

    private func processBluetoothDiscovery(
        peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi: Int
    ) {
        guard rssi != 127, rssi >= rssiMinimum else {
            return
        }

        let localName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = localName ?? peripheral.name
        let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data
        let manufacturerID = Self.manufacturerID(from: manufacturerData)
        let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? [])
            .map(\.uuidString)
        let displayAddress = "CB-\(peripheral.identifier.uuidString.prefix(8))"

        let classification = classifier.classifyBLE(
            displayAddress: displayAddress,
            name: name,
            manufacturerID: manufacturerID,
            serviceUUIDs: serviceUUIDs,
            addressType: nil
        )
        guard classification.matched else {
            return
        }

        stateQueue.sync {
            bleAdvertisementsSeen += 1
        }

        let candidate = NativeScanCandidate(
            protocolType: .ble,
            deviceID: "ble:\(peripheral.identifier.uuidString)",
            displayAddress: displayAddress,
            name: name,
            bssid: nil,
            ssid: nil,
            addressType: "corebluetooth",
            manufacturerID: manufacturerID,
            serviceUUIDs: serviceUUIDs,
            frameSubtype: nil,
            channel: nil,
            frequencyMHz: nil,
            rssi: rssi
        )

        emitIfNeeded(candidate: candidate, classification: classification)
    }

    private func emitIfNeeded(
        candidate: NativeScanCandidate,
        classification: FlockClassificationResult
    ) {
        let emission = stateQueue.sync { () -> NativeObservationEmission? in
            let nowMs = uptimeMilliseconds
            var record = records[candidate.deviceID] ?? NativeDeviceRecord(
                protocolType: candidate.protocolType,
                deviceID: candidate.deviceID,
                firstSeenMilliseconds: nowMs,
                lastSeenMilliseconds: nowMs
            )
            record.rssi.update(with: candidate.rssi)
            record.lastSeenMilliseconds = nowMs
            record.confidence = classification.confidence
            record.confidenceLabel = classification.confidenceLabel
            record.proximity = record.rssi.proximity

            let shouldEmit = record.shouldEmit(
                classification: classification,
                currentRSSI: candidate.rssi,
                nowMilliseconds: nowMs
            )
            if shouldEmit {
                record.lastEmissionMilliseconds = nowMs
                record.lastEmittedRSSI = candidate.rssi
                record.lastEmittedConfidence = classification.confidence
                record.lastEmittedProximity = record.proximity
            }

            records[candidate.deviceID] = record
            status.trackedDevices = records.count
            status.matchingDevices = records.count
            status.queueDepth = 0
            status.droppedObservations = droppedObservations
            status.wifiFramesSeen = wifiNetworksSeen
            status.bleAdvertisementsSeen = bleAdvertisementsSeen
            status.uptimeMilliseconds = nowMs

            guard shouldEmit else {
                return nil
            }
            return NativeObservationEmission(candidate: candidate, classification: classification, record: record, uptimeMilliseconds: nowMs)
        }

        guard let emission else {
            return
        }

        let observation = makeObservation(from: emission)
        observationPipe.continuation.yield(observation)
        updateDiagnostics { diagnostics in
            diagnostics.validJSONLineCount += 1
            diagnostics.lastValidEventDate = Date()
            diagnostics.schemaVersion = 1
            diagnostics.append(
                DiagnosticEvent(
                    date: Date(),
                    kind: "native_detection",
                    summary: observation.deviceID,
                    raw: observation.rawEvent
                )
            )
        }
        publishStatusSnapshot()
    }

    private func makeObservation(from emission: NativeObservationEmission) -> ScannerObservation {
        let candidate = emission.candidate
        let classification = emission.classification
        let record = emission.record
        let manufacturerIDText = candidate.manufacturerID.map { String(format: "0x%04X", $0) }
        let rawEvent = Self.rawDetectionEvent(
            candidate: candidate,
            classification: classification,
            record: record,
            uptimeMilliseconds: emission.uptimeMilliseconds,
            manufacturerIDText: manufacturerIDText
        )

        return ScannerObservation(
            schemaVersion: 1,
            event: "detection",
            vendor: classification.vendor,
            deviceType: classification.deviceType,
            protocolType: candidate.protocolType,
            deviceID: candidate.deviceID,
            macAddress: candidate.displayAddress,
            name: candidate.name,
            bssid: candidate.bssid,
            ssid: candidate.ssid,
            addressType: candidate.addressType,
            manufacturerID: manufacturerIDText,
            serviceUUIDs: candidate.serviceUUIDs,
            frameSubtype: candidate.frameSubtype,
            channel: candidate.channel,
            frequencyMHz: candidate.frequencyMHz,
            rssi: candidate.rssi,
            smoothedRSSI: record.rssi.smoothedRSSI,
            peakRSSI: record.rssi.peakRSSI,
            averageRSSI: record.rssi.averageRSSI,
            proximity: record.proximity,
            rssiTrend: record.rssi.trend,
            confidence: classification.confidence,
            confidenceLabel: classification.confidenceLabel,
            detectionMethods: classification.detectionMethods,
            observationCount: UInt64(record.rssi.observationCount),
            firstSeenMilliseconds: record.firstSeenMilliseconds,
            lastSeenMilliseconds: record.lastSeenMilliseconds,
            uptimeMilliseconds: emission.uptimeMilliseconds,
            rawEvent: rawEvent
        )
    }

    private func publishStatusSnapshot() {
        updateStatus { status in
            status.uptimeMilliseconds = uptimeMilliseconds
            status.wifiFramesSeen = wifiNetworksSeen
            status.bleAdvertisementsSeen = bleAdvertisementsSeen
            status.trackedDevices = records.count
            status.matchingDevices = records.count
            status.droppedObservations = droppedObservations
        }
        statusPipe.continuation.yield(snapshotStatus())
    }

    private func snapshotStatus() -> ScannerStatus {
        stateQueue.sync { status }
    }

    private func updateStatus(_ update: (inout ScannerStatus) -> Void) {
        stateQueue.sync {
            update(&status)
        }
    }

    private func updateDiagnostics(_ update: (inout ScannerDiagnostics) -> Void) {
        let snapshot = stateQueue.sync { () -> ScannerDiagnostics in
            update(&diagnostics)
            diagnostics.selectedDevice = .nativeMacScanner
            return diagnostics
        }
        diagnosticsPipe.continuation.yield(snapshot)
    }

    private var uptimeMilliseconds: UInt64 {
        UInt64(max(0, Date().timeIntervalSince(startDate)) * 1_000)
    }

    fileprivate static func makeStatus(
        state: String,
        mode: ScanMode,
        phase: String?,
        uptimeMilliseconds: UInt64,
        wifiNetworksSeen: UInt64,
        bleAdvertisementsSeen: UInt64,
        trackedDevices: Int,
        matchingDevices: Int,
        droppedObservations: UInt64
    ) -> ScannerStatus {
        ScannerStatus(
            schemaVersion: 1,
            state: state,
            mode: mode,
            phase: phase,
            wifiChannel: nil,
            wifiFramesSeen: wifiNetworksSeen,
            bleAdvertisementsSeen: bleAdvertisementsSeen,
            queueDepth: 0,
            queueHighWatermark: 0,
            droppedObservations: droppedObservations,
            trackedDevices: trackedDevices,
            matchingDevices: matchingDevices,
            freeHeap: nil,
            uptimeMilliseconds: uptimeMilliseconds,
            firmwareVersion: capabilities.firmwareVersion
        )
    }

    private static func phase(for mode: ScanMode) -> String? {
        switch mode {
        case .bleOnly:
            "ble"
        case .wifiOnly:
            "wifi"
        case .dual:
            "ble"
        }
    }

    private static func rawDetectionEvent(
        candidate: NativeScanCandidate,
        classification: FlockClassificationResult,
        record: NativeDeviceRecord,
        uptimeMilliseconds: UInt64,
        manufacturerIDText: String?
    ) -> String {
        var event: [String: Any] = [
            "schema_version": 1,
            "event": "detection",
            "source": "mac_native",
            "vendor": classification.vendor,
            "device_type": classification.deviceType,
            "protocol": candidate.protocolType.normalizedID,
            "device_id": candidate.deviceID,
            "mac_address": candidate.displayAddress,
            "rssi": candidate.rssi,
            "smoothed_rssi": record.rssi.smoothedRSSI,
            "peak_rssi": record.rssi.peakRSSI,
            "average_rssi": record.rssi.averageRSSI,
            "proximity": record.proximity.rawValue.lowercased(),
            "rssi_trend": record.rssi.trend.rawValue,
            "confidence": classification.confidence,
            "confidence_label": classification.confidenceLabel.rawValue,
            "detection_methods": classification.detectionMethods,
            "observation_count": record.rssi.observationCount,
            "first_seen_ms": record.firstSeenMilliseconds,
            "last_seen_ms": record.lastSeenMilliseconds,
            "uptime_ms": uptimeMilliseconds
        ]

        if let name = candidate.name {
            event["name"] = name
        }
        if let bssid = candidate.bssid {
            event["bssid"] = bssid
        }
        if let ssid = candidate.ssid {
            event["ssid"] = ssid
        }
        if let addressType = candidate.addressType {
            event["address_type"] = addressType
        }
        if let manufacturerIDText {
            event["manufacturer_id"] = manufacturerIDText
        }
        if !candidate.serviceUUIDs.isEmpty {
            event["service_uuids"] = candidate.serviceUUIDs
        }
        if let frameSubtype = candidate.frameSubtype {
            event["frame_subtype"] = frameSubtype
        }
        if let channel = candidate.channel {
            event["channel"] = channel
        }
        if let frequencyMHz = candidate.frequencyMHz {
            event["frequency_mhz"] = frequencyMHz
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return #"{"schema_version":1,"event":"detection","source":"mac_native"}"#
        }
        return string
    }

    private static func manufacturerID(from data: Data?) -> UInt16? {
        guard let data, data.count >= 2 else {
            return nil
        }
        return UInt16(data[0]) | (UInt16(data[1]) << 8)
    }

    private static func frequencyMHz(forWiFiChannel channel: Int) -> Int {
        if channel == 14 {
            return 2484
        }
        if (1...13).contains(channel) {
            return 2407 + channel * 5
        }
        if (32...177).contains(channel) {
            return 5000 + channel * 5
        }
        return 0
    }

    private static func bluetoothStateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown:
            "unknown"
        case .resetting:
            "resetting"
        case .unsupported:
            "unsupported"
        case .unauthorized:
            "unauthorized"
        case .poweredOff:
            "powered off"
        case .poweredOn:
            "powered on"
        @unknown default:
            "unknown"
        }
    }

    private static let capabilities = ScannerCapabilities(
        firmware: "FlockViewMacScanner",
        firmwareVersion: "macOS-native",
        board: ProcessInfo.processInfo.operatingSystemVersionString,
        passiveOnly: false,
        wifiBands: ["2.4GHz", "5GHz", "6GHz"],
        bleSupported: true
    )
}

extension NativeMacScannerTransport: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        updateDiagnostics { diagnostics in
            diagnostics.append(
                DiagnosticEvent(
                    date: Date(),
                    kind: "ble_state",
                    summary: Self.bluetoothStateDescription(central.state),
                    raw: nil
                )
            )
        }

        if central.state == .poweredOn {
            startBluetoothScanIfAvailable()
        } else if shouldScanBluetooth {
            reportBluetoothUnavailable(central.state)
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        processBluetoothDiscovery(
            peripheral: peripheral,
            advertisementData: advertisementData,
            rssi: RSSI.intValue
        )
    }
}

private struct NativeScanCandidate {
    var protocolType: ProtocolType
    var deviceID: String
    var displayAddress: String
    var name: String?
    var bssid: String?
    var ssid: String?
    var addressType: String?
    var manufacturerID: UInt16?
    var serviceUUIDs: [String]
    var frameSubtype: String?
    var channel: Int?
    var frequencyMHz: Int?
    var rssi: Int
}

private struct NativeObservationEmission {
    var candidate: NativeScanCandidate
    var classification: FlockClassificationResult
    var record: NativeDeviceRecord
    var uptimeMilliseconds: UInt64
}

private struct NativeDeviceRecord {
    var protocolType: ProtocolType
    var deviceID: String
    var firstSeenMilliseconds: UInt64
    var lastSeenMilliseconds: UInt64
    var rssi = NativeRSSIState()
    var confidence = 0
    var confidenceLabel: ConfidenceLabel = .possible
    var proximity: ProximityLevel = .far
    var lastEmissionMilliseconds: UInt64 = 0
    var lastEmittedRSSI = 0
    var lastEmittedConfidence = 0
    var lastEmittedProximity: ProximityLevel = .far

    func shouldEmit(
        classification: FlockClassificationResult,
        currentRSSI: Int,
        nowMilliseconds: UInt64,
        cooldownMilliseconds: UInt64 = 5_000
    ) -> Bool {
        if rssi.observationCount <= 1 || lastEmissionMilliseconds == 0 {
            return true
        }
        if classification.confidence != lastEmittedConfidence {
            return true
        }
        if proximity != lastEmittedProximity {
            return true
        }
        if abs(currentRSSI - lastEmittedRSSI) >= 5 {
            return true
        }
        return nowMilliseconds - lastEmissionMilliseconds >= cooldownMilliseconds
    }
}

private struct NativeRSSIState {
    private let alpha = 0.35
    private(set) var initialized = false
    private(set) var currentRSSI = 0
    private(set) var peakRSSI = -127
    private(set) var minimumRSSI = 127
    private(set) var smoothedRSSI = 0.0
    private(set) var averageRSSI = 0.0
    private(set) var observationCount = 0
    private(set) var trend: RSSITrend = .stable

    var proximity: ProximityLevel {
        if currentRSSI >= -59 {
            return .close
        }
        if currentRSSI >= -74 {
            return .medium
        }
        return .far
    }

    mutating func update(with newestRSSI: Int) {
        let previousSmoothed = smoothedRSSI
        currentRSSI = newestRSSI

        guard initialized else {
            initialized = true
            peakRSSI = newestRSSI
            minimumRSSI = newestRSSI
            smoothedRSSI = Double(newestRSSI)
            averageRSSI = Double(newestRSSI)
            observationCount = 1
            trend = .stable
            return
        }

        observationCount += 1
        peakRSSI = max(peakRSSI, newestRSSI)
        minimumRSSI = min(minimumRSSI, newestRSSI)
        smoothedRSSI = alpha * Double(newestRSSI) + (1.0 - alpha) * smoothedRSSI
        averageRSSI += (Double(newestRSSI) - averageRSSI) / Double(observationCount)

        let delta = smoothedRSSI - previousSmoothed
        if delta >= 1.5 {
            trend = .rising
        } else if delta <= -1.5 {
            trend = .falling
        } else {
            trend = .stable
        }
    }
}

private extension ScannerStatus {
    static let nativeMac = NativeMacScannerTransport.makeStatus(
        state: "stopped",
        mode: .dual,
        phase: nil,
        uptimeMilliseconds: 0,
        wifiNetworksSeen: 0,
        bleAdvertisementsSeen: 0,
        trackedDevices: 0,
        matchingDevices: 0,
        droppedObservations: 0
    )
}
