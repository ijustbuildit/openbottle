import Foundation

/// One hydration sample as HydroCap wants it in the health store; pure data so
/// the sync logic is testable.
nonisolated struct HydrationWrite: Sendable, Equatable {
    var clientRecordId: String
    var clientRecordVersion: Int64
    var startEpochSec: Int64
    var volumeMl: Double

    init(clientRecordId: String, clientRecordVersion: Int64, startEpochSec: Int64, volumeMl: Double) {
        self.clientRecordId = clientRecordId
        self.clientRecordVersion = clientRecordVersion
        self.startEpochSec = startEpochSec
        self.volumeMl = volumeMl
    }

    /// Records are instantaneous drinks; HealthKit needs start < end, so they
    /// last one second.
    static let durationSec: Int64 = 1
}

/// Outcome of one health upsert.
nonisolated struct HealthWriteResult: Sendable, Equatable {
    var inserted: Int
    var updated: Int
    var skipped: Int
    var error: String?

    init(inserted: Int, updated: Int, skipped: Int, error: String? = nil) {
        self.inserted = inserted
        self.updated = updated
        self.skipped = skipped
        self.error = error
    }

    var summary: String {
        var text = "\(inserted) inserted, \(updated) updated, \(skipped) skipped"
        if let error { text += " — \(error)" }
        return text
    }
}

/// Failures the gateway reports, mapped by the writer to a result string. The
/// Android port catches the four Health Connect exception classes; HealthKit
/// throws `HKError`s without those distinctions, so the gateway classifies and
/// the *messages stay identical*.
nonisolated enum HealthGatewayError: Error, Equatable {
    case permissionRevoked(String)
    case unreachable(String)
    case io(String)
    case state(String)
    case other(String)
}

/// The thin platform seam around `HKHealthStore`. The planner
/// (`HydrationRecordSync`) decides *what* to write; this decides *how*.
nonisolated protocol HydrationGateway: Sendable {
    /// nil when records can be written; otherwise a human-readable reason
    /// (unavailable / permission missing).
    func unavailableReason() async -> String?

    /// Inserts (or, for an existing sync identifier with a higher sync
    /// version, replaces) the given records.
    func insert(_ records: [HydrationWrite]) async throws

    /// Deletes only records HydroCap wrote, addressed by their sync identifiers.
    func delete(clientRecordIds: [String]) async throws
}

/// Decides which drink events go to the health store and remembers what was
/// written. No read-before-write: HealthKit deduplicates on
/// `HKMetadataKeySyncIdentifier` and lets the higher `HKMetadataKeySyncVersion`
/// win, so the plan is simply
///
/// 1. delete records whose event vanished (algorithm/profile change) or became
///    invalid — only ids HydroCap wrote itself, never other apps' data;
/// 2. insert every valid event whose (timestamp, version) is not yet recorded
///    as written; an id with an older written version counts as *updated*.
///
/// Inserts and deletes are chunked at `chunkSize`; the tracking table is
/// updated per chunk so a failure mid-way never causes duplicate work later.
/// Every health-store failure is mapped to a `HealthWriteResult.error` — the
/// sync must not crash because of the health sink.
nonisolated final class HydrationRecordSync: @unchecked Sendable {
    static let chunkSize = 500
    static let unpairedDeviceId = "unpaired"

    private let gateway: HydrationGateway
    private let store: HealthSyncStore
    private let debugLog: DebugLog
    private let clock: @Sendable () -> Int64
    private let lock = NSLock()
    private var loggedUnavailableReason: String?

    init(
        gateway: HydrationGateway,
        store: HealthSyncStore,
        debugLog: DebugLog,
        clock: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) },
    ) {
        self.gateway = gateway
        self.store = store
        self.debugLog = debugLog
        self.clock = clock
    }

    func upsert(events: [DrinkEvent], pairedDeviceIdHex: String?) async -> HealthWriteResult {
        if let reason = await gateway.unavailableReason() {
            if shouldLogUnavailable(reason) {
                debugLog.log(Self.TAG, "not writing \(events.count) event(s): \(reason)")
            }
            return HealthWriteResult(inserted: 0, updated: 0, skipped: events.count, error: reason)
        }
        clearUnavailable()

        let written = (try? await store.allHealthSyncRecords()) ?? []
        let nowSec = clock() / 1000
        let plan = Self.plan(events: events, written: written, pairedDeviceIdHex: pairedDeviceIdHex ?? Self.unpairedDeviceId, nowSec: nowSec)
        debugLog.log(
            Self.TAG,
            "plan: \(plan.inserts.count) insert, \(plan.updates.count) update, \(plan.deletes.count) delete, " +
                "\(plan.skipped) skipped, \(plan.unchanged) unchanged (of \(events.count) events)",
        )
        var inserted = 0
        var updated = 0
        do {
            for chunk in plan.deletes.chunked(into: Self.chunkSize) {
                try await gateway.delete(clientRecordIds: chunk.map { $0.clientRecordId })
                try await store.deleteHealthSyncRecords(timestamps: chunk.map { $0.timestamp })
            }
            let updatedTimestamps = Set(plan.updates.map { $0.timestamp })
            // Inserts first, then updates, chunked across the concatenation —
            // same order and chunking as the Kotlin port.
            for chunk in (plan.inserts + plan.updates).chunked(into: Self.chunkSize) {
                try await gateway.insert(chunk.map { $0.write })
                let writtenAt = clock()
                try await store.upsertHealthSyncRecords(chunk.map {
                    HealthSyncRecord(
                        timestamp: $0.timestamp,
                        clientRecordId: $0.write.clientRecordId,
                        writtenVersion: $0.write.clientRecordVersion,
                        writtenAtMs: writtenAt,
                    )
                })
                for item in chunk {
                    if updatedTimestamps.contains(item.timestamp) { updated += 1 } else { inserted += 1 }
                }
            }
        } catch let error as HealthGatewayError {
            return failed(inserted: inserted, updated: updated, skipped: plan.skipped, message: Self.message(for: error), error: error)
        } catch {
            return failed(
                inserted: inserted,
                updated: updated,
                skipped: plan.skipped,
                message: "HealthKit write failed: \(String(describing: type(of: error))): \(error)",
                error: error,
            )
        }
        debugLog.log(Self.TAG, "written: inserted=\(inserted) updated=\(updated) deleted=\(plan.deletes.count) skipped=\(plan.skipped)")
        return HealthWriteResult(inserted: inserted, updated: updated, skipped: plan.skipped)
    }

    private func failed(inserted: Int, updated: Int, skipped: Int, message: String, error: Error) -> HealthWriteResult {
        debugLog.error(Self.TAG, "\(message) (after inserted=\(inserted) updated=\(updated))", error: error)
        return HealthWriteResult(inserted: inserted, updated: updated, skipped: skipped, error: message)
    }

    /// Synchronous so the lock never sits in an async context (Swift 6 flags
    /// `NSLock.lock()` inside `async` functions).
    private func shouldLogUnavailable(_ reason: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let shouldLog = loggedUnavailableReason != reason
        if shouldLog { loggedUnavailableReason = reason }
        return shouldLog
    }

    private func clearUnavailable() {
        lock.lock()
        loggedUnavailableReason = nil
        lock.unlock()
    }

    static func message(for error: HealthGatewayError) -> String {
        switch error {
        case .permissionRevoked(let detail): "HealthKit permission revoked: \(detail)"
        case .unreachable(let detail): "HealthKit unreachable: \(detail)"
        case .io(let detail): "HealthKit I/O error: \(detail)"
        case .state(let detail): "HealthKit state error: \(detail)"
        case .other(let detail): "HealthKit write failed: \(detail)"
        }
    }

    /// A pending write together with the event timestamp it is tracked under.
    nonisolated struct PlannedWrite: Sendable, Equatable {
        var timestamp: Int64
        var write: HydrationWrite
    }

    nonisolated struct Plan: Sendable, Equatable {
        var inserts: [PlannedWrite]
        var updates: [PlannedWrite]
        var deletes: [HealthSyncRecord]
        var skipped: Int
        var unchanged: Int
    }

    static let TAG = "health"

    static func clientRecordId(pairedDeviceIdHex: String, timestampSec: Int64) -> String {
        "hydrocap:\(pairedDeviceIdHex):\(timestampSec)"
    }

    /// Pure planning step; exposed for tests.
    static func plan(events: [DrinkEvent], written: [HealthSyncRecord], pairedDeviceIdHex: String, nowSec: Int64) -> Plan {
        var writtenByTimestamp: [Int64: HealthSyncRecord] = [:]
        for record in written { writtenByTimestamp[record.timestamp] = record }
        var inserts: [PlannedWrite] = []
        var updates: [PlannedWrite] = []
        var skipped = 0
        var unchanged = 0
        var valid = Set<Int64>()
        for event in events {
            if event.volumeMl <= 0.0 || event.timestamp > nowSec {
                skipped += 1
                continue
            }
            valid.insert(event.timestamp)
            if let previous = writtenByTimestamp[event.timestamp], previous.writtenVersion >= event.version {
                unchanged += 1
                continue
            }
            let write = HydrationWrite(
                clientRecordId: clientRecordId(pairedDeviceIdHex: pairedDeviceIdHex, timestampSec: event.timestamp),
                clientRecordVersion: event.version,
                startEpochSec: event.timestamp,
                volumeMl: event.volumeMl,
            )
            if writtenByTimestamp[event.timestamp] == nil {
                inserts.append(PlannedWrite(timestamp: event.timestamp, write: write))
            } else {
                updates.append(PlannedWrite(timestamp: event.timestamp, write: write))
            }
        }
        // Records we wrote for events that no longer exist (or are no longer
        // valid) must go.
        let deletes = written.filter { !valid.contains($0.timestamp) }
        return Plan(inserts: inserts, updates: updates, deletes: deletes, skipped: skipped, unchanged: unchanged)
    }
}

extension Array {
    /// Splits into chunks of at most `size` elements (`chunked(n)` in Kotlin).
    nonisolated func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        var chunks: [[Element]] = []
        var index = 0
        while index < count {
            let end = Swift.min(index + size, count)
            chunks.append(Array(self[index..<end]))
            index = end
        }
        return chunks
    }
}
