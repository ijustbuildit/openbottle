package dev.hydrocap.app.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface TofLogDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(entries: List<TofLogEntry>): List<Long>

    @Query("SELECT MAX(timestamp) FROM tof_log")
    suspend fun maxTimestamp(): Long?

    @Query("SELECT * FROM tof_log ORDER BY timestamp ASC")
    suspend fun all(): List<TofLogEntry>

    @Query("SELECT * FROM tof_log ORDER BY timestamp DESC LIMIT 1")
    fun observeLatest(): Flow<TofLogEntry?>

    @Query("SELECT COUNT(*) FROM tof_log")
    fun observeCount(): Flow<Int>

    @Query("DELETE FROM tof_log")
    suspend fun deleteAll()
}

@Dao
interface ActivationLogDao {
    @Insert(onConflict = OnConflictStrategy.IGNORE)
    suspend fun insertAll(entries: List<ActivationLogEntry>): List<Long>

    @Query("SELECT MAX(timestamp) FROM activation_log")
    suspend fun maxTimestamp(): Long?

    @Query("SELECT COUNT(*) FROM activation_log")
    fun observeCount(): Flow<Int>

    @Query("DELETE FROM activation_log")
    suspend fun deleteAll()
}

@Dao
interface DrinkEventDao {
    @Upsert
    suspend fun upsertAll(events: List<DrinkEvent>)

    @Query("SELECT * FROM drink_event ORDER BY timestamp ASC")
    suspend fun all(): List<DrinkEvent>

    @Query("SELECT * FROM drink_event ORDER BY timestamp ASC")
    fun observeAll(): Flow<List<DrinkEvent>>

    @Query("SELECT * FROM drink_event WHERE timestamp >= :fromSec AND timestamp < :toSec ORDER BY timestamp DESC")
    fun observeBetween(fromSec: Long, toSec: Long): Flow<List<DrinkEvent>>

    @Query("DELETE FROM drink_event WHERE timestamp IN (:timestamps)")
    suspend fun deleteByTimestamps(timestamps: List<Long>)

    @Query("DELETE FROM drink_event")
    suspend fun deleteAll()
}

@Dao
interface HealthSyncDao {
    @Query("SELECT * FROM health_sync ORDER BY timestamp ASC")
    suspend fun all(): List<HealthSyncRecord>

    @Upsert
    suspend fun upsertAll(records: List<HealthSyncRecord>)

    @Query("DELETE FROM health_sync WHERE timestamp IN (:timestamps)")
    suspend fun deleteByTimestamps(timestamps: List<Long>)

    @Query("SELECT COUNT(*) FROM health_sync")
    fun observeCount(): Flow<Int>

    @Query("DELETE FROM health_sync")
    suspend fun deleteAll()
}

@Dao
interface BatterySampleDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insert(sample: BatterySample)

    @Query("SELECT * FROM battery_sample ORDER BY timestamp DESC LIMIT 1")
    fun observeLatest(): Flow<BatterySample?>

    @Query("DELETE FROM battery_sample")
    suspend fun deleteAll()
}

@Dao
interface DeviceDao {
    @Upsert
    suspend fun upsert(device: DeviceRecord)

    @Query("SELECT * FROM device WHERE deviceIdHex = :deviceIdHex")
    suspend fun byId(deviceIdHex: String): DeviceRecord?

    @Query("SELECT * FROM device WHERE deviceIdHex = :deviceIdHex")
    fun observeById(deviceIdHex: String): Flow<DeviceRecord?>

    @Query("DELETE FROM device")
    suspend fun deleteAll()
}
