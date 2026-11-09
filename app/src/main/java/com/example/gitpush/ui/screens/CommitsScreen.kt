package com.example.gitpush.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.Timeline
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.model.PathCommitInfo
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.EmptyState
import com.example.gitpush.ui.components.ErrorView
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.formatDateTime
import com.example.gitpush.util.openExternalUrl
import com.example.gitpush.util.shortSha
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommitsScreen(path: String?) {
    val g = Graph
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var commits by remember { mutableStateOf<List<PathCommitInfo>>(emptyList()) }
    var page by remember { mutableStateOf(1) }
    var loading by remember { mutableStateOf(true) }
    var hasMore by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    val perPage = 30

    suspend fun load(reset: Boolean) {
        loading = true
        error = null
        try {
            val p = if (reset) 1 else page + 1
            val list = g.repo.loadCommits(g.auth.token ?: "", path, p)
            commits = if (reset) list else commits + list
            page = p
            hasMore = list.size >= perPage
        } catch (e: GitHubApiException) { error = e.message } finally { loading = false }
    }

    LaunchedEffect(path) { load(true) }
    ScreenBack { g.nav.pop() }

    Scaffold(topBar = {
        TopAppBar(
            title = { Text(path ?: "Commit Geçmişi", maxLines = 1, overflow = TextOverflow.Ellipsis, style = if (path != null) AppTheme.mono.copy(fontSize = 15.sp) else androidx.compose.material3.LocalTextStyle.current) },
            navigationIcon = { IconButton(onClick = { g.nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
        )
    }) { inner ->
        Box(Modifier.fillMaxSize().padding(inner)) {
            when {
                error != null && commits.isEmpty() -> ErrorView(error!!) { scope.launch { load(true) } }
                loading && commits.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                commits.isEmpty() -> EmptyState(Icons.Outlined.Timeline, "Commit bulunamadı.")
                else -> LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    itemsIndexed(commits, key = { i, c -> "$i-${c.sha}" }) { _, c ->
                        Card(onClick = { c.htmlUrl?.let { if (!openExternalUrl(ctx, it)) Snacks.show("Bağlantı açılamadı.") } }) {
                            ListItem(
                                headlineContent = { Text(c.title, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                                supportingContent = {
                                    Text(
                                        listOfNotNull(c.authorName, c.date?.let { formatDateTime(it) }, shortSha(c.sha)).joinToString(" · "),
                                        fontSize = 12.sp,
                                    )
                                },
                                trailingContent = { Icon(Icons.Outlined.OpenInBrowser, null) },
                            )
                        }
                    }
                    item {
                        if (hasMore) {
                            Box(Modifier.fillMaxWidth().padding(8.dp), contentAlignment = Alignment.Center) {
                                if (loading) CircularProgressIndicator() else OutlinedButton(onClick = { scope.launch { load(false) } }) { Text("Daha fazla yükle") }
                            }
                        }
                    }
                }
            }
        }
    }
}
