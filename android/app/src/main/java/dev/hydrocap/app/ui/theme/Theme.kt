package dev.hydrocap.app.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.dp
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.font.FontVariation
import dev.hydrocap.app.R

@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
val RoundedNumbers = FontFamily(Font(R.font.hydrocap_numbers, weight = FontWeight.Bold, variationSettings = FontVariation.Settings(FontVariation.weight(700))))

val WaterBlue = Color(0xFF3D9EFA)
val WaterLight = Color(0xFF73C7FF)
val WaterGradient = Brush.verticalGradient(listOf(WaterLight, WaterBlue))

private val LightColors = lightColorScheme(
    primary = WaterBlue, onPrimary = Color.White, primaryContainer = Color(0xFFDCECFF),
    secondary = WaterBlue, background = Color(0xFFF2F2F7), onBackground = Color(0xFF1C1C1E),
    surface = Color.White, onSurface = Color(0xFF1C1C1E), surfaceContainer = Color.White,
    surfaceContainerLow = Color.White, surfaceVariant = Color(0xFFE9E9EE), onSurfaceVariant = Color(0xFF696970),
    outlineVariant = Color(0xFFE4E4E9),
)
private val DarkColors = darkColorScheme(
    primary = WaterBlue, onPrimary = Color.White, primaryContainer = Color(0xFF183B5A),
    secondary = WaterBlue, background = Color.Black, onBackground = Color.White,
    surface = Color(0xFF1C1C1E), onSurface = Color.White, surfaceContainer = Color(0xFF1C1C1E),
    surfaceContainerLow = Color(0xFF1C1C1E), surfaceVariant = Color(0xFF303034), onSurfaceVariant = Color(0xFFAAAAAF),
    outlineVariant = Color(0xFF38383C),
)

@Composable
fun HydroCapTheme(appearance: String = "system", darkTheme: Boolean = when (appearance) { "light" -> false; "dark" -> true; else -> isSystemInDarkTheme() }, content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (darkTheme) DarkColors else LightColors,
        shapes = Shapes(small = RoundedCornerShape(10.dp), medium = RoundedCornerShape(20.dp), large = RoundedCornerShape(20.dp)), content = content)
}
