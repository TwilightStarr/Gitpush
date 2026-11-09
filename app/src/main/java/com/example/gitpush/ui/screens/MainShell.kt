package com.example.gitpush.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.History
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.UploadFile
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderZip
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Source
import androidx.compose.material.icons.outlined.Timeline
import androidx.compose.material.icons.outlined.UploadFile
import androidx.compose.material3.Card
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Route
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.EmptyState
import com.example.gitpush.ui.components.GpHeader
import com.example.gitpush.ui.components.KeepAlive
import com.example.gitpush.ui.components.ModeCard
import com.example.gitpush.ui.components.RepoBranchChip
import com.example.gitpush.ui.components.SectionCard
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.openExternalUrl
import com.example.gitpush.util.shortSha
import kotlinx.coroutines.launch

private class Tab(val title: String, val label: String, val icon: ImageVector, val selectedIcon: ImageVector)

private val tabs = listOf(
    Tab("Gönder", "Gönder", Icons.Outlined.UploadFile, Icons.Filled.UploadFile),
    Tab("Repo Tarayıcı", "Repo", Icons.Outlined.Folder, Icons.Filled.Folder),
    Tab("GitHub Actions", "Actions", Icons.Outlined.Bolt, Icons.Filled.Bolt),
    Tab("Geçmiş", "Geçmiş", Icons.Outlined.History, Icons.Filled.History),
    Tab("Ayarlar", "Ayarlar", Icons.Outlined.Settings, Icons.Filled.Settings),
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainShell() {
    val g = Graph
    var current by rememberSaveable { mutableIntStateOf(0) }
    val cfg = LocalConfiguration.current
    val isTablet = minOf(cfg.screenWidthDp, cfg.screenHeightDp) >= 600

    LaunchedEffect(Unit) {
        val t = g.auth.token
        if (t != null && g.repo.repositories.isEmpty()) g.repo.loadRepositories(t)
    }
    // Repo ağacı değişince Mod A/B listelerini yeniden sınıflandır
    LaunchedEffect(g.repo.treeRevision) {
        g.upload.reclassifyAll(g.repo.treeIndex, g.repo.treeTruncated)
    }

    val content: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Box(Modifier.widthIn(max = if (isTablet) 900.dp else 640.dp).fillMaxSize()) {
                KeepAlive(current == 0) { SendScreen() }
                KeepAlive(current == 1) { RepoBrowserScreen() }
                KeepAlive(current == 2) { ActionsScreen(isActive = current == 2) }
                KeepAlive(current == 3) { HistoryScreen() }
                KeepAlive(current == 4) { SettingsScreen(isActive = current == 4) }
            }
        }
    }

    Scaffold(
        topBar = {
            GpHeader(tabs[current].title) {
                RepoBranchChip(g.repo.selectedRepo?.fullName, g.repo.selectedBranch) { g.nav.push(Route.RepoPicker) }
            }
        },
        bottomBar = {
            if (!isTablet) {
                NavigationBar(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
                    tabs.forEachIndexed { i, t ->
                        NavigationBarItem(
                            selected = current == i, onClick = { current = i },
                            icon = { Icon(if (current == i) t.selectedIcon else t.icon, null) },
                            label = { Text(t.label) },
                        )
                    }
                }
            }
        },
    ) { inner ->
        if (isTablet) {
            Row(Modifier.fillMaxSize().padding(inner)) {
                NavigationRail(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
                    tabs.forEachIndexed { i, t ->
                        NavigationRailItem(
                            selected = current == i, onClick = { current = i },
                            icon = { Icon(if (current == i) t.selectedIcon else t.icon, null) },
                            label = { Text(t.label) },
                        )
                    }
                }
                Box(Modifier.weight(1f).fillMaxSize()) { content() }
            }
        } else {
            Box(Modifier.fillMaxSize().padding(inner)) { content() }
        }
    }
}

// ───────────────────────── Gönder ─────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SendScreen() {
    val g = Graph
    val upload = g.upload
    upload.revision
    val repo = g.repo.selectedRepo
    if (repo == null) {
        EmptyState(
            Icons.Outlined.Source, "Dosya göndermek için önce bir GitHub deposu seçmelisiniz.",
            actionLabel = "Depo Seç", onAction = { g.nav.push(Route.RepoPicker) },
        )
        return
    }
    val branch = g.repo.selectedBranch ?: repo.defaultBranch
    val scope = rememberCoroutineScope()
    var refreshing by remember { mutableStateOf(false) }

    PullToRefreshBox(
        isRefreshing = refreshing,
        onRefresh = {
            scope.launch {
                refreshing = true
                g.auth.token?.let { g.repo.loadBranches(it, repo) }
                refreshing = false
            }
        },
        modifier = Modifier.fillMaxSize(),
    ) {
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
            Text(
                "Hedef dal: $branch", style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 4.dp, bottom = 12.dp),
            )
            ModeCard(
                "ZIP'ten Aktar",
                "Telefonda seçtiğiniz bir ZIP arşivini açın, dosya ağacını inceleyin ve tek seferde repoya yükleyin.",
                Icons.Outlined.FolderZip, AppTheme.statusUpdate, "MOD A",
            ) { g.nav.push(Route.Zip) }
            Spacer(Modifier.height(12.dp))
            ModeCard(
                "Dosyaları Güncelle",
                "Birden fazla dosyayı, her biri farklı repo yoluna (klasör yoksa otomatik oluşturularak) tek commit ile yükleyin.",
                Icons.Outlined.UploadFile, AppTheme.statusNew, "MOD B",
            ) { g.nav.push(Route.Multi) }
            Spacer(Modifier.height(16.dp))
            val last = g.upload.historyItems.firstOrNull()
            if (last != null) {
                SectionCard("Son Gönderim") {
                    Column {
                        Text(last.commitMessage, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold)
                        Spacer(Modifier.height(4.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(shortSha(last.commitSha), style = AppTheme.mono.copy(fontSize = 12.sp), color = MaterialTheme.colorScheme.primary)
                            Text("${last.filesCount} dosya", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                }
            }
        }
    }
}

// ───────────────────────── Geçmiş ─────────────────────────

@Composable
fun HistoryScreen() {
    val g = Graph
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val history = g.upload.historyItems
    if (history.isEmpty()) {
        EmptyState(Icons.Outlined.History, "Henüz bu uygulamadan bir gönderim yapılmadı.")
        return
    }
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp), verticalAlignment = Alignment.CenterVertically) {
            Text("${history.size} gönderim", Modifier.weight(1f), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            IconButton(onClick = {
                scope.launch {
                    val ok = Dialogs.confirm("Geçmiş Temizlensin mi?", "Tüm yerel gönderim kayıtları silinecek.", destructive = true)
                    if (ok) g.upload.clearHistory()
                }
            }) { Icon(Icons.Outlined.DeleteOutline, "Geçmişi temizle") }
        }
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp, 4.dp, 16.dp, 16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(history, key = { it.id }) { item ->
                Card(
                    onClick = {
                        if (!openExternalUrl(ctx, item.commitUrl)) Snacks.show("Link açılamadı.")
                    },
                ) {
                    ListItem(
                        leadingContent = { Icon(Icons.Outlined.Timeline, null, tint = AppTheme.statusNew) },
                        headlineContent = { Text(item.commitMessage, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                        supportingContent = {
                            Text("${item.repoFullName} (${item.branch}) · ${shortSha(item.commitSha)}", style = AppTheme.mono.copy(fontSize = 11.sp))
                        },
                        trailingContent = { Icon(Icons.Outlined.OpenInBrowser, null, Modifier.size(18.dp)) },
                    )
                }
            }
        }
    }
}
