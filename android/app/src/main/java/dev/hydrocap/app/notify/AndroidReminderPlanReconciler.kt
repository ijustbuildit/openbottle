package dev.hydrocap.app.notify

import dev.hydrocap.app.data.AppSettings
import java.time.Instant
import java.time.ZoneId

/** Android's inexact OS queue may still own overdue slots; a future-only planner cannot replace it wholesale. */
object AndroidReminderPlanReconciler {
    data class Registered(val epoch: Long, val capId: String) { val key: String get() = "$epoch|$capId" }
    data class Delta(val keep: List<Registered>, val cancel: List<Registered>, val add: List<DrinkReminderPlanner.PlannedReminder>)
    fun signature(settings: AppSettings, window: DrinkReminderPlanner.Window): String =
        "${settings.pairedDeviceIdHex}|${settings.drinkReminderFrequencyMinutes}|${window.startSec}|${window.stopSec}|${settings.drinkReminderOnlyWhenBehind}"
    fun reconcile(registered: List<Registered>, previousSignature: String?, current: AppSettings,
        input: DrinkReminderPlanner.Input?, proposed: List<DrinkReminderPlanner.PlannedReminder>, now: Instant, zone: ZoneId): Delta {
        val window=current.ringWindow()
        if (!current.drinkRemindersEnabled || window==null || input==null || input.consumedTodayMl==null) return Delta(emptyList(),registered,emptyList())
        val cap=current.pairedDeviceIdHex ?: return Delta(emptyList(),registered,emptyList())
        val sameConfig=previousSignature==signature(current,window)
        val eligibleOld=if (sameConfig) registered.filter { old ->
            old.capId==cap && (old.epoch>now.epochSecond && proposed.any { it.fireAt.epochSecond==old.epoch } ||
                old.epoch<=now.epochSecond && DrinkReminderDeliveryPolicy.eligible(current,current,old.epoch,cap,input,now,zone))
        } else emptyList()
        val due=eligibleOld.filter { it.epoch<=now.epochSecond }.sortedBy { it.epoch }.take(DrinkReminderPlanner.maxPending)
        val newSlots=proposed.filter { item -> due.none { it.epoch==item.fireAt.epochSecond } }
            .sortedBy { it.fireAt }.take((DrinkReminderPlanner.maxPending-due.size).coerceAtLeast(0))
        val desiredKeys=due.map { it.key }.toSet()+newSlots.map { "${it.fireAt.epochSecond}|$cap" }
        val keep=eligibleOld.filter { it.key in desiredKeys }
        val keepKeys=keep.map { it.key }.toSet()
        return Delta(keep,registered.filter { it.key !in keepKeys },newSlots.filter { "${it.fireAt.epochSecond}|$cap" !in keepKeys })
    }
}
