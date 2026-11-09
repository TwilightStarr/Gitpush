package com.example.gitpush.service

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.example.gitpush.model.AppSettings
import com.example.gitpush.model.HistoryItem
import com.example.gitpush.util.asArr
import com.example.gitpush.util.asStr
import com.example.gitpush.util.parseJson
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive

/** Android Keystore destekli şifreli depolama (token, PIN karması). */
class SecureStore(private val context: Context) {
    private val prefs: SharedPreferences by lazy {
        val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(
            context, "gitpush_secure", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    fun read(key: String): String? = try { prefs.getString(key, null) } catch (_: Exception) { null }
    fun write(key: String, value: String) { prefs.edit().putString(key, value).commit() }
    fun delete(key: String) { prefs.edit().remove(key).commit() }
}

class StorageService(context: Context) {
    private val ctx = context.applicationContext
    val secure = SecureStore(ctx)
    private val prefs: SharedPreferences = ctx.getSharedPreferences("gitpush_prefs", Context.MODE_PRIVATE)

    companion object {
        private const val KEY_TOKEN = "gitpush_github_token"
        private const val KEY_USERNAME = "gitpush_github_username"
        private const val KEY_AUTHOR_NAME = "gitpush_author_name"
        private const val KEY_AUTHOR_EMAIL = "gitpush_author_email"
        private const val KEY_SHORTCUTS = "gitpush_custom_shortcuts"
        private const val KEY_THEME_MODE = "gitpush_theme_mode"
        private const val KEY_LAST_REPO = "gitpush_last_repo"
        private const val KEY_LAST_BRANCH = "gitpush_last_branch"
        private const val KEY_HISTORY = "gitpush_commit_history"
        private const val KEY_CLIENT_ID = "gitpush_oauth_client_id"
        private const val KEY_SETTINGS = "gitpush_app_settings"
        private const val KEY_LAST_ACTIVE = "gitpush_last_active_ms"

        val defaultShortcuts = listOf(
            "Repo kökü", "lib/", "lib/screens/", "lib/models/", "lib/services/",
            "lib/widgets/", "assets/", ".github/workflows/", "android/app/",
        )
    }

    private suspend fun <T> io(block: () -> T): T = withContext(Dispatchers.IO) { block() }

    // ── Token / kullanıcı ──
    suspend fun saveToken(token: String) = io { secure.write(KEY_TOKEN, token) }
    suspend fun getToken(): String? = io { secure.read(KEY_TOKEN) }

    suspend fun clearAuth() = io {
        secure.delete(KEY_TOKEN)
        prefs.edit().remove(KEY_USERNAME).apply()
    }

    suspend fun saveClientId(id: String) = io { prefs.edit().putString(KEY_CLIENT_ID, id).apply() }
    suspend fun getClientId(): String? = io { prefs.getString(KEY_CLIENT_ID, null) }
    suspend fun clearClientId() = io { prefs.edit().remove(KEY_CLIENT_ID).apply() }

    /** Çıkışta token, yazar bilgileri, son repo/dal ve geçmiş tamamen silinir. */
    suspend fun clearAllUserData() = io {
        secure.delete(KEY_TOKEN)
        prefs.edit()
            .remove(KEY_USERNAME).remove(KEY_AUTHOR_NAME).remove(KEY_AUTHOR_EMAIL)
            .remove(KEY_LAST_REPO).remove(KEY_LAST_BRANCH).remove(KEY_HISTORY)
            .apply()
    }

    suspend fun saveUserInfo(username: String, name: String? = null, email: String? = null) = io {
        val e = prefs.edit().putString(KEY_USERNAME, username)
        if (name != null) e.putString(KEY_AUTHOR_NAME, name)
        if (email != null) e.putString(KEY_AUTHOR_EMAIL, email)
        e.apply()
    }

    class UserInfo(val username: String?, val name: String?, val email: String?)

    suspend fun getUserInfo() = io {
        UserInfo(
            prefs.getString(KEY_USERNAME, null),
            prefs.getString(KEY_AUTHOR_NAME, null),
            prefs.getString(KEY_AUTHOR_EMAIL, null),
        )
    }

    // ── Ayarlar ──
    suspend fun getAppSettings(): AppSettings = io { AppSettings.fromJson(prefs.getString(KEY_SETTINGS, null)) }
    suspend fun saveAppSettings(s: AppSettings) = io { prefs.edit().putString(KEY_SETTINGS, s.toJson()).apply() }

    // ── Oturum aktifliği (otomatik oturum kapatma) ──
    suspend fun getLastActive(): Long? = io {
        if (prefs.contains(KEY_LAST_ACTIVE)) prefs.getLong(KEY_LAST_ACTIVE, 0L) else null
    }

    suspend fun touchLastActive(at: Long = System.currentTimeMillis()) =
        io { prefs.edit().putLong(KEY_LAST_ACTIVE, at).apply() }

    // ── Son repo / dal ──
    suspend fun clearLastRepoAndBranch() = io {
        prefs.edit().remove(KEY_LAST_REPO).remove(KEY_LAST_BRANCH).apply()
    }

    suspend fun saveLastRepoAndBranch(repoFullName: String, branch: String) = io {
        val settings = AppSettings.fromJson(prefs.getString(KEY_SETTINGS, null))
        if (!settings.rememberLastRepo) {
            prefs.edit().remove(KEY_LAST_REPO).remove(KEY_LAST_BRANCH).apply()
        } else {
            prefs.edit().putString(KEY_LAST_REPO, repoFullName).putString(KEY_LAST_BRANCH, branch).apply()
        }
    }

    suspend fun getLastRepoAndBranch(): Pair<String?, String?> = io {
        prefs.getString(KEY_LAST_REPO, null) to prefs.getString(KEY_LAST_BRANCH, null)
    }

    // ── Tema ──
    suspend fun saveThemeMode(mode: String) = io { prefs.edit().putString(KEY_THEME_MODE, mode).apply() }
    suspend fun getThemeMode(): String = io { prefs.getString(KEY_THEME_MODE, null) ?: "system" }

    // ── Kısayollar ──
    private fun readStringList(key: String): List<String>? {
        val raw = prefs.getString(key, null) ?: return null
        return parseJson(raw).asArr?.mapNotNull { it.asStr }
    }

    private fun writeStringList(key: String, list: List<String>) {
        prefs.edit().putString(key, JsonArray(list.map { JsonPrimitive(it) }).toString()).apply()
    }

    suspend fun getShortcuts(): List<String> = io { readStringList(KEY_SHORTCUTS) ?: defaultShortcuts }
    suspend fun saveShortcuts(list: List<String>) = io { writeStringList(KEY_SHORTCUTS, list) }
    suspend fun resetShortcuts() = io { prefs.edit().remove(KEY_SHORTCUTS).apply() }

    suspend fun addShortcut(raw: String): Boolean {
        val value = raw.trim()
        if (value.isEmpty() || value.length > 120) return false
        val list = getShortcuts()
        if (list.any { it.equals(value, ignoreCase = true) }) return false
        saveShortcuts(list + value)
        return true
    }

    // ── Gönderim geçmişi (yalnızca cihazda) ──
    suspend fun getHistory(): List<HistoryItem> = io {
        (readStringList(KEY_HISTORY) ?: emptyList()).mapNotNull { HistoryItem.fromJson(it) }
    }

    suspend fun addHistoryItem(item: HistoryItem) = io {
        val list = (readStringList(KEY_HISTORY) ?: emptyList()).toMutableList()
        list.add(0, item.toJsonObject().toString())
        val limit = AppSettings.fromJson(prefs.getString(KEY_SETTINGS, null)).historyLimit
        while (list.size > limit) list.removeAt(list.size - 1)
        writeStringList(KEY_HISTORY, list)
    }

    suspend fun clearHistory() = io { prefs.edit().remove(KEY_HISTORY).apply() }
}
