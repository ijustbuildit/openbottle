package dev.hydrocap.app

import android.app.Application
import android.util.Log
import androidx.work.Configuration
import dev.hydrocap.app.sync.BackgroundSync
import kotlinx.coroutines.launch

/**
 * Process entry point. Owns the [AppContainer] and provides the WorkManager
 * configuration on demand (the default `androidx.startup` initializer is
 * removed in the manifest), so [dev.hydrocap.app.sync.CapSyncWorker] always
 * finds a fully built container behind `applicationContext`.
 */
class HydroCapApp : Application(), Configuration.Provider {
    lateinit var container: AppContainer
        private set

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setMinimumLoggingLevel(if (BuildConfig.DEBUG) Log.INFO else Log.WARN)
            .build()

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
        container.batteryNotifier.ensureChannel()
        container.drinkReminders.ensureChannel()
        container.debugLog.log("app", "OpenBottle ${BuildConfig.VERSION_NAME} (${BuildConfig.BUILD_TYPE}) started")
        container.appScope.launch {
            val settings = container.settings.current()
            container.refreshHealthBody()
            container.drinkReminders.replan().join()
            if (!container.connectionHandoff.isRunning) BackgroundSync.reconcile(this@HydroCapApp, container.settings.current())
            container.debugLog.log(
                "app",
                "background sync ${if (settings.hasPairedDevice && settings.backgroundSyncEnabled) "scheduled (every ${BackgroundSync.PERIOD_MINUTES} min)" else "not scheduled"} " +
                    "(paired=${settings.hasPairedDevice}, enabled=${settings.backgroundSyncEnabled})",
            )
        }
    }
}
