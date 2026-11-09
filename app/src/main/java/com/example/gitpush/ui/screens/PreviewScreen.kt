package com.example.gitpush.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.background
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.model.GitFileItem
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.state.PreviewSource
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Route
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.ProgressSheet
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.components.SendBottomBar
import com.example.gitpush.ui.components.StatusBadge
import com.example.gitpush.ui.theme.AppTheme
import kotlinx.coroutines.launch

/** Repo ağacını yeniden okuyup planı tazeler, sonra Önizleme ekranını açar. */
suspend fun openPreview(source: PreviewSource, commitMessage: String): Boolean {
    val g = Graph
    val token = g.auth.token ?: return false
    val ok = Dialogs.withBusy("Repo'nun güncel durumu kontrol ediliyor...") { g.repo.refreshTree(token) }
    if (!ok) {
        Snacks.show(g.repo.treeError ?: "Repo dosya listesi alınamadı; gönderim güvenli olmadığı için durduruldu.")
        return false
    }
    g.upload.reclassifyAll(g.repo.treeIndex, g.repo.treeTruncated)
    g.nav.push(Route.Preview(source, commitMessage))
    return true
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PreviewScreen(source: PreviewSource, commitMessage: String) {
    val g = Graph
    val upload = g.upload
    upload.revision
    val scope = rememberCoroutineScope()
    val plan = remember { upload.planFor(source) }
    val repo = g.repo.selectedRepo
    val branch = g.repo.selectedBranch
    var showProgress by remember { mutableStateOf(false) }

    ScreenBack(enabled = !upload.isUploading) { g.nav.pop() }

    suspend fun doPush() {
        if (repo == null || branch == null) return
        showProgress = true
        val ok = upload.executePush(
            g.auth.token ?: "", repo.owner, repo.name, branch, commitMessage, plan, g.auth.authorName, g.auth.authorEmail,
        )
        if (ok) {
            showProgress = false
            g.settings.success()
            val result = upload.lastResult!!
            val url = upload.lastCommitUrl ?: "https://github.com/${repo.fullName}"
            upload.resetAfterPush()
            scope.launch { g.auth.token?.let { g.repo.refreshTree(it) } }
            g.nav.popToRoot()
            g.nav.push(Route.Result(result, url, repo.owner, repo.name, branch, repo.isPrivate))
        }
    }

    fun send() {
        scope.launch {
            if (plan.deletes.isNotEmpty()) {
                val ok = Dialogs.typedConfirm(
                    "${plan.deletes.size} dosya silinecek",
                    "Bu gönderim repodan dosya silecek. Silinecek: " + plan.deletes.take(5).joinToString(", ") { it.repoPath } +
                        if (plan.deletes.size > 5) " …" else "",
                    "sil",
                )
                if (!ok) return@launch
            }
            doPush()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Gönderimi Onayla") },
                navigationIcon = { IconButton(onClick = { if (!upload.isUploading) g.nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
            )
        },
        bottomBar = {
            SendBottomBar(
                summaryText = "${plan.adds.size} yeni · ${plan.updates.size} güncelleme · ${plan.deletes.size} silme",
                buttonLabel = "GitHub'a Gönder",
                onButtonPressed = if (!plan.hasBlockers && plan.hasChanges && !upload.isUploading) ({ send() }) else null,
                isLoading = upload.isUploading,
            )
        },
    ) { inner ->
        LazyColumn(Modifier.fillMaxSize().padding(inner), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item {
                Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(16.dp)) {
                    Text("${repo?.fullName ?: ""} · $branch", style = AppTheme.monoBold.copy(fontSize = 13.sp), color = MaterialTheme.colorScheme.primary)
                    Spacer(Modifier.height(6.dp))
                    Text(commitMessage, fontWeight = FontWeight.Bold)
                }
            }
            if (plan.treeUnknown) item { Banner("Repo durumu bilinmiyor; gönderim güvenlik nedeniyle engellendi. Geri dönüp yenileyin.", true) }
            if (plan.conflicts.isNotEmpty()) item { Banner("${plan.conflicts.size} dosyada çakışma var; düzeltmeden gönderilemez.", true) }
            if (g.repo.treeTruncated) item { Banner("Repo ağacı çok büyük olduğu için kısmi; bazı denetimler sınırlı yapılır.", false) }
            if (!plan.hasChanges && !plan.hasBlockers) item { Banner("Gönderilecek bir değişiklik yok.", false) }

            section("Çakışmalar", plan.conflicts)
            section("Silinecek", plan.deletes)
            section("Yeni dosyalar", plan.adds)
            section("Güncellenecek", plan.updates)
            section("Değişmedi (gönderilmeyecek)", plan.unchanged)
            section("Atlanan (üzerine yazma kapalı)", plan.skipped)
        }
    }

    if (showProgress) {
        ProgressSheet(
            currentStep = upload.uploadStep, current = upload.uploadProgressCurrent, total = upload.uploadProgressTotal,
            error = upload.uploadError,
            onRetry = if (upload.uploadError != null) ({
                scope.launch {
                    if (upload.uploadErrorKind == GitHubApiExceptionKinds.BRANCH_MOVED) {
                        showProgress = false
                        Snacks.show("Dal değişti; durum yenileniyor. Lütfen planı tekrar inceleyin.")
                        g.nav.pop()
                        openPreview(source, commitMessage)
                    } else doPush()
                }
            }) else null,
            onCancel = if (upload.uploadError != null) ({ showProgress = false }) else null,
        )
    }
}

private object GitHubApiExceptionKinds {
    const val BRANCH_MOVED = GitHubApiException.KIND_BRANCH_MOVED
}

private fun androidx.compose.foundation.lazy.LazyListScope.section(title: String, list: List<GitFileItem>) {
    if (list.isEmpty()) return
    item {
        Text("$title (${list.size})", style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 8.dp))
    }
    items(list.size) { i ->
        val f = list[i]
        Row(
            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.surfaceContainer).padding(12.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(f.repoPath, style = AppTheme.mono.copy(fontSize = 12.sp))
                if (f.status == GitFileStatus.Conflict) Text(f.conflictMessage ?: "Çakışma", fontSize = 11.sp, color = MaterialTheme.colorScheme.error)
            }
            Spacer(Modifier.width(8.dp))
            StatusBadge(f.status)
        }
    }
}

@Composable
private fun Banner(text: String, error: Boolean) {
    val cs = MaterialTheme.colorScheme
    Box(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
            .background(if (error) cs.errorContainer else cs.tertiaryContainer).padding(12.dp),
    ) { Text(text, fontSize = 13.sp, color = if (error) cs.onErrorContainer else cs.onTertiaryContainer) }
}
