import Foundation

/// Storage seams for the sync engine and the UI.
///
/// The production implementation is the SwiftData `@ModelActor` in
/// `Data/SwiftDataModels.swift`; `InMemoryStore` implements the same protocol
/// for previews, tests and the Mac Catalyst typecheck. Keeping the protocols in
/// terms of the plain records in `Data/Records.swift` is what lets the health
/// planner be unit-tested with a fake store.

nonisolated protocol TofLogStore: Sendable {
    /// Inserts new entries, ignoring timestamps that are already stored.
    /// Returns the number of newly inserted rows.
    func insertTofLog(_ entries: [TofLogEntry]) async throws -> Int
    func tofLogMaxTimestamp() async throws -> Int64?
    func allTofLog() async throws -> [TofLogEntry]
    func latestTofLog() async throws -> TofLogEntry?
    func tofLogCount() async throws -> Int
    func deleteAllTofLog() async throws
}

nonisolated protocol ActivationLogStore: Sendable {
    func insertActivationLog(_ entries: [ActivationLogEntry]) async throws -> Int
    func activationLogMaxTimestamp() async throws -> Int64?
    func allActivationLog() async throws -> [ActivationLogEntry]
    func activationLogCount() async throws -> Int
    func deleteAllActivationLog() async throws
}

nonisolated protocol DrinkEventStore: Sendable {
    func upsertDrinkEvents(_ events: [DrinkEvent]) async throws
    func allDrinkEvents() async throws -> [DrinkEvent]
    /// Ascending by timestamp, half-open range `[fromSec, toSec)`.
    func drinkEvents(fromSec: Int64, toSec: Int64) async throws -> [DrinkEvent]
    func deleteDrinkEvents(timestamps: [Int64]) async throws
    func deleteAllDrinkEvents() async throws
}

nonisolated protocol BatterySampleStore: Sendable {
    func insertBatterySample(_ sample: BatterySample) async throws
    func latestBatterySample() async throws -> BatterySample?
    func deleteAllBatterySamples() async throws
}

nonisolated protocol DeviceStore: Sendable {
    func upsertDevice(_ device: DeviceRecord) async throws
    func device(deviceIdHex: String) async throws -> DeviceRecord?
    func deleteAllDevices() async throws
}

/// Write-tracking for the health sink (`health_sync` in the Android schema).
/// Separate from the other stores so the planner's tests need nothing else.
nonisolated protocol HealthSyncStore: Sendable {
    func allHealthSyncRecords() async throws -> [HealthSyncRecord]
    func upsertHealthSyncRecords(_ records: [HealthSyncRecord]) async throws
    func deleteHealthSyncRecords(timestamps: [Int64]) async throws
    func healthSyncRecordCount() async throws -> Int
    func deleteAllHealthSyncRecords() async throws
}

/// Everything the app persists, in one seam.
nonisolated protocol HydroCapStore: TofLogStore, ActivationLogStore, DrinkEventStore, BatterySampleStore, DeviceStore, HealthSyncStore {}
