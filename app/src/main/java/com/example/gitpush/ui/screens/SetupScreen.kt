package com.example.gitpush.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.HelpOutline
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.service.GitHubDeviceFlow
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.GitpushLogo
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.util.copyToClipboard
import com.example.gitpush.util.openExternalUrl
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupScreen() {
    val g = Graph
    val auth = g.auth
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()
    var mode by remember { mutableStateOf(if (auth.deviceFlowAvailable || auth.canEditClientId) 0 else 1) }
    var allRepos by remember { mutableStateOf(true) }
    var token by remember { mutableStateOf("") }
    var showToken by remember { mutableStateOf(false) }
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var help by remember { mutableStateOf(false) }

    fun login() {
        if (token.isBlank()) { Snacks.show("Lütfen token girin."); return }
        scope.launch {
            if (auth.loginWithToken(token, name, email)) { token = ""; g.settings.success() }
        }
    }

    fun deviceLogin() {
        scope.launch {
            if (!auth.deviceFlowAvailable) {
                val id = Dialogs.prompt(
                    "OAuth Client ID", "Client ID", mono = true,
                    message = "GitHub → Developer settings → OAuth Apps içinde \"Enable Device Flow\" açık bir uygulama oluşturup " +
                        "Client ID'sini yapıştırın. (client_secret gerekmez.)",
                ) ?: return@launch
                if (!auth.setClientId(id)) return@launch
            }
            val ok = auth.loginWithDeviceFlow(
                authorName = name, authorEmail = email,
                scope = if (allRepos) GitHubDeviceFlow.SCOPE_ALL else GitHubDeviceFlow.SCOPE_PUBLIC,
                onCode = { info ->
                    copyToClipboard(ctx, info.userCode)
                    Snacks.show("Kod kopyalandı: ${info.userCode}")
                    openExternalUrl(ctx, info.verificationUri)
                },
            )
            if (ok) g.settings.success()
        }
    }

    Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars).imePadding(), contentAlignment = Alignment.TopCenter) {
        Column(
            Modifier.widthIn(max = 480.dp).fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(Modifier.height(24.dp))
            GitpushLogo(88.dp)
            Spacer(Modifier.height(16.dp))
            Text("Gitpush", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
            Text(
                "Telefonunuzdan GitHub depolarınıza güvenle dosya gönderin.",
                textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(24.dp))

            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                SegmentedButton(selected = mode == 0, onClick = { mode = 0 }, shape = SegmentedButtonDefaults.itemShape(0, 2)) { Text("GitHub ile giriş") }
                SegmentedButton(selected = mode == 1, onClick = { mode = 1 }, shape = SegmentedButtonDefaults.itemShape(1, 2)) { Text("Token ile") }
            }
            Spacer(Modifier.height(16.dp))

            val info = auth.deviceInfo
            if (mode == 0) {
                if (info != null) {
                    Column(
                        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp))
                            .padding(0.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text("Bu kodu GitHub'da girin:", color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Spacer(Modifier.height(8.dp))
                        Text(info.userCode, style = AppTheme.monoBold.copy(fontSize = 32.sp), color = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.height(12.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            FilledTonalButton(onClick = { copyToClipboard(ctx, info.userCode); Snacks.show("Kod kopyalandı") }) {
                                Icon(Icons.Filled.ContentCopy, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Kopyala")
                            }
                            FilledTonalButton(onClick = {
                                if (!openExternalUrl(ctx, info.verificationUri)) Snacks.show("Bağlantı açılamadı: ${info.verificationUri}")
                            }) {
                                Icon(Icons.Outlined.OpenInBrowser, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("GitHub'ı aç")
                            }
                        }
                        Spacer(Modifier.height(12.dp))
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                            Spacer(Modifier.width(8.dp))
                            Text("Onayınız bekleniyor…", fontSize = 13.sp)
                        }
                        TextButton(onClick = { auth.cancelDeviceFlow() }) { Text("İptal") }
                    }
                } else {
                    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                        SegmentedButton(selected = allRepos, onClick = { allRepos = true }, shape = SegmentedButtonDefaults.itemShape(0, 2)) { Text("Tüm depolar") }
                        SegmentedButton(selected = !allRepos, onClick = { allRepos = false }, shape = SegmentedButtonDefaults.itemShape(1, 2)) { Text("Yalnızca herkese açık") }
                    }
                    Spacer(Modifier.height(12.dp))
                    GpTextField(name, { name = it }, Modifier.fillMaxWidth(), label = "Commit yazar adı (isteğe bağlı)", singleLine = true)
                    Spacer(Modifier.height(8.dp))
                    GpTextField(email, { email = it }, Modifier.fillMaxWidth(), label = "Commit yazar e-postası (isteğe bağlı)", singleLine = true)
                    Spacer(Modifier.height(16.dp))
                    Button(onClick = { deviceLogin() }, enabled = !auth.isLoading, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                        Text("GitHub ile Giriş Yap")
                    }
                    if (auth.canEditClientId && auth.deviceFlowAvailable) {
                        TextButton(onClick = { scope.launch { auth.clearClientId() } }) { Text("Client ID'yi sıfırla") }
                    }
                }
            } else {
                GpTextField(
                    token, { token = it }, Modifier.fillMaxWidth(), label = "GitHub Personal Access Token", singleLine = true, mono = true,
                    visualTransformation = if (showToken) VisualTransformation.None else PasswordVisualTransformation(),
                    trailing = {
                        IconButton(onClick = { showToken = !showToken }) {
                            Icon(if (showToken) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, null)
                        }
                    },
                )
                Spacer(Modifier.height(8.dp))
                GpTextField(name, { name = it }, Modifier.fillMaxWidth(), label = "Commit yazar adı (isteğe bağlı)", singleLine = true)
                Spacer(Modifier.height(8.dp))
                GpTextField(email, { email = it }, Modifier.fillMaxWidth(), label = "Commit yazar e-postası (isteğe bağlı)", singleLine = true)
                Spacer(Modifier.height(16.dp))
                Button(onClick = { login() }, enabled = !auth.isLoading, modifier = Modifier.fillMaxWidth().height(52.dp)) {
                    if (auth.isLoading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp) else Text("Giriş Yap")
                }
                TextButton(onClick = { help = true }) {
                    Icon(Icons.Outlined.HelpOutline, null, Modifier.size(16.dp)); Spacer(Modifier.width(6.dp)); Text("Token nasıl alınır?")
                }
            }

            auth.errorMessage?.let {
                Spacer(Modifier.height(12.dp))
                Text(it, color = MaterialTheme.colorScheme.error, textAlign = TextAlign.Center)
            }
            Spacer(Modifier.height(24.dp))
            Text(
                "Token cihazınızda Android Keystore ile şifreli saklanır; yalnızca api.github.com adresine gönderilir.",
                fontSize = 12.sp, textAlign = TextAlign.Center, color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }

    if (help) {
        ModalBottomSheet(onDismissRequest = { help = false }) {
            Column(Modifier.padding(horizontal = 24.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState())) {
                Text("Token nasıl alınır?", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(12.dp))
                Text(
                    "1. GitHub → Settings → Developer settings → Personal access tokens bölümüne gidin.\n" +
                        "2. Fine-grained (önerilir) veya Classic token oluşturun.\n" +
                        "3. Classic için `repo` ve `workflow` yetkilerini; fine-grained için ilgili depolarda " +
                        "Contents (Read & write) ve Actions yetkilerini verin.\n" +
                        "4. Oluşan token'ı kopyalayıp buraya yapıştırın.\n\n" +
                        "Token'ı kimseyle paylaşmayın. İstediğiniz zaman GitHub'dan iptal edebilirsiniz.",
                )
                Spacer(Modifier.height(16.dp))
                OutlinedButton(onClick = {
                    openExternalUrl(ctx, "https://github.com/settings/tokens")
                }) { Text("GitHub token sayfasını aç") }
            }
        }
    }
}
