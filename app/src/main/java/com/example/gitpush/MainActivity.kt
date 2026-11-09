package com.example.gitpush

import android.content.pm.ActivityInfo
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.lifecycleScope
import com.example.gitpush.ui.GitpushRoot
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private var ready by mutableStateOf(false)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Tablette yalnızca yatay; telefonda tüm yönler.
        val isTablet = resources.configuration.smallestScreenWidthDp >= 600
        if (isTablet) requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE

        Graph.settings.hapticView = window.decorView

        if (!ready) {
            lifecycleScope.launch {
                bootstrap()
                ready = true
            }
        }

        setContent { GitpushRoot(ready = ready) }
    }

    /** Açılış sırası: ayarlar → otomatik oturum kapatma → tema → kayıtlı oturum → kilit → geçmiş. */
    private suspend fun bootstrap() {
        val g = Graph
        g.settings.load()
        applyAutoLogout(g.settings.settings.autoLogoutDays)
        g.storage.touchLastActive()
        g.theme.initTheme()
        g.auth.checkSavedAuth()
        g.lock.init(g.settings.settings)
        g.upload.loadHistory()
    }

    /** Ayarlanan gün kadar açılmayan cihazda token ve yerel veri silinir. */
    private suspend fun applyAutoLogout(days: Int, now: Long = System.currentTimeMillis()): Boolean {
        if (days <= 0) return false
        val last = Graph.storage.getLastActive() ?: return false
        val elapsedDays = (now - last) / (24L * 60 * 60 * 1000)
        if (elapsedDays >= days) {
            Graph.storage.clearAllUserData()
            return true
        }
        return false
    }
}
