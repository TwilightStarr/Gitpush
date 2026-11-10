package com.example.gitpush

import com.example.gitpush.model.SecretRules
import com.example.gitpush.util.SealedBox
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Base64

/**
 * SealedBox, libsodium'un crypto_box_seal_open fonksiyonuyla doğrulanmış bilinen-cevap vektörleriyle sınanır.
 * Vektörler sabit geçici anahtarla üretildi; böylece çıktı deterministiktir.
 */
class SecretsTest {
    private fun hex(s: String) = ByteArray(s.length / 2) { s.substring(2 * it, 2 * it + 2).toInt(16).toByte() }
    private fun b64(s: String) = Base64.getDecoder().decode(s)
    private fun toHex(b: ByteArray) = b.joinToString("") { "%02x".format(it.toInt() and 0xff) }

    @Test fun x25519Rfc7748Vector() {
        val k = hex("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4")
        val u = hex("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")
        assertEquals("c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552", toHex(SealedBox.x25519(k, u)))
    }

    @Test fun poly1305Rfc8439Vector() {
        val key = hex("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b")
        val tag = SealedBox.poly1305(key, "Cryptographic Forum Research Group".toByteArray(Charsets.US_ASCII))
        assertEquals("a8061dc1305136c6c22b8baf0c0127a9", toHex(tag))
    }

    @Test fun blake2bVectors() {
        assertEquals("56a17e38cc371a46b12c32f18e0c61de2a84e9c2555b114e", toHex(SealedBox.blake2b("abc".toByteArray(), 24)))
        assertEquals("ab3b5331a7135ed50d0f182d026e60abdb3646fd51bcf8a3", toHex(SealedBox.blake2b(ByteArray(0), 24)))
    }

    @Test fun sealedBoxKnownAnswerShortMessage() {
        val rpk = b64("B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw=")
        val esk = hex("65666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f8081828384")
        val sealed = SealedBox.seal("s3cr3t-value çş".toByteArray(Charsets.UTF_8), rpk, esk)
        assertEquals(
            "VxR2nRFr92Q2rnS8eT0sMK0ZA8WaxSc4BcfiaYtBDDZzAHeLS9Xzqz3/qb5OakdiUq1AEDBxsXB7kE7W6bQZNmk=",
            Base64.getEncoder().encodeToString(sealed),
        )
    }

    @Test fun sealedBoxKnownAnswerMultiBlockMessage() {
        val rpk = b64("u1D/noKldM+/gg6X9g+5wUPsdBXPUU+M/Zjv9Z4FlhQ=")
        val esk = ByteArray(32) { ((it * 11 + 5) % 256).toByte() }
        val msg = ByteArray(200) { ((it * 3) % 256).toByte() }
        val expected = b64(
            "FO4OB/NOOhcDDG7s9m03BegNHhU/egyls0XoPOnWJkPC2iuqGRIkEzrjmkhXYlj9hAAWBBRrKsB8hDTehwesEEkpltWS2F8eWoUQK//EnNGSuHZ2" +
                "IrR1f0DvOquv/pPCoGYqN20KkAtBbU1ibHURQ/bk6NA0Qt6v0D7zzFI589idOV0QeBdNAPdA22SSi1h2PJiW8WgCKm/eJParjPAI/BrN9PF1ug+m" +
                "tdkj5FaiNGgM2cck751apY/YBZyEGXFNjINckB9fvBCD86IOGSvm91zeG5JvW+9GCa189Y7oLDbErZiV4yPMD0q52SrdkcYMEPTCfH9uyDk=",
        )
        assertArrayEquals(expected, SealedBox.seal(msg, rpk, esk))
    }

    @Test fun sealedBoxIsRandomizedAndSized() {
        val rpk = b64("B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9/AsrhtHHw=")
        val a = SealedBox.seal("x".toByteArray(), rpk)
        val b = SealedBox.seal("x".toByteArray(), rpk)
        assertEquals(32 + 16 + 1, a.size)
        assertEquals(false, a.contentEquals(b)) // her seferinde yeni geçici anahtar
    }

    @Test fun secretNameRules() {
        assertNull(SecretRules.validateName("KEY_PASSWORD"))
        assertNull(SecretRules.validateName("key_alias"))
        assertNotNull(SecretRules.validateName(""))
        assertNotNull(SecretRules.validateName("1ABC"))
        assertNotNull(SecretRules.validateName("MY-SECRET"))
        assertNotNull(SecretRules.validateName("HAS SPACE"))
        assertNotNull(SecretRules.validateName("GITHUB_CLIENT_ID"))
        assertNotNull(SecretRules.validateName("github_token"))
        assertEquals("KEY_ALIAS", SecretRules.normalizeName(" key_alias "))
    }

    @Test fun secretValueRules() {
        assertNull(SecretRules.validateValue("abc"))
        assertNotNull(SecretRules.validateValue(""))
        assertNotNull(SecretRules.validateValue("a".repeat(SecretRules.MAX_VALUE_BYTES + 1)))
    }
}
