package dev.hydrocap.app.protocol

import dev.hydrocap.app.proto.CapBleRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Asserts the compile-time command allowlist from docs/protocol/ble-protocol.md §4. */
class CommandAllowlistTest {

    @Test
    fun `allowlist contains exactly the MVP commands`() {
        val expected = setOf(
            "RequestSetCapTimeSettings",
            "RequestGetCapTimeSettings",
            "RequestGetCapUiState",
            "RequestGetCapTofSettings",
            "RequestGetCapTofState",
            "RequestGetCapTofLog",
            "RequestGetCapActivationLog",
            "RequestGetCapHydroReminderSettings",
            "RequestSetCapHydroReminderSettings",
            "RequestGetCapDoNotDisturbSettings",
            "RequestSetCapDoNotDisturbSettings",
            "RequestGetCapLowBatterySettings",
        )
        assertEquals(expected, CapCommand.allowedRequestTypeNames)
    }

    @Test
    fun `the only allowed setters are reminder, quiet hours and time`() {
        val setters = CapCommand.allowedRequestTypeNames.filterNot { it.startsWith("RequestGet") }.toSet()
        assertEquals(
            setOf("RequestSetCapHydroReminderSettings", "RequestSetCapDoNotDisturbSettings", "RequestSetCapTimeSettings"),
            setters,
        )
        assertEquals(
            setOf(CapCommand.SET_HYDRO_REMINDER, CapCommand.SET_DND, CapCommand.SET_TIME),
            CapCommand.entries.filter { it.responseTypeName == null }.toSet(),
        )
    }

    @Test
    fun `no forbidden command is allowlisted`() {
        val overlap = CapCommand.allowedRequestTypeNames intersect CapCommand.forbiddenRequestTypeNames
        assertTrue("forbidden commands present in allowlist: $overlap", overlap.isEmpty())
        val mustBeForbidden = listOf(
            "RequestSetCapUvActivate",
            "RequestCapEnterDfuMode",
            "RequestCapFactoryReset",
            "RequestSetCapCalibrationSettings",
            "RequestCapStartCapCalibration",
            "RequestCapStopCapCalibration",
            "RequestSetCapThreshold",
            "RequestSetCapAdcProtection",
            "RequestSetCapPowerSavingMode",
            "RequestSetCapTofSettings",
            "RequestSetCapLowBatterySettings",
            "RequestSetCapBottleSensorState",
            "RequestCapEnterLowBatteryMode",
            "RequestSetCapConfig",
        )
        mustBeForbidden.forEach { assertTrue("$it must be forbidden", it in CapCommand.forbiddenRequestTypeNames) }
    }

    @Test
    fun `forbidden message types do not exist in the generated schema`() {
        // If someone adds a setter to hydrocap.proto it must also be allowlisted here on purpose.
        CapCommand.forbiddenRequestTypeNames.forEach { name ->
            try {
                Class.forName("dev.hydrocap.app.proto.$name")
                fail("forbidden message $name must not be part of the schema")
            } catch (_: ClassNotFoundException) {
                // expected
            }
        }
    }

    @Test
    fun `every generated request message is either allowlisted or forbidden by name`() {
        // Every Request* class that exists in the schema must be allowlisted; the setters we ship are exactly three.
        val generated = listOf(
            "RequestSetCapTimeSettings", "RequestGetCapTimeSettings", "RequestGetCapUiState", "RequestGetCapTofSettings",
            "RequestGetCapTofState", "RequestGetCapTofLog", "RequestGetCapActivationLog", "RequestGetCapHydroReminderSettings",
            "RequestSetCapHydroReminderSettings", "RequestGetCapDoNotDisturbSettings", "RequestSetCapDoNotDisturbSettings",
            "RequestGetCapLowBatterySettings",
        )
        generated.forEach { name ->
            Class.forName("dev.hydrocap.app.proto.$name")
            assertTrue("$name exists in the schema and must be allowlisted", name in CapCommand.allowedRequestTypeNames)
        }
    }

    @Test
    fun `codec rejects a message that is not allowlisted`() {
        // CapBleRequest is a valid proto message but never a request body.
        try {
            CapCodec.encodeRequest(1, CapBleRequest.getDefaultInstance())
            fail("expected DisallowedCommandException")
        } catch (e: DisallowedCommandException) {
            assertTrue(e.message!!.contains("CapBleRequest"))
        }
        assertFalse(CapCommand.allowedRequestTypeNames.contains("CapBleRequest"))
    }
}
