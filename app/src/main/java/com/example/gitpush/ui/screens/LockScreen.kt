package com.example.gitpush.ui.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.example.gitpush.Graph
import com.example.gitpush.ui.Dialogs
import com.example.gitpush.ui.components.GitpushLogo
import com.example.gitpush.ui.components.PinPad
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Uygulama kilidi ekranı: tüm içeriğin üzerinde, dokunmaları yutar. */
@Composable
fun LockScreen() {
    val g = Graph
    val scope = rememberCoroutineScope()
    var error by remember { mutableStateOf<String?>(null) }
    var resetToken by remember { mutableIntStateOf(0) }
    var lockedMs by remember { mutableLongStateOf(0L) }
    var busy by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) { lockedMs = g.lock.service.lockoutRemaining() }
    LaunchedEffect(lockedMs) {
        var ms = lockedMs
        while (ms > 0) {
            delay(1000)
            ms -= 1000
            lockedMs = if (ms < 0) 0 else ms
            if (ms <= 0) break
        }
    }

    fun submit(pin: String) {
        scope.launch {
            busy = true
            val r = g.lock.tryUnlock(pin)
            busy = false
            if (r.ok) { g.settings.success(); return@launch }
            resetToken++
            if (r.isLockedOut) {
                lockedMs = r.lockedForMs
                error = null
            } else {
                error = "Hatalı PIN."
            }
        }
    }

    Surface(Modifier.fillMaxSize().pointerInput(Unit) {}, color = MaterialTheme.colorScheme.surface) {
        Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.systemBars), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                GitpushLogo(72.dp)
                Spacer(Modifier.height(16.dp))
                Text("Gitpush kilitli", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(4.dp))
                Text("Devam etmek için PIN'inizi girin", color = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(Modifier.height(24.dp))
                val secs = (lockedMs + 999) / 1000
                PinPad(
                    onCompleted = { submit(it) },
                    errorText = if (lockedMs > 0) "Çok fazla hatalı deneme. $secs sn sonra tekrar deneyin." else error,
                    enabled = !busy && lockedMs <= 0,
                    resetToken = resetToken,
                )
                TextButton(onClick = {
                    scope.launch {
                        val ok = Dialogs.confirm(
                            "PIN'imi unuttum",
                            "PIN'i sıfırlamak için oturumunuz kapatılacak; token ve yerel veriler cihazdan silinecek. " +
                                "Ardından yeniden giriş yapabilirsiniz.",
                            confirmLabel = "Oturumu kapat ve sıfırla", destructive = true,
                        )
                        if (ok) {
                            g.lock.wipe()
                            g.settings.update { it.copy(appLockEnabled = false) }
                            g.repo.reset()
                            g.upload.resetAll()
                            g.auth.logout()
                        }
                    }
                }) { Text("PIN'imi unuttum") }
            }
        }
    }
}
