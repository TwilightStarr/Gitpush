package com.example.gitpush.ui.screens

import androidx.compose.animation.Crossfade
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.automirrored.filled.WrapText
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.outlined.DeleteOutline
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.FormatSize
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Key
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.Palette
import androidx.compose.material.icons.outlined.Dialpad
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material.icons.outlined.Security
import androidx.compose.material.icons.outlined.Sort
import androidx.compose.material.icons.outlined.Source
import androidx.compose.material.icons.outlined.Storage
import androidx.compose.material.icons.outlined.Timer
import androidx.compose.material.icons.outlined.Upload
import androidx.compose.material.icons.outlined.Vibration
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
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
import com.example.gitpush.ui.components.ScreenBack
import com.example.gitpush.util.formatHhmm
import kotlinx.coroutines.launch

/** Ayarlar ana listesindeki kategoriler. Her biri kendi alt sayfasını açar. */
private enum class SettingsPage(val title: String, val icon: ImageVector) {
    Appearance("Görünüm", Icons.Outlined.Palette),
    Sending("Gönderim", Icons.Outlined.Upload),
    Files("Depo ve dosyalar", Icons.Outlined.FolderOpen),
    Security("Güvenlik", Icons.Outlined.Security),
    Data("Geçmiş ve veri", Icons.Outlined.Storage),
    About("Hakkında", Icons.Outlined.Info),
}

private const val APP_VERSION = "1.2.1"

@Composable
fun SettingsScreen(isActive: Boolean = true) {
    var pageKey by rememberSaveable { mutableStateOf<String?>(null) }
    val page = SettingsPage.values().firstOrNull { it.name == pageKey }

    // Alt sayfadayken geri tuşu ana ayar listesine döner (yalnızca bu sekme açıkken).
    ScreenBack(enabled = isActive && page != null) { pageKey = null }

    Crossfade(targetState = page, label = "settings-page") { p ->
        if (p == null) SettingsHome(onOpen = { pageKey = it.name })
        else SettingsDetail(p, onBack = { pageKey = null })
    }
}

// ───────────────────────── Ana liste ─────────────────────────

@Composable
private fun SettingsHome(onOpen: (SettingsPage) -> Unit) {
    val g = Graph
    val s = g.settings.settings
    val scope = rememberCoroutineScope()
    val cs = MaterialTheme.colorScheme

    fun themeLabel() = when (g.theme.mode) { ThemeMode.System -> "Sistem"; ThemeMode.Light -> "Açık"; ThemeMode.Dark -> "Koyu" }
    fun summary(p: SettingsPage): String = when (p) {
        SettingsPage.Appearance -> "${themeLabel()} · ${AppSettings.accentNames[s.accentIndex.coerceIn(0, AppSettings.accentNames.lastIndex)]}"
        SettingsPage.Sending -> s.defaultCommitMessage.ifBlank { "Varsayılan commit mesajı yok" }
        SettingsPage.Files -> "Sıralama: ${s.repoSort.label}"
        SettingsPage.Security -> if (s.appLockEnabled) "PIN kilidi açık" else "PIN kilidi kapalı"
        SettingsPage.Data -> "${s.historyLimit} kayıt saklanır"
        SettingsPage.About -> "Gitpush $APP_VERSION"
    }

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Hesap kartı
        Card(
            Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp),
            colors = CardDefaults.cardColors(containerColor = cs.surfaceContainer),
        ) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    val initial = (g.auth.username ?: "?").take(1).uppercase()
                    Box(
                        Modifier.size(52.dp).clip(CircleShape).background(cs.primaryContainer),
                        contentAlignment = Alignment.Center,
                    ) { Text(initial, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = cs.onPrimaryContainer) }
                    Spacer(Modifier.width(14.dp))
                    Column(Modifier.weight(1f)) {
                        Text("@${g.auth.username ?: ""}", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            "Commit yazarı: " + (g.auth.authorName?.takeIf { it.isNotBlank() } ?: "GitHub hesabınız"),
                            style = MaterialTheme.typography.bodySmall, color = cs.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    FilledTonalButton(
                        onClick = {
                            scope.launch {
                                val name = Dialogs.prompt("Yazar adı", "Ad Soyad", initial = g.auth.authorName ?: "") ?: return@launch
                                val email = Dialogs.prompt("Yazar e-postası", "E-posta", initial = g.auth.authorEmail ?: "") ?: return@launch
                                g.auth.updateAuthorInfo(name, email)
                            }
                        },
                        Modifier.weight(1f),
                    ) { Text("Yazar bilgisi", maxLines = 1) }
                    OutlinedButton(
                        onClick = {
                            scope.launch {
                                val t = g.auth.token ?: return@launch
                                try {
                                    val r = g.github.getRateLimit(t)
                                    val reset = r.resetAt?.let { " (sıfırlanma ${formatHhmm(it)})" } ?: ""
                                    Dialogs.info("GitHub API Limiti", "Kullanılan: ${r.used} / ${r.limit}\nKalan: ${r.remaining}$reset")
                                } catch (e: GitHubApiException) { Snacks.show(e.message) }
                            }
                        },
                        Modifier.weight(1f),
                    ) { Text("API limiti", maxLines = 1) }
                }
            }
        }

        // Kategoriler
        Group {
            SettingsPage.values().forEachIndexed { i, p ->
                if (i > 0) Hairline()
                NavRow(p.icon, p.title, summary(p)) { onOpen(p) }
            }
        }

        // Oturum
        Group {
            ActionRow(Icons.Outlined.Lock, "Çıkış yap", "Token ve yerel veriler bu cihazdan silinir", danger = true) {
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
            }
        }
        Spacer(Modifier.height(16.dp))
    }
}

// ───────────────────────── Alt sayfalar ─────────────────────────

@Composable
private fun SettingsDetail(page: SettingsPage, onBack: () -> Unit) {
    Column(Modifier.fillMaxSize()) {
        Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") }
            Text(page.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, maxLines = 1)
        }
        Column(
            Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (page) {
                SettingsPage.Appearance -> AppearancePage()
                SettingsPage.Sending -> SendingPage()
                SettingsPage.Files -> FilesPage()
                SettingsPage.Security -> SecurityPage()
                SettingsPage.Data -> DataPage()
                SettingsPage.About -> AboutPage()
            }
            Spacer(Modifier.height(16.dp))
        }
    }
}

@Composable
private fun ColumnScope.AppearancePage() {
    val g = Graph
    val s = g.settings.settings
    val cs = MaterialTheme.colorScheme
    val effectiveDark = when (g.theme.mode) {
        ThemeMode.Light -> false
        ThemeMode.Dark -> true
        ThemeMode.System -> isSystemInDarkTheme()
    }

    Group("Tema") {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            val modes = listOf(ThemeMode.System to "Sistem", ThemeMode.Light to "Açık", ThemeMode.Dark to "Koyu")
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                modes.forEachIndexed { i, (m, label) ->
                    SegmentedButton(
                        selected = g.theme.mode == m, onClick = { g.theme.setThemeMode(m) },
                        shape = SegmentedButtonDefaults.itemShape(i, modes.size),
                    ) { Text(label, maxLines = 1) }
                }
            }
            Text("Vurgu rengi", style = MaterialTheme.typography.labelLarge, color = cs.onSurfaceVariant)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                AppSettings.accentPalette.forEachIndexed { i, c ->
                    val on = i == s.accentIndex
                    Box(
                        Modifier.size(40.dp).clip(CircleShape).background(Color(c))
                            .border(if (on) 3.dp else 0.dp, cs.onSurface, CircleShape)
                            .clickable { g.settings.update { it.copy(accentIndex = i) } },
                        contentAlignment = Alignment.Center,
                    ) { if (on) Icon(Icons.Filled.Check, AppSettings.accentNames[i], tint = Color.White) }
                }
            }
        }
        Hairline()
        SwitchRow(
            Icons.Outlined.DarkMode, "AMOLED koyu tema", if (effectiveDark) "Saf siyah arka plan" else "Yalnızca koyu temada etkin olur",
            s.amoledDark, enabled = effectiveDark,
        ) { v -> g.settings.update { it.copy(amoledDark = v) } }
    }
    Group("Etkileşim") {
        SwitchRow(Icons.Outlined.Vibration, "Dokunsal geri bildirim", "Önemli işlemlerde hafif titreşim", s.haptics) { v ->
            g.settings.update { it.copy(haptics = v) }
        }
    }
}

@Composable
private fun ColumnScope.SendingPage() {
    val g = Graph
    val s = g.settings.settings
    val scope = rememberCoroutineScope()
    var commitText by remember { mutableStateOf(s.defaultCommitMessage) }

    Group("Commit") {
        Column(Modifier.padding(16.dp)) {
            GpTextField(
                commitText, { commitText = it; g.settings.update { st -> st.copy(defaultCommitMessage = it.trim()) } },
                Modifier.fillMaxWidth(), label = "Varsayılan commit mesajı", singleLine = true,
                supportingText = "Boşsa her ekran kendi varsayılanını kullanır.",
            )
        }
    }
    Group("Klasör kısayolları") {
        ActionRow(Icons.Outlined.Bolt, "Kısayolları sıfırla", "Eklediğiniz kısayollar silinir, varsayılanlar geri gelir") {
            scope.launch {
                val ok = Dialogs.confirm("Kısayollar sıfırlansın mı?", "Eklediğiniz klasör kısayolları silinip varsayılanlar geri yüklenecek.", "Sıfırla")
                if (ok) { g.storage.resetShortcuts(); Snacks.show("Kısayollar sıfırlandı.") }
            }
        }
    }
}

@Composable
private fun ColumnScope.FilesPage() {
    val g = Graph
    val s = g.settings.settings
    val scope = rememberCoroutineScope()

    Group("Depo") {
        SwitchRow(Icons.Outlined.Source, "Son depoyu hatırla", "Uygulama açılışında son seçilen depo ve dal", s.rememberLastRepo) { v ->
            g.settings.update { it.copy(rememberLastRepo = v) }
            if (!v) scope.launch { g.storage.clearLastRepoAndBranch() }
        }
        Hairline()
        SwitchRow(Icons.Outlined.VisibilityOff, "Gizli dosyaları göster", "Adı nokta ile başlayan dosyalar", s.showHiddenFiles) { v ->
            g.settings.update { it.copy(showHiddenFiles = v) }
        }
        Hairline()
        OptionRow(Icons.Outlined.Sort, "Dosya sıralaması", s.repoSort.label) {
            scope.launch {
                Dialogs.pick("Dosya sıralaması", RepoSortMode.values().map { it to it.label }, s.repoSort)?.let { v -> g.settings.update { it.copy(repoSort = v) } }
            }
        }
        Hairline()
        OptionRow(Icons.Outlined.Sort, "Depo listesi sıralaması", s.repoListSort.label) {
            scope.launch {
                Dialogs.pick("Depo listesi sıralaması", RepoListSort.values().map { it to it.label }, s.repoListSort)?.let { v -> g.settings.update { it.copy(repoListSort = v) } }
            }
        }
    }
    Group("Dosya önizleme") {
        OptionRow(Icons.Outlined.Visibility, "Boyut sınırı", AppSettings.formatKb(s.previewMaxKb)) {
            scope.launch {
                Dialogs.pick("Önizleme boyut sınırı", AppSettings.previewMaxKbOptions.map { it to AppSettings.formatKb(it) }, s.previewMaxKb)
                    ?.let { v -> g.settings.update { it.copy(previewMaxKb = v) } }
            }
        }
        Hairline()
        SwitchRow(Icons.AutoMirrored.Filled.WrapText, "Satırları kaydır", null, s.previewWrapLines) { v ->
            g.settings.update { it.copy(previewWrapLines = v) }
        }
        Hairline()
        Column(Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Outlined.FormatSize, null, Modifier.size(22.dp), tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.width(14.dp))
                Text("Yazı boyutu", Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
                Text("${s.previewFontSize.toInt()}", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary)
            }
            Slider(
                value = s.previewFontSize.toFloat(), onValueChange = { v -> g.settings.update { it.copy(previewFontSize = v.toInt().toDouble()) } },
                valueRange = 10f..18f, steps = 7,
            )
        }
    }
}

@Composable
private fun ColumnScope.SecurityPage() {
    val g = Graph
    val s = g.settings.settings
    val scope = rememberCoroutineScope()
    fun lockLabel(sec: Int) = when (sec) { 0 -> "Her seferinde"; 30 -> "30 saniye"; 60 -> "1 dakika"; 300 -> "5 dakika"; else -> "$sec sn" }
    fun logoutLabel(d: Int) = if (d == 0) "Kapalı" else "$d gün"

    Group("Uygulama kilidi") {
        SwitchRow(Icons.Outlined.Dialpad, "PIN ile kilitle", "Uygulama arka plandan dönünce PIN sorulur", s.appLockEnabled) { v ->
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
            Hairline()
            OptionRow(Icons.Outlined.Timer, "Kilitlenme süresi", lockLabel(s.lockTimeoutSeconds)) {
                scope.launch {
                    Dialogs.pick("Arka plandan dönünce kilitle", AppSettings.lockTimeoutOptions.map { it to lockLabel(it) }, s.lockTimeoutSeconds)?.let { v ->
                        g.settings.update { it.copy(lockTimeoutSeconds = v) }.join()
                        g.lock.syncSettings(g.settings.settings)
                    }
                }
            }
            Hairline()
            ActionRow(Icons.Outlined.Key, "PIN'i değiştir", null) {
                scope.launch {
                    if (!Dialogs.pin("Mevcut PIN", create = false)) return@launch
                    if (Dialogs.pin("Yeni PIN", create = true)) Snacks.show("PIN değiştirildi.")
                }
            }
            Hairline()
            ActionRow(Icons.Outlined.Lock, "Şimdi kilitle", null) { g.lock.lockNow() }
        }
    }
    Group("Oturum") {
        OptionRow(Icons.Outlined.Timer, "Otomatik oturum kapatma", logoutLabel(s.autoLogoutDays)) {
            scope.launch {
                Dialogs.pick("Bu kadar gün açılmazsa çıkış yap", AppSettings.autoLogoutOptions.map { it to logoutLabel(it) }, s.autoLogoutDays)
                    ?.let { v -> g.settings.update { it.copy(autoLogoutDays = v) } }
            }
        }
    }
}

@Composable
private fun ColumnScope.DataPage() {
    val g = Graph
    val s = g.settings.settings
    val scope = rememberCoroutineScope()

    Group("Gönderim geçmişi") {
        OptionRow(Icons.Outlined.History, "Saklanan kayıt sayısı", "${s.historyLimit}") {
            scope.launch {
                Dialogs.pick("Saklanan kayıt sayısı", AppSettings.historyLimitOptions.map { it to "$it" }, s.historyLimit)
                    ?.let { v -> g.settings.update { it.copy(historyLimit = v) } }
            }
        }
        Hairline()
        ActionRow(Icons.Outlined.DeleteOutline, "Geçmişi temizle", "Tüm yerel gönderim kayıtları silinir", danger = true) {
            scope.launch {
                if (Dialogs.confirm("Geçmiş temizlensin mi?", "Tüm yerel gönderim kayıtları silinecek.", "Temizle", destructive = true)) g.upload.clearHistory()
            }
        }
    }
    Group("Sıfırlama") {
        ActionRow(Icons.Outlined.RestartAlt, "Ayarları varsayılana döndür", "Hesap ve kilit ayarları korunur") {
            scope.launch {
                if (Dialogs.confirm("Ayarlar sıfırlansın mı?", "Hesap ve kilit ayarları korunur; diğer tüm ayarlar varsayılana döner.", "Sıfırla")) {
                    g.settings.resetToDefaults().join()
                }
            }
        }
    }
}

@Composable
private fun ColumnScope.AboutPage() {
    val scope = rememberCoroutineScope()
    Group {
        InfoRow(Icons.Outlined.Info, "Sürüm", "Gitpush $APP_VERSION")
        Hairline()
        ActionRow(Icons.Outlined.Description, "Açık kaynak lisansları", null) {
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
        }
    }
}

// ───────────────────────── Ortak parçalar ─────────────────────────

/** Başlıklı, yuvarlak köşeli ayar grubu. Satırlar [Hairline] ile ayrılır. */
@Composable
private fun Group(title: String? = null, content: @Composable ColumnScope.() -> Unit) {
    Column {
        if (title != null) {
            Text(
                title, Modifier.padding(start = 8.dp, bottom = 8.dp),
                style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary,
            )
        }
        Card(
            Modifier.fillMaxWidth(), shape = RoundedCornerShape(20.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceContainer),
        ) { Column(content = content) }
    }
}

@Composable
private fun Hairline() {
    HorizontalDivider(Modifier.padding(start = 52.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f))
}

@Composable
private fun RowScaffold(
    icon: ImageVector?, title: String, subtitle: String?, onClick: (() -> Unit)?,
    titleColor: Color = Color.Unspecified, iconTint: Color = MaterialTheme.colorScheme.primary,
    trailing: @Composable () -> Unit = {},
) {
    Row(
        Modifier.fillMaxWidth().then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .heightIn(min = 56.dp).padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, null, Modifier.size(22.dp), tint = iconTint)
            Spacer(Modifier.width(14.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = titleColor)
            if (subtitle != null) {
                Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
        Spacer(Modifier.width(8.dp))
        trailing()
    }
}

@Composable
private fun NavRow(icon: ImageVector, title: String, summary: String, onClick: () -> Unit) {
    RowScaffold(icon, title, summary, onClick) {
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun SwitchRow(icon: ImageVector, title: String, subtitle: String?, value: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    val dim = if (enabled) 1f else 0.5f
    RowScaffold(
        icon, title, subtitle, if (enabled) ({ onChange(!value) }) else null,
        titleColor = MaterialTheme.colorScheme.onSurface.copy(alpha = dim),
        iconTint = MaterialTheme.colorScheme.primary.copy(alpha = dim),
    ) { Switch(checked = value, onCheckedChange = onChange, enabled = enabled) }
}

@Composable
private fun OptionRow(icon: ImageVector, title: String, value: String, onClick: () -> Unit) {
    RowScaffold(icon, title, null, onClick) {
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.primary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.widthIn(max = 160.dp))
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ActionRow(icon: ImageVector, title: String, subtitle: String?, danger: Boolean = false, onClick: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    RowScaffold(
        icon, title, subtitle, onClick,
        titleColor = if (danger) cs.error else Color.Unspecified,
        iconTint = if (danger) cs.error else cs.primary,
    )
}

@Composable
private fun InfoRow(icon: ImageVector, title: String, value: String) {
    RowScaffold(icon, title, null, null) {
        Text(value, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
