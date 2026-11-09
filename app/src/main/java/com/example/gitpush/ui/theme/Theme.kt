package com.example.gitpush.ui.theme

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.ColorUtils

object AppTheme {
    val seedColor = Color(0xFF5B6CFF)
    val statusNew = Color(0xFF2EA043) // Yeni dosya (yeşil)
    val statusUpdate = Color(0xFF1F6FEB) // Güncelleme (mavi)
    val statusDelete = Color(0xFFDA3633) // Silinecek (kırmızı)
    val statusNewFolder = Color(0xFFD29922) // Yeni klasör (amber)

    val mono = TextStyle(fontFamily = FontFamily.Monospace, letterSpacing = (-0.2).sp)
    val monoBold = TextStyle(fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp)
}

private fun hsl(h: Float, s: Float, l: Float): Color =
    Color(ColorUtils.HSLToColor(floatArrayOf(h, s.coerceIn(0f, 1f), l.coerceIn(0f, 1f))))

/** Tohum renginden tonal bir Material 3 paleti türetir (açık/koyu/AMOLED). */
fun schemeFromSeed(seed: Color, dark: Boolean, amoled: Boolean): ColorScheme {
    val hsl = FloatArray(3)
    ColorUtils.colorToHSL(seed.toArgb(), hsl)
    val h = hsl[0]
    val sat = hsl[1].coerceIn(0.45f, 0.9f)
    fun p(l: Float) = hsl(h, sat, l)
    fun s(l: Float) = hsl(h, 0.28f, l)
    fun t(l: Float) = hsl((h + 60f) % 360f, 0.42f, l)
    fun n(l: Float) = hsl(h, 0.07f, l)
    fun nv(l: Float) = hsl(h, 0.12f, l)

    if (!dark) {
        return lightColorScheme(
            primary = p(0.48f), onPrimary = Color.White,
            primaryContainer = p(0.91f), onPrimaryContainer = p(0.16f),
            secondary = s(0.42f), onSecondary = Color.White,
            secondaryContainer = s(0.90f), onSecondaryContainer = s(0.14f),
            tertiary = t(0.42f), onTertiary = Color.White,
            tertiaryContainer = t(0.90f), onTertiaryContainer = t(0.14f),
            background = n(0.98f), onBackground = n(0.10f),
            surface = n(0.98f), onSurface = n(0.10f),
            surfaceVariant = nv(0.90f), onSurfaceVariant = nv(0.30f),
            surfaceTint = p(0.48f),
            outline = nv(0.50f), outlineVariant = nv(0.80f),
            error = Color(0xFFBA1A1A), onError = Color.White,
            errorContainer = Color(0xFFFFDAD6), onErrorContainer = Color(0xFF410002),
            inverseSurface = n(0.20f), inverseOnSurface = n(0.95f), inversePrimary = p(0.78f),
            surfaceContainerLowest = Color.White, surfaceContainerLow = n(0.96f),
            surfaceContainer = n(0.94f), surfaceContainerHigh = n(0.92f), surfaceContainerHighest = n(0.90f),
        )
    }
    val base = darkColorScheme(
        primary = p(0.78f), onPrimary = p(0.20f),
        primaryContainer = p(0.32f), onPrimaryContainer = p(0.91f),
        secondary = s(0.78f), onSecondary = s(0.20f),
        secondaryContainer = s(0.30f), onSecondaryContainer = s(0.90f),
        tertiary = t(0.78f), onTertiary = t(0.20f),
        tertiaryContainer = t(0.30f), onTertiaryContainer = t(0.90f),
        background = n(0.07f), onBackground = n(0.90f),
        surface = n(0.07f), onSurface = n(0.90f),
        surfaceVariant = nv(0.28f), onSurfaceVariant = nv(0.78f),
        surfaceTint = p(0.78f),
        outline = nv(0.60f), outlineVariant = nv(0.30f),
        error = Color(0xFFFFB4AB), onError = Color(0xFF690005),
        errorContainer = Color(0xFF93000A), onErrorContainer = Color(0xFFFFDAD6),
        inverseSurface = n(0.90f), inverseOnSurface = n(0.20f), inversePrimary = p(0.48f),
        surfaceContainerLowest = n(0.05f), surfaceContainerLow = n(0.09f),
        surfaceContainer = n(0.11f), surfaceContainerHigh = n(0.14f), surfaceContainerHighest = n(0.17f),
    )
    if (!amoled) return base
    return base.copy(
        background = Color.Black, surface = Color.Black,
        surfaceContainerLowest = Color.Black, surfaceContainerLow = Color(0xFF0A0A0C),
        surfaceContainer = Color(0xFF111114), surfaceContainerHigh = Color(0xFF17171B),
        surfaceContainerHighest = Color(0xFF1E1E23),
    )
}

/** Tema değişince renkleri ani sıçrama yerine yumuşakça geçirir; yarım kalmış/yarı koyu kareler oluşmaz. */
@Composable
private fun ColorScheme.animated(): ColorScheme {
    val spec = tween<Color>(durationMillis = 220)
    @Composable fun a(c: Color): Color = animateColorAsState(c, spec, label = "scheme").value
    return copy(
        primary = a(primary), onPrimary = a(onPrimary),
        primaryContainer = a(primaryContainer), onPrimaryContainer = a(onPrimaryContainer),
        secondary = a(secondary), onSecondary = a(onSecondary),
        secondaryContainer = a(secondaryContainer), onSecondaryContainer = a(onSecondaryContainer),
        tertiary = a(tertiary), onTertiary = a(onTertiary),
        tertiaryContainer = a(tertiaryContainer), onTertiaryContainer = a(onTertiaryContainer),
        background = a(background), onBackground = a(onBackground),
        surface = a(surface), onSurface = a(onSurface),
        surfaceVariant = a(surfaceVariant), onSurfaceVariant = a(onSurfaceVariant),
        surfaceTint = a(surfaceTint),
        outline = a(outline), outlineVariant = a(outlineVariant),
        error = a(error), onError = a(onError),
        errorContainer = a(errorContainer), onErrorContainer = a(onErrorContainer),
        inverseSurface = a(inverseSurface), inverseOnSurface = a(inverseOnSurface), inversePrimary = a(inversePrimary),
        surfaceContainerLowest = a(surfaceContainerLowest), surfaceContainerLow = a(surfaceContainerLow),
        surfaceContainer = a(surfaceContainer), surfaceContainerHigh = a(surfaceContainerHigh),
        surfaceContainerHighest = a(surfaceContainerHighest),
    )
}

@Composable
fun GitpushTheme(seed: Color, dark: Boolean, amoled: Boolean, content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = schemeFromSeed(seed, dark, amoled).animated(),
        shapes = Shapes(
            extraSmall = RoundedCornerShape(6.dp),
            small = RoundedCornerShape(8.dp),
            medium = RoundedCornerShape(12.dp),
            large = RoundedCornerShape(16.dp),
            extraLarge = RoundedCornerShape(24.dp),
        ),
        content = content,
    )
}
