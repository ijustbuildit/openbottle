package dev.hydrocap.app.sync

import android.content.Context
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import dev.hydrocap.app.data.AppSettings
import java.util.concurrent.TimeUnit

/**
 * Schedules [CapSyncWorker] as unique periodic work: every 15 minutes (the
 * WorkManager minimum) with a 5 minute flex window, battery-not-low, no
 * network constraint (HydroCap has no INTERNET permission anyway).
 */
object BackgroundSync {
    const val UNIQUE_WORK_NAME = "cap-periodic-sync"
    const val PERIOD_MINUTES = 15L
    const val FLEX_MINUTES = 5L

    fun schedule(context: Context) {
        val request = PeriodicWorkRequestBuilder<CapSyncWorker>(PERIOD_MINUTES, TimeUnit.MINUTES, FLEX_MINUTES, TimeUnit.MINUTES)
            .setConstraints(Constraints.Builder().setRequiresBatteryNotLow(true).build())
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(UNIQUE_WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
    }

    /** Schedules when a cap is paired and the setting is on, cancels otherwise. */
    fun reconcile(context: Context, settings: AppSettings) {
        if (settings.hasPairedDevice && settings.backgroundSyncEnabled) schedule(context) else cancel(context)
    }
}
