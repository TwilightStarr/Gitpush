package com.example.gitpush.service

import android.util.Base64
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.MessageDigest
import java.security.SecureRandom

class PinVerifyResult(val ok: Boolean, val lockedForMs: Long = 0, val failedAttempts: Int = 0) {
    val isLockedOut get() = lockedForMs > 0
}

/**
 * Uygulama kilidi: 6 haneli PIN. Düz metin saklanmaz; rastgele tuz + 20.000 tur SHA-256 karması
 * Keystore destekli depolamada durur. 5 hatadan sonra bekleme (30 sn → 32 dk) artar ve kalıcıdır.
 */
class AppLockService(
    private val store: SecureStore,
    private val clock: () -> Long = { System.currentTimeMillis() },
    private val random: SecureRandom = SecureRandom(),
) {
    companion object {
        const val PIN_LENGTH = 6
        const val HASH_ROUNDS = 20000
        const val FREE_ATTEMPTS = 5
        private const val K_SALT = "gitpush_pin_salt"
        private const val K_HASH = "gitpush_pin_hash"
        private const val K_FAILS = "gitpush_pin_fails"
        private const val K_UNTIL = "gitpush_pin_locked_until"

        fun isValidPin(pin: String) = Regex("^\\d{$PIN_LENGTH}$").matches(pin)

        /** Tekrar eden (000000) veya ardışık (123456) PIN'ler zayıftır. */
        fun isWeakPin(pin: String): Boolean {
            if (!isValidPin(pin)) return true
            if (pin.toSet().size == 1) return true
            val sequences = listOf(
                "012345", "123456", "234567", "345678", "456789",
                "987654", "876543", "765432", "654321", "543210",
            )
            return sequences.contains(pin)
        }

        /** Hatalı deneme sayısına göre bekleme (ms). */
        fun lockoutFor(failedAttempts: Int): Long {
            if (failedAttempts < FREE_ATTEMPTS) return 0
            val step = minOf(failedAttempts - FREE_ATTEMPTS, 6)
            return 30_000L * (1 shl step)
        }

        fun hashPin(pin: String, salt: ByteArray, rounds: Int = HASH_ROUNDS): String {
            val md = MessageDigest.getInstance("SHA-256")
            val pinBytes = pin.toByteArray(Charsets.UTF_8)
            var digest = md.digest(salt + pinBytes)
            repeat(rounds) { digest = md.digest(digest + salt + pinBytes) }
            return Base64.encodeToString(digest, Base64.NO_WRAP)
        }

        fun constantTimeEquals(a: String, b: String): Boolean {
            val x = a.toByteArray(Charsets.UTF_8)
            val y = b.toByteArray(Charsets.UTF_8)
            var diff = x.size xor y.size
            val n = minOf(x.size, y.size)
            for (i in 0 until n) diff = diff or (x[i].toInt() xor y[i].toInt())
            return diff == 0
        }
    }

    private suspend fun <T> io(block: () -> T): T = withContext(Dispatchers.IO) { block() }

    suspend fun hasPin(): Boolean = try {
        io { store.read(K_HASH).let { !it.isNullOrEmpty() } }
    } catch (_: Exception) {
        false
    }

    suspend fun setPin(pin: String) {
        require(isValidPin(pin)) { "PIN $PIN_LENGTH haneli olmalıdır." }
        val salt = ByteArray(16).also { random.nextBytes(it) }
        io {
            store.write(K_SALT, Base64.encodeToString(salt, Base64.NO_WRAP))
            store.write(K_HASH, hashPin(pin, salt))
        }
        resetFailures()
    }

    suspend fun lockoutRemaining(): Long = try {
        io {
            val ms = store.read(K_UNTIL)?.toLongOrNull()
            if (ms == null) 0L else maxOf(0L, ms - clock())
        }
    } catch (_: Exception) {
        0L
    }

    suspend fun verify(pin: String): PinVerifyResult {
        val remaining = lockoutRemaining()
        if (remaining > 0) return PinVerifyResult(false, remaining, readFails())
        try {
            val saltB64 = io { store.read(K_SALT) }
            val stored = io { store.read(K_HASH) }
            if (saltB64 == null || stored == null) return PinVerifyResult(false)
            val computed = withContext(Dispatchers.Default) { hashPin(pin, Base64.decode(saltB64, Base64.DEFAULT)) }
            if (constantTimeEquals(computed, stored)) {
                resetFailures()
                return PinVerifyResult(true)
            }
        } catch (_: Exception) {
            // okuma hatası: yanlış PIN gibi davran
        }
        val fails = readFails() + 1
        io { store.write(K_FAILS, fails.toString()) }
        val wait = lockoutFor(fails)
        if (wait > 0) io { store.write(K_UNTIL, (clock() + wait).toString()) }
        return PinVerifyResult(false, wait, fails)
    }

    private suspend fun readFails(): Int = try {
        io { store.read(K_FAILS)?.toIntOrNull() ?: 0 }
    } catch (_: Exception) {
        0
    }

    private suspend fun resetFailures() = io {
        store.delete(K_FAILS)
        store.delete(K_UNTIL)
    }

    /** PIN'i ve sayaçları tamamen siler. */
    suspend fun clear() {
        io {
            store.delete(K_SALT)
            store.delete(K_HASH)
        }
        resetFailures()
    }
}
