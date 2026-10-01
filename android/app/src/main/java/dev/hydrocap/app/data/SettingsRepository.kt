package dev.hydrocap.app.data

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dev.hydrocap.app.domain.BottleProfile
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "settings")

/** User settings; everything stays on device. */
data class AppSettings(
    /** Identity of the paired cap: advertised name + decoded serial. Never a MAC. */
    val pairedDeviceName: String?,
    val pairedDeviceIdHex: String?,
    val batteryAlertPercent: Int,
    val batteryCriticalPercent: Int,
    val healthSyncEnabled: Boolean,
    val bottleProfileId: String,
    val customCoefficients: DoubleArray?,
    val lastSyncMs: Long?,
    val lastCapBottleSizeMl: Int?,
    /** Battery thresholds that have fired and not yet re-armed (see BatteryAlertPolicy). */
    val firedBatteryThresholds: Set<Int>,
    /** Periodic WorkManager sync (phase 2); default on. */
    val backgroundSyncEnabled: Boolean,
    val lastBackgroundRunMs: Long?,
    val lastBackgroundOutcome: String?,
    /** Consecutive periodic runs that did not find the cap (see BackgroundRunPolicy). */
    val consecutiveCapMisses: Int,
    val appearance: String = "system",
    val dailyTargetUseEstimate: Boolean = true,
    val dailyTargetOverrideMl: Int? = null,
    val manualWeightKg: Double? = null,
    val manualSex: String? = null,
    val historyRange: String = "7d",
    val historyChartType: String = "bars",
    val historyYAxis: String = "auto",
    val drinkRemindersEnabled: Boolean = false,
    val drinkReminderFrequencyMinutes: Int = 120,
    val drinkReminderOnlyWhenBehind: Boolean = true,
    val ringDeviceId: String? = null,
    val lastRingStartSec: Int? = null,
    val lastRingStopSec: Int? = null,
) {
    val hasPairedDevice: Boolean get() = pairedDeviceName != null

    /** Resolves the selected [BottleProfile], falling back to the default body. */
    fun bottleProfile(): BottleProfile = when (bottleProfileId) {
        BottleProfile.ID_CUSTOM -> customCoefficients?.let {
            BottleProfile(BottleProfile.ID_CUSTOM, "Custom", 0, it)
        } ?: BottleProfile.DEFAULT
        else -> BottleProfile.builtIn(bottleProfileId) ?: BottleProfile.DEFAULT
    }
}

class SettingsRepository(private val context: Context) {

    private object Keys {
        val PAIRED_NAME = stringPreferencesKey("paired_device_name")
        val PAIRED_ID = stringPreferencesKey("paired_device_id_hex")
        val BATTERY_ALERT = intPreferencesKey("battery_alert_percent")
        val BATTERY_CRITICAL = intPreferencesKey("battery_critical_percent")
        val HEALTH_SYNC = booleanPreferencesKey("health_sync_enabled")
        val BOTTLE_PROFILE = stringPreferencesKey("bottle_profile_id")
        val CUSTOM_COEFFICIENTS = stringPreferencesKey("custom_coefficients")
        val LAST_SYNC = longPreferencesKey("last_sync_ms")
        val LAST_CAP_BOTTLE_SIZE = intPreferencesKey("last_cap_bottle_size_ml")
        val FIRED_BATTERY_THRESHOLDS = stringPreferencesKey("fired_battery_thresholds")
        val BACKGROUND_SYNC = booleanPreferencesKey("background_sync_enabled")
        val LAST_BACKGROUND_RUN = longPreferencesKey("last_background_run_ms")
        val LAST_BACKGROUND_OUTCOME = stringPreferencesKey("last_background_outcome")
        val CONSECUTIVE_CAP_MISSES = intPreferencesKey("consecutive_cap_misses")
        val APPEARANCE = stringPreferencesKey("appearance")
        val USE_ESTIMATE = booleanPreferencesKey("daily_target_use_estimate")
        val TARGET = intPreferencesKey("daily_target_override_ml")
        val WEIGHT = stringPreferencesKey("manual_weight_kg")
        val SEX = stringPreferencesKey("manual_sex")
        val HISTORY_RANGE = stringPreferencesKey("history_range")
        val CHART = stringPreferencesKey("history_chart_type")
        val AXIS = stringPreferencesKey("history_y_axis")
        val DRINK_ENABLED = booleanPreferencesKey("drink_reminders_enabled")
        val FREQUENCY = intPreferencesKey("drink_reminder_frequency_minutes")
        val BEHIND = booleanPreferencesKey("drink_reminder_only_when_behind")
        val RING_ID = stringPreferencesKey("ring_device_id")
        val RING_START = intPreferencesKey("last_ring_start_sec")
        val RING_STOP = intPreferencesKey("last_ring_stop_sec")
    }

    val settings: Flow<AppSettings> = context.settingsDataStore.data.map { it.toSettings() }

    suspend fun current(): AppSettings = settings.first()

    suspend fun setPairedDevice(name: String, deviceIdHex: String) {
        context.settingsDataStore.edit {
            if (it[Keys.PAIRED_ID] != deviceIdHex) clearRing(it)
            it[Keys.PAIRED_NAME] = name
            it[Keys.PAIRED_ID] = deviceIdHex
        }
    }

    suspend fun forgetDevice() {
        context.settingsDataStore.edit {
            clearRing(it)
            it.remove(Keys.PAIRED_NAME)
            it.remove(Keys.PAIRED_ID)
            it.remove(Keys.LAST_SYNC)
            it.remove(Keys.LAST_CAP_BOTTLE_SIZE)
            it.remove(Keys.LAST_BACKGROUND_RUN)
            it.remove(Keys.LAST_BACKGROUND_OUTCOME)
            it.remove(Keys.CONSECUTIVE_CAP_MISSES)
        }
    }

    /** New thresholds re-arm every alert (the fired set is cleared). */
    suspend fun setBatteryThresholds(alertPercent: Int, criticalPercent: Int) {
        context.settingsDataStore.edit {
            it[Keys.BATTERY_ALERT] = alertPercent.coerceIn(2, MAX_BATTERY_THRESHOLD)
            it[Keys.BATTERY_CRITICAL] = criticalPercent.coerceIn(1, alertPercent.coerceIn(2, MAX_BATTERY_THRESHOLD) - 1)
            it.remove(Keys.FIRED_BATTERY_THRESHOLDS)
        }
    }

    suspend fun setHealthSyncEnabled(enabled: Boolean) {
        context.settingsDataStore.edit { it[Keys.HEALTH_SYNC] = enabled }
    }

    suspend fun setBottleProfile(profileId: String, customCoefficients: DoubleArray? = null) {
        context.settingsDataStore.edit {
            it[Keys.BOTTLE_PROFILE] = profileId
            if (customCoefficients != null) it[Keys.CUSTOM_COEFFICIENTS] = customCoefficients.joinToString(",")
        }
    }

    suspend fun setLastSync(timestampMs: Long) {
        context.settingsDataStore.edit { it[Keys.LAST_SYNC] = timestampMs }
    }

    suspend fun setLastCapBottleSize(bottleSizeMl: Int) {
        context.settingsDataStore.edit { it[Keys.LAST_CAP_BOTTLE_SIZE] = bottleSizeMl }
    }

    suspend fun setFiredBatteryThresholds(thresholds: Set<Int>) {
        context.settingsDataStore.edit { it[Keys.FIRED_BATTERY_THRESHOLDS] = thresholds.joinToString(",") }
    }

    suspend fun setBackgroundSyncEnabled(enabled: Boolean) {
        context.settingsDataStore.edit { it[Keys.BACKGROUND_SYNC] = enabled }
    }

    /** Records the outcome of one periodic run (Debug screen + miss counter). */
    suspend fun setLastBackgroundRun(timestampMs: Long, outcome: String, consecutiveCapMisses: Int) {
        context.settingsDataStore.edit {
            it[Keys.LAST_BACKGROUND_RUN] = timestampMs
            it[Keys.LAST_BACKGROUND_OUTCOME] = outcome
            it[Keys.CONSECUTIVE_CAP_MISSES] = consecutiveCapMisses
        }
    }

    suspend fun setAppearance(value: String) { context.settingsDataStore.edit { it[Keys.APPEARANCE] = value.takeIf { v -> v in listOf("system", "light", "dark") } ?: "system" } }

    suspend fun setDailyTarget(useEstimate: Boolean, overrideMl: Int?) { context.settingsDataStore.edit {
        it[Keys.USE_ESTIMATE] = useEstimate
        if (overrideMl == null) it.remove(Keys.TARGET) else it[Keys.TARGET] = overrideMl
    } }

    suspend fun setManualBody(weightKg: Double?, sex: String?) { context.settingsDataStore.edit {
        if (weightKg == null || !weightKg.isFinite() || weightKg !in 20.0..300.0) it.remove(Keys.WEIGHT) else it[Keys.WEIGHT] = weightKg.toString()
        if (sex == null || sex !in listOf("female", "male", "other")) it.remove(Keys.SEX) else it[Keys.SEX] = sex
    } }

    suspend fun setHistory(range: String? = null, chart: String? = null, axis: String? = null) { context.settingsDataStore.edit {
        range?.let { v -> it[Keys.HISTORY_RANGE] = v }
        chart?.let { v -> it[Keys.CHART] = v }
        axis?.let { v -> it[Keys.AXIS] = v }
    } }

    suspend fun setDrinkReminders(enabled: Boolean, frequency: Int? = null, behind: Boolean? = null) { context.settingsDataStore.edit {
        it[Keys.DRINK_ENABLED] = enabled
        frequency?.let { v -> if (v in listOf(60, 90, 120, 180)) it[Keys.FREQUENCY] = v }
        behind?.let { v -> it[Keys.BEHIND] = v }
    } }

    /** Only a real GET/read-back may populate these identity-bound hours. */
    suspend fun setRingHours(deviceId: String, startSec: Int, stopSec: Int) { context.settingsDataStore.edit {
        if (it[Keys.PAIRED_ID] == deviceId) {
            it[Keys.RING_ID] = deviceId
            it[Keys.RING_START] = startSec
            it[Keys.RING_STOP] = stopSec
        }
    } }

    private fun clearRing(p: androidx.datastore.preferences.core.MutablePreferences) {
        p.remove(Keys.RING_ID); p.remove(Keys.RING_START); p.remove(Keys.RING_STOP)
        p[Keys.DRINK_ENABLED] = false
    }

    private fun Preferences.toSettings(): AppSettings = AppSettings(
        pairedDeviceName = this[Keys.PAIRED_NAME],
        pairedDeviceIdHex = this[Keys.PAIRED_ID],
        batteryAlertPercent = this[Keys.BATTERY_ALERT] ?: DEFAULT_BATTERY_ALERT,
        batteryCriticalPercent = this[Keys.BATTERY_CRITICAL] ?: DEFAULT_BATTERY_CRITICAL,
        healthSyncEnabled = this[Keys.HEALTH_SYNC] ?: false,
        bottleProfileId = this[Keys.BOTTLE_PROFILE] ?: BottleProfile.DEFAULT.id,
        customCoefficients = this[Keys.CUSTOM_COEFFICIENTS]?.let(::parseCoefficients),
        lastSyncMs = this[Keys.LAST_SYNC],
        lastCapBottleSizeMl = this[Keys.LAST_CAP_BOTTLE_SIZE],
        firedBatteryThresholds = this[Keys.FIRED_BATTERY_THRESHOLDS]
            ?.split(',')?.mapNotNull { it.trim().toIntOrNull() }?.toSet() ?: emptySet(),
        backgroundSyncEnabled = this[Keys.BACKGROUND_SYNC] ?: true,
        lastBackgroundRunMs = this[Keys.LAST_BACKGROUND_RUN],
        lastBackgroundOutcome = this[Keys.LAST_BACKGROUND_OUTCOME],
        consecutiveCapMisses = this[Keys.CONSECUTIVE_CAP_MISSES] ?: 0,
        appearance = this[Keys.APPEARANCE] ?: "system",
        dailyTargetUseEstimate = this[Keys.USE_ESTIMATE] ?: true,
        dailyTargetOverrideMl = this[Keys.TARGET],
        manualWeightKg = this[Keys.WEIGHT]?.toDoubleOrNull()?.takeIf { it.isFinite() && it in 20.0..300.0 },
        manualSex = this[Keys.SEX],
        historyRange = this[Keys.HISTORY_RANGE] ?: "7d",
        historyChartType = this[Keys.CHART] ?: "bars",
        historyYAxis = this[Keys.AXIS] ?: "auto",
        drinkRemindersEnabled = this[Keys.DRINK_ENABLED] ?: false,
        drinkReminderFrequencyMinutes = this[Keys.FREQUENCY] ?: 120,
        drinkReminderOnlyWhenBehind = this[Keys.BEHIND] ?: true,
        ringDeviceId = this[Keys.RING_ID],
        lastRingStartSec = this[Keys.RING_START],
        lastRingStopSec = this[Keys.RING_STOP],
    )

    private fun parseCoefficients(raw: String): DoubleArray? =
        raw.split(',').mapNotNull { it.trim().toDoubleOrNull() }.toDoubleArray().takeIf { it.size == 5 }

    companion object {
        const val DEFAULT_BATTERY_ALERT = 10
        const val DEFAULT_BATTERY_CRITICAL = 5
        const val MIN_BATTERY_THRESHOLD = 1
        const val MAX_BATTERY_THRESHOLD = 50
    }
}
