package com.example.gitpush.ui.theme

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import dev.chrisbanes.haze.HazeInput
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import dev.chrisbanes.haze.glass.GlassStyle
import dev.chrisbanes.haze.glass.hazeGlass
import kotlin.math.cos
import kotlin.math.sin

/*
 * Cam (glass) altyapısı.
 *
 * Tüm efekt kütüphanesi bağımlılığı BU DOSYADA toplanır; uygulamanın geri kalanı yalnızca
 * `GlassBackdrop`, `Modifier.glass(...)` ve `Modifier.glow(...)` kullanır. Böylece kütüphane
 * değişirse tek dosya değişir.
 */

/** Cam yüzeylerin arkasını okuyacağı kaynak durumu. null ise cam yerine yarı saydam yüzey çizilir. */
val LocalGlassState = staticCompositionLocalOf<HazeState?> { null }

/**
 * AMOLED saf siyah zemin + çok yavaş süzülen, düşük doygunlukta renkli ışık halkaları.
 * Halkalar cam yüzeylerin kırılma/bulanıklık kaynağıdır; bu yüzden cam üzerinde ışık oynaşması görünür.
 * İçerik ([content]) halkaların üstünde çizilir.
 */
@Composable
fun GlassBackdrop(
    modifier: Modifier = Modifier,
    animated: Boolean = true,
    content: @Composable BoxScope.() -> Unit,
) {
    val state = rememberHazeState()
    val cs = MaterialTheme.colorScheme
    val c1 = cs.primary
    val c2 = cs.tertiary

    val phase = if (animated) {
        val t = rememberInfiniteTransition(label = "aurora")
        t.animateFloat(
            initialValue = 0f, targetValue = (2 * Math.PI).toFloat(),
            animationSpec = infiniteRepeatable(tween(36_000, easing = LinearEasing), RepeatMode.Restart),
            label = "phase",
        ).value
    } else 0f

    Box(modifier.fillMaxSize().background(Color.Black)) {
        // Kaynak katman: cam yüzeyler bunu okur.
        Canvas(Modifier.fillMaxSize().hazeSource(state)) {
            val w = size.width
            val h = size.height
            val r = maxOf(w, h)
            fun orb(color: Color, cx: Float, cy: Float, radius: Float, alpha: Float) {
                drawCircle(
                    brush = Brush.radialGradient(
                        listOf(color.copy(alpha = alpha), Color.Transparent),
                        center = Offset(cx, cy), radius = radius,
                    ),
                    radius = radius, center = Offset(cx, cy),
                )
            }
            orb(c1, w * (0.25f + 0.10f * cos(phase)), h * (0.18f + 0.05f * sin(phase)), r * 0.55f, 0.34f)
            orb(c2, w * (0.85f + 0.06f * sin(phase * 1.3f)), h * (0.55f + 0.06f * cos(phase)), r * 0.50f, 0.22f)
            orb(c1, w * (0.35f + 0.08f * sin(phase * 0.7f)), h * (0.92f + 0.03f * cos(phase * 1.1f)), r * 0.45f, 0.20f)
        }
        CompositionLocalProvider(LocalGlassState provides state) {
            Box(Modifier.fillMaxSize()) { content() }
        }
    }
}

/**
 * Cam yüzey. [GlassBackdrop] içindeyse gerçek kırılma + bulanıklık, değilse yarı saydam yüzey çizer.
 * İnce, açık renkli bir kenar çizgisi parlaklık hissi verir.
 */
@Composable
fun Modifier.glass(
    corner: Dp = 24.dp,
    tint: Color = Color.White.copy(alpha = 0.06f),
    edge: Color = Color.White.copy(alpha = 0.16f),
): Modifier {
    val state = LocalGlassState.current
    val shape = RoundedCornerShape(corner)
    val border = Modifier.border(1.dp, Brush.verticalGradient(listOf(edge, edge.copy(alpha = edge.alpha * 0.25f))), shape)
    if (state == null) {
        return this.background(tint.copy(alpha = 0.10f), shape).then(border)
    }
    val style = remember(corner, tint) {
        val tintColor = tint
        val cornerShape = RoundedCornerShape(corner)
        GlassStyle.regular.then {
            tint(tintColor)
            shape(cornerShape)
        }
    }
    return this.hazeGlass(input = HazeInput.Sources(state), style = style).then(border)
}

/** Öğenin arkasında yumuşak, renkli bir parıltı (ana düğmeler için). */
fun Modifier.glow(color: Color, radius: Dp = 28.dp, alpha: Float = 0.45f): Modifier = this.drawBehind {
    val rPx = radius.toPx()
    drawCircle(
        brush = Brush.radialGradient(
            listOf(color.copy(alpha = alpha), Color.Transparent),
            center = center, radius = size.maxDimension / 2f + rPx,
        ),
        radius = size.maxDimension / 2f + rPx, center = center,
    )
}
