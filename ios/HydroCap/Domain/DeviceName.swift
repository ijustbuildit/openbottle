import Foundation

/// Cap advertising name → device id. Names are `LARQ_` + 11 base62 characters
/// (alphabet 0-9A-Za-z, big-endian); the decoded number, upper-case hex and
/// zero-padded to 16 digits, equals the Serial Number String (0x2A25).
/// Conversion is covered by generated synthetic base62/hex test fixtures.
///
/// The Kotlin port uses BigInteger and takes the last 16 hex digits; 62^11 is
/// larger than UInt64, so the wrap is reproduced explicitly with `&*`/`&+`
/// (modulo 2^64 == "last 16 hex digits").
nonisolated enum DeviceName {
    static let prefix = "LARQ_"
    static let idLength = 11
    private static let alphabet: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")

    /// True when `name` is a LARQ-family cap name (case-insensitive contains,
    /// as the vendor scanner does).
    static func matches(_ name: String?) -> Bool {
        name?.range(of: "larq", options: .caseInsensitive) != nil
    }

    /// Decodes the 11-char suffix into a 16-hex-digit id, or nil when the name
    /// has another shape.
    static func decodeDeviceId(_ name: String?) -> String? {
        guard let name, name.hasPrefix(prefix) else { return nil }
        let suffix = name.dropFirst(prefix.count)
        guard suffix.count == idLength else { return nil }
        var value: UInt64 = 0
        for character in suffix {
            guard let digit = alphabet.firstIndex(of: character) else { return nil }
            value = value &* 62 &+ UInt64(digit)
        }
        let hex = String(value, radix: 16, uppercase: true)
        return String(repeating: "0", count: max(0, 16 - hex.count)) + hex.suffix(16)
    }
}
