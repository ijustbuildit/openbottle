package dev.hydrocap.app.protocol

import com.google.protobuf.Any
import com.google.protobuf.ByteString
import com.google.protobuf.InvalidProtocolBufferException
import com.google.protobuf.MessageLite
import dev.hydrocap.app.proto.CapBleRequest
import dev.hydrocap.app.proto.CapBleResponse
import dev.hydrocap.app.proto.CapEnumResponseCode
import dev.hydrocap.app.proto.ResponseGetCapActivationLog
import dev.hydrocap.app.proto.ResponseGetCapDoNotDisturbSettings
import dev.hydrocap.app.proto.ResponseGetCapHydroReminderSettings
import dev.hydrocap.app.proto.ResponseGetCapLowBatterySettings
import dev.hydrocap.app.proto.ResponseGetCapTimeSettings
import dev.hydrocap.app.proto.ResponseGetCapTofLog
import dev.hydrocap.app.proto.ResponseGetCapTofSettings
import dev.hydrocap.app.proto.ResponseGetCapTofState
import dev.hydrocap.app.proto.ResponseGetCapUiState

/** Thrown when a message outside [CapCommand] is handed to the codec. */
class DisallowedCommandException(typeName: String) :
    IllegalArgumentException("Request '$typeName' is not in the HydroCap command allowlist")

/** A decoded response envelope. [body] is null for setters and for NOT_SUPPORTED/FAIL. */
data class DecodedResponse(
    val requestId: Long,
    val code: CapEnumResponseCode,
    val codeNumber: Int,
    val typeName: String?,
    val body: MessageLite?,
) {
    val isSuccess: Boolean get() = code == CapEnumResponseCode.SUCCESS

    /** Human-readable rendering for the debug log. */
    fun describe(): String = buildString {
        append("id=").append(requestId).append(" code=").append(code.name)
        if (code == CapEnumResponseCode.UNRECOGNIZED) append('(').append(codeNumber).append(')')
        if (typeName != null) append(" type=").append(typeName)
        if (body != null) append(' ').append(body.toString().replace('\n', ' ').replace(Regex("\\s+"), " ").trim())
    }
}

/**
 * Encodes [CapBleRequest] envelopes and decodes [CapBleResponse] envelopes,
 * including unpacking the `google.protobuf.Any` body by its unqualified
 * message name. Enforces the command allowlist on the encode path.
 */
object CapCodec {

    fun encodeRequest(requestId: Long, body: MessageLite): ByteArray {
        val typeName = body.javaClass.simpleName
        if (typeName !in CapCommand.allowedRequestTypeNames) throw DisallowedCommandException(typeName)
        return buildRequest(requestId, typeName, body).toByteArray()
    }

    fun buildRequest(requestId: Long, body: MessageLite): CapBleRequest {
        val typeName = body.javaClass.simpleName
        if (typeName !in CapCommand.allowedRequestTypeNames) throw DisallowedCommandException(typeName)
        return buildRequest(requestId, typeName, body)
    }

    private fun buildRequest(requestId: Long, typeName: String, body: MessageLite): CapBleRequest =
        CapBleRequest.newBuilder()
            .setRequestId(requestId.toInt())
            .setBody(
                Any.newBuilder()
                    .setTypeUrl(TypeUrls.of(typeName))
                    .setValue(body.toByteString())
                    .build(),
            )
            .build()

    /** Request id as sent on the wire (fixed32 → unsigned). */
    fun requestIdOf(request: CapBleRequest): Long = request.requestId.toLong() and 0xFFFF_FFFFL

    @Throws(InvalidProtocolBufferException::class)
    fun decodeResponse(bytes: ByteArray): DecodedResponse {
        val envelope = CapBleResponse.parseFrom(bytes)
        val requestId = envelope.requestId.toLong() and 0xFFFF_FFFFL
        val codeNumber = envelope.codeValue
        val code = envelope.code
        if (!envelope.hasBody() || envelope.body.typeUrl.isEmpty()) {
            return DecodedResponse(requestId, code, codeNumber, null, null)
        }
        val typeName = TypeUrls.messageName(envelope.body.typeUrl)
        val body = unpack(typeName, envelope.body.value)
        return DecodedResponse(requestId, code, codeNumber, typeName, body)
    }

    /**
     * Strict parse used by the reassembly buffer: a truncated message must not
     * be accepted as a complete one. Proto3 parsing tolerates missing trailing
     * fields, so we additionally require the envelope to round-trip to the
     * same byte length (i.e. no trailing garbage, no unknown data) and, when a
     * body is present, that its `Any` payload decodes to a known type.
     */
    fun tryDecodeComplete(bytes: ByteArray): DecodedResponse? {
        if (bytes.isEmpty()) return null
        return try {
            val envelope = CapBleResponse.parseFrom(bytes)
            if (envelope.serializedSize != bytes.size) return null
            decodeResponse(bytes)
        } catch (_: InvalidProtocolBufferException) {
            null
        }
    }

    @Throws(InvalidProtocolBufferException::class)
    private fun unpack(typeName: String, value: ByteString): MessageLite? = when (typeName) {
        "ResponseGetCapUiState" -> ResponseGetCapUiState.parseFrom(value)
        "ResponseGetCapTofSettings" -> ResponseGetCapTofSettings.parseFrom(value)
        "ResponseGetCapTofState" -> ResponseGetCapTofState.parseFrom(value)
        "ResponseGetCapTofLog" -> ResponseGetCapTofLog.parseFrom(value)
        "ResponseGetCapActivationLog" -> ResponseGetCapActivationLog.parseFrom(value)
        "ResponseGetCapHydroReminderSettings" -> ResponseGetCapHydroReminderSettings.parseFrom(value)
        "ResponseGetCapDoNotDisturbSettings" -> ResponseGetCapDoNotDisturbSettings.parseFrom(value)
        "ResponseGetCapLowBatterySettings" -> ResponseGetCapLowBatterySettings.parseFrom(value)
        "ResponseGetCapTimeSettings" -> ResponseGetCapTimeSettings.parseFrom(value)
        else -> null // unknown body type: keep the envelope, drop the payload
    }
}
