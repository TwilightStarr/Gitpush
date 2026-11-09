package com.example.gitpush.ui.components

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.Backspace
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.outlined.Block
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.HourglassEmpty
import androidx.compose.material.icons.outlined.OpenInNew
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Checkbox
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.example.gitpush.model.ActionRun
import com.example.gitpush.model.GitFileItem
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.model.TreeEntry
import com.example.gitpush.service.AppLockService
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.normalizeAndValidateGitPath
import com.example.gitpush.util.shortSha

// ───────────────────────── PIN paneli ─────────────────────────

@Composable
fun PinPad(onCompleted: (String) -> Unit, errorText: String? = null, enabled: Boolean = true, resetToken: Int = 0) {
    val cs = MaterialTheme.colorScheme
    var pin by remember { mutableStateOf("") }
    val haptic = LocalHapticFeedback.current
    LaunchedEffect(resetToken) { pin = "" }

    fun add(d: String) {
        if (!enabled || pin.length >= AppLockService.PIN_LENGTH) return
        haptic.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        pin += d
        if (pin.length == AppLockService.PIN_LENGTH) onCompleted(pin)
    }

    @Composable
    fun Key(label: String, onClick: () -> Unit, content: (@Composable () -> Unit)? = null) {
        Box(
            Modifier.size(width = 72.dp, height = 60.dp).clip(RoundedCornerShape(18.dp))
                .background(cs.surfaceContainerHighest.copy(alpha = 0.55f))
                .clickable(enabled = enabled, onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            if (content != null) content() else Text(label, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, color = cs.onSurface)
        }
    }

    @Composable
    fun DigitRow(digits: List<String>) {
        Row(Modifier.padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            for (d in digits) Key(d, { add(d) })
        }
    }

    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Row(horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            for (i in 0 until AppLockService.PIN_LENGTH) {
                val filled = i < pin.length
                Box(
                    Modifier.size(14.dp).clip(CircleShape)
                        .background(if (filled) cs.primary else Color.Transparent)
                        .border(1.6.dp, if (errorText != null) cs.error else if (filled) cs.primary else cs.outline, CircleShape),
                )
            }
        }
        Box(Modifier.height(36.dp), contentAlignment = Alignment.Center) {
            if (errorText != null) Text(errorText, color = cs.error, fontSize = 12.5.sp, textAlign = TextAlign.Center)
        }
        DigitRow(listOf("1", "2", "3"))
        DigitRow(listOf("4", "5", "6"))
        DigitRow(listOf("7", "8", "9"))
        Row(Modifier.padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Spacer(Modifier.width(72.dp))
            Key("0", { add("0") })
            Key("", { if (enabled && pin.isNotEmpty()) pin = pin.dropLast(1) }) {
                Icon(Icons.AutoMirrored.Outlined.Backspace, null, tint = cs.onSurfaceVariant)
            }
        }
    }
}

// ───────────────────────── Dosya kartı (Mod B) ─────────────────────────

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun FileCard(
    file: GitFileItem,
    isSelected: Boolean,
    selectionMode: Boolean,
    onSelectPath: () -> Unit,
    onPathChanged: (String) -> Unit,
    onDelete: () -> Unit,
    onToggleSelect: () -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    val hasError = file.status == GitFileStatus.Conflict
    val validation = normalizeAndValidateGitPath(file.targetPath)
    val showResolved = !hasError && validation.isValid && validation.normalizedPath != file.repoPath

    var text by remember(file.id) { mutableStateOf(file.repoPath) }
    LaunchedEffect(file.repoPath) { if (text != file.repoPath) text = file.repoPath }

    val dismissState = rememberSwipeToDismissBoxState(
        confirmValueChange = { v ->
            if (v == SwipeToDismissBoxValue.EndToStart) { onDelete(); true } else false
        },
    )
    SwipeToDismissBox(
        state = dismissState,
        enableDismissFromStartToEnd = false,
        backgroundContent = {
            Box(
                Modifier.fillMaxSize().clip(RoundedCornerShape(16.dp)).background(cs.errorContainer).padding(end = 20.dp),
                contentAlignment = Alignment.CenterEnd,
            ) { Icon(Icons.Outlined.DeleteOutline, null, tint = cs.error) }
        },
    ) {
        Card(
            shape = RoundedCornerShape(16.dp),
            colors = CardDefaults.cardColors(
                containerColor = if (isSelected) cs.primaryContainer.copy(alpha = 0.3f) else cs.surfaceContainer,
            ),
            border = if (isSelected) BorderStroke(1.5.dp, cs.primary) else null,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(Modifier.padding(14.dp)) {
                Row(
                    Modifier.fillMaxWidth().clickable { onToggleSelect() },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (selectionMode) {
                        Icon(
                            if (isSelected) Icons.Filled.CheckBox else Icons.Filled.CheckBoxOutlineBlank,
                            null, Modifier.size(20.dp), tint = cs.primary,
                        )
                        Spacer(Modifier.width(8.dp))
                    }
                    val vis = com.example.gitpush.ui.fileVisualFor(file.fileName.substringAfterLast('.', ""))
                    Icon(vis.icon, null, Modifier.size(20.dp), tint = cs.primary)
                    Spacer(Modifier.width(8.dp))
                    Text(
                        file.fileName, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    )
                    if (file.statusKnown) StatusBadge(file.status)
                    Spacer(Modifier.width(4.dp))
                    IconButton(onClick = onDelete, Modifier.size(24.dp)) {
                        Icon(Icons.Filled.Close, "Listeden çıkar", Modifier.size(18.dp))
                    }
                }
                Spacer(Modifier.height(4.dp))
                Text(file.formattedSize, style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant)
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.Top) {
                    GpTextField(
                        value = text,
                        onValueChange = { text = it; onPathChanged(it) },
                        modifier = Modifier.weight(1f),
                        label = "Hedef Repo Yolu", placeholder = "lib/screens/a.dart",
                        mono = true, textSize = 12f, singleLine = false, maxLines = 3,
                        isError = hasError,
                        supportingText = if (hasError) (file.conflictMessage ?: "Çakışma")
                        else if (showResolved) "→ ${validation.normalizedPath}" else null,
                    )
                    Spacer(Modifier.width(8.dp))
                    FilledTonalIconButton(onClick = onSelectPath) {
                        Icon(Icons.Outlined.FolderOpen, "Repo klasörlerinden seç", Modifier.size(18.dp))
                    }
                }
                if (file.needsChoice) {
                    Spacer(Modifier.height(6.dp))
                    Text("Birden fazla eşleşme var, seçin.", fontSize = 11.sp, color = cs.error)
                }
                if (file.suggestions.isNotEmpty()) {
                    Spacer(Modifier.height(8.dp))
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text("Eşleşen:", fontSize = 11.sp, color = cs.onSurfaceVariant)
                        for (path in file.suggestions.take(6)) {
                            Box(
                                Modifier.clip(RoundedCornerShape(4.dp)).background(cs.surfaceContainerHighest)
                                    .clickable { text = path; onPathChanged(path) }
                                    .padding(horizontal = 6.dp, vertical = 2.dp),
                            ) { Text(path, style = AppTheme.mono.copy(fontSize = 10.sp), color = cs.primary) }
                        }
                    }
                }
            }
        }
    }
}

// ───────────────────────── ZIP dosya listesi ─────────────────────────

@Composable
fun FileTreeView(files: List<GitFileItem>, onToggle: (Int) -> Unit) {
    val cs = MaterialTheme.colorScheme
    Column {
        files.forEachIndexed { index, item ->
            val hasConflict = item.isSelected && item.status == GitFileStatus.Conflict
            Row(
                Modifier.fillMaxWidth().clickable { onToggle(index) }.padding(vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Checkbox(checked = item.isSelected, onCheckedChange = { onToggle(index) })
                Column(Modifier.weight(1f)) {
                    Text(
                        item.repoPath,
                        style = AppTheme.mono.copy(fontSize = 12.sp),
                        color = if (item.isSelected) cs.onSurface else cs.onSurfaceVariant,
                    )
                    if (hasConflict) Text(item.conflictMessage ?: "Çakışma", fontSize = 11.sp, color = cs.error)
                }
                Column(horizontalAlignment = Alignment.End) {
                    if (item.statusKnown) StatusBadge(item.status)
                    Spacer(Modifier.height(2.dp))
                    Text(item.formattedSize, fontSize = 11.sp, style = MaterialTheme.typography.bodySmall)
                }
            }
        }
    }
}

// ───────────────────────── Klasör seçici ─────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PathPickerSheet(
    repoTree: List<TreeEntry>,
    fileName: String,
    onPathSelected: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    var currentDir by remember { mutableStateOf("") }
    var newFolder by remember { mutableStateOf("") }

    val folders = remember(repoTree, currentDir) {
        val dirs = sortedSetOf<String>()
        for (node in repoTree) {
            if (node.type != "tree") continue
            val path = node.path
            if (currentDir.isEmpty()) {
                dirs.add(path.split('/')[0])
            } else if (path.startsWith("$currentDir/")) {
                dirs.add(path.substring(currentDir.length + 1).split('/')[0])
            }
        }
        dirs.toList()
    }

    fun confirm(folder: String) {
        onPathSelected(if (folder.isEmpty()) fileName else "$folder/$fileName")
        onDismiss()
    }

    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxWidth()) {
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (currentDir.isNotEmpty()) {
                    IconButton(onClick = {
                        val i = currentDir.lastIndexOf('/')
                        currentDir = if (i == -1) "" else currentDir.substring(0, i)
                    }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null) }
                }
                Text(
                    if (currentDir.isEmpty()) "/ (Kök Dizin)" else "/$currentDir",
                    Modifier.weight(1f), style = AppTheme.monoBold.copy(fontSize = 14.sp),
                    maxLines = 1, overflow = TextOverflow.Ellipsis,
                )
                FilledTonalButton(onClick = { confirm(currentDir) }) { Text("Bu Klasöre Koy") }
            }
            HorizontalDivider()
            Row(Modifier.padding(horizontal = 16.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                GpTextField(
                    value = newFolder, onValueChange = { newFolder = it }, modifier = Modifier.weight(1f),
                    placeholder = "Yeni klasör adı...", mono = true, textSize = 12f, singleLine = true,
                )
                Spacer(Modifier.width(8.dp))
                Button(onClick = {
                    val name = newFolder.trim()
                    if (name.isNotEmpty()) confirm(if (currentDir.isEmpty()) name else "$currentDir/$name")
                }) { Text("Oluştur & Seç") }
            }
            HorizontalDivider()
            if (folders.isEmpty()) {
                Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
                    Text("Alt klasör bulunamadı", color = cs.onSurfaceVariant)
                }
            } else {
                LazyColumn(Modifier.height(320.dp)) {
                    items(folders) { folder ->
                        ListItem(
                            leadingContent = { Icon(Icons.Filled.Folder, null, tint = cs.primary) },
                            headlineContent = { Text(folder, style = AppTheme.mono) },
                            trailingContent = { Icon(Icons.Filled.ChevronRight, null) },
                            modifier = Modifier.clickable { currentDir = if (currentDir.isEmpty()) folder else "$currentDir/$folder" },
                        )
                    }
                }
            }
        }
    }
}

// ───────────────────────── İlerleme penceresi ─────────────────────────

@Composable
fun ProgressSheet(
    currentStep: String, current: Int, total: Int,
    error: String? = null, onRetry: (() -> Unit)? = null, onCancel: (() -> Unit)? = null,
) {
    val cs = MaterialTheme.colorScheme
    val progress = if (total > 0) (current.toFloat() / total).coerceIn(0f, 1f) else 0f
    Dialog(
        onDismissRequest = {},
        properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false),
    ) {
        androidx.compose.material3.Surface(shape = RoundedCornerShape(24.dp), tonalElevation = 6.dp) {
            Column(Modifier.padding(24.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (error == null) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.5.dp)
                    else Icon(Icons.Outlined.ErrorOutline, null, tint = cs.error)
                    Spacer(Modifier.width(12.dp))
                    Text(
                        if (error == null) "Gönderim Sürüyor" else "Gönderim Başarısız Oldu",
                        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold,
                    )
                }
                Spacer(Modifier.height(16.dp))
                if (error != null) {
                    LinearProgressIndicator(progress = { 1f }, Modifier.fillMaxWidth(), color = cs.error)
                } else if (total > 0) {
                    LinearProgressIndicator(progress = { progress }, Modifier.fillMaxWidth())
                } else {
                    LinearProgressIndicator(Modifier.fillMaxWidth())
                }
                Spacer(Modifier.height(12.dp))
                Text(
                    currentStep, style = AppTheme.mono.copy(fontSize = 13.sp),
                    color = if (error != null) cs.error else cs.onSurface,
                )
                if (error != null) {
                    Spacer(Modifier.height(12.dp))
                    Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(cs.errorContainer).padding(12.dp)) {
                        Text(error, color = cs.onErrorContainer, fontSize = 13.sp)
                    }
                    Spacer(Modifier.height(16.dp))
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                        if (onCancel != null) TextButton(onClick = onCancel) { Text("İptal") }
                        Spacer(Modifier.width(8.dp))
                        if (onRetry != null) Button(onClick = onRetry) { Text("Tekrar Dene") }
                    }
                }
            }
        }
    }
}

// ───────────────────────── Kısayol çipleri ─────────────────────────

@Composable
fun QuickCommandChips(shortcuts: List<String>, onSelect: (String) -> Unit, onAddShortcut: () -> Unit) {
    Row(
        Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        for (s in shortcuts) {
            AssistChip(
                onClick = { onSelect(s) }, label = { Text(s) },
                leadingIcon = { Icon(Icons.Filled.Bolt, null, Modifier.size(14.dp)) },
            )
        }
        AssistChip(
            onClick = onAddShortcut, label = { Text("+ Kısayol") },
            leadingIcon = { Icon(Icons.Filled.Add, null, Modifier.size(14.dp)) },
        )
    }
}

// ───────────────────────── Actions satırı ─────────────────────────

@Composable
fun ActionRunTile(run: ActionRun, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    Card(
        onClick = onClick, shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(containerColor = cs.surfaceContainer),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(Modifier.padding(horizontal = 16.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
            when {
                run.isRunning -> CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.5.dp)
                run.isSuccess -> Icon(Icons.Outlined.CheckCircle, null, Modifier.size(22.dp), tint = AppTheme.statusNew)
                run.isFailed || run.isTimedOut || run.isStartupFailure ->
                    Icon(Icons.Outlined.Cancel, null, Modifier.size(22.dp), tint = cs.error)
                run.isCancelled -> Icon(Icons.Outlined.Block, null, Modifier.size(22.dp), tint = cs.onSurfaceVariant)
                else -> Icon(Icons.Outlined.HourglassEmpty, null, Modifier.size(22.dp), tint = cs.onSurfaceVariant)
            }
            Spacer(Modifier.width(16.dp))
            Column(Modifier.weight(1f)) {
                Text(run.name, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(2.dp))
                Text(run.commitMessage, maxLines = 1, overflow = TextOverflow.Ellipsis, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(4.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(run.headBranch, style = AppTheme.mono.copy(fontSize = 10.sp), color = cs.primary)
                    Text(shortSha(run.headSha), style = AppTheme.mono.copy(fontSize = 10.sp), color = cs.onSurfaceVariant)
                    Text(run.statusLabel, fontSize = 10.sp)
                }
            }
            Icon(Icons.Outlined.OpenInNew, null, Modifier.size(16.dp))
        }
    }
}
