package dev.hydrocap.app.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout
import java.time.Duration
import java.time.Instant

/** Weight is optional and independent of hydration-write access. HC has no fitness SexRecord. */
data class HealthBodyState(
    val availability: HealthConnectSupport.Availability = HealthConnectSupport.Availability.UNAVAILABLE,
    val weightPermission: Boolean = false,
    val hydrationPermission: Boolean = false,
    val weightKg: Double? = null,
    val error: String? = null,
) {
    val weightStatus: String get() = when {
        error != null -> "Could not read weight: $error"
        availability != HealthConnectSupport.Availability.AVAILABLE -> "Not available"
        !weightPermission -> "Read permission missing"
        weightKg == null -> "No weight in the last 30 days"
        else -> "%.1f kg".format(weightKg)
    }
}
data class WeightValue(val time: Instant, val kg: Double)
data class WeightPage(val records: List<WeightValue>, val nextToken: String?)
interface HealthBodyGateway {
    fun availability(): HealthConnectSupport.Availability
    suspend fun permissions(): Set<String>
    suspend fun weights(from: Instant, to: Instant, token: String?): WeightPage
}
class AndroidHealthBodyGateway(private val context: Context) : HealthBodyGateway {
    override fun availability() = HealthConnectSupport.availability(context)
    override suspend fun permissions() = HealthConnectClient.getOrCreate(context).permissionController.getGrantedPermissions()
    override suspend fun weights(from: Instant,to: Instant,token: String?): WeightPage {
        val result = HealthConnectClient.getOrCreate(context).readRecords(ReadRecordsRequest(
            recordType=WeightRecord::class,timeRangeFilter=TimeRangeFilter.between(from,to),ascendingOrder=false,pageSize=100,pageToken=token))
        return WeightPage(result.records.map { WeightValue(it.time,it.weight.inKilograms) },result.pageToken)
    }
}

/** Bounded optional read: stalled/invalid providers never hold onboarding indefinitely. */
class HealthConnectBodyReader(private val gateway: HealthBodyGateway, private val timeoutMs: Long = 8_000) {
    constructor(context: Context) : this(AndroidHealthBodyGateway(context))
    suspend fun read(now: Instant = Instant.now()): HealthBodyState {
        val availability = gateway.availability()
        if (availability != HealthConnectSupport.Availability.AVAILABLE) return HealthBodyState(availability)
        var state = HealthBodyState(availability)
        return try {
            withTimeout(timeoutMs) {
                val granted = gateway.permissions()
                state=state.copy(weightPermission=READ_WEIGHT in granted,hydrationPermission=HealthConnectSupport.HYDRATION_WRITE_PERMISSION in granted)
                if (!state.weightPermission) return@withTimeout state
                var token: String? = null
                val seen=mutableSetOf<String>()
                do {
                    // Normal HC permission has history restrictions; only query a safe recent window.
                    val page=gateway.weights(now.minus(Duration.ofDays(30)),now.plusNanos(1),token)
                    val weight=page.records.filter { it.time<=now && it.kg.isFinite() && it.kg>0 }.maxByOrNull { it.time }
                    if (weight!=null) return@withTimeout state.copy(weightKg=weight.kg)
                    token=page.nextToken?.takeIf { it.isNotEmpty() }
                    if (token!=null && !seen.add(token)) return@withTimeout state.copy(error="Health Connect returned a repeated page token")
                } while (!token.isNullOrEmpty())
                state
            }
        } catch (_: TimeoutCancellationException) { state.copy(error="Health Connect did not answer in time") }
        catch (e: CancellationException) { throw e }
        catch (e: Exception) { state.copy(error=e.message ?: e.javaClass.simpleName) }
    }
    companion object {
        val READ_WEIGHT: String = HealthPermission.getReadPermission(WeightRecord::class)
        val ONBOARDING_PERMISSIONS: Set<String> = setOf(HealthConnectSupport.HYDRATION_WRITE_PERMISSION,READ_WEIGHT)
    }
}
