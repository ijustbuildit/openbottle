package dev.hydrocap.app.ble

import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.proto.CapDoNotDisturbSettings
import dev.hydrocap.app.proto.CapEnumLogQuerySearchAlgo
import dev.hydrocap.app.proto.CapHydroReminderSettings
import dev.hydrocap.app.proto.CapLogQuery
import dev.hydrocap.app.proto.CapTimeSettings
import dev.hydrocap.app.proto.RequestGetCapActivationLog
import dev.hydrocap.app.proto.RequestGetCapDoNotDisturbSettings
import dev.hydrocap.app.proto.RequestGetCapHydroReminderSettings
import dev.hydrocap.app.proto.RequestGetCapLowBatterySettings
import dev.hydrocap.app.proto.RequestGetCapTimeSettings
import dev.hydrocap.app.proto.RequestGetCapTofLog
import dev.hydrocap.app.proto.RequestGetCapTofSettings
import dev.hydrocap.app.proto.RequestGetCapTofState
import dev.hydrocap.app.proto.RequestGetCapUiState
import dev.hydrocap.app.proto.RequestSetCapDoNotDisturbSettings
import dev.hydrocap.app.proto.RequestSetCapHydroReminderSettings
import dev.hydrocap.app.proto.RequestSetCapTimeSettings
import dev.hydrocap.app.proto.ResponseGetCapActivationLog
import dev.hydrocap.app.proto.ResponseGetCapDoNotDisturbSettings
import dev.hydrocap.app.proto.ResponseGetCapHydroReminderSettings
import dev.hydrocap.app.proto.ResponseGetCapLowBatterySettings
import dev.hydrocap.app.proto.ResponseGetCapTimeSettings
import dev.hydrocap.app.proto.ResponseGetCapTofLog
import dev.hydrocap.app.proto.ResponseGetCapTofSettings
import dev.hydrocap.app.proto.ResponseGetCapTofState
import dev.hydrocap.app.proto.ResponseGetCapUiState
import dev.hydrocap.app.protocol.DecodedResponse
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow

/**
 * Typed API over one connected cap. Every method maps 1:1 to an allowlisted
 * command from docs/protocol/ble-protocol.md §4; setters return the bare
 * envelope because the cap answers them with SUCCESS and no body.
 */
class CapClient(
    private val connection: CapConnection,
    debugLog: DebugLog,
    scope: CoroutineScope,
    requestIds: RequestIdCounter,
) {
    private val channel = NusChannel(
        transport = object : NusTransport {
            override val notifications: Flow<ByteArray> = connection.nusNotifications
            override suspend fun write(bytes: ByteArray) = connection.writeNusRx(bytes)
        },
        debugLog = debugLog,
        scope = scope,
        requestIds = requestIds,
    )

    val connectionState: StateFlow<ConnectionState> get() = connection.state
    val deviceInformation: DeviceInformation? get() = connection.deviceInformation
    val negotiatedMtu: Int get() = connection.negotiatedMtu

    /** Must be the first request after subscribing: the cap clock drifts by weeks otherwise. */
    suspend fun setTime(nowEpochMs: Long = System.currentTimeMillis()): DecodedResponse =
        channel.request(
            RequestSetCapTimeSettings.newBuilder()
                .setSettings(CapTimeSettings.newBuilder().setTimeInMillisec(nowEpochMs))
                .build(),
        )

    suspend fun getTime(): ResponseGetCapTimeSettings =
        channel.request(RequestGetCapTimeSettings.getDefaultInstance()).bodyAs()

    suspend fun getUiState(): ResponseGetCapUiState =
        channel.request(RequestGetCapUiState.getDefaultInstance()).bodyAs()

    suspend fun getTofSettings(): ResponseGetCapTofSettings =
        channel.request(RequestGetCapTofSettings.getDefaultInstance()).bodyAs()

    suspend fun getTofState(): ResponseGetCapTofState =
        channel.request(RequestGetCapTofState.getDefaultInstance()).bodyAs()

    /** Entries with timestamp > [fromTimestampSec], oldest first, at most [limit]. */
    suspend fun getTofLog(fromTimestampSec: Long, limit: Int): ResponseGetCapTofLog =
        channel.request(RequestGetCapTofLog.newBuilder().setQuery(query(fromTimestampSec, limit)).build())
            .bodyOrEmpty(ResponseGetCapTofLog.getDefaultInstance())

    suspend fun getActivationLog(fromTimestampSec: Long, limit: Int): ResponseGetCapActivationLog =
        channel.request(RequestGetCapActivationLog.newBuilder().setQuery(query(fromTimestampSec, limit)).build())
            .bodyOrEmpty(ResponseGetCapActivationLog.getDefaultInstance())

    suspend fun getHydroReminder(): ResponseGetCapHydroReminderSettings =
        channel.request(RequestGetCapHydroReminderSettings.getDefaultInstance()).bodyAs()

    suspend fun setHydroReminder(settings: CapHydroReminderSettings): DecodedResponse =
        channel.request(RequestSetCapHydroReminderSettings.newBuilder().setSettings(settings).build())

    suspend fun getDnd(): ResponseGetCapDoNotDisturbSettings =
        channel.request(RequestGetCapDoNotDisturbSettings.getDefaultInstance()).bodyAs()

    suspend fun setDnd(settings: CapDoNotDisturbSettings): DecodedResponse =
        channel.request(RequestSetCapDoNotDisturbSettings.newBuilder().setSettings(settings).build())

    suspend fun getLowBatterySettings(): ResponseGetCapLowBatterySettings =
        channel.request(RequestGetCapLowBatterySettings.getDefaultInstance()).bodyAs()

    /** Battery Level (0x2A19) via GATT read, not NUS. */
    suspend fun readBattery(): Int? = connection.readBatteryLevel()

    /** Battery Level notifications while connected. */
    fun observeBattery(): StateFlow<Int?> = connection.batteryLevel

    fun close() = channel.close()

    private fun query(fromTimestampSec: Long, limit: Int): CapLogQuery.Builder =
        CapLogQuery.newBuilder()
            .setFromTimestamp(fromTimestampSec)
            .setLimit(limit)
            .setAlgo(CapEnumLogQuerySearchAlgo.SEARCH_ALGO_TIMESTAMP)

    private inline fun <reified T> DecodedResponse.bodyAs(): T =
        body as? T ?: throw NusRequestException("expected ${T::class.java.simpleName} body but got ${typeName ?: "none"} (id $requestId)")

    /**
     * Log queries: hardware session 2 showed that the cap answers a query that
     * matches no entries with `SUCCESS` and **no body at all** (not an empty
     * message). Treat that as an empty page; any other body type is an error.
     */
    private inline fun <reified T> DecodedResponse.bodyOrEmpty(empty: T): T = when {
        body == null && typeName == null -> empty
        else -> bodyAs()
    }
}
