import Foundation

/// Pure decision logic for the background sync: whether a run should happen at
/// all, how a run's result maps to the platform verdict, and the "cap not seen"
/// streak. Free of CoreBluetooth/BackgroundTasks types so it is unit-testable;
/// the coordinators stay thin.
nonisolated enum BackgroundRunPolicy {

    /// After this many consecutive runs without the cap the app only logs — it
    /// never notifies.
    static let quietAfterMisses = 3

    enum SkipReason: String, Sendable, Equatable {
        case notPaired
        case disabled
        case permissionsMissing

        /// Log spelling matches the Kotlin port so the log lines are comparable.
        var label: String {
            switch self {
            case .notPaired: "NOT_PAIRED"
            case .disabled: "DISABLED"
            case .permissionsMissing: "PERMISSIONS_MISSING"
            }
        }
    }

    static func skipReason(hasPairedDevice: Bool, backgroundSyncEnabled: Bool, hasBLEPermissions: Bool) -> SkipReason? {
        if !hasPairedDevice { return .notPaired }
        if !backgroundSyncEnabled { return .disabled }
        if !hasBLEPermissions { return .permissionsMissing }
        return nil
    }

    enum Outcome: Sendable, Equatable {
        case synced(newTofEntries: Int, drinkEvents: Int, batteryPercent: Int?)
        case capNotFound
        case busy
        case failed(reason: String)

        /// Short persisted label (Debug screen "last background run").
        func label() -> String {
            switch self {
            case .synced(let newTofEntries, let drinkEvents, let batteryPercent):
                "synced: \(newTofEntries) new readings, \(drinkEvents) drinks, battery \(batteryPercent.map { "\($0) %" } ?? "n/a")"
            case .capNotFound: "cap not found"
            case .busy: "another cap job was running, retried"
            case .failed(let reason): "failed: \(reason)"
            }
        }
    }

    static func classify(_ error: Error) -> Outcome {
        if error is CapBusyError { return .busy }
        if error is CapNotFoundError { return .capNotFound }
        if let syncError = error as? SyncError { return .failed(reason: syncError.message) }
        if let nusError = error as? NusRequestError { return .failed(reason: nusError.message) }
        if let bleError = error as? BleConnectionError { return .failed(reason: bleError.message) }
        return .failed(reason: String(describing: type(of: error)))
    }

    enum Verdict: String, Sendable, Equatable {
        case success = "SUCCESS"
        case retry = "RETRY"
    }

    /// `consecutiveMisses` is the new streak to persist; `quiet` is true once
    /// the streak has reached `quietAfterMisses` (log only, no notification).
    struct Evaluation: Sendable, Equatable {
        let verdict: Verdict
        let consecutiveMisses: Int
        let quiet: Bool
    }

    static func evaluate(_ outcome: Outcome, previousMisses: Int) -> Evaluation {
        switch outcome {
        case .synced:
            return Evaluation(verdict: .success, consecutiveMisses: 0, quiet: false)
        case .failed:
            // The cap was reachable but something else went wrong: background
            // work must not accumulate backoff.
            return Evaluation(verdict: .success, consecutiveMisses: 0, quiet: false)
        case .busy:
            // Only a concurrent cap job justifies a retry (the engine refuses
            // to run two jobs at once).
            return Evaluation(verdict: .retry, consecutiveMisses: previousMisses, quiet: false)
        case .capNotFound:
            let misses = previousMisses + 1
            return Evaluation(verdict: .success, consecutiveMisses: misses, quiet: misses >= quietAfterMisses)
        }
    }
}
