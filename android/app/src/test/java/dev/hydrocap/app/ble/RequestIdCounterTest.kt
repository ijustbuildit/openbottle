package dev.hydrocap.app.ble

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RequestIdCounterTest {

    @Test
    fun `starts at one and increases`() {
        val counter = RequestIdCounter()
        assertEquals(1L, counter.next())
        assertEquals(2L, counter.next())
        assertEquals(3L, counter.next())
    }

    @Test
    fun `wraps around fixed32 skipping zero`() {
        val counter = RequestIdCounter(start = 0xFFFF_FFFEL)
        assertEquals(0xFFFF_FFFFL, counter.next())
        assertEquals(1L, counter.next())
    }
}

// Synthetic identity: base62(0xFEDCBA9876543210), alphabet 0-9A-Za-z.
// Alternate: base62(0x0123456789ABCDEF), padded to 11 characters.
// The address is a synthetic locally administered test address.
class CapAdvertisementMatcherTest {

    @Test
    fun `matches a synthetic advertisement by name and manufacturer data`() {
        assertTrue(CapAdvertisementMatcher.matchesName("LARQ_LscmunaixMG"))
        // AD 0xff payload after the company id 0x0059: "CAP"
        assertTrue(CapAdvertisementMatcher.matchesManufacturerData(byteArrayOf(0x43, 0x41, 0x50)))
        assertTrue(CapAdvertisementMatcher.matchesManufacturerData("CAP123".toByteArray()))
        assertFalse(CapAdvertisementMatcher.matchesManufacturerData(byteArrayOf(0x43, 0x41)))
        assertFalse(CapAdvertisementMatcher.matchesManufacturerData(null))
        assertFalse(CapAdvertisementMatcher.matchesManufacturerData("DFU".toByteArray()))
    }

    @Test
    fun `paired cap is recognised by id or name never by address`() {
        val cap = DiscoveredCap("LARQ_LscmunaixMG", "02:00:00:00:00:01", -66, "FEDCBA9876543210", null, true, true, 0)
        assertTrue(cap.isSameCap("LARQ_LscmunaixMG", null))
        assertTrue(cap.isSameCap(null, "fedcba9876543210"))
        assertFalse(cap.isSameCap("LARQ_063UfDVRKBz", "0123456789ABCDEF"))
        assertFalse(cap.isSameCap(null, null))
    }
}
