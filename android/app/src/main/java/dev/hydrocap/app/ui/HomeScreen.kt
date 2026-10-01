package dev.hydrocap.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.hydrocap.app.data.DrinkEvent
import dev.hydrocap.app.sync.SyncStatus
import dev.hydrocap.app.ui.theme.WaterBlue
import dev.hydrocap.app.ui.theme.RoundedNumbers
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(state: HomeUiState, onRefresh: () -> Unit, onShowAll: () -> Unit) {
    val syncing = state.syncStatus is SyncStatus.Running
    PullToRefreshBox(isRefreshing = syncing, onRefresh = onRefresh, modifier = Modifier.fillMaxSize()) {
        LazyColumn(contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp), modifier = Modifier.fillMaxSize().testTag("home")) {
            item { PageHeader("LARQ iQ", state.settings?.pairedDeviceIdHex?.let { "Serial $it" } ?: "No cap paired") }
            item {
                Text(when (val status = state.syncStatus) {
                    is SyncStatus.Running -> if (state.initialImportRunning) "Importing saved drinks…" else "Syncing · ${status.step}"
                    is SyncStatus.Failed -> "Sync failed · ${status.reason}"
                    else -> state.settings?.lastSyncMs?.let { "Last synced ${relativeAge(it, state.now)}" } ?: "Nothing synced yet"
                }, style = MaterialTheme.typography.bodySmall, color = if (state.syncStatus is SyncStatus.Failed) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (state.tofCount > 0 || state.battery != null || state.todayEvents.isNotEmpty()) {
                item {
                    ContentCard(Modifier.fillMaxWidth().testTag("today-card")) {
                        CardTitle("Today", HydroGlyph.DROP)
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            // Reserve the left metric group as one box. A fill=false
                            // weighted number directly in this outer Row leaves its
                            // unused width after the goal instead of right-aligning it.
                            Row(Modifier.weight(1f), verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(ml(state.todayMl), fontSize = 56.sp, fontFamily = RoundedNumbers, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f, false), maxLines = 1)
                                Text("ml", fontSize = 18.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                            }
                            Text("of ${liters(state.targetMl)}", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        val progress = state.todayMl/state.targetMl
                        WaterProgress(progress)
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text("${state.todayEvents.size} drink${if (state.todayEvents.size == 1) "" else "s"}", style = MaterialTheme.typography.bodySmall)
                            Text("${(progress*100).roundToInt()} %", style = MaterialTheme.typography.bodySmall)
                        }
                        Text(state.targetCaption, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                item { HomeGaugeCards(state) }
                item {
                    ContentCard(Modifier.fillMaxWidth()) {
                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                            CardTitle("Today's drinks", HydroGlyph.LIST)
                            Spacer(Modifier.weight(1f))
                            TextButton(onClick = onShowAll) { Text("Show all") }
                        }
                        if (state.todayEvents.isEmpty()) Text("No drinks today yet. They appear after a sync.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        state.todayEvents.take(8).forEachIndexed { index, event ->
                            DrinkRow(event)
                            if (index < minOf(state.todayEvents.size,8)-1) HorizontalDivider()
                        }
                        if (state.todayEvents.size > 8) Text("${state.todayEvents.size - 8} more today", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
            } else item {
                ContentCard(Modifier.fillMaxWidth()) {
                    BottleGauge(if (state.initialImportRunning) .5 else null, Modifier.size(32.dp,64.dp))
                    Text(if (state.initialImportRunning) "Your bottle is connected" else "Nothing synced yet", style = MaterialTheme.typography.titleMedium)
                    if (state.initialImportRunning) {
                        LinearProgressIndicator(Modifier.fillMaxWidth())
                        Text("You can use the app while your history loads. Keep the bottle nearby.", style = MaterialTheme.typography.bodyMedium)
                    } else Text("Keep the cap nearby and pull down to sync. Saved drinks will appear here.", style = MaterialTheme.typography.bodyMedium)
                    Text(state.targetCaption, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            state.dataError?.let { error -> item { Text(error, color = MaterialTheme.colorScheme.error) } }
        }
    }
}

/** Intrinsic row + stretch: both cards have exactly the same drawn height, including enlarged text. */
@Composable
fun HomeGaugeCards(state: HomeUiState) {
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).testTag("gauge-row"), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
        ContentCard(Modifier.weight(1f).fillMaxHeight().heightIn(min = 180.dp).testTag("bottle-card")) {
            CardTitle("Bottle", HydroGlyph.BOTTLE)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BottleGauge(state.fill?.percent?.div(100), Modifier.size(36.dp,76.dp))
                Column(Modifier.weight(1f)) {
                    Text(state.fill?.let { ml(it.ml) } ?: "—", fontSize = 28.sp, fontFamily = RoundedNumbers, fontWeight = FontWeight.Bold, maxLines = 1)
                    Text(state.fill?.let { "ml · ${it.percent.roundToInt()} %" } ?: "no reading", style = MaterialTheme.typography.labelSmall)
                }
            }
            Spacer(Modifier.weight(1f))
            Text(state.fill?.let { "last reading ${formatTime(it.timestampSec*1000)}" } ?: "Appears after a sync", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        ContentCard(Modifier.weight(1f).fillMaxHeight().heightIn(min = 180.dp).testTag("battery-card")) {
            CardTitle("Battery", HydroGlyph.BOLT)
            val percent = state.liveBattery ?: state.battery?.percent
            val critical = state.settings?.batteryCriticalPercent ?: 5
            val low = state.settings?.batteryAlertPercent ?: 10
            val color = when { percent == null -> MaterialTheme.colorScheme.onSurfaceVariant; percent <= critical -> Color(0xFFFF453A); percent <= low -> Color(0xFFFF9F0A); else -> WaterBlue }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                BatteryGauge(percent, color, Modifier.size(64.dp))
                Column(Modifier.weight(1f)) {
                    if (percent != null) Text("%", fontSize = 28.sp, fontFamily = RoundedNumbers, fontWeight = FontWeight.Bold, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(when { percent == null -> "No data"; percent <= critical -> "Charge now"; percent <= low -> "Low"; else -> "Good" }, style = MaterialTheme.typography.labelSmall, color = color)
                }
            }
            Spacer(Modifier.weight(1f))
            Text(state.battery?.let { "measured ${formatTime(it.timestamp*1000)}" } ?: "Appears after a sync", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
@Composable
fun DrinkRow(event: DrinkEvent) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp).heightIn(min = 36.dp), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
        Text(formatTime(event.timestamp*1000))
        Text("${ml(event.volumeMl)} ml", fontWeight = FontWeight.SemiBold)
    }
}
@Composable
fun AllDrinksScreen(snapshot: DrinkSnapshot, onBack: () -> Unit) {
    val groups = snapshot.events.groupBy { Instant.ofEpochSecond(it.timestamp).atZone(ZoneId.systemDefault()).toLocalDate() }.toSortedMap(compareByDescending { it })
    LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { PageHeader("All drinks", onBack = onBack) }
        if (!snapshot.loaded) item { CircularProgressIndicator() }
        snapshot.error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
        if (snapshot.loaded && groups.isEmpty() && snapshot.error == null) item { ContentCard(Modifier.fillMaxWidth()) { Text("No drinks yet"); Text("Drinks appear here after a sync.") } }
        items(groups.entries.toList()) { (date, events) ->
            ContentCard(Modifier.fillMaxWidth()) {
                ValueRow(date.format(DateTimeFormatter.ofPattern("d MMM yyyy")), "${ml(events.sumOf { it.volumeMl })} ml")
                events.sortedByDescending { it.timestamp }.forEach { DrinkRow(it) }
            }
        }
    }
}
fun relativeAge(ms: Long, now: Instant): String {
    val minutes = ((now.toEpochMilli()-ms)/60_000).coerceAtLeast(0)
    return when { minutes < 1 -> "just now"; minutes < 60 -> "$minutes min ago"; minutes < 1440 -> "${minutes/60} h ago"; else -> "${minutes/1440} d ago" }
}
