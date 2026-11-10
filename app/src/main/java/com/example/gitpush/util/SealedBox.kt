package com.example.gitpush.util

import java.math.BigInteger
import java.security.SecureRandom

/**
 * libsodium `crypto_box_seal` uyumlu şifreleme (GitHub Actions secret'ları bu biçimi ister).
 *
 *   çıktı = epk(32) || Poly1305 etiketi(16) || XSalsa20 ile şifrelenmiş mesaj
 *   nonce = BLAKE2b-24(epk || alıcı_açık_anahtar)
 *   anahtar = HSalsa20(X25519(esk, alıcı_açık_anahtar), 0^16)
 *
 * Harici bağımlılık gerektirmez. Yalnızca GİZLİ DEĞERİ TEK SEFERLİK şifrelemek için tasarlanmıştır:
 * esk her çağrıda rastgele üretilir, bu yüzden zamanlama saldırıları bu kullanımda geçerli değildir.
 * Doğruluk, libsodium'a karşı üretilmiş bilinen-cevap vektörüyle LogicTest'te sınanır.
 */
object SealedBox {
    private val random = SecureRandom()

    fun seal(
        message: ByteArray,
        recipientPublicKey: ByteArray,
        ephemeralSecret: ByteArray = ByteArray(32).also { random.nextBytes(it) },
    ): ByteArray {
        require(recipientPublicKey.size == 32) { "Açık anahtar 32 bayt olmalı." }
        require(ephemeralSecret.size == 32) { "Geçici gizli anahtar 32 bayt olmalı." }

        val epk = x25519(ephemeralSecret, BASE_POINT)
        val nonce = blake2b(epk + recipientPublicKey, 24)
        val shared = x25519(ephemeralSecret, recipientPublicKey)
        require(shared.any { it.toInt() != 0 }) { "Geçersiz açık anahtar." }

        val boxKey = hsalsa20(shared, ByteArray(16))
        val subKey = hsalsa20(boxKey, nonce.copyOfRange(0, 16))
        val nonceTail = nonce.copyOfRange(16, 24)
        val stream = salsa20Stream(subKey, nonceTail, 32 + message.size)

        val cipher = ByteArray(message.size) { i ->
            (message[i].toInt() xor stream[32 + i].toInt()).toByte()
        }
        val tag = poly1305(stream.copyOfRange(0, 32), cipher)
        return epk + tag + cipher
    }

    // ───────────────────────── X25519 ─────────────────────────

    private val BASE_POINT = ByteArray(32).also { it[0] = 9 }
    private val P: BigInteger = BigInteger.ONE.shiftLeft(255).subtract(BigInteger.valueOf(19))
    private val A24: BigInteger = BigInteger.valueOf(121665)
    private val TWO: BigInteger = BigInteger.valueOf(2)

    internal fun x25519(scalar: ByteArray, u: ByteArray): ByteArray {
        val kb = scalar.copyOf()
        kb[0] = (kb[0].toInt() and 248).toByte()
        kb[31] = ((kb[31].toInt() and 127) or 64).toByte()
        val k = leToBig(kb)

        val ub = u.copyOf()
        ub[31] = (ub[31].toInt() and 127).toByte()
        val x1 = leToBig(ub).mod(P)

        var x2 = BigInteger.ONE
        var z2 = BigInteger.ZERO
        var x3 = x1
        var z3 = BigInteger.ONE
        var swap = 0
        for (t in 254 downTo 0) {
            val bit = if (k.testBit(t)) 1 else 0
            swap = swap xor bit
            if (swap == 1) {
                val tx = x2; x2 = x3; x3 = tx
                val tz = z2; z2 = z3; z3 = tz
            }
            swap = bit

            val a = x2.add(z2).mod(P)
            val aa = a.multiply(a).mod(P)
            val b = x2.subtract(z2).mod(P)
            val bb = b.multiply(b).mod(P)
            val e = aa.subtract(bb).mod(P)
            val c = x3.add(z3).mod(P)
            val d = x3.subtract(z3).mod(P)
            val da = d.multiply(a).mod(P)
            val cb = c.multiply(b).mod(P)
            x3 = da.add(cb).mod(P).modPow(TWO, P)
            z3 = x1.multiply(da.subtract(cb).mod(P).modPow(TWO, P)).mod(P)
            x2 = aa.multiply(bb).mod(P)
            z2 = e.multiply(aa.add(A24.multiply(e)).mod(P)).mod(P)
        }
        if (swap == 1) {
            val tx = x2; x2 = x3; x3 = tx
            val tz = z2; z2 = z3; z3 = tz
        }
        val result = x2.multiply(z2.modPow(P.subtract(TWO), P)).mod(P)
        return bigToLe(result, 32)
    }

    private fun leToBig(b: ByteArray): BigInteger {
        val be = ByteArray(b.size) { b[b.size - 1 - it] }
        return BigInteger(1, be)
    }

    private fun bigToLe(v: BigInteger, size: Int): ByteArray {
        val be = v.toByteArray() // büyük-uçlu, başta işaret baytı olabilir
        val out = ByteArray(size)
        var i = 0
        while (i < size && i < be.size) {
            out[i] = be[be.size - 1 - i]
            i++
        }
        return out
    }

    // ───────────────────────── Salsa20 ailesi ─────────────────────────

    private val SIGMA = "expand 32-byte k".toByteArray(Charsets.US_ASCII)

    private fun le32(b: ByteArray, o: Int): Int =
        (b[o].toInt() and 0xff) or
            ((b[o + 1].toInt() and 0xff) shl 8) or
            ((b[o + 2].toInt() and 0xff) shl 16) or
            ((b[o + 3].toInt() and 0xff) shl 24)

    private fun putLe32(out: ByteArray, o: Int, v: Int) {
        out[o] = v.toByte()
        out[o + 1] = (v ushr 8).toByte()
        out[o + 2] = (v ushr 16).toByte()
        out[o + 3] = (v ushr 24).toByte()
    }

    private fun initState(key: ByteArray, in16: ByteArray): IntArray {
        val s = IntArray(16)
        s[0] = le32(SIGMA, 0)
        s[5] = le32(SIGMA, 4)
        s[10] = le32(SIGMA, 8)
        s[15] = le32(SIGMA, 12)
        for (i in 0 until 4) {
            s[1 + i] = le32(key, 4 * i)
            s[11 + i] = le32(key, 16 + 4 * i)
            s[6 + i] = le32(in16, 4 * i)
        }
        return s
    }

    private fun quarter(y: IntArray, a: Int, b: Int, c: Int, d: Int) {
        y[b] = y[b] xor (y[a] + y[d]).rotateLeft(7)
        y[c] = y[c] xor (y[b] + y[a]).rotateLeft(9)
        y[d] = y[d] xor (y[c] + y[b]).rotateLeft(13)
        y[a] = y[a] xor (y[d] + y[c]).rotateLeft(18)
    }

    private fun twentyRounds(y: IntArray) {
        for (round in 0 until 10) {
            quarter(y, 0, 4, 8, 12); quarter(y, 5, 9, 13, 1); quarter(y, 10, 14, 2, 6); quarter(y, 15, 3, 7, 11)
            quarter(y, 0, 1, 2, 3); quarter(y, 5, 6, 7, 4); quarter(y, 10, 11, 8, 9); quarter(y, 15, 12, 13, 14)
        }
    }

    internal fun hsalsa20(key: ByteArray, in16: ByteArray): ByteArray {
        val y = initState(key, in16)
        twentyRounds(y)
        val idx = intArrayOf(0, 5, 10, 15, 6, 7, 8, 9)
        val out = ByteArray(32)
        for (i in 0 until 8) putLe32(out, 4 * i, y[idx[i]])
        return out
    }

    private fun salsa20Block(key: ByteArray, nonce8: ByteArray, counter: Long): ByteArray {
        val in16 = ByteArray(16)
        System.arraycopy(nonce8, 0, in16, 0, 8)
        for (i in 0 until 8) in16[8 + i] = (counter ushr (8 * i)).toByte()
        val x = initState(key, in16)
        val y = x.copyOf()
        twentyRounds(y)
        val out = ByteArray(64)
        for (i in 0 until 16) putLe32(out, 4 * i, y[i] + x[i])
        return out
    }

    private fun salsa20Stream(key: ByteArray, nonce8: ByteArray, length: Int): ByteArray {
        val out = ByteArray(length)
        var counter = 0L
        var pos = 0
        while (pos < length) {
            val block = salsa20Block(key, nonce8, counter++)
            val n = minOf(64, length - pos)
            System.arraycopy(block, 0, out, pos, n)
            pos += n
        }
        return out
    }

    // ───────────────────────── Poly1305 ─────────────────────────

    private val POLY_P: BigInteger = BigInteger.ONE.shiftLeft(130).subtract(BigInteger.valueOf(5))
    private val POLY_R_MASK = BigInteger("0ffffffc0ffffffc0ffffffc0fffffff", 16)
    private val MOD_2_128: BigInteger = BigInteger.ONE.shiftLeft(128)

    internal fun poly1305(key32: ByteArray, msg: ByteArray): ByteArray {
        val r = leToBig(key32.copyOfRange(0, 16)).and(POLY_R_MASK)
        val s = leToBig(key32.copyOfRange(16, 32))
        var acc = BigInteger.ZERO
        var off = 0
        while (off < msg.size) {
            val n = minOf(16, msg.size - off)
            val blk = ByteArray(n + 1)
            System.arraycopy(msg, off, blk, 0, n)
            blk[n] = 1
            acc = acc.add(leToBig(blk)).multiply(r).mod(POLY_P)
            off += n
        }
        return bigToLe(acc.add(s).mod(MOD_2_128), 16)
    }

    // ───────────────────────── BLAKE2b ─────────────────────────

    private val B2_IV = longArrayOf(
        0x6a09e667f3bcc908UL.toLong(), 0xbb67ae8584caa73bUL.toLong(),
        0x3c6ef372fe94f82bUL.toLong(), 0xa54ff53a5f1d36f1UL.toLong(),
        0x510e527fade682d1UL.toLong(), 0x9b05688c2b3e6c1fUL.toLong(),
        0x1f83d9abfb41bd6bUL.toLong(), 0x5be0cd19137e2179UL.toLong(),
    )

    private val B2_SIGMA = intArrayOf(
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
        14, 10, 4, 8, 9, 15, 13, 6, 1, 12, 0, 2, 11, 7, 5, 3,
        11, 8, 12, 0, 5, 2, 15, 13, 10, 14, 3, 6, 7, 1, 9, 4,
        7, 9, 3, 1, 13, 12, 11, 14, 2, 6, 5, 10, 4, 0, 15, 8,
        9, 0, 5, 7, 2, 4, 10, 15, 14, 1, 11, 12, 6, 8, 3, 13,
        2, 12, 6, 10, 0, 11, 8, 3, 4, 13, 7, 5, 15, 14, 1, 9,
        12, 5, 1, 15, 14, 13, 4, 10, 0, 7, 6, 3, 9, 2, 8, 11,
        13, 11, 7, 14, 12, 1, 3, 9, 5, 0, 15, 4, 8, 6, 2, 10,
        6, 15, 14, 9, 11, 3, 0, 8, 12, 2, 13, 7, 1, 4, 10, 5,
        10, 2, 8, 4, 7, 6, 1, 5, 15, 11, 9, 14, 3, 12, 13, 0,
    )

    private fun b2Mix(v: LongArray, a: Int, b: Int, c: Int, d: Int, x: Long, y: Long) {
        v[a] = v[a] + v[b] + x
        v[d] = (v[d] xor v[a]).rotateRight(32)
        v[c] = v[c] + v[d]
        v[b] = (v[b] xor v[c]).rotateRight(24)
        v[a] = v[a] + v[b] + y
        v[d] = (v[d] xor v[a]).rotateRight(16)
        v[c] = v[c] + v[d]
        v[b] = (v[b] xor v[c]).rotateRight(63)
    }

    private fun b2Compress(h: LongArray, block: ByteArray, t: Long, last: Boolean) {
        val m = LongArray(16)
        for (i in 0 until 16) {
            var w = 0L
            for (j in 7 downTo 0) w = (w shl 8) or (block[8 * i + j].toLong() and 0xff)
            m[i] = w
        }
        val v = LongArray(16)
        for (i in 0 until 8) {
            v[i] = h[i]
            v[i + 8] = B2_IV[i]
        }
        v[12] = v[12] xor t
        if (last) v[14] = v[14].inv()
        for (r in 0 until 12) {
            val o = (r % 10) * 16
            val s = B2_SIGMA
            b2Mix(v, 0, 4, 8, 12, m[s[o]], m[s[o + 1]])
            b2Mix(v, 1, 5, 9, 13, m[s[o + 2]], m[s[o + 3]])
            b2Mix(v, 2, 6, 10, 14, m[s[o + 4]], m[s[o + 5]])
            b2Mix(v, 3, 7, 11, 15, m[s[o + 6]], m[s[o + 7]])
            b2Mix(v, 0, 5, 10, 15, m[s[o + 8]], m[s[o + 9]])
            b2Mix(v, 1, 6, 11, 12, m[s[o + 10]], m[s[o + 11]])
            b2Mix(v, 2, 7, 8, 13, m[s[o + 12]], m[s[o + 13]])
            b2Mix(v, 3, 4, 9, 14, m[s[o + 14]], m[s[o + 15]])
        }
        for (i in 0 until 8) h[i] = h[i] xor v[i] xor v[i + 8]
    }

    internal fun blake2b(data: ByteArray, outLen: Int): ByteArray {
        require(outLen in 1..64)
        val h = B2_IV.copyOf()
        h[0] = h[0] xor 0x01010000L xor outLen.toLong()
        var off = 0
        while (data.size - off > 128) {
            b2Compress(h, data.copyOfRange(off, off + 128), (off + 128).toLong(), false)
            off += 128
        }
        val lastBlock = ByteArray(128)
        System.arraycopy(data, off, lastBlock, 0, data.size - off)
        b2Compress(h, lastBlock, data.size.toLong(), true)
        val out = ByteArray(64)
        for (i in 0 until 8) for (j in 0 until 8) out[8 * i + j] = (h[i] ushr (8 * j)).toByte()
        return out.copyOf(outLen)
    }
}
