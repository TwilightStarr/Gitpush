package com.example.gitpush.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.example.gitpush.model.AppSettings
import com.example.gitpush.service.AppLockService
import com.example.gitpush.service.PinVerifyResult
import com.example.gitpush.service.StorageService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/** Kilit durumu + uygulama yaşam döngüsü (arka plana gidip dönünce zaman aşımına göre kilitler). */
class AppLockProvider(
    val service: AppLockService,
    private val storage: StorageService,
    private val scope: CoroutineScope,
    private val clock: () -> Long = { System.currentTimeMillis() },
) : DefaultLifecycleObserver {

    var enabled by mutableStateOf(false)

        private set
    var locked by mutableStateOf(false)
        private set

    private var timeoutSeconds = 30
    private var pausedAt: Long? = null
    private var observing = false

    suspend fun init(settings: AppSettings) {
        timeoutSeconds = settings.lockTimeoutSeconds
        enabled = settings.appLockEnabled && service.hasPin()
        locked = enabled // soğuk açılışta kilitli
        if (!observing) {
            ProcessLifecycleOwner.get().lifecycle.addObserver(this)
            observing = true
        }
    }

    suspend fun syncSettings(settings: AppSettings) {
        timeoutSeconds = settings.lockTimeoutSeconds
        val shouldEnable = settings.appLockEnabled && service.hasPin()
        if (shouldEnable != enabled) {
            enabled = shouldEnable
            if (!enabled) locked = false
        }
    }

    suspend fun tryUnlock(pin: String): PinVerifyResult {
        val r = service.verify(pin)
        if (r.ok) {
            locked = false
            pausedAt = null
        }
        return r
    }

    fun lockNow() {
        if (!enabled) return
        locked = true
    }

    /** "PIN'imi unuttum": PIN'i siler ve kilidi kaldırır. */
    suspend fun wipe() {
        service.clear()
        enabled = false
        locked = false
        pausedAt = null
    }

    override fun onStop(owner: LifecycleOwner) {
        if (pausedAt == null) pausedAt = clock()
        scope.launch { try { storage.touchLastActive(clock()) } catch (_: Exception) { } }
    }

    override fun onStart(owner: LifecycleOwner) {
        val since = pausedAt
        pausedAt = null
        if (enabled && !locked && since != null) {
            val awaySec = (clock() - since) / 1000
            if (awaySec >= timeoutSeconds) locked = true
        }
    }
}
