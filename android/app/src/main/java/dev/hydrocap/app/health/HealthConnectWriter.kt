package dev.hydrocap.app.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HydrationRecord
import dev.hydrocap.app.data.DrinkEvent

/** Outcome of one Health Connect upsert. */
data class HealthWriteResult(val inserted: Int, val updated: Int, val skipped: Int, val error: String? = null)

/**
 * Sink for drink events. [HealthConnectHydrationWriter] writes one
 * `HydrationRecord` per drink event (deduplicated by `clientRecordId`,
 * versioned by `clientRecordVersion`, tracked in the `health_sync` table);
 * the interface stays the seam for the sync engine.
 */
interface HealthConnectWriter {
    suspend fun upsert(events: List<DrinkEvent>): HealthWriteResult
}

/** Availability + permission helpers shared by onboarding, Settings and the writer. */
object HealthConnectSupport {
    val HYDRATION_WRITE_PERMISSION: String = HealthPermission.getWritePermission(HydrationRecord::class)
    val REQUIRED_PERMISSIONS: Set<String> = setOf(HYDRATION_WRITE_PERMISSION)

    enum class Availability { AVAILABLE, UPDATE_REQUIRED, UNAVAILABLE }

    fun availability(context: Context): Availability = when (HealthConnectClient.getSdkStatus(context)) {
        HealthConnectClient.SDK_AVAILABLE -> Availability.AVAILABLE
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> Availability.UPDATE_REQUIRED
        else -> Availability.UNAVAILABLE
    }

    suspend fun hasHydrationWritePermission(context: Context): Boolean {
        if (availability(context) != Availability.AVAILABLE) return false
        return try {
            val granted = HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions()
            HYDRATION_WRITE_PERMISSION in granted
        } catch (_: Exception) {
            false
        }
    }
}
