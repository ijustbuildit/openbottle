package dev.hydrocap.app.health

import dev.hydrocap.app.data.DrinkEvent
import dev.hydrocap.app.data.HealthSyncDao
import dev.hydrocap.app.data.HealthSyncRecord
import dev.hydrocap.app.debug.DebugLog
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class HydrationRecordSyncTest {

    /** Records every call; can be told to fail or report unavailability. */
    private class FakeHealthConnectGateway : HealthConnectGateway {
        var unavailable: String? = null
        val insertBatches = ArrayList<List<HydrationWrite>>()
        val deleteBatches = ArrayList<List<String>>()
        var failInsertWith: Exception? = null
        var failDeleteWith: Exception? = null

        override suspend fun unavailableReason(): String? = unavailable

        override suspend fun insert(records: List<HydrationWrite>) {
            failInsertWith?.let { throw it }
            insertBatches += records
        }

        override suspend fun delete(clientRecordIds: List<String>) {
            failDeleteWith?.let { throw it }
            deleteBatches += clientRecordIds
        }

        val inserted: List<HydrationWrite> get() = insertBatches.flatten()
        val deleted: List<String> get() = deleteBatches.flatten()
    }

    /** In-memory `health_sync` table. */
    private class FakeHealthSyncDao : HealthSyncDao {
        val rows = LinkedHashMap<Long, HealthSyncRecord>()
        private val count = MutableStateFlow(0)

        override suspend fun all(): List<HealthSyncRecord> = rows.values.sortedBy { it.timestamp }

        override suspend fun upsertAll(records: List<HealthSyncRecord>) {
            records.forEach { rows[it.timestamp] = it }
            count.value = rows.size
        }

        override suspend fun deleteByTimestamps(timestamps: List<Long>) {
            timestamps.forEach { rows.remove(it) }
            count.value = rows.size
        }

        override fun observeCount(): Flow<Int> = count

        override suspend fun deleteAll() {
            rows.clear()
            count.value = 0
        }
    }

    private val gateway = FakeHealthConnectGateway()
    private val dao = FakeHealthSyncDao()
    private val log = DebugLog(filesDir = null)
    private val nowMs = 1_700_000_000_000L
    private val sync = HydrationRecordSync(gateway, dao, log, clock = { nowMs })
    // Synthetic patterned uint64 fixture, not a paired device's serial.
    private val deviceId = "FEDCBA9876543210"

    private fun event(ts: Long, ml: Double = 150.0, version: Long = 1) = DrinkEvent(ts, ml, ts, "body_680", version)

    @Test
    fun `first upsert inserts every valid event with the expected ids and versions`() = runTest {
        val events = listOf(event(1_000), event(2_000, ml = 80.5, version = 3))
        val result = sync.upsert(events, deviceId)

        assertEquals(HealthWriteResult(inserted = 2, updated = 0, skipped = 0), result)
        assertEquals(listOf("hydrocap:$deviceId:1000", "hydrocap:$deviceId:2000"), gateway.inserted.map { it.clientRecordId })
        assertEquals(listOf(1L, 3L), gateway.inserted.map { it.clientRecordVersion })
        assertEquals(80.5, gateway.inserted[1].volumeMl, 0.0)
        assertEquals(2_000L, gateway.inserted[1].startEpochSec)
        assertEquals(setOf(1_000L, 2_000L), dao.rows.keys)
        assertEquals(3L, dao.rows[2_000]!!.writtenVersion)
        assertEquals(nowMs, dao.rows[2_000]!!.writtenAtMs)
    }

    @Test
    fun `unchanged events are not written again and bumped versions count as updated`() = runTest {
        sync.upsert(listOf(event(1_000), event(2_000)), deviceId)
        gateway.insertBatches.clear()

        val result = sync.upsert(listOf(event(1_000), event(2_000, ml = 200.0, version = 2)), deviceId)

        assertEquals(HealthWriteResult(inserted = 0, updated = 1, skipped = 0), result)
        assertEquals(listOf("hydrocap:$deviceId:2000"), gateway.inserted.map { it.clientRecordId })
        assertEquals(2L, gateway.inserted.single().clientRecordVersion)
        assertEquals(2L, dao.rows[2_000]!!.writtenVersion)
        assertEquals(1L, dao.rows[1_000]!!.writtenVersion)
    }

    @Test
    fun `events with zero volume or a future start time are skipped`() = runTest {
        val nowSec = nowMs / 1000
        val events = listOf(event(1_000), event(2_000, ml = 0.0), event(3_000, ml = -5.0), event(nowSec + 60))
        val result = sync.upsert(events, deviceId)

        assertEquals(HealthWriteResult(inserted = 1, updated = 0, skipped = 3), result)
        assertEquals(listOf("hydrocap:$deviceId:1000"), gateway.inserted.map { it.clientRecordId })
        assertEquals(setOf(1_000L), dao.rows.keys)
    }

    @Test
    fun `records for vanished events are deleted by client id and dropped from the tracking table`() = runTest {
        sync.upsert(listOf(event(1_000), event(2_000), event(3_000)), deviceId)

        val result = sync.upsert(listOf(event(1_000)), deviceId)

        assertEquals(HealthWriteResult(inserted = 0, updated = 0, skipped = 0), result)
        assertEquals(setOf("hydrocap:$deviceId:2000", "hydrocap:$deviceId:3000"), gateway.deleted.toSet())
        assertEquals(setOf(1_000L), dao.rows.keys)
    }

    @Test
    fun `delete uses the client id that was written even if the paired device changed`() = runTest {
        sync.upsert(listOf(event(1_000)), "OLDDEVICE")
        sync.upsert(emptyList(), deviceId)
        assertEquals(listOf("hydrocap:OLDDEVICE:1000"), gateway.deleted)
    }

    @Test
    fun `inserts and deletes are chunked at 500`() = runTest {
        val events = (1..1_201L).map { event(it * 10) }
        val result = sync.upsert(events, deviceId)
        assertEquals(1_201, result.inserted)
        assertEquals(listOf(500, 500, 201), gateway.insertBatches.map { it.size })

        sync.upsert(emptyList(), deviceId)
        assertEquals(listOf(500, 500, 201), gateway.deleteBatches.map { it.size })
        assertTrue(dao.rows.isEmpty())
    }

    @Test
    fun `unavailable Health Connect skips everything without touching the gateway`() = runTest {
        gateway.unavailable = "Health Connect hydration write permission is not granted"
        val result = sync.upsert(listOf(event(1_000), event(2_000)), deviceId)

        assertEquals(0, result.inserted)
        assertEquals(2, result.skipped)
        assertEquals("Health Connect hydration write permission is not granted", result.error)
        assertTrue(gateway.insertBatches.isEmpty())
        assertTrue(dao.rows.isEmpty())
        // Logged once, not once per call.
        sync.upsert(listOf(event(1_000)), deviceId)
        assertEquals(1, log.entries.value.count { it.message.contains("not writing") })
    }

    @Test
    fun `gateway failures map to an error and leave partial progress consistent`() = runTest {
        gateway.failInsertWith = SecurityException("revoked")
        val result = sync.upsert(listOf(event(1_000)), deviceId)
        assertNotNull(result.error)
        assertTrue(result.error!!.contains("permission revoked"))
        assertEquals(0, result.inserted)
        assertTrue("nothing must be tracked when the insert failed", dao.rows.isEmpty())

        gateway.failInsertWith = IOException("binder died")
        assertTrue(sync.upsert(listOf(event(1_000)), deviceId).error!!.contains("I/O"))

        gateway.failInsertWith = IllegalStateException("not bound")
        assertTrue(sync.upsert(listOf(event(1_000)), deviceId).error!!.contains("state"))

        gateway.failInsertWith = null
        assertNull(sync.upsert(listOf(event(1_000)), deviceId).error)
    }

    @Test
    fun `a failing delete does not lose the tracking row so the delete is retried later`() = runTest {
        sync.upsert(listOf(event(1_000)), deviceId)
        gateway.failDeleteWith = IllegalStateException("busy")
        val failed = sync.upsert(emptyList(), deviceId)
        assertNotNull(failed.error)
        assertEquals(setOf(1_000L), dao.rows.keys)

        gateway.failDeleteWith = null
        assertNull(sync.upsert(emptyList(), deviceId).error)
        assertEquals(listOf("hydrocap:$deviceId:1000"), gateway.deleted)
        assertTrue(dao.rows.isEmpty())
    }

    @Test
    fun `unpaired writes use the unpaired placeholder id`() = runTest {
        sync.upsert(listOf(event(1_000)), null)
        assertEquals("hydrocap:unpaired:1000", gateway.inserted.single().clientRecordId)
    }

    @Test
    fun `plan is pure and reports counts`() {
        val written = listOf(
            HealthSyncRecord(1_000, "hydrocap:x:1000", 1, 0),
            HealthSyncRecord(2_000, "hydrocap:x:2000", 1, 0),
            HealthSyncRecord(9_000, "hydrocap:x:9000", 1, 0),
        )
        val plan = HydrationRecordSync.plan(
            events = listOf(event(1_000), event(2_000, version = 2), event(3_000), event(4_000, ml = 0.0)),
            written = written,
            pairedDeviceIdHex = "x",
            nowSec = 100_000,
        )
        assertEquals(listOf(3_000L), plan.inserts.map { it.timestamp })
        assertEquals(listOf(2_000L), plan.updates.map { it.timestamp })
        assertEquals(listOf(9_000L), plan.deletes.map { it.timestamp })
        assertEquals(1, plan.skipped)
        assertEquals(1, plan.unchanged)
    }
}
