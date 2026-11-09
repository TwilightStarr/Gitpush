package com.example.gitpush.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.Source
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExtendedFloatingActionButton
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
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
import com.example.gitpush.model.ActionRun
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Route
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.ActionRunTile
import com.example.gitpush.ui.components.EmptyState
import com.example.gitpush.ui.components.ErrorView
import com.example.gitpush.util.openExternalUrl
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ActionsScreen(isActive: Boolean) {
    val g = Graph
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    val repo = g.repo.selectedRepo
    val branch = g.repo.selectedBranch
    var runs by remember { mutableStateOf<List<ActionRun>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    suspend fun load() {
        val r = g.repo.selectedRepo ?: return
        val t = g.auth.token ?: return
        loading = true
        try {
            runs = g.github.getActionRuns(t, r.owner, r.name)
            error = null
        } catch (e: GitHubApiException) {
            error = e.message
        } finally { loading = false }
    }

    // Sekme açıkken ve repo değişince yükle; çalışan iş varsa 10 sn'de bir yenile
    LaunchedEffect(repo?.id, isActive) {
        if (!isActive || repo == null) return@LaunchedEffect
        load()
        while (true) {
            delay(10_000)
            if (runs.any { it.isRunning }) load()
        }
    }

    if (repo == null) {
        EmptyState(Icons.Outlined.Source, "Actions'ı görmek için önce bir depo seçin.", "Depo Seç") { g.nav.push(Route.RepoPicker) }
        return
    }

    Box(Modifier.fillMaxSize()) {
        PullToRefreshBox(isRefreshing = loading, onRefresh = { scope.launch { load() } }, modifier = Modifier.fillMaxSize()) {
            when {
                error != null && runs.isEmpty() -> ErrorView(error!!) { scope.launch { load() } }
                runs.isEmpty() && !loading -> EmptyState(Icons.Outlined.Bolt, "Bu depoda henüz bir workflow çalışması yok.")
                else -> LazyColumn(
                    Modifier.fillMaxSize(), contentPadding = PaddingValues(16.dp, 16.dp, 16.dp, 96.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(runs, key = { it.id }) { run ->
                        ActionRunTile(run) { if (!openExternalUrl(ctx, run.htmlUrl)) Snacks.show("Bağlantı açılamadı.") }
                    }
                }
            }
        }
        ExtendedFloatingActionButton(
            onClick = {
                scope.launch {
                    val name = Dialogs.prompt(
                        "Workflow Tetikle", "Workflow dosya adı", initial = "build.yml", mono = true,
                        message = "Dal: $branch — workflow'un `workflow_dispatch` ile tetiklenebilir olması gerekir.",
                        confirmLabel = "Tetikle",
                    )?.trim().orEmpty()
                    if (name.isEmpty()) return@launch
                    try {
                        g.github.triggerWorkflow(g.auth.token ?: "", repo.owner, repo.name, name, branch ?: repo.defaultBranch)
                        Snacks.show("Workflow tetiklendi.")
                        delay(2000); load()
                    } catch (e: GitHubApiException) { Snacks.show(e.message) }
                }
            },
            icon = { Icon(Icons.Filled.PlayArrow, null) }, text = { Text("Tetikle") },
            modifier = Modifier.align(Alignment.BottomEnd).padding(16.dp),
        )
    }
}
