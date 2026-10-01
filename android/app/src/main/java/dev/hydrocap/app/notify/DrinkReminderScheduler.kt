package dev.hydrocap.app.notify

import android.Manifest
import android.annotation.SuppressLint
import android.app.*
import android.content.*
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.edit
import androidx.core.net.toUri
import androidx.work.*
import dev.hydrocap.app.HydroCapApp
import dev.hydrocap.app.MainActivity
import dev.hydrocap.app.R
import dev.hydrocap.app.data.*
import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.domain.HydrationTarget
import dev.hydrocap.app.health.HealthConnectBodyReader
import dev.hydrocap.app.ui.AppPermissions
import kotlinx.coroutines.*
import java.time.Instant
import java.time.Clock
import java.time.ZoneId
import java.util.concurrent.TimeUnit

fun AppSettings.ringWindow(): DrinkReminderPlanner.Window? {
    if (pairedDeviceIdHex == null || ringDeviceId != pairedDeviceIdHex) return null
    return DrinkReminderPlanner.Window(lastRingStartSec ?: return null, lastRingStopSec ?: return null).takeIf { it.isUsable }
}
fun AppSettings.resolveTarget(weightKg: Double?): HydrationTarget.TargetResult = HydrationTarget.resolve(
    useEstimate = dailyTargetUseEstimate, overrideMl = dailyTargetOverrideMl,
    healthWeightKg = weightKg, manualWeightKg = manualWeightKg,
    manualSex = manualSex?.let { value -> HydrationTarget.Sex.entries.firstOrNull { it.name.equals(value, true) } },
)

/** Real local, inexact alarms. No INTERNET or exact-alarm special access. */
class DrinkReminderScheduler(
    private val context: Context, private val settings: SettingsRepository,
    private val database: HydroCapDatabase, private val bodyReader: HealthConnectBodyReader,
    private val scope: CoroutineScope, private val log: DebugLog,
    private val clock: Clock = Clock.systemUTC(),
) {
    private val queue = DrinkReminderQueue(scope)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val prefs = context.getSharedPreferences("drink_alarm_ids", Context.MODE_PRIVATE)
    fun notificationsAllowed(): Boolean = NotificationManagerCompat.from(context).areNotificationsEnabled() &&
        (Build.VERSION.SDK_INT < 33 || AppPermissions.isGranted(context, Manifest.permission.POST_NOTIFICATIONS))

    fun ensureChannel() { context.getSystemService(NotificationManager::class.java).createNotificationChannel(
        NotificationChannel(CHANNEL, "Drink reminders", NotificationManager.IMPORTANCE_DEFAULT).apply { description = "Optional local reminders during your cap's ring hours" }) }

    fun replan(): Job = queue.submit { replacePlan(it, Instant.now(clock)) }

    /** Persist and cancel through the same owner so disabling fences every old read/add. */
    fun update(enabled: Boolean, frequency: Int? = null, behind: Boolean? = null): Job = queue.submitMutation { lease ->
        val before = settings.current()
        settings.setDrinkReminders(enabled, frequency, behind)
        val after = settings.current()
        if (!enabled || before.pairedDeviceIdHex != after.pairedDeviceIdHex || before.ringWindow() != after.ringWindow() ||
            before.drinkReminderFrequencyMinutes != after.drinkReminderFrequencyMinutes || before.drinkReminderOnlyWhenBehind != after.drinkReminderOnlyWhenBehind) cancelAll()
        if (!enabled) NotificationManagerCompat.from(context).cancel(TAG, NOTIFICATION_ID)
        replacePlan(lease, Instant.now(clock))
    }

    private fun pending(epoch: Long, capId: String, flags: Int = PendingIntent.FLAG_UPDATE_CURRENT): PendingIntent? =
        PendingIntent.getBroadcast(context, 0, Intent(context, DrinkReminderReceiver::class.java)
            .setData("hydrocap://drink/$epoch/${Uri.encode(capId)}".toUri())
            .putExtra("epoch", epoch).putExtra("cap", capId), flags or PendingIntent.FLAG_IMMUTABLE)

    private fun cancelAll() {
        prefs.getStringSet("ids", emptySet()).orEmpty().forEach { key ->
            val parts = key.split('|', limit = 2)
            val epoch = parts.firstOrNull()?.toLongOrNull()
            if (epoch != null && parts.size == 2) pending(epoch, parts[1], PendingIntent.FLAG_NO_CREATE)?.let { alarms.cancel(it); it.cancel() }
        }
        prefs.edit { remove("ids"); remove("signature") }
    }

    private fun registered(): List<AndroidReminderPlanReconciler.Registered> = prefs.getStringSet("ids", emptySet()).orEmpty().mapNotNull { key ->
        val parts = key.split('|', limit = 2)
        val epoch = parts.firstOrNull()?.toLongOrNull()
        if (epoch == null || parts.size != 2) null else AndroidReminderPlanReconciler.Registered(epoch, parts[1])
    }

    private suspend fun replacePlan(lease: DrinkReminderQueue.Lease, now: Instant) {
        if (!lease.isCurrent) return
        val current = settings.current()
        if (!lease.isCurrent) return
        if (!current.drinkRemindersEnabled || !current.hasPairedDevice || !notificationsAllowed()) {
            cancelAll()
            WorkManager.getInstance(context).cancelUniqueWork(MAINTENANCE)
            return
        }
        val window = current.ringWindow() ?: run { cancelAll(); return }
        val fetched = input(current, window, now) ?: run { cancelAll(); return }
        if (!lease.isCurrent) return
        val freshNow = Instant.now(clock)
        val zone = ZoneId.systemDefault()
        if (fetched.zoneId != zone || fetched.now.atZone(zone).toLocalDate() != freshNow.atZone(zone).toLocalDate()) {
            replan() // Schedule a new day snapshot, without awaiting the queue from inside itself.
            return
        }
        val input = fetched.copy(now = freshNow)
        val plan = DrinkReminderPlanner.plan(input)
        val old = registered()
        val delta = AndroidReminderPlanReconciler.reconcile(old, prefs.getString("signature", null), current, input, plan, freshNow, zone)
        val ids = old.map { it.key }.toMutableSet()
        val signature = AndroidReminderPlanReconciler.signature(current, window)
        delta.cancel.forEach { slot ->
            if (!lease.isCurrent) return
            pending(slot.epoch, slot.capId, PendingIntent.FLAG_NO_CREATE)?.let { alarms.cancel(it); it.cancel() }
            ids.remove(slot.key)
            prefs.edit { putStringSet("ids", ids.toSet()); putString("signature", signature) }
        }
        delta.add.forEach { item ->
            if (!lease.isCurrent) return
            val epoch = item.fireAt.epochSecond
            val cap = current.pairedDeviceIdHex ?: return
            val pi = pending(epoch, cap) ?: return
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, item.fireAt.toEpochMilli(), pi)
            ids += "$epoch|$cap"
            // Persist after each actual add; a later queued disable can cancel an in-flight prefix.
            prefs.edit { putStringSet("ids", ids.toSet()); putString("signature", signature) }
        }
        if (!lease.isCurrent) return
        prefs.edit { putStringSet("ids", ids.toSet()); putString("signature", signature) }
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(MAINTENANCE, ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<DrinkReminderMaintenanceWorker>(15, TimeUnit.MINUTES).build())
        log.log("reminders", "scheduled ${ids.size} inexact local slots from verified cap hours")
    }

    private suspend fun input(current: AppSettings, window: DrinkReminderPlanner.Window, now: Instant): DrinkReminderPlanner.Input? {
        val zone = ZoneId.systemDefault()
        val day = DrinkReminderPlanner.dayRange(now, zone)
        val events = try { database.drinkEventDao().all().filter { it.timestamp >= day.start.epochSecond && it.timestamp < day.end.epochSecond && it.timestamp <= now.epochSecond } }
        catch (e: Exception) { log.error("reminders", "intake unavailable; not treating as zero", e); return null }
        val weight = bodyReader.read(now).weightKg
        return DrinkReminderPlanner.Input(enabled = true, now = now, window = window,
            frequencyMinutes = current.drinkReminderFrequencyMinutes, targetMl = current.resolveTarget(weight).ml.toDouble(),
            consumedTodayMl = events.sumOf { it.volumeMl }, drinkTimestampsToday = events.map { it.timestamp },
            onlyWhenBehind = current.drinkReminderOnlyWhenBehind, zoneId = zone)
    }

    @SuppressLint("MissingPermission")
    fun deliver(epoch: Long, capId: String): Job = queue.submitDelivery { lease ->
        val key = "$epoch|$capId"
        val delivered = prefs.getStringSet("delivered", emptySet()).orEmpty().toMutableSet()
        if (key in delivered || registered().none { it.key == key }) return@submitDelivery
        delivered.add(key)
        val recent = delivered.sortedByDescending { it.substringBefore('|').toLongOrNull() ?: 0L }.take(64).toSet()
        prefs.edit { putStringSet("ids", prefs.getStringSet("ids", emptySet()).orEmpty() - key); putStringSet("delivered", recent) }
        val now = Instant.now(clock)
        val current = settings.current()
        val window = current.ringWindow()
        if (lease.isAuthorized && current.drinkRemindersEnabled && current.pairedDeviceIdHex == capId && notificationsAllowed() && window != null) {
            val input = input(current, window, now)
            val freshSettings = settings.current()
            val freshNow = Instant.now(clock)
            if (lease.isAuthorized && input != null && notificationsAllowed() && DrinkReminderDeliveryPolicy.eligible(current, freshSettings, epoch, capId, input, freshNow, ZoneId.systemDefault())) {
                ensureChannel()
                val tap = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
                val syncAt = current.lastSyncMs?.let(Instant::ofEpochMilli)
                val body = if (syncAt == null) "No synced intake yet. Your editable drink goal is %.2f L.".format(input.targetMl / 1000)
                    else DrinkReminderPlanner.body(input.copy(now = syncAt), tomorrow = false)
                NotificationManagerCompat.from(context).notify(TAG, NOTIFICATION_ID,
                    NotificationCompat.Builder(context, CHANNEL).setSmallIcon(R.drawable.ic_notification_drop)
                        .setContentTitle("Time to drink").setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
                        .setContentIntent(tap).setAutoCancel(true).build())
            }
        }
        replacePlan(lease, Instant.now(clock))
    }
    companion object { const val CHANNEL = "drink-reminders"; const val TAG = "hydrocap-drink"; const val NOTIFICATION_ID = 120; const val MAINTENANCE = "drink-reminder-maintenance" }
}

class DrinkReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val epoch = intent.getLongExtra("epoch", 0)
        val cap = intent.getStringExtra("cap") ?: return
        if (epoch <= 0 || cap.isEmpty()) return
        // Enqueue immediately; never spend the receiver's ten-second budget waiting behind a Health read.
        val request = OneTimeWorkRequestBuilder<DrinkReminderDeliveryWorker>()
            .setInputData(workDataOf("epoch" to epoch, "cap" to cap))
            .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.NOT_REQUIRED).build()).build()
        WorkManager.getInstance(context).enqueueUniqueWork("drink-delivery-$epoch", ExistingWorkPolicy.KEEP, request)
    }
}
class ReminderClockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in setOf(Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED, Intent.ACTION_DATE_CHANGED)) return
        WorkManager.getInstance(context).enqueueUniqueWork("drink-clock-replan", ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<DrinkReminderMaintenanceWorker>()
                .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.NOT_REQUIRED).build()).build())
    }
}
class DrinkReminderDeliveryWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val epoch = inputData.getLong("epoch", 0)
        val cap = inputData.getString("cap") ?: return Result.success()
        (applicationContext as HydroCapApp).container.drinkReminders.deliver(epoch, cap).join()
        return Result.success()
    }
}
class DrinkReminderMaintenanceWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        (applicationContext as HydroCapApp).container.drinkReminders.replan().join()
        return Result.success()
    }
}
