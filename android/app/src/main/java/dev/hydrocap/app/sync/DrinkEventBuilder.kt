package dev.hydrocap.app.sync

import dev.hydrocap.app.data.DrinkEvent
import dev.hydrocap.app.data.HydroCapDatabase
import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.domain.BottleProfile
import dev.hydrocap.app.domain.TofAlgorithm
import dev.hydrocap.app.domain.TofReading

/**
 * Runs [TofAlgorithm] over the entire stored ToF log and reconciles the
 * `drink_event` table: new events are inserted, changed volumes bump the
 * version (so Health Connect can update), events that no longer exist (e.g.
 * after a profile change) are removed.
 */
class DrinkEventBuilder(private val database: HydroCapDatabase, private val debugLog: DebugLog) {

    suspend fun rebuild(profile: BottleProfile): List<DrinkEvent> {
        val readings = database.tofLogDao().all().map { TofReading(it.timestamp, it.distanceMm, it.kcps) }
        val computed = TofAlgorithm(profile).drinkEvents(readings)
        val existing = database.drinkEventDao().all().associateBy { it.timestamp }

        val upserts = computed.map { event ->
            val ts = event.reading.timestampSec
            val volume = event.countedMl.round1()
            val previous = existing[ts]
            when {
                previous == null -> DrinkEvent(ts, volume, ts, profile.id, version = 1)
                previous.volumeMl != volume || previous.profileId != profile.id ->
                    previous.copy(volumeMl = volume, profileId = profile.id, version = previous.version + 1)
                else -> previous
            }
        }
        val dao = database.drinkEventDao()
        dao.upsertAll(upserts)
        val keep = upserts.mapTo(HashSet()) { it.timestamp }
        val stale = existing.keys.filterNot { it in keep }
        // Chunked so the IN list stays below SQLite's bound-parameter limit on older Android versions.
        stale.chunked(500).forEach { dao.deleteByTimestamps(it) }
        debugLog.log(
            TAG,
            "algorithm(${profile.id}) over ${readings.size} readings → ${upserts.size} drink events " +
                "(${upserts.count { it.timestamp !in existing }} new, ${upserts.count { existing[it.timestamp]?.let { p -> p.version != it.version } == true }} changed, " +
                "${stale.size} removed)",
        )
        return upserts
    }

    private fun Double.round1(): Double = Math.round(this * 10.0) / 10.0

    private companion object {
        const val TAG = "drinks"
    }
}
