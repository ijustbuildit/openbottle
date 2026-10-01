package dev.hydrocap.app.health

import android.content.Context
import dev.hydrocap.app.data.DrinkEvent
import dev.hydrocap.app.data.HydroCapDatabase
import dev.hydrocap.app.data.SettingsRepository
import dev.hydrocap.app.debug.DebugLog

/**
 * Production [HealthConnectWriter]: `HydrationRecord`s via the Health Connect
 * client, tracked in the `health_sync` table. Ids are
 * `hydrocap:<pairedDeviceIdHex>:<timestamp>`, versions follow
 * [DrinkEvent.version]. See [HydrationRecordSync] for the planning rules.
 */
class HealthConnectHydrationWriter(
    context: Context,
    private val database: HydroCapDatabase,
    private val settings: SettingsRepository,
    debugLog: DebugLog,
) : HealthConnectWriter {

    private val sync = HydrationRecordSync(AndroidHealthConnectGateway(context.applicationContext), database.healthSyncDao(), debugLog)

    override suspend fun upsert(events: List<DrinkEvent>): HealthWriteResult =
        sync.upsert(events, settings.current().pairedDeviceIdHex)

    /** The "Sync to Health Connect now" path: every stored drink event, no BLE involved. */
    suspend fun upsertAllStored(): HealthWriteResult = upsert(database.drinkEventDao().all())
}
