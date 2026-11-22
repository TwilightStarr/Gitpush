package com.example.gitpush.ui.screens

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.FolderZip
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.service.ZipServiceException
import com.example.gitpush.state.PreviewSource
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.FileTreeView
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.components.SectionCard
import com.example.gitpush.ui.components.SendBottomBar
import com.example.gitpush.util.formatBytes
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ZipTransferScreen() {
    val g = Graph
    val up = g.upload
    up.revision
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var commitMsg by remember { mutableStateOf(g.settings.settings.defaultCommitMessage.ifBlank { "Update from ZIP" }) }
    var prefix by remember { mutableStateOf(up.zipPrefix) }

    fun close() {
        up.resetZip()
        g.nav.pop()
    }
    ScreenBack(enabled = !up.zipBusy) { close() }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            try {
                up.importZip(ctx, uri)
                g.auth.token?.let { g.repo.refreshTree(it) }
                up.reclassifyAll(g.repo.treeIndex, g.repo.treeTruncated)
                if (up.zipFiles.isEmpty()) Snacks.show("ZIP içinde gönderilebilir dosya bulunamadı.")
            } catch (e: ZipServiceException) {
                Snacks.show(e.message)
            } catch (e: kotlinx.coroutines.CancellationException) {
                throw e
            } catch (e: java.io.IOException) {
                Snacks.show(e.message ?: "ZIP okunamadı.")
            } catch (e: OutOfMemoryError) {
                Snacks.show("Bellek yetersiz kaldı; ZIP işlenemedi.")
            }
        }
    }
    val zipMimes = arrayOf("application/zip", "application/x-zip-compressed", "application/x-zip", "application/octet-stream")

    val selectedFiles = up.zipFiles.filter { it.isSelected }
    val plan = up.planFor(PreviewSource.Zip)

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("ZIP'ten Aktar") },
                navigationIcon = { IconButton(onClick = { if (!up.zipBusy) close() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
            )
        },
        bottomBar = {
            if (up.zipFileName != null && !up.zipBusy) {
                SendBottomBar(
                    summaryText = "${selectedFiles.size} / ${up.zipFiles.size} dosya seçili",
                    buttonLabel = "İncele",
                    onButtonPressed = if (selectedFiles.isNotEmpty() || (up.zipDeleteUnlisted && up.zipDeleteItems.isNotEmpty())) ({
                        val msg = commitMsg.trim()
                        if (msg.isEmpty()) Snacks.show("Commit mesajı boş olamaz.")
                        else scope.launch { openPreview(PreviewSource.Zip, msg) }
                    }) else null,
                )
            }
        },
    ) { inner ->
        Column(Modifier.fillMaxSize().padding(inner).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            if (up.zipBusy) {
                SectionCard("ZIP hazırlanıyor") {
                    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        LinearProgressIndicator(Modifier.fillMaxWidth())
                        Text(up.zipBusyText, fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(
                            "Büyük arşivlerde bu birkaç dakika sürebilir. Lütfen uygulamayı kapatmayın.",
                            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            } else if (up.zipFileName == null) {
                SectionCard("ZIP arşivi seçin") {
                    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Outlined.FolderZip, null, Modifier.size(56.dp), tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.height(12.dp))
                        Text("Dosyalar arşivden çıkarılır, repo ile karşılaştırılır ve tek commit ile gönderilir.", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(16.dp))
                        Button(onClick = { picker.launch(zipMimes) }) { Text("ZIP Seç") }
                    }
                }
            } else {
                SectionCard("Arşiv", trailing = { TextButton(onClick = { picker.launch(zipMimes) }) { Text("Değiştir") } }) {
                    Text(up.zipFileName ?: "", fontWeight = FontWeight.Bold)
                    Text("${formatBytes(up.zipFileSize)} · ${up.zipFiles.size} dosya", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    if (up.zipOversizedEntries.isNotEmpty()) {
                        Spacer(Modifier.height(6.dp))
                        Text(
                            "${up.zipOversizedEntries.size} dosya 100 MB GitHub sınırını aştığı için atlandı: " +
                                up.zipOversizedEntries.take(3).joinToString(", ") + if (up.zipOversizedEntries.size > 3) " …" else "",
                            fontSize = 12.sp, color = MaterialTheme.colorScheme.error,
                        )
                    }
                    if (up.zipInvalidEntries.isNotEmpty()) {
                        Spacer(Modifier.height(6.dp))
                        Text("${up.zipInvalidEntries.size} güvensiz/geçersiz girdi atlandı.", fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                    }
                }
                SectionCard("Commit") {
                    GpTextField(commitMsg, { commitMsg = it }, Modifier.fillMaxWidth(), label = "Commit mesajı", singleLine = true)
                }
                SectionCard("Seçenekler") {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        ToggleRow("Tek üst klasörü kaldır", up.zipStripRootDir) { up.setZipStripRootDir(it) }
                        ToggleRow("Repodaki konuma otomatik hizala", up.zipAutoAlign) { up.setZipAutoAlign(it) }
                        ToggleRow("Mevcut dosyaların üzerine yaz", up.zipOverwriteExisting) { up.setZipOverwriteExisting(it) }
                        ToggleRow("ZIP'te olmayan repo dosyalarını sil", up.zipDeleteUnlisted) { v ->
                            if (!v) up.setZipDeleteUnlisted(false) else scope.launch {
                                val ok = Dialogs.confirm(
                                    "Dikkat: silme etkinleştirilsin mi?",
                                    "ZIP'te bulunmayan ve hedef klasör kapsamındaki repo dosyaları silinecek. Önizlemede ayrıca onay istenir.",
                                    "Etkinleştir", destructive = true,
                                )
                                if (ok) up.setZipDeleteUnlisted(true)
                            }
                        }
                        GpTextField(
                            prefix, { prefix = it; up.setZipPrefix(it) }, Modifier.fillMaxWidth(),
                            label = "Hedef klasör öneki (isteğe bağlı)", placeholder = "lib/", mono = true, singleLine = true,
                        )
                    }
                }
                up.zipAlignNotice?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.primary) }
                up.zipDeleteNotice?.let { Text(it, fontSize = 12.sp, color = MaterialTheme.colorScheme.error) }
                if (up.zipDeleteUnlisted && up.zipDeleteItems.isNotEmpty()) {
                    Text("${up.zipDeleteItems.size} repo dosyası silinecek.", fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
                }
                SectionCard(
                    "Dosyalar",
                    trailing = {
                        Row {
                            TextButton(onClick = { up.selectAllZipFiles(true) }) { Text("Tümü") }
                            TextButton(onClick = { up.selectAllZipFiles(false) }) { Text("Hiçbiri") }
                        }
                    },
                ) {
                    Text(
                        "${plan.adds.size} yeni · ${plan.updates.size} güncelleme · ${plan.unchanged.size} değişmedi · ${plan.conflicts.size} çakışma",
                        fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    FileTreeView(up.zipFiles) { i -> up.toggleZipFileSelection(i, !up.zipFiles[i].isSelected) }
                }
            }
        }
    }
}

@Composable
private fun ToggleRow(label: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), fontSize = 14.sp)
        Spacer(Modifier.width(8.dp))
        Switch(checked = value, onCheckedChange = onChange)
    }
}
