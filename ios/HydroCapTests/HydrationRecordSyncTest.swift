import Foundation
import Testing

@testable import HydroCap

/// Records every call; can be told to fail or report unavailability.
private final class FakeGateway: HydrationGateway, @unchecked Sendable {
    private let lock = NSLock()
    var unavailable: String?
    var insertBatches: [[HydrationWrite]] = []
    var deleteBatches: [[String]] = []
    var failInsertWith: HealthGatewayError?
    var failDeleteWith: HealthGatewayError?

    func unavailableReason() async -> String? { snapshotUnavailable() }

    func insert(_ records: [HydrationWrite]) async throws {
        if let failure = snapshotFailInsert() { throw failure }
        recordInsert(records)
    }

    func delete(clientRecordIds: [String]) async throws {
        if let failure = snapshotFailDelete() { throw failure }
        recordDelete(clientRecordIds)
    }

    var inserted: [HydrationWrite] { snapshotInserts().flatMap { $0 } }

    var deleted: [String] { snapshotDeletes().flatMap { $0 } }

    func clearInsertBatches() { removeInserts() }

    // MARK: - Synchronous state access (locks never sit in an async context)

    private func snapshotUnavailable() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return unavailable
    }

    private func snapshotFailInsert() -> HealthGatewayError? {
        lock.lock()
        defer { lock.unlock() }
        return failInsertWith
    }

    private func snapshotFailDelete() -> HealthGatewayError? {
        lock.lock()
        defer { lock.unlock() }
        return failDeleteWith
    }

    private func recordInsert(_ records: [HydrationWrite]) {
        lock.lock()
        insertBatches.append(records)
        lock.unlock()
    }

    private func recordDelete(_ records: [String]) {
        lock.lock()
        deleteBatches.append(records)
        lock.unlock()
    }

    private func snapshotInserts() -> [[HydrationWrite]] {
        lock.lock()
        defer { lock.unlock() }
        return insertBatches
    }

    private func snapshotDeletes() -> [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return deleteBatches
    }

    private func removeInserts() {
        lock.lock()
        insertBatches.removeAll()
        lock.unlock()
    }
}

/// In-memory `health_sync` table.
private final class FakeHealthSyncStore: HealthSyncStore, @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [Int64: HealthSyncRecord] = [:]

    var keys: Set<Int64> {
        lock.lock()
        defer { lock.unlock() }
        return Set(rows.keys)
    }

    func row(_ timestamp: Int64) -> HealthSyncRecord? {
        lock.lock()
        defer { lock.unlock() }
        return rows[timestamp]
    }

    func allHealthSyncRecords() async throws -> [HealthSyncRecord] { snapshot() }

    func upsertHealthSyncRecords(_ records: [HealthSyncRecord]) async throws { store(records) }

    func deleteHealthSyncRecords(timestamps: [Int64]) async throws { remove(timestamps) }

    func healthSyncRecordCount() async throws -> Int { snapshot().count }

    func deleteAllHealthSyncRecords() async throws { store([]) ; clear() }

    // MARK: - Synchronous state access

    private func snapshot() -> [HealthSyncRecord] {
        lock.lock()
        defer { lock.unlock() }
        return rows.values.sorted { $0.timestamp < $1.timestamp }
    }

    private func store(_ records: [HealthSyncRecord]) {
        lock.lock()
        defer { lock.unlock() }
        for record in records { rows[record.timestamp] = record }
    }

    private func remove(_ timestamps: [Int64]) {
        lock.lock()
        defer { lock.unlock() }
        for timestamp in timestamps { rows.removeValue(forKey: timestamp) }
    }

    private func clear() {
        lock.lock()
        defer { lock.unlock() }
        rows.removeAll()
    }
}

@Suite("Hydration record sync")
struct HydrationRecordSyncTest {

    private let gateway = FakeGateway()
    private let store = FakeHealthSyncStore()
    private let log = DebugLog(directory: nil)
    private let nowMs: Int64 = 1_700_000_000_000
    // Synthetic patterned uint64 fixture, not a paired device's serial.
    private let deviceId = "FEDCBA9876543210"
    /// One writer instance per test, exactly like the app (the "logged once"
    /// dedup state lives in the instance).
    private let sync: HydrationRecordSync

    init() {
        sync = HydrationRecordSync(gateway: gateway, store: store, debugLog: log, clock: { 1_700_000_000_000 })
    }

    private func event(_ ts: Int64, ml: Double = 150.0, version: Int64 = 1) -> DrinkEvent {
        DrinkEvent(timestamp: ts, volumeMl: ml, sourceLogTimestamp: ts, profileId: "body_680", version: version)
    }

    @Test func firstUpsertInsertsEveryValidEventWithTheExpectedIdsAndVersions() async {
        let events = [event(1_000), event(2_000, ml: 80.5, version: 3)]
        let result = await sync.upsert(events: events, pairedDeviceIdHex: deviceId)

        #expect(result == HealthWriteResult(inserted: 2, updated: 0, skipped: 0))
        #expect(gateway.inserted.map(\.clientRecordId) == ["hydrocap:\(deviceId):1000", "hydrocap:\(deviceId):2000"])
        #expect(gateway.inserted.map(\.clientRecordVersion) == [1, 3])
        #expect(gateway.inserted[1].volumeMl == 80.5)
        #expect(gateway.inserted[1].startEpochSec == 2_000)
        #expect(store.keys == [1_000, 2_000])
        #expect(store.row(2_000)?.writtenVersion == 3)
        #expect(store.row(2_000)?.writtenAtMs == nowMs)
    }

    @Test func unchangedEventsAreNotWrittenAgainAndBumpedVersionsCountAsUpdated() async {
        _ = await sync.upsert(events: [event(1_000), event(2_000)], pairedDeviceIdHex: deviceId)
        gateway.clearInsertBatches()

        let result = await sync.upsert(events: [event(1_000), event(2_000, ml: 200.0, version: 2)], pairedDeviceIdHex: deviceId)

        #expect(result == HealthWriteResult(inserted: 0, updated: 1, skipped: 0))
        #expect(gateway.inserted.map(\.clientRecordId) == ["hydrocap:\(deviceId):2000"])
        #expect(gateway.inserted.first?.clientRecordVersion == 2)
        #expect(store.row(2_000)?.writtenVersion == 2)
        #expect(store.row(1_000)?.writtenVersion == 1)
    }

    @Test func eventsWithZeroVolumeOrAFutureStartTimeAreSkipped() async {
        let nowSec = nowMs / 1000
        let events = [event(1_000), event(2_000, ml: 0.0), event(3_000, ml: -5.0), event(nowSec + 60)]
        let result = await sync.upsert(events: events, pairedDeviceIdHex: deviceId)

        #expect(result == HealthWriteResult(inserted: 1, updated: 0, skipped: 3))
        #expect(gateway.inserted.map(\.clientRecordId) == ["hydrocap:\(deviceId):1000"])
        #expect(store.keys == [1_000])
    }

    @Test func recordsForVanishedEventsAreDeletedByClientIdAndDroppedFromTheTrackingTable() async {
        _ = await sync.upsert(events: [event(1_000), event(2_000), event(3_000)], pairedDeviceIdHex: deviceId)

        let result = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: deviceId)

        #expect(result == HealthWriteResult(inserted: 0, updated: 0, skipped: 0))
        #expect(Set(gateway.deleted) == ["hydrocap:\(deviceId):2000", "hydrocap:\(deviceId):3000"])
        #expect(store.keys == [1_000])
    }

    @Test func deleteUsesTheClientIdThatWasWrittenEvenIfThePairedDeviceChanged() async {
        _ = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: "OLDDEVICE")
        _ = await sync.upsert(events: [], pairedDeviceIdHex: deviceId)
        #expect(gateway.deleted == ["hydrocap:OLDDEVICE:1000"])
    }

    @Test func insertsAndDeletesAreChunkedAt500() async {
        let events = (1...1_201).map { event(Int64($0) * 10) }
        let result = await sync.upsert(events: events, pairedDeviceIdHex: deviceId)
        #expect(result.inserted == 1_201)
        #expect(gateway.insertBatches.map(\.count) == [500, 500, 201])

        _ = await sync.upsert(events: [], pairedDeviceIdHex: deviceId)
        #expect(gateway.deleteBatches.map(\.count) == [500, 500, 201])
        #expect(store.keys.isEmpty)
    }

    @Test func unavailableHealthKitSkipsEverythingWithoutTouchingTheGateway() async {
        gateway.unavailable = "HealthKit hydration write permission is not granted"
        let result = await sync.upsert(events: [event(1_000), event(2_000)], pairedDeviceIdHex: deviceId)

        #expect(result.inserted == 0)
        #expect(result.skipped == 2)
        #expect(result.error == "HealthKit hydration write permission is not granted")
        #expect(gateway.insertBatches.isEmpty)
        #expect(store.keys.isEmpty)
        // Logged once, not once per call.
        _ = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: deviceId)
        #expect(TestSupport.logMessageCount(log, containing: "not writing") == 1)
    }

    @Test func gatewayFailuresMapToAnErrorAndLeavePartialProgressConsistent() async {
        gateway.failInsertWith = .permissionRevoked("revoked")
        let result = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: deviceId)
        #expect(result.error != nil)
        #expect(result.error?.contains("permission revoked") == true)
        #expect(result.inserted == 0)
        #expect(store.keys.isEmpty, "nothing must be tracked when the insert failed")

        gateway.failInsertWith = .io("binder died")
        let ioResult = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: deviceId)
        #expect(ioResult.error?.contains("I/O") == true)

        gateway.failInsertWith = .state("not bound")
        let stateResult = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: deviceId)
        #expect(stateResult.error?.contains("state") == true)

        gateway.failInsertWith = .other("boom")
        let otherResult = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: deviceId)
        #expect(otherResult.error?.contains("HealthKit write failed") == true)

        gateway.failInsertWith = nil
        let okResult = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: deviceId)
        #expect(okResult.error == nil)
        #expect(okResult.inserted == 1)
    }

    @Test func aFailingDeleteDoesNotLoseTheTrackingRowSoTheDeleteIsRetriedLater() async {
        _ = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: deviceId)
        gateway.failDeleteWith = .state("busy")
        let failed = await sync.upsert(events: [], pairedDeviceIdHex: deviceId)
        #expect(failed.error != nil)
        #expect(store.keys == [1_000])

        gateway.failDeleteWith = nil
        let retried = await sync.upsert(events: [], pairedDeviceIdHex: deviceId)
        #expect(retried.error == nil)
        #expect(gateway.deleted == ["hydrocap:\(deviceId):1000"])
        #expect(store.keys.isEmpty)
    }

    @Test func unpairedWritesUseTheUnpairedPlaceholderId() async {
        _ = await sync.upsert(events: [event(1_000)], pairedDeviceIdHex: nil)
        #expect(gateway.inserted.first?.clientRecordId == "hydrocap:unpaired:1000")
    }

    @Test func planIsPureAndReportsCounts() {
        let written = [
            HealthSyncRecord(timestamp: 1_000, clientRecordId: "hydrocap:x:1000", writtenVersion: 1, writtenAtMs: 0),
            HealthSyncRecord(timestamp: 2_000, clientRecordId: "hydrocap:x:2000", writtenVersion: 1, writtenAtMs: 0),
            HealthSyncRecord(timestamp: 9_000, clientRecordId: "hydrocap:x:9000", writtenVersion: 1, writtenAtMs: 0),
        ]
        let plan = HydrationRecordSync.plan(
            events: [event(1_000), event(2_000, version: 2), event(3_000), event(4_000, ml: 0.0)],
            written: written,
            pairedDeviceIdHex: "x",
            nowSec: 100_000,
        )
        #expect(plan.inserts.map(\.timestamp) == [3_000])
        #expect(plan.updates.map(\.timestamp) == [2_000])
        #expect(plan.deletes.map(\.timestamp) == [9_000])
        #expect(plan.skipped == 1)
        #expect(plan.unchanged == 1)
    }

    @Test func syncIdentifierUsesThePairedDeviceIdAndTheEventTimestamp() {
        #expect(HydrationRecordSync.clientRecordId(pairedDeviceIdHex: "FEDCBA9876543210", timestampSec: 1_790_000_100) == "hydrocap:FEDCBA9876543210:1790000100")
    }
}
