import Foundation

/// One-shot awaitable used by the BLE layer: an operation issues a GATT call,
/// stores a `Waiter`, and awaits its completion with a timeout. The delegate
/// (on the dedicated serial queue) or a timeout task completes it — whichever
/// happens first wins; later completions are ignored.
///
/// `nonisolated` so both the MainActor code and the CoreBluetooth delegate
/// plumbing can use it.
nonisolated final class AsyncWaiter<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var result: Result<T, Error>?

    /// Waits for the value or `timeoutSeconds`, whichever comes first.
    func wait(timeoutSeconds: Double, timeoutError: @escaping @Sendable () -> Error) async throws -> T {
        let timer = Task { [weak self] in
            if (try? await Task.sleep(nanoseconds: UInt64(max(0, timeoutSeconds) * 1_000_000_000))) != nil {
                self?.fail(timeoutError())
            }
        }
        defer { timer.cancel() }
        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let result {
                lock.unlock()
                continuation.resume(with: result)
                return
            }
            self.continuation = continuation
            lock.unlock()
        }
    }

    func complete(_ value: T) {
        lock.lock()
        if continuation == nil && result == nil {
            result = .success(value)
            lock.unlock()
            return
        }
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }

    func fail(_ error: Error) {
        lock.lock()
        if continuation == nil && result == nil {
            result = .failure(error)
            lock.unlock()
            return
        }
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(throwing: error)
    }
}
