import Foundation
import Testing

@testable import HydroCap

/// Fake link: records writes and lets the test inject notifications.
private final class FakeTransport: NusTransport, @unchecked Sendable {
    private let stream: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation
    private(set) var writes: [Data] = []
    /// Called from `write` (awaited on the channel's actor).
    var onWrite: (@Sendable (Data) async -> Void)?

    init() {
        (stream, continuation) = AsyncStream.makeStream(of: Data.self)
    }

    var notifications: AsyncStream<Data> { stream }

    func write(_ bytes: Data) async throws {
        writes.append(bytes)
        await onWrite?(bytes)
    }

    func respond(requestId: UInt32, body: Data? = nil, code: Int32 = CapResponseCode.success) {
        let envelope = CapBleResponse(
            requestId: requestId,
            code: code,
            body: body.map { AnyMessage(typeUrl: TypeUrls.of("ResponseGetCapUiState"), value: $0) },
        )
        continuation.yield(envelope.protoEncoded())
    }

    func emit(_ bytes: Data) {
        continuation.yield(bytes)
    }
}

@Suite("NUS channel")
struct NusChannelTest {

    private let uiStateBody = ResponseGetCapUiState(state: 8, powerSavingMode: 1).protoEncoded()

    /// Short timeout so the retry paths run in milliseconds instead of seconds
    /// (the Kotlin port used the coroutines test clock; a real Swift Testing run
    /// has no virtual clock for awaited work).
    private let fastTimeout = 0.05

    @Test func requestIsAnsweredWhenTheResponseIdMatches() async throws {
        let transport = FakeTransport()
        let log = DebugLog(directory: nil)
        let channel = await MainActor.run {
            NusChannel(transport: transport, debugLog: log, requestIds: RequestIdCounter(), timeoutSeconds: 4.0, maxRetries: 2)
        }
        transport.onWrite = { bytes in
            let request = try? CapBleRequest(protoDecodedFrom: bytes)
            transport.respond(requestId: request?.requestId ?? 0, body: self.uiStateBody)
        }
        let response = try await channel.request(RequestGetCapUiState())
        #expect(response.requestId == 1)
        #expect(response.body == .uiState(ResponseGetCapUiState(state: 8, powerSavingMode: 1)))
        #expect(transport.writes.count == 1)
        await MainActor.run { channel.close() }
    }

    @Test func idsIncreaseMonotonicallyAcrossRequestsAndRetries() async throws {
        let transport = FakeTransport()
        let ids = RequestIdCounter()
        let channel = await MainActor.run {
            NusChannel(transport: transport, debugLog: DebugLog(directory: nil), requestIds: ids, timeoutSeconds: fastTimeout, maxRetries: 2)
        }
        let calls = Counter()
        transport.onWrite = { bytes in
            let call = calls.increment()
            let request = try? CapBleRequest(protoDecodedFrom: bytes)
            if call >= 2 { transport.respond(requestId: request?.requestId ?? 0, body: self.uiStateBody) } // first attempt times out
        }
        let response = try await channel.request(RequestGetCapUiState())
        #expect(response.requestId == 2)
        let writtenIds = transport.writes.compactMap { (try? CapBleRequest(protoDecodedFrom: $0))?.requestId }
        #expect(writtenIds == [1, 2])

        async let next = channel.request(RequestGetCapUiState())
        let nextResponse = try await next
        #expect(nextResponse.requestId == 3)
        await MainActor.run { channel.close() }
    }

    @Test func unmatchedAndLateResponsesAreDropped() async throws {
        let transport = FakeTransport()
        let log = DebugLog(directory: nil)
        let channel = await MainActor.run {
            NusChannel(transport: transport, debugLog: log, requestIds: RequestIdCounter(), timeoutSeconds: 4.0, maxRetries: 2)
        }
        transport.onWrite = { bytes in
            let request = try? CapBleRequest(protoDecodedFrom: bytes)
            let id = request?.requestId ?? 0
            transport.respond(requestId: id + 100, body: self.uiStateBody) // wrong id → must be ignored
            transport.respond(requestId: id, body: self.uiStateBody)
        }
        let response = try await channel.request(RequestGetCapUiState())
        #expect(response.requestId == 1)
        // A response arriving with no pending request must not crash anything.
        transport.emit(CapBleResponse(requestId: 99, code: 1, body: AnyMessage(typeUrl: TypeUrls.of("ResponseGetCapUiState"), value: uiStateBody)).protoEncoded())
        #expect(await TestSupport.waitForLog(log, containing: "unmatched response"))
        await MainActor.run { channel.close() }
    }

    @Test func failsAfterThreeAttemptsWithTimeouts() async throws {
        let transport = FakeTransport()
        let channel = await MainActor.run {
            NusChannel(transport: transport, debugLog: DebugLog(directory: nil), requestIds: RequestIdCounter(), timeoutSeconds: fastTimeout, maxRetries: 2)
        }
        var message = ""
        do {
            _ = try await channel.request(RequestGetCapUiState())
        } catch let error as NusRequestError {
            message = error.message
        } catch {
            Issue.record("expected NusRequestError, got \(error)")
        }
        #expect(message.contains("3 attempts"))
        #expect(transport.writes.count == 3)
        await MainActor.run { channel.close() }
    }

    @Test func notSupportedSurfacesAsCapErrorResponseWithoutRetry() async throws {
        let transport = FakeTransport()
        let channel = await MainActor.run {
            NusChannel(transport: transport, debugLog: DebugLog(directory: nil), requestIds: RequestIdCounter(), timeoutSeconds: fastTimeout, maxRetries: 2)
        }
        transport.onWrite = { bytes in
            let id = (try? CapBleRequest(protoDecodedFrom: bytes))?.requestId ?? 0
            var bytes = Data([0x0d])
            bytes.append(contentsOf: [UInt8(id & 0xff), 0, 0, 0])
            bytes.append(contentsOf: [0x10, 0x02])
            transport.emit(bytes)
        }
        var caught: CapErrorResponse?
        do {
            _ = try await channel.request(RequestGetCapUiState())
        } catch let error as CapErrorResponse {
            caught = error
        }
        #expect(caught?.response.code == CapResponseCode.notSupported)
        #expect(caught?.requestTypeName == "RequestGetCapUiState")
        #expect(transport.writes.count == 1)
        await MainActor.run { channel.close() }
    }

    @Test func fragmentedNotificationsAreReassembled() async throws {
        let transport = FakeTransport()
        let log = DebugLog(directory: nil)
        let channel = await MainActor.run {
            NusChannel(transport: transport, debugLog: log, requestIds: RequestIdCounter(), timeoutSeconds: 4.0, maxRetries: 2)
        }
        transport.onWrite = { bytes in
            let id = (try? CapBleRequest(protoDecodedFrom: bytes))?.requestId ?? 0
            let full = CapBleResponse(
                requestId: id,
                code: 1,
                body: AnyMessage(typeUrl: TypeUrls.of("ResponseGetCapUiState"), value: self.uiStateBody),
            ).protoEncoded()
            // 20-byte ATT fragments as a stack without MTU negotiation would deliver them.
            for chunk in Array(full).chunked(into: 20) { transport.emit(Data(chunk)) }
        }
        let response = try await channel.request(RequestGetCapUiState())
        #expect(response.body == .uiState(ResponseGetCapUiState(state: 8, powerSavingMode: 1)))
        #expect(await TestSupport.waitForLog(log, containing: "reassembled"))
        await MainActor.run { channel.close() }
    }

    @Test func onlyOneRequestIsOutstandingAtATime() async throws {
        let transport = FakeTransport()
        let channel = await MainActor.run {
            NusChannel(transport: transport, debugLog: DebugLog(directory: nil), requestIds: RequestIdCounter(), timeoutSeconds: 4.0, maxRetries: 2)
        }
        let inFlight = Counter()
        let maxInFlight = Counter()
        transport.onWrite = { bytes in
            let current = inFlight.increment()
            _ = maxInFlight.record(candidate: current)
            let id = (try? CapBleRequest(protoDecodedFrom: bytes))?.requestId ?? 0
            try? await Task.sleep(nanoseconds: 50_000_000)
            _ = inFlight.decrement()
            transport.respond(requestId: id, body: self.uiStateBody)
        }
        async let a = channel.request(RequestGetCapUiState())
        async let b = channel.request(RequestGetCapUiState())
        async let c = channel.request(RequestGetCapUiState())
        let responses = try await [a, b, c]
        #expect(Set(responses.map(\.requestId)) == [1, 2, 3])
        #expect(maxInFlight.highWaterValue == 1)
        await MainActor.run { channel.close() }
    }
}

/// Tiny lock-protected counter for the async fakes.
nonisolated private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    private var highWater = 0

    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        stored += 1
        return stored
    }

    func decrement() -> Int {
        lock.lock()
        defer { lock.unlock() }
        stored -= 1
        return stored
    }

    func record(candidate: Int) -> Int {
        lock.lock()
        defer { lock.unlock() }
        highWater = Swift.max(highWater, candidate)
        return highWater
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    var highWaterValue: Int {
        lock.lock()
        defer { lock.unlock() }
        return highWater
    }
}
