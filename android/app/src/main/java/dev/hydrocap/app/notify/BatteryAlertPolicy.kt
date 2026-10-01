package dev.hydrocap.app.notify

/**
 * Pure decision logic for battery alerts: each threshold fires once when the
 * level drops to or below it and re-arms only after the level has risen above
 * `threshold + rearmMargin`. Kept free of Android types so it is unit-testable;
 * [BatteryNotifier] persists [firedThresholds] and shows the notification.
 */
class BatteryAlertPolicy(
    thresholds: Set<Int>,
    firedThresholds: Set<Int> = emptySet(),
    private val rearmMargin: Int = REARM_MARGIN,
) {
    /** Thresholds sorted descending so the most severe crossing is evaluated last. */
    val thresholds: List<Int> = thresholds.filter { it in 0..100 }.sortedDescending()

    var firedThresholds: Set<Int> = firedThresholds.intersect(thresholds)
        private set

    /**
     * Feeds a new battery level and returns the thresholds that were crossed
     * for the first time since their last re-arm (empty when nothing to notify).
     */
    fun onLevel(percent: Int): List<Int> {
        val fired = firedThresholds.toMutableSet()
        val toNotify = ArrayList<Int>()
        for (threshold in thresholds) {
            when {
                percent <= threshold && threshold !in fired -> {
                    fired += threshold
                    toNotify += threshold
                }
                percent > threshold + rearmMargin && threshold in fired -> fired -= threshold
            }
        }
        firedThresholds = fired
        return toNotify
    }

    companion object {
        const val REARM_MARGIN = 5
    }
}
