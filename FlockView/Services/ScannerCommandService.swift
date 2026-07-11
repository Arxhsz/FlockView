import Foundation

enum ScanControlState: Equatable, Sendable {
    case idle
    case starting
    case scanning
    case stopping
    case stopped
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .starting, .stopping:
            true
        default:
            false
        }
    }

    var buttonLabel: String {
        switch self {
        case .starting:
            "Starting…"
        case .stopping:
            "Stopping…"
        case .scanning:
            "Stop Scan"
        case .stopped, .idle, .failed:
            "Start Scan"
        }
    }

    var buttonSymbol: String {
        switch self {
        case .starting:
            "hourglass"
        case .stopping:
            "hourglass"
        case .scanning:
            "stop.fill"
        default:
            "play.fill"
        }
    }
}

actor ScannerCommandQueue {
    enum Priority: Int, Comparable, Sendable {
        case ping = 0
        case status = 1
        case configuration = 2
        case mode = 3
        case start = 4
        case stop = 5

        static func < (lhs: Priority, rhs: Priority) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        static func from(_ command: ScannerCommand) -> Priority {
            switch command {
            case .stop:
                .stop
            case .start:
                .start
            case .setMode:
                .mode
            case .status:
                .status
            case .ping:
                .ping
            default:
                .configuration
            }
        }
    }

    private struct QueuedCommand {
        let command: ScannerCommand
        let priority: Priority
        let timeoutNanoseconds: UInt64
        let write: @Sendable () throws -> Void
        let continuation: CheckedContinuation<ScannerCommandResponse, Error>
    }

    private var backlog: [QueuedCommand] = []
    private var inFlight: QueuedCommand?
    private var timeoutTask: Task<Void, Never>?
    private(set) var depth: Int = 0

    var hasInFlightCommand: Bool {
        inFlight != nil
    }

    var hasHigherPriorityWorkThanPing: Bool {
        if let inFlight, inFlight.priority > .ping {
            return true
        }
        return backlog.contains { $0.priority > .ping }
    }

    func perform(
        _ command: ScannerCommand,
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        write: @escaping @Sendable () throws -> Void
    ) async throws -> ScannerCommandResponse {
        let priority = Priority.from(command)
        if command == .ping, hasHigherPriorityWorkThanPing || inFlight?.command == .ping {
            throw ScannerTransportError.commandRejected("heartbeat deferred")
        }

        return try await withCheckedThrowingContinuation { continuation in
            let item = QueuedCommand(
                command: command,
                priority: priority,
                timeoutNanoseconds: timeoutNanoseconds,
                write: write,
                continuation: continuation
            )
            insert(item)
            depth = backlog.count + (inFlight == nil ? 0 : 1)
            startNextIfNeeded()
        }
    }

    func resolve(_ response: ScannerCommandResponse) {
        guard let current = inFlight, current.command.responseCommand == response.command else {
            return
        }

        timeoutTask?.cancel()
        timeoutTask = nil
        inFlight = nil
        depth = backlog.count

        if response.ok {
            current.continuation.resume(returning: response)
        } else {
            current.continuation.resume(throwing: ScannerTransportError.commandRejected(response.message))
        }

        startNextIfNeeded()
    }

    func cancelAll(reason: ScannerTransportError = .connectionLost) {
        timeoutTask?.cancel()
        timeoutTask = nil

        if let current = inFlight {
            inFlight = nil
            current.continuation.resume(throwing: reason)
        }

        for item in backlog {
            item.continuation.resume(throwing: reason)
        }
        backlog.removeAll()
        depth = 0
    }

    private func insert(_ item: QueuedCommand) {
        if let index = backlog.firstIndex(where: { item.priority > $0.priority }) {
            backlog.insert(item, at: index)
        } else {
            backlog.append(item)
        }
    }

    private func startNextIfNeeded() {
        guard inFlight == nil, !backlog.isEmpty else {
            depth = backlog.count
            return
        }

        let item = backlog.removeFirst()
        inFlight = item
        depth = backlog.count + 1

        timeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: item.timeoutNanoseconds)
            } catch {
                return
            }
            await self?.timeoutCurrent()
        }

        do {
            try item.write()
        } catch {
            timeoutTask?.cancel()
            timeoutTask = nil
            inFlight = nil
            depth = backlog.count
            item.continuation.resume(throwing: error)
            startNextIfNeeded()
        }
    }

    private func timeoutCurrent() {
        guard let current = inFlight else {
            return
        }

        timeoutTask = nil
        inFlight = nil
        depth = backlog.count
        current.continuation.resume(throwing: ScannerTransportError.commandTimeout(current.command.responseCommand))
        startNextIfNeeded()
    }
}
