package dev.hydrocap.app.domain

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// Synthetic IDs: integers 0x0123456789ABCDEF and 0xFEDCBA9876543210,
// encoded with alphabet 0-9A-Za-z and left-padded to 11 base62 digits.
class DeviceNameTest {

    @Test
    fun `decodes a synthetic leading zero example`() {
        assertEquals("0123456789ABCDEF", DeviceName.decodeDeviceId("LARQ_063UfDVRKBz"))
    }

    @Test
    fun `decodes a synthetic unsigned upper half serial number`() {
        assertEquals("FEDCBA9876543210", DeviceName.decodeDeviceId("LARQ_LscmunaixMG"))
    }

    @Test
    fun `rejects names of another shape`() {
        assertNull(DeviceName.decodeDeviceId(null))
        assertNull(DeviceName.decodeDeviceId("CapDFU"))
        assertNull(DeviceName.decodeDeviceId("LARQ_short"))
        assertNull(DeviceName.decodeDeviceId("LARQ_063UfDVRKB!"))
    }

    @Test
    fun `matcher is a case-insensitive contains`() {
        assertTrue(DeviceName.matches("LARQ_LscmunaixMG"))
        assertTrue(DeviceName.matches("my larq cap"))
        assertFalse(DeviceName.matches("CapDFU"))
        assertFalse(DeviceName.matches(null))
    }
}
