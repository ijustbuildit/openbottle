package dev.hydrocap.app

import android.content.Context
import dev.hydrocap.app.ble.BleScanner
import dev.hydrocap.app.ble.CapConnection
import dev.hydrocap.app.ble.RequestIdCounter
import dev.hydrocap.app.data.HydroCapDatabase
import dev.hydrocap.app.data.SettingsRepository
import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.health.HealthConnectHydrationWriter
import dev.hydrocap.app.notify.BatteryNotifier
import dev.hydrocap.app.sync.BackgroundSync
import dev.hydrocap.app.sync.DrinkEventBuilder
import dev.hydrocap.app.sync.SyncEngine
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/** Manual dependency wiring; one instance per process, owned by [HydroCapApp]. */
class AppContainer(context: Context) {
    val appContext: Context = context.applicationContext

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    val debugLog = DebugLog(appContext.filesDir)
    val database: HydroCapDatabase = HydroCapDatabase.build(appContext)
    val settings = SettingsRepository(appContext)
    val scanner = BleScanner(appContext, debugLog)
    val requestIds = RequestIdCounter()
    val batteryNotifier = BatteryNotifier(appContext, settings, debugLog)
    val healthWriter = HealthConnectHydrationWriter(appContext, database, settings, debugLog)
    val healthBodyReader = dev.hydrocap.app.health.HealthConnectBodyReader(appContext)
    val healthBody = kotlinx.coroutines.flow.MutableStateFlow(dev.hydrocap.app.health.HealthBodyState())
    val capAdmission = dev.hydrocap.app.sync.CapJobAdmission()
    val connectionHandoff = dev.hydrocap.app.sync.ConnectionHandoff(appScope, capAdmission)
    val drinkReminders = dev.hydrocap.app.notify.DrinkReminderScheduler(appContext, settings, database, healthBodyReader, appScope, debugLog)
    val drinkEventBuilder = DrinkEventBuilder(database, debugLog)
    val syncEngine = SyncEngine(
        scanner = scanner,
        connectionFactory = { CapConnection(appContext, debugLog) },
        database = database,
        settings = settings,
        drinkEventBuilder = drinkEventBuilder,
        healthWriter = healthWriter,
        batteryNotifier = batteryNotifier,
        requestIds = requestIds,
        scope = appScope,
        debugLog = debugLog,
        onPaired = { BackgroundSync.reconcile(appContext, settings.current()) },
        admission = capAdmission,
        onSynced = { refreshHealthBody(); drinkReminders.replan().join() },
        onRingRead = { drinkReminders.replan().join() },
        onIdentityChanged = { drinkReminders.update(false) },
    )

    suspend fun refreshHealthBody() { healthBody.value = healthBodyReader.read() }
}
