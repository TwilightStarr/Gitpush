package com.example.gitpush.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.model.AppSettings
import com.example.gitpush.model.RepoListSort
import com.example.gitpush.model.RepoSortMode
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.state.ThemeMode
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.components.SectionCard
import com.example.gitpush.util.formatBytes
import com.example.gitpush.util.formatHhmm
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen() {
    val g = Graph
    val s = g.settings.settings
    val scope = rememberCoroutineScope()
    var commitText by remember { mutableStateOf(s.defaultCommitMessage) }

    fun lockLabel(sec: Int) = when (sec) { 0 -> "Her seferinde (dosya seçici sonrası da)"; 30 -> "30 saniye"; 60 -> "1 dakika"; 300 -> "5 dakika"; else -> "$sec sn" }
    fun logoutLabel(d: Int) = if (d == 0) "Kapalı" else "$d gün"

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {

        SectionCard("Hesap") {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text("@${g.auth.username ?: ""}", fontWeight = FontWeight.Bold)
                Text(
                    "Commit yazarı: " + (g.auth.authorName?.takeIf { it.isNotBlank() } ?: "GitHub hesabınız"),
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Row {
                    TextButton(onClick = {
                        scope.launch {
                            val name = Dialogs.prompt("Yazar adı", "Ad Soyad", initial = g.auth.authorName ?: "") ?: return@launch
                            val email = Dialogs.prompt("Yazar e-postası", "E-posta", initial = g.auth.authorEmail ?: "") ?: return@launch
                            g.auth.updateAuthorInfo(name, email)
                        }
                    }) { Text("Yazar bilgisi") }
                    TextButton(onClick = {
                        scope.launch {
                            val t = g.auth.token ?: return@launch
                            try {
                                val r = g.github.getRateLimit(t)
                                val reset = r.resetAt?.let { " (sıfırlanma ${formatHhmm(it)})" } ?: ""
                                Dialogs.info("GitHub API Limiti", "Kullanılan: ${r.used} / ${r.limit}\nKalan: ${r.remaining}$reset")
                            } catch (e: GitHubApiException) { Snacks.show(e.message) }
                        }
                    }) { Text("API limiti") }
                }
                TextButton(onClick = {
                    scope.launch {
                        val ok = Dialogs.confirm(
                            "Çıkış yapılsın mı?",
                            "Token, yazar bilgileri, son depo ve gönderim geçmişi bu cihazdan silinecek.",
                            "Çıkış Yap", destructive = true,
                        )
                        if (ok) {
                            g.repo.reset()
                            g.upload.resetAll()
                            g.upload.loadHistory()
                            g.auth.logout()
                        }
                    }
                }) { Text("Çıkış Yap", color = MaterialTheme.colorScheme.error) }
            }
        }

        SectionCard("Görünüm") {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                val modes = listOf(ThemeMode.System to "Sistem", ThemeMode.Light to "Açık", ThemeMode.Dark to "Koyu")
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    modes.forEachIndexed { i, (m, label) ->
                        SegmentedButton(
                            selected = g.theme.mode == m, onClick = { g.theme.setThemeMode(m) },
                            shape = SegmentedButtonDefaults.itemShape(i, modes.size),
                        ) { Text(label) }
                    }
                }
                Text("Vurgu rengi", fontSize = 13.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    AppSettings.accentPalette.forEachIndexed { i, c ->
                        Box(
                            Modifier.size(36.dp).clip(CircleShape).background(Color(c))
                                .border(if (i == s.accentIndex) 3.dp else 0.dp, MaterialTheme.colorScheme.onSurface, CircleShape)
                                .clickable { g.settings.update { it.copy(accentIndex = i) } },
                            contentAlignment = Alignment.Center,
                        ) { if (i == s.accentIndex) Icon(Icons.Filled.Check, AppSettings.accentNames[i], tint = Color.White) }
                    }
                }
                SwitchRow("AMOLED koyu tema (saf siyah)", s.amoledDark) { v -> g.settings.update { it.copy(amoledDark = v) } }
                SwitchRow("Dokunsal geri bildirim", s.haptics) { v -> g.settings.update { it.copy(haptics = v) } }
            }
        }

        SectionCard("Gönderim") {
            GpTextField(
                commitText, { commitText = it; g.settings.update { st -> st.copy(defaultCommitMessage = it.trim()) } },
                Modifier.fillMaxWidth(), label = "Varsayılan commit mesajı", singleLine = true,
                supportingText = "Boşsa her ekran kendi varsayılanını kullanır.",
            )
            TextButton(onClick = {
                scope.launch {
                    val ok = Dialogs.confirm("Kısayollar sıfırlansın mı?", "Eklediğiniz klasör kısayolları silinip varsayılanlar geri yüklenecek.", "Sıfırla")
                    if (ok) { g.storage.resetShortcuts(); Snacks.show("Kısayollar sıfırlandı.") }
                }
            }) { Text("Kısayolları sıfırla") }
        }

        SectionCard("Depo") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SwitchRow("Son kullanılan depoyu hatırla", s.rememberLastRepo) { v ->
                    g.settings.update { it.copy(rememberLastRepo = v) }
                    if (!v) scope.launch { g.storage.clearLastRepoAndBranch() }
                }
                SwitchRow("Gizli dosyaları göster (.ile başlayan)", s.showHiddenFiles) { v -> g.settings.update { it.copy(showHiddenFiles = v) } }
                OptionRow("Dosya sıralaması", s.repoSort.label) {
                    scope.launch {
                        Dialogs.pick("Dosya sıralaması", RepoSortMode.values().map { it to it.label }, s.repoSort)?.let { v -> g.settings.update { it.copy(repoSort = v) } }
                    }
                }
                OptionRow("Depo listesi sıralaması", s.repoListSort.label) {
                    scope.launch {
                        Dialogs.pick("Depo listesi sıralaması", RepoListSort.values().map { it to it.label }, s.repoListSort)?.let { v -> g.settings.update { it.copy(repoListSort = v) } }
                    }
                }
            }
        }

        SectionCard("Önizleme") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OptionRow("Önizleme boyut sınırı", AppSettings.formatKb(s.previewMaxKb)) {
                    scope.launch {
                        Dialogs.pick("Önizleme boyut sınırı", AppSettings.previewMaxKbOptions.map { it to AppSettings.formatKb(it) }, s.previewMaxKb)
                            ?.let { v -> g.settings.update { it.copy(previewMaxKb = v) } }
                    }
                }
                SwitchRow("Satırları kaydır", s.previewWrapLines) { v -> g.settings.update { it.copy(previewWrapLines = v) } }
                Text("Yazı boyutu: ${s.previewFontSize.toInt()}", fontSize = 13.sp)
                Slider(
                    value = s.previewFontSize.toFloat(), onValueChange = { v -> g.settings.update { it.copy(previewFontSize = v.toInt().toDouble()) } },
                    valueRange = 10f..18f, steps = 7,
                )
            }
        }

        SectionCard("Geçmiş") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OptionRow("Saklanan kayıt sayısı", "${s.historyLimit}") {
                    scope.launch {
                        Dialogs.pick("Saklanan kayıt sayısı", AppSettings.historyLimitOptions.map { it to "$it" }, s.historyLimit)
                            ?.let { v -> g.settings.update { it.copy(historyLimit = v) } }
                    }
                }
                TextButton(onClick = {
                    scope.launch {
                        if (Dialogs.confirm("Geçmiş temizlensin mi?", "Tüm yerel gönderim kayıtları silinecek.", "Temizle", destructive = true)) g.upload.clearHistory()
                    }
                }) { Text("Geçmişi temizle") }
            }
        }

        SectionCard("Güvenlik") {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SwitchRow("Uygulama kilidi (PIN)", s.appLockEnabled) { v ->
                    scope.launch {
                        if (v) {
                            if (!g.lock.service.hasPin() && !Dialogs.pin("PIN oluştur", create = true)) return@launch
                            g.settings.update { it.copy(appLockEnabled = true) }.join()
                            g.lock.syncSettings(g.settings.settings)
                        } else {
                            if (!Dialogs.pin("PIN'i doğrula", create = false)) return@launch
                            g.lock.wipe()
                            g.settings.update { it.copy(appLockEnabled = false) }.join()
                        }
                    }
                }
                if (s.appLockEnabled) {
                    OptionRow("Kilitlenme süresi", lockLabel(s.lockTimeoutSeconds)) {
                        scope.launch {
                            Dialogs.pick("Arka plandan dönünce kilitle", AppSettings.lockTimeoutOptions.map { it to lockLabel(it) }, s.lockTimeoutSeconds)?.let { v ->
                                g.settings.update { it.copy(lockTimeoutSeconds = v) }.join()
                                g.lock.syncSettings(g.settings.settings)
                            }
                        }
                    }
                    TextButton(onClick = {
                        scope.launch {
                            if (!Dialogs.pin("Mevcut PIN", create = false)) return@launch
                            if (Dialogs.pin("Yeni PIN", create = true)) Snacks.show("PIN değiştirildi.")
                        }
                    }) { Text("PIN'i değiştir") }
                    TextButton(onClick = { g.lock.lockNow() }) { Text("Şimdi kilitle") }
                }
                OptionRow("Otomatik oturum kapatma", logoutLabel(s.autoLogoutDays)) {
                    scope.launch {
                        Dialogs.pick("Bu kadar gün açılmazsa çıkış yap", AppSettings.autoLogoutOptions.map { it to logoutLabel(it) }, s.autoLogoutDays)
                            ?.let { v -> g.settings.update { it.copy(autoLogoutDays = v) } }
                    }
                }
            }
        }

        SectionCard("Diğer") {
            Column {
                TextButton(onClick = {
                    scope.launch {
                        if (Dialogs.confirm("Ayarlar sıfırlansın mı?", "Hesap ve kilit ayarları korunur; diğer tüm ayarlar varsayılana döner.", "Sıfırla")) {
                            g.settings.resetToDefaults().join()
                            commitText = g.settings.settings.defaultCommitMessage
                        }
                    }
                }) { Text("Ayarları varsayılana döndür") }
                TextButton(onClick = {
                    scope.launch {
                        Dialogs.info(
                            "Açık kaynak lisansları",
                            "Bu uygulama şu açık kaynak bileşenleri kullanır:\n\n" +
                                "• Jetpack Compose / AndroidX — Apache 2.0\n" +
                                "• Kotlin & kotlinx (coroutines, serialization) — Apache 2.0\n" +
                                "• OkHttp / Okio — Apache 2.0\n" +
                                "• AndroidX Security Crypto — Apache 2.0\n" +
                                "• Material Icons — Apache 2.0",
                        )
                    }
                }) { Text("Lisanslar") }
                Text("Gitpush 1.2.1", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(start = 12.dp, top = 4.dp))
            }
        }
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun SwitchRow(label: String, value: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), fontSize = 14.sp)
        Spacer(Modifier.width(8.dp))
        Switch(checked = value, onCheckedChange = onChange)
    }
}

@Composable
private fun OptionRow(label: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), fontSize = 14.sp)
        Text(value, fontSize = 13.sp, color = MaterialTheme.colorScheme.primary)
    }
}
