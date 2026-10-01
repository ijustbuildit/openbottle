import Foundation

/// User settings; everything stays on device (UserDefaults).
nonisolated struct AppSettings: Sendable, Equatable {
    /// Identity of the paired cap: advertised name + decoded serial. Never a MAC.
    var pairedDeviceName: String?
    var pairedDeviceIdHex: String?
    var batteryAlertPercent: Int
    var batteryCriticalPercent: Int
    var healthSyncEnabled: Bool
    var bottleProfileId: String
    var customCoefficients: [Double]?
    var lastSyncMs: Int64?
    var lastCapBottleSizeMl: Int?
    /// Battery thresholds that have fired and not yet re-armed (see `BatteryAlertPolicy`).
    var firedBatteryThresholds: Set<Int>
    /// Background sync (CoreBluetooth background scan + BGAppRefreshTask); default on.
    var backgroundSyncEnabled: Bool
    var lastBackgroundRunMs: Int64?
    var lastBackgroundOutcome: String?
    /// Consecutive background runs that did not find the cap (see `BackgroundRunPolicy`).
    var consecutiveCapMisses: Int
    /// UI appearance: `"system"` (follow iOS), `"light"` or `"dark"`.
    var appearance: String
    /// History chart controls (`HistoryAggregation.Range.rawValue`,
    /// `"bars"|"line"|"area"`, `"auto"|"fixed"`).
    var historyRange: String
    var historyChartType: String
    var historyYAxis: String
    /// Daily target: estimate from Apple Health / manual body values unless
    /// `dailyTargetUseEstimate` is off and an override is set.
    var dailyTargetUseEstimate: Bool
    var dailyTargetOverrideMl: Int?
    /// Body values entered by hand (used only when Apple Health has none).
    var manualWeightKg: Double?
    /// `HydrationTarget.Sex.rawValue`.
    var manualSex: String?
    /// Drink reminders (local notifications), default off.
    var drinkRemindersEnabled: Bool
    var drinkReminderFrequencyMinutes: Int
    var drinkReminderOnlyWhenBehind: Bool
    /// Reminder-ring hours as last read from the cap (seconds of day,
    /// midnight = 86400); nil until the first read.
    var lastRingStartSec: Int?
    var lastRingStopSec: Int?

    init(
        pairedDeviceName: String? = nil,
        pairedDeviceIdHex: String? = nil,
        batteryAlertPercent: Int = SettingsDefaults.batteryAlert,
        batteryCriticalPercent: Int = SettingsDefaults.batteryCritical,
        healthSyncEnabled: Bool = false,
        bottleProfileId: String = BottleProfile.default.id,
        customCoefficients: [Double]? = nil,
        lastSyncMs: Int64? = nil,
        lastCapBottleSizeMl: Int? = nil,
        firedBatteryThresholds: Set<Int> = [],
        backgroundSyncEnabled: Bool = true,
        lastBackgroundRunMs: Int64? = nil,
        lastBackgroundOutcome: String? = nil,
        consecutiveCapMisses: Int = 0,
        appearance: String = SettingsDefaults.appearance,
        historyRange: String = SettingsDefaults.historyRange,
        historyChartType: String = SettingsDefaults.historyChartType,
        historyYAxis: String = SettingsDefaults.historyYAxis,
        dailyTargetUseEstimate: Bool = true,
        dailyTargetOverrideMl: Int? = nil,
        manualWeightKg: Double? = nil,
        manualSex: String? = nil,
        drinkRemindersEnabled: Bool = false,
        drinkReminderFrequencyMinutes: Int = SettingsDefaults.drinkReminderFrequencyMinutes,
        drinkReminderOnlyWhenBehind: Bool = true,
        lastRingStartSec: Int? = nil,
        lastRingStopSec: Int? = nil,
    ) {
        self.pairedDeviceName = pairedDeviceName
        self.pairedDeviceIdHex = pairedDeviceIdHex
        self.batteryAlertPercent = batteryAlertPercent
        self.batteryCriticalPercent = batteryCriticalPercent
        self.healthSyncEnabled = healthSyncEnabled
        self.bottleProfileId = bottleProfileId
        self.customCoefficients = customCoefficients
        self.lastSyncMs = lastSyncMs
        self.lastCapBottleSizeMl = lastCapBottleSizeMl
        self.firedBatteryThresholds = firedBatteryThresholds
        self.backgroundSyncEnabled = backgroundSyncEnabled
        self.lastBackgroundRunMs = lastBackgroundRunMs
        self.lastBackgroundOutcome = lastBackgroundOutcome
        self.consecutiveCapMisses = consecutiveCapMisses
        self.appearance = appearance
        self.historyRange = historyRange
        self.historyChartType = historyChartType
        self.historyYAxis = historyYAxis
        self.dailyTargetUseEstimate = dailyTargetUseEstimate
        self.dailyTargetOverrideMl = dailyTargetOverrideMl
        self.manualWeightKg = manualWeightKg
        self.manualSex = manualSex
        self.drinkRemindersEnabled = drinkRemindersEnabled
        self.drinkReminderFrequencyMinutes = drinkReminderFrequencyMinutes
        self.drinkReminderOnlyWhenBehind = drinkReminderOnlyWhenBehind
        self.lastRingStartSec = lastRingStartSec
        self.lastRingStopSec = lastRingStopSec
    }

    var hasPairedDevice: Bool { pairedDeviceName != nil }

    /// The reminder window from the cap's ring hours, or the 08:00–22:00
    /// fallback before the first read.
    var ringWindow: DrinkReminderPlanner.Window? {
        guard let lastRingStartSec, let lastRingStopSec else { return nil }
        return DrinkReminderPlanner.Window(startSec: lastRingStartSec, stopSec: lastRingStopSec)
    }

    /// Resolves the selected `BottleProfile`, falling back to the default body.
    func bottleProfile() -> BottleProfile {
        if bottleProfileId == BottleProfile.idCustom {
            if let customCoefficients, customCoefficients.count == 5 {
                return BottleProfile(id: BottleProfile.idCustom, label: "Custom", nominalMl: 0, coefficients: customCoefficients)
            }
            return BottleProfile.default
        }
        return BottleProfile.builtIn(id: bottleProfileId) ?? BottleProfile.default
    }
}

nonisolated enum SettingsDefaults {
    static let batteryAlert = 10
    static let batteryCritical = 5
    static let minBatteryThreshold = 1
    static let maxBatteryThreshold = 50
    static let appearance = "system"
    /// Accepted `AppSettings.appearance` values, in the order the UI offers them.
    static let appearanceOptions = ["system", "light", "dark"]
    static let historyRange = HistoryAggregation.Range.week.rawValue
    static let historyChartType = "bars"
    static let historyChartTypeOptions = ["bars", "line", "area"]
    static let historyYAxis = "auto"
    static let historyYAxisOptions = ["auto", "fixed"]
    static let drinkReminderFrequencyMinutes = DrinkReminderPlanner.defaultFrequencyMinutes
}

/// Small typed settings store (the Kotlin port keeps these in DataStore; on iOS
/// UserDefaults is the platform-native equivalent for a handful of scalars).
@MainActor
final class SettingsStore {
    private enum Key {
        static let pairedName = "paired_device_name"
        static let pairedId = "paired_device_id_hex"
        static let batteryAlert = "battery_alert_percent"
        static let batteryCritical = "battery_critical_percent"
        static let healthSync = "health_sync_enabled"
        static let bottleProfile = "bottle_profile_id"
        static let customCoefficients = "custom_coefficients"
        static let lastSync = "last_sync_ms"
        static let lastCapBottleSize = "last_cap_bottle_size_ml"
        static let firedBatteryThresholds = "fired_battery_thresholds"
        static let backgroundSync = "background_sync_enabled"
        static let lastBackgroundRun = "last_background_run_ms"
        static let lastBackgroundOutcome = "last_background_outcome"
        static let consecutiveCapMisses = "consecutive_cap_misses"
        static let appearance = "appearance"
        static let historyRange = "history_range"
        static let historyChartType = "history_chart_type"
        static let historyYAxis = "history_y_axis"
        static let dailyTargetUseEstimate = "daily_target_use_estimate"
        static let dailyTargetOverride = "daily_target_override_ml"
        static let manualWeightKg = "manual_weight_kg"
        static let manualSex = "manual_sex"
        static let drinkRemindersEnabled = "drink_reminders_enabled"
        static let drinkReminderFrequency = "drink_reminder_frequency_minutes"
        static let drinkReminderOnlyWhenBehind = "drink_reminder_only_when_behind"
        static let lastRingStart = "last_ring_start_sec"
        static let lastRingStop = "last_ring_stop_sec"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var current: AppSettings {
        AppSettings(
            pairedDeviceName: defaults.string(forKey: Key.pairedName),
            pairedDeviceIdHex: defaults.string(forKey: Key.pairedId),
            batteryAlertPercent: defaults.object(forKey: Key.batteryAlert) as? Int ?? SettingsDefaults.batteryAlert,
            batteryCriticalPercent: defaults.object(forKey: Key.batteryCritical) as? Int ?? SettingsDefaults.batteryCritical,
            healthSyncEnabled: defaults.bool(forKey: Key.healthSync),
            bottleProfileId: defaults.string(forKey: Key.bottleProfile) ?? BottleProfile.default.id,
            customCoefficients: parseCoefficients(defaults.string(forKey: Key.customCoefficients)),
            lastSyncMs: int64(defaults, Key.lastSync),
            lastCapBottleSizeMl: defaults.object(forKey: Key.lastCapBottleSize) as? Int,
            firedBatteryThresholds: parseThresholds(defaults.string(forKey: Key.firedBatteryThresholds)),
            backgroundSyncEnabled: defaults.object(forKey: Key.backgroundSync) as? Bool ?? true,
            lastBackgroundRunMs: int64(defaults, Key.lastBackgroundRun),
            lastBackgroundOutcome: defaults.string(forKey: Key.lastBackgroundOutcome),
            consecutiveCapMisses: defaults.object(forKey: Key.consecutiveCapMisses) as? Int ?? 0,
            appearance: Self.validAppearance(defaults.string(forKey: Key.appearance)),
            historyRange: Self.valid(defaults.string(forKey: Key.historyRange), in: HistoryAggregation.Range.allCases.map(\.rawValue), default: SettingsDefaults.historyRange),
            historyChartType: Self.valid(defaults.string(forKey: Key.historyChartType), in: SettingsDefaults.historyChartTypeOptions, default: SettingsDefaults.historyChartType),
            historyYAxis: Self.valid(defaults.string(forKey: Key.historyYAxis), in: SettingsDefaults.historyYAxisOptions, default: SettingsDefaults.historyYAxis),
            dailyTargetUseEstimate: defaults.object(forKey: Key.dailyTargetUseEstimate) as? Bool ?? true,
            dailyTargetOverrideMl: defaults.object(forKey: Key.dailyTargetOverride) as? Int,
            manualWeightKg: defaults.object(forKey: Key.manualWeightKg) as? Double,
            manualSex: defaults.string(forKey: Key.manualSex).flatMap { HydrationTarget.Sex(rawValue: $0)?.rawValue },
            drinkRemindersEnabled: defaults.bool(forKey: Key.drinkRemindersEnabled),
            drinkReminderFrequencyMinutes: defaults.object(forKey: Key.drinkReminderFrequency) as? Int ?? SettingsDefaults.drinkReminderFrequencyMinutes,
            drinkReminderOnlyWhenBehind: defaults.object(forKey: Key.drinkReminderOnlyWhenBehind) as? Bool ?? true,
            lastRingStartSec: defaults.object(forKey: Key.lastRingStart) as? Int,
            lastRingStopSec: defaults.object(forKey: Key.lastRingStop) as? Int,
        )
    }

    /// Unknown or missing values fall back to "system".
    private static func validAppearance(_ raw: String?) -> String {
        guard let raw, SettingsDefaults.appearanceOptions.contains(raw) else { return SettingsDefaults.appearance }
        return raw
    }

    private static func valid(_ raw: String?, in options: [String], default fallback: String) -> String {
        guard let raw, options.contains(raw) else { return fallback }
        return raw
    }

    func setAppearance(_ appearance: String) {
        defaults.set(Self.validAppearance(appearance), forKey: Key.appearance)
    }

    // MARK: History chart controls

    func setHistoryControls(range: String? = nil, chartType: String? = nil, yAxis: String? = nil) {
        if let range { defaults.set(Self.valid(range, in: HistoryAggregation.Range.allCases.map(\.rawValue), default: SettingsDefaults.historyRange), forKey: Key.historyRange) }
        if let chartType { defaults.set(Self.valid(chartType, in: SettingsDefaults.historyChartTypeOptions, default: SettingsDefaults.historyChartType), forKey: Key.historyChartType) }
        if let yAxis { defaults.set(Self.valid(yAxis, in: SettingsDefaults.historyYAxisOptions, default: SettingsDefaults.historyYAxis), forKey: Key.historyYAxis) }
    }

    // MARK: Daily target

    func setDailyTarget(useEstimate: Bool, overrideMl: Int?) {
        defaults.set(useEstimate, forKey: Key.dailyTargetUseEstimate)
        if let overrideMl {
            defaults.set(HydrationTarget.clampOverride(overrideMl), forKey: Key.dailyTargetOverride)
        } else {
            defaults.removeObject(forKey: Key.dailyTargetOverride)
        }
    }

    /// Body values entered by hand; nil clears the value.
    func setManualBody(weightKg: Double?, sex: HydrationTarget.Sex?) {
        if let weightKg, weightKg.isFinite, weightKg > 0 {
            defaults.set(weightKg, forKey: Key.manualWeightKg)
        } else {
            defaults.removeObject(forKey: Key.manualWeightKg)
        }
        if let sex {
            defaults.set(sex.rawValue, forKey: Key.manualSex)
        } else {
            defaults.removeObject(forKey: Key.manualSex)
        }
    }

    // MARK: Drink reminders

    func setDrinkReminders(enabled: Bool, frequencyMinutes: Int, onlyWhenBehind: Bool) {
        defaults.set(enabled, forKey: Key.drinkRemindersEnabled)
        defaults.set(max(1, frequencyMinutes), forKey: Key.drinkReminderFrequency)
        defaults.set(onlyWhenBehind, forKey: Key.drinkReminderOnlyWhenBehind)
    }

    /// Ring hours as read from the cap (`SyncEngine.readReminder` / `applyReminder`).
    func setLastRingHours(startSec: Int, stopSec: Int) {
        defaults.set(startSec, forKey: Key.lastRingStart)
        defaults.set(stopSec, forKey: Key.lastRingStop)
    }

    func setPairedDevice(name: String, deviceIdHex: String) {
        if defaults.string(forKey: Key.pairedId) != deviceIdHex {
            defaults.removeObject(forKey: Key.lastRingStart)
            defaults.removeObject(forKey: Key.lastRingStop)
            defaults.set(false, forKey: Key.drinkRemindersEnabled)
        }
        defaults.set(name, forKey: Key.pairedName)
        defaults.set(deviceIdHex, forKey: Key.pairedId)
    }

    func forgetDevice() {
        for key in [Key.pairedName, Key.pairedId, Key.lastSync, Key.lastCapBottleSize, Key.lastBackgroundRun, Key.lastBackgroundOutcome, Key.consecutiveCapMisses, Key.lastRingStart, Key.lastRingStop] {
            defaults.removeObject(forKey: key)
        }
        defaults.set(false, forKey: Key.drinkRemindersEnabled)
    }

    /// New thresholds re-arm every alert (the fired set is cleared).
    func setBatteryThresholds(alertPercent: Int, criticalPercent: Int) {
        defaults.set(alertPercent, forKey: Key.batteryAlert)
        defaults.set(criticalPercent, forKey: Key.batteryCritical)
        defaults.removeObject(forKey: Key.firedBatteryThresholds)
    }

    func setHealthSyncEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.healthSync)
    }

    func setBottleProfile(_ profileId: String, customCoefficients: [Double]? = nil) {
        defaults.set(profileId, forKey: Key.bottleProfile)
        if let customCoefficients {
            defaults.set(customCoefficients.map { String($0) }.joined(separator: ","), forKey: Key.customCoefficients)
        }
    }

    func setLastSync(_ timestampMs: Int64) {
        defaults.set(timestampMs, forKey: Key.lastSync)
    }

    func setLastCapBottleSize(_ bottleSizeMl: Int) {
        defaults.set(bottleSizeMl, forKey: Key.lastCapBottleSize)
    }

    func setFiredBatteryThresholds(_ thresholds: Set<Int>) {
        defaults.set(thresholds.sorted().map(String.init).joined(separator: ","), forKey: Key.firedBatteryThresholds)
    }

    func setBackgroundSyncEnabled(_ enabled: Bool) {
        defaults.set(enabled, forKey: Key.backgroundSync)
    }

    /// Records the outcome of one background run (Debug screen + miss counter).
    func setLastBackgroundRun(timestampMs: Int64, outcome: String, consecutiveCapMisses: Int) {
        defaults.set(timestampMs, forKey: Key.lastBackgroundRun)
        defaults.set(outcome, forKey: Key.lastBackgroundOutcome)
        defaults.set(consecutiveCapMisses, forKey: Key.consecutiveCapMisses)
    }

    private func int64(_ defaults: UserDefaults, _ key: String) -> Int64? {
        if let number = defaults.object(forKey: key) as? NSNumber { return number.int64Value }
        return nil
    }

    private func parseCoefficients(_ raw: String?) -> [Double]? {
        guard let raw else { return nil }
        let values = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        return values.count == 5 ? values : nil
    }

    private func parseThresholds(_ raw: String?) -> Set<Int> {
        guard let raw else { return [] }
        return Set(raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    }
}
