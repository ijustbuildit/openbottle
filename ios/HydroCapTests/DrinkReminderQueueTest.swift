import Foundation
import Testing
@testable import HydroCap

@Suite("Drink reminder scheduling ownership")
@MainActor
struct DrinkReminderQueueTest {
    struct Timeout: Error {}

    @Test func disableWaitsForInflightAddThenRemovesIt() async throws {
        let queue = DrinkReminderQueue()
        let addStarted = AsyncWaiter<Void>()
        let finishAdd = AsyncWaiter<Void>()
        let disableStarted = AsyncWaiter<Void>()
        var pending: [String] = []
        var disableFinished = false
        let older = Task { @MainActor in
            await queue.submit { lease in
                addStarted.complete(())
                try? await finishAdd.wait(timeoutSeconds: 1) { Timeout() }
                // Represents an OS add already in flight when disabled.
                pending.append("old")
                if lease.isCurrent { pending.append("must-not-add-rest") }
            }
        }
        try await addStarted.wait(timeoutSeconds: 1) { Timeout() }
        let disable = Task { @MainActor in
            disableStarted.complete(())
            await queue.submit { _ in pending.removeAll() }
            disableFinished = true
        }
        try await disableStarted.wait(timeoutSeconds: 1) { Timeout() }
        #expect(!disableFinished)
        finishAdd.complete(())
        await older.value
        await disable.value
        #expect(disableFinished)
        #expect(pending.isEmpty)
    }

    @Test func latestSettingsSupersedeAnOlderRead() async throws {
        let queue = DrinkReminderQueue()
        let readStarted = AsyncWaiter<Void>()
        let finishRead = AsyncWaiter<Void>()
        let latestStarted = AsyncWaiter<Void>()
        var pending: [String] = []
        let old = Task { @MainActor in
            await queue.submit { lease in
                readStarted.complete(())
                try? await finishRead.wait(timeoutSeconds: 1) { Timeout() }
                if lease.isCurrent { pending = ["stale"] }
            }
        }
        try await readStarted.wait(timeoutSeconds: 1) { Timeout() }
        let latest = Task { @MainActor in
            latestStarted.complete(())
            await queue.submit { _ in pending = ["latest"] }
        }
        try await latestStarted.wait(timeoutSeconds: 1) { Timeout() }
        finishRead.complete(())
        await old.value
        await latest.value
        #expect(pending == ["latest"])
    }
}
