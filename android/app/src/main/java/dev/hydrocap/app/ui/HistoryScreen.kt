package dev.hydrocap.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.hydrocap.app.data.AppSettings
import dev.hydrocap.app.domain.HistoryAggregation as History
import dev.hydrocap.app.ui.theme.WaterBlue
import dev.hydrocap.app.ui.theme.WaterGradient
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

@Composable
fun HistoryScreen(snapshot: DrinkSnapshot, settings: AppSettings?, now: Instant, targetMl: Int, onControls: (String?, String?, String?) -> Unit) {
    val range = History.Range.fromRawValue(settings?.historyRange ?: "7d") ?: History.Range.WEEK
    val zone = ZoneId.systemDefault()
    val buckets = remember(snapshot, range, now, zone) { History.buckets(snapshot.events, range, now, zone) }
    val summary = remember(snapshot, range, now, targetMl, zone) { History.summary(snapshot.events, range, now, zone, targetMl.toDouble()) }
    val events = remember(snapshot, range, now, zone) { History.eventsInRange(snapshot.events, range, now, zone) }
    val days = events.groupBy { Instant.ofEpochSecond(it.timestamp).atZone(zone).toLocalDate() }.filterValues { it.sumOf { e -> e.volumeMl } > 0 }.toSortedMap(compareByDescending { it })
    var menu by remember { mutableStateOf(false) }
    var selected by remember(range) { mutableStateOf<Int?>(null) }
    val chart = settings?.historyChartType ?: "bars"
    val fixedYAxis = range != History.Range.DAY && settings?.historyYAxis == "fixed"
    val upper = History.yUpperBound(buckets, targetMl.toDouble(), fixedYAxis, hourly = range == History.Range.DAY)
    val goalFootnote = if (History.showsGoalRule(targetMl.toDouble(), upper))
        "Dashed line = daily goal (${ml(targetMl.toDouble())} ml/day)."
        else if (targetMl > 0) "Daily goal: ${ml(targetMl.toDouble())} ml/day (above chart scale)."
        else "Daily goal is unavailable."
    LazyColumn(Modifier.fillMaxSize().testTag("history"), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item { PageHeader("History") }
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                ChoicePill(History.Range.entries.map { it.label }, range.ordinal, { onControls(History.Range.entries[it].rawValue, null, null) }, Modifier.weight(1f).testTag("history-ranges"))
                Box {
                    IconButton(onClick = { menu = true }, modifier = Modifier.size(48.dp).testTag("chart-menu")) { HydroIcon(HydroGlyph.HISTORY, Modifier.size(22.dp), "Chart type and y axis") }
                    DropdownMenu(menu, { menu = false }) {
                        listOf("bars" to "Bars", "line" to "Line", "area" to "Area").forEach { (value,label) -> DropdownMenuItem(text = { Text(if (chart == value) "✓ $label" else label) }, onClick = { onControls(null,value,null); menu = false }) }
                        HorizontalDivider()
                        if (range == History.Range.DAY) {
                            DropdownMenuItem(text = { Text("Y axis: Auto") }, onClick = {}, enabled = false)
                        } else {
                            listOf("auto" to "Auto", "fixed" to "Fixed to target").forEach { (value,label) -> DropdownMenuItem(text = { Text(if (settings?.historyYAxis == value) "✓ $label" else label) }, onClick = { onControls(null,null,value); menu = false }) }
                        }
                    }
                }
            }
        }
        item {
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SummaryTile(if (range == History.Range.DAY) "Today" else "Average", summary.averagePerDayMl?.let(::ml) ?: "—", if (range == History.Range.DAY) "ml" else "ml / day", Modifier.weight(1f).fillMaxHeight())
                SummaryTile("Best day", summary.bestDay?.let { ml(it.ml) } ?: "—", summary.bestDay?.day?.atZone(zone)?.format(DateTimeFormatter.ofPattern("d MMM")) ?: "no data", Modifier.weight(1f).fillMaxHeight())
                SummaryTile("On target", summary.daysOnTarget.toString(), if (summary.daysOnTarget == 1) "day" else "days", Modifier.weight(1f).fillMaxHeight())
            }
        }
        item {
            ContentCard(Modifier.fillMaxWidth()) {
                CardTitle(when (range) { History.Range.DAY -> "Today"; History.Range.WEEK -> "Last 7 days"; History.Range.MONTH -> "Last 30 days"; History.Range.QUARTER -> "Last 90 days"; History.Range.YEAR -> "Last year" })
                selected?.let { i -> buckets.getOrNull(i)?.let { bucket ->
                    Text(bucketLabel(bucket, range, zone), style = MaterialTheme.typography.labelMedium)
                    Text(bucket.averagePerDayMl?.let { "${ml(it)} ${if (range == History.Range.DAY) "ml / hour" else "ml / day"}" } ?: "No recorded drinks", fontWeight = FontWeight.SemiBold)
                    if (range != History.Range.DAY && bucket.recordedDayCount > 0) Text("Based on ${bucket.recordedDayCount} day${if (bucket.recordedDayCount == 1) "" else "s"} with drinks", style = MaterialTheme.typography.labelSmall)
                } }
                NativeHistoryChart(buckets, range, chart, targetMl.toDouble(), fixedYAxis, selected) { selected = it }
                Text(if (range == History.Range.DAY) "Today's recorded water by hour, in local time. Empty hours have no recorded drinks; the daily goal is not an hourly requirement."
                    else "Average ml/day. Days with 0 ml are excluded (${summary.recordedDayCount} days used). $goalFootnote${if (range.scrolls) " · swipe to scroll" else ""} · tap for values", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (snapshot.error != null) item { Text(snapshot.error, color = MaterialTheme.colorScheme.error) }
        else if (snapshot.loaded && days.isEmpty()) item { ContentCard(Modifier.fillMaxWidth()) { Text("No drinks in this range"); Text("Drinks appear here after a sync.", style = MaterialTheme.typography.bodySmall) } }
        items(days.entries.toList()) { (date, drinks) -> ContentCard(Modifier.fillMaxWidth()) {
            ValueRow(date.format(DateTimeFormatter.ofPattern("d MMM yyyy")), "${ml(drinks.sumOf { it.volumeMl })} ml")
            drinks.sortedByDescending { it.timestamp }.forEachIndexed { index, event -> DrinkRow(event); if (index < drinks.size-1) HorizontalDivider() }
        } }
    }
}
@Composable
private fun SummaryTile(title: String, value: String, unit: String, modifier: Modifier) {
    Surface(modifier, shape = androidx.compose.foundation.shape.RoundedCornerShape(16.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(value, fontSize = 22.sp, fontFamily = dev.hydrocap.app.ui.theme.RoundedNumbers, fontWeight = FontWeight.Bold, maxLines = 1)
            Text(unit, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun NativeHistoryChart(buckets: List<History.Bucket>, range: History.Range, type: String, target: Double, fixed: Boolean, selected: Int?, onSelect: (Int) -> Unit) {
    val upper = History.yUpperBound(buckets, target, fixed, hourly = range == History.Range.DAY)
    val showGoal = History.showsGoalRule(target, upper, hourly = range == History.Range.DAY)
    val points = History.plotPoints(buckets)
    val plottedValues = points.associate { it.id to it.averagePerDayMl }
    val axis = MaterialTheme.colorScheme.onSurfaceVariant
    val grid = MaterialTheme.colorScheme.outlineVariant
    val scroll = rememberScrollState()
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val viewportWidth = (maxWidth - 38.dp).coerceAtLeast(80.dp)
        val width = if (range.scrolls) viewportWidth * (buckets.size.toFloat()/range.visibleBuckets).coerceAtLeast(1f) else viewportWidth
        LaunchedEffect(range, buckets.size) { if (range.scrolls) scroll.scrollTo(scroll.maxValue) }
        Row {
            Column(Modifier.width(38.dp).height(220.dp), verticalArrangement = Arrangement.SpaceBetween) {
                listOf(upper, upper * (2.0 / 3), upper / 3, 0.0).forEach { Text(ml(it), fontSize = 10.sp, color = axis) }
            }
            Box(Modifier.weight(1f).horizontalScroll(scroll, enabled = range.scrolls)) {
                val description = "${range.label} ${if (range == History.Range.DAY) "milliliters per hour" else "average milliliters per used day"}. " + buckets.map { b -> "${bucketLabel(b,range,ZoneId.systemDefault())}: ${plottedValues[b.id]?.let(::ml) ?: "no recorded drinks"}" }.joinToString("; ")
                Canvas(Modifier.width(width).height(242.dp).testTag("history-chart")
                    .semantics {
                        contentDescription = description
                        stateDescription = "Y axis: 0 to ${ml(upper)} ml. Daily goal line ${if (showGoal) "shown" else "hidden"}."
                        customActions = listOf(CustomAccessibilityAction("Next period") { onSelect(((selected ?: -1)+1).coerceAtMost(buckets.lastIndex)); true }, CustomAccessibilityAction("Previous period") { onSelect(((selected ?: 1)-1).coerceAtLeast(0)); true })
                    }.pointerInput(buckets) { detectTapGestures { offset -> if (buckets.isNotEmpty()) onSelect((offset.x/size.width*buckets.size).toInt().coerceIn(0,buckets.lastIndex)) } }) {
                    if (buckets.isEmpty()) return@Canvas
                    val plotH = size.height - 28.dp.toPx()
                    val cell = size.width/buckets.size
                    fun x(i: Int) = cell*(i+.5f)
                    fun y(v: Double) = (plotH*(1-v/upper)).toFloat()
                    for (i in 0..3) drawLine(grid, Offset(0f,plotH*i/3), Offset(size.width,plotH*i/3), strokeWidth = 1.dp.toPx())
                    clipRect(0f,0f,size.width,plotH) {
                        if (showGoal) drawLine(axis.copy(alpha = .6f), Offset(0f,y(target)), Offset(size.width,y(target)), strokeWidth = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(),4.dp.toPx())))
                        if (type == "bars") points.forEach { point ->
                            val i = buckets.indexOf(point.bucket)
                            val v = point.averagePerDayMl
                            drawRoundRect(WaterGradient, Offset(x(i)-cell*.32f,y(v)), Size(cell*.64f,plotH-y(v)), cornerRadius = androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()), alpha = if (selected == null || selected == i) 1f else .45f)
                        }
                        else points.groupBy { it.series }.values.forEach { series ->
                            val indexed = series.map { buckets.indexOf(it.bucket) to it.averagePerDayMl }
                            val path = Path().apply {
                                indexed.firstOrNull()?.let { (i,v) -> moveTo(x(i),y(v)) }
                                MonotoneCurve.segments(indexed.map { (i,v) -> MonotoneCurve.Point(x(i).toDouble(),y(v).toDouble()) }).forEach { s ->
                                    cubicTo(s.control1.x.toFloat(),s.control1.y.toFloat(),s.control2.x.toFloat(),s.control2.y.toFloat(),s.end.x.toFloat(),s.end.y.toFloat())
                                }
                            }
                            if (type == "area" && indexed.isNotEmpty()) {
                                val area = Path().apply { addPath(path); lineTo(x(indexed.last().first),plotH); lineTo(x(indexed.first().first),plotH); close() }
                                drawPath(area, WaterGradient, alpha = .35f)
                            }
                            drawPath(path, WaterBlue, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round))
                            indexed.forEach { (i,v) -> drawCircle(WaterBlue, if (selected == i) 5.dp.toPx() else 3.dp.toPx(), Offset(x(i),y(v))) }
                        }
                    }
                    val paint = android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { color = axis.toArgb(); textSize = 10.sp.toPx(); textAlign = android.graphics.Paint.Align.CENTER }
                    buckets.forEachIndexed { i,b ->
                        val every = if (range == History.Range.DAY) 4 else if (range == History.Range.MONTH) 5 else 1
                        if (i % every == 0) {
                            val date = b.start.atZone(ZoneId.systemDefault())
                            val label = date.format(DateTimeFormatter.ofPattern(when(range) { History.Range.DAY -> "HH"; History.Range.WEEK -> "EEEEE"; History.Range.YEAR -> "MMM"; else -> "d MMM" }))
                            drawContext.canvas.nativeCanvas.drawText(label, x(i), size.height-6.dp.toPx(),paint)
                        }
                    }
                }
            }
        }
    }
}
fun bucketLabel(bucket: History.Bucket, range: History.Range, zone: ZoneId): String {
    val f = DateTimeFormatter.ofPattern(if (range == History.Range.DAY) "HH:mm xxx" else "d MMM yyyy")
    val start = bucket.start.atZone(zone).format(f)
    val end = (if (range == History.Range.DAY) bucket.end else bucket.end.minusSeconds(1)).atZone(zone).format(f)
    return if (range != History.Range.DAY && bucket.dayCount == 1) start else "$start – $end"
}
