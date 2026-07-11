import Foundation

final class SerialLineDecoder {
    private var buffer = Data()
    private let maximumLineLength: Int
    private(set) var didDiscardOversizedLine = false

    init(maximumLineLength: Int = 16 * 1024) {
        self.maximumLineLength = maximumLineLength
    }

    func append(_ data: Data) -> [String] {
        didDiscardOversizedLine = false
        guard !data.isEmpty else {
            return []
        }

        buffer.append(data)
        if buffer.count > maximumLineLength {
            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                buffer.removeSubrange(0 ... newlineIndex)
            } else {
                buffer.removeAll(keepingCapacity: true)
            }
            didDiscardOversizedLine = true
        }

        var lines: [String] = []
        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.prefix(upTo: newlineIndex)
            buffer.removeSubrange(0 ... newlineIndex)

            var cleaned = Data(lineData)
            if cleaned.last == 0x0D {
                cleaned.removeLast()
            }

            guard !cleaned.isEmpty else {
                continue
            }

            if let line = String(data: cleaned, encoding: .utf8), !line.isEmpty {
                lines.append(line)
            }
        }

        return lines
    }

    func reset() {
        buffer.removeAll(keepingCapacity: true)
        didDiscardOversizedLine = false
    }
}
