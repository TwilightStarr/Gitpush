package com.example.gitpush.service

import com.example.gitpush.BuildConfig
import com.example.gitpush.util.asInt
import com.example.gitpush.util.asObj
import com.example.gitpush.util.asStr
import com.example.gitpush.util.parseJson
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import java.io.InterruptedIOException
import java.net.URI

class DeviceCodeInfo(
    val deviceCode: String,
    val userCode: String,
    val verificationUri: String,
    val expiresIn: Int,
    val interval: Int,
)

class DeviceFlowException(override val message: String) : Exception(message)

/**
 * GitHub OAuth Device Flow. Yalnızca herkese açık client_id kullanılır; client_secret gerekmez
 * ve istemciye asla konmamalıdır.
 */
class GitHubDeviceFlow(
    clientIdOverride: String? = null,
    private val transport: HttpTransport = OkHttpTransport(),
    private val sleep: suspend (Long) -> Unit = { delay(it) },
) {
    private val clientId: String = clientIdOverride ?: buildClientId

    companion object {
        /** Derleme zamanı Client ID (-PGITHUB_CLIENT_ID). Boşsa Device Flow kullanılamaz. */
        val buildClientId: String get() = BuildConfig.GITHUB_CLIENT_ID

        const val SCOPE_ALL = "repo workflow"
        const val SCOPE_PUBLIC = "public_repo workflow"
        const val SCOPE = SCOPE_ALL

        private const val DEVICE_CODE_URL = "https://github.com/login/device/code"
        private const val TOKEN_URL = "https://github.com/login/oauth/access_token"
        private const val GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"
        private val clientIdRe = Regex("^[A-Za-z0-9._-]{10,40}$")

        fun isAllowedScope(s: String) = s == SCOPE_ALL || s == SCOPE_PUBLIC
        fun isValidClientId(id: String) = clientIdRe.matches(id)
        val isConfigured: Boolean get() = isValidClientId(buildClientId)

        /** Yalnızca https://github.com doğrulama adresi kabul edilir. */
        fun isTrustedVerificationUri(raw: String): Boolean =
            try {
                val uri = URI(raw)
                uri.scheme == "https" && uri.host == "github.com"
            } catch (_: Exception) {
                false
            }
    }

    private suspend fun post(url: String, form: Map<String, String>): kotlinx.serialization.json.JsonObject {
        val res = transport.postForm(
            url,
            mapOf("Accept" to "application/json", "User-Agent" to "Gitpush"),
            form,
            20_000,
        )
        return parseJson(res.body).asObj
            ?: throw DeviceFlowException("GitHub beklenmeyen bir yanıt döndürdü (${res.code}).")
    }

    private fun describeError(code: String): String = when (code) {
        "device_flow_disabled" ->
            "OAuth App ayarlarında \"Enable Device Flow\" kapalı. GitHub → Developer settings → OAuth Apps bölümünden açın."
        "incorrect_client_credentials" ->
            "Client ID geçersiz. Girdiğiniz veya derlemedeki GITHUB_CLIENT_ID değerini kontrol edin."
        "expired_token" -> "Doğrulama kodunun süresi doldu. Lütfen tekrar deneyin."
        "access_denied" -> "GitHub üzerinde yetkilendirme reddedildi."
        "unsupported_grant_type", "incorrect_device_code" -> "Doğrulama oturumu geçersiz. Lütfen tekrar deneyin."
        else -> "GitHub girişi başarısız: $code"
    }

    suspend fun start(scopeOverride: String = SCOPE): DeviceCodeInfo {
        if (!isValidClientId(clientId)) throw DeviceFlowException("GitHub ile giriş için geçerli bir Client ID gerekli.")
        if (!isAllowedScope(scopeOverride)) throw DeviceFlowException("Geçersiz yetki kapsamı.")
        try {
            val json = post(DEVICE_CODE_URL, mapOf("client_id" to clientId, "scope" to scopeOverride))
            val error = json["error"].asStr
            if (error != null) throw DeviceFlowException(describeError(error))

            val deviceCode = json["device_code"].asStr
            val userCode = json["user_code"].asStr
            val uri = json["verification_uri"].asStr
            if (deviceCode == null || userCode == null || uri == null) {
                throw DeviceFlowException("GitHub yanıtı eksik alanlar içeriyor.")
            }
            if (!isTrustedVerificationUri(uri)) throw DeviceFlowException("Güvenilmeyen doğrulama adresi reddedildi.")
            return DeviceCodeInfo(
                deviceCode = deviceCode,
                userCode = userCode,
                verificationUri = uri,
                expiresIn = json["expires_in"].asInt ?: 900,
                interval = json["interval"].asInt ?: 5,
            )
        } catch (e: DeviceFlowException) {
            throw e
        } catch (e: CancellationException) {
            throw e
        } catch (e: InterruptedIOException) {
            throw DeviceFlowException("GitHub'a bağlanılamadı (zaman aşımı).")
        } catch (e: Exception) {
            throw DeviceFlowException("GitHub'a bağlanılamadı. İnternet bağlantınızı kontrol edin.")
        }
    }

    /**
     * Kullanıcı onaylayana kadar yoklar. Token döner; iptal edilirse null.
     * `slow_down` yanıtında aralık artırılır; süre dolarsa hata fırlatılır.
     */
    suspend fun pollForToken(info: DeviceCodeInfo, isCancelled: () -> Boolean = { false }): String? {
        var interval = if (info.interval < 5) 5 else info.interval
        var waited = 0
        var failures = 0
        while (true) {
            for (i in 0 until interval) {
                if (isCancelled()) return null
                sleep(1000)
            }
            waited += interval
            if (isCancelled()) return null
            if (waited > info.expiresIn) throw DeviceFlowException(describeError("expired_token"))

            val json = try {
                post(
                    TOKEN_URL,
                    mapOf("client_id" to clientId, "device_code" to info.deviceCode, "grant_type" to GRANT_TYPE),
                ).also { failures = 0 }
            } catch (e: DeviceFlowException) {
                throw e
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                if (++failures >= 3) {
                    throw DeviceFlowException("GitHub'a bağlanılamadı. İnternet bağlantınızı kontrol edin.")
                }
                continue
            }

            val token = json["access_token"].asStr
            if (!token.isNullOrEmpty()) return token

            val error = json["error"].asStr
            if (error == "authorization_pending") continue
            if (error == "slow_down") {
                interval = json["interval"].asInt ?: (interval + 5)
                continue
            }
            throw DeviceFlowException(describeError(error ?: "unknown"))
        }
    }
}
