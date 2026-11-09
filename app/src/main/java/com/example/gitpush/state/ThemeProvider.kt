package com.example.gitpush.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.gitpush.service.StorageService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

enum class ThemeMode(val key: String) { System("system"), Light("light"), Dark("dark") }

class ThemeProvider(private val storage: StorageService, private val scope: CoroutineScope) {
    var mode by mutableStateOf(ThemeMode.Dark)
        private set

    suspend fun initTheme() {
        val s = storage.getThemeMode()
        mode = ThemeMode.values().firstOrNull { it.key == s } ?: ThemeMode.Dark
    }

    fun setThemeMode(m: ThemeMode) {
        mode = m
        scope.launch { storage.saveThemeMode(m.key) }
    }
}
