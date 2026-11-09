package com.example.gitpush.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.DriveFileRenameOutline
import androidx.compose.material.icons.outlined.FolderOff
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Source
import androidx.compose.material.icons.outlined.Timeline
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.material3.rememberModalBottomSheetState
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.model.RepoEntry
import com.example.gitpush.model.RepoSortMode
import com.example.gitpush.model.breadcrumbsFor
import com.example.gitpush.model.buildDirectoryListing
import com.example.gitpush.model.searchRepoTree
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Route
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.EmptyState
import com.example.gitpush.ui.components.ErrorView
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.fileVisualFor
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.copyToClipboard
import com.example.gitpush.util.formatBytes
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun RepoBrowserScreen() {
    val g = Graph
    val repoP = g.repo
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val settings = g.settings.settings

    var dir by remember { mutableStateOf("") }
    var query by remember { mutableStateOf("") }
    var searchOpen by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<Set<String>>(emptySet()) }
    var sortMenu by remember { mutableStateOf(false) }
    var actionsFor by remember { mutableStateOf<RepoEntry?>(null) }

    val repo = repoP.selectedRepo
    val branch = repoP.selectedBranch
    val token = g.auth.token ?: ""
    val selectMode = selected.isNotEmpty()

    // Dal/depo değişince (ağaç sıfırlanınca) başa dön
    LaunchedEffect(repo?.id, branch) { dir = ""; query = ""; selected = emptySet() }

    val searching = query.trim().isNotEmpty()
    val listing = remember(repoP.treeRevision, dir, settings.repoSort, settings.showHiddenFiles, query) {
        if (searching) searchRepoTree(repoP.currentTree, query, settings.showHiddenFiles)
        else buildDirectoryListing(repoP.currentTree, dir, settings.repoSort, settings.showHiddenFiles)
    }

    ScreenBack(enabled = selectMode || searching || dir.isNotEmpty()) {
        when {
            selectMode -> selected = emptySet()
            searching -> { query = ""; searchOpen = false }
            else -> dir = dir.substringBeforeLast('/', "")
        }
    }

    if (repo == null || branch == null) {
        EmptyState(Icons.Outlined.Source, "Dosyaları görmek için önce bir depo seçin.", "Depo Seç") { g.nav.push(Route.RepoPicker) }
        return
    }

    fun defaultMsg(fallback: String) = settings.defaultCommitMessage.ifBlank { fallback }

    fun afterCommit(sha: String, message: String, count: Int) {
        scope.launch {
            g.upload.recordExternalCommit(repo.owner, repo.name, branch, message, sha, count)
            g.settings.success()
        }
    }

    fun deleteEntries(entries: List<RepoEntry>) {
        scope.launch {
            val hasDir = entries.any { it.isDir }
            val label = if (entries.size == 1) entries.first().name else "${entries.size} öğe"
            val ok = if (hasDir) {
                Dialogs.typedConfirm("Silinsin mi?", "$label ve altındaki tüm dosyalar tek commit ile silinecek.", "sil")
            } else {
                Dialogs.confirm("Silinsin mi?", "$label tek commit ile silinecek.", "Sil", destructive = true)
            }
            if (!ok) return@launch
            val msg = Dialogs.prompt("Commit mesajı", "Mesaj", initial = defaultMsg("Delete $label"), confirmLabel = "Sil")?.trim().orEmpty()
            if (msg.isEmpty()) return@launch
            try {
                val r = Dialogs.withBusy("Siliniyor...") {
                    repoP.deleteEntries(token, entries, msg, g.auth.authorName, g.auth.authorEmail)
                }
                selected = emptySet()
                afterCommit(r.commitSha, msg, r.fileCount)
                Snacks.show("${r.fileCount} dosya silindi.")
            } catch (e: GitHubApiException) { Snacks.show(e.message) }
        }
    }

    fun moveEntry(e: RepoEntry) {
        scope.launch {
            val target = Dialogs.prompt(
                if (e.isDir) "Klasörü Taşı / Yeniden Adlandır" else "Dosyayı Taşı / Yeniden Adlandır",
                "Yeni yol", initial = e.path, mono = true, confirmLabel = "İleri",
            )?.trim().orEmpty()
            if (target.isEmpty()) return@launch
            try {
                val moves = repoP.planMove(e, target)
                val ok = Dialogs.confirm("Taşıma Onayı", "${moves.size} dosya taşınacak:\n${e.path}  →  $target", "Taşı")
                if (!ok) return@launch
                val msg = Dialogs.prompt("Commit mesajı", "Mesaj", initial = defaultMsg("Move ${e.name}"), confirmLabel = "Taşı")?.trim().orEmpty()
                if (msg.isEmpty()) return@launch
                val sha = Dialogs.withBusy("Taşınıyor...") { repoP.applyMoves(token, moves, msg, g.auth.authorName, g.auth.authorEmail) }
                afterCommit(sha, msg, moves.size)
                Snacks.show("${moves.size} dosya taşındı.")
            } catch (ex: GitHubApiException) { Snacks.show(ex.message) }
        }
    }

    fun newFile() {
        scope.launch {
            val raw = Dialogs.prompt(
                "Yeni Dosya", "Dosya yolu", initial = if (dir.isEmpty()) "" else "$dir/", mono = true,
                message = "Yol repo köküne göre; klasörler otomatik oluşturulur.", confirmLabel = "Oluştur",
            )?.trim().orEmpty()
            if (raw.isEmpty()) return@launch
            val problem = repoP.newFilePathProblem(raw)
            if (problem != null) { Snacks.show(problem); return@launch }
            g.nav.push(Route.FileEditor(path = raw, isNew = true))
        }
    }

    Box(Modifier.fillMaxSize()) {
        Column(Modifier.fillMaxSize()) {
            // Araç çubuğu
            Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                if (selectMode) {
                    IconButton(onClick = { selected = emptySet() }) { Icon(Icons.Filled.Close, "Seçimi kapat") }
                    Text("${selected.size} seçili", Modifier.weight(1f), fontWeight = FontWeight.Bold)
                    IconButton(onClick = {
                        val items = listing.filter { it.path in selected }
                        if (items.isNotEmpty()) deleteEntries(items)
                    }) { Icon(Icons.Outlined.DeleteOutline, "Sil", tint = MaterialTheme.colorScheme.error) }
                } else {
                    GpTextField(
                        query, { query = it }, Modifier.weight(1f),
                        placeholder = "Depoda ara...", singleLine = true, leadingIcon = Icons.Filled.Search,
                        trailing = if (query.isNotEmpty()) ({ IconButton(onClick = { query = "" }) { Icon(Icons.Filled.Close, null) } }) else null,
                    )
                    Box {
                        IconButton(onClick = { sortMenu = true }) { Icon(Icons.Filled.Sort, "Sırala") }
                        DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                            for (m in RepoSortMode.values()) {
                                DropdownMenuItem(
                                    text = { Text(m.label) },
                                    leadingIcon = { if (settings.repoSort == m) Icon(Icons.Filled.Check, null) },
                                    onClick = { sortMenu = false; g.settings.update { it.copy(repoSort = m) } },
                                )
                            }
                            DropdownMenuItem(
                                text = { Text(if (settings.showHiddenFiles) "Gizli dosyaları gizle" else "Gizli dosyaları göster") },
                                onClick = { sortMenu = false; g.settings.update { it.copy(showHiddenFiles = !it.showHiddenFiles) } },
                            )
                        }
                    }
                    IconButton(onClick = { g.nav.push(Route.Commits(null)) }) { Icon(Icons.Outlined.History, "Commit geçmişi") }
                    IconButton(onClick = { scope.launch { repoP.refreshTree(token) } }) { Icon(Icons.Filled.Refresh, "Yenile") }
                }
            }

            // Yol (breadcrumb)
            if (!searching) {
                val crumbs = breadcrumbsFor(dir)
                val lazy = rememberLazyListState()
                LaunchedEffect(dir) { lazy.scrollToItem((crumbs.size - 1).coerceAtLeast(0)) }
                LazyRow(Modifier.fillMaxWidth().padding(horizontal = 12.dp), state = lazy, verticalAlignment = Alignment.CenterVertically) {
                    items(crumbs.size) { i ->
                        val c = crumbs[i]
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                c.label, style = AppTheme.mono.copy(fontSize = 12.sp),
                                color = if (i == crumbs.size - 1) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
                                fontWeight = if (i == crumbs.size - 1) FontWeight.Bold else FontWeight.Normal,
                                modifier = Modifier.clickable { dir = c.path }.padding(horizontal = 4.dp, vertical = 6.dp),
                            )
                            if (i < crumbs.size - 1) Icon(Icons.Filled.ChevronRight, null, Modifier.size(14.dp))
                        }
                    }
                }
            }

            if (repoP.treeTruncated) {
                Text(
                    "Depo çok büyük olduğu için dosya listesi kısmi. Taşıma/silme güvenlik nedeniyle devre dışı olabilir.",
                    Modifier.fillMaxWidth().background(MaterialTheme.colorScheme.errorContainer).padding(10.dp),
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onErrorContainer,
                )
            }
            val dirs = listing.count { it.isDir }
            Text(
                if (searching) "${listing.size} sonuç" else "$dirs klasör · ${listing.size - dirs} dosya",
                Modifier.padding(horizontal = 16.dp, vertical = 4.dp), fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            HorizontalDivider()

            PullToRefreshBox(isRefreshing = repoP.isTreeLoading, onRefresh = { scope.launch { repoP.refreshTree(token) } }, modifier = Modifier.fillMaxSize()) {
                when {
                    repoP.treeError != null && repoP.currentTree.isEmpty() ->
                        ErrorView(repoP.treeError!!) { scope.launch { repoP.refreshTree(token) } }
                    listing.isEmpty() && !repoP.isTreeLoading ->
                        EmptyState(Icons.Outlined.FolderOff, if (searching) "Eşleşen yol bulunamadı." else "Bu klasör boş.")
                    else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(bottom = 96.dp)) {
                        items(listing, key = { it.path }) { e ->
                            val vis = fileVisualFor(e.extension)
                            val isSel = e.path in selected
                            ListItem(
                                leadingContent = {
                                    if (selectMode) Checkbox(checked = isSel, onCheckedChange = { selected = if (isSel) selected - e.path else selected + e.path })
                                    else if (e.isDir) Icon(Icons.Filled.Folder, null, tint = MaterialTheme.colorScheme.primary)
                                    else Icon(vis.icon, null, tint = vis.color)
                                },
                                headlineContent = {
                                    Text(
                                        if (searching) e.path else e.name, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                        fontWeight = if (e.isDir) FontWeight.SemiBold else FontWeight.Normal,
                                    )
                                },
                                supportingContent = {
                                    Text(
                                        when {
                                            e.isSubmodule -> "alt modül"
                                            e.isDir -> "${e.fileCount} dosya · ${formatBytes(e.size)}"
                                            else -> formatBytes(e.size)
                                        },
                                        fontSize = 12.sp,
                                    )
                                },
                                trailingContent = {
                                    if (!selectMode) IconButton(onClick = { actionsFor = e }) { Icon(Icons.Filled.MoreVert, null) }
                                },
                                modifier = Modifier.combinedClickable(
                                    onClick = {
                                        when {
                                            selectMode -> selected = if (isSel) selected - e.path else selected + e.path
                                            e.isDir -> { dir = e.path; query = "" }
                                            e.isSubmodule -> Snacks.show("Alt modüller görüntülenemez.")
                                            else -> g.nav.push(Route.FileDetail(e))
                                        }
                                    },
                                    onLongClick = { selected = selected + e.path },
                                ),
                            )
                        }
                    }
                }
            }
        }

        if (!selectMode) {
            ExtendedFloatingActionButton(
                onClick = { newFile() }, icon = { Icon(Icons.Filled.Add, null) }, text = { Text("Yeni dosya") },
                modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
            )
        }
    }

    actionsFor?.let { e ->
        ModalBottomSheet(onDismissRequest = { actionsFor = null }, sheetState = rememberModalBottomSheetState()) {
            Column(Modifier.padding(bottom = 16.dp)) {
                Text(e.path, Modifier.padding(horizontal = 20.dp, vertical = 8.dp), style = AppTheme.monoBold.copy(fontSize = 13.sp), maxLines = 2)
                ListItem(
                    leadingContent = { Icon(Icons.Outlined.ContentCopy, null) }, headlineContent = { Text("Yolu kopyala") },
                    modifier = Modifier.clickable { copyToClipboard(ctx, e.path); actionsFor = null; Snacks.show("Yol kopyalandı") },
                )
                ListItem(
                    leadingContent = { Icon(Icons.Outlined.Timeline, null) }, headlineContent = { Text("Commit geçmişi") },
                    modifier = Modifier.clickable { actionsFor = null; g.nav.push(Route.Commits(e.path)) },
                )
                if (!e.isSubmodule) {
                    ListItem(
                        leadingContent = { Icon(Icons.Outlined.DriveFileRenameOutline, null) }, headlineContent = { Text("Taşı / yeniden adlandır") },
                        modifier = Modifier.clickable { actionsFor = null; moveEntry(e) },
                    )
                    ListItem(
                        leadingContent = { Icon(Icons.Outlined.DeleteOutline, null, tint = MaterialTheme.colorScheme.error) },
                        headlineContent = { Text("Sil", color = MaterialTheme.colorScheme.error) },
                        modifier = Modifier.clickable { actionsFor = null; deleteEntries(listOf(e)) },
                    )
                }
            }
        }
    }
}
