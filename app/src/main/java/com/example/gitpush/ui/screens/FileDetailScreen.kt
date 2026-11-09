package com.example.gitpush.ui.screens

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.WrapText
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Timeline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.model.PathCommitInfo
import com.example.gitpush.model.PreviewKind
import com.example.gitpush.model.RepoEntry
import com.example.gitpush.model.previewKindFor
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Route
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.ErrorView
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.components.SectionCard
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.FilePreviewData
import com.example.gitpush.util.FilePreviewStatus
import com.example.gitpush.util.copyToClipboard
import com.example.gitpush.util.formatBytes
import com.example.gitpush.util.formatDateTime
import com.example.gitpush.util.prepareFilePreview
import com.example.gitpush.util.shortSha
import com.example.gitpush.util.splitIntoChunks
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private sealed interface DetailState {
    data object Loading : DetailState
    data class Failed(val message: String) : DetailState
    data class TooBig(val limitKb: Int) : DetailState
    data object Binary : DetailState
    data class Image(val bitmap: Bitmap) : DetailState
    data class Text(val preview: FilePreviewData) : DetailState
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FileDetailScreen(entry: RepoEntry) {
    val g = Graph
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings = g.settings.settings
    var state by remember { mutableStateOf<DetailState>(DetailState.Loading) }
    var lastCommit by remember { mutableStateOf<PathCommitInfo?>(null) }
    var reloadKey by remember { mutableStateOf(0) }
    val kind = remember(entry.name) { previewKindFor(entry.name) }
    val maxBytes = settings.previewMaxKb * 1024L

    ScreenBack { g.nav.pop() }

    LaunchedEffect(entry.path, reloadKey) {
        state = DetailState.Loading
        val token = g.auth.token ?: ""
        launch {
            try { lastCommit = g.repo.lastCommitFor(token, entry.path) } catch (_: Exception) { }
        }
        if (kind == PreviewKind.Binary) { state = DetailState.Binary; return@LaunchedEffect }
        if (entry.size > maxBytes) { state = DetailState.TooBig(settings.previewMaxKb); return@LaunchedEffect }
        try {
            val bytes = g.repo.readFileBytes(token, entry, maxBytes)
            state = withContext(Dispatchers.Default) {
                if (kind == PreviewKind.Image) {
                    val bmp = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                    if (bmp != null) DetailState.Image(bmp) else DetailState.Binary
                } else {
                    val p = prepareFilePreview(bytes)
                    if (p.status == FilePreviewStatus.Ok) DetailState.Text(p) else DetailState.Binary
                }
            }
        } catch (e: GitHubApiException) {
            state = DetailState.Failed(e.message)
        } catch (e: Exception) {
            state = DetailState.Failed("Dosya okunamadı: $e")
        }
    }

    fun delete() {
        scope.launch {
            val ok = Dialogs.confirm("Dosya silinsin mi?", "${entry.name} tek commit ile silinecek.", "Sil", destructive = true)
            if (!ok) return@launch
            val msg = Dialogs.prompt(
                "Commit mesajı", "Mesaj", initial = settings.defaultCommitMessage.ifBlank { "Delete ${entry.name}" }, confirmLabel = "Sil",
            )?.trim().orEmpty()
            if (msg.isEmpty()) return@launch
            try {
                val r = Dialogs.withBusy("Siliniyor...") {
                    g.repo.deleteEntries(g.auth.token ?: "", listOf(entry), msg, g.auth.authorName, g.auth.authorEmail)
                }
                val repo = g.repo.selectedRepo
                if (repo != null) g.upload.recordExternalCommit(repo.owner, repo.name, g.repo.selectedBranch ?: "", msg, r.commitSha, r.fileCount)
                Snacks.show("Dosya silindi.")
                g.nav.pop(true)
            } catch (e: GitHubApiException) { Snacks.show(e.message) }
        }
    }

    val textState = state as? DetailState.Text

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(entry.name, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                navigationIcon = { IconButton(onClick = { g.nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
                actions = {
                    if (textState != null) {
                        IconButton(onClick = { g.settings.update { it.copy(previewWrapLines = !it.previewWrapLines) } }) {
                            Icon(Icons.AutoMirrored.Filled.WrapText, "Satır kaydır")
                        }
                        IconButton(onClick = { copyToClipboard(ctx, textState.preview.fullText); Snacks.show("İçerik kopyalandı") }) {
                            Icon(Icons.Outlined.ContentCopy, "Kopyala")
                        }
                        IconButton(onClick = {
                            g.nav.push(Route.FileEditor(path = entry.path, initialText = textState.preview.fullText, mode = entry.mode)) { saved ->
                                if (saved) g.nav.pop(true)
                            }
                        }) { Icon(Icons.Outlined.Edit, "Düzenle") }
                    }
                    IconButton(onClick = { delete() }) { Icon(Icons.Outlined.DeleteOutline, "Sil", tint = MaterialTheme.colorScheme.error) }
                },
            )
        },
    ) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            val hs = rememberScrollState()
            LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                item {
                    SectionCard("Bilgi") {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            InfoRow("Yol", entry.path, mono = true)
                            InfoRow("Boyut", formatBytes(entry.size))
                            entry.sha?.let { InfoRow("SHA", shortSha(it, 10), mono = true) }
                            lastCommit?.let { c ->
                                InfoRow("Son commit", c.title)
                                InfoRow("Yazar / tarih", listOfNotNull(c.authorName, c.date?.let { formatDateTime(it) }).joinToString(" · "))
                            }
                        }
                    }
                }
                when (val s = state) {
                    DetailState.Loading -> item { Box(Modifier.fillMaxWidth().padding(32.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
                    is DetailState.Failed -> item { Text(s.message, color = MaterialTheme.colorScheme.error) }
                    is DetailState.TooBig -> item {
                        Text("Dosya önizleme sınırından (${com.example.gitpush.model.AppSettings.formatKb(s.limitKb)}) büyük. Sınırı Ayarlar'dan artırabilirsiniz.")
                    }
                    DetailState.Binary -> item { Text("Bu dosya türü önizlenemiyor (ikili dosya).", color = MaterialTheme.colorScheme.onSurfaceVariant) }
                    is DetailState.Image -> item { ZoomableImage(s.bitmap) }
                    is DetailState.Text -> {
                        val p = s.preview
                        item {
                            Text(
                                "${p.shownLines} / ${p.totalLines} satır" + if (p.truncated) " (kısaltıldı)" else "",
                                fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                        val chunked = splitIntoChunks(p.displayText, maxLines = 100, maxChars = 20000)
                        var lineStart = 1
                        val starts = ArrayList<Int>()
                        for (c in chunked.lineCounts) { starts.add(lineStart); lineStart += c }
                        val wrap = settings.previewWrapLines
                        val fs = settings.previewFontSize.sp
                        items(chunked.chunks.size) { i ->
                            val nums = (starts[i] until starts[i] + chunked.lineCounts[i]).joinToString("\n")
                            SelectionContainer {
                                if (wrap) {
                                    Text(chunked.chunks[i], style = AppTheme.mono.copy(fontSize = fs), modifier = Modifier.fillMaxWidth())
                                } else {
                                    Row(Modifier.horizontalScroll(hs)) {
                                        Text(
                                            nums, style = AppTheme.mono.copy(fontSize = fs), textAlign = TextAlign.End,
                                            color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(end = 12.dp),
                                        )
                                        Text(chunked.chunks[i], style = AppTheme.mono.copy(fontSize = fs), softWrap = false)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun InfoRow(label: String, value: String, mono: Boolean = false) {
    Row {
        Text(label, Modifier.width(96.dp), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, Modifier.weight(1f), fontSize = 13.sp, style = if (mono) AppTheme.mono.copy(fontSize = 12.sp) else MaterialTheme.typography.bodySmall)
    }
}

@Composable
private fun ZoomableImage(bitmap: Bitmap) {
    var scale by remember { mutableStateOf(1f) }
    var offsetX by remember { mutableStateOf(0f) }
    var offsetY by remember { mutableStateOf(0f) }
    Box(
        Modifier.fillMaxWidth().heightIn(max = 420.dp).clip(RoundedCornerShape(12.dp))
            .background(MaterialTheme.colorScheme.surfaceContainer)
            .pointerInput(Unit) {
                detectTransformGestures { _, pan, zoom, _ ->
                    scale = (scale * zoom).coerceIn(1f, 6f)
                    offsetX += pan.x
                    offsetY += pan.y
                    if (scale == 1f) { offsetX = 0f; offsetY = 0f }
                }
            },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            bitmap.asImageBitmap(), null, contentScale = ContentScale.Fit,
            modifier = Modifier.fillMaxWidth().graphicsLayer(scaleX = scale, scaleY = scale, translationX = offsetX, translationY = offsetY),
        )
    }
}
