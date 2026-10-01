import Foundation

/// Byte transport used by `NusChannel`; implemented by the CoreBluetooth
/// connection and by test fakes.
nonisolated protocol NusTransport: Sendable {
    /// Fragments (or whole responses) exactly as the stack delivered them.
    /// `AsyncStream` buffers, so a response that arrives before the collector
    /// starts is not lost.
    var notifications: AsyncStream<Data> { get }
    func write(_ bytes: Data) async throws
}

/// Request/response channel over NUS: one outstanding request at a time,
/// monotonically increasing ids, 4 s timeout, 2 retries (3 attempts total),
/// reassembly of fragmented notifications, and the command allowlist enforced
/// by `CapCodec` before anything reaches the transport. Unmatched or late
/// responses are logged and dropped.
@MainActor
final class NusChannel {
    nonisolated static let tag = "nus"
    nonisolated static let requestTimeoutSeconds: Double = 4.0
    nonisolated static let maxRetriesDefault = 2

    private let transport: NusTransport
    private let debugLog: DebugLog
    private let requestIds: RequestIdCounter
    private let timeoutSeconds: Double
    private let maxRetries: Int
    private let reassembler = NotificationReassembler()

    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var pendingId: UInt32?
    private var pendingContinuation: AsyncStream<DecodedResponse>.Continuation?
    private var collector: Task<Void, Never>?

    init(
        transport: NusTransport,
        debugLog: DebugLog,
        requestIds: RequestIdCounter,
        timeoutSeconds: Double = NusChannel.requestTimeoutSeconds,
        maxRetries: Int = NusChannel.maxRetriesDefault,
    ) {
        self.transport = transport
        self.debugLog = debugLog
        self.requestIds = requestIds
        self.timeoutSeconds = timeoutSeconds
        self.maxRetries = maxRetries
        self.collector = Task { @MainActor [weak self] in
            let notifications = transport.notifications
            for await bytes in notifications {
                self?.onNotification(bytes)
            }
        }
    }

    /// Sends `body` and returns the decoded response. Throws `NusRequestError`
    /// after all attempts time out and `CapErrorResponse` when the cap answers
    /// with FAIL/NOT_SUPPORTED (no retry for those — the cap did answer).
    func request<Body: ProtoMessage>(_ body: Body) async throws -> DecodedResponse {
        await acquire()
        defer { release() }

        let typeName = Body.protoName
        var lastError: Error?
        for attempt in 1...(maxRetries + 1) {
            let id = requestIds.next()
            // The allowlist is enforced here, before anything reaches the transport.
            let bytes = try CapCodec.encodeRequest(requestId: id, body: body)
            let (stream, continuation) = AsyncStream.makeStream(of: DecodedResponse.self, bufferingPolicy: .bufferingNewest(1))
            pendingId = id
            pendingContinuation = continuation
            debugLog.log(
                Self.tag,
                "TX id=\(id) \(typeName) attempt=\(attempt) len=\(bytes.count) hex=\(Hex.encode(bytes)) \(CapCodec.describeRequest(body))",
            )
            do {
                try await transport.write(bytes)
                let timeoutTask = Task { [timeoutSeconds] in
                    if (try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))) != nil {
                        continuation.finish()
                    }
                }
                var iterator = stream.makeAsyncIterator()
                let response = await iterator.next()
                timeoutTask.cancel()
                continuation.finish()
                if let response {
                    clearPending()
                    debugLog.log(Self.tag, "RX \(response.describe())")
                    if !response.isSuccess {
                        throw CapErrorResponse(response: response, requestTypeName: typeName)
                    }
                    return response
                }
                clearPending()
                debugLog.log(
                    Self.tag,
                    "timeout id=\(id) \(typeName) after \(Int(timeoutSeconds * 1000)) ms (attempt \(attempt)/\(maxRetries + 1))",
                )
                lastError = NusRequestError("\(typeName) timed out (id \(id))")
            } catch let error as CapErrorResponse {
                clearPending()
                throw error
            } catch let error as BleConnectionError {
                clearPending()
                debugLog.log(Self.tag, "write failed id=\(id) \(typeName): \(error.message)")
                lastError = error
                if !isRetryable(error) { break }
            } catch {
                clearPending()
                lastError = error
            }
        }
        let detail = lastError.map { "\($0)" } ?? "unknown error"
        throw NusRequestError("\(typeName) failed after \(maxRetries + 1) attempts: \(detail)")
    }

    func close() {
        collector?.cancel()
        collector = nil
        reassembler.reset()
        clearPending()
    }

    var pendingRequestId: UInt32? { pendingId }

    private func clearPending() {
        pendingId = nil
        pendingContinuation = nil
    }

    private func isRetryable(_ error: BleConnectionError) -> Bool {
        !error.message.contains("not connected")
    }

    private func onNotification(_ bytes: Data) {
        switch reassembler.offer(bytes) {
        case .complete(let response, let data, let fragments):
            if fragments > 1 {
                debugLog.log(Self.tag, "reassembled \(fragments) notifications into \(data.count) bytes")
            }
            deliver(response)
        case .buffered(let pendingBytes):
            debugLog.log(Self.tag, "notification (\(bytes.count) B) is not a complete response, buffering (\(pendingBytes) B pending)")
        case .reset(let droppedBytes):
            debugLog.log(Self.tag, "reassembly buffer exceeded \(NotificationReassembler.maxBufferBytes) B, dropped \(droppedBytes) B")
        }
    }

    private func deliver(_ response: DecodedResponse) {
        let expected = pendingId.map { String($0) } ?? "nil"
        guard let continuation = pendingContinuation, let pendingId, response.requestId == pendingId else {
            debugLog.log(Self.tag, "unmatched response \(response.describe()) (expected id=\(expected)), dropped")
            return
        }
        if case .terminated = continuation.yield(response) {
            debugLog.log(Self.tag, "duplicate response for id=\(response.requestId), dropped")
        }
    }

    // MARK: - Single outstanding request (FIFO, like `Mutex.withLock`)

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            busy = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}
