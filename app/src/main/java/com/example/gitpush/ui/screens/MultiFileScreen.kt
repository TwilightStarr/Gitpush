package com.example.gitpush.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.Terminal
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import com.example.gitpush.Graph
import com.example.gitpush.model.GitFileItem
import com.example.gitpush.state.PreviewSource
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.EmptyState
import com.example.gitpush.ui.components.FileCard
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.components.PathPickerSheet
import com.example.gitpush.ui.components.QuickCommandChips
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.components.SendBottomBar
import com.example.gitpush.util.readPickedFile
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MultiFileScreen() {
    val g = Graph
    val up = g.upload
    up.revision
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var commitMsg by remember { mutableStateOf(g.settings.settings.defaultCommitMessage.ifBlank { "Update files" }) }
    var shortcuts by remember { mutableStateOf<List<String>>(emptyList()) }
    var selectedIds by remember { mutableStateOf<Set<Int>>(emptySet()) }
    var pickerFor by remember { mutableStateOf<GitFileItem?>(null) }

    LaunchedEffect(Unit) { shortcuts = g.storage.getShortcuts() }

    fun close() {
        up.clearMultiFiles()
        g.nav.pop()
    }
    ScreenBack { close() }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        scope.launch {
            val items = ArrayList<GitFileItem>()
            var skipped = 0
            for (u in uris) {
                val f = readPickedFile(ctx, u)
                if (f == null) { skipped++; continue }
                items.add(GitFileItem(localPath = f.uri, repoPath = f.name, size = f.size.toInt(), bytes = f.bytes, sourceName = f.name))
            }
            if (items.isNotEmpty()) {
                g.auth.token?.let { if (g.repo.treeIndex == null) g.repo.refreshTree(it) }
                up.reclassifyAll(g.repo.treeIndex, g.repo.treeTruncated)
                up.addMultiFiles(items)
            }
            if (skipped > 0) Snacks.show("$skipped dosya okunamadı veya 100 MB sınırını aşıyor.")
        }
    }

    val files = up.multiFiles
    val sendable = files.count { it.status != com.example.gitpush.model.GitFileStatus.Unchanged }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Dosyaları Güncelle") },
                navigationIcon = { IconButton(onClick = { close() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
                actions = {
                    IconButton(onClick = {
                        scope.launch {
                            val raw = Dialogs.prompt(
                                "Metinle yol komutu", "Komutlar",
                                message = "Her satır:\ndosya.dart=lib/screens/dosya.dart\nlib/models/: a.dart b.dart\n(# ile başlayan satırlar yorumdur)",
                                confirmLabel = "Uygula", mono = true,
                            ) ?: return@launch
                            up.parseAndApplyTextCommands(raw)
                        }
                    }) { Icon(Icons.Outlined.Terminal, "Metin komutu") }
                    IconButton(onClick = {
                        val removed = up.clearMultiFiles()
                        selectedIds = emptySet()
                        if (removed.isNotEmpty()) Snacks.show("Liste temizlendi", "Geri al") { up.restoreMultiFiles(removed) }
                    }) { Icon(Icons.Outlined.DeleteSweep, "Listeyi temizle") }
                },
            )
        },
        bottomBar = {
            SendBottomBar(
                summaryText = "${files.size} dosya · $sendable gönderilecek",
                buttonLabel = "İncele",
                onButtonPressed = if (files.isNotEmpty()) ({
                    val msg = commitMsg.trim()
                    if (msg.isEmpty()) Snacks.show("Commit mesajı boş olamaz.")
                    else scope.launch { openPreview(PreviewSource.Multi, msg) }
                }) else null,
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(onClick = { picker.launch(arrayOf("*/*")) }, icon = { Icon(Icons.Filled.Add, null) }, text = { Text("Dosya ekle") })
        },
    ) { inner ->
        Column(Modifier.fillMaxSize().padding(inner)) {
            GpTextField(commitMsg, { commitMsg = it }, Modifier.fillMaxWidth().padding(16.dp, 8.dp), label = "Commit mesajı", singleLine = true)
            QuickCommandChips(
                shortcuts,
                onSelect = { up.applyShortcutToMultiFiles(it, selectedIds) },
                onAddShortcut = {
                    scope.launch {
                        val v = Dialogs.prompt("Yeni Kısayol", "Klasör yolu", mono = true, message = "Örn: lib/widgets/") ?: return@launch
                        if (g.storage.addShortcut(v)) shortcuts = g.storage.getShortcuts() else Snacks.show("Kısayol eklenemedi (boş, çok uzun veya zaten var).")
                    }
                },
            )
            Spacer(Modifier.height(8.dp))
            if (files.isEmpty()) {
                EmptyState(Icons.Outlined.UploadFile, "Henüz dosya eklenmedi. Birden fazla dosya seçip her birine farklı bir repo yolu verebilirsiniz.", "Dosya Seç") { picker.launch(arrayOf("*/*")) }
            } else {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 4.dp, 16.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    items(files.toList(), key = { it.id }) { f ->
                        FileCard(
                            file = f,
                            isSelected = f.id in selectedIds,
                            selectionMode = selectedIds.isNotEmpty(),
                            onSelectPath = { pickerFor = f },
                            onPathChanged = { up.updateMultiFilePathById(f.id, it) },
                            onDelete = {
                                val idx = files.indexOfFirst { it.id == f.id }
                                up.removeMultiFile(idx)
                                selectedIds = selectedIds - f.id
                                Snacks.show("Dosya çıkarıldı", "Geri al") { up.restoreMultiFiles(listOf(f), idx) }
                            },
                            onToggleSelect = { selectedIds = if (f.id in selectedIds) selectedIds - f.id else selectedIds + f.id },
                        )
                    }
                }
            }
        }
    }

    pickerFor?.let { f ->
        PathPickerSheet(
            repoTree = g.repo.currentTree, fileName = f.sourceName,
            onPathSelected = { up.updateMultiFilePathById(f.id, it) },
            onDismiss = { pickerFor = null },
        )
    }
}
