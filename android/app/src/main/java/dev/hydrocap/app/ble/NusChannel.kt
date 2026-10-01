package dev.hydrocap.app.ble

import com.google.protobuf.MessageLite
import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.protocol.CapCodec
import dev.hydrocap.app.protocol.CapCommand
import dev.hydrocap.app.protocol.DecodedResponse
import dev.hydrocap.app.protocol.Hex
import dev.hydrocap.app.protocol.TypeUrls
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

/** Byte transport used by [NusChannel]; implemented by [CapConnection] and by test fakes. */
interface NusTransport {
    val notifications: Flow<ByteArray>
    suspend fun write(bytes: ByteArray)
}

class NusRequestException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** The cap answered, but not with SUCCESS. */
class CapErrorResponse(val response: DecodedResponse, val requestTypeName: String) :
    Exception("$requestTypeName answered ${response.code.name} (id ${response.requestId})")

/**
 * Request/response channel over NUS: one outstanding request at a time
 * ([requestMutex]), monotonically increasing ids, 4 s timeout, 2 retries
 * (3 attempts total), reassembly of fragmented notifications, and the command
 * allowlist enforced by [CapCodec] before anything reaches the transport.
 * Unmatched or late responses are logged and dropped.
 */
class NusChannel(
    private val transport: NusTransport,
    private val debugLog: DebugLog,
    scope: CoroutineScope,
    private val requestIds: RequestIdCounter,
    private val timeoutMs: Long = REQUEST_TIMEOUT_MS,
    private val maxRetries: Int = MAX_RETRIES,
) {
    private val requestMutex = Mutex()
    private val reassembler = NotificationReassembler()

    @Volatile
    private var pendingId: Long? = null
    @Volatile
    private var pendingResponse: CompletableDeferred<DecodedResponse>? = null

    // UNDISPATCHED: the collector subscribes to the transport's SharedFlow synchronously,
    // so a response can never arrive before we listen (SharedFlow drops values without subscribers).
    private val collector: Job = scope.launch(start = CoroutineStart.UNDISPATCHED) {
        transport.notifications.collect { bytes -> onNotification(bytes) }
    }

    /**
     * Sends [body] and returns the decoded response. Throws [NusRequestException]
     * after all attempts time out and [CapErrorResponse] when the cap answers
     * with FAIL/NOT_SUPPORTED (no retry for those — the cap did answer).
     */
    suspend fun request(body: MessageLite): DecodedResponse = requestMutex.withLock {
        val typeName = body.javaClass.simpleName
        var lastError: Throwable? = null
        for (attempt in 1..(maxRetries + 1)) {
            val id = requestIds.next()
            val bytes = CapCodec.encodeRequest(id, body) // allowlist enforced here
            val deferred = CompletableDeferred<DecodedResponse>()
            pendingId = id
            pendingResponse = deferred
            debugLog.log(TAG, "TX id=$id $typeName attempt=$attempt len=${bytes.size} hex=${Hex.encode(bytes)} ${body.summary()}")
            try {
                transport.write(bytes)
                val response = withTimeoutOrNull(timeoutMs) { deferred.await() }
                if (response != null) {
                    debugLog.log(TAG, "RX ${response.describe()}")
                    if (!response.isSuccess) throw CapErrorResponse(response, typeName)
                    return@withLock response
                }
                debugLog.log(TAG, "timeout id=$id $typeName after ${timeoutMs} ms (attempt $attempt/${maxRetries + 1})")
                lastError = NusRequestException("$typeName timed out (id $id)")
            } catch (e: CapErrorResponse) {
                throw e
            } catch (e: BleConnectionException) {
                debugLog.log(TAG, "write failed id=$id $typeName: ${e.message}")
                lastError = e
                if (!isRetryable(e)) break
            } finally {
                pendingId = null
                pendingResponse = null
            }
        }
        throw NusRequestException("$typeName failed after ${maxRetries + 1} attempts: ${lastError?.message}", lastError)
    }

    private fun isRetryable(e: BleConnectionException): Boolean =
        e.message?.contains("not connected") != true

    private fun onNotification(bytes: ByteArray) {
        when (val outcome = reassembler.offer(bytes)) {
            is NotificationReassembler.Outcome.Complete -> {
                if (outcome.fragments > 1) {
                    debugLog.log(TAG, "reassembled ${outcome.fragments} notifications into ${outcome.bytes.size} bytes")
                }
                deliver(outcome.response)
            }
            is NotificationReassembler.Outcome.Buffered ->
                debugLog.log(TAG, "notification (${bytes.size} B) is not a complete response, buffering (${outcome.pendingBytes} B pending)")
            is NotificationReassembler.Outcome.Reset ->
                debugLog.log(TAG, "reassembly buffer exceeded ${NotificationReassembler.MAX_BUFFER_BYTES} B, dropped ${outcome.droppedBytes} B")
        }
    }

    private fun deliver(response: DecodedResponse) {
        val expected = pendingId
        val deferred = pendingResponse
        if (expected != null && deferred != null && response.requestId == expected) {
            if (!deferred.complete(response)) debugLog.log(TAG, "duplicate response for id=${response.requestId}, dropped")
        } else {
            debugLog.log(TAG, "unmatched response ${response.describe()} (expected id=$expected), dropped")
        }
    }

    fun close() {
        collector.cancel()
        reassembler.reset()
    }

    private fun MessageLite.summary(): String {
        val text = toString().replace('\n', ' ').replace(Regex("\\s+"), " ").trim()
        return if (text.isEmpty()) "{}" else "{ $text }"
    }

    companion object {
        const val TAG = "nus"
        const val REQUEST_TIMEOUT_MS = 4_000L
        const val MAX_RETRIES = 2

        /** Type URL of the request a command sends; exposed for the Debug screen's "read all settings". */
        fun requestTypeUrl(command: CapCommand): String = TypeUrls.of(command.requestTypeName)
    }
}
