package dev.hydrocap.app.ble

import java.util.concurrent.atomic.AtomicLong

/**
 * Monotonically increasing request id, one counter per app process
 * (fixed32 on the wire, so it wraps after 2^32-1 and skips 0 so that an
 * unset field is never mistaken for a real id).
 */
class RequestIdCounter(start: Long = 0) {
    private val counter = AtomicLong(start)

    fun next(): Long {
        while (true) {
            val current = counter.get()
            val next = if (current >= 0xFFFF_FFFFL) 1L else current + 1
            if (counter.compareAndSet(current, next)) return next
        }
    }

    val current: Long get() = counter.get()
}
