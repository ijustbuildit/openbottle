import Foundation
import HealthKit

/// Body values read from Apple Health for the daily water target. HealthKit
/// never reveals whether *read* access was granted: a denied read simply
/// returns no data, exactly like an empty Health record. So `nil` means
/// "not available" — never "denied" and never "granted but empty".
nonisolated struct HealthBodyValues: Sendable, Equatable {
    var weightKg: Double?
    var weightSampledAt: Date?
    var sex: HydrationTarget.Sex?

    init(weightKg: Double? = nil, weightSampledAt: Date? = nil, sex: HydrationTarget.Sex? = nil) {
        self.weightKg = weightKg
        self.weightSampledAt = weightSampledAt
        self.sex = sex
    }

    static let none = HealthBodyValues()
}

/// Availability + authorization helpers shared by onboarding, Settings and the
/// writer, and the `HydrationGateway` implementation around `HKHealthStore`.
///
/// Sync semantics (quoted from the SDK headers, see ios/README.md):
/// HealthKit upserts on `HKMetadataKeySyncIdentifier` / `HKMetadataKeySyncVersion`
/// — "If you save a sample with the same sync identifier but a higher sync
/// version, HealthKit replaces the previous sample" — so there is no
/// read-before-write on the Android port either.
@MainActor
final class HealthKitGateway: HydrationGateway {
    nonisolated static let deviceManufacturer = "LARQ"
    nonisolated static let deviceModel = "CAP"
    /// `HKQuantityType` / `HKUnit` instances are immutable and `Sendable` in
    /// the current SDK, so they are plain `nonisolated` statics.
    nonisolated static let waterType = HKQuantityType(.dietaryWater)
    nonisolated static let milliliterUnit = HKUnit.literUnit(with: .milli)
    /// Read set for the daily target: latest body mass (kg) + biological sex.
    nonisolated static let bodyMassType = HKQuantityType(.bodyMass)
    nonisolated static let biologicalSexType = HKCharacteristicType(.biologicalSex)
    nonisolated static let kilogramUnit = HKUnit.gramUnit(with: .kilo)
    nonisolated static var readTypes: Set<HKObjectType> { [bodyMassType, biologicalSexType] }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    /// True when the user granted permission to *write* water.
    var isAuthorized: Bool {
        store.authorizationStatus(for: HealthKitGateway.waterType) == .sharingAuthorized
    }

    var authorizationStatus: HKAuthorizationStatus {
        store.authorizationStatus(for: HealthKitGateway.waterType)
    }

    /// True while the Health sheet has never been shown for our types (the
    /// user could still be asked). After the sheet was answered this is
    /// false whatever the answer was; HealthKit does not report read grants.
    func canStillAsk() async -> Bool {
        guard Self.isAvailable else { return false }
        let status = try? await store.statusForAuthorizationRequest(toShare: [HealthKitGateway.waterType], read: HealthKitGateway.readTypes)
        return status == .shouldRequest
    }

    /// Asks for write access to dietary water and read access to body mass +
    /// biological sex (onboarding + the Settings toggle). Returns whether
    /// writes may happen; read grants are not observable.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [HealthKitGateway.waterType], read: HealthKitGateway.readTypes)
            return isAuthorized
        } catch {
            return false
        }
    }

    /// Latest body mass (most recent end date) and the biological sex
    /// characteristic. Missing data and denied reads are indistinguishable
    /// and both yield nil.
    func readBodyValues() async -> HealthBodyValues {
        guard Self.isAvailable else { return .none }
        var values = HealthBodyValues()
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.quantitySample(type: HealthKitGateway.bodyMassType)],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1,
        )
        if let sample = try? await descriptor.result(for: store).first {
            let kg = sample.quantity.doubleValue(for: HealthKitGateway.kilogramUnit)
            if kg.isFinite, kg > 0 {
                values.weightKg = kg
                values.weightSampledAt = sample.endDate
            }
        }
        if let object = try? store.biologicalSex() {
            switch object.biologicalSex {
            case .female: values.sex = .female
            case .male: values.sex = .male
            case .other: values.sex = .other
            case .notSet: values.sex = nil
            @unknown default: values.sex = nil
            }
        }
        return values
    }

    // MARK: HydrationGateway

    // The gateway witnesses are nonisolated so the nonisolated health planner
    // can call them; the `HKHealthStore` work itself runs on the MainActor.

    nonisolated func unavailableReason() async -> String? {
        await unavailableReasonOnMain()
    }

    @MainActor
    private func unavailableReasonOnMain() -> String? {
        guard Self.isAvailable else { return "Apple Health is not available on this device" }
        guard isAuthorized else { return "Apple Health permission to write water is not granted" }
        return nil
    }

    nonisolated func insert(_ records: [HydrationWrite]) async throws {
        try await insertOnMain(records)
    }

    @MainActor
    private func insertOnMain(_ records: [HydrationWrite]) async throws {
        guard !records.isEmpty else { return }
        let samples = records.map { write -> HKQuantitySample in
            let start = Date(timeIntervalSince1970: TimeInterval(write.startEpochSec))
            let end = start.addingTimeInterval(TimeInterval(HydrationWrite.durationSec))
            let metadata: [String: Any] = [
                HKMetadataKeySyncIdentifier: write.clientRecordId,
                HKMetadataKeySyncVersion: NSNumber(value: write.clientRecordVersion),
            ]
            return HKQuantitySample(
                type: HealthKitGateway.waterType,
                quantity: HKQuantity(unit: HealthKitGateway.milliliterUnit, doubleValue: write.volumeMl),
                start: start,
                end: end,
                metadata: metadata,
            )
        }
        do {
            try await store.save(samples)
        } catch {
            throw Self.classify(error)
        }
    }

    /// Deletes only records HydroCap wrote, addressed by their sync identifiers
    /// (never other apps' data).
    nonisolated func delete(clientRecordIds: [String]) async throws {
        try await deleteOnMain(clientRecordIds)
    }

    @MainActor
    private func deleteOnMain(_ clientRecordIds: [String]) async throws {
        guard !clientRecordIds.isEmpty else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: HKMetadataKeySyncIdentifier, allowedValues: clientRecordIds)
        do {
            try await store.deleteObjects(of: HealthKitGateway.waterType, predicate: predicate)
        } catch {
            throw Self.classify(error)
        }
    }

    /// HealthKit throws `HKError`s, not the four Health Connect exception
    /// classes; the writer maps the classified cases to the same messages the
    /// Android port reports.
    nonisolated private static func classify(_ error: Error) -> HealthGatewayError {
        guard let healthError = error as? HKError else {
            return .other("\(String(describing: type(of: error))): \(error.localizedDescription)")
        }
        switch healthError.code {
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined:
            return .permissionRevoked(healthError.localizedDescription)
        case .errorDatabaseInaccessible:
            return .io(healthError.localizedDescription)
        case .errorHealthDataUnavailable, .errorHealthDataRestricted:
            return .unreachable(healthError.localizedDescription)
        case .errorInvalidArgument, .errorUserCanceled:
            return .state(healthError.localizedDescription)
        default:
            return .other("\(healthError.localizedDescription) (code \(healthError.code.rawValue))")
        }
    }
}

/// Production health sink: one dietary-water sample per drink event, tracked in
/// the `health_sync` store. Ids are
/// `hydrocap:<pairedDeviceIdHex>:<timestamp>`, versions follow
/// `DrinkEvent.version`. See `HydrationRecordSync` for the planning rules.
@MainActor
final class HealthKitHydrationWriter {
    nonisolated static let tag = "health"

    private let store: any HydroCapStore
    private let settings: SettingsStore
    private let gateway: HealthKitGateway
    private let sync: HydrationRecordSync
    private let debugLog: DebugLog

    init(store: any HydroCapStore, settings: SettingsStore, debugLog: DebugLog, gateway: HealthKitGateway? = nil) {
        let gateway = gateway ?? HealthKitGateway()
        self.store = store
        self.settings = settings
        self.debugLog = debugLog
        self.gateway = gateway
        self.sync = HydrationRecordSync(gateway: gateway, store: store, debugLog: debugLog)
    }

    var isAuthorized: Bool { gateway.isAuthorized }
    var isAvailable: Bool { HealthKitGateway.isAvailable }
    var authorizationStatus: HKAuthorizationStatus { gateway.authorizationStatus }

    /// Requests (or re-checks) authorization; returns whether writes may happen.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await gateway.requestAuthorization()
    }

    /// True while the Health sheet could still be shown for our types.
    func canStillAsk() async -> Bool {
        await gateway.canStillAsk()
    }

    /// Latest weight + biological sex for the daily target (nil = not available).
    func readBodyValues() async -> HealthBodyValues {
        await gateway.readBodyValues()
    }

    func upsert(events: [DrinkEvent]) async -> HealthWriteResult {
        await sync.upsert(events: events, pairedDeviceIdHex: settings.current.pairedDeviceIdHex)
    }

    /// "Write to Apple Health now": every stored drink event, without a BLE sync.
    func upsertAllStored() async -> HealthWriteResult {
        let events = (try? await store.allDrinkEvents()) ?? []
        return await upsert(events: events)
    }

    func trackedRecordCount() async -> Int {
        (try? await store.healthSyncRecordCount()) ?? 0
    }
}
