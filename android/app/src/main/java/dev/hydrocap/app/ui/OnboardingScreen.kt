package dev.hydrocap.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import dev.hydrocap.app.health.HealthBodyState
import dev.hydrocap.app.health.HealthConnectSupport
import dev.hydrocap.app.domain.HydrationTarget

@Composable
fun OnboardingStepIndicator(step: Int) {
    Box(Modifier.widthIn(min = 80.dp).heightIn(min = 32.dp).testTag("onboarding-step").semantics { contentDescription = "Step $step of 3" }, contentAlignment = Alignment.Center) {
        Text("$step of 3", style = MaterialTheme.typography.labelMedium, maxLines = 1, softWrap = false, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable
fun OnboardingWelcomeActions(available: Boolean, busy: Boolean, onConnect: () -> Unit, onSkip: () -> Unit, onInstall: () -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 12.dp, bottom = 20.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Button(onClick = onConnect, enabled = available && !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp).testTag("connect-health")) {
            if (busy) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp)
            Text("Connect Health Connect", fontWeight = FontWeight.SemiBold)
        }
        if (!available) TextButton(onClick = onInstall, modifier = Modifier.fillMaxWidth()) { Text("Install or update Health Connect") }
        TextButton(onClick = onSkip, enabled = !busy, modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp).testTag("not-now")) { Text("Not now") }
    }
}
@Composable
fun OnboardingScreen(body: HealthBodyState, busy: Boolean, onHealth: () -> Unit, onSkip: () -> Unit, onInstall: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            PageHeader("Welcome", trailing = { OnboardingStepIndicator(1) })
            Spacer(Modifier.height(24.dp))
            HydroIcon(HydroGlyph.BOTTLE, Modifier.size(64.dp))
            Text("Track your bottle", style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            Text("HydroCap reads your LARQ iQ cap and can write drinks to Health Connect. Available weight helps estimate an editable daily drink goal.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("No HydroCap account or server. Health Connect follows your system settings.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("The cap needs no pairing code.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (body.availability != HealthConnectSupport.Availability.AVAILABLE) Text(if (body.availability == HealthConnectSupport.Availability.UPDATE_REQUIRED) "Health Connect needs an update. You can continue without it." else "Health Connect is not available here. You can continue without it.", style = MaterialTheme.typography.bodySmall)
        }
        OnboardingWelcomeActions(body.availability == HealthConnectSupport.Availability.AVAILABLE, busy, onHealth, onSkip, onInstall)
    }
}
@Composable
fun OptionalScreen(state: SettingsUiState, permissions: PermissionUiState, onHealth: () -> Unit, onHealthSettings: () -> Unit,
    onBluetooth: () -> Unit, onNotifications: () -> Unit, onSettings: () -> Unit, onBody: (Double?, String?) -> Unit, onContinue: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            PageHeader("Optional", trailing = { OnboardingStepIndicator(2) })
            Text("A few optional things. You can leave these off and change them later in Settings.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (!state.body.hydrationPermission) OptionalCard("Health Connect", if (state.body.availability == HealthConnectSupport.Availability.AVAILABLE) "Writing water is not allowed. Reading weight is optional and separate." else "Install or update Health Connect, or leave it off.") {
                TextButton(onClick = onHealth) { Text("Connect") }; TextButton(onClick = onHealthSettings) { Text("Change access in Health Connect") }
            }
            if (!permissions.notifications) OptionalCard("Notifications", "Needed for battery alerts and drink reminders.") {
                TextButton(onClick = onNotifications) { Text("Allow") }; TextButton(onClick = onSettings) { Text("Open Settings") }
            }
            if (!permissions.bluetooth) OptionalCard("Bluetooth", "Bluetooth access is required to find your cap. Allow access or change it in Android Settings.") {
                TextButton(onClick = onBluetooth) { Text("Allow Bluetooth") }; TextButton(onClick = onSettings) { Text("Open Settings") }
            }
            if (state.body.weightKg == null) ContentCard(Modifier.fillMaxWidth()) {
                Text("Daily target", style = MaterialTheme.typography.titleMedium)
                Text("Weight is not available from Health Connect. Add only the missing values, or leave them blank. The goal is editable in Settings.", style = MaterialTheme.typography.bodySmall)
                ManualBodyFields(state, onBody)
                Text(state.targetCaption, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        Button(onClick = onContinue, modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(bottom = 20.dp, top = 12.dp).heightIn(min = 50.dp)) { Text("Continue") }
    }
}
@Composable
private fun OptionalCard(title: String, description: String, actions: @Composable ColumnScope.() -> Unit) {
    ContentCard(Modifier.fillMaxWidth()) { Text(title, style = MaterialTheme.typography.titleMedium); Text(description, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant); actions() }
}
@Composable
fun ManualBodyFields(state: SettingsUiState, onBody: (Double?, String?) -> Unit) {
    var weight by remember(state.settings?.manualWeightKg) { mutableStateOf(state.settings?.manualWeightKg?.let { if (it % 1.0 == 0.0) it.toInt().toString() else it.toString() } ?: "") }
    val sex = state.settings?.manualSex
    if (state.body.weightKg == null) {
        OutlinedTextField(weight, onValueChange = { value ->
            weight = value
            val number = value.trim().replace(',','.').toDoubleOrNull()
            if (value.isBlank() || number != null && number.isFinite() && number in 20.0..300.0) onBody(number, sex)
        }, label = { Text("Weight (optional) · kg") }, singleLine = true,
            keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal), modifier = Modifier.fillMaxWidth())
    }
    Text("Sex (optional)", style = MaterialTheme.typography.bodyMedium)
    ChoicePill(listOf("Skip","Female","Male","Other"), listOf(null,"female","male","other").indexOf(sex).coerceAtLeast(0), { onBody(state.settings?.manualWeightKg, listOf(null,"female","male","other")[it]) }, Modifier.fillMaxWidth())
    Text("Health Connect does not provide biological sex. This optional manual fallback is used only without weight.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}
