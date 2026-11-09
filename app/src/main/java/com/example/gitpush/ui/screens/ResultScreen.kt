package com.example.gitpush.ui.screens

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
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.model.ActionRun
import com.example.gitpush.service.evaluateRuns
import com.example.gitpush.ui.Route
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.ActionRunTile
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.components.SectionCard
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.copyToClipboard
import com.example.gitpush.util.openExternalUrl
import com.example.gitpush.util.shortSha
import kotlinx.coroutines.delay

@Composable
fun ResultScreen(route: Route.Result) {
    val g = Graph
    val ctx = LocalContext.current
    val r = route.result
    var runs by remember { mutableStateOf<List<ActionRun>>(emptyList()) }
    var tracking by remember { mutableStateOf(!r.noChanges && r.commitSha != null) }

    ScreenBack { g.nav.popToRoot() }

    // Bu commit'e ait Actions çalışmalarını izle (en çok ~3 dk)
    LaunchedEffect(r.commitSha) {
        val sha = r.commitSha ?: return@LaunchedEffect
        val token = g.auth.token ?: return@LaunchedEffect
        var tries = 0
        while (tries < 36) {
            try {
                val all = g.github.getActionRuns(token, route.owner, route.repo)
                val ev = evaluateRuns(all, sha)
                runs = ev.matching
                if (ev.allCompleted) break
            } catch (_: Exception) { }
            tries++
            delay(5000)
        }
        tracking = false
    }

    Scaffold { inner ->
        Column(
            Modifier.fillMaxSize().padding(inner).verticalScroll(rememberScrollState()).padding(20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(24.dp))
            Icon(Icons.Outlined.CheckCircle, null, Modifier.size(72.dp), tint = AppTheme.statusNew)
            Spacer(Modifier.height(12.dp))
            Text(if (r.noChanges) "Değişiklik yok" else "Gönderim Tamamlandı", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(4.dp))
            Text("${route.owner}/${route.repo} · ${route.branch}", style = AppTheme.mono.copy(fontSize = 13.sp), color = MaterialTheme.colorScheme.onSurfaceVariant)
            Spacer(Modifier.height(20.dp))

            SectionCard("Özet") {
                Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    if (r.noChanges) Text("Repo ile aynı olduğu için commit atılmadı.")
                    else {
                        Text("${r.added} yeni · ${r.updated} güncellendi · ${r.deleted} silindi")
                        if (r.skipped > 0) Text("${r.skipped} dosya atlandı (değişmedi/zaten yok)", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    r.commitSha?.let { Text("Commit: ${shortSha(it)}", style = AppTheme.mono.copy(fontSize = 13.sp), color = MaterialTheme.colorScheme.primary) }
                }
            }
            for (w in r.warnings) {
                Spacer(Modifier.height(8.dp))
                Text(w, fontSize = 12.sp, color = MaterialTheme.colorScheme.error)
            }
            if (r.commitSha != null) {
                Spacer(Modifier.height(12.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedButton(onClick = { if (!openExternalUrl(ctx, route.commitUrl)) Snacks.show("Bağlantı açılamadı.") }) {
                        Icon(Icons.Outlined.OpenInBrowser, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Commit'i aç")
                    }
                    OutlinedButton(onClick = { copyToClipboard(ctx, r.commitSha ?: ""); Snacks.show("SHA kopyalandı") }) {
                        Icon(Icons.Filled.ContentCopy, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("SHA")
                    }
                }
            }
            if (runs.isNotEmpty() || tracking) {
                Spacer(Modifier.height(16.dp))
                SectionCard("GitHub Actions") {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        if (runs.isEmpty()) Text("Bu commit için workflow çalışması aranıyor…", fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        for (run in runs) ActionRunTile(run) { if (!openExternalUrl(ctx, run.htmlUrl)) Snacks.show("Bağlantı açılamadı.") }
                    }
                }
            }
            Spacer(Modifier.height(24.dp))
            Button(onClick = { g.nav.popToRoot() }, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("Bitti") }
        }
    }
}
