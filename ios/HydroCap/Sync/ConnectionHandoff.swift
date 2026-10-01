import Foundation

/// Stable pairing identity, available after DIS; never persist a BLE address.
nonisolated struct ConnectedCapIdentity: Sendable, Equatable {
    let name: String
    let deviceIdHex: String

    init?(name: String?, advertisedId: String?, serial: String?) {
        let name = name.flatMap { $0.isEmpty ? nil : $0 }
        let id = advertisedId.flatMap { $0.isEmpty ? nil : $0 }
            ?? serial.flatMap { $0.isEmpty ? nil : $0 }
            ?? name
        guard let id else { return nil }
        self.name = name ?? id
        self.deviceIdHex = id
    }
}

/// Owns one initial connection + import, independent of the scan view's task.
/// Readiness is a milestone inside that same job, not a second connection.
@MainActor
final class ConnectionHandoff {
    typealias Ready = @MainActor (ConnectedCapIdentity) -> Void
    private var task: Task<Void, Never>?
    var isRunning: Bool { task != nil }

    func run(
        operation: @escaping @MainActor (@escaping Ready) async throws -> Void,
        onReady: @escaping Ready,
        onFailure: @escaping @MainActor (Error, Bool) -> Void,
        onFinished: @escaping @MainActor () async -> Void
    ) async {
        guard task == nil else { return }
        defer { task = nil }
        task = Task { @MainActor in
            var reachedReady = false
            do {
                try await operation { identity in
                    guard !reachedReady else { return }
                    reachedReady = true
                    onReady(identity)
                }
            } catch {
                onFailure(error, reachedReady)
            }
            await onFinished()
        }
        // Cancelling a view/caller does not cancel this app-owned task.
        await task?.value
    }
}
