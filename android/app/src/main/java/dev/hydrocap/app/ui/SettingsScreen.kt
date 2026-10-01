package dev.hydrocap.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import dev.hydrocap.app.BuildConfig
import dev.hydrocap.app.domain.BottleProfile
import dev.hydrocap.app.domain.HydrationTarget
import dev.hydrocap.app.health.HealthConnectSupport
import dev.hydrocap.app.notify.DrinkReminderPlanner
import dev.hydrocap.app.notify.ringWindow

@Composable
fun SettingsScreen(state: SettingsUiState, busy: Boolean, onAppearance: (String) -> Unit, onRing: () -> Unit, onProfile: () -> Unit,
    onTarget: (Boolean,Int?) -> Unit, onBody: (Double?,String?) -> Unit, onBattery: (Int,Int) -> Unit, onHealthToggle: (Boolean) -> Unit,
    onHealthSettings: () -> Unit, onHealthConnect: () -> Unit, onWriteHealth: () -> Unit, onDrink: (Boolean,Int?,Boolean?) -> Unit,
    onNotifications: () -> Unit, onBackground: (Boolean) -> Unit, onScan: () -> Unit, onForget: () -> Unit, onDebug: () -> Unit) {
    val s = state.settings ?: return
    var forgetting by remember { mutableStateOf(false) }
    var changing by remember { mutableStateOf(false) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { PageHeader("Settings") }
        item { FormSection("Appearance") { ChoicePill(listOf("System","Light","Dark"), listOf("system","light","dark").indexOf(s.appearance).coerceAtLeast(0), { onAppearance(listOf("system","light","dark")[it]) }, Modifier.fillMaxWidth()) } }
        item { FormSection("Bottle", "The ring settings are read from and written to the cap. The cap's reported size is only information; the profile is a setting.") {
            ValueRow("Reminder ring & quiet hours", "", onRing); HorizontalDivider(); ValueRow("Profile", profileTitle(s.bottleProfileId), onProfile)
            state.profileMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        } }
        item { FormSection("Daily target", if (s.dailyTargetUseEstimate) HydrationTarget.estimateExplanation else "Your own value. Used on Home, in History and for drink reminders.") {
            ToggleRow("Use Health Connect estimate", s.dailyTargetUseEstimate) { onTarget(it, s.dailyTargetOverrideMl ?: state.targetMl) }
            if (s.dailyTargetUseEstimate) {
                ValueRow("Daily target", liters(state.targetMl)); Text(state.targetCaption, style = MaterialTheme.typography.labelSmall)
                ManualBodyFields(state, onBody)
            } else {
                StepperRow("Daily target", liters(state.targetMl), { onTarget(false, state.targetMl-50) }, { onTarget(false,state.targetMl+50) })
            }
        } }
        item { FormSection("Reminders", "Local notifications between your cap's verified reminder-ring hours. Intake is the last synced bottle data, not a live measurement. Android may delay notifications.") {
            ToggleRow("Remind me to drink", s.drinkRemindersEnabled, enabled = !state.updatingReminders || s.drinkRemindersEnabled) { onDrink(it,null,null) }
            if (state.updatingReminders) { LinearProgressIndicator(Modifier.fillMaxWidth()); Text("Reading the cap's ring hours…", style = MaterialTheme.typography.bodySmall) }
            state.drinkMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error); TextButton(onClick = onNotifications) { Text("Notification settings") } }
            if (s.drinkRemindersEnabled) {
                Text("Frequency", style = MaterialTheme.typography.bodyMedium)
                ChoicePill(listOf("1 h","1.5 h","2 h","3 h"), DrinkReminderPlanner.frequencyChoicesMinutes.indexOf(s.drinkReminderFrequencyMinutes).coerceAtLeast(0), { onDrink(true,DrinkReminderPlanner.frequencyChoicesMinutes[it],null) }, Modifier.fillMaxWidth())
                ToggleRow("Only when behind target", s.drinkReminderOnlyWhenBehind) { onDrink(true,null,it) }
                ValueRow("Window", s.ringWindow()?.let { DrinkReminderPlanner.windowLabel(it).removePrefix("Between ") } ?: "Hours unavailable")
            }
        } }
        item { FormSection("Battery alerts", "Critical stays below the alert level. Changing a value re-arms both alerts.") {
            StepperRow("Alert at", "${s.batteryAlertPercent} %", { onBattery((s.batteryAlertPercent-1).coerceAtLeast(2),s.batteryCriticalPercent) }, { onBattery((s.batteryAlertPercent+1).coerceAtMost(50),s.batteryCriticalPercent) })
            StepperRow("Critical at", "${s.batteryCriticalPercent} %", { onBattery(s.batteryAlertPercent,(s.batteryCriticalPercent-1).coerceAtLeast(1)) }, { onBattery(s.batteryAlertPercent,(s.batteryCriticalPercent+1).coerceAtMost(s.batteryAlertPercent-1)) })
        } }
        item { FormSection("Health Connect", "${state.healthTrackedCount} records written by HydroCap. Reading weight is optional and separate from writing water. Weight is checked in the last 30 days; biological sex is an optional manual fallback.") {
            ToggleRow("Write drinks to Health Connect", s.healthSyncEnabled, state.body.availability == HealthConnectSupport.Availability.AVAILABLE) { onHealthToggle(it) }
            ValueRow("Status", when { state.body.availability != HealthConnectSupport.Availability.AVAILABLE -> "Not available"; !s.healthSyncEnabled -> "Off"; state.body.hydrationPermission -> "Allowed"; else -> "Permission missing" })
            ValueRow("Weight", state.body.weightStatus)
            TextButton(onClick = onHealthConnect) { Text(if (state.body.availability == HealthConnectSupport.Availability.AVAILABLE) "Connect Health Connect" else "Install or update Health Connect") }
            TextButton(onClick = onHealthSettings) { Text("Change access in Health Connect") }
            TextButton(onClick = onWriteHealth, enabled = s.healthSyncEnabled && state.body.hydrationPermission && state.healthWrite !is HealthWriteStatus.Running) { Text("Write all drinks to Health now") }
            when (val result = state.healthWrite) {
                HealthWriteStatus.Running -> LinearProgressIndicator(Modifier.fillMaxWidth())
                HealthWriteStatus.Denied -> Text("Hydration write permission missing. Reading weight remains optional.", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                is HealthWriteStatus.Done -> Text(result.result.error ?: "${result.result.inserted} inserted · ${result.result.updated} updated · ${result.result.skipped} unchanged", style = MaterialTheme.typography.bodySmall, color = if (result.result.error == null) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.error)
                else -> Unit
            }
        } }
        item { FormSection("Background sync", "Android schedules a sync roughly every 15 minutes when battery allows. Android decides when this actually runs.") {
            ToggleRow("Sync in the background", s.backgroundSyncEnabled, onChange = onBackground)
            ValueRow("Last run", s.lastBackgroundRunMs?.let { "${formatDateTime(it)} · ${s.lastBackgroundOutcome ?: ""}" } ?: "Never")
        } }
        item { FormSection("Device") {
            ValueRow("Name", s.pairedDeviceName ?: "No cap paired"); ValueRow("Serial", s.pairedDeviceIdHex ?: "—")
            TextButton(onClick = { changing = true }, enabled = !busy) { Text("Pair a different bottle") }
            TextButton(onClick = { forgetting = true }, enabled = s.hasPairedDevice && !busy) { Text("Forget bottle", color = MaterialTheme.colorScheme.error) }
            if (busy) Text("Finish the current cap job before changing bottles.", style = MaterialTheme.typography.labelSmall)
        } }
        item { FormSection("Debug") { ValueRow("Debug log & actions", "", onDebug) } }
        item { FormSection("About", "HydroCap is not affiliated with, endorsed by, or supported by BRITA SE or LARQ, Inc. BRITA and LARQ are trademarks used only to identify compatible hardware.") {
            ValueRow("Version", BuildConfig.VERSION_NAME); Text("No HydroCap account or server. Health Connect follows your system settings.", style = MaterialTheme.typography.bodySmall)
        } }
    }
    if (forgetting || changing) AlertDialog(onDismissRequest = { forgetting = false; changing = false }, title = { Text(if (forgetting) "Forget this bottle?" else "Pair a different bottle?") },
        text = { Text("Stored measurements stay on this phone. Changing the bottle clears its cached ring hours and turns off drink reminders.") },
        confirmButton = { TextButton(onClick = { if (forgetting) onForget() else onScan(); forgetting = false; changing = false }) { Text(if (forgetting) "Forget bottle" else "Find bottle", color = if (forgetting) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.primary) } },
        dismissButton = { TextButton(onClick = { forgetting = false; changing = false }) { Text("Cancel") } })
}
@Composable
fun FormSection(title: String, footer: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(title, style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp))
        ContentCard(Modifier.fillMaxWidth(), content)
        footer?.let { Text(it, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 16.dp)) }
    }
}
fun profileTitle(id: String): String = when (id) { BottleProfile.ID_680_CAL -> "680 ml, no filter (calibrated)"; BottleProfile.ID_680 -> "680 ml (LARQ curve)"; BottleProfile.ID_1000 -> "1000 ml (LARQ curve)"; else -> "Custom coefficients" }
@Composable
fun BottleProfileScreen(state: SettingsUiState, onSelect: (BottleProfile) -> Unit, onBack: () -> Unit) {
    val settings = state.settings ?: return
    val initial = settings.customCoefficients ?: BottleProfile.DEFAULT.coefficients
    val fields = remember { mutableStateListOf(*initial.map { it.toString() }.toTypedArray()) }
    var error by remember { mutableStateOf<String?>(null) }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { PageHeader("Bottle profile", onBack = onBack) }
        item { FormSection("Profiles", "Choosing a profile rebuilds every drink from the stored readings and reconciles Health Connect when enabled.") {
            listOf(BottleProfile.BODY_680_NO_FILTER_CAL, BottleProfile.BODY_680, BottleProfile.BODY_1000).forEach { profile ->
                ValueRow(profileTitle(profile.id), if (settings.bottleProfileId == profile.id) "✓" else "", { onSelect(profile) })
                Text(if (profile.id == BottleProfile.DEFAULT.id) "Default · measuring-cup fit; not independently validated" else "Community curve, unverified", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                HorizontalDivider()
            }
        } }
        item { FormSection("Custom", "V(d) = c0·d⁴ + c1·d³ + c2·d² + c3·d + c4, d = distance in mm.") {
            fields.forEachIndexed { i,value -> OutlinedTextField(value, { fields[i] = it }, label = { Text("c$i") }, singleLine = true, textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace), modifier = Modifier.fillMaxWidth()) }
            TextButton(onClick = {
                val values = fields.map { it.trim().toDoubleOrNull() }
                if (values.any { it == null || !it.isFinite() }) error = "A custom profile needs five finite numeric coefficients (c0…c4)."
                else { error = null; onSelect(BottleProfile(BottleProfile.ID_CUSTOM,"Custom",0,values.map { it!! }.toDoubleArray())) }
            }) { Text(if (settings.bottleProfileId == BottleProfile.ID_CUSTOM) "Custom coefficients ✓" else "Use custom coefficients") }
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        } }
        state.profileMessage?.let { item { Text(it, style = MaterialTheme.typography.bodySmall) } }
    }
}
