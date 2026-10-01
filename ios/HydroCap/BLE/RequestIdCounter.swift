import Foundation

/// Monotonically increasing request id, one counter per app process
/// (fixed32 on the wire, so it wraps after 2^32-1 and skips 0 so that an unset
/// field is never mistaken for a real id).
nonisolated final class RequestIdCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt32

    init(start: UInt32 = 0) {
        value = start
    }

    func next() -> UInt32 {
        lock.lock()
        defer { lock.unlock() }
        value = value >= 0xFFFF_FFFF ? 1 : value + 1
        return value
    }

    var current: UInt32 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
