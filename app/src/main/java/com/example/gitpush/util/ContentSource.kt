package com.example.gitpush.util

import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream

/**
 * Bir dosyanın içeriği: bellekte (küçük dosyalar) ya da diskte (büyük dosyalar).
 * Büyük içerikler hiçbir zaman tamamen belleğe alınmaz; [open] ile akış olarak okunur.
 */
interface ContentSource {
    val size: Long

    /** Her çağrıda içeriğin başından başlayan yeni bir akış döndürür (yeniden deneme için güvenli). */
    fun open(): InputStream
}

class BytesSource(private val bytes: ByteArray) : ContentSource {
    override val size: Long get() = bytes.size.toLong()
    override fun open(): InputStream = ByteArrayInputStream(bytes)
}

class FileSource(val file: File) : ContentSource {
    override val size: Long get() = file.length()
    override fun open(): InputStream = file.inputStream().buffered(STREAM_BUFFER)
}

const val STREAM_BUFFER = 128 * 1024

/** İçeriği belleğe okur; [limit] aşılırsa IOException (yanlışlıkla büyük dosyayı RAM'e almamak için). */
fun ContentSource.readSmall(limit: Long): ByteArray {
    if (size > limit) throw IOException("İçerik belleğe okunamayacak kadar büyük ($size bayt).")
    return open().use { it.readBytes() }
}
