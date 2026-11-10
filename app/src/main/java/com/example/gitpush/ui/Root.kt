package com.example.gitpush.ui

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.graphics.drawable.ColorDrawable
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalContext
import androidx.compose.runtime.key
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.SideEffect
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.unit.dp
import com.example.gitpush.Graph
import com.example.gitpush.state.ThemeMode
import com.example.gitpush.ui.components.KeepAlive
import com.example.gitpush.ui.components.LocalActive
import com.example.gitpush.ui.screens.CommitsScreen
import com.example.gitpush.ui.screens.FileDetailScreen
import com.example.gitpush.ui.screens.FileEditorScreen
import com.example.gitpush.ui.screens.LockScreen
import com.example.gitpush.ui.screens.MainShell
import com.example.gitpush.ui.screens.MultiFileScreen
import com.example.gitpush.ui.screens.PreviewScreen
import com.example.gitpush.ui.screens.RepoPickerScreen
import com.example.gitpush.ui.screens.SecretsScreen
import com.example.gitpush.ui.screens.ResultScreen
import com.example.gitpush.ui.screens.OnboardingScreen
import com.example.gitpush.ui.screens.ZipTransferScreen
import com.example.gitpush.ui.theme.GitpushTheme
import androidx.compose.ui.graphics.Color as ComposeColor

@Composable
fun GitpushRoot(ready: Boolean) {
    val g = Graph
    val settings = g.settings.settings
    val dark = when (g.theme.mode) {
        ThemeMode.Light -> false
        ThemeMode.Dark -> true
        ThemeMode.System -> isSystemInDarkTheme()
    }
    val scope = rememberCoroutineScope()
    SideEffect { Snacks.scope = scope }

    GitpushTheme(seed = ComposeColor(settings.accentColorValue), dark = dark, amoled = settings.amoledDark) {
        SystemBarsAndWindow(dark)
        Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
            if (!ready) {
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { CircularProgressIndicator() }
                return@Surface
            }
            val nav = g.nav
            Box(Modifier.fillMaxSize()) {
                // Kök geri tuşu: yığın doluysa en üstteki ekranı kapatır (ekranlar kendi BackHandler'ını sonra ekler).
                BackHandler(enabled = nav.stack.isNotEmpty()) { nav.pop() }

                if (!g.auth.isAuthenticated || g.auth.onboarding) {
                    OnboardingScreen()
                } else {
                    val total = nav.stack.size + 1
                    KeepAlive(visible = nav.stack.isEmpty()) {
                        CompositionLocalProvider(LocalActive provides nav.stack.isEmpty()) { MainShell() }
                    }
                    nav.stack.forEachIndexed { i, entry ->
                        key(entry.id) {
                            val top = i == nav.stack.size - 1
                            KeepAlive(visible = top) {
                                CompositionLocalProvider(LocalActive provides top) {
                                    Surface(
                                        Modifier.fillMaxSize().pointerInput(Unit) {},
                                        color = MaterialTheme.colorScheme.surface,
                                    ) { RouteContent(entry.route) }
                                }
                            }
                        }
                    }
                }

                SnackbarHost(
                    Snacks.host,
                    Modifier.align(Alignment.BottomCenter).windowInsetsPadding(WindowInsets.navigationBars).padding(bottom = 72.dp),
                )

                DialogHost()

                if (g.lock.locked) {
                    BackHandler(enabled = true) { /* kilitliyken geri tuşu yutulur */ }
                    LockScreen()
                }
            }
        }
    }
}

@Composable
private fun RouteContent(route: Route) {
    when (route) {
        Route.RepoPicker -> RepoPickerScreen()
        Route.Zip -> ZipTransferScreen()
        Route.Multi -> MultiFileScreen()
        Route.Secrets -> SecretsScreen()
        is Route.Preview -> PreviewScreen(route.source, route.commitMessage)
        is Route.Result -> ResultScreen(route)
        is Route.FileDetail -> FileDetailScreen(route.entry)
        is Route.FileEditor -> FileEditorScreen(route)
        is Route.Commits -> CommitsScreen(route.path)
    }
}

private fun Context.findActivity(): Activity? {
    var c: Context? = this
    while (c is ContextWrapper) {
        if (c is Activity) return c
        c = c.baseContext
    }
    return null
}

/**
 * Durum/gezinme çubuğu simgeleri ve pencere zemini SİSTEM temasına değil UYGULAMANIN seçili temasına uyar.
 * (Önceden "açık" seçiliyken sistem koyuysa üst çubuk koyu kalıyor, simgeler okunmuyordu.)
 */
@Composable
private fun SystemBarsAndWindow(dark: Boolean) {
    val activity = LocalContext.current.findActivity() as? ComponentActivity ?: return
    val bg = MaterialTheme.colorScheme.surface.toArgb()
    DisposableEffect(dark) {
        activity.enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT) { dark },
            navigationBarStyle = SystemBarStyle.auto(android.graphics.Color.TRANSPARENT, android.graphics.Color.TRANSPARENT) { dark },
        )
        if (Build.VERSION.SDK_INT >= 29) activity.window.isNavigationBarContrastEnforced = false
        onDispose { }
    }
    DisposableEffect(bg) {
        activity.window.setBackgroundDrawable(ColorDrawable(bg))
        onDispose { }
    }
}
