import CoreBluetooth
import Foundation
import Observation
import UserNotifications

/// One day's intake for the History chart (`AppModel.dailyTotals(days:)`).
nonisolated struct DailyTotal: Sendable, Equatable, Identifiable {
    /// Start of the day in the current calendar.
    let day: Date
    let ml: Double

    var id: Date { day }
}

/// The app's single view model: navigation, the scan list, the Home data and
/// the Settings/Debug actions. Port of the Android `MainViewModel`, with the
/// Cap-observed values pushed by the sync engine and pulled from the store.
@MainActor
@Observable
final class AppModel {
    enum Screen: Hashable {
        case onboarding
        case scan
        case home
        case reminder
        case settings
        case debug
        /// Pushed from Settings (bottle profile list).
        case bottleProfile
    }

    /// Bottom tab bar of the main screen (`MainTabView`). The Ring screen
    /// lives under Settings since UX round 2.
    enum MainTab: Hashable {
        case home
        case history
        case settings
    }

    /// Onboarding steps (UX round 2): Health first, optional things only
    /// when something is missing, then the scan list.
    enum OnboardingStep: Int, Hashable {
        case welcome = 1
        case optional = 2
        case findBottle = 3
    }

    /// Notification permission as the onboarding step reports it.
    enum NotificationStatus: Equatable {
        case notDetermined
        case denied
        case authorized
    }

    /// Battery colour tier derived from the configured thresholds.
    enum BatteryTier {
        case ok
        case low
        case critical
    }

    let container: AppContainer

    var screen: Screen
    /// Pushed screens inside the Settings tab (`.reminder`, `.debug`, `.bottleProfile`).
    var path: [Screen] = []
    var tab: MainTab = .home

    // Onboarding / permissions
    var hasRequestedNotifications = false
    var onboardingStep: OnboardingStep = .welcome
    /// Apple Health *write* grant (the only grant HealthKit reports).
    private(set) var healthWriteGranted = false
    /// True while the Health sheet was never shown for our types.
    private(set) var healthCanStillAsk = true
    private(set) var notificationStatus: NotificationStatus = .notDetermined

    // Daily target
    /// Latest values from Apple Health (nil = not available: no data *or*
    /// no read access — HealthKit does not tell them apart).
    private(set) var healthBody: HealthBodyValues = .none

    // Scan
    private(set) var scanning = false
    private(set) var discoveredCaps: [DiscoveredCap] = []
    private(set) var scanError: String?
    private var scanTask: Task<Void, Never>?
    /// Only the connection phase stays on the scan screen.
    private(set) var pairingCap: DiscoveredCap?
    private(set) var connectionNotice: String?
    private(set) var initialImportRunning: Bool = false
    private let connectionHandoff = ConnectionHandoff()

    // Home
    private(set) var settings: AppSettings
    private(set) var latestBattery: BatterySample?
    private(set) var todayEvents: [DrinkEvent] = []
    private(set) var latestTof: TofLogEntry?
    private(set) var tofCount = 0
    var syncStatus: SyncEngine.Status { container.syncEngine.status }
    var connectionState: ConnectionState { container.syncEngine.activeClient?.connectionState ?? .disconnected }

    // Settings
    private(set) var healthWriteMessage: String?
    private(set) var healthTrackedCount = 0
    private(set) var profileMessage: String?
    private(set) var healthAuthorized = false

    // Reminder
    private(set) var reminderConfig: CapReminderConfig?
    private(set) var reminderMessage: String?
    private(set) var drinkReminderMessage: String?
    private(set) var updatingDrinkReminders = false
    var reminderStatus: SyncEngine.ReminderStatus { container.syncEngine.reminder }

    // Debug
    private(set) var debugEntries: [DebugEntry] = []
    private var debugTask: Task<Void, Never>?

    init(container: AppContainer) {
        self.container = container
        self.settings = container.settings.current
        self.screen = container.settings.current.hasPairedDevice ? .home : .onboarding
        // Do not restore notifications planned with guessed hours by an older build.
        if settings.drinkRemindersEnabled, settings.ringWindow?.isUsable != true {
            container.settings.setDrinkReminders(
                enabled: false,
                frequencyMinutes: settings.drinkReminderFrequencyMinutes,
                onlyWhenBehind: settings.drinkReminderOnlyWhenBehind,
            )
            settings = container.settings.current
            drinkReminderMessage = "Reminders are off until the bottle's ring hours are known. Keep the cap nearby and turn reminders on to read them."
        }
        container.onSyncCompleted = { [weak self] in
            await self?.refresh()
        }
        container.drinkReminders.targetMlProvider = { [weak self] in
            // Reads settings directly: the scheduler may run before the model
            // refreshed, and after a background sync with no UI at all.
            guard let self else { return Double(HydrationTarget.defaultMl) }
            return Double(self.resolveTarget(settings: self.container.settings.current).ml)
        }
        startDebugStream()
    }

    // MARK: - Refresh

    func refresh() async {
        settings = container.settings.current
        latestBattery = try? await container.store.latestBatterySample()
        latestTof = try? await container.store.latestTofLog()
        tofCount = (try? await container.store.tofLogCount()) ?? 0
        let range = Self.todayRangeSec()
        todayEvents = (try? await container.store.drinkEvents(fromSec: range.from, toSec: range.to)) ?? []
        healthTrackedCount = await container.healthWriter.trackedRecordCount()
        healthAuthorized = container.healthWriter.isAuthorized
        healthWriteGranted = healthAuthorized
    }

    /// Once per app start and after every Health authorization: latest
    /// weight + biological sex for the daily target.
    func refreshHealthBody() async {
        guard container.healthWriter.isAvailable else {
            healthBody = .none
            return
        }
        let values = await container.healthWriter.readBodyValues()
        if values != healthBody {
            healthBody = values
            let weight = values.weightKg.map { String(format: "%.1f kg", $0) } ?? "n/a"
            container.debugLog.log("ui", "apple health body values: weight=\(weight) sex=\(values.sex?.rawValue ?? "n/a") (nil = not available; read grants are not observable)")
            container.drinkReminders.replanSoon()
        }
    }

    // MARK: - Daily target

    /// The resolved daily target (manual override → Apple Health → manual
    /// body values → default). An editable estimate, not a prescription.
    var dailyTarget: HydrationTarget.TargetResult { resolveTarget(settings: settings) }

    var dailyTargetMl: Double { Double(dailyTarget.ml) }

    /// "Target 2.45 L · from your weight in Apple Health (70 kg)".
    var dailyTargetCaption: String { HydrationTarget.caption(dailyTarget) }

    private func resolveTarget(settings: AppSettings) -> HydrationTarget.TargetResult {
        HydrationTarget.resolve(
            useEstimate: settings.dailyTargetUseEstimate,
            overrideMl: settings.dailyTargetOverrideMl,
            healthWeightKg: healthBody.weightKg,
            healthSex: healthBody.sex,
            manualWeightKg: settings.manualWeightKg,
            manualSex: settings.manualSex.flatMap { HydrationTarget.Sex(rawValue: $0) },
        )
    }

    func setDailyTarget(useEstimate: Bool, overrideMl: Int?) {
        container.settings.setDailyTarget(useEstimate: useEstimate, overrideMl: overrideMl)
        settings = container.settings.current
        container.debugLog.log("ui", "daily target useEstimate=\(useEstimate) override=\(overrideMl.map(String.init) ?? "nil") → \(dailyTarget.ml) ml")
        container.drinkReminders.replanSoon()
    }

    /// Weight / sex entered by hand (onboarding step 2, Settings).
    func setManualBody(weightKg: Double?, sex: HydrationTarget.Sex?) {
        container.settings.setManualBody(weightKg: weightKg, sex: sex)
        settings = container.settings.current
        container.debugLog.log("ui", "manual body values weight=\(weightKg.map { String(format: "%.1f", $0) } ?? "nil") sex=\(sex?.rawValue ?? "nil") → \(dailyTarget.ml) ml")
        container.drinkReminders.replanSoon()
    }

    /// Missing Health fields are independently editable, even when the other
    /// field is readable. Blank manual values remain optional.
    var needsManualWeightInput: Bool { healthBody.weightKg == nil }
    var needsManualSexInput: Bool { healthBody.sex == nil }
    var bodyValuesMissing: Bool {
        (needsManualWeightInput && settings.manualWeightKg == nil)
            || (needsManualSexInput && settings.manualSex == nil)
    }

    // MARK: - Onboarding

    private var hasMadeHealthChoice = false

    /// Checking the static authorization does not create a central or prompt.
    /// Once Health is connected or skipped, scanning can request Bluetooth.
    func startOnboardingScanIfAllowed() {
        guard screen == .onboarding, pairingCap == nil,
              hasMadeHealthChoice || CBManager.authorization == .allowedAlways,
              !scanning, discoveredCaps.isEmpty else { return }
        startScan(seconds: OnboardingFindBottleStep.onboardingScanSeconds)
    }

    /// Always query the body after the combined request, including when writing
    /// water was declined. HealthKit does not expose read authorization grants.
    @discardableResult
    func connectAppleHealth() async -> Bool {
        _ = await container.healthWriter.requestAuthorization()
        if screen == .onboarding, onboardingStep == .welcome {
            hasMadeHealthChoice = true
            startOnboardingScanIfAllowed()
        }
        await refreshPermissionStatus()
        await refreshHealthBody()
        container.settings.setHealthSyncEnabled(healthWriteGranted)
        settings = container.settings.current
        container.debugLog.log("ui", "apple health water write granted=\(healthWriteGranted)")
        return healthWriteGranted
    }

    func refreshPermissionStatus() async {
        healthWriteGranted = container.healthWriter.isAuthorized
        healthAuthorized = healthWriteGranted
        healthCanStillAsk = await container.healthWriter.canStillAsk()
        switch await container.batteryNotifier.authorizationStatus() {
        case .notDetermined: notificationStatus = .notDetermined
        case .denied: notificationStatus = .denied
        default: notificationStatus = .authorized
        }
    }

    /// Return from iOS/Health Settings, or foreground after a background sync.
    func refreshAfterBecomingActive() async {
        await refreshPermissionStatus()
        await refreshHealthBody()
        await refresh()
        if settings.hasPairedDevice {
            if !connectionHandoff.isRunning { container.backgroundSync.reconcile() }
        } else {
            startOnboardingScanIfAllowed()
        }
        container.drinkReminders.replanSoon()
    }

    @discardableResult
    func requestNotifications() async -> Bool {
        hasRequestedNotifications = true
        let granted = await container.batteryNotifier.requestAuthorization()
        await refreshPermissionStatus()
        container.debugLog.log("ui", "notification permission granted=\(granted)")
        return granted
    }

    /// Unknown central state is not a denial, and can precede manager creation.
    var bluetoothDenied: Bool {
        CBManager.authorization == .denied || CBManager.authorization == .restricted
            || container.central.state == .unauthorized
    }

    /// Denied water writes stay visible even when Health cannot ask again.
    var hasOptionalItemsMissing: Bool {
        (!healthWriteGranted && container.healthWriter.isAvailable)
            || notificationStatus != .authorized
            || bluetoothDenied
            || bodyValuesMissing
    }

    /// Start discovery immediately after either Health choice, before changing
    /// page; already-authorized Welcome scans are not restarted.
    func advanceFromWelcome() async {
        hasMadeHealthChoice = true
        startOnboardingScanIfAllowed()
        await refreshPermissionStatus()
        onboardingStep = hasOptionalItemsMissing ? .optional : .findBottle
    }

    func showFindBottle() {
        onboardingStep = .findBottle
    }

    var todayMl: Double { todayEvents.reduce(0) { $0 + $1.volumeMl } }

    /// Today's drinks, most recent first (the store's order is not guaranteed).
    var todayDrinksNewestFirst: [DrinkEvent] {
        todayEvents.sorted { $0.timestamp > $1.timestamp }
    }

    /// 0…1 progress toward the daily target.
    var todayProgress: Double {
        guard dailyTargetMl > 0 else { return 0 }
        return min(max(todayMl / dailyTargetMl, 0), 1)
    }

    /// False right after pairing, before the first sync stored anything.
    var hasAnyData: Bool {
        latestBattery != nil || latestTof != nil || !todayEvents.isEmpty || tofCount > 0
    }

    /// "LARQ iQ" for a LARQ-family cap, the raw name otherwise.
    var displayName: String {
        guard let name = settings.pairedDeviceName else { return "HydroCap" }
        return name.hasPrefix(DeviceName.prefix) ? "LARQ iQ" : name
    }

    var pairedSerial: String? { settings.pairedDeviceIdHex }

    var batteryTier: BatteryTier? {
        guard let percent = latestBattery?.percent else { return nil }
        if percent <= settings.batteryCriticalPercent { return .critical }
        if percent <= settings.batteryAlertPercent { return .low }
        return .ok
    }

    /// One-line status for the Home header, e.g. "Synced 5 min ago",
    /// "Syncing… pull ToF log (page 12, 60 new)", "Cap not in range".
    var syncStatusLine: String { syncStatusLine(now: Date()) }

    func syncStatusLine(now: Date) -> String {
        switch syncStatus {
        case .running(let step):
            return "Syncing… \(step)"
        case .failed(let reason, _):
            if reason.localizedCaseInsensitiveContains("not found") || reason.localizedCaseInsensitiveContains("no cap matched") {
                return "Cap not in range"
            }
            if reason.localizedCaseInsensitiveContains("busy") || reason.localizedCaseInsensitiveContains("already running") {
                return "Cap busy — try again in a moment"
            }
            return "Sync failed — \(reason)"
        case .idle, .done:
            if connectionState.isActive { return "Connected" }
            guard let lastSync = settings.lastSyncMs else { return "Not synced yet" }
            return "Synced \(Self.relativeString(fromMs: lastSync, now: now))"
        }
    }

    /// "just now", "5 min ago", "3 h ago", or the date for older syncs.
    static func relativeString(fromMs timestampMs: Int64, now: Date) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestampMs) / 1000)
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h ago" }
        if Calendar.current.isDateInYesterday(date) { return "yesterday \(timeString(date))" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    /// All stored drink events, oldest first (Home "Show all", History).
    func allDrinkEvents() async -> [DrinkEvent] {
        (try? await container.store.allDrinkEvents()) ?? []
    }

    /// Intake per calendar day for the last `days` days (today last), zero
    /// for days without drinks.
    func dailyTotals(days: Int) async -> [DailyTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard days > 0, let start = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        let fromSec = Int64(start.timeIntervalSince1970)
        let toSec = Int64(today.timeIntervalSince1970) + 86_400
        let events = (try? await container.store.drinkEvents(fromSec: fromSec, toSec: toSec)) ?? []
        var totals: [Date: Double] = [:]
        for event in events {
            let day = calendar.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(event.timestamp)))
            totals[day, default: 0] += event.volumeMl
        }
        return (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start).map { DailyTotal(day: $0, ml: totals[$0] ?? 0) }
        }
    }

    /// Drink events inside a History range (`[rangeStart, rangeEnd)`).
    func drinkEvents(in range: HistoryAggregation.Range, now: Date = Date()) async -> [DrinkEvent] {
        let calendar = Calendar.current
        let start = HistoryAggregation.rangeStart(range: range, now: now, calendar: calendar)
        let end = HistoryAggregation.rangeEnd(range: range, now: now, calendar: calendar)
        return (try? await container.store.drinkEvents(fromSec: Int64(start.timeIntervalSince1970), toSec: Int64(end.timeIntervalSince1970))) ?? []
    }

    // MARK: - History chart controls

    var historyRange: HistoryAggregation.Range {
        HistoryAggregation.Range(rawValue: settings.historyRange) ?? .week
    }

    func setHistoryControls(range: HistoryAggregation.Range? = nil, chartType: String? = nil, yAxis: String? = nil) {
        container.settings.setHistoryControls(range: range?.rawValue, chartType: chartType, yAxis: yAxis)
        settings = container.settings.current
    }

    // MARK: - Drink reminders

    /// Enabling needs known cap hours and notification permission. A read uses
    /// the existing reminder GET path, never applies or changes ring settings.
    func setDrinkReminders(enabled: Bool, frequencyMinutes: Int? = nil, onlyWhenBehind: Bool? = nil) async {
        guard !updatingDrinkReminders else { return }
        updatingDrinkReminders = true
        defer { updatingDrinkReminders = false }
        drinkReminderMessage = nil
        var enable = enabled
        if enable, container.settings.current.ringWindow?.isUsable != true {
            if container.settings.current.hasPairedDevice {
                drinkReminderMessage = "Reading your bottle's ring hours…"
                await loadReminder()
            }
            if container.settings.current.ringWindow?.isUsable != true {
                enable = false
                drinkReminderMessage = "Reminders stay off because the bottle's ring hours are unknown. Wake the cap, keep it nearby, then turn reminders on to try again."
            } else {
                drinkReminderMessage = nil
            }
        }
        if enable, !(await container.batteryNotifier.isAuthorized()) {
            enable = await requestNotifications()
            if !enable {
                drinkReminderMessage = "Reminders stay off because notifications are not allowed. Enable notifications for HydroCap in iOS Settings."
                container.debugLog.log("ui", "drink reminders stay off: notification permission missing")
            }
        }
        let current = container.settings.current
        container.settings.setDrinkReminders(
            enabled: enable,
            frequencyMinutes: frequencyMinutes ?? current.drinkReminderFrequencyMinutes,
            onlyWhenBehind: onlyWhenBehind ?? current.drinkReminderOnlyWhenBehind,
        )
        settings = container.settings.current
        container.debugLog.log("ui", "drink reminders enabled=\(enable) every \(settings.drinkReminderFrequencyMinutes) min onlyWhenBehind=\(settings.drinkReminderOnlyWhenBehind)")
        await container.drinkReminders.replan()
    }

    /// Reminder window line for Settings.
    var reminderWindow: DrinkReminderPlanner.Window { settings.ringWindow ?? .fallback }
    var reminderWindowFromCap: Bool { settings.ringWindow != nil }

    // MARK: - Navigation

    func navigate(_ screen: Screen) {
        switch screen {
        case .home:
            path = []
            tab = .home
            self.screen = .home
        case .scan:
            stopScan()
            path = []
            self.screen = .scan
        case .onboarding:
            path = []
            self.screen = .onboarding
        case .reminder:
            tab = .settings
            self.screen = .home
            if !path.contains(.reminder) { path.append(.reminder) }
        case .settings:
            path = []
            tab = .settings
            self.screen = .home
        case .debug:
            tab = .settings
            self.screen = .home
            if !path.contains(.debug) { path.append(.debug) }
        case .bottleProfile:
            tab = .settings
            self.screen = .home
            if !path.contains(.bottleProfile) { path.append(.bottleProfile) }
        }
    }

    func finishOnboarding() {
        screen = settings.hasPairedDevice ? .home : .scan
        path = []
    }

    // MARK: - Scan & pair

    /// Foreground scan for the onboarding/scan screens. Results found so far
    /// are visible while the scan runs (the central publishes them live).
    func startScan(seconds: Double = BleScanner.foregroundScanWindowSeconds) {
        guard !connectionHandoff.isRunning, pairingCap == nil else { return }
        stopScan()
        scanning = true
        scanError = nil
        discoveredCaps = []
        scanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let caps = await container.scanner.scanFor(seconds: seconds)
            guard !Task.isCancelled else { return }
            if let error = container.central.lastScanError { scanError = error }
            discoveredCaps = caps
            scanning = false
        }
    }

    /// Caps seen so far: the finished list, or the central's live results
    /// while a scan is still running (onboarding shows them immediately).
    var visibleCaps: [DiscoveredCap] {
        scanning ? container.central.discoveredSorted : discoveredCaps
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        scanning = false
        container.central.stopScan()
    }

    /// Persist and navigate only at GATT readiness; the same app-owned task
    /// keeps importing logs after the scan view disappears.
    func selectCap(_ cap: DiscoveredCap) async {
        guard !connectionHandoff.isRunning, pairingCap == nil else { return }
        guard !container.syncEngine.isRunning else {
            scanError = "The bottle is busy. Try again in a moment."
            return
        }
        pairingCap = cap
        scanError = nil
        dismissConnectionNotice()
        container.syncEngine.backgroundSyncSuspended = true
        container.backgroundSync.stopBackgroundScan()
        stopScan()
        await connectionHandoff.run(
            operation: { ready in
                _ = try await self.container.syncEngine.sync(target: cap, onConnectionReady: ready)
            },
            onReady: { identity in
                self.container.settings.setPairedDevice(name: identity.name, deviceIdHex: identity.deviceIdHex)
                self.settings = self.container.settings.current
                self.initialImportRunning = true
                self.pairingCap = nil
                self.connectionNotice = "Bottle connected"
                self.navigate(.home)
                self.container.drinkReminders.replanSoon()
                self.container.debugLog.log("ui", "cap ready; opening Home while first import continues")
            },
            onFailure: { error, reachedReady in
                self.container.debugLog.error("ui", reachedReady ? "initial import failed" : "connection failed", error: error)
                if !reachedReady {
                    self.scanError = "Could not connect: \(error). Try again."
                }
                // A later import failure is shown by syncStatus on Home; the
                // verified pairing and the user's current tab remain intact.
            },
            onFinished: {
                await self.refresh()
                self.pairingCap = nil
                self.initialImportRunning = false
                self.container.syncEngine.backgroundSyncSuspended = false
                self.container.backgroundSync.reconcile()
            }
        )
    }

    func dismissConnectionNotice() {
        connectionNotice = nil
    }

    func forgetDevice() async {
        container.backgroundSync.stopBackgroundScan()
        container.settings.forgetDevice()
        await container.drinkReminders.replan()
        try? await container.store.deleteAllDevices()
        container.debugLog.log("ui", "forgot paired device; background sync stopped")
        await refresh()
        screen = .scan
        tab = .home
        path = []
    }

    // MARK: - Home actions

    func syncNow() async {
        do {
            _ = try await container.syncEngine.sync()
        } catch {
            container.debugLog.error("ui", "sync now failed", error: error)
        }
        await refresh()
    }

    func liveTof() async -> (distanceMm: Int, kcps: Int)? {
        do {
            let measurement = try await container.syncEngine.liveTof()
            await refresh()
            return measurement
        } catch {
            container.debugLog.error("ui", "live ToF failed", error: error)
            return nil
        }
    }

    func readAllSettings() async {
        do {
            _ = try await container.syncEngine.readAllSettings()
        } catch {
            container.debugLog.error("ui", "read all settings failed", error: error)
        }
    }

    // MARK: - Reminder screen

    func loadReminder() async {
        do {
            let config = try await container.syncEngine.readReminder()
            reminderConfig = config
            reminderMessage = "read from the cap at \(Self.timeString(Date()))"
        } catch {
            reminderConfig = nil
            reminderMessage = "\(error)"
        }
        // The GET stores the actual cap hours used by local notifications.
        settings = container.settings.current
    }

    @discardableResult
    func applyReminder(_ patch: ReminderPatch) async -> CapReminderConfig? {
        do {
            let config = try await container.syncEngine.applyReminder(patch)
            reminderConfig = config
            reminderMessage = "written and read back from the cap"
            return config
        } catch {
            reminderMessage = "\(error)"
            return nil
        }
    }

    // MARK: - Settings screen

    func setAppearance(_ appearance: String) {
        container.settings.setAppearance(appearance)
        container.debugLog.log("ui", "appearance → \(appearance)")
        settings = container.settings.current
    }

    func setBatteryThresholds(alert: Int, critical: Int) {
        container.settings.setBatteryThresholds(alertPercent: alert, criticalPercent: critical)
        container.debugLog.log("ui", "battery thresholds alert=\(alert) critical=\(critical) (alerts re-armed)")
        settings = container.settings.current
    }

    func setBackgroundSyncEnabled(_ enabled: Bool) {
        container.settings.setBackgroundSyncEnabled(enabled)
        if !connectionHandoff.isRunning { container.backgroundSync.reconcile() }
        container.debugLog.log("ui", "background sync \(enabled ? "enabled" : "disabled")")
        settings = container.settings.current
    }

    /// Toggle on: request authorization, persist, then write every stored event.
    func setHealthSyncEnabled(_ enabled: Bool) async {
        if enabled {
            let granted = await connectAppleHealth()
            guard granted else {
                healthWriteMessage = "Writing water is not allowed. Open Apple Health → profile → Apps and Services → HydroCap to change access. Body values can still be used when available."
                container.debugLog.log("ui", "apple health water write permission missing")
                return
            }
            container.settings.setHealthSyncEnabled(true)
            settings = container.settings.current
            container.debugLog.log("ui", "health sync enabled → writing all stored drink events")
            await writeAllToHealth()
        } else {
            container.settings.setHealthSyncEnabled(false)
            settings = container.settings.current
            healthWriteMessage = nil
            container.debugLog.log("ui", "health sync disabled (records already written stay in Apple Health)")
        }
    }

    /// "Write to Apple Health now": every stored drink event, no BLE sync.
    func writeAllToHealth() async {
        let result = await container.healthWriter.upsertAllStored()
        healthTrackedCount = await container.healthWriter.trackedRecordCount()
        healthWriteMessage = result.summary
        container.debugLog.log("ui", "apple health one-off: inserted=\(result.inserted) updated=\(result.updated) skipped=\(result.skipped) error=\(result.error ?? "none")")
    }

    /// Profile change → drink-event rebuild → health upsert when enabled.
    func setBottleProfile(_ profile: BottleProfile) async {
        container.settings.setBottleProfile(profile.id, customCoefficients: profile.id == BottleProfile.idCustom ? profile.coefficients : nil)
        do {
            let events = try await container.drinkEventBuilder.rebuild(profile: profile)
            profileMessage = "Rebuilt \(events.count) drink event(s) with \(profile.label)."
        } catch {
            profileMessage = "Rebuild failed: \(error)"
        }
        container.debugLog.log("ui", "bottle profile → \(profile.id)")
        settings = container.settings.current
        if settings.healthSyncEnabled { await writeAllToHealth() }
    }

    func setProfileMessage(_ message: String) {
        profileMessage = message
    }

    // MARK: - Debug screen

    func clearDebugLog() {
        container.debugLog.clearMemory()
    }

    var debugText: String { container.debugLog.dumpText() }

    private func startDebugStream() {
        debugTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await entries in container.debugLog.updates() {
                debugEntries = entries
            }
        }
    }

    // MARK: - Helpers

    static func todayRangeSec() -> (from: Int64, to: Int64) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        let from = Int64(start.timeIntervalSince1970)
        return (from, from + 86_400)
    }

    static func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// "Battery measured at" line for the Home screen.
    var batteryMeasuredAt: String? {
        guard let latestBattery else { return nil }
        return Self.timeString(Date(timeIntervalSince1970: TimeInterval(latestBattery.timestamp)))
    }

    var fillEstimate: (ml: Double, percent: Double, distanceMm: Int, kcps: Int, at: String)? {
        guard let latestTof else { return nil }
        let profile = settings.bottleProfile()
        guard latestTof.distanceMm < profile.tofMaxMm else { return nil }
        let ml = profile.volumeMl(latestTof.distanceMm)
        let percent = profile.fullVolumeMl > 0 ? min(max(ml / profile.fullVolumeMl * 100, 0), 100) : 0
        return (ml, percent, latestTof.distanceMm, latestTof.kcps, Self.timeString(Date(timeIntervalSince1970: TimeInterval(latestTof.timestamp))))
    }
}
