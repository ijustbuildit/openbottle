package dev.hydrocap.app.sync

import android.content.Context
import android.content.pm.ServiceInfo
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import dev.hydrocap.app.HydroCapApp
import dev.hydrocap.app.R
import dev.hydrocap.app.notify.SyncNotifications
import dev.hydrocap.app.ui.AppPermissions
import kotlin.coroutines.cancellation.CancellationException

/**
 * Periodic background sync (see [BackgroundSync]). Thin by design: every
 * decision lives in [BackgroundRunPolicy]. Tries to run as a
 * `connectedDevice` foreground worker so the GATT link survives; when the
 * system refuses (app in background on API 31+) it continues without
 * foreground — WorkManager still grants the execution window.
 *
 * Battery alerts fire from [dev.hydrocap.app.notify.BatteryNotifier] inside
 * the normal sync, so a background run is all it takes for the 10 % / 5 %
 * notifications to appear without opening the app.
 */
class CapSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {

    override suspend fun doWork(): Result {
        val container = (applicationContext as HydroCapApp).container
        val log = container.debugLog
        if (container.connectionHandoff.isRunning) {
            log.log(TAG, "periodic run skipped: initial connection/import owns the cap")
            return Result.success()
        }
        val settings = container.settings.current()
        val skip = BackgroundRunPolicy.skipReason(
            hasPairedDevice = settings.hasPairedDevice,
            backgroundSyncEnabled = settings.backgroundSyncEnabled,
            hasBlePermissions = AppPermissions.hasEssential(applicationContext),
        )
        if (skip != null) {
            log.log(TAG, "periodic run skipped: $skip")
            return Result.success()
        }
        log.log(TAG, "periodic run start (attempt ${runAttemptCount + 1}, misses so far ${settings.consecutiveCapMisses})")
        try {
            setForeground(getForegroundInfo())
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // ForegroundServiceStartNotAllowedException (API 31+) is an IllegalStateException; keep going without foreground.
            log.log(TAG, "foreground not allowed (${e.javaClass.simpleName}: ${e.message}), continuing in the background")
        }
        val outcome = try {
            val summary = container.syncEngine.sync()
            BackgroundRunPolicy.Outcome.Synced(summary.newTofEntries, summary.drinkEvents, summary.batteryPercent)
        } catch (e: CancellationException) {
            log.log(TAG, "periodic run cancelled by WorkManager")
            throw e
        } catch (e: Exception) {
            BackgroundRunPolicy.classify(e)
        }
        val evaluation = BackgroundRunPolicy.evaluate(outcome, settings.consecutiveCapMisses)
        container.settings.setLastBackgroundRun(System.currentTimeMillis(), outcome.label(), evaluation.consecutiveMisses)
        if (evaluation.quiet) {
            log.log(TAG, "cap not found for ${evaluation.consecutiveMisses} consecutive runs; staying silent (no notification)")
        }
        log.log(TAG, "periodic run done: ${outcome.label()} → ${evaluation.verdict}")
        return if (evaluation.verdict == BackgroundRunPolicy.Verdict.RETRY) Result.retry() else Result.success()
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val notification = SyncNotifications.build(applicationContext, applicationContext.getString(R.string.notification_sync_text_background))
        return ForegroundInfo(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
    }

    companion object {
        const val TAG = "worker"
        const val NOTIFICATION_ID = 43
    }
}
