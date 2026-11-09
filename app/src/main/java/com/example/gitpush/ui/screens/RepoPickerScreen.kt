package com.example.gitpush.ui.screens

import androidx.compose.foundation.ExperimentalFoundationApi
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
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Sort
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import com.example.gitpush.Graph
import com.example.gitpush.model.GitHubRepo
import com.example.gitpush.model.RepoListSort
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.EmptyState
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.timeAgo
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun RepoPickerScreen() {
    val g = Graph
    val repoP = g.repo
    val scope = rememberCoroutineScope()
    var query by remember { mutableStateOf("") }
    var expandedId by remember { mutableStateOf<Long?>(repoP.selectedRepo?.id) }
    var sortMenu by remember { mutableStateOf(false) }
    var newRepoDialog by remember { mutableStateOf(false) }
    val token = g.auth.token ?: ""

    ScreenBack { g.nav.pop() }

    val repos = run {
        val q = query.trim().lowercase()
        val filtered = repoP.repositories.filter { q.isEmpty() || it.fullName.lowercase().contains(q) }
        when (g.settings.settings.repoListSort) {
            RepoListSort.Recent -> filtered.sortedByDescending { it.updatedAt ?: 0L }
            RepoListSort.Name -> filtered.sortedBy { it.fullName.lowercase() }
            RepoListSort.PrivateFirst -> filtered.sortedWith(compareByDescending<GitHubRepo> { it.isPrivate }.thenBy { it.fullName.lowercase() })
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Depo ve Dal Seç") },
                navigationIcon = { IconButton(onClick = { g.nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
                actions = {
                    Box {
                        IconButton(onClick = { sortMenu = true }) { Icon(Icons.Filled.Sort, "Sırala") }
                        DropdownMenu(expanded = sortMenu, onDismissRequest = { sortMenu = false }) {
                            for (s in RepoListSort.values()) {
                                DropdownMenuItem(
                                    text = { Text(s.label) },
                                    leadingIcon = { if (g.settings.settings.repoListSort == s) Icon(Icons.Filled.Check, null) },
                                    onClick = { sortMenu = false; g.settings.update { it.copy(repoListSort = s) } },
                                )
                            }
                        }
                    }
                    IconButton(onClick = { scope.launch { repoP.loadRepositories(token) } }) { Icon(Icons.Filled.Refresh, "Yenile") }
                },
            )
        },
        floatingActionButton = {
            ExtendedFloatingActionButton(onClick = { newRepoDialog = true }, icon = { Icon(Icons.Filled.Add, null) }, text = { Text("Yeni Depo") })
        },
    ) { inner ->
        Column(Modifier.fillMaxSize().padding(inner)) {
            if (repoP.isLoading) LinearProgressIndicator(Modifier.fillMaxWidth())
            GpTextField(
                query, { query = it }, Modifier.fillMaxWidth().padding(16.dp, 8.dp),
                placeholder = "Depo ara...", singleLine = true, leadingIcon = Icons.Filled.Search,
            )
            repoP.errorMessage?.let { Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp, 4.dp)) }
            if (repos.isEmpty() && !repoP.isLoading) {
                EmptyState(Icons.Outlined.AccountTree, "Depo bulunamadı.")
            } else {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 4.dp, 16.dp, 96.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(repos, key = { it.id }) { repo ->
                        val selected = repoP.selectedRepo?.id == repo.id
                        val expanded = expandedId == repo.id
                        Card(
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
                        ) {
                            ListItem(
                                leadingContent = {
                                    Icon(if (repo.isPrivate) Icons.Filled.Lock else Icons.Outlined.Public, null, tint = MaterialTheme.colorScheme.primary)
                                },
                                headlineContent = { Text(repo.fullName, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                supportingContent = {
                                    Text(
                                        (repo.description?.takeIf { it.isNotBlank() } ?: "Açıklama yok") +
                                            (repo.updatedAt?.let { " · ${timeAgo(it)}" } ?: ""),
                                        maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    )
                                },
                                trailingContent = { Icon(if (expanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore, null) },
                                modifier = Modifier.combinedClickable(onClick = {
                                    if (expanded) expandedId = null else {
                                        expandedId = repo.id
                                        if (!selected) scope.launch { repoP.selectRepository(token, repo) }
                                    }
                                }),
                            )
                            if (expanded && selected) {
                                Column(Modifier.padding(start = 16.dp, end = 8.dp, bottom = 8.dp)) {
                                    if (repoP.branches.isEmpty()) {
                                        LinearProgressIndicator(Modifier.fillMaxWidth().padding(vertical = 8.dp))
                                    }
                                    for (b in repoP.branches) {
                                        val isSel = repoP.selectedBranch == b.name
                                        Row(
                                            Modifier.fillMaxWidth().combinedClickable(
                                                onClick = {
                                                    scope.launch { repoP.selectBranch(token, b.name); g.nav.pop() }
                                                },
                                                onLongClick = {
                                                    if (b.name == repo.defaultBranch) {
                                                        Snacks.show("Varsayılan dal silinemez.")
                                                    } else scope.launch {
                                                        val ok = Dialogs.typedConfirm("Dal silinsin mi?", "\"${b.name}\" dalı GitHub'dan silinecek.", b.name)
                                                        if (!ok) return@launch
                                                        try {
                                                            repoP.deleteBranch(token, b.name)
                                                            Snacks.show("Dal silindi.")
                                                        } catch (e: Exception) { Snacks.show(e.message ?: "Dal silinemedi.") }
                                                    }
                                                },
                                            ).padding(vertical = 10.dp, horizontal = 8.dp),
                                            verticalAlignment = Alignment.CenterVertically,
                                        ) {
                                            Icon(Icons.Outlined.AccountTree, null, Modifier.size(18.dp), tint = if (isSel) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant)
                                            Spacer(Modifier.width(10.dp))
                                            Text(b.name, Modifier.weight(1f), style = AppTheme.mono.copy(fontSize = 13.sp), fontWeight = if (isSel) FontWeight.Bold else FontWeight.Normal)
                                            if (b.name == repo.defaultBranch) Text("varsayılan", fontSize = 10.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                            if (isSel) Icon(Icons.Filled.Check, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                                        }
                                    }
                                    TextButton(onClick = {
                                        scope.launch {
                                            val name = Dialogs.prompt(
                                                "Yeni Dal", "Dal adı", mono = true,
                                                message = "\"${repoP.selectedBranch}\" dalının ucundan oluşturulur.",
                                            )?.trim().orEmpty()
                                            if (name.isEmpty()) return@launch
                                            if (!Regex("^[A-Za-z0-9._/-]{1,100}$").matches(name) || name.startsWith("/") || name.contains("..")) {
                                                Snacks.show("Geçersiz dal adı."); return@launch
                                            }
                                            if (repoP.createNewBranch(token, name)) g.nav.pop() else Snacks.show(repoP.errorMessage ?: "Dal oluşturulamadı.")
                                        }
                                    }) { Icon(Icons.Filled.Add, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Yeni dal oluştur") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    if (newRepoDialog) {
        var name by remember { mutableStateOf("") }
        var priv by remember { mutableStateOf(true) }
        AlertDialog(
            onDismissRequest = { newRepoDialog = false },
            title = { Text("Yeni Depo Oluştur") },
            text = {
                Column {
                    GpTextField(name, { name = it }, Modifier.fillMaxWidth(), label = "Depo adı", singleLine = true, mono = true)
                    Spacer(Modifier.height(12.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Özel depo", Modifier.weight(1f))
                        Switch(priv, { priv = it })
                    }
                }
            },
            dismissButton = { TextButton(onClick = { newRepoDialog = false }) { Text("Vazgeç") } },
            confirmButton = {
                Button(onClick = {
                    val n = name.trim()
                    if (!Regex("^[A-Za-z0-9_.-]{1,100}$").matches(n)) { Snacks.show("Geçersiz depo adı."); return@Button }
                    newRepoDialog = false
                    scope.launch {
                        val r = repoP.createNewRepo(token, n, priv)
                        if (r != null) { Snacks.show("Depo oluşturuldu: ${r.fullName}"); g.nav.pop() } else Snacks.show(repoP.errorMessage ?: "Depo oluşturulamadı.")
                    }
                }) { Text("Oluştur") }
            },
        )
    }
}
