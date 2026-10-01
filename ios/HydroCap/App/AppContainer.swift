import Foundation
import Observation
import UIKit

/// Manual dependency wiring; one instance per process, owned by `HydroCapApp`
/// (no DI framework, same as the Android `AppContainer`).
@MainActor
final class AppContainer {
    let debugLog: DebugLog
    let settings: SettingsStore
    let store: any HydroCapStore
    let central: CapCentral
    let scanner: BleScanner
    let requestIds: RequestIdCounter
    let batteryNotifier: BatteryNotifier
    let healthWriter: HealthKitHydrationWriter
    let drinkEventBuilder: DrinkEventBuilder
    let backgroundGuard: BackgroundTaskGuard
    let syncEngine: SyncEngine
    let backgroundSync: BackgroundSyncController
    let drinkReminders: DrinkReminderScheduler
    let debugActions: DebugActions
    /// The UI refresh is awaited with the scheduler after every successful sync.
    var onSyncCompleted: () async -> Void = {}
    private var started = false

    init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let debugLog = DebugLog(directory: documents)
        self.debugLog = debugLog
        let settings = SettingsStore()
        self.settings = settings
        let store: any HydroCapStore
        do {
            store = try StoreFactory.make()
        } catch {
            debugLog.error("app", "SwiftData store unavailable, falling back to the in-memory store for this session", error: error)
            store = InMemoryStore()
        }
        self.store = store
        let central = CapCentral(debugLog: debugLog)
        self.central = central
        let scanner = BleScanner(central: central, debugLog: debugLog)
        self.scanner = scanner
        let requestIds = RequestIdCounter()
        self.requestIds = requestIds
        let batteryNotifier = BatteryNotifier(settings: settings, debugLog: debugLog)
        self.batteryNotifier = batteryNotifier
        let healthWriter = HealthKitHydrationWriter(store: store, settings: settings, debugLog: debugLog)
        self.healthWriter = healthWriter
        let drinkEventBuilder = DrinkEventBuilder(store: store, debugLog: debugLog)
        self.drinkEventBuilder = drinkEventBuilder
        let backgroundGuard = BackgroundTaskGuard(debugLog: debugLog)
        self.backgroundGuard = backgroundGuard
        let syncEngine = SyncEngine(
            central: central,
            scanner: scanner,
            store: store,
            settings: settings,
            drinkEventBuilder: drinkEventBuilder,
            healthWriter: healthWriter,
            batteryNotifier: batteryNotifier,
            requestIds: requestIds,
            debugLog: debugLog,
            backgroundGuard: backgroundGuard,
        )
        self.syncEngine = syncEngine
        let backgroundSync = BackgroundSyncController(
            engine: syncEngine,
            central: central,
            scanner: scanner,
            settings: settings,
            debugLog: debugLog,
        )
        self.backgroundSync = backgroundSync
        let drinkReminders = DrinkReminderScheduler(settings: settings, store: store, debugLog: debugLog)
        self.drinkReminders = drinkReminders
        self.debugActions = DebugActions(engine: syncEngine, scanner: scanner, settings: settings, debugLog: debugLog)
        // Pairing (a first sync that finds an unpaired cap) reconciles the
        // background trigger.
        syncEngine.onPaired = { [weak backgroundSync] in
            backgroundSync?.reconcile()
        }
        // Every sync re-plans the drink reminders with today's intake (awaited
        // inside the job); a ring-hours read re-plans with the cap's window.
        syncEngine.onSynced = { [weak self, weak drinkReminders] in
            await self?.onSyncCompleted()
            await drinkReminders?.replan()
        }
        syncEngine.onRingHoursRead = { [weak drinkReminders] in
            drinkReminders?.replanSoon()
        }
        debugLog.log("app", "HydroCap \(Self.version) started (local-only, no networking)")
    }

    /// Register background work once. An unpaired app leaves Bluetooth startup
    /// to onboarding so unknown Bluetooth consent cannot precede Health.
    func start() {
        guard !started else { return }
        started = true
        backgroundSync.registerBackgroundRefresh()
        if settings.current.hasPairedDevice {
            central.start()
            backgroundSync.reconcile()
        }
        drinkReminders.replanSoon()
    }

    static var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var debugLogFileURL: URL? { debugLog.fileURL }
}
