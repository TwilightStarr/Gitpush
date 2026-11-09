package com.example.gitpush.ui.components

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.automirrored.filled.ArrowForward
import androidx.compose.material.icons.outlined.Source
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.RemoveCircleOutline
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.text.KeyboardOptions
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.ui.theme.AppTheme

/** Yığındaki ekran en üstteyse true; gizli ekranların BackHandler'ı çalışmasın. */
val LocalActive = compositionLocalOf { true }

@Composable
fun ScreenBack(enabled: Boolean = true, onBack: () -> Unit) {
    BackHandler(enabled = enabled && LocalActive.current, onBack = onBack)
}

/** Ekranı bellekte (durumuyla) tutar ama görünmezken ölçmez/çizmez/dokunma almaz. */
@Composable
fun KeepAlive(visible: Boolean, content: @Composable () -> Unit) {
    Box(
        Modifier.fillMaxSize().layout { measurable, constraints ->
            if (visible) {
                val p = measurable.measure(constraints)
                layout(p.width, p.height) { p.place(0, 0) }
            } else {
                layout(0, 0) {}
            }
        },
    ) { content() }
}

/** Dolgu (filled), kenarlıksız metin alanı — orijinal tasarımdaki gibi. */
@Composable
fun GpTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    label: String? = null,
    placeholder: String? = null,
    enabled: Boolean = true,
    singleLine: Boolean = false,
    minLines: Int = 1,
    maxLines: Int = if (singleLine) 1 else Int.MAX_VALUE,
    mono: Boolean = false,
    isError: Boolean = false,
    supportingText: String? = null,
    leadingIcon: ImageVector? = null,
    trailing: (@Composable () -> Unit)? = null,
    keyboardType: KeyboardType = KeyboardType.Text,
    visualTransformation: androidx.compose.ui.text.input.VisualTransformation = androidx.compose.ui.text.input.VisualTransformation.None,
    textSize: Float? = null,
) {
    val cs = MaterialTheme.colorScheme
    val style = (if (mono) AppTheme.mono else TextStyle.Default).let {
        if (textSize != null) it.copy(fontSize = textSize.sp) else it
    }.copy(color = cs.onSurface)
    val labelC: (@Composable () -> Unit)? = if (label != null) { { Text(label) } } else null
    val placeholderC: (@Composable () -> Unit)? = if (placeholder != null) { { Text(placeholder) } } else null
    val supportingC: (@Composable () -> Unit)? = if (supportingText != null) { { Text(supportingText) } } else null
    val leadingC: (@Composable () -> Unit)? = if (leadingIcon != null) { { Icon(leadingIcon, null) } } else null
    TextField(
        value = value, onValueChange = onValueChange, modifier = modifier, enabled = enabled,
        label = labelC,
        placeholder = placeholderC,
        singleLine = singleLine, minLines = minLines, maxLines = maxLines,
        textStyle = style, isError = isError,
        supportingText = supportingC,
        leadingIcon = leadingC,
        trailingIcon = trailing,
        visualTransformation = visualTransformation,
        keyboardOptions = KeyboardOptions(keyboardType = keyboardType, autoCorrectEnabled = false),
        shape = RoundedCornerShape(12.dp),
        colors = TextFieldDefaults.colors(
            focusedContainerColor = cs.surfaceContainerHighest.copy(alpha = 0.5f),
            unfocusedContainerColor = cs.surfaceContainerHighest.copy(alpha = 0.5f),
            disabledContainerColor = cs.surfaceContainerHighest.copy(alpha = 0.3f),
            errorContainerColor = cs.surfaceContainerHighest.copy(alpha = 0.5f),
            focusedIndicatorColor = Color.Transparent,
            unfocusedIndicatorColor = Color.Transparent,
            disabledIndicatorColor = Color.Transparent,
            errorIndicatorColor = Color.Transparent,
        ),
    )
}

@Composable
fun SectionCard(
    title: String,
    modifier: Modifier = Modifier,
    trailing: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit,
) {
    Card(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f, fill = false))
                if (trailing != null) trailing()
            }
            Spacer(Modifier.height(12.dp))
            content()
        }
    }
}

@Composable
fun EmptyState(icon: ImageVector, message: String, actionLabel: String? = null, onAction: (() -> Unit)? = null) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
            Icon(icon, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f))
            Spacer(Modifier.height(16.dp))
            Text(message, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (actionLabel != null && onAction != null) {
                Spacer(Modifier.height(16.dp))
                FilledTonalButton(onClick = onAction) { Text(actionLabel) }
            }
        }
    }
}

@Composable
fun ErrorView(message: String, onRetry: () -> Unit) {
    Box(Modifier.fillMaxSize().padding(32.dp), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(Icons.Outlined.ErrorOutline, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(16.dp))
            Text(message, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.error)
            Spacer(Modifier.height(16.dp))
            FilledTonalButton(onClick = onRetry) { Text("Tekrar Dene") }
        }
    }
}

@Composable
fun StatusBadge(status: GitFileStatus) {
    val (color, icon, label) = when (status) {
        GitFileStatus.IsNew -> Triple(AppTheme.statusNew, Icons.Outlined.AddCircleOutline, "Yeni")
        GitFileStatus.Update -> Triple(AppTheme.statusUpdate, Icons.Outlined.Sync, "Güncelleme")
        GitFileStatus.Delete -> Triple(AppTheme.statusDelete, Icons.Outlined.RemoveCircleOutline, "Silinecek")
        GitFileStatus.NewFolder -> Triple(AppTheme.statusNewFolder, Icons.Outlined.CreateNewFolder, "Yeni Klasör")
        GitFileStatus.Unchanged -> Triple(Color.Gray, Icons.Filled.Check, "Değişmedi")
        GitFileStatus.Conflict -> Triple(AppTheme.statusDelete, Icons.Outlined.ErrorOutline, "Çakışma")
    }
    Row(
        Modifier.clip(RoundedCornerShape(6.dp)).background(color.copy(alpha = 0.15f)).padding(horizontal = 6.dp, vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(12.dp), tint = color)
        Spacer(Modifier.width(4.dp))
        Text(label, fontSize = 10.sp, fontWeight = FontWeight.Bold, color = color)
    }
}

@Composable
fun SendBottomBar(summaryText: String, buttonLabel: String, onButtonPressed: (() -> Unit)?, isLoading: Boolean = false) {
    Column(Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.surfaceContainer)) {
        androidx.compose.material3.HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
        Row(
            Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.navigationBars).padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(summaryText, Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.width(12.dp))
            Button(onClick = { onButtonPressed?.invoke() }, enabled = onButtonPressed != null && !isLoading) {
                if (isLoading) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text(buttonLabel)
            }
        }
    }
}

/** Seçili repo · dal rozeti (üst çubukta). */
@Composable
fun RepoBranchChip(repoFullName: String?, branchName: String?, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    val selected = !repoFullName.isNullOrEmpty()
    Row(
        Modifier.clip(RoundedCornerShape(20.dp))
            .background(cs.surfaceContainerHighest.copy(alpha = 0.6f))
            .clickableNoRipple(onClick)
            .padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.Outlined.Source, null, Modifier.size(16.dp),
            tint = if (selected) cs.primary else cs.onSurfaceVariant,
        )
        Spacer(Modifier.width(6.dp))
        Text(
            if (selected) "$repoFullName · $branchName" else "Depo seçiniz",
            style = AppTheme.monoBold.copy(fontSize = 12.sp),
            color = if (selected) cs.onSurface else cs.onSurfaceVariant,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
        )
        Spacer(Modifier.width(4.dp))
        Icon(Icons.Filled.KeyboardArrowDown, null, Modifier.size(16.dp), tint = cs.onSurfaceVariant)
    }
}

private fun Modifier.clickableNoRipple(onClick: () -> Unit): Modifier =
    this.then(Modifier.clickable(onClick = onClick))

/** Uygulama logosu: koyu zemin, beyaz yukarı ok (push) ve indigo commit düğümü. */
@Composable
fun GitpushLogo(size: androidx.compose.ui.unit.Dp = 72.dp, radiusFactor: Float = 0.219f) {
    Canvas(Modifier.size(size)) {
        val k = this.size.width / 128f
        drawRoundRect(
            Color(0xFF0E1015), size = Size(128f * k, 128f * k),
            cornerRadius = CornerRadius(128f * radiusFactor * k),
        )
        val stroke = Stroke(width = 9f * k, cap = StrokeCap.Round, join = StrokeJoin.Round)
        val shaft = Path().apply { moveTo(64f * k, 88f * k); lineTo(64f * k, 32f * k) }
        val head = Path().apply { moveTo(46f * k, 50f * k); lineTo(64f * k, 32f * k); lineTo(82f * k, 50f * k) }
        drawPath(shaft, Color.White, style = stroke)
        drawPath(head, Color.White, style = stroke)
        val node = Offset(64f * k, 92f * k)
        drawCircle(Color(0xFF8C9BFF), radius = 11f * k, center = node)
        drawCircle(Color(0xFF0E1015), radius = 11f * k, center = node, style = Stroke(width = 4f * k))
    }
}

@Composable
fun ModeCard(
    title: String, description: String, icon: ImageVector, iconColor: Color, badgeText: String, onClick: () -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    Card(
        onClick = onClick, modifier = Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = cs.surfaceContainer),
    ) {
        Column(Modifier.padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Box(Modifier.clip(RoundedCornerShape(12.dp)).background(iconColor.copy(alpha = 0.12f)).padding(10.dp)) {
                    Icon(icon, null, Modifier.size(28.dp), tint = iconColor)
                }
                Box(Modifier.clip(RoundedCornerShape(8.dp)).background(cs.surfaceContainerHighest).padding(horizontal = 8.dp, vertical = 4.dp)) {
                    Text(badgeText, style = AppTheme.monoBold.copy(fontSize = 10.sp), color = cs.primary)
                }
            }
            Spacer(Modifier.height(14.dp))
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(4.dp))
            Text(description, style = MaterialTheme.typography.bodyMedium, color = cs.onSurfaceVariant)
            Spacer(Modifier.height(12.dp))
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End, verticalAlignment = Alignment.CenterVertically) {
                Text("BAŞLAT", style = AppTheme.monoBold.copy(fontSize = 12.sp), color = cs.primary)
                Spacer(Modifier.width(4.dp))
                Icon(Icons.AutoMirrored.Filled.ArrowForward, null, Modifier.size(16.dp), tint = cs.primary)
            }
        }
    }
}
