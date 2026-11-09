package com.example.gitpush.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.gitpush.service.DeviceCodeInfo
import com.example.gitpush.service.DeviceFlowException
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.service.GitHubDeviceFlow
import com.example.gitpush.service.GitHubService
import com.example.gitpush.service.StorageService
import com.example.gitpush.util.asStr
import kotlinx.coroutines.CancellationException

class AuthProvider(private val storage: StorageService, private val github: GitHubService) {
    var isLoading by mutableStateOf(false)
        private set
    var isAuthenticated by mutableStateOf(false)
        private set
    var token: String? = null
        private set
    var username by mutableStateOf<String?>(null)
        private set
    var avatarUrl by mutableStateOf<String?>(null)
        private set
    var authorName by mutableStateOf<String?>(null)
        private set
    var authorEmail by mutableStateOf<String?>(null)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set
    var deviceInfo by mutableStateOf<DeviceCodeInfo?>(null)
        private set

    private var deviceCancelled = false
    private var customClientId by mutableStateOf<String?>(null)

    val isDeviceFlowActive get() = deviceInfo != null

    val effectiveClientId: String
        get() {
            val custom = customClientId
            if (custom != null && GitHubDeviceFlow.isValidClientId(custom)) return custom
            return GitHubDeviceFlow.buildClientId
        }
    val deviceFlowAvailable get() = GitHubDeviceFlow.isValidClientId(effectiveClientId)

    /** Derlemede Client ID verilmediyse kullanıcı uygulama içinden girebilir. */
    val canEditClientId get() = !GitHubDeviceFlow.isConfigured

    suspend fun setClientId(raw: String): Boolean {
        val id = raw.trim()
        if (!GitHubDeviceFlow.isValidClientId(id)) {
            errorMessage = "Client ID biçimi geçersiz. GitHub OAuth App sayfasındaki Client ID'yi aynen yapıştırın."
            return false
        }
        customClientId = id
        errorMessage = null
        storage.saveClientId(id)
        return true
    }

    suspend fun clearClientId() {
        customClientId = null
        storage.clearClientId()
    }

    /** Açılışta kayıtlı token'ı doğrular. 401 ise token silinir. */
    suspend fun checkSavedAuth() {
        isLoading = true
        customClientId = try { storage.getClientId() } catch (_: Exception) { null }
        try {
            val saved = storage.getToken()
            if (!saved.isNullOrEmpty()) {
                token = saved
                val user = github.verifyUser(saved)
                username = user["login"].asStr
                avatarUrl = user["avatar_url"].asStr
                val info = storage.getUserInfo()
                authorName = info.name
                authorEmail = info.email
                isAuthenticated = true
            }
        } catch (e: GitHubApiException) {
            isAuthenticated = false
            token = null
            if (e.statusCode == 401) storage.clearAuth()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Exception) {
            isAuthenticated = false
            token = null
        } finally {
            isLoading = false
        }
    }

    private val tokenRe = Regex("^[\\x21-\\x7E]{1,255}$")

    suspend fun loginWithToken(token: String, authorName: String? = null, authorEmail: String? = null): Boolean {
        isLoading = true
        errorMessage = null
        try {
            val clean = token.trim()
            if (!tokenRe.matches(clean)) {
                errorMessage = "Token geçersiz karakterler içeriyor (boşluk, satır sonu veya özel karakter olamaz)."
                return false
            }
            val user = github.verifyUser(clean)
            username = user["login"].asStr
            avatarUrl = user["avatar_url"].asStr
            this.token = clean
            this.authorName = authorName?.trim()
            this.authorEmail = authorEmail?.trim()
            storage.saveToken(clean)
            storage.saveUserInfo(username ?: "", this.authorName, this.authorEmail)
            isAuthenticated = true
            return true
        } catch (e: GitHubApiException) {
            errorMessage = e.message
            return false
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            errorMessage = "Beklenmeyen hata: $e"
            return false
        } finally {
            isLoading = false
        }
    }

    /** GitHub Device Flow ile giriş. [onCode] kod hazır olunca çağrılır (kopyalama/tarayıcı açma). */
    suspend fun loginWithDeviceFlow(
        authorName: String? = null,
        authorEmail: String? = null,
        onCode: ((DeviceCodeInfo) -> Unit)? = null,
        flow: GitHubDeviceFlow? = null,
        scope: String = GitHubDeviceFlow.SCOPE,
    ): Boolean {
        if (deviceInfo != null) return false
        errorMessage = null
        deviceCancelled = false
        val deviceFlow = flow ?: GitHubDeviceFlow(clientIdOverride = effectiveClientId)
        try {
            val info = deviceFlow.start(scope)
            deviceInfo = info
            onCode?.invoke(info)
            val tok = deviceFlow.pollForToken(info) { deviceCancelled }
            deviceInfo = null
            if (tok == null) return false
            return loginWithToken(tok, authorName, authorEmail)
        } catch (e: DeviceFlowException) {
            deviceInfo = null
            errorMessage = e.message
            return false
        } catch (e: CancellationException) {
            deviceInfo = null
            throw e
        } catch (_: Exception) {
            deviceInfo = null
            errorMessage = "GitHub girişi sırasında beklenmeyen bir hata oluştu."
            return false
        }
    }

    fun cancelDeviceFlow() {
        deviceCancelled = true
        deviceInfo = null
    }

    suspend fun updateAuthorInfo(name: String, email: String) {
        authorName = name.trim()
        authorEmail = email.trim()
        storage.saveUserInfo(username ?: "", authorName, authorEmail)
    }

    suspend fun logout() {
        deviceCancelled = true
        deviceInfo = null
        storage.clearAllUserData()
        isAuthenticated = false
        token = null
        username = null
        avatarUrl = null
        authorName = null
        authorEmail = null
        errorMessage = null
    }
}
