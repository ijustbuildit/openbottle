import Foundation

/// Runs `TofAlgorithm` over the entire stored ToF log and reconciles the drink
/// events: new events are inserted, changed volumes bump the version (so
/// HealthKit can update), events that no longer exist (e.g. after a profile
/// change) are removed.
@MainActor
final class DrinkEventBuilder {
    nonisolated static let tag = "drinks"

    private let store: any HydroCapStore
    private let debugLog: DebugLog

    init(store: any HydroCapStore, debugLog: DebugLog) {
        self.store = store
        self.debugLog = debugLog
    }

    func rebuild(profile: BottleProfile) async throws -> [DrinkEvent] {
        let entries = try await store.allTofLog()
        let readings = entries.map { TofReading(timestampSec: $0.timestamp, distanceMm: $0.distanceMm, kcps: $0.kcps) }
        let computed = TofAlgorithm(profile: profile).drinkEvents(readings)
        let existing = Dictionary(uniqueKeysWithValues: (try await store.allDrinkEvents()).map { ($0.timestamp, $0) })

        let upserts = computed.map { event -> DrinkEvent in
            let timestamp = event.reading.timestampSec
            let volume = Self.round1(event.countedMl)
            guard let previous = existing[timestamp] else {
                return DrinkEvent(timestamp: timestamp, volumeMl: volume, sourceLogTimestamp: timestamp, profileId: profile.id, version: 1)
            }
            if previous.volumeMl != volume || previous.profileId != profile.id {
                var updated = previous
                updated.volumeMl = volume
                updated.profileId = profile.id
                updated.version = previous.version + 1
                return updated
            }
            return previous
        }
        try await store.upsertDrinkEvents(upserts)
        let keep = Set(upserts.map { $0.timestamp })
        let stale = existing.keys.filter { !keep.contains($0) }
        // Chunked so a delete statement never carries thousands of parameters.
        for chunk in stale.sorted().chunked(into: 500) {
            try await store.deleteDrinkEvents(timestamps: chunk)
        }
        let newCount = upserts.filter { existing[$0.timestamp] == nil }.count
        let changedCount = upserts.filter { existing[$0.timestamp]?.version != $0.version }.count
        debugLog.log(
            Self.tag,
            "algorithm(\(profile.id)) over \(readings.count) readings → \(upserts.count) drink events " +
                "(\(newCount) new, \(changedCount) changed, \(stale.count) removed)",
        )
        return upserts
    }

    private static func round1(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }
}
