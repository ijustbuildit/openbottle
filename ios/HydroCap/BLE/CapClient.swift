import Foundation

/// Typed API over one connected cap. Every method maps 1:1 to an allowlisted
/// command from docs/protocol/ble-protocol.md §4; setters return the bare
/// envelope because the cap answers them with SUCCESS and no body.
@MainActor
final class CapClient {
    let connection: CapConnection
    private let channel: NusChannel

    init(connection: CapConnection, debugLog: DebugLog, requestIds: RequestIdCounter) {
        self.connection = connection
        self.channel = NusChannel(transport: connection, debugLog: debugLog, requestIds: requestIds)
    }

    var connectionState: ConnectionState { connection.state }
    var deviceInformation: DeviceInformation? { connection.deviceInformation }
    var maximumWriteLength: Int { connection.maximumWriteLength }

    /// Must be the first request after subscribing: the cap clock drifts by
    /// weeks otherwise (hardware session 1: it was a month behind).
    func setTime(_ nowEpochMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) async throws -> DecodedResponse {
        try await channel.request(RequestSetCapTimeSettings(settings: CapTimeSettings(timeInMillisec: UInt64(max(0, nowEpochMs)))))
    }

    func getTime() async throws -> ResponseGetCapTimeSettings {
        try bodyAs(ResponseGetCapTimeSettings.self, try await channel.request(RequestGetCapTimeSettings())) { $0.timeSettings }
    }

    func getUiState() async throws -> ResponseGetCapUiState {
        try bodyAs(ResponseGetCapUiState.self, try await channel.request(RequestGetCapUiState())) { $0.uiState }
    }

    func getTofSettings() async throws -> ResponseGetCapTofSettings {
        try bodyAs(ResponseGetCapTofSettings.self, try await channel.request(RequestGetCapTofSettings())) { $0.tofSettings }
    }

    func getTofState() async throws -> ResponseGetCapTofState {
        try bodyAs(ResponseGetCapTofState.self, try await channel.request(RequestGetCapTofState())) { $0.tofState }
    }

    /// Entries with timestamp > `fromTimestampSec`, oldest first, at most `limit`.
    func getTofLog(fromTimestampSec: Int64, limit: Int) async throws -> ResponseGetCapTofLog {
        let response = try await channel.request(RequestGetCapTofLog(query: query(fromTimestampSec, limit)))
        return try bodyOrEmpty(ResponseGetCapTofLog.self, response) { $0.tofLog }
    }

    func getActivationLog(fromTimestampSec: Int64, limit: Int) async throws -> ResponseGetCapActivationLog {
        let response = try await channel.request(RequestGetCapActivationLog(query: query(fromTimestampSec, limit)))
        return try bodyOrEmpty(ResponseGetCapActivationLog.self, response) { $0.activationLog }
    }

    func getHydroReminder() async throws -> ResponseGetCapHydroReminderSettings {
        try bodyAs(ResponseGetCapHydroReminderSettings.self, try await channel.request(RequestGetCapHydroReminderSettings())) { $0.hydroReminder }
    }

    func setHydroReminder(_ settings: CapHydroReminderSettings) async throws -> DecodedResponse {
        try await channel.request(RequestSetCapHydroReminderSettings(settings: settings))
    }

    func getDnd() async throws -> ResponseGetCapDoNotDisturbSettings {
        try bodyAs(ResponseGetCapDoNotDisturbSettings.self, try await channel.request(RequestGetCapDoNotDisturbSettings())) { $0.dnd }
    }

    func setDnd(_ settings: CapDoNotDisturbSettings) async throws -> DecodedResponse {
        try await channel.request(RequestSetCapDoNotDisturbSettings(settings: settings))
    }

    func getLowBatterySettings() async throws -> ResponseGetCapLowBatterySettings {
        try bodyAs(ResponseGetCapLowBatterySettings.self, try await channel.request(RequestGetCapLowBatterySettings())) { $0.lowBattery }
    }

    /// Battery Level (0x2A19) via a GATT read, not NUS.
    func readBattery() async -> Int? {
        await connection.readBatteryLevel()
    }

    func close() {
        channel.close()
    }

    private func query(_ fromTimestampSec: Int64, _ limit: Int) -> CapLogQuery {
        CapLogQuery(
            fromTimestamp: UInt64(max(0, fromTimestampSec)),
            limit: UInt32(clamping: limit),
            algo: CapLogQuerySearchAlgo.timestamp,
        )
    }

    private func bodyAs<T>(
        _ type: T.Type,
        _ response: DecodedResponse,
        _ extract: (ProtoBody) -> T?,
    ) throws -> T {
        guard let body = response.body, let value = extract(body) else {
            throw NusRequestError("expected \(type) body but got \(response.typeName ?? "none") (id \(response.requestId))")
        }
        return value
    }

    /// Log queries: the cap answers a query that matches no entries with
    /// `SUCCESS` and **no body at all** (not an empty message). Treat that as
    /// an empty page; any other body type is an error.
    private func bodyOrEmpty<T>(
        _ type: T.Type,
        _ response: DecodedResponse,
        _ extract: (ProtoBody) -> T?,
    ) throws -> T where T: EmptyPageProviding {
        if response.hasNoBody { return T.emptyPage }
        return try bodyAs(type, response, extract)
    }
}

/// Response types that can answer a log query past the newest entry.
nonisolated protocol EmptyPageProviding {
    static var emptyPage: Self { get }
}

extension ResponseGetCapTofLog: EmptyPageProviding {
    static var emptyPage: ResponseGetCapTofLog { ResponseGetCapTofLog() }
}

extension ResponseGetCapActivationLog: EmptyPageProviding {
    static var emptyPage: ResponseGetCapActivationLog { ResponseGetCapActivationLog() }
}
