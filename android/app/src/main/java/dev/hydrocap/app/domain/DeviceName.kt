package dev.hydrocap.app.domain

import java.math.BigInteger

/**
 * Cap advertising name → device id. Names are `LARQ_` + 11 base62 characters
 * (alphabet 0-9A-Za-z, big-endian); the decoded number, upper-case hex and
 * zero-padded to 16 digits, equals the Serial Number String (0x2A25).
 * Conversion is covered by generated synthetic base62/hex test fixtures.
 */
object DeviceName {
    const val PREFIX = "LARQ_"
    const val ID_LENGTH = 11
    private const val ALPHABET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    private val SIXTY_TWO = BigInteger.valueOf(62)

    /** True when [name] is a LARQ-family cap name (case-insensitive contains, as the vendor scanner does). */
    fun matches(name: String?): Boolean = name != null && name.contains("larq", ignoreCase = true)

    /** Decodes the 11-char suffix into a 16-hex-digit id, or null when the name has another shape. */
    fun decodeDeviceId(name: String?): String? {
        if (name == null || !name.startsWith(PREFIX)) return null
        val suffix = name.removePrefix(PREFIX)
        if (suffix.length != ID_LENGTH) return null
        var value = BigInteger.ZERO
        for (ch in suffix) {
            val digit = ALPHABET.indexOf(ch)
            if (digit < 0) return null
            value = value.multiply(SIXTY_TWO).add(BigInteger.valueOf(digit.toLong()))
        }
        return value.toString(16).uppercase().padStart(16, '0').takeLast(16)
    }
}
