package dev.hydrocap.app.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.hydrocap.app.debug.DebugEntry
import dev.hydrocap.app.sync.SyncStatus
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Full approved Debug form; logs are real, all synthetic tests render through separate fixtures. */
@Composable
fun DebugScreen(entries: List<DebugEntry>, busy: Boolean, backgroundLine: String, onCopy: () -> Unit,
    onLiveTof: () -> Unit, onReadAll: () -> Unit, onScan: () -> Unit, onClear: () -> Unit, onBack: () -> Unit,
    home: HomeUiState = HomeUiState(), onSync: () -> Unit = {}, onReadReminder: () -> Unit = {}, liveTof: Pair<Int,Int>? = null) {
    var copied by remember {mutableStateOf(false)}
    val scope=rememberCoroutineScope()
    LazyColumn(Modifier.fillMaxSize(),contentPadding=PaddingValues(16.dp),verticalArrangement=Arrangement.spacedBy(16.dp)) {
        item { PageHeader("Debug",onBack=onBack) }
        item { FormSection("Actions") {
            DebugAction("Scan 20 s",HydroGlyph.SIGNAL,!busy,onScan)
            DebugAction("Sync now",HydroGlyph.RELOAD,!busy,onSync)
            DebugAction("Live ToF",HydroGlyph.BOTTLE,!busy,onLiveTof)
            DebugAction("Read all settings",HydroGlyph.LIST,!busy,onReadAll)
            DebugAction("Read reminder",HydroGlyph.RING,!busy,onReadReminder)
            if (busy) { LinearProgressIndicator(Modifier.fillMaxWidth()); Text("Cap job in progress…",style=MaterialTheme.typography.bodySmall) }
            liveTof?.let { ValueRow("Live ToF","${it.first} mm, ${it.second} kcps") }
        } }
        item { FormSection("State") {
            ValueRow("Sync",when(val status=home.syncStatus) { is SyncStatus.Running -> status.step; is SyncStatus.Failed -> status.reason; is SyncStatus.Done -> "Done"; else -> "Idle" })
            ValueRow("Connection",home.connection.javaClass.simpleName)
            ValueRow("Stored readings",home.tofCount.toString())
            home.settings?.lastCapBottleSizeMl?.let { ValueRow("Cap reports","$it ml") }
            ValueRow("Profile",home.settings?.bottleProfile()?.label ?: "—")
            home.fill?.let { ValueRow("Last reading","${it.distanceMm} mm, ${it.kcps} kcps at ${formatTime(it.timestampSec*1000)}") }
        } }
        item { FormSection("Last background run") { Text(backgroundLine,style=MaterialTheme.typography.bodySmall); ValueRow("Misses in a row",(home.settings?.consecutiveCapMisses ?: 0).toString()) } }
        item { FormSection("Log actions","File: files/debug-log.txt") {
            TextButton(onClick={onCopy();copied=true;scope.launch {delay(2_000);copied=false}},modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) { Text(if(copied) "Copied" else "Copy log") }
            TextButton(onClick=onClear,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) {Text("Clear view")}
        } }
        item { Text("Log (${entries.size} lines)",style=MaterialTheme.typography.labelLarge,color=MaterialTheme.colorScheme.onSurfaceVariant) }
        if(entries.isEmpty()) item { ContentCard(Modifier.fillMaxWidth()) {Text("empty",color=MaterialTheme.colorScheme.onSurfaceVariant)} }
        items(entries.takeLast(300).reversed()) { entry -> ContentCard(Modifier.fillMaxWidth()) { SelectionContainer {Text(entry.format(),fontFamily=FontFamily.Monospace,fontSize=11.sp,lineHeight=14.sp)} } }
    }
}
@Composable
private fun DebugAction(title:String,glyph:HydroGlyph,enabled:Boolean,action:()->Unit) {
    TextButton(onClick=action,enabled=enabled,modifier=Modifier.fillMaxWidth().heightIn(min=48.dp)) {
        HydroIcon(glyph,Modifier.size(20.dp)); Spacer(Modifier.width(10.dp)); Text(title,modifier=Modifier.weight(1f))
    }
}
