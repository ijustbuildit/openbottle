package dev.hydrocap.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import dev.hydrocap.app.ble.DiscoveredCap
import kotlinx.coroutines.delay

@Composable
fun ScanScreen(state: ScanUiState, bluetoothAllowed: Boolean, paired: Boolean, onStartScan: () -> Unit, onSelect: (DiscoveredCap) -> Unit, onBluetooth: () -> Unit, onSettings: () -> Unit, onBack: () -> Unit) {
    var wakeHint by remember { mutableStateOf(false) }
    LaunchedEffect(state.scanning) { if (state.scanning) { wakeHint = false; delay(20_000); wakeHint = true } }
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { PageHeader("Find your bottle", onBack = if (paired) onBack else null, trailing = if (paired) null else ({ OnboardingStepIndicator(3) })) }
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Column(Modifier.weight(1f)) {
                    Text(if (state.pairingId != null) "Connecting…" else if (state.scanning) "Searching…" else "Search stopped", style = MaterialTheme.typography.titleMedium)
                    Text("Tap your cap when it shows up", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                if (state.scanning || state.pairingId != null) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
            }
        }
        if (!bluetoothAllowed) item { ContentCard(Modifier.fillMaxWidth()) {
            Text("Bluetooth access is required"); Text("Allow access to find the cap. If Android no longer asks, open Settings.", style = MaterialTheme.typography.bodySmall)
            TextButton(onClick = onBluetooth) { Text("Allow Bluetooth") }; TextButton(onClick = onSettings) { Text("Open Settings") }
        } }
        state.error?.let { error -> item { ContentCard(Modifier.fillMaxWidth()) { Text(error, color = MaterialTheme.colorScheme.error); TextButton(onClick = onStartScan) { Text("Retry") } } } }
        items(state.caps, key = { it.address }) { cap ->
            ContentCard(Modifier.fillMaxWidth().clickable(enabled = state.pairingId == null) { onSelect(cap) }.semantics { role = Role.Button; contentDescription = "Connect ${cap.name ?: "cap"}" }) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    HydroIcon(HydroGlyph.BOTTLE, Modifier.size(36.dp,44.dp))
                    Column(Modifier.weight(1f)) { Text("LARQ iQ", style = MaterialTheme.typography.titleMedium); Text(cap.deviceIdHex?.let { "Serial $it" } ?: cap.name ?: "Cap", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    if (state.pairingId == cap.address) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp)
                    else Text("${cap.rssi} dBm", style = MaterialTheme.typography.labelSmall)
                }
                if (state.pairingId == cap.address) Text("Connecting…", style = MaterialTheme.typography.bodySmall)
            }
        }
        if (state.caps.isEmpty() && state.pairingId == null && (wakeHint || !state.scanning)) item { ContentCard(Modifier.fillMaxWidth()) {
            Text("No cap found yet", style = MaterialTheme.typography.titleMedium)
            Text("Open the flap of your bottle once to wake it, then keep it next to the phone.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            OutlinedButton(onClick = onStartScan, enabled = bluetoothAllowed && !state.scanning) { Text("Scan again") }
        } }
    }
}
