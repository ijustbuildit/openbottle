package dev.hydrocap.app.ui

import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.res.painterResource
import androidx.compose.foundation.Image
import dev.hydrocap.app.R
import androidx.compose.ui.unit.dp
import dev.hydrocap.app.ui.theme.WaterBlue

/** Owned 24-unit native vectors, not text glyphs or an SF Symbols font. */
enum class HydroGlyph { HOME, HISTORY, SETTINGS, DROP, BOLT, LIST, BACK, FORWARD, BOTTLE, RING, RELOAD, SIGNAL }
private val vectors by lazy { HydroGlyph.entries.associateWith { glyph ->
    ImageVector.Builder(glyph.name,24.dp,24.dp,24f,24f).apply {
        path(fill=null,stroke=SolidColor(Color.Black),strokeLineWidth=1.9f,strokeLineCap=StrokeCap.Round,strokeLineJoin=StrokeJoin.Round) {
            when(glyph) {
                HydroGlyph.HOME -> { moveTo(3f,10f); lineTo(12f,3f); lineTo(21f,10f); moveTo(5f,9f); lineTo(5f,21f); lineTo(10f,21f); lineTo(10f,14f); lineTo(14f,14f); lineTo(14f,21f); lineTo(19f,21f); lineTo(19f,9f) }
                HydroGlyph.HISTORY -> { moveTo(4f,20f); lineTo(4f,12f); lineTo(8f,12f); lineTo(8f,20f); close(); moveTo(10f,20f); lineTo(10f,4f); lineTo(14f,4f); lineTo(14f,20f); close(); moveTo(16f,20f); lineTo(16f,8f); lineTo(20f,8f); lineTo(20f,20f); close() }
                HydroGlyph.SETTINGS -> {
                    moveTo(10f,3f); lineTo(14f,3f); lineTo(14.7f,6f); lineTo(17f,7.3f); lineTo(20f,6.4f); lineTo(22f,9.8f); lineTo(19.7f,12f); lineTo(19.7f,14f); lineTo(22f,16f); lineTo(20f,19.5f); lineTo(17f,18.6f); lineTo(14.7f,20f); lineTo(14f,23f); lineTo(10f,23f); lineTo(9.3f,20f); lineTo(7f,18.6f); lineTo(4f,19.5f); lineTo(2f,16f); lineTo(4.3f,14f); lineTo(4.3f,12f); lineTo(2f,9.8f); lineTo(4f,6.4f); lineTo(7f,7.3f); lineTo(9.3f,6f); close()
                    moveTo(15.3f,13f); curveTo(15.3f,17.4f,8.7f,17.4f,8.7f,13f); curveTo(8.7f,8.6f,15.3f,8.6f,15.3f,13f); close()
                }
                HydroGlyph.DROP -> { moveTo(12f,2f); curveTo(10f,7f,5f,11f,5f,15f); curveTo(5f,24f,19f,24f,19f,15f); curveTo(19f,11f,14f,7f,12f,2f); close() }
                HydroGlyph.BOLT -> { moveTo(14f,2f); lineTo(5f,13f); lineTo(11f,13f); lineTo(10f,22f); lineTo(20f,10f); lineTo(13f,10f); close() }
                HydroGlyph.LIST -> { for (y in listOf(6f,12f,18f)) { moveTo(8f,y); lineTo(21f,y); moveTo(3f,y); lineTo(3.2f,y) } }
                HydroGlyph.BACK -> { moveTo(15f,4f); lineTo(7f,12f); lineTo(15f,20f) }
                HydroGlyph.FORWARD -> { moveTo(9f,4f); lineTo(17f,12f); lineTo(9f,20f) }
                HydroGlyph.BOTTLE -> { moveTo(9f,2f); lineTo(15f,2f); lineTo(15f,6f); curveTo(15f,8f,19f,8f,19f,11f); lineTo(19f,20f); quadTo(19f,22f,17f,22f); lineTo(7f,22f); quadTo(5f,22f,5f,20f); lineTo(5f,11f); curveTo(5f,8f,9f,8f,9f,6f); close(); moveTo(9f,5f); lineTo(15f,5f) }
                HydroGlyph.RING -> { moveTo(18f,12f); curveTo(18f,20f,6f,20f,6f,12f); curveTo(6f,4f,18f,4f,18f,12f); close(); for (v in listOf(0f,1f)) { moveTo(12f,1f+21f*v); lineTo(12f,3f+17f*v); moveTo(1f+21f*v,12f); lineTo(3f+17f*v,12f) } }
                HydroGlyph.RELOAD -> { moveTo(20f,9f); curveTo(17f,1f,5f,3f,4f,11f); curveTo(2f,20f,15f,25f,20f,16f); moveTo(20f,3f); lineTo(20f,9f); lineTo(14f,9f) }
                HydroGlyph.SIGNAL -> { moveTo(3f,20f); lineTo(3f,16f); moveTo(9f,20f); lineTo(9f,12f); moveTo(15f,20f); lineTo(15f,8f); moveTo(21f,20f); lineTo(21f,4f) }
            }
        }
    }.build()
} }
@Composable
fun HydroIcon(glyph: HydroGlyph, modifier: Modifier = Modifier, description: String? = null, color: Color = WaterBlue) {
    if (glyph == HydroGlyph.BOTTLE) Image(painterResource(R.drawable.hydrocap_bottle),description,modifier)
    else Icon(vectors.getValue(glyph),description,modifier,tint=color)
}
