import Foundation

/// One line of the session debug log.
nonisolated struct DebugEntry: Sendable, Equatable {
    let timestampMs: Int64
    let tag: String
    let message: String

    func format() -> String {
        "\(DebugLog.timestampFormatter.string(from: Date(timeIntervalSince1970: Double(timestampMs) / 1000))) [\(tag)] \(message)"
    }
}

/// Process-wide debug log: in-memory ring (for the Debug screen) and an
/// append-only `Documents/debug-log.txt` rotated at 2 MB, so the first hardware
/// session can be driven over the `hydrocap://` URL hooks and inspected
/// afterwards. Free of UIKit so the tests and the pure logic can log too.
nonisolated final class DebugLog: @unchecked Sendable {
    static let file_name = "debug-log.txt"
    static let rotatedFileName = "debug-log.1.txt"
    static let maxFileBytes: Int64 = 2 * 1024 * 1024
    static let maxMemoryEntriesDefault = 4_000

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    private let lock = NSLock()
    private var buffer: [DebugEntry] = []
    private var subscribers: [UUID: AsyncStream<[DebugEntry]>.Continuation] = [:]
    private let directory: URL?
    private let maxMemoryEntries: Int

    init(directory: URL?, maxMemoryEntries: Int = DebugLog.maxMemoryEntriesDefault) {
        self.directory = directory
        self.maxMemoryEntries = maxMemoryEntries
    }

    var fileURL: URL? { directory?.appendingPathComponent(DebugLog.file_name) }

    func entries() -> [DebugEntry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func log(_ tag: String, _ message: String) {
        let entry = DebugEntry(timestampMs: Int64(Date().timeIntervalSince1970 * 1000), tag: tag, message: message)
        var snapshot: [DebugEntry] = []
        var continuations: [AsyncStream<[DebugEntry]>.Continuation] = []
        lock.lock()
        if buffer.count >= maxMemoryEntries {
            buffer.removeFirst(buffer.count - maxMemoryEntries + 1)
        }
        buffer.append(entry)
        snapshot = buffer
        continuations = Array(subscribers.values)
        lock.unlock()
        for continuation in continuations { continuation.yield(snapshot) }
        appendToFile(entry)
    }

    func error(_ tag: String, _ message: String, error: Error? = nil) {
        let full: String
        if let error {
            full = "\(message): \(String(describing: type(of: error))): \(error)"
        } else {
            full = message
        }
        log(tag, "ERROR \(full)")
    }

    /// Clears the in-memory view only; the file keeps its history.
    func clearMemory() {
        var continuations: [AsyncStream<[DebugEntry]>.Continuation] = []
        lock.lock()
        buffer = []
        continuations = Array(subscribers.values)
        lock.unlock()
        for continuation in continuations { continuation.yield([]) }
    }

    func dumpText() -> String {
        entries().map { $0.format() }.joined(separator: "\n")
    }

    /// Live view of the entries for the Debug screen.
    func updates() -> AsyncStream<[DebugEntry]> {
        AsyncStream { continuation in
            let id = UUID()
            lock.lock()
            subscribers[id] = continuation
            let current = buffer
            lock.unlock()
            continuation.yield(current)
            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.subscribers.removeValue(forKey: id)
                self?.lock.unlock()
            }
        }
    }

    private func appendToFile(_ entry: DebugEntry) {
        guard let directory else { return }
        let file = directory.appendingPathComponent(DebugLog.file_name)
        do {
            if let size = try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber,
               size.int64Value > DebugLog.maxFileBytes
            {
                let rotated = directory.appendingPathComponent(DebugLog.rotatedFileName)
                try? FileManager.default.removeItem(at: rotated)
                try? FileManager.default.moveItem(at: file, to: rotated)
            }
            let line = Data((entry.format() + "\n").utf8)
            if FileManager.default.fileExists(atPath: file.path) {
                let handle = try FileHandle(forWritingTo: file)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: line)
            } else {
                try line.write(to: file)
            }
        } catch {
            // Never let logging break the app; the entry stays in memory.
        }
    }
}
