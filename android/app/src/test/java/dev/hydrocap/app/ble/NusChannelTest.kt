package dev.hydrocap.app.ble

import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.proto.CapBleResponse
import dev.hydrocap.app.proto.CapEnumResponseCode
import dev.hydrocap.app.proto.RequestGetCapUiState
import dev.hydrocap.app.proto.ResponseGetCapUiState
import dev.hydrocap.app.protocol.CapCodec
import dev.hydrocap.app.protocol.Hex
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.async
import kotlinx.coroutines.delay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class NusChannelTest {

    /** Fake link: records writes and lets the test inject notifications. */
    private class FakeTransport : NusTransport {
        override val notifications = MutableSharedFlow<ByteArray>(extraBufferCapacity = 16)
        val writes = ArrayList<ByteArray>()
        var onWrite: suspend (ByteArray) -> Unit = {}

        override suspend fun write(bytes: ByteArray) {
            writes += bytes
            onWrite(bytes)
        }

        suspend fun respond(requestId: Long, body: ByteArray? = null, code: CapEnumResponseCode = CapEnumResponseCode.SUCCESS) {
            val builder = CapBleResponse.newBuilder().setRequestId(requestId.toInt()).setCode(code)
            if (body != null) {
                builder.setBody(
                    com.google.protobuf.Any.newBuilder()
                        .setTypeUrl("type.googleapis.com/ResponseGetCapUiState")
                        .setValue(com.google.protobuf.ByteString.copyFrom(body)),
                )
            }
            notifications.emit(builder.build().toByteArray())
        }
    }

    private val log = DebugLog(filesDir = null)
    private val uiStateBody = ResponseGetCapUiState.newBuilder().setStateValue(8).setPowerSavingModeValue(1).build().toByteArray()

    private fun TestScope.channel(transport: FakeTransport, ids: RequestIdCounter = RequestIdCounter()) =
        NusChannel(transport, log, this, ids, timeoutMs = 4_000, maxRetries = 2)

    @Test
    fun `request is answered when the response id matches`() = runTest {
        val transport = FakeTransport()
        val channel = channel(transport)
        transport.onWrite = { bytes ->
            val id = CapCodec.requestIdOf(dev.hydrocap.app.proto.CapBleRequest.parseFrom(bytes))
            transport.respond(id, uiStateBody)
        }
        val response = channel.request(RequestGetCapUiState.getDefaultInstance())
        assertEquals(1L, response.requestId)
        assertTrue(response.body is ResponseGetCapUiState)
        assertEquals(1, transport.writes.size)
        channel.close()
    }

    @Test
    fun `ids increase monotonically across requests and retries`() = runTest {
        val transport = FakeTransport()
        val channel = channel(transport)
        var calls = 0
        transport.onWrite = { bytes ->
            calls++
            val id = CapCodec.requestIdOf(dev.hydrocap.app.proto.CapBleRequest.parseFrom(bytes))
            if (calls >= 2) transport.respond(id, uiStateBody) // first attempt times out
        }
        val response = channel.request(RequestGetCapUiState.getDefaultInstance())
        assertEquals(2L, response.requestId)
        val ids = transport.writes.map { CapCodec.requestIdOf(dev.hydrocap.app.proto.CapBleRequest.parseFrom(it)) }
        assertEquals(listOf(1L, 2L), ids)
        val next = async { channel.request(RequestGetCapUiState.getDefaultInstance()) }
        advanceTimeBy(1)
        assertEquals(3L, next.await().requestId)
        channel.close()
    }

    @Test
    fun `unmatched and late responses are dropped`() = runTest {
        val transport = FakeTransport()
        val channel = channel(transport)
        transport.onWrite = { bytes ->
            val id = CapCodec.requestIdOf(dev.hydrocap.app.proto.CapBleRequest.parseFrom(bytes))
            transport.respond(id + 100, uiStateBody) // wrong id → must be ignored
            transport.respond(id, uiStateBody)
        }
        val response = channel.request(RequestGetCapUiState.getDefaultInstance())
        assertEquals(1L, response.requestId)
        // A response arriving with no pending request must not crash anything.
        transport.respond(99, uiStateBody)
        assertTrue(log.entries.value.any { it.message.contains("unmatched response") })
        channel.close()
    }

    @Test
    fun `fails after three attempts with timeouts`() = runTest {
        val transport = FakeTransport()
        val channel = channel(transport)
        try {
            channel.request(RequestGetCapUiState.getDefaultInstance())
            fail("expected NusRequestException")
        } catch (e: NusRequestException) {
            assertTrue(e.message!!.contains("3 attempts"))
        }
        assertEquals(3, transport.writes.size)
        channel.close()
    }

    @Test
    fun `NOT_SUPPORTED surfaces as CapErrorResponse without retry`() = runTest {
        val transport = FakeTransport()
        val channel = channel(transport)
        transport.onWrite = { bytes ->
            val id = CapCodec.requestIdOf(dev.hydrocap.app.proto.CapBleRequest.parseFrom(bytes))
            transport.notifications.emit(Hex.decode("0d" + Hex.encode(byteArrayOf(id.toByte(), 0, 0, 0)) + "1002"))
        }
        try {
            channel.request(RequestGetCapUiState.getDefaultInstance())
            fail("expected CapErrorResponse")
        } catch (e: CapErrorResponse) {
            assertEquals(CapEnumResponseCode.NOT_SUPPORTED, e.response.code)
        }
        assertEquals(1, transport.writes.size)
        channel.close()
    }

    @Test
    fun `fragmented notifications are reassembled`() = runTest {
        val transport = FakeTransport()
        val channel = channel(transport)
        transport.onWrite = { bytes ->
            val id = CapCodec.requestIdOf(dev.hydrocap.app.proto.CapBleRequest.parseFrom(bytes))
            val full = CapBleResponse.newBuilder()
                .setRequestId(id.toInt())
                .setCode(CapEnumResponseCode.SUCCESS)
                .setBody(
                    com.google.protobuf.Any.newBuilder()
                        .setTypeUrl("type.googleapis.com/ResponseGetCapUiState")
                        .setValue(com.google.protobuf.ByteString.copyFrom(uiStateBody)),
                )
                .build()
                .toByteArray()
            // 20-byte ATT fragments as a stack without MTU negotiation would deliver them.
            full.toList().chunked(20).forEach { transport.notifications.emit(it.toByteArray()) }
        }
        val response = channel.request(RequestGetCapUiState.getDefaultInstance())
        assertTrue(response.body is ResponseGetCapUiState)
        assertTrue(log.entries.value.any { it.message.contains("reassembled") })
        channel.close()
    }

    @Test
    fun `only one request is outstanding at a time`() = runTest(StandardTestDispatcher()) {
        val transport = FakeTransport()
        val channel = channel(transport)
        var inFlight = 0
        var maxInFlight = 0
        transport.onWrite = { bytes ->
            inFlight++
            maxInFlight = maxOf(maxInFlight, inFlight)
            val id = CapCodec.requestIdOf(dev.hydrocap.app.proto.CapBleRequest.parseFrom(bytes))
            delay(50)
            inFlight--
            transport.respond(id, uiStateBody)
        }
        val a = async { channel.request(RequestGetCapUiState.getDefaultInstance()) }
        val b = async { channel.request(RequestGetCapUiState.getDefaultInstance()) }
        val c = async { channel.request(RequestGetCapUiState.getDefaultInstance()) }
        assertEquals(setOf(1L, 2L, 3L), setOf(a.await().requestId, b.await().requestId, c.await().requestId))
        assertEquals(1, maxInFlight)
        channel.close()
    }
}
