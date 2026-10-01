import Foundation

/// Hex helpers used by the codec, the debug log and the tests.
/// Port of `dev.hydrocap.app.protocol.Hex`.
nonisolated enum Hex {
    private static let digits: [Character] = Array("0123456789abcdef")

    static func encode(_ bytes: Data) -> String {
        var out = ""
        out.reserveCapacity(bytes.count * 2)
        for byte in bytes {
            out.append(digits[Int(byte >> 4)])
            out.append(digits[Int(byte & 0x0f)])
        }
        return out
    }

    static func decode(_ hex: String) throws -> Data {
        let clean = hex.filter { !$0.isWhitespace }
        guard clean.count % 2 == 0 else { throw HexError.oddLength(clean) }
        var out = Data()
        out.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { throw HexError.invalidDigit(clean) }
            out.append(byte)
            index = next
        }
        return out
    }
}

nonisolated enum HexError: Error, Equatable, CustomStringConvertible {
    case oddLength(String)
    case invalidDigit(String)

    var description: String {
        switch self {
        case .oddLength(let value): "hex string must have even length: '\(value)'"
        case .invalidDigit(let value): "invalid hex digit in '\(value)'"
        }
    }
}
