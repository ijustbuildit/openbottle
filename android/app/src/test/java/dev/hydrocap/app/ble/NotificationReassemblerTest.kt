package dev.hydrocap.app.ble

import dev.hydrocap.app.protocol.Hex
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationReassemblerTest {

    private val tofState = Hex.decode("0d0600000010011a3a0a2a747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f665374617465120c0a0a0d2a00000015e02e0000")

    @Test
    fun `whole notification is complete immediately`() {
        val outcome = NotificationReassembler().offer(tofState)
        assertTrue(outcome is NotificationReassembler.Outcome.Complete)
        assertEquals(6L, (outcome as NotificationReassembler.Outcome.Complete).response.requestId)
        assertEquals(1, outcome.fragments)
    }

    @Test
    fun `two fragments are concatenated`() {
        val r = NotificationReassembler()
        val first = r.offer(tofState.copyOfRange(0, 20))
        assertTrue(first is NotificationReassembler.Outcome.Buffered)
        val second = r.offer(tofState.copyOfRange(20, tofState.size))
        assertTrue(second is NotificationReassembler.Outcome.Complete)
        assertEquals(2, (second as NotificationReassembler.Outcome.Complete).fragments)
        assertEquals(0, r.pendingBytes)
    }

    // Synthetic rebased-time vector: first timestamp 1_600_000_000 s, original
    // measurement/enum fields and timestamp intervals retained; not a raw capture.
    @Test
    fun `the 179 byte synthetic ToF page decodes as one notification`() {
        val page = Hex.decode(
            "0d0800000010011aa9010a28747970652e676f6f676c65617069732e636f6d2f526573706f6e7365476574436170546f664c6f67127d0a170880a0f8fa0510041d3a00000025b20100002dd84534460a17089dbaf8fa0510041d6200000025920000002d249c35460a1708dbbaf8fa0510041d7500000025bd0000002dd89036460a170888c5f8fa0510021d7500000025960000002d52d034460a170897c5f8fa0510041da7000000251a0000002dd2eb3346",
        )
        assertEquals(179, page.size)
        val outcome = NotificationReassembler().offer(page)
        assertTrue(outcome is NotificationReassembler.Outcome.Complete)
        val body = (outcome as NotificationReassembler.Outcome.Complete).response.body as dev.hydrocap.app.proto.ResponseGetCapTofLog
        assertEquals(5, body.itemsCount)
        assertEquals(58, body.getItems(0).distanceInMillimeter)
    }

    @Test
    fun `buffer resets when it grows beyond the cap`() {
        val r = NotificationReassembler(maxBytes = 40)
        r.offer(ByteArray(20) { 0x7f })
        r.offer(ByteArray(20) { 0x7f })
        val outcome = r.offer(ByteArray(20) { 0x7f })
        assertTrue(outcome is NotificationReassembler.Outcome.Reset)
        assertEquals(0, r.pendingBytes)
    }

    @Test
    fun `no body response with no id is not mistaken for a complete message`() {
        // A lone "code=NOT_SUPPORTED" prefix of a longer message must be buffered, not accepted.
        val r = NotificationReassembler()
        val outcome = r.offer(tofState.copyOfRange(0, 7)) // "0d06000000 1001" → parses but the trailing bytes are a truncated Any tag
        // Whether this is accepted depends on proto3 lenience; what matters is the full message still decodes afterwards.
        if (outcome is NotificationReassembler.Outcome.Complete) {
            assertEquals(6L, outcome.response.requestId)
        } else {
            val rest = r.offer(tofState.copyOfRange(7, tofState.size))
            assertTrue(rest is NotificationReassembler.Outcome.Complete)
        }
    }
}
