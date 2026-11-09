package com.example.gitpush.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.ContentCopy
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.outlined.AccountCircle
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.FolderZip
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material.icons.outlined.OpenInBrowser
import androidx.compose.material.icons.outlined.Public
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.VpnKey
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.example.gitpush.Graph
import com.example.gitpush.service.GitHubDeviceFlow
import com.example.gitpush.ui.Snacks
import com.example.gitpush.ui.components.GitpushLogo
import com.example.gitpush.ui.components.GpTextField
import com.example.gitpush.ui.theme.AppTheme
import com.example.gitpush.ui.theme.GlassBackdrop
import com.example.gitpush.ui.theme.glass
import com.example.gitpush.ui.theme.glow
import com.example.gitpush.util.copyToClipboard
import com.example.gitpush.util.openExternalUrl
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

private enum class Step { Welcome, Method, Access, Verify, Identity, Done }
private enum class Method { GitHub, Token }

/**
 * Adım adım giriş / kurulum akışı:
 * Karşılama → Yöntem → (Erişim) → Doğrulama → Commit kimliği → Hazır.
 *
 * GitHub ile girişte e-posta ve doğrulayıcı uygulama (2 adımlı doğrulama) adımları GitHub'ın kendi
 * sayfasında yapılır; uygulama parolayı veya doğrulama kodunu hiç görmez, yalnızca sonunda bir token alır.
 */
@Composable
fun OnboardingScreen() {
    val g = Graph
    val auth = g.auth
    val ctx = LocalContext.current
    val scope = rememberCoroutineScope()

    var step by rememberSaveable { mutableStateOf(Step.Welcome) }
    var method by rememberSaveable { mutableStateOf(Method.GitHub) }
    var allRepos by rememberSaveable { mutableStateOf(true) }
    // Gizli değerler rememberSaveable ile saklanmaz.
    var token by remember { mutableStateOf("") }
    var name by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var starting by remember { mutableStateOf(false) }

    // Giriş sonrası kurulum adımları bitene kadar ana ekrana geçilmez.
    LaunchedEffect(Unit) { if (!auth.isAuthenticated) auth.beginOnboarding() }

    val flow = remember(method) {
        if (method == Method.Token) listOf(Step.Welcome, Step.Method, Step.Verify, Step.Identity, Step.Done)
        else Step.values().toList()
    }

    fun go(s: Step) { g.settings.tap(); step = s }

    fun back() {
        when (step) {
            Step.Method -> go(Step.Welcome)
            Step.Access -> go(Step.Method)
            Step.Verify -> {
                auth.cancelDeviceFlow(); auth.clearError(); starting = false
                go(if (method == Method.Token) Step.Method else Step.Access)
            }
            else -> Unit
        }
    }

    fun startDeviceLogin() {
        if (starting || auth.deviceInfo != null) return
        starting = true // eşzamanlı: "Tekrar dene" düğmesi bir an bile görünmesin
        scope.launch {
            auth.clearError()
            val ok = auth.loginWithDeviceFlow(
                scope = if (allRepos) GitHubDeviceFlow.SCOPE_ALL else GitHubDeviceFlow.SCOPE_PUBLIC,
                onCode = { info ->
                    starting = false
                    copyToClipboard(ctx, info.userCode)
                    Snacks.show("Kod kopyalandı: ${info.userCode}")
                    openExternalUrl(ctx, info.verificationUri)
                },
            )
            starting = false
            if (ok) { g.settings.success(); step = Step.Identity }
        }
    }

    fun tokenLogin() {
        if (token.isBlank()) { Snacks.show("Lütfen token girin."); return }
        scope.launch {
            if (auth.loginWithToken(token)) { token = ""; g.settings.success(); step = Step.Identity }
        }
    }

    // Kimlik adımına girerken GitHub profilinden önceden doldur.
    LaunchedEffect(step) {
        if (step == Step.Identity) {
            if (name.isBlank()) name = auth.suggestedAuthorName
            if (email.isBlank()) email = auth.suggestedAuthorEmail
        }
    }

    BackHandler(enabled = step == Step.Method || step == Step.Access || step == Step.Verify) { back() }

    GlassBackdrop {
        Column(
            Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars).imePadding(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            // Üst şerit: geri + ilerleme göstergesi
            Row(
                Modifier.widthIn(max = 480.dp).fillMaxWidth().height(56.dp).padding(horizontal = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(Modifier.size(48.dp), contentAlignment = Alignment.Center) {
                    val canBack = step == Step.Method || step == Step.Access || step == Step.Verify
                    if (canBack) IconButton(onClick = { back() }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") }
                }
                Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    StepDots(current = flow.indexOf(step).coerceAtLeast(0), total = flow.size)
                }
                Spacer(Modifier.width(48.dp))
            }

            AnimatedContent(
                targetState = step,
                modifier = Modifier.weight(1f).widthIn(max = 480.dp).fillMaxWidth(),
                transitionSpec = {
                    val forward = targetState.ordinal >= initialState.ordinal
                    val dir = if (forward) 1 else -1
                    (slideInHorizontally(tween(340)) { dir * it / 5 } + fadeIn(tween(340))) togetherWith
                        (slideOutHorizontally(tween(240)) { -dir * it / 5 } + fadeOut(tween(180)))
                },
                label = "step",
            ) { s ->
                when (s) {
                    Step.Welcome -> WelcomeStep(onStart = { go(Step.Method) })

                    Step.Method -> MethodStep(
                        method = method, onSelect = { g.settings.tap(); method = it },
                        onNext = { go(if (method == Method.Token) Step.Verify else Step.Access) },
                    )

                    Step.Access -> AccessStep(
                        allRepos = allRepos, onSelect = { g.settings.tap(); allRepos = it },
                        onNext = { go(Step.Verify); if (auth.deviceFlowAvailable) startDeviceLogin() },
                    )

                    Step.Verify ->
                        if (method == Method.Token) TokenStep(
                            token = token, onToken = { token = it }, loading = auth.isLoading,
                            error = auth.errorMessage, onSubmit = { tokenLogin() },
                            onOpenGitHub = { openExternalUrl(ctx, "https://github.com/settings/tokens") },
                        ) else DeviceStep(
                            starting = starting,
                            onRetry = { startDeviceLogin() },
                            onSaveClientId = { id -> scope.launch { if (auth.setClientId(id)) startDeviceLogin() } },
                        )

                    Step.Identity -> IdentityStep(
                        name = name, onName = { name = it }, email = email, onEmail = { email = it },
                        onNext = { scope.launch { auth.updateAuthorInfo(name, email); go(Step.Done) } },
                        onSkip = { go(Step.Done) },
                    )

                    Step.Done -> DoneStep(
                        username = auth.username.orEmpty(),
                        onFinish = { g.settings.success(); auth.finishOnboarding() },
                    )
                }
            }
        }
    }
}

// ───────────────────────── Adımlar ─────────────────────────

@Composable
private fun WelcomeStep(onStart: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    StepScaffold(
        bottom = { PrimaryButton("Başla", onStart) },
    ) {
        Spacer(Modifier.height(24.dp))
        Enter(0) {
            Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                Box(Modifier.glow(cs.primary, 36.dp, 0.40f)) { GitpushLogo(96.dp) }
            }
        }
        Spacer(Modifier.height(24.dp))
        Enter(120) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text("Gitpush", fontSize = 36.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(
                    "GitHub'ı telefonunuzdan sade ve güvenle yönetin.",
                    textAlign = TextAlign.Center, color = cs.onSurfaceVariant, fontSize = 16.sp,
                )
            }
        }
        Spacer(Modifier.height(32.dp))
        Enter(240) { FeatureRow(Icons.Outlined.FolderZip, "Dosya ve ZIP gönderimi", "Tek atomik commit ile güvenle yükleyin.") }
        Spacer(Modifier.height(10.dp))
        Enter(320) { FeatureRow(Icons.Outlined.Bolt, "Depo, dal ve Actions", "Hepsi telefona uygun, sade ekranlarda.") }
        Spacer(Modifier.height(10.dp))
        Enter(400) { FeatureRow(Icons.Outlined.Shield, "Cihazınızda güvende", "Token Android Keystore ile şifreli saklanır.") }
        Spacer(Modifier.height(16.dp))
    }
}

@Composable
private fun MethodStep(method: Method, onSelect: (Method) -> Unit, onNext: () -> Unit) {
    StepScaffold(bottom = { PrimaryButton("Devam", onNext) }) {
        StepTitle("Nasıl giriş yapmak istersiniz?", "Daha sonra Ayarlar'dan hesabı değiştirebilirsiniz.")
        ChoiceCard(
            selected = method == Method.GitHub, icon = Icons.Outlined.AccountCircle,
            title = "GitHub hesabı", badge = "ÖNERİLEN",
            description = "E-postanızla giriş yapıp doğrulayıcı uygulamanızla (2 adımlı doğrulama) onaylarsınız. " +
                "Bunlar GitHub'ın kendi sayfasında olur; şifrenizi bu uygulama görmez.",
            onClick = { onSelect(Method.GitHub) },
        )
        Spacer(Modifier.height(12.dp))
        ChoiceCard(
            selected = method == Method.Token, icon = Icons.Outlined.VpnKey,
            title = "Erişim token'ı", badge = "GELİŞMİŞ",
            description = "Kendi oluşturduğunuz Personal Access Token ile giriş yapın.",
            onClick = { onSelect(Method.Token) },
        )
    }
}

@Composable
private fun AccessStep(allRepos: Boolean, onSelect: (Boolean) -> Unit, onNext: () -> Unit) {
    StepScaffold(bottom = { PrimaryButton("GitHub ile devam et", onNext) }) {
        StepTitle("Hangi depolara erişilsin?", "Gitpush yalnızca burada verdiğiniz yetkiyle çalışır.")
        ChoiceCard(
            selected = allRepos, icon = Icons.Outlined.Lock, title = "Tüm depolar",
            description = "Özel ve herkese açık depolarınızı yönetebilirsiniz.",
            onClick = { onSelect(true) },
        )
        Spacer(Modifier.height(12.dp))
        ChoiceCard(
            selected = !allRepos, icon = Icons.Outlined.Public, title = "Yalnızca herkese açık",
            description = "Özel depolarınıza erişilmez.",
            onClick = { onSelect(false) },
        )
        Spacer(Modifier.height(16.dp))
        Text(
            "Yetkiyi istediğiniz zaman GitHub → Settings → Applications bölümünden kaldırabilirsiniz.",
            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = 4.dp),
        )
    }
}

@Composable
private fun DeviceStep(starting: Boolean, onRetry: () -> Unit, onSaveClientId: (String) -> Unit) {
    val g = Graph
    val auth = g.auth
    val ctx = LocalContext.current
    val cs = MaterialTheme.colorScheme
    val info = auth.deviceInfo
    var clientId by remember { mutableStateOf("") }

    StepScaffold(bottom = {
        if (info == null && !starting && auth.deviceFlowAvailable) PrimaryButton("Tekrar dene", onRetry)
        if (info != null) TextButton(onClick = { auth.cancelDeviceFlow() }, modifier = Modifier.fillMaxWidth()) { Text("İptal") }
    }) {
        StepTitle("GitHub'da onaylayın", "Giriş ve doğrulama GitHub'ın kendi sayfasında yapılır.")

        if (!auth.deviceFlowAvailable) {
            // Derlemede Client ID verilmemişse burada girilir.
            Column(Modifier.fillMaxWidth().glass(24.dp).padding(16.dp)) {
                Text("OAuth Client ID gerekli", fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(6.dp))
                Text(
                    "GitHub → Developer settings → OAuth Apps içinde \"Enable Device Flow\" açık bir uygulama " +
                        "oluşturup Client ID'sini yapıştırın. (client_secret gerekmez.)",
                    fontSize = 13.sp, color = cs.onSurfaceVariant,
                )
                Spacer(Modifier.height(12.dp))
                GpTextField(clientId, { clientId = it }, Modifier.fillMaxWidth(), label = "Client ID", singleLine = true, mono = true)
                Spacer(Modifier.height(12.dp))
                PrimaryButton("Kaydet ve devam et", { onSaveClientId(clientId) }, enabled = clientId.isNotBlank())
            }
        } else if (info != null) {
            Column(
                Modifier.fillMaxWidth().glass(28.dp, tint = cs.primary.copy(alpha = 0.10f)).padding(20.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                Text("Bu kodu GitHub'da girin", color = cs.onSurfaceVariant, fontSize = 13.sp)
                Spacer(Modifier.height(8.dp))
                Text(info.userCode, style = AppTheme.monoBold.copy(fontSize = 34.sp, letterSpacing = 4.sp), color = cs.primary)
                Spacer(Modifier.height(14.dp))
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
                Spacer(Modifier.height(16.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                    Text("Onayınız bekleniyor…", fontSize = 13.sp)
                }
            }
            Spacer(Modifier.height(16.dp))
            NumberedLine(1, "GitHub açılır; e-posta adresinizle giriş yapın.")
            NumberedLine(2, "2 adımlı doğrulama açıksa doğrulayıcı uygulamanızdaki kodu girin.")
            NumberedLine(3, "Yukarıdaki kodu yazıp \"Authorize\" düğmesine dokunun, sonra buraya dönün.")
        } else if (starting) {
            Box(Modifier.fillMaxWidth().padding(vertical = 40.dp), contentAlignment = Alignment.Center) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(12.dp))
                    Text("GitHub'a bağlanılıyor…")
                }
            }
        }

        auth.errorMessage?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, color = cs.error, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun TokenStep(
    token: String, onToken: (String) -> Unit, loading: Boolean, error: String?,
    onSubmit: () -> Unit, onOpenGitHub: () -> Unit,
) {
    val cs = MaterialTheme.colorScheme
    var show by remember { mutableStateOf(false) }
    StepScaffold(bottom = { PrimaryButton("Giriş yap", onSubmit, loading = loading, enabled = token.isNotBlank()) }) {
        StepTitle("Token'ınızı girin", "Classic: repo + workflow · Fine-grained: Contents ve Actions (Read & write).")
        Column(Modifier.fillMaxWidth().glass(24.dp).padding(16.dp)) {
            GpTextField(
                token, onToken, Modifier.fillMaxWidth(), label = "GitHub Personal Access Token", singleLine = true, mono = true,
                visualTransformation = if (show) VisualTransformation.None else PasswordVisualTransformation(),
                trailing = {
                    IconButton(onClick = { show = !show }) {
                        Icon(if (show) Icons.Filled.VisibilityOff else Icons.Filled.Visibility, null)
                    }
                },
            )
            TextButton(onClick = onOpenGitHub) { Text("Token oluşturma sayfasını aç") }
        }
        error?.let {
            Spacer(Modifier.height(12.dp))
            Text(it, color = cs.error, textAlign = TextAlign.Center, modifier = Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun IdentityStep(
    name: String, onName: (String) -> Unit, email: String, onEmail: (String) -> Unit,
    onNext: () -> Unit, onSkip: () -> Unit,
) {
    StepScaffold(bottom = {
        PrimaryButton("Devam", onNext)
        TextButton(onClick = onSkip, modifier = Modifier.fillMaxWidth()) { Text("Şimdilik atla") }
    }) {
        StepTitle(
            "Commit kimliğiniz",
            "Gönderdiğiniz commit'lerde bu ad ve e-posta görünür. GitHub profilinizden dolduruldu; değiştirebilirsiniz.",
        )
        Column(Modifier.fillMaxWidth().glass(24.dp).padding(16.dp)) {
            GpTextField(name, onName, Modifier.fillMaxWidth(), label = "Ad", singleLine = true)
            Spacer(Modifier.height(10.dp))
            GpTextField(email, onEmail, Modifier.fillMaxWidth(), label = "E-posta", singleLine = true)
        }
        Spacer(Modifier.height(12.dp))
        Text(
            "Herkese açık e-postanız yoksa GitHub'ın gizlilik dostu \"noreply\" adresi önerilir; commit'ler hesabınıza bağlanır, gerçek adresiniz görünmez.",
            fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.padding(horizontal = 4.dp),
        )
    }
}

@Composable
private fun DoneStep(username: String, onFinish: () -> Unit) {
    val cs = MaterialTheme.colorScheme
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val scale by animateFloatAsState(
        if (shown) 1f else 0.4f, spring(Spring.DampingRatioMediumBouncy, Spring.StiffnessLow), label = "done",
    )
    StepScaffold(bottom = { PrimaryButton("Gitpush'a geç", onFinish) }) {
        Spacer(Modifier.height(56.dp))
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            Box(
                Modifier.graphicsLayer { scaleX = scale; scaleY = scale }
                    .glow(cs.primary, 40.dp, 0.45f).size(104.dp)
                    .glass(52.dp, tint = cs.primary.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.Check, null, Modifier.size(48.dp), tint = cs.primary) }
        }
        Spacer(Modifier.height(28.dp))
        Enter(200) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
                Text("Hazırsınız", fontSize = 30.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(8.dp))
                Text(
                    if (username.isNotBlank()) "@$username olarak giriş yapıldı." else "Giriş yapıldı.",
                    color = cs.onSurfaceVariant, textAlign = TextAlign.Center,
                )
            }
        }
    }
}

// ───────────────────────── Ortak parçalar ─────────────────────────

/** İçerik kaydırılır, alt eylem alanı sabit kalır. */
@Composable
private fun StepScaffold(bottom: @Composable () -> Unit = {}, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) { content() }
        Column(Modifier.padding(top = 8.dp, bottom = 16.dp)) { bottom() }
    }
}

@Composable
private fun StepTitle(title: String, subtitle: String) {
    Column(Modifier.padding(top = 8.dp, bottom = 24.dp)) {
        Text(title, fontSize = 28.sp, fontWeight = FontWeight.Bold, lineHeight = 34.sp)
        Spacer(Modifier.height(8.dp))
        Text(subtitle, color = MaterialTheme.colorScheme.onSurfaceVariant, fontSize = 15.sp)
    }
}

@Composable
private fun StepDots(current: Int, total: Int) {
    val cs = MaterialTheme.colorScheme
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
        repeat(total) { i ->
            val active = i == current
            val w by animateDpAsState(if (active) 26.dp else 8.dp, tween(300), label = "dotW")
            val c by animateColorAsState(
                when {
                    active -> cs.primary
                    i < current -> cs.primary.copy(alpha = 0.55f)
                    else -> Color.White.copy(alpha = 0.18f)
                },
                tween(300), label = "dotC",
            )
            Box(Modifier.height(8.dp).width(w).clip(CircleShape).background(c))
        }
    }
}

@Composable
private fun PrimaryButton(text: String, onClick: () -> Unit, enabled: Boolean = true, loading: Boolean = false) {
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(28.dp)
    Button(
        onClick = onClick, enabled = enabled && !loading,
        modifier = Modifier.fillMaxWidth().height(56.dp).let {
            if (enabled) it.shadow(18.dp, shape, ambientColor = cs.primary, spotColor = cs.primary) else it
        },
        shape = shape,
    ) {
        if (loading) CircularProgressIndicator(Modifier.size(22.dp), strokeWidth = 2.dp, color = cs.onPrimary)
        else Text(text, fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
    }
}

@Composable
private fun ChoiceCard(
    selected: Boolean, icon: ImageVector, title: String, description: String,
    onClick: () -> Unit, badge: String? = null,
) {
    val cs = MaterialTheme.colorScheme
    val shape = RoundedCornerShape(22.dp)
    val ring by animateColorAsState(if (selected) cs.primary else Color.Transparent, tween(250), label = "ring")
    Row(
        Modifier.fillMaxWidth()
            .glass(22.dp, tint = if (selected) cs.primary.copy(alpha = 0.12f) else Color.White.copy(alpha = 0.05f))
            .border(1.5.dp, ring, shape)
            .clip(shape).clickable(onClick = onClick)
            .padding(16.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Icon(icon, null, Modifier.size(28.dp), tint = if (selected) cs.primary else cs.onSurfaceVariant)
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(title, fontWeight = FontWeight.Bold, fontSize = 17.sp)
                if (badge != null) {
                    Spacer(Modifier.width(8.dp))
                    Box(Modifier.clip(RoundedCornerShape(6.dp)).background(cs.primary.copy(alpha = 0.18f)).padding(horizontal = 6.dp, vertical = 2.dp)) {
                        Text(badge, style = AppTheme.monoBold.copy(fontSize = 10.sp), color = cs.primary)
                    }
                }
            }
            Spacer(Modifier.height(4.dp))
            Text(description, fontSize = 13.sp, color = cs.onSurfaceVariant, lineHeight = 18.sp)
        }
        Spacer(Modifier.width(8.dp))
        Box(
            Modifier.size(22.dp).clip(CircleShape).background(if (selected) cs.primary else Color.White.copy(alpha = 0.10f)),
            contentAlignment = Alignment.Center,
        ) { if (selected) Icon(Icons.Filled.Check, null, Modifier.size(14.dp), tint = cs.onPrimary) }
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, title: String, desc: String) {
    val cs = MaterialTheme.colorScheme
    Row(
        Modifier.fillMaxWidth().glass(20.dp).padding(14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, null, Modifier.size(24.dp), tint = cs.primary)
        Spacer(Modifier.width(14.dp))
        Column {
            Text(title, fontWeight = FontWeight.SemiBold)
            Text(desc, fontSize = 13.sp, color = cs.onSurfaceVariant)
        }
    }
}

@Composable
private fun NumberedLine(n: Int, text: String) {
    val cs = MaterialTheme.colorScheme
    Row(Modifier.fillMaxWidth().padding(vertical = 5.dp), verticalAlignment = Alignment.Top) {
        Box(Modifier.size(22.dp).clip(CircleShape).background(cs.primary.copy(alpha = 0.18f)), contentAlignment = Alignment.Center) {
            Text("$n", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = cs.primary)
        }
        Spacer(Modifier.width(12.dp))
        Text(text, fontSize = 14.sp, color = cs.onSurfaceVariant, modifier = Modifier.weight(1f))
    }
}

/** Hafif giriş efekti: gecikmeli solma + aşağıdan yükselme. */
@Composable
private fun Enter(delayMs: Int, content: @Composable () -> Unit) {
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { delay(delayMs.toLong()); shown = true }
    val a by animateFloatAsState(if (shown) 1f else 0f, tween(450), label = "enter")
    Box(Modifier.graphicsLayer { alpha = a; translationY = (1f - a) * 24.dp.toPx() }) { content() }
}
