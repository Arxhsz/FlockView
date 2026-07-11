import Darwin
import Dispatch
import Foundation

final class SerialScannerTransport: ScannerTransport {
    private let observationPipe = AsyncStream<ScannerObservation>.makeStream()
    private let statusPipe = AsyncStream<ScannerStatus>.makeStream()
    private let connectionPipe = AsyncStream<ScannerConnectionState>.makeStream()
    private let responsePipe = AsyncStream<ScannerCommandResponse>.makeStream()
    private let errorPipe = AsyncStream<ScannerTransportError>.makeStream()
    private let diagnosticsPipe = AsyncStream<ScannerDiagnostics>.makeStream()

    private let discovery = SerialPortDiscoveryService()
    private let persistence = ConnectionPersistenceService()
    private let eventDecoder = ScannerEventDecoder()
    private let commandQueue = ScannerCommandQueue()
    private let lineDecoder = SerialLineDecoder()
    private let baudRate = 115200

    private var fd: Int32 = -1
    private var readTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var diagnostics = ScannerDiagnostics()
    private var selectedDevice: SerialDevice?
    private var capabilities: ScannerCapabilities?
    private var sawValidScannerEvent = false
    private var lastStatus: ScannerStatus?
    private var manuallyDisconnected = false
    private var consecutivePingFailures = 0
    private var pingInFlight = false
    private let stateQueue = DispatchQueue(
        label: "com.flockview.serial-scanner-transport.state"
    )

    var observationStream: AsyncStream<ScannerObservation> { observationPipe.stream }
    var statusStream: AsyncStream<ScannerStatus> { statusPipe.stream }
    var connectionStream: AsyncStream<ScannerConnectionState> { connectionPipe.stream }
    var responseStream: AsyncStream<ScannerCommandResponse> { responsePipe.stream }
    var errorStream: AsyncStream<ScannerTransportError> { errorPipe.stream }
    var diagnosticsStream: AsyncStream<ScannerDiagnostics> { diagnosticsPipe.stream }

    deinit {
        readTask?.cancel()
        heartbeatTask?.cancel()
        closeFD()
    }

    func availableDevices() async -> [SerialDevice] {
        discovery.availableDevices()
    }

    func connect(to device: SerialDevice) async throws {
        manuallyDisconnected = false
        selectedDevice = device
        capabilities = nil
        stateQueue.sync {
            sawValidScannerEvent = false
            lastStatus = nil
            consecutivePingFailures = 0
        }
        lineDecoder.reset()
        updateDiagnostics { diagnostics in
            diagnostics = ScannerDiagnostics(
                connectionStateDescription: "Connecting",
                selectedDevice: device,
                baudRate: baudRate
            )
        }

        connectionPipe.continuation.yield(.connecting(device))
        try open(device: device)
        connectionPipe.continuation.yield(.handshaking(device))

        readTask?.cancel()
        let readFD = fd
        readTask = Task { [weak self] in
            await self?.readLoop(fd: readFD)
        }

        // Wait 1.2 seconds for the ESP32 to boot and emit the boot JSON event
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        // Note: We intentionally DO NOT call tcflush here to avoid discarding 
        // the boot event printed by the ESP32 during its startup.

        do {
            _ = try await sendAndWait(.ping, timeoutNanoseconds: 5_000_000_000)
        } catch {
            let sawEvent = stateQueue.sync { sawValidScannerEvent }
            if !sawEvent {
                throw await failHandshake(error)
            }
        }

        do {
            _ = try await sendAndWait(.status, timeoutNanoseconds: 4_000_000_000)
        } catch {
            let sawEvent = stateQueue.sync { sawValidScannerEvent }
            if !sawEvent {
                throw await failHandshake(error)
            }
        }

        let resolvedCapabilities = capabilities ?? .unknown
        guard resolvedCapabilities.firmware == "FlockViewScanner" || capabilities == nil else {
            throw ScannerTransportError.incompatibleFirmware(resolvedCapabilities.firmware)
        }
        if capabilities != nil, !resolvedCapabilities.passiveOnly {
            throw ScannerTransportError.incompatibleFirmware("passive_only was false")
        }

        persistence.save(device: device)
        updateDiagnostics { diagnostics in
            diagnostics.connectionStateDescription = "Connected"
            diagnostics.firmwareVersion = resolvedCapabilities.firmwareVersion
            diagnostics.board = resolvedCapabilities.board
        }
        connectionPipe.continuation.yield(.connected(device, resolvedCapabilities))
        startHeartbeat()
    }

    func disconnect() async {
        manuallyDisconnected = true
        readTask?.cancel()
        readTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        await commandQueue.cancelAll()
        closeFD()
        updateDiagnostics { diagnostics in
            diagnostics.connectionStateDescription = "Disconnected"
        }
        connectionPipe.continuation.yield(.disconnected)
    }

    func startScan() async throws {
        let isScanning = stateQueue.sync { lastStatus?.isScanning == true }
        if isScanning {
            return
        }

        _ = try await sendAndWait(.start, timeoutNanoseconds: 4_000_000_000)

        stateQueue.sync {
            if lastStatus != nil {
                lastStatus?.state = "scanning"
            }
        }
    }

    func stopScan() async throws {
        let isScanning = stateQueue.sync { lastStatus?.isScanning == true }
        if !isScanning {
            return
        }

        _ = try await sendAndWait(.stop, timeoutNanoseconds: 4_000_000_000)

        stateQueue.sync {
            if lastStatus != nil {
                lastStatus?.state = "stopped"
            }
        }
    }

    func send(_ command: ScannerCommand) async throws {
        _ = try await sendAndWait(command)
    }

    func reconnectLastDevice() async throws {
        guard let saved = persistence.loadDevice() else {
            throw ScannerTransportError.noDeviceSelected
        }
        let devices = await availableDevices()
        let device = devices.first { candidate in
            candidate.serialNumber == saved.serialNumber && candidate.serialNumber != nil
        } ?? devices.first { $0.id == saved.id } ?? devices.first { $0.path == saved.path } ?? saved
        try await connect(to: device)
    }

    private func failHandshake(_ error: Error) async -> ScannerTransportError {
        await disconnect()
        if let scannerError = error as? ScannerTransportError {
            return scannerError
        }
        return .handshakeTimeout
    }

    private func open(device: SerialDevice) throws {
        closeFD()
        let newFD = Darwin.open(device.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard newFD >= 0 else {
            if errno == EACCES || errno == EPERM {
                throw ScannerTransportError.permissionDenied
            }
            throw ScannerTransportError.openFailed(String(cString: strerror(errno)))
        }

        var options = termios()
        guard tcgetattr(newFD, &options) == 0 else {
            Darwin.close(newFD)
            throw ScannerTransportError.configureFailed(String(cString: strerror(errno)))
        }

        cfmakeraw(&options)
        cfsetspeed(&options, speed_t(B115200))
        options.c_cflag |= UInt(CLOCAL | CREAD)
        options.c_cflag &= ~UInt(PARENB)
        options.c_cflag &= ~UInt(CSTOPB)
        options.c_cflag &= ~UInt(CSIZE)
        options.c_cflag |= UInt(CS8)
        options.c_cflag &= ~UInt(CRTSCTS)
        options.c_cc.16 = 0 // VMIN
        options.c_cc.17 = 1 // VTIME

        guard tcsetattr(newFD, TCSANOW, &options) == 0 else {
            Darwin.close(newFD)
            throw ScannerTransportError.configureFailed(String(cString: strerror(errno)))
        }

        // Reset sequence and RTS/DTR control approach informed by the serial protocol
        // patterns and reset handling documented in colonelpanichacks/flock-you.
        // This is an original Swift implementation for FlockView.
        // EN = Chip PU (reset), GPIO0 = Boot mode.
        // Transistor cross-coupling rules:
        // - RTS=1, DTR=0: EN=0 (reset), GPIO0=1 (normal run)
        // - RTS=0, DTR=0: EN=1 (normal run), GPIO0=1 (normal run)
        var flags: Int32 = 0
        if ioctl(newFD, TIOCMGET, &flags) == 0 {
            // Set RTS=1 and DTR=0 to pull EN low (reset state)
            flags |= TIOCM_RTS
            flags &= ~TIOCM_DTR
            _ = ioctl(newFD, TIOCMSET, &flags)
            
            // Hold reset for 100 milliseconds
            usleep(100_000)
            
            // Set RTS=0 and DTR=0 to release EN high (normal run boot state)
            flags &= ~TIOCM_RTS
            flags &= ~TIOCM_DTR
            _ = ioctl(newFD, TIOCMSET, &flags)
        }

        fd = newFD
    }

    private func sendAndWait(_ command: ScannerCommand, timeoutNanoseconds: UInt64 = 2_000_000_000) async throws -> ScannerCommandResponse {
        updateDiagnostics { diagnostics in
            diagnostics.append(
                DiagnosticEvent(
                    date: Date(),
                    kind: "command_sent",
                    summary: command.responseCommand,
                    raw: nil
                )
            )
        }
        let response = try await commandQueue.perform(command, timeoutNanoseconds: timeoutNanoseconds) { [weak self] in
            guard let self else {
                throw ScannerTransportError.deviceUnavailable
            }
            try self.write(command.serialString)
        }
        updateDiagnostics { diagnostics in
            diagnostics.commandCount += 1
        }
        return response
    }

    private func write(_ string: String) throws {
        guard fd >= 0 else {
            throw ScannerTransportError.deviceUnavailable
        }
        guard let data = string.data(using: .utf8) else {
            return
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            let result: Int = stateQueue.sync {
                Darwin.write(fd, baseAddress, data.count)
            }
            guard result == data.count else {
                throw ScannerTransportError.writeFailed(String(cString: strerror(errno)))
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                } catch {
                    break
                }
                await self?.sendHeartbeatIfNeeded()
            }
        }
    }

    private func sendHeartbeatIfNeeded() async {
        guard fd >= 0, !manuallyDisconnected else {
            return
        }

        let shouldSkip = await commandQueue.hasHigherPriorityWorkThanPing
        let canPing = stateQueue.sync { () -> Bool in
            if pingInFlight { return false }
            pingInFlight = true
            return true
        }
        guard !shouldSkip, canPing else { return }
        defer { stateQueue.sync { pingInFlight = false } }

        do {
            _ = try await sendAndWait(.ping, timeoutNanoseconds: 3_000_000_000)
            stateQueue.sync { consecutivePingFailures = 0 }
            updateDiagnostics { diagnostics in
                diagnostics.append(
                    DiagnosticEvent(
                        date: Date(),
                        kind: "ping_success",
                        summary: "pong",
                        raw: nil
                    )
                )
            }
        } catch let error as ScannerTransportError where error.isHeartbeatDeferred {
            return
        } catch {
            let failures = stateQueue.sync { () -> Int in
                consecutivePingFailures += 1
                return consecutivePingFailures
            }
            updateDiagnostics { diagnostics in
                diagnostics.append(
                    DiagnosticEvent(
                        date: Date(),
                        kind: "ping_timeout",
                        summary: "failure \(failures)",
                        raw: nil
                    )
                )
            }

            if failures >= 3, !manuallyDisconnected {
                errorPipe.continuation.yield(.connectionLost)
                connectionPipe.continuation.yield(.failed(message: "Connection lost"))
                await disconnect()
            }
        }
    }

    private func readLoop(fd readFD: Int32) async {
        var bytes = [UInt8](repeating: 0, count: 4096)
        while !Task.isCancelled {
            let count = Darwin.read(readFD, &bytes, bytes.count)
            if count > 0 {
                let data = Data(bytes.prefix(count))
                stateQueue.sync {
                    diagnostics.bytesReceived += UInt64(count)
                }
                let lines = lineDecoder.append(data)
                if lineDecoder.didDiscardOversizedLine {
                    stateQueue.sync {
                        diagnostics.malformedLineCount += 1
                    }
                    errorPipe.continuation.yield(.oversizedSerialLine)
                }
                for line in lines {
                    await handle(line: line)
                }
            } else if count == 0 {
                try? await Task.sleep(nanoseconds: 20_000_000)
            } else if errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR {
                try? await Task.sleep(nanoseconds: 20_000_000)
            } else {
                if !manuallyDisconnected {
                    errorPipe.continuation.yield(.connectionLost)
                    connectionPipe.continuation.yield(.failed(message: "Connection lost"))
                }
                return
            }
        }
    }

    private func handle(line: String) async {
        do {
            let decoded = try eventDecoder.decode(line: line)
            noteValidEvent()
            stateQueue.sync {
                diagnostics.validJSONLineCount += 1
                diagnostics.lastValidEventDate = Date()
                diagnostics.schemaVersion = 1
            }

            switch decoded {
            case .boot(let boot, let raw):
                capabilities = boot.capabilities
                stateQueue.sync {
                    diagnostics.firmwareVersion = boot.firmwareVersion
                    diagnostics.board = boot.board
                    diagnostics.append(
                        DiagnosticEvent(
                            date: Date(),
                            kind: "boot",
                            summary: boot.firmwareVersion,
                            raw: raw
                        )
                    )
                }
            case .detection(let observation):
                observationPipe.continuation.yield(observation)
                stateQueue.sync {
                    diagnostics.append(
                        DiagnosticEvent(
                            date: Date(),
                            kind: "detection",
                            summary: observation.deviceID,
                            raw: observation.rawEvent
                        )
                    )
                }
            case .status(let status, let raw):
                stateQueue.sync {
                    lastStatus = status
                    diagnostics.queueDepth = status.queueDepth
                    diagnostics.droppedFirmwareObservations = status.droppedObservations
                    diagnostics.freeHeap = status.freeHeap
                    diagnostics.append(
                        DiagnosticEvent(
                            date: Date(),
                            kind: "scanner_status",
                            summary: status.state,
                            raw: raw
                        )
                    )
                }
                statusPipe.continuation.yield(status)
            case .commandResponse(let response, let raw):
                responsePipe.continuation.yield(response)
                await commandQueue.resolve(response)
                stateQueue.sync {
                    diagnostics.append(
                        DiagnosticEvent(
                            date: Date(),
                            kind: "command_response",
                            summary: "\(response.command): \(response.ok)",
                            raw: raw
                        )
                    )
                }
            case .firmwareError(let event, let raw):
                stateQueue.sync {
                    diagnostics.append(
                        DiagnosticEvent(
                            date: Date(),
                            kind: "error",
                            summary: event.message,
                            raw: raw
                        )
                    )
                }
            case .debug(let event, let raw):
                stateQueue.sync {
                    diagnostics.append(
                        DiagnosticEvent(
                            date: Date(),
                            kind: "debug",
                            summary: event.message,
                            raw: raw
                        )
                    )
                }
            case .unknown(let event, let raw):
                stateQueue.sync {
                    diagnostics.unknownEventCount += 1
                    diagnostics.append(
                        DiagnosticEvent(
                            date: Date(),
                            kind: "unknown",
                            summary: event,
                            raw: raw
                        )
                    )
                }
            }

            publishDiagnostics()
        } catch {
            updateDiagnostics { diagnostics in
                diagnostics.malformedLineCount += 1
                diagnostics.append(
                    DiagnosticEvent(
                        date: Date(),
                        kind: "malformed",
                        summary: "Invalid JSON",
                        raw: line
                    )
                )
            }
            publishDiagnostics()
            errorPipe.continuation.yield(.malformedJSON(line))
        }
    }

    private func noteValidEvent() {
        stateQueue.sync {
            sawValidScannerEvent = true
            consecutivePingFailures = 0
        }
    }

    private func closeFD() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }

    private func publishDiagnostics() {
        let snapshot = stateQueue.sync { () -> ScannerDiagnostics in
            diagnostics.selectedDevice = selectedDevice
            return diagnostics
        }
        diagnosticsPipe.continuation.yield(snapshot)
    }

    private func updateDiagnostics(
        _ update: (inout ScannerDiagnostics) -> Void
    ) {
        let snapshot = stateQueue.sync { () -> ScannerDiagnostics in
            update(&diagnostics)
            diagnostics.selectedDevice = selectedDevice
            return diagnostics
        }
        diagnosticsPipe.continuation.yield(snapshot)
    }
}

private extension ScannerTransportError {
    var isHeartbeatDeferred: Bool {
        if case .commandRejected(let message) = self {
            return message.contains("heartbeat deferred")
        }
        return false
    }
}
