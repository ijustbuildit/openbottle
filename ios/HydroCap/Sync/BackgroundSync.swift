import BackgroundTasks
import CoreBluetooth
import Foundation
import Observation

/// Carries a non-`Sendable` `BGTask` across an isolation hop. The task is
/// consumed exactly once, on the MainActor.
nonisolated struct UncheckedTaskBox: @unchecked Sendable {
    let task: BGAppRefreshTask
}

/// Background sync, the iOS-native way, with honest limits (see ios/README.md):
///
/// 1. **Service-filtered background scan** — while a cap is paired and
///    background sync is enabled, the app keeps a `bluetooth-central` scan
///    running. iOS wakes/keeps the app alive on discovery; because the cap
///    rotates its address it reappears as a new peripheral roughly every
///    15 min, which yields a natural sync cadence while in range. After every
///    background sync the connection is dropped and the scan restarted.
/// 2. **`BGAppRefreshTask` `dev.hydrocap.refresh`** (earliest 15 min) as a
///    second trigger: one scan-and-sync attempt with a 25 s budget, then
///    reschedule. Cap not found counts as success and never notifies.
@MainActor
@Observable
final class BackgroundSyncController {
    nonisolated static let tag = "worker"
    nonisolated static let refreshTaskIdentifier = "dev.hydrocap.refresh"
    nonisolated static let refreshEarliestMinutes = 15.0
    nonisolated static let refreshBudgetSeconds = 25.0
    nonisolated static let discoveryPollMilliseconds = 500
    /// Minimum gap between two background syncs. The cap rotates its address
    /// after every disconnect, so iOS reports it as a *new* peripheral right
    /// away and a discovery wake would follow every sync within seconds — a
    /// permanent connect/disconnect loop that drains the cap battery. Manual
    /// "Sync now" is not throttled.
    nonisolated static let minimumSyncIntervalSeconds = 15.0 * 60

    private let engine: SyncEngine
    private let central: CapCentral
    private let scanner: BleScanner
    private let settings: SettingsStore
    private let debugLog: DebugLog
    private var watchTask: Task<Void, Never>?
    private var registered = false
    private(set) var isBackgroundScanActive = false

    init(engine: SyncEngine, central: CapCentral, scanner: BleScanner, settings: SettingsStore, debugLog: DebugLog) {
        self.engine = engine
        self.central = central
        self.scanner = scanner
        self.settings = settings
        self.debugLog = debugLog
    }

    /// Must run before the app finishes launching (BGTaskScheduler requirement).
    func registerBackgroundRefresh() {
        guard !registered else { return }
        registered = true
        let identifier = Self.refreshTaskIdentifier
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            // `BGTask` is not Sendable; the box carries it across the hop to
            // the MainActor, where it is consumed exactly once.
            let box = UncheckedTaskBox(task: refreshTask)
            Task { @MainActor in
                await self?.runRefreshTask(box.task)
            }
        }
        debugLog.log(Self.tag, "registered BGTaskScheduler identifier=\(identifier) earliest=\(Int(Self.refreshEarliestMinutes)) min")
    }

    /// Schedules when a cap is paired and background sync is on, stops
    /// everything otherwise.
    func reconcile() {
        let current = settings.current
        let skip = BackgroundRunPolicy.skipReason(
            hasPairedDevice: current.hasPairedDevice,
            backgroundSyncEnabled: current.backgroundSyncEnabled,
            hasBLEPermissions: Self.bluetoothUsable(central.state),
        )
        if let skip {
            debugLog.log(Self.tag, "background sync inactive: \(skip.label)")
            stopBackgroundScan()
            return
        }
        startBackgroundScan()
        scheduleRefresh()
    }

    func stopBackgroundScan() {
        watchTask?.cancel()
        watchTask = nil
        if isBackgroundScanActive {
            scanner.stopBackgroundScan()
            isBackgroundScanActive = false
        }
    }

    private func startBackgroundScan() {
        guard watchTask == nil else { return }
        isBackgroundScanActive = true
        debugLog.log(Self.tag, "background scan started (service 0x180A, no duplicates)")
        scanner.startBackgroundScan()
        watchTask = Task { @MainActor [weak self] in
            await self?.watchForCap()
        }
    }

    private func watchForCap() async {
        let current = settings.current
        // Throttle: wait out the remainder of the minimum interval since the
        // last successful sync (manual or background) before even looking.
        // The scan keeps running meanwhile so iOS can still wake us later.
        if let lastMs = current.lastSyncMs {
            let elapsed = Date().timeIntervalSince1970 - Double(lastMs) / 1000
            let remaining = Self.minimumSyncIntervalSeconds - elapsed
            if remaining > 0 {
                debugLog.log(Self.tag, "last sync \(Int(elapsed)) s ago; next background sync in \(Int(remaining)) s")
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                if Task.isCancelled { return }
                // Restart the scan so the discovery list reflects "in range now",
                // not an advertisement seen 15 minutes ago.
                scanner.stopBackgroundScan()
                scanner.startBackgroundScan()
            }
        }
        var found: DiscoveredCap?
        while !Task.isCancelled {
            if let cap = central.discoveredSorted.first(where: {
                $0.isSameCap(pairedName: current.pairedDeviceName, pairedDeviceIdHex: current.pairedDeviceIdHex)
            }) {
                found = cap
                break
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.discoveryPollMilliseconds) * 1_000_000)
        }
        guard !Task.isCancelled else { return }
        if let found {
            debugLog.log(Self.tag, "discovery wake: \(found.name ?? "?") rssi=\(found.rssi) id=\(found.address)")
        }
        scanner.stopBackgroundScan()
        _ = await runBackgroundJob(
            source: "background discovery",
            budgetSeconds: BleScanner.connectScanSeconds,
            allowReconnectRetry: false,
        )
        // After a background sync: disconnect (done by the engine), restart the scan.
        watchTask = nil
        if !Task.isCancelled { startBackgroundScan() }
    }

    // MARK: - BGAppRefreshTask

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: Self.refreshEarliestMinutes * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
            debugLog.log(Self.tag, "scheduled \(Self.refreshTaskIdentifier), earliest \(Int(Self.refreshEarliestMinutes)) min from now")
        } catch {
            debugLog.error(Self.tag, "could not schedule \(Self.refreshTaskIdentifier)", error: error)
        }
    }

    func runRefreshTask(_ task: BGAppRefreshTask) async {
        debugLog.log(Self.tag, "\(Self.refreshTaskIdentifier) fired, budget \(Int(Self.refreshBudgetSeconds)) s")
        scheduleRefresh()
        if let lastMs = settings.current.lastSyncMs,
           Date().timeIntervalSince1970 - Double(lastMs) / 1000 < Self.minimumSyncIntervalSeconds {
            debugLog.log(Self.tag, "refresh skipped: synced less than \(Int(Self.minimumSyncIntervalSeconds / 60)) min ago")
            task.setTaskCompleted(success: true)
            return
        }
        let work = Task { @MainActor [weak self] in
            await self?.runBackgroundJob(
                source: "BGAppRefreshTask",
                budgetSeconds: Self.refreshBudgetSeconds,
                allowReconnectRetry: false,
            )
        }
        task.expirationHandler = {
            // `Task` is a Sendable struct; the expiration handler may run on
            // any queue, cancelling is thread-safe.
            work.cancel()
        }
        let evaluation = await work.value
        let success = evaluation?.verdict != BackgroundRunPolicy.Verdict.retry
        task.setTaskCompleted(success: success)
        debugLog.log(Self.tag, "\(Self.refreshTaskIdentifier) completed success=\(success)")
    }

    // MARK: - One run

    @discardableResult
    private func runBackgroundJob(source: String, budgetSeconds: Double, allowReconnectRetry: Bool) async -> BackgroundRunPolicy.Evaluation {
        let current = settings.current
        debugLog.log(Self.tag, "run start (\(source), misses so far \(current.consecutiveCapMisses), budget \(Int(budgetSeconds)) s)")
        let outcome = await engine.runBackgroundAttempt(
            budgetSeconds: budgetSeconds,
            allowReconnectRetry: allowReconnectRetry,
        )
        let evaluation = BackgroundRunPolicy.evaluate(outcome, previousMisses: current.consecutiveCapMisses)
        settings.setLastBackgroundRun(
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
            outcome: outcome.label(),
            consecutiveCapMisses: evaluation.consecutiveMisses,
        )
        if evaluation.quiet {
            debugLog.log(Self.tag, "cap not found for \(evaluation.consecutiveMisses) consecutive runs; staying silent (no notification)")
        }
        debugLog.log(Self.tag, "run done (\(source)): \(outcome.label()) → \(evaluation.verdict.rawValue)")
        return evaluation
    }

    /// The Bluetooth permission is granted as long as the manager is not
    /// explicitly unauthorized/unsupported. `poweredOff` still allows scans to
    /// be started once the user turns Bluetooth back on.
    nonisolated static func bluetoothUsable(_ state: CBManagerState) -> Bool {
        switch state {
        case .unauthorized, .unsupported: false
        default: true
        }
    }
}
