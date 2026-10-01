package dev.hydrocap.app.protocol

import dev.hydrocap.app.proto.CapActivationLog
import dev.hydrocap.app.proto.CapColor
import dev.hydrocap.app.proto.CapEnumHydroReminderState
import dev.hydrocap.app.proto.CapEnumLogQuerySearchAlgo
import dev.hydrocap.app.proto.CapEnumResponseCode
import dev.hydrocap.app.proto.CapEnumTofMode
import dev.hydrocap.app.proto.CapEnumTofTriggerType
import dev.hydrocap.app.proto.CapEnumUiState
import dev.hydrocap.app.proto.CapEnumUvActivationMode
import dev.hydrocap.app.proto.CapHydroReminderSettings
import dev.hydrocap.app.proto.CapLogQuery
import dev.hydrocap.app.proto.CapLowBatterySettings
import dev.hydrocap.app.proto.CapPowerSavingMode
import dev.hydrocap.app.proto.CapTimeSettings
import dev.hydrocap.app.proto.CapTofLog
import dev.hydrocap.app.proto.CapTofSettings
import dev.hydrocap.app.proto.CapTofState
import dev.hydrocap.app.proto.RequestGetCapActivationLog
import dev.hydrocap.app.proto.RequestGetCapTofLog
import dev.hydrocap.app.proto.RequestGetCapUiState
import dev.hydrocap.app.proto.RequestSetCapHydroReminderSettings
import dev.hydrocap.app.proto.RequestSetCapTimeSettings
import dev.hydrocap.app.proto.ResponseGetCapActivationLog
import dev.hydrocap.app.proto.ResponseGetCapHydroReminderSettings
import dev.hydrocap.app.proto.ResponseGetCapLowBatterySettings
import dev.hydrocap.app.proto.ResponseGetCapTofLog
import dev.hydrocap.app.proto.ResponseGetCapTofSettings
import dev.hydrocap.app.proto.ResponseGetCapTofState
import dev.hydrocap.app.proto.ResponseGetCapUiState
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Golden vectors copied verbatim from docs/protocol/ble-protocol.md §7
 * (generated with protoc 36.0 against the vendor schema). Every request must
 * encode byte-for-byte; every response must decode to the documented message.
 */
class ProtocolGoldenTest {

    // --- Requests ---------------------------------------------------------

    @Test
    fun `request 1 GetCapUiState`() {
        val expected = "0d01000000122a0a28747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617055695374617465"
        val bytes = CapCodec.encodeRequest(1, RequestGetCapUiState.getDefaultInstance())
        assertEquals(expected, Hex.encode(bytes))
        assertArrayEquals(Hex.decode(expected), bytes)
    }

    @Test
    fun `request 7 SetCapTimeSettings`() {
        val expected = "0d07000000123a0a2d747970652e676f6f676c65617069732e636f6d2f5265717565737453657443617054696d6553657474696e677312090a070880d8c1a28c34"
        val body = RequestSetCapTimeSettings.newBuilder()
            .setSettings(CapTimeSettings.newBuilder().setTimeInMillisec(1_790_000_000_000L))
            .build()
        assertEquals(expected, Hex.encode(CapCodec.encodeRequest(7, body)))
    }

    @Test
    fun `request 3 GetCapTofLog`() {
        val expected = "0d0300000012380a27747970652e676f6f676c65617069732e636f6d2f52657175657374476574436170546f664c6f67120d0a0b08fff6c4d5061505000000"
        val body = RequestGetCapTofLog.newBuilder()
            .setQuery(
                CapLogQuery.newBuilder()
                    .setFromTimestamp(1_789_999_999L)
                    .setLimit(5)
                    .setAlgo(CapEnumLogQuerySearchAlgo.SEARCH_ALGO_TIMESTAMP),
            )
            .build()
        assertEquals(expected, Hex.encode(CapCodec.encodeRequest(3, body)))
    }

    @Test
    fun `request 12 GetCapActivationLog with zero fromTimestamp`() {
        val expected = "0d0c00000012390a2e747970652e676f6f676c65617069732e636f6d2f5265717565737447657443617041637469766174696f6e4c6f6712070a051506000000"
        val body = RequestGetCapActivationLog.newBuilder()
            .setQuery(
                CapLogQuery.newBuilder()
                    .setFromTimestamp(0)
                    .setLimit(6)
                    .setAlgo(CapEnumLogQuerySearchAlgo.SEARCH_ALGO_TIMESTAMP),
            )
            .build()
        assertEquals(expected, Hex.encode(CapCodec.encodeRequest(12, body)))
    }

    @Test
    fun `request 11 SetCapHydroReminderSettings`() {
        val expected = "0d0b00000012520a36747970652e676f6f676c65617069732e636f6d2f52657175657374536574436170487964726f52656d696e64657253657474696e677312180a1615010000001d805101002a0a1d0000803f250000803f"
        val body = RequestSetCapHydroReminderSettings.newBuilder()
            .setSettings(
                CapHydroReminderSettings.newBuilder()
                    .setState(CapEnumHydroReminderState.REMINDER_STATE_OFF)
                    .setStartTimeInSec(1)
                    .setStopTimeInSec(86_400)
                    .setIntervalInSec(0)
                    .setColor(CapColor.newBuilder().setRed(0f).setGreen(0f).setBlue(1f).setAlpha(1f)),
            )
            .build()
        assertEquals(expected, Hex.encode(CapCodec.encodeRequest(11, body)))
    }

    // --- Responses --------------------------------------------------------

    @Test
    fun `response 1 GetCapUiState`() {
        val decoded = CapCodec.decodeResponse(
            Hex.decode("0d0100000010011a310a29747970652e676f6f676c65617069732e636f6d2f526573706f6e736547657443617055695374617465120408081001"),
        )
        assertEquals(1L, decoded.requestId)
        assertEquals(CapEnumResponseCode.SUCCESS, decoded.code)
        assertEquals("ResponseGetCapUiState", decoded.typeName)
        val expected = ResponseGetCapUiState.newBuilder()
            .setState(CapEnumUiState.UI_STATE_CHARGING)
            .setPowerSavingMode(CapPowerSavingMode.POWER_SAVING_MODE_OFF)
            .build()
        assertEquals(expected, decoded.body)
    }

    @Test
    fun `response 3 GetCapTofLog`() {
        val decoded = CapCodec.decodeResponse(
            Hex.decode("0d0300000010011a5e0a28747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f664c6f6712320a1708e4f7c4d50610021d7800000025641900002d00421c460a1708c8f8c4d50610011d8700000025d41700002d00191c46"),
        )
        assertEquals(3L, decoded.requestId)
        assertEquals(CapEnumResponseCode.SUCCESS, decoded.code)
        val expected = ResponseGetCapTofLog.newBuilder()
            .addItems(
                CapTofLog.newBuilder()
                    .setTimestamp(1_790_000_100L)
                    .setTriggerType(CapEnumTofTriggerType.TYPE_CAP)
                    .setDistanceInMillimeter(120)
                    .setKcps(6_500)
                    .setUvLedTempInOhm(10_000.5f),
            )
            .addItems(
                CapTofLog.newBuilder()
                    .setTimestamp(1_790_000_200L)
                    .setTriggerType(CapEnumTofTriggerType.TYPE_INTERVAL)
                    .setDistanceInMillimeter(135)
                    .setKcps(6_100)
                    .setUvLedTempInOhm(9_990.25f),
            )
            .build()
        assertEquals(expected, decoded.body)
    }

    @Test
    fun `response 4 GetCapTofSettings`() {
        val decoded = CapCodec.decodeResponse(
            Hex.decode("0d0400000010011a4b0a2d747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f6653657474696e6773121a0a18080210011d2c01000025050000002da8020000350a000000"),
        )
        assertEquals(4L, decoded.requestId)
        val expected = ResponseGetCapTofSettings.newBuilder()
            .setSettings(
                CapTofSettings.newBuilder()
                    .setMode(CapEnumTofMode.DISPLAY_MODE_EVENT)
                    .setIsIntervalTriggerEnabled(true)
                    .setTriggerIntervalInSec(300)
                    .setAccelerometerCheckIntervalInSec(5)
                    .setBottleSizeInMilliliter(680)
                    .setAccelerometerTimeoutInSec(10),
            )
            .build()
        assertEquals(expected, decoded.body)
    }

    @Test
    fun `response 5 GetCapHydroReminderSettings`() {
        val decoded = CapCodec.decodeResponse(
            Hex.decode("0d0500000010011a640a37747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170487964726f52656d696e64657253657474696e677312290a27080115807000001d6035010025100e00002a140d0000803f150000003f1d0000803e250000803f"),
        )
        assertEquals(5L, decoded.requestId)
        val expected = ResponseGetCapHydroReminderSettings.newBuilder()
            .setSettings(
                CapHydroReminderSettings.newBuilder()
                    .setState(CapEnumHydroReminderState.REMINDER_STATE_INTERVAL_FIXED)
                    .setStartTimeInSec(28_800)
                    .setStopTimeInSec(79_200)
                    .setIntervalInSec(3_600)
                    .setColor(CapColor.newBuilder().setRed(1f).setGreen(0.5f).setBlue(0.25f).setAlpha(1f)),
            )
            .build()
        assertEquals(expected, decoded.body)
    }

    @Test
    fun `response 6 GetCapTofState`() {
        val decoded = CapCodec.decodeResponse(
            Hex.decode("0d0600000010011a3a0a2a747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f665374617465120c0a0a0d2a00000015e02e0000"),
        )
        assertEquals(6L, decoded.requestId)
        val expected = ResponseGetCapTofState.newBuilder()
            .setState(CapTofState.newBuilder().setDistanceInMillimeter(42).setKcps(12_000))
            .build()
        assertEquals(expected, decoded.body)
    }

    @Test
    fun `response 8 GetCapLowBatterySettings`() {
        val decoded = CapCodec.decodeResponse(
            Hex.decode("0d0800000010011a440a34747970652e676f6f676c65617069732e636f6d2f526573706f6e73654765744361704c6f774261747465727953657474696e6773120c0a0a0d140000001505000000"),
        )
        assertEquals(8L, decoded.requestId)
        val expected = ResponseGetCapLowBatterySettings.newBuilder()
            .setSettings(
                CapLowBatterySettings.newBuilder()
                    .setAlertThresholdInPercentage(20)
                    .setLockoutThresholdInPercentage(5),
            )
            .build()
        assertEquals(expected, decoded.body)
    }

    @Test
    fun `response 10 GetCapActivationLog`() {
        val decoded = CapCodec.decodeResponse(
            Hex.decode("0d0a00000010011a400a2f747970652e676f6f676c65617069732e636f6d2f526573706f6e736547657443617041637469766174696f6e4c6f67120d0a0b08acf9c4d5061d57000000"),
        )
        assertEquals(10L, decoded.requestId)
        val expected = ResponseGetCapActivationLog.newBuilder()
            .addItems(
                CapActivationLog.newBuilder()
                    .setTimestamp(1_790_000_300L)
                    .setMode(CapEnumUvActivationMode.UV_ACTIVATION_MAINTENANCE)
                    .setBatterySocInPercentage(87),
            )
            .build()
        assertEquals(expected, decoded.body)
    }

    @Test
    fun `response 9 NOT_SUPPORTED without body`() {
        val decoded = CapCodec.decodeResponse(Hex.decode("0d090000001002"))
        assertEquals(9L, decoded.requestId)
        assertEquals(CapEnumResponseCode.NOT_SUPPORTED, decoded.code)
        assertNull(decoded.typeName)
        assertNull(decoded.body)
        assertTrue(!decoded.isSuccess)
    }

    /**
     * Hardware session 2 (2026-09-29): a log query whose `fromTimestamp` is past
     * the newest entry is answered with `SUCCESS` and no `body` field at all
     * (`0d 03010000 10 01` = requestId 259, code 1). Log readers must treat this
     * as an empty page, not as a protocol error.
     */
    @Test
    fun `log query past the newest entry is SUCCESS without body`() {
        val decoded = CapCodec.decodeResponse(Hex.decode("0d030100001001"))
        assertEquals(259L, decoded.requestId)
        assertEquals(CapEnumResponseCode.SUCCESS, decoded.code)
        assertTrue(decoded.isSuccess)
        assertNull(decoded.typeName)
        assertNull(decoded.body)
    }

    // --- type_url strings -------------------------------------------------

    @Test
    fun `type urls use the unqualified message names from the protocol doc`() {
        val expectedRequestUrls = mapOf(
            CapCommand.SET_TIME to "type.googleapis.com/RequestSetCapTimeSettings",
            CapCommand.GET_TIME to "type.googleapis.com/RequestGetCapTimeSettings",
            CapCommand.GET_UI_STATE to "type.googleapis.com/RequestGetCapUiState",
            CapCommand.GET_TOF_SETTINGS to "type.googleapis.com/RequestGetCapTofSettings",
            CapCommand.GET_TOF_STATE to "type.googleapis.com/RequestGetCapTofState",
            CapCommand.GET_TOF_LOG to "type.googleapis.com/RequestGetCapTofLog",
            CapCommand.GET_ACTIVATION_LOG to "type.googleapis.com/RequestGetCapActivationLog",
            CapCommand.GET_HYDRO_REMINDER to "type.googleapis.com/RequestGetCapHydroReminderSettings",
            CapCommand.SET_HYDRO_REMINDER to "type.googleapis.com/RequestSetCapHydroReminderSettings",
            CapCommand.GET_DND to "type.googleapis.com/RequestGetCapDoNotDisturbSettings",
            CapCommand.SET_DND to "type.googleapis.com/RequestSetCapDoNotDisturbSettings",
            CapCommand.GET_LOW_BATTERY to "type.googleapis.com/RequestGetCapLowBatterySettings",
        )
        assertEquals(CapCommand.entries.toSet(), expectedRequestUrls.keys)
        expectedRequestUrls.forEach { (command, url) -> assertEquals(url, command.requestTypeUrl) }

        // The generated classes must carry the exact unqualified names (no package prefix).
        val built = CapCodec.buildRequest(1, RequestGetCapUiState.getDefaultInstance())
        assertEquals("type.googleapis.com/RequestGetCapUiState", built.body.typeUrl)
        assertEquals("RequestGetCapUiState", RequestGetCapUiState::class.java.simpleName)
        assertEquals("ResponseGetCapTofLog", ResponseGetCapTofLog::class.java.simpleName)
    }

    @Test
    fun `request id is encoded as fixed32 and read back unsigned`() {
        val built = CapCodec.buildRequest(0xFFFF_FFF0L, RequestGetCapUiState.getDefaultInstance())
        assertEquals(0xFFFF_FFF0L, CapCodec.requestIdOf(built))
        val decoded = CapCodec.decodeResponse(Hex.decode("0df0ffffff1001"))
        assertEquals(0xFFFF_FFF0L, decoded.requestId)
    }
}
