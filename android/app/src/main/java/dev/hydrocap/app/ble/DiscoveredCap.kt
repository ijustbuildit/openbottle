package dev.hydrocap.app.ble

import dev.hydrocap.app.domain.DeviceName

/** One advertising cap as shown in the scan list. */
data class DiscoveredCap(
    val name: String?,
    val address: String,
    val rssi: Int,
    val deviceIdHex: String?,
    val rawAdvertisementHex: String?,
    val matchedByName: Boolean,
    val matchedByManufacturerData: Boolean,
    val seenAtMs: Long,
) {
    val displayName: String get() = name ?: "(no name)"

    /** Whether this result is the paired cap (matched by name or decoded serial, never by address). */
    fun isSameCap(pairedName: String?, pairedDeviceIdHex: String?): Boolean =
        (pairedDeviceIdHex != null && deviceIdHex != null && deviceIdHex.equals(pairedDeviceIdHex, ignoreCase = true)) ||
            (pairedName != null && name != null && name == pairedName)
}

/** Pure matching logic shared by the Android scanner and unit tests. */
object CapAdvertisementMatcher {

    fun matchesName(name: String?): Boolean = DeviceName.matches(name)

    fun matchesManufacturerData(manufacturerData: ByteArray?): Boolean {
        if (manufacturerData == null || manufacturerData.size < CapUuids.MANUFACTURER_PREFIX_CAP.size) return false
        for (i in CapUuids.MANUFACTURER_PREFIX_CAP.indices) {
            if (manufacturerData[i] != CapUuids.MANUFACTURER_PREFIX_CAP[i]) return false
        }
        return true
    }
}
