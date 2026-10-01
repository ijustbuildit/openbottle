import Foundation

/// A cap job failed for a reason the caller may show and retry later.
nonisolated struct SyncError: Error, Equatable, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}

/// Another cap job holds the link; the caller may retry later.
nonisolated struct CapBusyError: Error, Equatable, CustomStringConvertible {
    init() {}

    var description: String { "a cap job is already running" }
}

/// The (paired) cap did not advertise within the scan window — a normal
/// outcome when the bottle is out of range.
nonisolated struct CapNotFoundError: Error, Equatable, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}

/// A request/response failure on the NUS channel.
nonisolated struct NusRequestError: Error, Equatable, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}

/// The cap answered, but not with SUCCESS.
nonisolated struct CapErrorResponse: Error, Equatable, CustomStringConvertible {
    let response: DecodedResponse
    let requestTypeName: String

    var description: String { "\(requestTypeName) answered \(response.codeName) (id \(response.requestId))" }
}

/// BLE link failures (connect, discovery, CCCD, write).
nonisolated struct BleConnectionError: Error, Equatable, CustomStringConvertible {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var description: String { message }
}
