import Foundation

/// Serializes notification side effects while allowing the latest request to
/// invalidate stale reads/adds across suspension points. Disabling submits
/// through the same queue, so it returns only after older adds have settled
/// and the latest cleanup has completed.
@MainActor
final class DrinkReminderQueue {
    @MainActor
    final class Lease {
        private(set) var isCurrent = true
        fileprivate func invalidate() { isCurrent = false }
    }

    private var tail: Task<Void, Never>?
    private var latest: Lease?

    func submit(_ operation: @escaping @MainActor (Lease) async -> Void) async {
        latest?.invalidate()
        let lease = Lease()
        latest = lease
        let previous = tail
        let task = Task { @MainActor in
            await previous?.value
            guard lease.isCurrent else { return }
            await operation(lease)
        }
        tail = task
        await task.value
        if latest === lease { tail = nil }
    }
}
