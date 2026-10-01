import Foundation
import UserNotifications

/// Battery notifications on the "battery" category. Thresholds (default
/// 10 % / 5 %) come from settings; the fired/re-armed state is persisted so a
/// threshold fires exactly once per crossing across app restarts.
@MainActor
final class BatteryNotifier {
    nonisolated static let tag = "battery"
    nonisolated static let categoryIdentifier = "battery"
    nonisolated static let notificationIdBase = 1_000

    private let settings: SettingsStore
    private let debugLog: DebugLog
    private let center: UNUserNotificationCenter

    init(settings: SettingsStore, debugLog: DebugLog, center: UNUserNotificationCenter = .current()) {
        self.settings = settings
        self.debugLog = debugLog
        self.center = center
        registerCategory()
    }

    func registerCategory() {
        let category = UNNotificationCategory(
            identifier: BatteryNotifier.categoryIdentifier,
            actions: [],
            intentIdentifiers: [],
            options: [],
        )
        // `setNotificationCategories` replaces the whole set: register the
        // drink category alongside so neither overwrites the other.
        center.setNotificationCategories([category, DrinkReminderScheduler.category])
    }

    /// Onboarding asks for the permission once; the Debug screen reports it.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            debugLog.error(BatteryNotifier.tag, "notification permission request failed", error: error)
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    /// Raw status for the onboarding "optional things" step.
    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// Evaluates `percent` against the configured thresholds and notifies on new
    /// crossings.
    func onBatteryLevel(_ percent: Int) async {
        let current = settings.current
        let policy = BatteryAlertPolicy(
            thresholds: [current.batteryAlertPercent, current.batteryCriticalPercent],
            firedThresholds: current.firedBatteryThresholds,
        )
        let crossed = policy.onLevel(percent)
        if policy.firedThresholds != current.firedBatteryThresholds {
            settings.setFiredBatteryThresholds(policy.firedThresholds)
        }
        guard let lowest = crossed.min() else { return }
        debugLog.log(BatteryNotifier.tag, "battery \(percent) % crossed threshold(s) \(crossed) → notify")
        await show(percent: percent, threshold: lowest)
    }

    private func show(percent: Int, threshold: Int) async {
        guard await isAuthorized() else {
            debugLog.log(BatteryNotifier.tag, "notification permission missing, battery alert suppressed")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = "Battery at \(percent) %"
        if threshold <= SettingsDefaults.batteryCritical {
            content.body = "Your LARQ cap is critically low. Charge it before it locks out."
        } else {
            content.body = "Your LARQ cap is low. Charge it soon — HydroCap keeps syncing until \(threshold) %."
        }
        content.categoryIdentifier = BatteryNotifier.categoryIdentifier
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(BatteryNotifier.categoryIdentifier)-\(threshold)",
            content: content,
            trigger: nil,
        )
        do {
            try await center.add(request)
        } catch {
            debugLog.error(BatteryNotifier.tag, "battery notification failed", error: error)
        }
    }
}
