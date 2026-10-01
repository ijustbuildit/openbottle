package dev.hydrocap.app.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.HydrationRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Volume
import java.time.Instant
import java.time.ZoneId

/** One hydration record as HydroCap wants it in Health Connect; pure data so the sync logic is testable. */
data class HydrationWrite(
    val clientRecordId: String,
    val clientRecordVersion: Long,
    val startEpochSec: Long,
    val volumeMl: Double,
) {
    companion object {
        /** Records are instantaneous drinks; Health Connect needs start < end, so they last one second. */
        const val DURATION_SEC = 1L
    }
}

/**
 * The thin Android-facing seam around [HealthConnectClient]. The planner
 * ([HydrationRecordSync]) decides *what* to write; this decides *how*.
 */
interface HealthConnectGateway {
    /** Null when records can be written; otherwise a human-readable reason (unavailable / permission missing). */
    suspend fun unavailableReason(): String?

    /**
     * Inserts (or, for an existing `clientRecordId` with a higher
     * `clientRecordVersion`, replaces) the given records.
     */
    suspend fun insert(records: List<HydrationWrite>)

    /** Deletes only records HydroCap wrote, addressed by their `clientRecordId`s. */
    suspend fun delete(clientRecordIds: List<String>)
}

/** Maps a [HydrationWrite] to the library record; zone offsets follow the phone's zone at that instant. */
fun HydrationWrite.toHydrationRecord(device: Device, zone: ZoneId = ZoneId.systemDefault()): HydrationRecord {
    val start = Instant.ofEpochSecond(startEpochSec)
    val end = start.plusSeconds(HydrationWrite.DURATION_SEC)
    return HydrationRecord(
        startTime = start,
        startZoneOffset = zone.rules.getOffset(start),
        endTime = end,
        endZoneOffset = zone.rules.getOffset(end),
        volume = Volume.milliliters(volumeMl),
        metadata = Metadata.autoRecorded(
            device = device,
            clientRecordId = clientRecordId,
            clientRecordVersion = clientRecordVersion,
        ),
    )
}

class AndroidHealthConnectGateway(private val context: Context) : HealthConnectGateway {

    private val device = Device(type = Device.TYPE_UNKNOWN, manufacturer = DEVICE_MANUFACTURER, model = DEVICE_MODEL)

    private val client: HealthConnectClient get() = HealthConnectClient.getOrCreate(context)

    override suspend fun unavailableReason(): String? = when (HealthConnectSupport.availability(context)) {
        HealthConnectSupport.Availability.UPDATE_REQUIRED -> "Health Connect needs an update before hydration can be written"
        HealthConnectSupport.Availability.UNAVAILABLE -> "Health Connect is not available on this device"
        HealthConnectSupport.Availability.AVAILABLE ->
            if (HealthConnectSupport.hasHydrationWritePermission(context)) null
            else "Health Connect hydration write permission is not granted"
    }

    override suspend fun insert(records: List<HydrationWrite>) {
        if (records.isEmpty()) return
        client.insertRecords(records.map { it.toHydrationRecord(device) })
    }

    override suspend fun delete(clientRecordIds: List<String>) {
        if (clientRecordIds.isEmpty()) return
        client.deleteRecords(HydrationRecord::class, recordIdsList = emptyList(), clientRecordIdsList = clientRecordIds)
    }

    companion object {
        const val DEVICE_MANUFACTURER = "LARQ"
        const val DEVICE_MODEL = "CAP"
    }
}
