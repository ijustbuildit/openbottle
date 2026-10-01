import Foundation
import UIKit

/// Wraps a cap job in `UIApplication.beginBackgroundTask` so a sync (or a
/// reminder write) survives the user leaving the app — the iOS equivalent of
/// the Android foreground service, with the same caveat: iOS grants a limited
/// amount of time and then expires the assertion.
@MainActor
final class BackgroundTaskGuard {
    nonisolated static let tag = "background"

    private let debugLog: DebugLog
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(debugLog: DebugLog) {
        self.debugLog = debugLog
    }

    var isActive: Bool { identifier != .invalid }

    func begin(name: String) {
        guard identifier == .invalid else { return }
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            Task { @MainActor in
                self?.debugLog.log(BackgroundTaskGuard.tag, "background time expired during '\(name)'")
                self?.end(name: name)
            }
        }
        debugLog.log(BackgroundTaskGuard.tag, "beginBackgroundTask '\(name)' id=\(identifier.rawValue)")
    }

    func end(name: String) {
        guard identifier != .invalid else { return }
        let ending = identifier
        identifier = .invalid
        UIApplication.shared.endBackgroundTask(ending)
        debugLog.log(BackgroundTaskGuard.tag, "endBackgroundTask '\(name)' id=\(ending.rawValue)")
    }

    /// Runs `body` inside a background assertion.
    func run<T>(name: String, _ body: () async throws -> T) async rethrows -> T {
        begin(name: name)
        defer { end(name: name) }
        return try await body()
    }
}
