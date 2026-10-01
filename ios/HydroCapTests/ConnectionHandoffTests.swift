import Foundation
import Testing
@testable import HydroCap

@MainActor
@Suite("Connection handoff")
struct ConnectionHandoffTests {
    private enum Failure: Error { case connection, logImport }

    /// Deterministic suspension, not a timed sleep or a fake success stub.
    @MainActor
    private final class Gate {
        private var opened = false
        private var waiters: [CheckedContinuation<Void, Never>] = []
        func wait() async {
            if opened { return }
            await withCheckedContinuation { waiters.append($0) }
        }
        func open() {
            opened = true
            let pending = waiters
            waiters = []
            pending.forEach { $0.resume() }
        }
    }

    private var identity: ConnectedCapIdentity {
        ConnectedCapIdentity(name: "LARQ_test", advertisedId: "stable-id", serial: "DIS-serial")!
    }

    @Test func readyNavigatesBeforeBlockedImportAndCallerCancellationDoesNotStopJob() async {
        let job = ConnectionHandoff()
        let connecting = Gate(), readyAllowed = Gate(), importing = Gate(), finishImport = Gate()
        var events: [String] = []
        var persisted: ConnectedCapIdentity?
        var home = false
        var completed = false
        let identity = identity
        let caller = Task { @MainActor in
            await job.run(operation: { ready in
                events.append("connect")
                connecting.open()
                await readyAllowed.wait()
                events.append("notifications+DIS")
                ready(identity)
                events.append("first-log-request")
                importing.open()
                await finishImport.wait()
                try Task.checkCancellation()
                events.append("import-complete")
            }, onReady: {
                persisted = $0
                home = true
                events.append("persist+home+notice")
            }, onFailure: { _, _ in
                Issue.record("Caller/view cancellation must not cancel the import")
            }, onFinished: {
                completed = true
                events.append("cleanup+reconcile")
            })
        }
        await connecting.wait()
        #expect(job.isRunning)
        #expect(persisted == nil)
        #expect(!home)
        await job.run(operation: { _ in
            Issue.record("A second tap during connection must not start a job")
        }, onReady: { _ in
            Issue.record("A duplicate must not publish readiness")
        }, onFailure: { _, _ in
            Issue.record("A duplicate must not disturb the first attempt")
        }, onFinished: {
            Issue.record("A duplicate must not clear the first attempt's state")
        })
        readyAllowed.open()
        await importing.wait()
        #expect(persisted == identity)
        #expect(home)
        #expect(!completed)
        #expect(job.isRunning)
        #expect(events == ["connect", "notifications+DIS", "persist+home+notice", "first-log-request"])
        caller.cancel() // scan disappearance/caller cancellation
        finishImport.open()
        await caller.value
        #expect(completed)
        #expect(!job.isRunning)
        #expect(events.suffix(2) == ["import-complete", "cleanup+reconcile"])
    }

    @Test func failureBeforeReadyDoesNotPersistAndReleasesJobForRetry() async {
        let job = ConnectionHandoff()
        var saved: ConnectedCapIdentity?
        var failureWasAfterReady: Bool?
        var cleanups = 0
        await job.run(operation: { _ in throw Failure.connection }, onReady: { saved = $0 }, onFailure: { _, ready in
            failureWasAfterReady = ready
        }, onFinished: { cleanups += 1 })
        #expect(saved == nil)
        #expect(failureWasAfterReady == false)
        #expect(cleanups == 1)
        #expect(!job.isRunning)
        await job.run(operation: { ready in ready(identity) }, onReady: { saved = $0 }, onFailure: { _, _ in
            Issue.record("Retry unexpectedly failed")
        }, onFinished: { cleanups += 1 })
        #expect(saved == identity)
        #expect(cleanups == 2)
        #expect(!job.isRunning)
    }

    @Test func laterImportFailureKeepsVerifiedPairingAndCleansUp() async {
        let job = ConnectionHandoff()
        var saved: ConnectedCapIdentity?
        var failureWasAfterReady: Bool?
        var cleaned = false
        await job.run(operation: { ready in
            ready(identity)
            throw Failure.logImport
        }, onReady: { saved = $0 }, onFailure: { _, ready in
            failureWasAfterReady = ready
        }, onFinished: { cleaned = true })
        #expect(saved == identity)
        #expect(failureWasAfterReady == true)
        #expect(cleaned)
        #expect(!job.isRunning)
    }

    @Test func duplicateTapAndDuplicateReadyDoNotStartAnotherJobOrNotice() async {
        let job = ConnectionHandoff()
        let importing = Gate(), finish = Gate()
        var starts = 0, notices = 0, cleanups = 0
        let caller = Task { @MainActor in
            await job.run(operation: { ready in
                starts += 1
                ready(identity)
                ready(identity)
                importing.open()
                await finish.wait()
            }, onReady: { _ in notices += 1 }, onFailure: { _, _ in
                Issue.record("Unexpected failure")
            }, onFinished: { cleanups += 1 })
        }
        await importing.wait()
        await job.run(operation: { _ in starts += 1 }, onReady: { _ in notices += 1 }, onFailure: { _, _ in
            Issue.record("Unexpected duplicate failure")
        }, onFinished: { cleanups += 1 })
        #expect(starts == 1)
        #expect(notices == 1)
        #expect(cleanups == 0)
        #expect(job.isRunning)
        finish.open()
        await caller.value
        #expect(cleanups == 1)
        #expect(!job.isRunning)
    }

    @Test func identityUsesAdvertisementThenDISThenNameNeverTransientAddress() {
        #expect(identity.deviceIdHex == "stable-id")
        #expect(ConnectedCapIdentity(name: "LARQ_test", advertisedId: nil, serial: "serial")?.deviceIdHex == "serial")
        #expect(ConnectedCapIdentity(name: "LARQ_test", advertisedId: nil, serial: nil)?.deviceIdHex == "LARQ_test")
        #expect(ConnectedCapIdentity(name: nil, advertisedId: nil, serial: "serial")?.name == "serial")
        #expect(ConnectedCapIdentity(name: nil, advertisedId: nil, serial: nil) == nil)
        #expect(ConnectedCapIdentity(name: "", advertisedId: "", serial: "") == nil)
    }
}
