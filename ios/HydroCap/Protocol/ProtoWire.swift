import Foundation

/// Minimal protobuf wire codec written by hand — no SwiftProtobuf.
///
/// Supported wire types, exactly what `android/app/src/main/proto/hydrocap.proto`
/// uses: varint (uint64 / int32 / bool / enum), fixed32 (and float through its
/// fixed32 bits) and length-delimited (string / bytes / nested messages /
/// repeated fields). Unknown fields are *skipped*, never rejected, which is what
/// proto3 requires and what the cap's extra fields need.
nonisolated enum ProtoWireType {
    static let varint = 0
    static let fixed64 = 1
    static let lengthDelimited = 2
    static let fixed32 = 5
}

nonisolated enum ProtoWireError: Error, Equatable, CustomStringConvertible {
    case truncated
    case varintTooLong
    case unsupportedWireType(Int)
    case invalidTag(UInt64)
    case invalidUTF8

    var description: String {
        switch self {
        case .truncated: "truncated message"
        case .varintTooLong: "varint longer than 10 bytes"
        case .unsupportedWireType(let wire): "unsupported wire type \(wire)"
        case .invalidTag(let tag): "invalid field tag \(tag)"
        case .invalidUTF8: "field is not valid UTF-8"
        }
    }
}

/// proto3 writer: scalar zero values are omitted, message fields are written
/// whenever the caller sets them (matching the vendor app's builder semantics,
/// which is what the golden vectors show).
nonisolated struct ProtoWriter {
    private(set) var data = Data()

    mutating func raw(_ bytes: Data) {
        data.append(bytes)
    }

    mutating func tag(_ field: Int, wire: Int) {
        varint(UInt64(field) << 3 | UInt64(wire))
    }

    mutating func varint(_ value: UInt64) {
        var v = value
        while true {
            let low = UInt8(v & 0x7f)
            v >>= 7
            if v == 0 {
                data.append(low)
                return
            }
            data.append(low | 0x80)
        }
    }

    mutating func fixed32(_ value: UInt32) {
        data.append(UInt8(value & 0xff))
        data.append(UInt8((value >> 8) & 0xff))
        data.append(UInt8((value >> 16) & 0xff))
        data.append(UInt8((value >> 24) & 0xff))
    }

    mutating func uint64(_ field: Int, _ value: UInt64) {
        guard value != 0 else { return }
        tag(field, wire: ProtoWireType.varint)
        varint(value)
    }

    mutating func int32(_ field: Int, _ value: Int32) {
        guard value != 0 else { return }
        tag(field, wire: ProtoWireType.varint)
        // proto3 encodes int32 through the standard varint path (negative values
        // sign-extend to 10 bytes); all our int32 fields are enums.
        varint(UInt64(bitPattern: Int64(value)))
    }

    mutating func uint32(_ field: Int, _ value: UInt32) {
        guard value != 0 else { return }
        tag(field, wire: ProtoWireType.varint)
        varint(UInt64(value))
    }

    mutating func bool(_ field: Int, _ value: Bool) {
        guard value else { return }
        tag(field, wire: ProtoWireType.varint)
        varint(1)
    }

    mutating func fixed32(_ field: Int, _ value: UInt32) {
        guard value != 0 else { return }
        tag(field, wire: ProtoWireType.fixed32)
        fixed32(value)
    }

    mutating func float(_ field: Int, _ value: Float) {
        guard value != 0 else { return }
        tag(field, wire: ProtoWireType.fixed32)
        fixed32(value.bitPattern)
    }

    mutating func string(_ field: Int, _ value: String) {
        guard !value.isEmpty else { return }
        let bytes = Data(value.utf8)
        tag(field, wire: ProtoWireType.lengthDelimited)
        varint(UInt64(bytes.count))
        raw(bytes)
    }

    mutating func bytes(_ field: Int, _ value: Data) {
        guard !value.isEmpty else { return }
        tag(field, wire: ProtoWireType.lengthDelimited)
        varint(UInt64(value.count))
        raw(value)
    }

    /// A nested message field: written whenever the caller provides one, even
    /// when it serialises to zero bytes (an explicitly set empty message).
    mutating func message(_ field: Int, _ body: Data) {
        tag(field, wire: ProtoWireType.lengthDelimited)
        varint(UInt64(body.count))
        raw(body)
    }
}

nonisolated struct ProtoReader {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    var isAtEnd: Bool { index >= bytes.count }

    /// Returns nil at the end of the message.
    mutating func nextTag() throws -> (field: Int, wire: Int)? {
        guard !isAtEnd else { return nil }
        let tag = try readVarint()
        let field = Int(tag >> 3)
        let wire = Int(tag & 0x07)
        guard field > 0 else { throw ProtoWireError.invalidTag(tag) }
        return (field, wire)
    }

    mutating func readVarint() throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while true {
            guard index < bytes.count else { throw ProtoWireError.truncated }
            let byte = bytes[index]
            index += 1
            guard shift < 64 else { throw ProtoWireError.varintTooLong }
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
    }

    mutating func readFixed32() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw ProtoWireError.truncated }
        var value: UInt32 = 0
        for offset in 0..<4 {
            value |= UInt32(bytes[index + offset]) << (8 * offset)
        }
        index += 4
        return value
    }

    mutating func readFloat() throws -> Float {
        Float(bitPattern: try readFixed32())
    }

    mutating func readBytes() throws -> Data {
        let length = Int(try readVarint())
        guard length >= 0, index + length <= bytes.count else { throw ProtoWireError.truncated }
        let slice = Data(bytes[index..<(index + length)])
        index += length
        return slice
    }

    mutating func readString() throws -> String {
        let data = try readBytes()
        guard let text = String(data: data, encoding: .utf8) else { throw ProtoWireError.invalidUTF8 }
        return text
    }

    mutating func readInt32() throws -> Int32 {
        Int32(truncatingIfNeeded: try readVarint())
    }

    mutating func readBool() throws -> Bool {
        try readVarint() != 0
    }

    mutating func readUInt32() throws -> UInt32 {
        UInt32(truncatingIfNeeded: try readVarint())
    }

    mutating func skip(wire: Int) throws {
        switch wire {
        case ProtoWireType.varint: _ = try readVarint()
        case ProtoWireType.fixed64:
            guard index + 8 <= bytes.count else { throw ProtoWireError.truncated }
            index += 8
        case ProtoWireType.lengthDelimited: _ = try readBytes()
        case ProtoWireType.fixed32: _ = try readFixed32()
        default: throw ProtoWireError.unsupportedWireType(wire)
        }
    }
}

/// A message the codec knows how to serialize and parse.
/// `protoName` is the unqualified name the `google.protobuf.Any` type URL uses.
nonisolated protocol ProtoMessage: Sendable, Equatable {
    static var protoName: String { get }
    func write(to writer: inout ProtoWriter)
    init(reading reader: inout ProtoReader) throws
    /// Compact one-line rendering for the debug log.
    var protoText: String { get }
}

nonisolated extension ProtoMessage {
    func protoEncoded() -> Data {
        var writer = ProtoWriter()
        write(to: &writer)
        return writer.data
    }

    init(protoDecodedFrom bytes: Data) throws {
        var reader = ProtoReader(bytes)
        try self.init(reading: &reader)
    }

    init(protoDecodedFrom bytes: Data, requireFullConsumption: Bool) throws {
        var reader = ProtoReader(bytes)
        try self.init(reading: &reader)
        guard !requireFullConsumption || reader.isAtEnd else { throw ProtoWireError.truncated }
    }
}
