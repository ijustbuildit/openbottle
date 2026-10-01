import Foundation

/// Summary of one sync, shown on the Home status line and in the debug log.
nonisolated struct SyncSummary: Sendable, Equatable {
    var deviceName: String
    var batteryPercent: Int?
    var newTofEntries: Int
    var newActivationEntries: Int
    var drinkEvents: Int
    var capBottleSizeMl: Int?
    var capReportedUiState: String?
    var durationMs: Int64

    var label: String {
        "\(deviceName): \(newTofEntries) new readings, \(drinkEvents) drinks" +
            (batteryPercent.map { ", battery \($0) %" } ?? "")
    }
}

/// The full sync sequence from the brief, adjusted for hardware session 1:
///
/// scan (filter 0x180A, match by name/serial — the cap rotates its address) →
/// connect → notify/DIS → **setTime first** → getUiState → getTofSettings →
/// battery read → ToF log pages (from = max stored timestamp, limit 5, until a
/// short page or 500 pages) → activation log pages → TofAlgorithm over the
/// whole stored log → upsert DrinkEvents → HealthKit writer → disconnect.
///
/// Only one cap job runs at a time. Each job builds its own `CapConnection` and
/// `CapClient` so a failed link never leaks into the next attempt, and the job
/// is wrapped in a `UIApplication` background assertion so it survives the user
/// leaving the app.
@MainActor
@Observable
final class SyncEngine {
    nonisolated static let tag = "sync"
    nonisolated static let pageLimit = 5
    /// Hardware session 1: the log holds months of history, so allow up to
    /// 500 pages × 5 entries.
    nonisolated static let maxPages = 500

    enum Status: Equatable, Sendable {
        case idle
        case running(step: String)
        case done(SyncSummary, finishedAtMs: Int64)
        case failed(reason: String, finishedAtMs: Int64)

        var label: String {
            switch self {
            case .idle: "idle"
            case .running(let step): "syncing: \(step)"
            case .done(let summary, _): summary.label
            case .failed(let reason, _): "failed: \(reason)"
            }
        }

        var isRunning: Bool {
            if case .running = self { return true }
            return false
        }
    }

    /// State of the Reminder screen's cap round trip (read on open, write +
    /// re-read on Apply).
    enum ReminderStatus: Equatable, Sendable {
        case idle
        case busy(step: String, applying: Bool)
        /// `applied` is true when the values are the re-read result of a write.
        case loaded(CapReminderConfig, atMs: Int64, applied: Bool)
        case failed(reason: String, atMs: Int64, lastKnown: CapReminderConfig?, applying: Bool)
    }

    private let central: CapCentral
    private let scanner: BleScanner
    private let store: any HydroCapStore
    private let settings: SettingsStore
    private let drinkEventBuilder: DrinkEventBuilder
    private let healthWriter: HealthKitHydrationWriter
    private let batteryNotifier: BatteryNotifier
    private let requestIds: RequestIdCounter
    private let debugLog: DebugLog
    private let backgroundGuard: BackgroundTaskGuard
    /// Invoked after a sync paired a cap that was not paired before (wired by
    /// `AppContainer` so the background trigger can reconcile).
    var onPaired: () -> Void = {}
    /// Invoked after every completed sync (foreground or background) so the
    /// drink reminders can be re-planned with today's intake. Awaited inside
    /// the job so a background run finishes the re-plan before iOS may
    /// suspend the app.
    var onSynced: () async -> Void = {}
    /// Invoked after the ring hours were read from the cap (reminder window).
    var onRingHoursRead: () -> Void = {}

    private(set) var status: Status = .idle
    private(set) var reminder: ReminderStatus = .idle
    private(set) var activeClient: CapClient?
    private var running = false
    /// Reserve the initial connection before its app-owned task is scheduled.
    /// Background refresh must not win that scheduling gap.
    var backgroundSyncSuspended = false

    init(
        central: CapCentral,
        scanner: BleScanner,
        store: any HydroCapStore,
        settings: SettingsStore,
        drinkEventBuilder: DrinkEventBuilder,
        healthWriter: HealthKitHydrationWriter,
        batteryNotifier: BatteryNotifier,
        requestIds: RequestIdCounter,
        debugLog: DebugLog,
        backgroundGuard: BackgroundTaskGuard,
    ) {
        self.central = central
        self.scanner = scanner
        self.store = store
        self.settings = settings
        self.drinkEventBuilder = drinkEventBuilder
        self.healthWriter = healthWriter
        self.batteryNotifier = batteryNotifier
        self.requestIds = requestIds
        self.debugLog = debugLog
        self.backgroundGuard = backgroundGuard
    }

    var isRunning: Bool { running }

    // MARK: - Jobs

    /// Runs a full sync. `target` preselects a cap from a scan list; otherwise
    /// the paired cap (by name/serial) is searched, or — if nothing is paired —
    /// the first cap that advertises.
    @discardableResult
    func sync(
        target: DiscoveredCap? = nil,
        allowReconnectRetry: Bool = true,
        onConnectionReady: ConnectionHandoff.Ready? = nil
    ) async throws -> SyncSummary {
        try await exclusive("sync", allowReconnectRetry: allowReconnectRetry) { startedAt in
            let summary = try await runSync(target: target, startedAt: startedAt, allowReconnectRetry: allowReconnectRetry, onConnectionReady: onConnectionReady)
            status = .done(summary, finishedAtMs: Self.nowMs())
            return summary
        }
    }

    /// Connects and performs a single live ToF measurement (Debug "Live ToF").
    @discardableResult
    func liveTof(target: DiscoveredCap? = nil) async throws -> (distanceMm: Int, kcps: Int) {
        let result = try await exclusive("live ToF") { _ in
            try await withConnectedCap(target: target, purpose: "live ToF") { client, _ in
                _ = try await client.setTime()
                let state = try await client.getTofState().state
                let distance = state.map { Int($0.distanceInMillimeter) } ?? 0
                let kcps = state.map { Int($0.kcps) } ?? 0
                debugLog.log(Self.tag, "live ToF distance=\(distance) mm kcps=\(kcps)")
                return (distance, kcps)
            }
        }
        status = .idle
        return result
    }

    /// Reads every GET-able setting and logs it (Debug "Read all settings").
    func readAllSettings(target: DiscoveredCap? = nil) async throws -> [String] {
        let lines = try await exclusive("read all settings") { _ in
            try await withConnectedCap(target: target, purpose: "read all settings") { client, _ in
                _ = try await client.setTime()
                var lines: [String] = []
                func add(_ label: String, _ value: String) {
                    let line = "\(label): \(value)"
                    debugLog.log(Self.tag, line)
                    lines.append(line)
                }
                add("time", (try await client.getTime()).settings.map { "\($0.timeInMillisec) ms" } ?? "n/a")
                add("uiState", (try await client.getUiState()).protoText)
                add("tofSettings", (try await client.getTofSettings()).settings?.protoText ?? "n/a")
                add("hydroReminder", (try await client.getHydroReminder()).settings?.protoText ?? "n/a")
                add("dnd", (try await client.getDnd()).settings?.protoText ?? "n/a")
                add("lowBattery", (try await client.getLowBatterySettings()).settings?.protoText ?? "n/a")
                add("battery", await client.readBattery().map { "\($0) %" } ?? "n/a")
                return lines
            }
        }
        status = .idle
        return lines
    }

    /// Reads reminder + quiet hours (Reminder screen on open).
    @discardableResult
    func readReminder(target: DiscoveredCap? = nil) async throws -> CapReminderConfig {
        try await reminderJob("read reminder", applying: false) {
            try await withConnectedCap(target: target, purpose: "read reminder") { client, _ in
                _ = try await client.setTime()
                return try await readReminderConfig(client)
            }
        }
    }

    /// Writes the reminder and/or quiet hours: connect → setTime → read the
    /// current values → merge `patch` → validate → `SetCapHydroReminderSettings`
    /// → `SetCapDoNotDisturbSettings` (each must answer SUCCESS; FAIL /
    /// NOT_SUPPORTED aborts with the code) → re-read both. The returned config
    /// is what the cap actually stored.
    @discardableResult
    func applyReminder(_ patch: ReminderPatch, target: DiscoveredCap? = nil) async throws -> CapReminderConfig {
        try await reminderJob("apply reminder", applying: true) {
            guard !patch.isEmpty else { throw SyncError("nothing to write") }
            return try await withConnectedCap(target: target, purpose: "apply reminder") { client, _ in
                _ = try await client.setTime()
                reminderStep("reading current values", applying: true)
                let current = try await readReminderConfig(client)
                let resolved: CapReminderConfig
                do {
                    resolved = try ReminderRules.validateOrThrow(ReminderRules.resolve(current: current, patch: patch))
                } catch {
                    throw SyncError("invalid reminder settings: \(error)")
                }
                debugLog.log(Self.tag, "writing \(ReminderMapping.describe(resolved))")
                if patch.reminder != nil {
                    reminderStep("writing reminder", applying: true)
                    let response = try await client.setHydroReminder(ReminderMapping.toProto(resolved.reminder))
                    debugLog.log(Self.tag, "SetCapHydroReminderSettings → \(response.codeName)")
                }
                if patch.dnd != nil {
                    reminderStep("writing quiet hours", applying: true)
                    let response = try await client.setDnd(ReminderMapping.toProto(resolved.dnd))
                    debugLog.log(Self.tag, "SetCapDoNotDisturbSettings → \(response.codeName)")
                }
                reminderStep("reading back", applying: true)
                return try await readReminderConfig(client)
            }
        }
    }

    /// One background attempt with a time budget: scan (no duplicates), sync,
    /// and map every failure to a policy outcome. Cap not found is a normal
    /// outcome, not an error.
    func runBackgroundAttempt(budgetSeconds: Double, allowReconnectRetry: Bool) async -> BackgroundRunPolicy.Outcome {
        guard !backgroundSyncSuspended else { return .busy }
        do {
            let summary = try await sync(target: nil, allowReconnectRetry: allowReconnectRetry)
            return .synced(
                newTofEntries: summary.newTofEntries,
                drinkEvents: summary.drinkEvents,
                batteryPercent: summary.batteryPercent,
            )
        } catch let error as CapNotFoundError {
            debugLog.log(Self.tag, "background attempt: \(error.message)")
            return .capNotFound
        } catch {
            return BackgroundRunPolicy.classify(error)
        }
    }

    // MARK: - Internals

    private func readReminderConfig(_ client: CapClient) async throws -> CapReminderConfig {
        let reminder = ReminderMapping.fromProto(try await client.getHydroReminder().settings ?? CapHydroReminderSettings())
        let dnd = ReminderMapping.fromProto(try await client.getDnd().settings ?? CapDoNotDisturbSettings())
        let config = CapReminderConfig(reminder: reminder, dnd: dnd)
        debugLog.log(Self.tag, "cap holds \(ReminderMapping.describe(config))")
        // The ring hours double as the drink-reminder window (Settings →
        // Reminders); remembered from every read so the planner uses what
        // the cap actually holds.
        settings.setLastRingHours(startSec: reminder.startSec, stopSec: reminder.stopSec)
        onRingHoursRead()
        return config
    }

    private func reminderJob(_ purpose: String, applying: Bool, _ block: () async throws -> CapReminderConfig) async throws -> CapReminderConfig {
        let lastKnown: CapReminderConfig? = switch reminder {
        case .loaded(let config, _, _): config
        case .failed(_, _, let known, _): known
        default: nil
        }
        do {
            return try await exclusive(purpose) { _ in
                reminder = .busy(step: "scanning", applying: applying)
                let config = try await block()
                reminder = .loaded(config, atMs: Self.nowMs(), applied: applying)
                status = .idle
                return config
            }
        } catch {
            // Covers failures inside the job and the "already running" refusal.
            reminder = .failed(
                reason: "\(error)",
                atMs: Self.nowMs(),
                lastKnown: lastKnown,
                applying: applying,
            )
            throw error
        }
    }

    private func reminderStep(_ step: String, applying: Bool) {
        reminder = .busy(step: step, applying: applying)
        debugLog.log(Self.tag, "step: \(step)")
    }

    /// One cap job at a time; converts every failure into `Status.failed` and
    /// a `SyncError`/`CapBusyError` the caller can act on.
    private func exclusive<T>(_ purpose: String, allowReconnectRetry: Bool = true, _ block: (Int64) async throws -> T) async throws -> T {
        guard !running else { throw CapBusyError() }
        running = true
        let startedAt = Self.nowMs()
        defer {
            running = false
            activeClient = nil
        }
        do {
            return try await backgroundGuard.run(name: purpose) {
                try await block(startedAt)
            }
        } catch {
            if error is CapBusyError { throw error }
            let reason = "\(error)"
            debugLog.error(Self.tag, "\(purpose) failed", error: error)
            status = .failed(reason: reason, finishedAtMs: Self.nowMs())
            throw error as? SyncError ?? SyncError(reason)
        }
    }

    private func runSync(
        target: DiscoveredCap?, startedAt: Int64, allowReconnectRetry: Bool,
        onConnectionReady: ConnectionHandoff.Ready?
    ) async throws -> SyncSummary {
        try await withConnectedCap(target: target, purpose: "sync", allowReconnectRetry: allowReconnectRetry) { client, cap in
            // withConnectedCap has completed notifications + DIS. Notify the
            // UI synchronously before any protocol request or log import.
            if let onConnectionReady {
                try Task.checkCancellation()
                guard client.connection.isReady,
                      let identity = ConnectedCapIdentity(name: cap.name, advertisedId: cap.deviceIdHex, serial: client.deviceInformation?.serial) else {
                    throw SyncError("cap is not ready with a stable identity")
                }
                onConnectionReady(identity)
            }
            let current = settings.current

            step("set time")
            _ = try await client.setTime()

            step("read ui state")
            let uiState = try await client.getUiState()
            debugLog.log(Self.tag, "ui state=\(CapUiState.name(uiState.state)) (\(uiState.state)) powerSaving=\(CapPowerSavingMode.name(uiState.powerSavingMode))")

            step("read ToF settings")
            let tofSettings = try await client.getTofSettings().settings
            let capBottleSize = tofSettings.map { Int($0.bottleSizeInMilliliter) } ?? 0
            debugLog.log(
                Self.tag,
                "tof settings mode=\(CapTofMode.name(tofSettings?.mode ?? 0)) interval=\(tofSettings?.triggerIntervalInSec ?? 0)s bottleSize=\(capBottleSize) ml",
            )
            settings.setLastCapBottleSize(capBottleSize)
            let matchingProfile = BottleProfile.forCapReportedSize(capBottleSize)
            if matchingProfile == nil {
                debugLog.log(Self.tag, "WARN cap reports bottle size \(capBottleSize) ml which matches no built-in profile")
            } else if matchingProfile?.id != current.bottleProfileId {
                debugLog.log(
                    Self.tag,
                    "cap reports \(capBottleSize) ml but profile stays '\(current.bottleProfileId)' (cap value is informational, see hw-session-1)",
                )
            }

            step("read battery")
            let battery = await client.readBattery()
            if let battery {
                try await store.insertBatterySample(BatterySample(timestamp: Self.nowMs() / 1000, percent: battery))
                await batteryNotifier.onBatteryLevel(battery)
            }

            step("pull ToF log")
            let newTof = try await pullTofLog(client)

            step("pull activation log")
            let newActivation = try await pullActivationLog(client)

            if current.drinkRemindersEnabled {
                step("read ring hours")
                do {
                    _ = try await readReminderConfig(client)
                } catch {
                    // Keep the last successfully read hours. If there are none,
                    // the scheduler suppresses reminders rather than inventing a window.
                    debugLog.error(Self.tag, "could not refresh ring hours", error: error)
                }
            }

            step("compute drinks")
            let drinkEvents = try await drinkEventBuilder.rebuild(profile: current.bottleProfile())

            step("apple health")
            if current.healthSyncEnabled {
                let result = await healthWriter.upsert(events: drinkEvents)
                debugLog.log(Self.tag, "apple health inserted=\(result.inserted) updated=\(result.updated) skipped=\(result.skipped) error=\(result.error ?? "none")")
            } else {
                debugLog.log(Self.tag, "health sync disabled, skipping Apple Health")
            }

            let info = client.deviceInformation
            let deviceId = cap.deviceIdHex ?? info?.serial ?? cap.name ?? cap.address
            try await store.upsertDevice(DeviceRecord(
                deviceIdHex: deviceId,
                name: cap.name ?? "",
                lastAddress: cap.address,
                bottleSizeMl: capBottleSize,
                manufacturer: info?.manufacturer,
                model: info?.model,
                serial: info?.serial,
                firmwareRevision: info?.firmwareRevision,
                hardwareRevision: info?.hardwareRevision,
                softwareRevision: info?.softwareRevision,
                lastSeenMs: Self.nowMs(),
            ))
            if let name = cap.name, !current.hasPairedDevice {
                settings.setPairedDevice(name: name, deviceIdHex: deviceId)
                debugLog.log(Self.tag, "paired with \(name) (id \(deviceId))")
                onPaired()
            }
            let finishedAt = Self.nowMs()
            settings.setLastSync(finishedAt)
            let summary = SyncSummary(
                deviceName: cap.name ?? cap.address,
                batteryPercent: battery,
                newTofEntries: newTof,
                newActivationEntries: newActivation,
                drinkEvents: drinkEvents.count,
                capBottleSizeMl: capBottleSize,
                capReportedUiState: CapUiState.name(uiState.state),
                durationMs: finishedAt - startedAt,
            )
            debugLog.log(Self.tag, "sync done \(summary.label) in \(summary.durationMs) ms")
            await onSynced()
            return summary
        }
    }

    private func pullTofLog(_ client: CapClient) async throws -> Int {
        var from = try await store.tofLogMaxTimestamp() ?? 0
        var inserted = 0
        var pages = 0
        while pages < Self.maxPages {
            let page = try await client.getTofLog(fromTimestampSec: from, limit: Self.pageLimit).items
            pages += 1
            if page.isEmpty { break }
            let entries = page.map {
                TofLogEntry(
                    timestamp: Int64($0.timestamp),
                    triggerType: $0.triggerType,
                    distanceMm: Int($0.distanceInMillimeter),
                    kcps: Int($0.kcps),
                    uvLedTempOhm: $0.uvLedTempInOhm,
                )
            }
            inserted += try await store.insertTofLog(entries)
            guard let last = entries.map(\.timestamp).max() else { break }
            if last <= from {
                debugLog.log(Self.tag, "ToF log page did not advance (from=\(from) last=\(last)), stopping")
                break
            }
            from = last
            if page.count < Self.pageLimit { break }
            if pages % 10 == 0 {
                status = .running(step: "pull ToF log (page \(pages), \(inserted) new)")
            }
        }
        debugLog.log(Self.tag, "ToF log: \(pages) page(s), \(inserted) new entr\(inserted == 1 ? "y" : "ies"), newest ts=\(from)")
        if pages >= Self.maxPages { debugLog.log(Self.tag, "WARN ToF log paging stopped at the \(Self.maxPages) page cap") }
        return inserted
    }

    private func pullActivationLog(_ client: CapClient) async throws -> Int {
        var from = try await store.activationLogMaxTimestamp() ?? 0
        var inserted = 0
        var pages = 0
        while pages < Self.maxPages {
            let page = try await client.getActivationLog(fromTimestampSec: from, limit: Self.pageLimit).items
            pages += 1
            if page.isEmpty { break }
            let entries = page.map { ActivationLogEntry(timestamp: Int64($0.timestamp), mode: $0.mode, batterySocPercent: Int($0.batterySocInPercentage)) }
            inserted += try await store.insertActivationLog(entries)
            guard let last = entries.map(\.timestamp).max() else { break }
            if last <= from { break }
            from = last
            if page.count < Self.pageLimit { break }
        }
        debugLog.log(Self.tag, "activation log: \(pages) page(s), \(inserted) new entr\(inserted == 1 ? "y" : "ies"), newest ts=\(from)")
        return inserted
    }

    /// Scan → connect → block → disconnect, with the client exposed for the UI
    /// while connected.
    private func withConnectedCap<T>(
        target: DiscoveredCap?,
        purpose: String,
        allowReconnectRetry: Bool = true,
        _ block: (CapClient, DiscoveredCap) async throws -> T,
    ) async throws -> T {
        let current = settings.current
        step("scanning")
        let cap = try await findCap(target: target, current: current)

        let connection = CapConnection(central: central, debugLog: debugLog, cap: cap)
        let client = CapClient(connection: connection, debugLog: debugLog, requestIds: requestIds)
        activeClient = client
        defer {
            client.close()
            connection.disconnect()
            activeClient = nil
        }
        step("connecting")
        try await connection.connect(allowReconnectRetry: allowReconnectRetry)
        return try await block(client, cap)
    }

    private func findCap(target: DiscoveredCap?, current: AppSettings) async throws -> DiscoveredCap {
        if let target { return target }
        let scanSeconds = BleScanner.connectScanSeconds
        let predicate: (DiscoveredCap) -> Bool
        if current.pairedDeviceName != nil || current.pairedDeviceIdHex != nil {
            predicate = { $0.isSameCap(pairedName: current.pairedDeviceName, pairedDeviceIdHex: current.pairedDeviceIdHex) }
        } else {
            predicate = { $0.name != nil || $0.matchedByManufacturerData }
        }
        do {
            return try await scanner.findCap(seconds: scanSeconds, predicate: predicate)
        } catch let error as CapNotFoundError {
            throw CapNotFoundError(
                current.pairedDeviceName != nil
                    ? "cap '\(current.pairedDeviceName ?? "")' not found within \(Int(scanSeconds)) s — is it awake and nearby?"
                    : error.message,
            )
        }
    }

    private func step(_ name: String) {
        status = .running(step: name)
        if case .busy(_, let applying) = reminder {
            reminder = .busy(step: name, applying: applying)
        }
        debugLog.log(Self.tag, "step: \(name)")
    }

    private static func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}
