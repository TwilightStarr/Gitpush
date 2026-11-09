package com.example.gitpush.state

import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.gitpush.model.AppSettings
import com.example.gitpush.service.StorageService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

class SettingsProvider(private val storage: StorageService, private val scope: CoroutineScope) {
    var settings by mutableStateOf(AppSettings())
        private set

    /** Titreşim için pencere görünümü (MainActivity atar). */
    var hapticView: View? = null

    suspend fun load() {
        settings = try { storage.getAppSettings() } catch (_: Exception) { AppSettings() }
    }

    /** Durumu anında günceller, diske arka planda yazar. Sıralama gerekiyorsa dönen Job beklenir. */
    fun update(change: (AppSettings) -> AppSettings): Job {
        val next = change(settings)
        settings = next
        return scope.launch { try { storage.saveAppSettings(next) } catch (_: Exception) { } }
    }

    /** Hesap ve kilit ayarları korunur; geri kalanı varsayılana döner. */
    fun resetToDefaults(): Job = update {
        AppSettings(appLockEnabled = it.appLockEnabled, lockTimeoutSeconds = it.lockTimeoutSeconds)
    }

    fun tap() {
        if (settings.haptics) hapticView?.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    }

    fun success() {
        if (settings.haptics) hapticView?.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    }
}
