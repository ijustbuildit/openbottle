package dev.hydrocap.app.ble

import dev.hydrocap.app.protocol.CapCodec
import dev.hydrocap.app.protocol.DecodedResponse

/**
 * Bounded reassembly for NUS TX notifications. On hardware (MTU 247) every
 * response arrived as one notification; this buffer only matters for stacks
 * that refuse the MTU and fragment at 20 bytes. Each notification is first
 * parsed alone; if that fails it is appended to the pending buffer and the
 * concatenation is tried. The buffer is capped at [maxBytes] and reset when
 * exceeded so a corrupt stream cannot wedge the channel.
 */
class NotificationReassembler(private val maxBytes: Int = MAX_BUFFER_BYTES) {

    private var pending = ByteArray(0)

    val pendingBytes: Int get() = pending.size

    sealed class Outcome {
        data class Complete(val response: DecodedResponse, val bytes: ByteArray, val fragments: Int) : Outcome()
        data class Buffered(val pendingBytes: Int) : Outcome()
        data class Reset(val droppedBytes: Int) : Outcome()
    }

    fun offer(notification: ByteArray): Outcome {
        if (pending.isEmpty()) {
            CapCodec.tryDecodeComplete(notification)?.let { return Outcome.Complete(it, notification, 1) }
        }
        val combined = pending + notification
        val fragments = if (pending.isEmpty()) 1 else 2
        CapCodec.tryDecodeComplete(combined)?.let {
            pending = ByteArray(0)
            return Outcome.Complete(it, combined, fragments)
        }
        if (combined.size > maxBytes) {
            pending = ByteArray(0)
            return Outcome.Reset(combined.size)
        }
        pending = combined
        return Outcome.Buffered(pending.size)
    }

    fun reset() {
        pending = ByteArray(0)
    }

    companion object {
        const val MAX_BUFFER_BYTES = 256
    }
}
