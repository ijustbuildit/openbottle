import Foundation

/// Pure decision logic for battery alerts: each threshold fires once when the
/// level drops to or below it and re-arms only after the level has risen above
/// `threshold + rearmMargin`. Kept free of UIKit/UserNotifications types so it
/// is unit-testable; `BatteryNotifier` persists `firedThresholds` and shows the
/// notification.
nonisolated final class BatteryAlertPolicy {
    static let rearmMargin = 5

    /// Thresholds sorted descending so the most severe crossing is evaluated last.
    let thresholds: [Int]
    private(set) var firedThresholds: Set<Int>
    private let rearmMargin: Int

    init(thresholds: Set<Int>, firedThresholds: Set<Int> = [], rearmMargin: Int = BatteryAlertPolicy.rearmMargin) {
        self.thresholds = thresholds.filter { (0...100).contains($0) }.sorted(by: >)
        self.rearmMargin = rearmMargin
        self.firedThresholds = firedThresholds.intersection(self.thresholds)
    }

    /// Feeds a new battery level and returns the thresholds that were crossed
    /// for the first time since their last re-arm (empty when nothing to notify).
    func onLevel(_ percent: Int) -> [Int] {
        var fired = firedThresholds
        var toNotify: [Int] = []
        for threshold in thresholds {
            if percent <= threshold && !fired.contains(threshold) {
                fired.insert(threshold)
                toNotify.append(threshold)
            } else if percent > threshold + rearmMargin && fired.contains(threshold) {
                fired.remove(threshold)
            }
        }
        firedThresholds = fired
        return toNotify
    }
}
