package dev.hydrocap.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.*
import androidx.compose.ui.unit.dp
import dev.hydrocap.app.domain.*
import dev.hydrocap.app.sync.ReminderStatus
import dev.hydrocap.app.ui.theme.WaterBlue

/** Draft preserves exact cap colour and the engine alone owns snooze/merge/write/read-back. */
data class ReminderForm(val mode: Int, val intervalSec: Int, val startSec: Int, val stopSec: Int, val color: RingColor,
    val dndMode: Int, val dndStartSec: Int, val dndStopSec: Int) {
    fun toPatch() = ReminderPatch(ReminderValues(mode,startSec,stopSec,if (mode == ReminderSettings.MODE_OFF) 0 else intervalSec,color), DndValues(dndMode,dndStartSec,dndStopSec))
    companion object {
        fun from(config: CapReminderConfig): ReminderForm {
            fun time(value: Int) = value.takeIf { it in 1..86400 } ?: 86400
            val r = config.reminder; val d = config.dnd
            return ReminderForm(r.mode, r.intervalSec.takeIf { it>0 } ?: 1800,time(r.startSec),time(r.stopSec),r.color,d.mode,time(d.startSec),time(d.stopSec))
        }
    }
}
@Composable
fun ReminderScreen(status: ReminderStatus, onRead: () -> Unit, onApply: (ReminderPatch) -> Unit, onBack: () -> Unit) {
    var baseline by remember { mutableStateOf<CapReminderConfig?>(null) }
    var draft by remember { mutableStateOf<ReminderForm?>(null) }
    var timeField by remember { mutableStateOf<Int?>(null) }
    var colorDialog by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { if (status !is ReminderStatus.Busy) onRead() }
    LaunchedEffect(status) { if (status is ReminderStatus.Loaded) { baseline = status.config; draft = ReminderForm.from(status.config) } }
    val busy = status is ReminderStatus.Busy
    val form = draft
    val resolved = if (form != null && baseline != null) ReminderRules.resolve(baseline!!,form.toPatch()) else null
    val problem = resolved?.let(ReminderRules::validate)
    fun normalized(c: CapReminderConfig) = if (c.reminder.mode == ReminderSettings.MODE_OFF) c.copy(reminder = c.reminder.copy(intervalSec = 0)) else c
    val changed = resolved != null && baseline != null && normalized(resolved) != normalized(ReminderRules.resolve(baseline!!,ReminderPatch(ReminderValues(),DndValues())))
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            PageHeader("Ring", when (status) { is ReminderStatus.Busy -> if (status.applying) "Writing to the cap…" else "Reading from the cap…"; is ReminderStatus.Loaded -> "Read from the cap ${formatTime(status.atMs)}"; else -> "Reminder & quiet hours" }, onBack)
            if (status is ReminderStatus.Failed) ContentCard(Modifier.fillMaxWidth()) {
                Text(if (status.applying) "Could not store the settings" else "Could not read the cap", color = MaterialTheme.colorScheme.error)
                Text(if (status.reason.contains("already running")) "The cap is busy with a sync. Try again in a moment." else status.reason, style = MaterialTheme.typography.bodySmall)
                Text("Wake the cap with a tap and keep it nearby.", style = MaterialTheme.typography.labelSmall)
                TextButton(onClick = onRead) { Text("Retry") }
            }
            if (form == null && status !is ReminderStatus.Failed) ContentCard(Modifier.fillMaxWidth()) { LinearProgressIndicator(Modifier.fillMaxWidth()); Text("Reading actual cap settings…", style = MaterialTheme.typography.bodySmall) }
            if (form != null) {
                ContentCard(Modifier.fillMaxWidth()) {
                    CardTitle("Reminder ring")
                    Text(when(form.mode) { 0 -> "The ring stays dark."; 1 -> "The ring lights up every interval."; else -> "The ring lights up only when you have not drunk for one interval." }, style = MaterialTheme.typography.bodySmall)
                    ChoicePill(listOf("Off","Always","Adaptive"), form.mode, { draft = form.copy(mode = it) }, Modifier.fillMaxWidth(), !busy)
                }
                if (form.mode != ReminderSettings.MODE_OFF) {
                    ContentCard(Modifier.fillMaxWidth()) {
                        CardTitle("Interval")
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            (ReminderRules.INTERVAL_CHOICES_MINUTES + listOf(form.intervalSec/60)).distinct().sorted().forEach { minutes ->
                                FilterChip(form.intervalSec == minutes*60, { draft = form.copy(intervalSec = minutes*60) }, enabled = !busy, label = { Text("$minutes min") })
                            }
                        }
                    }
                    ContentCard(Modifier.fillMaxWidth()) {
                        CardTitle("Active hours")
                        ValueRow("From", ReminderRules.formatSecOfDay(form.startSec), if (busy) null else ({ timeField = 0 }))
                        HorizontalDivider()
                        ValueRow("Until", ReminderRules.formatSecOfDay(form.stopSec), if (busy) null else ({ timeField = 1 }))
                    }
                    ContentCard(Modifier.fillMaxWidth()) {
                        CardTitle("Ring colour")
                        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                            ColorSwatch("Firmware default", RingColor.FIRMWARE_DEFAULT, form.color.isFirmwareDefault, !busy) { draft = form.copy(color = RingColor.FIRMWARE_DEFAULT) }
                            RingColor.PRESETS.forEach { (name,color) -> ColorSwatch(name,color,form.color == color,!busy) { draft = form.copy(color = color) } }
                        }
                        ValueRow("Custom colour", if (form.color.isFirmwareDefault) "Default" else "RGB ${form.color.red255()}, ${form.color.green255()}, ${form.color.blue255()}", if (busy) null else ({ colorDialog = true }))
                        Text(if (form.color.isFirmwareDefault) "Firmware default is the cap's own colour, not black." else "Custom RGB colour is stored on the cap.", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                }
                ContentCard(Modifier.fillMaxWidth()) {
                    CardTitle("Quiet hours")
                    Text(when(form.dndMode) { 0 -> "The ring may light up at any time."; 1 -> "The ring stays dark between the hours below."; else -> "The ring stays dark outside the active hours." }, style = MaterialTheme.typography.bodySmall)
                    ChoicePill(listOf("Off","Auto","Custom"), when(form.dndMode) { 1 -> 2; 2 -> 1; else -> 0 }, { draft = form.copy(dndMode = listOf(0,2,1)[it]) }, Modifier.fillMaxWidth(), !busy)
                    if (form.dndMode == DndSettings.MODE_CUSTOM) {
                        ValueRow("Quiet from",ReminderRules.formatSecOfDay(form.dndStartSec),if (busy) null else ({timeField=2})); HorizontalDivider()
                        ValueRow("Quiet until",ReminderRules.formatSecOfDay(form.dndStopSec),if (busy) null else ({timeField=3}))
                    }
                }
                problem?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                if (status is ReminderStatus.Loaded && status.applied && !changed) Text("Cap stored the settings", color = Color(0xFF34C759), style = MaterialTheme.typography.bodySmall)
                TextButton(onClick = onRead, enabled = !busy) { Text("Read from the cap again") }
            }
        }
        Button(onClick = { form?.let { onApply(it.toPatch()) } }, enabled = !busy && form != null && changed && problem == null,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).padding(top = 12.dp,bottom = 20.dp).heightIn(min = 50.dp)) { Text(if ((status as? ReminderStatus.Busy)?.applying == true) "Writing…" else "Apply to cap") }
    }
    if (timeField != null && form != null) {
        val field = timeField!!
        val values = listOf(form.startSec,form.stopSec,form.dndStartSec,form.dndStopSec)
        SecOfDayPickerDialog(listOf("From","Until","Quiet from","Quiet until")[field],values[field],{timeField=null}) { sec ->
            draft = when(field) { 0 -> form.copy(startSec=sec); 1 -> form.copy(stopSec=sec); 2 -> form.copy(dndStartSec=sec); else -> form.copy(dndStopSec=sec) }; timeField = null
        }
    }
    if (colorDialog && form != null) CustomColorDialog(form.color,{colorDialog=false}) { draft = form.copy(color=it); colorDialog=false }
}
@Composable
private fun ColorSwatch(label: String, color: RingColor, selected: Boolean, enabled: Boolean, onClick: () -> Unit) {
    val accent = WaterBlue
    Box(Modifier.size(44.dp).clickable(enabled=enabled,onClick=onClick).semantics { contentDescription=label; this.selected=selected; role=Role.Button },contentAlignment=Alignment.Center) {
        Canvas(Modifier.size(30.dp)) {
            if (color.isFirmwareDefault) { drawCircle(Color.Gray, style=Stroke(1.5.dp.toPx())); drawLine(Color.Gray,Offset(size.width*.2f,size.height*.8f),Offset(size.width*.8f,size.height*.2f),2.dp.toPx()) }
            else drawCircle(Color(color.red,color.green,color.blue))
            if (selected) drawCircle(accent,radius=size.width/2+3.dp.toPx(),style=Stroke(2.dp.toPx()))
        }
    }
}
@Composable
private fun CustomColorDialog(initial: RingColor, onDismiss: () -> Unit, onColor: (RingColor) -> Unit) {
    var red by remember { mutableFloatStateOf(initial.red) }; var green by remember { mutableFloatStateOf(initial.green) }; var blue by remember { mutableFloatStateOf(initial.blue) }
    AlertDialog(onDismissRequest=onDismiss,title={Text("Custom colour")},text={Column {
        Box(Modifier.fillMaxWidth().height(40.dp).background(Color(red,green,blue),CircleShape))
        Text("Red ${(red*255).toInt()}"); Slider(red,{red=it},valueRange=0f..1f)
        Text("Green ${(green*255).toInt()}"); Slider(green,{green=it},valueRange=0f..1f)
        Text("Blue ${(blue*255).toInt()}"); Slider(blue,{blue=it},valueRange=0f..1f)
    }},confirmButton={TextButton(onClick={onColor(RingColor(red,green,blue))}) {Text("Use colour")}},dismissButton={TextButton(onClick=onDismiss) {Text("Cancel")}})
}
