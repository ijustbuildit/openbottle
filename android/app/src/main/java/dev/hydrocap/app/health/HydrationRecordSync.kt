package dev.hydrocap.app.health

import android.os.RemoteException
import dev.hydrocap.app.data.DrinkEvent
import dev.hydrocap.app.data.HealthSyncDao
import dev.hydrocap.app.data.HealthSyncRecord
import dev.hydrocap.app.debug.DebugLog
import java.io.IOException
import kotlin.coroutines.cancellation.CancellationException

/**
 * Decides which drink events go to Health Connect and remembers what was
 * written (`health_sync`). No read-before-write: Health Connect deduplicates
 * on `clientRecordId` and lets the higher `clientRecordVersion` win, so the
 * plan is simply
 *
 * 1. delete records whose event vanished (algorithm/profile change) or became
 *    invalid — only ids HydroCap wrote itself, never other apps' data;
 * 2. insert every valid event whose (timestamp, version) is not yet recorded
 *    as written; an id with an older written version counts as *updated*.
 *
 * Inserts and deletes are chunked at [CHUNK_SIZE]; the tracking table is
 * updated per chunk so a failure mid-way never causes duplicate work later.
 * Every Health Connect failure is mapped to [HealthWriteResult.error] — the
 * sync must not crash because of the health sink.
 */
class HydrationRecordSync(
    private val gateway: HealthConnectGateway,
    private val store: HealthSyncDao,
    private val debugLog: DebugLog,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    @Volatile
    private var loggedUnavailableReason: String? = null

    suspend fun upsert(events: List<DrinkEvent>, pairedDeviceIdHex: String?): HealthWriteResult {
        val reason = gateway.unavailableReason()
        if (reason != null) {
            if (loggedUnavailableReason != reason) {
                loggedUnavailableReason = reason
                debugLog.log(TAG, "not writing ${events.size} event(s): $reason")
            }
            return HealthWriteResult(inserted = 0, updated = 0, skipped = events.size, error = reason)
        }
        loggedUnavailableReason = null

        val nowSec = clock() / 1000
        val plan = plan(events, store.all(), pairedDeviceIdHex ?: UNPAIRED_DEVICE_ID, nowSec)
        debugLog.log(
            TAG,
            "plan: ${plan.inserts.size} insert, ${plan.updates.size} update, ${plan.deletes.size} delete, " +
                "${plan.skipped} skipped, ${plan.unchanged} unchanged (of ${events.size} events)",
        )
        var inserted = 0
        var updated = 0
        try {
            plan.deletes.chunked(CHUNK_SIZE).forEach { chunk ->
                gateway.delete(chunk.map { it.clientRecordId })
                store.deleteByTimestamps(chunk.map { it.timestamp })
            }
            val updatedTimestamps = plan.updates.mapTo(HashSet()) { it.timestamp }
            (plan.inserts + plan.updates).chunked(CHUNK_SIZE).forEach { chunk ->
                gateway.insert(chunk.map { it.write })
                val writtenAt = clock()
                store.upsertAll(chunk.map { HealthSyncRecord(it.timestamp, it.write.clientRecordId, it.write.clientRecordVersion, writtenAt) })
                chunk.forEach { if (it.timestamp in updatedTimestamps) updated++ else inserted++ }
            }
        } catch (e: CancellationException) {
            throw e
        } catch (e: SecurityException) {
            return failed(inserted, updated, plan.skipped, "Health Connect permission revoked: ${e.message}", e)
        } catch (e: RemoteException) {
            return failed(inserted, updated, plan.skipped, "Health Connect unreachable: ${e.message}", e)
        } catch (e: IOException) {
            return failed(inserted, updated, plan.skipped, "Health Connect I/O error: ${e.message}", e)
        } catch (e: IllegalStateException) {
            return failed(inserted, updated, plan.skipped, "Health Connect state error: ${e.message}", e)
        } catch (e: Exception) {
            return failed(inserted, updated, plan.skipped, "Health Connect write failed: ${e.javaClass.simpleName}: ${e.message}", e)
        }
        debugLog.log(TAG, "written: inserted=$inserted updated=$updated deleted=${plan.deletes.size} skipped=${plan.skipped}")
        return HealthWriteResult(inserted, updated, plan.skipped)
    }

    private fun failed(inserted: Int, updated: Int, skipped: Int, message: String, e: Exception): HealthWriteResult {
        debugLog.error(TAG, "$message (after inserted=$inserted updated=$updated)", e)
        return HealthWriteResult(inserted, updated, skipped, error = message)
    }

    /** A pending write together with the event timestamp it is tracked under. */
    data class PlannedWrite(val timestamp: Long, val write: HydrationWrite)

    data class Plan(
        val inserts: List<PlannedWrite>,
        val updates: List<PlannedWrite>,
        val deletes: List<HealthSyncRecord>,
        val skipped: Int,
        val unchanged: Int,
    )

    companion object {
        const val TAG = "health"
        const val CHUNK_SIZE = 500
        const val UNPAIRED_DEVICE_ID = "unpaired"

        fun clientRecordId(pairedDeviceIdHex: String, timestampSec: Long): String = "hydrocap:$pairedDeviceIdHex:$timestampSec"

        /** Pure planning step; exposed for tests. */
        fun plan(events: List<DrinkEvent>, written: List<HealthSyncRecord>, pairedDeviceIdHex: String, nowSec: Long): Plan {
            val writtenByTimestamp = written.associateBy { it.timestamp }
            val inserts = ArrayList<PlannedWrite>()
            val updates = ArrayList<PlannedWrite>()
            var skipped = 0
            var unchanged = 0
            val valid = HashSet<Long>()
            for (event in events) {
                if (event.volumeMl <= 0.0 || event.timestamp > nowSec) {
                    skipped++
                    continue
                }
                valid += event.timestamp
                val previous = writtenByTimestamp[event.timestamp]
                if (previous != null && previous.writtenVersion >= event.version) {
                    unchanged++
                    continue
                }
                val write = HydrationWrite(
                    clientRecordId = clientRecordId(pairedDeviceIdHex, event.timestamp),
                    clientRecordVersion = event.version,
                    startEpochSec = event.timestamp,
                    volumeMl = event.volumeMl,
                )
                if (previous == null) inserts += PlannedWrite(event.timestamp, write) else updates += PlannedWrite(event.timestamp, write)
            }
            // Records we wrote for events that no longer exist (or are no longer valid) must go.
            val deletes = written.filter { it.timestamp !in valid }
            return Plan(inserts, updates, deletes, skipped, unchanged)
        }
    }
}
