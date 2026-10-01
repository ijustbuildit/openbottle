import Foundation
import Testing

@testable import HydroCap

/// Shared helpers for the pure-logic tests.
enum TestSupport {
    /// Polls a debug log until a line containing `text` shows up. Log lines are
    /// produced asynchronously (the channel's collector task, the gateway
    /// tasks), so tests must wait instead of asserting immediately.
    static func waitForLog(_ log: DebugLog, containing text: String, timeout: Double = 2.0) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if log.entries().contains(where: { $0.message.contains(text) }) { return true }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
        return log.entries().contains(where: { $0.message.contains(text) })
    }

    static func logMessageCount(_ log: DebugLog, containing text: String) -> Int {
        log.entries().filter { $0.message.contains(text) }.count
    }
}
