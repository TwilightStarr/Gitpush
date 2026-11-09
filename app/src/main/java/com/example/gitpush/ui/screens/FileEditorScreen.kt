package com.example.gitpush.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Route
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.util.splitIntoChunks
import kotlinx.coroutines.launch

private const val CHUNK_MODE_THRESHOLD = 150_000

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FileEditorScreen(route: Route.FileEditor) {
    val g = Graph
    val scope = rememberCoroutineScope()
    val settings = g.settings.settings
    val chunkMode = route.initialText.length > CHUNK_MODE_THRESHOLD

    var single by remember { mutableStateOf(route.initialText) }
    val chunks = remember { mutableStateListOf<String>().also { if (chunkMode) it.addAll(splitIntoChunks(route.initialText).chunks) } }
    var saving by remember { mutableStateOf(false) }

    fun current(): String = if (chunkMode) chunks.joinToString("\n") else single
    val dirty = if (chunkMode) current() != route.initialText else single != route.initialText

    fun leave() {
        if (!dirty && !route.isNew) { g.nav.pop(false); return }
        scope.launch {
            val discard = Dialogs.confirm(
                "Değişiklikler atılsın mı?", "Kaydedilmemiş değişiklikleriniz kaybolacak.", "At", "Düzenlemeye dön", destructive = true,
            )
            if (discard) g.nav.pop(false)
        }
    }

    ScreenBack { leave() }

    fun save() {
        if (saving) return
        val text = current()
        if (!route.isNew && !dirty) { Snacks.show("Değişiklik yok."); return }
        scope.launch {
            val msg = Dialogs.prompt(
                "Commit mesajı", "Mesaj",
                initial = settings.defaultCommitMessage.ifBlank { (if (route.isNew) "Add " else "Update ") + route.path.substringAfterLast('/') },
                confirmLabel = "Kaydet",
            )?.trim().orEmpty()
            if (msg.isEmpty()) return@launch
            saving = true
            try {
                val sha = g.repo.saveFile(
                    g.auth.token ?: "", route.path, text.toByteArray(Charsets.UTF_8), msg, route.mode,
                    g.auth.authorName, g.auth.authorEmail,
                )
                val repo = g.repo.selectedRepo
                if (repo != null) g.upload.recordExternalCommit(repo.owner, repo.name, g.repo.selectedBranch ?: "", msg, sha, 1)
                g.settings.success()
                Snacks.show("Kaydedildi.")
                g.nav.pop(true)
            } catch (e: GitHubApiException) {
                Snacks.show(e.message)
            } finally { saving = false }
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(route.path, maxLines = 1, overflow = TextOverflow.Ellipsis, fontSize = 15.sp) },
                navigationIcon = { IconButton(onClick = { leave() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
                actions = {
                    if (saving) CircularProgressIndicator(Modifier.padding(12.dp), strokeWidth = 2.dp)
                    else IconButton(onClick = { save() }) { Icon(Icons.Filled.Check, "Kaydet") }
                },
            )
        },
    ) { inner ->
        Column(Modifier.fillMaxSize().padding(inner).imePadding()) {
            val text = current()
            Text(
                "${text.count { it == '\n' } + 1} satır · ${text.length} karakter" + if (chunkMode) " · büyük dosya (bölümlü düzenleme)" else "",
                Modifier.padding(horizontal = 16.dp, vertical = 6.dp), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            if (chunkMode) {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    itemsIndexed(chunks) { i, c ->
                        GpTextField(c, { chunks[i] = it }, Modifier.fillMaxWidth(), mono = true, textSize = settings.previewFontSize.toFloat())
                    }
                }
            } else {
                Box(Modifier.fillMaxSize().padding(12.dp)) {
                    GpTextField(
                        single, { single = it }, Modifier.fillMaxSize(), mono = true,
                        textSize = settings.previewFontSize.toFloat(), placeholder = "Dosya içeriği...",
                    )
                }
            }
        }
    }
}
