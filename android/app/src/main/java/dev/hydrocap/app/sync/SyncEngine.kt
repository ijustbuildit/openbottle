package dev.hydrocap.app.sync

import dev.hydrocap.app.ble.BleScanner
import dev.hydrocap.app.ble.CapClient
import dev.hydrocap.app.ble.CapConnection
import dev.hydrocap.app.ble.DiscoveredCap
import dev.hydrocap.app.ble.RequestIdCounter
import dev.hydrocap.app.data.ActivationLogEntry
import dev.hydrocap.app.data.BatterySample
import dev.hydrocap.app.data.DeviceRecord
import dev.hydrocap.app.data.HydroCapDatabase
import dev.hydrocap.app.data.SettingsRepository
import dev.hydrocap.app.data.TofLogEntry
import dev.hydrocap.app.debug.DebugLog
import dev.hydrocap.app.domain.BottleProfile
import dev.hydrocap.app.domain.CapReminderConfig
import dev.hydrocap.app.domain.ReminderPatch
import dev.hydrocap.app.domain.ReminderRules
import dev.hydrocap.app.domain.ReminderValidationException
import dev.hydrocap.app.health.HealthConnectWriter
import dev.hydrocap.app.notify.BatteryNotifier
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex

/** Progress of a running sync, shown on the Home status line. */
sealed class SyncStatus {
    data object Idle : SyncStatus()
    data class Running(val step: String) : SyncStatus()
    data class Done(val summary: SyncSummary, val finishedAtMs: Long) : SyncStatus()
    data class Failed(val reason: String, val finishedAtMs: Long) : SyncStatus()
}

data class SyncSummary(
    val deviceName: String,
    val batteryPercent: Int?,
    val newTofEntries: Int,
    val newActivationEntries: Int,
    val drinkEvents: Int,
    val capBottleSizeMl: Int?,
    val capReportedUiState: String?,
    val durationMs: Long,
)

open class SyncException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** Another cap job holds the link; the caller may retry later. */
class CapBusyException : SyncException("a cap job is already running")

/** The (paired) cap did not advertise within the scan window — a normal outcome when the bottle is out of range. */
class CapNotFoundException(message: String) : SyncException(message)

/** State of the Reminder screen's cap round trip (read on open, write + re-read on Apply). */
sealed class ReminderStatus {
    data object Idle : ReminderStatus()
    data class Busy(val step: String, val applying: Boolean) : ReminderStatus()
    /** [applied] is true when the values are the re-read result of a write. */
    data class Loaded(val config: CapReminderConfig, val atMs: Long, val applied: Boolean) : ReminderStatus()
    data class Failed(val reason: String, val atMs: Long, val lastKnown: CapReminderConfig?, val applying: Boolean) : ReminderStatus()
}

/**
 * The full sync sequence from the brief, adjusted for hardware session 1:
 *
 * scan (filter 0x180A, match by name/serial — the cap rotates its MAC) →
 * connect → MTU/notify/DIS → **setTime first** → getUiState → getTofSettings
 * → battery read → ToF log pages (from = max stored timestamp, limit 5, until
 * a short page or 500 pages) → activation log pages → TofAlgorithm over the
 * whole stored log → upsert DrinkEvents → Health Connect writer → disconnect.
 *
 * Only one cap job runs at a time. Each job builds its own [CapConnection] and
 * [CapClient] so a failed link never leaks into the next attempt.
 */
class SyncEngine(
    private val scanner: BleScanner,
    private val connectionFactory: () -> CapConnection,
    private val database: HydroCapDatabase,
    private val settings: SettingsRepository,
    private val drinkEventBuilder: DrinkEventBuilder,
    private val healthWriter: HealthConnectWriter,
    private val batteryNotifier: BatteryNotifier,
    private val requestIds: RequestIdCounter,
    private val scope: CoroutineScope,
    private val debugLog: DebugLog,
    /** Invoked after a sync paired a cap that was not paired before (e.g. DEBUG_SYNC on a fresh install). */
    private val onPaired: suspend () -> Unit = {},
    private val admission: CapJobAdmission = CapJobAdmission(),
    private val onSynced: suspend () -> Unit = {},
    private val onRingRead: suspend () -> Unit = {},
    private val onIdentityChanged: () -> Unit = {},
) {
    private val syncMutex = Mutex()
    private val _status = MutableStateFlow<SyncStatus>(SyncStatus.Idle)
    val status: StateFlow<SyncStatus> = _status

    private val _activeClient = MutableStateFlow<CapClient?>(null)
    /** The client of the sync in progress (for the Home connection line); null when idle. */
    val activeClient: StateFlow<CapClient?> = _activeClient
    private val _liveTof = MutableStateFlow<Pair<Int, Int>?>(null)
    val lastLiveTof: StateFlow<Pair<Int, Int>?> = _liveTof

    private val _reminder = MutableStateFlow<ReminderStatus>(ReminderStatus.Idle)
    /** Reminder ring / quiet hours as last read from the cap; the cap is the source of truth. */
    val reminder: StateFlow<ReminderStatus> = _reminder

    val isRunning: Boolean get() = syncMutex.isLocked

    /**
     * Runs a full sync. [target] preselects a cap from a scan list; otherwise
     * the paired cap (by name/serial) is searched, or — if nothing is paired —
     * the first cap that advertises.
     */
    suspend fun sync(target: DiscoveredCap? = null, onReady: (suspend (ConnectedCapIdentity) -> Unit)? = null): SyncSummary = exclusive("sync", initial = onReady != null) { startedAt ->
        val summary = runSync(target, startedAt, onReady)
        _status.value = SyncStatus.Done(summary, System.currentTimeMillis())
        onSynced()
        summary
    }

    /** Connects and performs a single live ToF measurement (Debug "Live ToF" / DEBUG_TOF). */
    suspend fun liveTof(target: DiscoveredCap? = null): Pair<Int, Int> = exclusive("live ToF") {
        withConnectedCap(target, "live ToF") { client, _ ->
            client.setTime()
            val state = client.getTofState().state
            debugLog.log(TAG, "live ToF distance=${state.distanceInMillimeter} mm kcps=${state.kcps}")
            _liveTof.value = state.distanceInMillimeter to state.kcps
            state.distanceInMillimeter to state.kcps
        }.also { _status.value = SyncStatus.Idle }
    }

    /** Reads every GET-able setting and logs it (Debug "Read all settings"). */
    suspend fun readAllSettings(target: DiscoveredCap? = null): List<String> = exclusive("read all settings") {
        withConnectedCap(target, "read all settings") { client, _ ->
            client.setTime()
            val lines = ArrayList<String>()
            fun add(label: String, value: Any) {
                val line = "$label: ${value.toString().replace('\n', ' ').replace(Regex("\\s+"), " ").trim()}"
                debugLog.log(TAG, line)
                lines += line
            }
            add("time", client.getTime())
            add("uiState", client.getUiState())
            add("tofSettings", client.getTofSettings())
            add("hydroReminder", client.getHydroReminder())
            add("dnd", client.getDnd())
            add("lowBattery", client.getLowBatterySettings())
            add("battery", client.readBattery() ?: "n/a")
            lines
        }.also { _status.value = SyncStatus.Idle }
    }

    /** Reads reminder + quiet hours (Reminder screen on open, DEBUG_READ_REMINDER). */
    suspend fun readReminder(target: DiscoveredCap? = null): CapReminderConfig = reminderJob("read reminder", applying = false) {
        withConnectedCap(target, "read reminder") { client, _ ->
            client.setTime()
            readReminderConfig(client)
        }
    }

    /**
     * Writes the reminder and/or quiet hours: connect → setTime → read the
     * current values → merge [patch] → validate → `SetCapHydroReminderSettings`
     * → `SetCapDoNotDisturbSettings` (each must answer SUCCESS; FAIL /
     * NOT_SUPPORTED aborts with the code) → re-read both. The returned config
     * is what the cap actually stored.
     */
    suspend fun applyReminder(patch: ReminderPatch, target: DiscoveredCap? = null): CapReminderConfig =
        reminderJob("apply reminder", applying = true) {
            if (patch.isEmpty) throw SyncException("nothing to write")
            withConnectedCap(target, "apply reminder") { client, _ ->
                client.setTime()
                reminderStep("reading current values", applying = true)
                val current = readReminderConfig(client)
                val resolved = try {
                    ReminderRules.validateOrThrow(ReminderRules.resolve(current, patch))
                } catch (e: ReminderValidationException) {
                    throw SyncException("invalid reminder settings: ${e.message}", e)
                }
                debugLog.log(TAG, "writing ${ReminderMapping.describe(resolved)}")
                if (patch.reminder != null) {
                    reminderStep("writing reminder", applying = true)
                    val response = client.setHydroReminder(ReminderMapping.toProto(resolved.reminder))
                    debugLog.log(TAG, "SetCapHydroReminderSettings → ${response.code.name}")
                }
                if (patch.dnd != null) {
                    reminderStep("writing quiet hours", applying = true)
                    val response = client.setDnd(ReminderMapping.toProto(resolved.dnd))
                    debugLog.log(TAG, "SetCapDoNotDisturbSettings → ${response.code.name}")
                }
                reminderStep("reading back", applying = true)
                readReminderConfig(client)
            }
        }

    private suspend fun readReminderConfig(client: CapClient): CapReminderConfig {
        val reminder = ReminderMapping.fromProto(client.getHydroReminder().settings)
        val dnd = ReminderMapping.fromProto(client.getDnd().settings)
        val config = CapReminderConfig(reminder, dnd)
        settings.current().pairedDeviceIdHex?.let { settings.setRingHours(it, reminder.startSec, reminder.stopSec) }
        debugLog.log(TAG, "cap holds ${ReminderMapping.describe(config)}")
        return config
    }

    private suspend fun reminderJob(purpose: String, applying: Boolean, block: suspend () -> CapReminderConfig): CapReminderConfig {
        val lastKnown = (_reminder.value as? ReminderStatus.Loaded)?.config ?: (_reminder.value as? ReminderStatus.Failed)?.lastKnown
        try {
            return exclusive(purpose) {
                _reminder.value = ReminderStatus.Busy("scanning", applying)
                val config = block()
                _reminder.value = ReminderStatus.Loaded(config, System.currentTimeMillis(), applied = applying)
                // Replan only after the BLE read/write/read-back connection has closed; a Health read must not idle the cap mid-write.
                onRingRead()
                _status.value = SyncStatus.Idle
                config
            }
        } catch (e: Exception) {
            // Covers failures inside the job and the "already running" refusal before it starts.
            _reminder.value = ReminderStatus.Failed(e.message ?: e.javaClass.simpleName, System.currentTimeMillis(), lastKnown, applying)
            throw e
        }
    }

    private fun reminderStep(step: String, applying: Boolean) {
        _reminder.value = ReminderStatus.Busy(step, applying)
        debugLog.log(TAG, "step: $step")
    }

    /** One cap job at a time; converts every failure into [SyncStatus.Failed] + [SyncException]. */
    private suspend fun <T> exclusive(purpose: String, initial: Boolean = false, block: suspend (startedAt: Long) -> T): T {
        if (!admission.acquire(initial)) throw CapBusyException()
        if (!syncMutex.tryLock()) { admission.releaseJob(); throw CapBusyException() }
        val startedAt = System.currentTimeMillis()
        try {
            return block(startedAt)
        } catch (e: Exception) {
            val reason = e.message ?: e.javaClass.simpleName
            debugLog.error(TAG, "$purpose failed", e)
            _status.value = SyncStatus.Failed(reason, System.currentTimeMillis())
            throw if (e is SyncException) e else SyncException(reason, e)
        } finally {
            _activeClient.value = null
            syncMutex.unlock()
            admission.releaseJob()
        }
    }

    private suspend fun runSync(target: DiscoveredCap?, startedAt: Long, onReady: (suspend (ConnectedCapIdentity) -> Unit)?): SyncSummary = withConnectedCap(target, "sync", onReady) { client, cap ->
        val current = settings.current()

        step("set time")
        client.setTime(System.currentTimeMillis())

        step("read ui state")
        val uiState = client.getUiState()
        debugLog.log(TAG, "ui state=${uiState.state} (${uiState.stateValue}) powerSaving=${uiState.powerSavingMode}")

        step("read ToF settings")
        val tofSettings = client.getTofSettings().settings
        val capBottleSize = tofSettings.bottleSizeInMilliliter
        debugLog.log(TAG, "tof settings mode=${tofSettings.mode} interval=${tofSettings.triggerIntervalInSec}s bottleSize=$capBottleSize ml")
        settings.setLastCapBottleSize(capBottleSize)
        val matchingProfile = BottleProfile.forCapReportedSize(capBottleSize)
        if (matchingProfile == null) {
            debugLog.log(TAG, "WARN cap reports bottle size $capBottleSize ml which matches no built-in profile")
        } else if (matchingProfile.id != current.bottleProfileId) {
            debugLog.log(TAG, "cap reports $capBottleSize ml but profile stays '${current.bottleProfileId}' (cap value is informational, see hw-session-1)")
        }

        step("read battery")
        val battery = client.readBattery()
        if (battery != null) {
            database.batterySampleDao().insert(BatterySample(System.currentTimeMillis() / 1000, battery))
            batteryNotifier.onBatteryLevel(battery)
        }

        step("pull ToF log")
        val newTof = pullTofLog(client)

        step("pull activation log")
        val newActivation = pullActivationLog(client)

        step("compute drinks")
        val drinkEvents = drinkEventBuilder.rebuild(current.bottleProfile())

        step("health connect")
        if (current.healthSyncEnabled) {
            val result = healthWriter.upsert(drinkEvents)
            debugLog.log(TAG, "health connect inserted=${result.inserted} updated=${result.updated} skipped=${result.skipped} error=${result.error}")
        } else {
            debugLog.log(TAG, "health sync disabled, skipping Health Connect")
        }

        val info = client.deviceInformation
        database.deviceDao().upsert(
            DeviceRecord(
                deviceIdHex = cap.deviceIdHex ?: info?.serial ?: cap.name ?: cap.address,
                name = cap.name ?: "",
                lastAddress = cap.address,
                bottleSizeMl = capBottleSize,
                manufacturer = info?.manufacturer,
                model = info?.model,
                serial = info?.serial,
                firmwareRevision = info?.firmwareRevision,
                hardwareRevision = info?.hardwareRevision,
                softwareRevision = info?.softwareRevision,
                lastSeenMs = System.currentTimeMillis(),
            ),
        )
        if (cap.name != null && !current.hasPairedDevice) {
            settings.setPairedDevice(cap.name, cap.deviceIdHex ?: info?.serial ?: cap.name)
            debugLog.log(TAG, "paired with ${cap.name} (id ${cap.deviceIdHex})")
            onPaired()
        }
        val finishedAt = System.currentTimeMillis()
        settings.setLastSync(finishedAt)
        SyncSummary(
            deviceName = cap.name ?: cap.address,
            batteryPercent = battery,
            newTofEntries = newTof,
            newActivationEntries = newActivation,
            drinkEvents = drinkEvents.size,
            capBottleSizeMl = capBottleSize,
            capReportedUiState = uiState.state.name,
            durationMs = finishedAt - startedAt,
        ).also { debugLog.log(TAG, "sync done $it") }
    }

    private suspend fun pullTofLog(client: CapClient): Int {
        val dao = database.tofLogDao()
        var from = dao.maxTimestamp() ?: 0L
        var inserted = 0
        var pages = 0
        while (pages < MAX_PAGES) {
            val page = client.getTofLog(from, PAGE_LIMIT).itemsList
            pages++
            if (page.isEmpty()) break
            val entries = page.map {
                TofLogEntry(
                    timestamp = it.timestamp,
                    triggerType = it.triggerTypeValue,
                    distanceMm = it.distanceInMillimeter,
                    kcps = it.kcps,
                    uvLedTempOhm = it.uvLedTempInOhm,
                )
            }
            inserted += dao.insertAll(entries).count { it != -1L }
            val last = entries.maxOf { it.timestamp }
            if (last <= from) {
                debugLog.log(TAG, "ToF log page did not advance (from=$from last=$last), stopping")
                break
            }
            from = last
            if (page.size < PAGE_LIMIT) break
            if (pages % 10 == 0) _status.value = SyncStatus.Running("pull ToF log (page $pages, $inserted new)")
        }
        debugLog.log(TAG, "ToF log: $pages page(s), $inserted new entr${if (inserted == 1) "y" else "ies"}, newest ts=$from")
        if (pages >= MAX_PAGES) debugLog.log(TAG, "WARN ToF log paging stopped at the $MAX_PAGES page cap")
        return inserted
    }

    private suspend fun pullActivationLog(client: CapClient): Int {
        val dao = database.activationLogDao()
        var from = dao.maxTimestamp() ?: 0L
        var inserted = 0
        var pages = 0
        while (pages < MAX_PAGES) {
            val page = client.getActivationLog(from, PAGE_LIMIT).itemsList
            pages++
            if (page.isEmpty()) break
            val entries = page.map { ActivationLogEntry(it.timestamp, it.modeValue, it.batterySocInPercentage) }
            inserted += dao.insertAll(entries).count { it != -1L }
            val last = entries.maxOf { it.timestamp }
            if (last <= from) break
            from = last
            if (page.size < PAGE_LIMIT) break
        }
        debugLog.log(TAG, "activation log: $pages page(s), $inserted new entr${if (inserted == 1) "y" else "ies"}, newest ts=$from")
        return inserted
    }

    /** Scan → connect → block → disconnect, with the client exposed for the UI while connected. */
    private suspend fun <T> withConnectedCap(
        target: DiscoveredCap?,
        purpose: String,
        onReady: (suspend (ConnectedCapIdentity) -> Unit)? = null,
        block: suspend (CapClient, DiscoveredCap) -> T,
    ): T {
        val current = settings.current()
        step("scanning")
        val cap = target ?: findCap(current.pairedDeviceName, current.pairedDeviceIdHex)
        debugLog.log(TAG, "$purpose: using ${cap.name} at ${cap.address} (rssi ${cap.rssi}, id ${cap.deviceIdHex})")

        val connection = connectionFactory()
        val client = CapClient(connection, debugLog, scope, requestIds)
        _activeClient.value = client
        try {
            step("connecting")
            connection.connect(cap.address)
            if (purpose == "sync") {
                val identity = ConnectedCapIdentity.from(cap.name, cap.deviceIdHex, client.deviceInformation?.serial)
                    ?: throw SyncException("cap has no stable identity")
                if (onReady != null || !current.hasPairedDevice) {
                    settings.setPairedDevice(identity.name, identity.deviceIdHex)
                    if (current.pairedDeviceIdHex != identity.deviceIdHex) {
                        _reminder.value = ReminderStatus.Idle
                        onIdentityChanged()
                    }
                    onReady?.invoke(identity)
                    if (onReady == null) onPaired()
                }
            }
            return block(client, cap)
        } finally {
            client.close()
            connection.disconnect()
        }
    }

    private suspend fun findCap(pairedName: String?, pairedIdHex: String?): DiscoveredCap {
        val predicate: (DiscoveredCap) -> Boolean = if (pairedName != null || pairedIdHex != null) {
            { it.isSameCap(pairedName, pairedIdHex) }
        } else {
            { it.name != null || it.matchedByManufacturerData }
        }
        return scanner.findCap(BleScanner.CONNECT_SCAN_MS, predicate)
            ?: throw CapNotFoundException(
                if (pairedName != null) "cap '$pairedName' not found within ${BleScanner.CONNECT_SCAN_MS / 1000} s — is it awake and nearby?"
                else "no cap found within ${BleScanner.CONNECT_SCAN_MS / 1000} s",
            )
    }

    private fun step(name: String) {
        _status.value = SyncStatus.Running(name)
        if (_reminder.value is ReminderStatus.Busy) {
            _reminder.value = ReminderStatus.Busy(name, (_reminder.value as ReminderStatus.Busy).applying)
        }
        debugLog.log(TAG, "step: $name")
    }

    companion object {
        const val TAG = "sync"
        const val PAGE_LIMIT = 5
        /** Hardware session 1: the log holds months of history, so allow up to 500 pages × 5. */
        const val MAX_PAGES = 500
    }
}
