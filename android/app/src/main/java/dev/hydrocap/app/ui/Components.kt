package dev.hydrocap.app.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import dev.hydrocap.app.ui.theme.WaterBlue
import dev.hydrocap.app.ui.theme.WaterGradient
import java.text.DateFormat
import java.util.Date
import kotlin.math.roundToInt

@Composable
fun ContentCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(modifier, shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}
@Composable
fun CardTitle(title: String, symbol: HydroGlyph? = null) {
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        if (symbol != null) HydroIcon(symbol, Modifier.size(17.dp))
        Text(title, style = MaterialTheme.typography.titleSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable
fun PageHeader(title: String, subtitle: String? = null, onBack: (() -> Unit)? = null, trailing: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) IconButton(onClick = onBack, modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)) { HydroIcon(HydroGlyph.BACK, Modifier.size(24.dp), "Back") }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.headlineLarge, fontWeight = FontWeight.Bold)
            if (subtitle != null) Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        trailing?.invoke()
    }
}
@Composable
fun ChoicePill(options: List<String>, selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    Row(modifier.background(MaterialTheme.colorScheme.surfaceVariant.copy(alpha = .72f), RoundedCornerShape(30.dp)).padding(3.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        options.forEachIndexed { i, text ->
            val active = i == selected
            Box(Modifier.weight(1f).heightIn(min = 44.dp).background(if (active) WaterBlue else Color.Transparent, RoundedCornerShape(25.dp))
                .clickable(enabled = enabled, onClick = { onSelect(i) }).semantics { this.selected = active; role = Role.RadioButton }
                .padding(horizontal = 3.dp, vertical = 9.dp), contentAlignment = Alignment.Center) {
                Text(text, style = MaterialTheme.typography.labelMedium, color = if (active) Color.White else MaterialTheme.colorScheme.onSurface, maxLines = 1)
            }
        }
    }
}
@Composable
fun ValueRow(label: String, value: String, onClick: (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).then(if (onClick == null) Modifier else Modifier.clickable(onClick = onClick)), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.widthIn(max = 180.dp))
        if (onClick != null) HydroIcon(HydroGlyph.FORWARD, Modifier.size(16.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
@Composable
fun ToggleRow(label: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f).padding(end = 8.dp))
        Switch(checked = checked, enabled = enabled, onCheckedChange = onChange, modifier = Modifier.semantics { contentDescription = label })
    }
}
@Composable
fun StepperRow(label: String, value: String, onMinus: () -> Unit, onPlus: () -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) { Text(label); Text(value, color = MaterialTheme.colorScheme.onSurfaceVariant) }
        TextButton(onClick = onMinus, modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)) { Text("−", fontSize = 24.sp, modifier = Modifier.semantics { contentDescription = "Decrease $label" }) }
        TextButton(onClick = onPlus, modifier = Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)) { Text("+", fontSize = 24.sp, modifier = Modifier.semantics { contentDescription = "Increase $label" }) }
    }
}
@Composable
fun BottleGauge(fraction: Double?, modifier: Modifier = Modifier) {
    val track = MaterialTheme.colorScheme.surfaceVariant
    Canvas(modifier.clearAndSetSemantics {}) {
        val w = size.width; val h = size.height
        val p = Path().apply {
            moveTo(w*.34f, 0f); lineTo(w*.66f, 0f); quadraticTo(w*.73f, 0f, w*.73f, h*.05f)
            lineTo(w*.73f, h*.16f); quadraticTo(w, h*.16f, w, h*.28f)
            lineTo(w, h*.93f); quadraticTo(w, h, w*.86f, h); lineTo(w*.14f, h)
            quadraticTo(0f, h, 0f, h*.93f); lineTo(0f, h*.28f); quadraticTo(0f, h*.16f, w*.27f, h*.16f)
            lineTo(w*.27f, h*.05f); quadraticTo(w*.27f, 0f, w*.34f, 0f); close()
        }
        drawPath(p, track)
        clipPath(p) {
            val level = (fraction ?: 0.0).coerceIn(0.0, 1.0).toFloat()
            drawRect(WaterGradient, topLeft = Offset(0f, h*(1-level)), size = Size(w, h*level))
        }
    }
}
@Composable
fun BatteryGauge(percent: Int?, color: Color, modifier: Modifier = Modifier) {
    val track = MaterialTheme.colorScheme.surfaceVariant
    Box(modifier.clearAndSetSemantics {}, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize().padding(4.dp)) {
            drawArc(track, 0f, 360f, false, style = Stroke(8.dp.toPx(), cap = StrokeCap.Round))
            drawArc(color, -90f, (percent ?: 0).coerceIn(0,100)*3.6f, false, style = Stroke(8.dp.toPx(), cap = StrokeCap.Round))
        }
        Text(percent?.toString() ?: "—", fontSize = 18.sp, fontFamily = dev.hydrocap.app.ui.theme.RoundedNumbers, fontWeight = FontWeight.Bold)
    }
}
@Composable
fun WaterProgress(fraction: Double) {
    val track = MaterialTheme.colorScheme.surfaceVariant
    Canvas(Modifier.fillMaxWidth().height(8.dp).semantics { progressBarRangeInfo = ProgressBarRangeInfo(fraction.toFloat().coerceIn(0f,1f), 0f..1f) }) {
        drawRoundRect(track, cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height/2))
        val w = size.width*fraction.toFloat().coerceIn(0f,1f)
        if (w > 0) drawRoundRect(Brush.horizontalGradient(listOf(WaterBlue, dev.hydrocap.app.ui.theme.WaterLight)), size = Size(w, size.height), cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height/2))
    }
}
fun formatTime(ms: Long): String = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(ms))
fun formatDateTime(ms: Long): String = DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(ms))
fun ml(value: Double): String = value.roundToInt().toString()
fun liters(value: Int): String = "%.2f L".format(value / 1000.0)
