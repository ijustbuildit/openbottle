package dev.hydrocap.app.data

import android.content.Context
import androidx.room.AutoMigration
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase

/**
 * Schema history (exported to `app/schemas/`, see `room.schemaLocation`):
 *
 * - v1: tof_log, activation_log, drink_event, battery_sample, device.
 * - v2: + health_sync (Health Connect write tracking). Auto-migrated; no
 *   destructive fallback, the ToF history is months of data.
 */
@Database(
    entities = [
        TofLogEntry::class,
        ActivationLogEntry::class,
        DrinkEvent::class,
        BatterySample::class,
        DeviceRecord::class,
        HealthSyncRecord::class,
    ],
    version = 2,
    exportSchema = true,
    autoMigrations = [AutoMigration(from = 1, to = 2)],
)
abstract class HydroCapDatabase : RoomDatabase() {
    abstract fun tofLogDao(): TofLogDao
    abstract fun activationLogDao(): ActivationLogDao
    abstract fun drinkEventDao(): DrinkEventDao
    abstract fun batterySampleDao(): BatterySampleDao
    abstract fun deviceDao(): DeviceDao
    abstract fun healthSyncDao(): HealthSyncDao

    companion object {
        fun build(context: Context): HydroCapDatabase =
            Room.databaseBuilder(context.applicationContext, HydroCapDatabase::class.java, "hydrocap.db")
                .build()
    }
}
