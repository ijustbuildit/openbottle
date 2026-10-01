import Foundation
import Testing

@testable import HydroCap

@Suite("Background run policy")
struct BackgroundRunPolicyTest {

    @Test func runsOnlyWhenPairedEnabledAndPermitted() {
        #expect(BackgroundRunPolicy.skipReason(hasPairedDevice: true, backgroundSyncEnabled: true, hasBLEPermissions: true) == nil)
        #expect(BackgroundRunPolicy.skipReason(hasPairedDevice: false, backgroundSyncEnabled: true, hasBLEPermissions: true) == .notPaired)
        #expect(BackgroundRunPolicy.skipReason(hasPairedDevice: true, backgroundSyncEnabled: false, hasBLEPermissions: true) == .disabled)
        #expect(BackgroundRunPolicy.skipReason(hasPairedDevice: true, backgroundSyncEnabled: true, hasBLEPermissions: false) == .permissionsMissing)
        // Not paired wins over everything else: nothing to sync at all.
        #expect(BackgroundRunPolicy.skipReason(hasPairedDevice: false, backgroundSyncEnabled: false, hasBLEPermissions: false) == .notPaired)
        // Log spellings match the Kotlin port.
        #expect(BackgroundRunPolicy.SkipReason.notPaired.label == "NOT_PAIRED")
        #expect(BackgroundRunPolicy.SkipReason.disabled.label == "DISABLED")
        #expect(BackgroundRunPolicy.SkipReason.permissionsMissing.label == "PERMISSIONS_MISSING")
    }

    @Test func exceptionsAreClassifiedByType() {
        #expect(BackgroundRunPolicy.classify(CapBusyError()) == .busy)
        #expect(BackgroundRunPolicy.classify(CapNotFoundError("cap 'LARQ_x' not found within 30 s")) == .capNotFound)
        #expect(BackgroundRunPolicy.classify(SyncError("GATT 133")) == .failed(reason: "GATT 133"))
        #expect(BackgroundRunPolicy.classify(NusRequestError("RequestGetCapUiState timed out")) == .failed(reason: "RequestGetCapUiState timed out"))
        #expect(BackgroundRunPolicy.classify(BleConnectionError("connect failed, status 133")) == .failed(reason: "connect failed, status 133"))
        // Anything else falls back to the type name (Android: javaClass.simpleName).
        struct IllegalStateError: Error {}
        #expect(BackgroundRunPolicy.classify(IllegalStateError()) == .failed(reason: "IllegalStateError"))
    }

    @Test func aSuccessfulSyncResetsTheMissStreak() {
        let evaluation = BackgroundRunPolicy.evaluate(.synced(newTofEntries: 3, drinkEvents: 10, batteryPercent: 42), previousMisses: 2)
        #expect(evaluation.verdict == .success)
        #expect(evaluation.consecutiveMisses == 0)
        #expect(!evaluation.quiet)
    }

    @Test func capNotFoundIsASuccessThatCountsAMissAndGoesQuietAfterThree() {
        let first = BackgroundRunPolicy.evaluate(.capNotFound, previousMisses: 0)
        #expect(first.verdict == .success)
        #expect(first.consecutiveMisses == 1)
        #expect(!first.quiet)

        let second = BackgroundRunPolicy.evaluate(.capNotFound, previousMisses: first.consecutiveMisses)
        #expect(!second.quiet)

        let third = BackgroundRunPolicy.evaluate(.capNotFound, previousMisses: second.consecutiveMisses)
        #expect(third.consecutiveMisses == 3)
        #expect(third.quiet)
        #expect(third.verdict == .success)

        let fourth = BackgroundRunPolicy.evaluate(.capNotFound, previousMisses: third.consecutiveMisses)
        #expect(fourth.quiet)
        #expect(fourth.consecutiveMisses == 4)
    }

    @Test func otherFailuresNeverRetryAndDoNotCountAsMisses() {
        let evaluation = BackgroundRunPolicy.evaluate(.failed(reason: "GATT 133"), previousMisses: 2)
        #expect(evaluation.verdict == .success)
        #expect(evaluation.consecutiveMisses == 0)
        #expect(!evaluation.quiet)
    }

    @Test func onlyAConcurrentCapJobTriggersARetryAndKeepsTheStreak() {
        let evaluation = BackgroundRunPolicy.evaluate(.busy, previousMisses: 2)
        #expect(evaluation.verdict == .retry)
        #expect(evaluation.consecutiveMisses == 2)
        #expect(!evaluation.quiet)
    }

    @Test func labelsAreShortAndInformative() {
        #expect(BackgroundRunPolicy.Outcome.synced(newTofEntries: 3, drinkEvents: 10, batteryPercent: 42).label() == "synced: 3 new readings, 10 drinks, battery 42 %")
        #expect(BackgroundRunPolicy.Outcome.synced(newTofEntries: 0, drinkEvents: 0, batteryPercent: nil).label() == "synced: 0 new readings, 0 drinks, battery n/a")
        #expect(BackgroundRunPolicy.Outcome.capNotFound.label() == "cap not found")
        #expect(BackgroundRunPolicy.Outcome.busy.label() == "another cap job was running, retried")
        #expect(BackgroundRunPolicy.Outcome.failed(reason: "boom").label() == "failed: boom")
    }
}
