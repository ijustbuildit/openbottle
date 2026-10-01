import Foundation

/// Bounded reassembly for NUS TX notifications. On hardware (MTU 247) every
/// response arrived as one notification; this buffer only matters for stacks
/// that refuse the MTU and fragment at 20 bytes. Each notification is first
/// parsed alone; if that fails it is appended to the pending buffer and the
/// concatenation is tried. The buffer is capped at `maxBytes` and reset when
/// exceeded so a corrupt stream cannot wedge the channel.
nonisolated final class NotificationReassembler {
    static let maxBufferBytes = 256

    enum Outcome: Equatable {
        case complete(DecodedResponse, bytes: Data, fragments: Int)
        case buffered(pendingBytes: Int)
        case reset(droppedBytes: Int)
    }

    private var pending = Data()
    private let maxBytes: Int

    init(maxBytes: Int = NotificationReassembler.maxBufferBytes) {
        self.maxBytes = maxBytes
    }

    var pendingBytes: Int { pending.count }

    func offer(_ notification: Data) -> Outcome {
        if pending.isEmpty, let response = CapCodec.tryDecodeComplete(notification) {
            return .complete(response, bytes: notification, fragments: 1)
        }
        var combined = pending
        combined.append(notification)
        let fragments = pending.isEmpty ? 1 : 2
        if let response = CapCodec.tryDecodeComplete(combined) {
            pending = Data()
            return .complete(response, bytes: combined, fragments: fragments)
        }
        if combined.count > maxBytes {
            pending = Data()
            return .reset(droppedBytes: combined.count)
        }
        pending = combined
        return .buffered(pendingBytes: pending.count)
    }

    func reset() {
        pending = Data()
    }
}
