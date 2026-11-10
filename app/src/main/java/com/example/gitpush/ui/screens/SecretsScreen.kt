package com.example.gitpush.ui.screens

import android.util.Base64
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.outlined.AccountTree
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.model.ActionSecret
import com.example.gitpush.model.GitHubRepo
import com.example.gitpush.model.SecretRules
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.ui.components.SectionCard
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.readPickedFile
import com.example.gitpush.util.timeAgo
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Release imzası için workflow'un beklediği secret'lar (README: "Sabit imza"). */
private val SIGNING_SECRETS = listOf("KEYSTORE_BASE64", "KEYSTORE_PASSWORD", "KEY_ALIAS", "KEY_PASSWORD")

private class EditTarget(val name: String, val lockName: Boolean)

private val repoPartRe = Regex("^[A-Za-z0-9_.-]{1,100}$")

/** "sahip/depo" metnini ayrıştırır; geçersizse null. */
private fun parseRepo(text: String): Pair<String, String>? {
    val parts = text.trim().split('/')
    if (parts.size != 2) return null
    val owner = parts[0]
    val repo = parts[1]
    for (p in listOf(owner, repo)) {
        if (!repoPartRe.matches(p) || p == "." || p == "..") return null
    }
    return owner to repo
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SecretsScreen() {
    val g = Graph
    val scope = rememberCoroutineScope()
    val token = g.auth.token ?: ""

    // Hedef depo, uygulamada seçili depodan bağımsızdır: listeden seçilebilir ya da elle yazılabilir.
    var target by remember { mutableStateOf(g.repo.selectedRepo?.fullName ?: "") }
    val parsed = remember(target) { parseRepo(target) }
    var secrets by remember { mutableStateOf<List<ActionSecret>>(emptyList()) }
    var loadedFor by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var chooser by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf<EditTarget?>(null) }

    ScreenBack { g.nav.pop() }

    suspend fun load() {
        val p = parsed ?: return
        loading = true
        try {
            val list = g.github.listActionSecrets(token, p.first, p.second)
            secrets = list
            loadedFor = "${p.first}/${p.second}"
            error = null
        } catch (e: GitHubApiException) {
            secrets = emptyList()
            loadedFor = null
            error = e.message
        } finally {
            loading = false
        }
    }

    LaunchedEffect(parsed) {
        secrets = emptyList()
        loadedFor = null
        error = null
        if (parsed == null) return@LaunchedEffect
        delay(500) // yazarken her tuşta istek atılmasın
        load()
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Actions Secret'ları") },
                navigationIcon = { IconButton(onClick = { g.nav.pop() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
                actions = {
                    IconButton(onClick = { scope.launch { load() } }, enabled = parsed != null && !loading) {
                        Icon(Icons.Filled.Refresh, "Yenile")
                    }
                },
            )
        },
        floatingActionButton = {
            if (parsed != null) {
                ExtendedFloatingActionButton(
                    onClick = { editing = EditTarget("", false) },
                    icon = { Icon(Icons.Filled.Add, null) },
                    text = { Text("Secret Ekle") },
                )
            }
        },
    ) { inner ->
        Column(Modifier.fillMaxSize().padding(inner)) {
            if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
            GpTextField(
                target, { target = it },
                Modifier.fillMaxWidth().padding(16.dp, 8.dp, 16.dp, 4.dp),
                label = "Depo (sahip/ad)", placeholder = "ornek-kullanici/depo-adi",
                singleLine = true, mono = true, isError = target.isNotBlank() && parsed == null,
                supportingText = "Listeden seçin ya da herhangi bir depoyu elle yazın.",
                trailing = {
                    IconButton(onClick = { chooser = true }) { Icon(Icons.Outlined.AccountTree, "Depo seç") }
                },
            )
            error?.let {
                Text(it, color = MaterialTheme.colorScheme.error, modifier = Modifier.padding(16.dp, 4.dp))
            }
            if (parsed == null) {
                Text(
                    "Secret'ları görmek veya eklemek için bir depo seçin.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(16.dp),
                )
            } else {
                LazyColumn(
                    Modifier.fillMaxSize(),
                    contentPadding = PaddingValues(16.dp, 8.dp, 16.dp, 96.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (loadedFor != null && error == null) {
                        item(key = "signing") {
                            val existing = secrets.map { it.name.uppercase() }.toSet()
                            SectionCard("Release imza secret'ları") {
                                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                                    for (n in SIGNING_SECRETS) {
                                        val has = n in existing
                                        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                            Icon(
                                                if (has) Icons.Filled.Check else Icons.Filled.Close, null,
                                                Modifier.size(18.dp),
                                                tint = if (has) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
                                            )
                                            Spacer(Modifier.width(10.dp))
                                            Text(n, Modifier.weight(1f), style = AppTheme.mono.copy(fontSize = 13.sp))
                                            TextButton(onClick = { editing = EditTarget(n, has) }) { Text(if (has) "Güncelle" else "Ekle") }
                                        }
                                    }
                                    Text(
                                        "Eksik veya hatalıysa workflow imzayı atlar ve debug APK üretir.",
                                        style = MaterialTheme.typography.bodySmall,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    )
                                }
                            }
                        }
                    }
                    if (loadedFor != null && error == null && secrets.isEmpty()) {
                        item(key = "empty") {
                            Text(
                                "Bu depoda henüz secret yok.",
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                                modifier = Modifier.padding(8.dp),
                            )
                        }
                    }
                    items(secrets, key = { it.name }) { s ->
                        Card(
                            shape = RoundedCornerShape(16.dp),
                            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
                        ) {
                            ListItem(
                                leadingContent = { Icon(Icons.Filled.Lock, null, tint = MaterialTheme.colorScheme.primary) },
                                headlineContent = {
                                    Text(s.name, style = AppTheme.mono.copy(fontSize = 14.sp), fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                },
                                supportingContent = {
                                    Text(s.updatedAt?.let { "Güncellendi: ${timeAgo(it)}" } ?: "Değer gizli")
                                },
                                trailingContent = {
                                    Row {
                                        IconButton(onClick = { editing = EditTarget(s.name, true) }) { Icon(Icons.Filled.Edit, "Güncelle") }
                                        IconButton(onClick = {
                                            scope.launch {
                                                val p = parsed ?: return@launch
                                                val ok = Dialogs.confirm(
                                                    "Secret silinsin mi?",
                                                    "\"${s.name}\", ${p.first}/${p.second} deposundan silinecek. Bu işlem geri alınamaz.",
                                                    confirmLabel = "Sil", destructive = true,
                                                )
                                                if (!ok) return@launch
                                                try {
                                                    g.github.deleteActionSecret(token, p.first, p.second, s.name)
                                                    Snacks.show("Secret silindi.")
                                                    load()
                                                } catch (e: GitHubApiException) {
                                                    Snacks.show(e.message)
                                                }
                                            }
                                        }) { Icon(Icons.Filled.Delete, "Sil", tint = MaterialTheme.colorScheme.error) }
                                    }
                                },
                            )
                        }
                    }
                }
            }
        }
    }

    if (chooser) {
        RepoChooserDialog(
            repos = g.repo.repositories,
            onPick = { target = it; chooser = false },
            onDismiss = { chooser = false },
        )
    }

    val et = editing
    val p = parsed
    if (et != null && p != null) {
        SecretEditorDialog(
            repoLabel = "${p.first}/${p.second}",
            initial = et,
            onDismiss = { editing = null },
        ) { name, secretValue ->
            try {
                val created = g.github.putActionSecret(token, p.first, p.second, name, secretValue)
                Snacks.show(if (created) "Secret eklendi." else "Secret güncellendi.")
                editing = null
                scope.launch { load() }
                null
            } catch (e: GitHubApiException) {
                e.message
            } catch (e: IllegalArgumentException) {
                "Şifreleme hatası: ${e.message}"
            }
        }
    }
}

@Composable
private fun RepoChooserDialog(repos: List<GitHubRepo>, onPick: (String) -> Unit, onDismiss: () -> Unit) {
    var q by remember { mutableStateOf("") }
    val shown = remember(q, repos) {
        val s = q.trim().lowercase()
        repos.filter { s.isEmpty() || it.fullName.lowercase().contains(s) }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Depo Seç") },
        text = {
            Column {
                GpTextField(
                    q, { q = it }, Modifier.fillMaxWidth(),
                    placeholder = "Depo ara...", singleLine = true, leadingIcon = Icons.Filled.Search,
                )
                Spacer(Modifier.height(8.dp))
                if (repos.isEmpty()) {
                    Text("Depo listesi boş. sahip/depo biçiminde elle yazabilirsiniz.")
                } else {
                    LazyColumn(Modifier.heightIn(max = 360.dp)) {
                        items(shown, key = { it.id }) { r ->
                            ListItem(
                                leadingContent = { Icon(if (r.isPrivate) Icons.Filled.Lock else Icons.Outlined.Public, null) },
                                headlineContent = { Text(r.fullName, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                                modifier = Modifier.clickable { onPick(r.fullName) },
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {},
        dismissButton = { TextButton(onClick = onDismiss) { Text("Kapat") } },
    )
}

/** [onSave] hata metni döndürürse gösterilir; null dönerse çağıran diyaloğu kapatır. */
@Composable
private fun SecretEditorDialog(
    repoLabel: String,
    initial: EditTarget,
    onDismiss: () -> Unit,
    onSave: suspend (name: String, value: String) -> String?,
) {
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var name by remember { mutableStateOf(initial.name) }
    var secretValue by remember { mutableStateOf("") }
    var reveal by remember { mutableStateOf(false) }
    var trim by remember { mutableStateOf(true) }
    var saving by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }

    // Keystore (.jks/.keystore) dosyasını seçip KEYSTORE_BASE64 değerini otomatik üretir.
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val picked = readPickedFile(ctx, uri, maxBytes = 30_000L)
            if (picked == null) {
                err = "Dosya okunamadı veya çok büyük (en çok ~30 KB)."
                return@launch
            }
            secretValue = Base64.encodeToString(picked.bytes, Base64.NO_WRAP)
            if (name.isBlank()) name = "KEYSTORE_BASE64"
            err = null
        }
    }

    AlertDialog(
        onDismissRequest = { if (!saving) onDismiss() },
        title = { Text(if (initial.lockName) "Secret'ı Güncelle" else "Secret Ekle") },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(repoLabel, style = AppTheme.mono.copy(fontSize = 12.sp), color = MaterialTheme.colorScheme.onSurfaceVariant)
                GpTextField(
                    name, { name = it.filter { c -> !c.isWhitespace() } }, Modifier.fillMaxWidth(),
                    label = "Ad", placeholder = "KEY_PASSWORD", singleLine = true, mono = true,
                    enabled = !initial.lockName && !saving,
                    supportingText = "GitHub adı büyük harfe çevirir.",
                )
                GpTextField(
                    secretValue, { secretValue = it }, Modifier.fillMaxWidth(),
                    label = "Değer", mono = true, minLines = 3, maxLines = 8, enabled = !saving,
                    visualTransformation = if (reveal) VisualTransformation.None else PasswordVisualTransformation(),
                    trailing = {
                        IconButton(onClick = { reveal = !reveal }) {
                            Icon(if (reveal) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, if (reveal) "Gizle" else "Göster")
                        }
                    },
                )
                Row(
                    Modifier.fillMaxWidth().clickable(enabled = !saving) { trim = !trim },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Switch(checked = trim, onCheckedChange = { trim = it }, enabled = !saving)
                    Spacer(Modifier.width(10.dp))
                    Text("Baştaki/sondaki boşluk ve satır sonlarını temizle", style = MaterialTheme.typography.bodySmall)
                }
                TextButton(onClick = { picker.launch(arrayOf("*/*")) }, enabled = !saving) {
                    Icon(Icons.Filled.VpnKey, null, Modifier.size(16.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("Keystore dosyasından oku (base64)")
                }
                err?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
            }
        },
        confirmButton = {
            Button(
                enabled = !saving,
                onClick = {
                    val n = name.trim()
                    val v = if (trim) secretValue.trim() else secretValue
                    val problem = SecretRules.validateName(n) ?: SecretRules.validateValue(v)
                    if (problem != null) {
                        err = problem
                    } else {
                        saving = true
                        err = null
                        scope.launch {
                            val result = onSave(n, v)
                            saving = false
                            if (result != null) err = result
                        }
                    }
                },
            ) { Text(if (saving) "Şifreleniyor…" else "Kaydet") }
        },
        dismissButton = { TextButton(onClick = onDismiss, enabled = !saving) { Text("Vazgeç") } },
    )
}
