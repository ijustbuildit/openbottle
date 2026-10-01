package dev.hydrocap.app.ui

import androidx.lifecycle.*
import dev.hydrocap.app.AppContainer
import dev.hydrocap.app.R
import dev.hydrocap.app.ble.*
import dev.hydrocap.app.data.*
import dev.hydrocap.app.debug.DebugEntry
import dev.hydrocap.app.domain.*
import dev.hydrocap.app.health.*
import dev.hydrocap.app.notify.resolveTarget
import dev.hydrocap.app.notify.ringWindow
import dev.hydrocap.app.sync.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.atomic.AtomicLong

sealed class Screen {
    data object Loading : Screen()
    data object Onboarding : Screen()
    data object Optional : Screen()
    data object Scan : Screen()
    data object Home : Screen()
    data object History : Screen()
    data object AllDrinks : Screen()
    data object Debug : Screen()
    data object Reminder : Screen()
    data object Settings : Screen()
    data object BottleProfile : Screen()
}
data class ScanUiState(val scanning: Boolean = false, val caps: List<DiscoveredCap> = emptyList(), val error: String? = null, val pairingId: String? = null)
data class FillEstimate(val ml: Double, val percent: Double, val distanceMm: Int, val kcps: Int, val timestampSec: Long) {
    companion object {
        fun from(entry: TofLogEntry, profile: BottleProfile): FillEstimate? {
            if (entry.distanceMm >= profile.tofMaxMm) return null
            val volume = profile.volumeMl(entry.distanceMm)
            if (!volume.isFinite()) return null
            val full = profile.fullVolumeMl
            val percent = if (full.isFinite() && full > 0) (volume / full * 100).coerceIn(0.0, 100.0) else 0.0
            return FillEstimate(volume, percent, entry.distanceMm, entry.kcps, entry.timestamp)
        }
    }
}
data class DrinkSnapshot(val events: List<DrinkEvent> = emptyList(), val loaded: Boolean = false, val error: String? = null)
data class HomeUiState(
    val settings: AppSettings? = null, val battery: BatterySample? = null, val liveBattery: Int? = null,
    val todayEvents: List<DrinkEvent> = emptyList(), val todayMl: Double = 0.0, val fill: FillEstimate? = null,
    val syncStatus: SyncStatus = SyncStatus.Idle, val connection: ConnectionState = ConnectionState.Disconnected,
    val tofCount: Int = 0, val targetMl: Int = 2000, val targetCaption: String = "Drink goal 2.00 L · default, adjustable",
    val now: Instant = Instant.now(), val initialImportRunning: Boolean = false, val dataError: String? = null,
)
sealed class HealthWriteStatus {
    data object Idle : HealthWriteStatus(); data object Running : HealthWriteStatus()
    data class Done(val result: HealthWriteResult) : HealthWriteStatus(); data object Denied : HealthWriteStatus()
}
data class SettingsUiState(
    val settings: AppSettings? = null, val healthWrite: HealthWriteStatus = HealthWriteStatus.Idle,
    val healthTrackedCount: Int = 0, val profileMessage: String? = null,
    val body: HealthBodyState = HealthBodyState(), val targetMl: Int = 2000, val targetCaption: String = "",
    val drinkMessage: String? = null, val updatingReminders: Boolean = false,
)
data class PermissionUiState(val bluetooth: Boolean = false, val notifications: Boolean = false)

@OptIn(ExperimentalCoroutinesApi::class)
class MainViewModel(val container: AppContainer) : ViewModel() {
    private val mutableScreen = MutableStateFlow<Screen>(Screen.Loading)
    val screen: StateFlow<Screen> = mutableScreen
    val scan = MutableStateFlow(ScanUiState())
    val permissions = MutableStateFlow(PermissionUiState())
    val notice = MutableStateFlow<String?>(null)
    val debugEntries: StateFlow<List<DebugEntry>> = container.debugLog.entries
    val settings = container.settings.settings.stateIn(viewModelScope, SharingStarted.Eagerly, null)
    val body = container.healthBody
    val clock = MutableStateFlow(Instant.now())
    private var scanJob: Job? = null
    private var healthGeneration = AtomicLong()
    private var reminderGeneration = AtomicLong()
    private val drinkMessage = MutableStateFlow<String?>(null)
    private val updatingReminders = MutableStateFlow(false)
    private val healthWrite = MutableStateFlow<HealthWriteStatus>(HealthWriteStatus.Idle)
    private val profileMessage = MutableStateFlow<String?>(null)
    val allDrinks = container.database.drinkEventDao().observeAll().map { DrinkSnapshot(it, true) }
        .catch { emit(DrinkSnapshot(error = it.message ?: "Could not load drinks", loaded = true)) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, DrinkSnapshot())

    private val connectionFlow = container.syncEngine.activeClient.flatMapLatest { it?.connectionState ?: flowOf(ConnectionState.Disconnected) }
    private val liveBattery = container.syncEngine.activeClient.flatMapLatest { it?.observeBattery() ?: flowOf(null) }

    val home = combine(container.settings.settings, container.database.batterySampleDao().observeLatest(), allDrinks,
        container.database.tofLogDao().observeLatest(), container.syncEngine.status) { s, battery, snapshot, tof, status ->
        HomeUiState(settings = s, battery = battery, todayEvents = snapshot.events,
            fill = tof?.let { estimateFill(it, s.bottleProfile()) }, syncStatus = status, dataError = snapshot.error)
    }.combine(body) { state, health ->
        val target = state.settings!!.resolveTarget(health.weightKg)
        state.copy(targetMl = target.ml, targetCaption = HydrationTarget.caption(target))
    }.combine(clock) { state, now ->
        val day = now.atZone(ZoneId.systemDefault()).toLocalDate()
        val events = state.todayEvents.filter { it.timestamp <= now.epochSecond && Instant.ofEpochSecond(it.timestamp).atZone(ZoneId.systemDefault()).toLocalDate() == day }.sortedByDescending { it.timestamp }
        state.copy(todayEvents = events, todayMl = events.sumOf { it.volumeMl }, now = now)
    }.combine(connectionFlow) { s, c -> s.copy(connection = c) }
        .combine(liveBattery) { s, b -> s.copy(liveBattery = b) }
        .combine(container.database.tofLogDao().observeCount()) { s, count -> s.copy(tofCount = count) }
        .combine(container.connectionHandoff.state) { s, h -> s.copy(initialImportRunning = h.isRunning && h.reachedReady) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, HomeUiState())

    val settingsUi = combine(container.settings.settings, healthWrite, container.database.healthSyncDao().observeCount(), profileMessage, body) { s, w, count, message, health ->
        val target = s.resolveTarget(health.weightKg)
        SettingsUiState(s, w, count, message, health, target.ml, HydrationTarget.caption(target))
    }.combine(drinkMessage) { s, m -> s.copy(drinkMessage = m) }.combine(updatingReminders) { s, b -> s.copy(updatingReminders = b) }
        .stateIn(viewModelScope, SharingStarted.Eagerly, SettingsUiState())

    init {
        viewModelScope.launch {
            if (mutableScreen.value == Screen.Loading) mutableScreen.value = if (container.settings.current().hasPairedDevice) Screen.Home else Screen.Onboarding
            refreshForeground()
        }
        viewModelScope.launch { while (isActive) { delay(30_000); clock.value = Instant.now() } }
        viewModelScope.launch {
            var notifiedToken = -1L
            container.connectionHandoff.state.collect { handoff ->
                if (handoff.reachedReady && handoff.generation != notifiedToken) {
                    notifiedToken = handoff.generation
                    scan.value = scan.value.copy(pairingId = null, error = null)
                    mutableScreen.value = Screen.Home
                    notice.value = "Bottle connected"
                    viewModelScope.launch { delay(4_000); notice.value = null }
                } else if (!handoff.isRunning && !handoff.reachedReady && handoff.error != null) {
                    scan.value = scan.value.copy(pairingId = null, error = handoff.error)
                }
            }
        }
    }
    fun navigate(destination: Screen) {
        if (destination !in listOf(Screen.Scan, Screen.Optional, Screen.Onboarding)) stopScan()
        mutableScreen.value = destination
    }
    fun back() = navigate(when (screen.value) {
        Screen.Reminder, Screen.BottleProfile, Screen.Debug -> Screen.Settings
        Screen.AllDrinks -> Screen.Home
        Screen.Scan -> if (settings.value?.hasPairedDevice == true) Screen.Settings else Screen.Optional
        Screen.Optional -> Screen.Onboarding
        else -> Screen.Home
    })
    fun refreshToday() { clock.value = Instant.now() }
    fun refreshForeground() {
        refreshToday()
        permissions.value = PermissionUiState(AppPermissions.hasEssential(container.appContext), container.drinkReminders.notificationsAllowed())
        val token = healthGeneration.incrementAndGet()
        container.appScope.launch {
            val value = container.healthBodyReader.read()
            if (healthGeneration.get() == token) body.value = value
            container.drinkReminders.replan().join()
        }
        if (permissions.value.bluetooth && screen.value in listOf(Screen.Optional, Screen.Scan) && !container.connectionHandoff.isRunning && !scan.value.scanning) startScan()
    }
    fun advanceFromWelcome() {
        viewModelScope.launch {
            container.refreshHealthBody()
            refreshForeground()
            if (permissions.value.bluetooth) startScan()
            val s = container.settings.current()
            val hasWeight = body.value.weightKg != null || s.manualWeightKg != null
            navigate(if (!body.value.hydrationPermission || !permissions.value.notifications || !permissions.value.bluetooth || !hasWeight) Screen.Optional else Screen.Scan)
        }
    }
    fun findBottle() { navigate(Screen.Scan); if (permissions.value.bluetooth && !scan.value.scanning) startScan() }
    fun startScan(durationMs: Long = 45_000) {
        if (!AppPermissions.hasEssential(container.appContext) || container.connectionHandoff.isRunning) return
        stopScan()
        scan.value = scan.value.copy(scanning = true, error = null)
        scanJob = viewModelScope.launch {
            try { withTimeoutOrNull(durationMs) { container.scanner.scan().collect { caps -> scan.value = scan.value.copy(caps = caps.sortedByDescending { it.rssi }) } } }
            catch (e: CancellationException) { throw e }
            catch (e: Exception) { scan.value = scan.value.copy(error = e.message ?: "Could not scan") }
            finally { scan.value = scan.value.copy(scanning = false) }
        }
    }
    fun stopScan() { scanJob?.cancel(); scanJob = null; scan.value = scan.value.copy(scanning = false) }
    fun selectCap(cap: DiscoveredCap) {
        if (container.syncEngine.isRunning) { scan.value = scan.value.copy(error = "The cap is busy with a sync. Try again in a moment."); return }
        val token = container.connectionHandoff.reserve() ?: return
        stopScan()
        scan.value = scan.value.copy(pairingId = cap.address, error = null)
        BackgroundSync.cancel(container.appContext)
        try { SyncService.startInitial(container.appContext, cap, token) }
        catch (e: Exception) { container.connectionHandoff.failReservation(token, e.message ?: "Could not connect"); BackgroundSync.reconcile(container.appContext, settings.value ?: return) }
    }
    fun forgetDevice() {
        if (container.connectionHandoff.isRunning || container.syncEngine.isRunning) return
        container.appScope.launch {
            BackgroundSync.cancel(container.appContext)
            container.settings.forgetDevice()
            container.drinkReminders.update(false).join()
            container.database.deviceDao().deleteAll()
            navigate(Screen.Onboarding)
        }
    }
    fun setBatteryThresholds(alertPercent: Int, criticalPercent: Int) { container.appScope.launch { container.settings.setBatteryThresholds(alertPercent, criticalPercent) } }
    fun setBackgroundSyncEnabled(enabled: Boolean) { container.appScope.launch { container.settings.setBackgroundSyncEnabled(enabled); if (!container.connectionHandoff.isRunning) BackgroundSync.reconcile(container.appContext, container.settings.current()) } }
    fun setAppearance(value: String) { container.appScope.launch { container.settings.setAppearance(value) } }
    fun setHistory(range: String? = null, chart: String? = null, axis: String? = null) { container.appScope.launch { container.settings.setHistory(range, chart, axis) } }
    fun setDailyTarget(estimate: Boolean, target: Int?) { container.appScope.launch { container.settings.setDailyTarget(estimate, target?.let(HydrationTarget::clampOverride)); container.drinkReminders.replan().join() } }
    fun setManualBody(weight: Double?, sex: String?) { container.appScope.launch { container.settings.setManualBody(weight, sex); container.drinkReminders.replan().join() } }
    fun setDrinkReminders(enabled: Boolean, frequency: Int? = null, behind: Boolean? = null) {
        val token = reminderGeneration.incrementAndGet()
        if (!enabled) { updatingReminders.value = false; drinkMessage.value = null; container.drinkReminders.update(false); return }
        updatingReminders.value = true
        container.appScope.launch {
            try {
                if (!container.drinkReminders.notificationsAllowed()) { drinkMessage.value = "Allow notifications in Android Settings first."; return@launch }
                val originalId = container.settings.current().pairedDeviceIdHex ?: run { drinkMessage.value = "Pair a bottle first."; return@launch }
                if (container.settings.current().ringWindow() == null) {
                    try { container.syncEngine.readReminder() }
                    catch (e: Exception) { drinkMessage.value = "Keep the cap nearby to read its ring hours. ${e.message}"; return@launch }
                }
                if (token != reminderGeneration.get()) return@launch
                val s = container.settings.current()
                if (s.pairedDeviceIdHex != originalId || s.ringWindow() == null) { drinkMessage.value = "The cap's ring hours are not set. Set valid active hours in Ring first."; return@launch }
                container.drinkReminders.update(true, frequency, behind).join()
                if (token == reminderGeneration.get()) drinkMessage.value = null
            } finally { if (token == reminderGeneration.get()) updatingReminders.value = false }
        }
    }
    fun enableHealthSync() { container.appScope.launch { container.settings.setHealthSyncEnabled(true); writeAllToHealthConnect() } }
    fun disableHealthSync() { container.appScope.launch { container.settings.setHealthSyncEnabled(false); healthWrite.value = HealthWriteStatus.Idle } }
    fun onHealthPermissionDenied() { container.appScope.launch { container.settings.setHealthSyncEnabled(false); healthWrite.value = HealthWriteStatus.Denied } }
    fun writeAllToHealthConnect() {
        if (healthWrite.value == HealthWriteStatus.Running) return
        healthWrite.value = HealthWriteStatus.Running
        container.appScope.launch {
            try { healthWrite.value = HealthWriteStatus.Done(container.healthWriter.upsertAllStored()) }
            catch (e: Exception) { healthWrite.value = HealthWriteStatus.Done(HealthWriteResult(0,0,0,e.message)) }
        }
    }
    fun setBottleProfile(profile: BottleProfile) { container.appScope.launch {
        try {
            container.settings.setBottleProfile(profile.id, profile.coefficients.takeIf { profile.id == BottleProfile.ID_CUSTOM })
            val events = container.drinkEventBuilder.rebuild(profile)
            profileMessage.value = container.appContext.resources.getQuantityString(R.plurals.settings_bottle_rebuilt, events.size, profile.label, events.size)
            if (container.settings.current().healthSyncEnabled) writeAllToHealthConnect()
            container.drinkReminders.replan().join()
        } catch (e: Exception) { profileMessage.value = e.message ?: "Could not rebuild drinks" }
    } }
    fun clearDebugLog() = container.debugLog.clearMemory()
    fun debugText(): String = container.debugLog.dumpText()
    private fun estimateFill(entry: TofLogEntry, profile: BottleProfile): FillEstimate? = FillEstimate.from(entry, profile)
    class Factory(private val container: AppContainer) : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST") override fun <T : ViewModel> create(modelClass: Class<T>): T = MainViewModel(container) as T
    }
}
