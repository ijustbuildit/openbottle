package dev.hydrocap.app.notify

import dev.hydrocap.app.data.AppSettings
import java.time.Instant
import java.time.ZoneId

/** Used immediately before the real notification; stale pre-await clocks/intake cannot authorize delivery. */
object DrinkReminderDeliveryPolicy {
    fun eligible(snapshot: AppSettings, current: AppSettings, epoch: Long, capId: String,
        input: DrinkReminderPlanner.Input?, now: Instant, zone: ZoneId): Boolean {
        if (!current.drinkRemindersEnabled || current.pairedDeviceIdHex != capId || input == null || now.epochSecond < epoch) return false
        val window=current.ringWindow() ?: return false
        if (window!=input.window || current.drinkReminderFrequencyMinutes!=input.frequencyMinutes ||
            current.drinkReminderOnlyWhenBehind!=snapshot.drinkReminderOnlyWhenBehind ||
            current.dailyTargetUseEstimate!=snapshot.dailyTargetUseEstimate || current.dailyTargetOverrideMl!=snapshot.dailyTargetOverrideMl ||
            current.manualWeightKg!=snapshot.manualWeightKg || current.manualSex!=snapshot.manualSex) return false
        val local=now.atZone(zone)
        val due=Instant.ofEpochSecond(epoch)
        if (local.toLocalDate()!=due.atZone(zone).toLocalDate() || local.toLocalDate()!=input.now.atZone(zone).toLocalDate()) return false
        val second=local.toLocalTime().toSecondOfDay()
        if (!window.contains(second) || input.consumedTodayMl==null || !input.consumedTodayMl.isFinite()) return false
        if (current.drinkReminderOnlyWhenBehind && !DrinkReminderPlanner.isBehind(input.targetMl,input.consumedTodayMl,window,second)) return false
        // Reuse exactly the planner's DST wall-clock resolution, not raw nominal slot seconds.
        return DrinkReminderPlanner.plan(input.copy(now=due.minusSeconds(1),onlyWhenBehind=false)).any { it.fireAt==due }
    }
}
