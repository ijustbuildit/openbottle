package dev.hydrocap.app.protocol

import com.google.protobuf.MessageLite

/**
 * Compile-time inventory of every request the cap understands that HydroCap is
 * allowed to send. A request whose message type is not listed here is rejected
 * by [CapCodec] before it reaches the BLE layer, so the out-of-scope commands
 * from the protocol doc (UV activate, DFU, factory reset, calibration,
 * thresholds, ADC, power saving, ToF/low-battery/bottle-sensor setters) can
 * never be encoded, let alone transmitted.
 */
enum class CapCommand(val requestTypeName: String, val responseTypeName: String?) {
    SET_TIME("RequestSetCapTimeSettings", null),
    GET_TIME("RequestGetCapTimeSettings", "ResponseGetCapTimeSettings"),
    GET_UI_STATE("RequestGetCapUiState", "ResponseGetCapUiState"),
    GET_TOF_SETTINGS("RequestGetCapTofSettings", "ResponseGetCapTofSettings"),
    GET_TOF_STATE("RequestGetCapTofState", "ResponseGetCapTofState"),
    GET_TOF_LOG("RequestGetCapTofLog", "ResponseGetCapTofLog"),
    GET_ACTIVATION_LOG("RequestGetCapActivationLog", "ResponseGetCapActivationLog"),
    GET_HYDRO_REMINDER("RequestGetCapHydroReminderSettings", "ResponseGetCapHydroReminderSettings"),
    SET_HYDRO_REMINDER("RequestSetCapHydroReminderSettings", null),
    GET_DND("RequestGetCapDoNotDisturbSettings", "ResponseGetCapDoNotDisturbSettings"),
    SET_DND("RequestSetCapDoNotDisturbSettings", null),
    GET_LOW_BATTERY("RequestGetCapLowBatterySettings", "ResponseGetCapLowBatterySettings");

    val requestTypeUrl: String get() = TypeUrls.of(requestTypeName)
    val responseTypeUrl: String? get() = responseTypeName?.let(TypeUrls::of)

    companion object {
        /** Request message class names allowed on the wire (unqualified proto names). */
        val allowedRequestTypeNames: Set<String> = entries.map { it.requestTypeName }.toSet()

        /**
         * Commands the firmware supports but which HydroCap must never send
         * (docs/protocol/ble-protocol.md §4). Kept here so the unit test can
         * assert the two sets are disjoint and the forbidden ones are absent.
         */
        val forbiddenRequestTypeNames: Set<String> = setOf(
            "RequestSetCapUvActivate",
            "RequestSetCapConfig",
            "RequestSetCapThreshold",
            "RequestSetCapAdcProtection",
            "RequestSetCapLowBatterySettings",
            "RequestSetCapTofSettings",
            "RequestSetCapCalibrationSettings",
            "RequestCapStartCapCalibration",
            "RequestCapStopCapCalibration",
            "RequestCapEnterLowBatteryMode",
            "RequestCapEnterDfuMode",
            "RequestCapFactoryReset",
            "RequestSetCapPowerSavingMode",
            "RequestSetCapBottleSensorState",
        )

        fun forRequest(message: MessageLite): CapCommand? {
            val name = message.javaClass.simpleName
            return entries.firstOrNull { it.requestTypeName == name }
        }

        fun forRequestTypeName(name: String): CapCommand? = entries.firstOrNull { it.requestTypeName == name }
    }
}

/** Any.type_url construction; the cap dispatches on the unqualified message name. */
object TypeUrls {
    const val PREFIX = "type.googleapis.com/"

    fun of(messageName: String): String = PREFIX + messageName

    fun messageName(typeUrl: String): String = typeUrl.substringAfterLast('/')
}
