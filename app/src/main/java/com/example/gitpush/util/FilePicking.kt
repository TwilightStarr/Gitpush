package com.example.gitpush.util

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import kotlin.coroutines.coroutineContext

class PickedFile(val uri: String, val name: String, val size: Long, val bytes: ByteArray)

/** Sistem dosya seçicisinden dönen Uri'yi okur. Sınırı aşan dosya için null döner (küçük dosyalar içindir). */
suspend fun readPickedFile(context: Context, uri: Uri, maxBytes: Long = 100L * 1024 * 1024): PickedFile? =
    withContext(Dispatchers.IO) {
        val (name, size) = queryNameAndSize(context, uri)
        if (size > maxBytes) return@withContext null
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@withContext null
        if (bytes.size > maxBytes) return@withContext null
        PickedFile(uri.toString(), name, bytes.size.toLong(), bytes)
    }

/** (ad, bayt) — boyut bilinmiyorsa -1. Engelleyici çağrıdır; IO iş parçacığında kullanın. */
fun queryNameAndSize(context: Context, uri: Uri): Pair<String, Long> {
    var name = "dosya"
    var size = -1L
    context.contentResolver.query(uri, null, null, null, null)?.use { c ->
        val ni = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
        val si = c.getColumnIndex(OpenableColumns.SIZE)
        if (c.moveToFirst()) {
            if (ni >= 0) name = c.getString(ni) ?: name
            if (si >= 0 && !c.isNull(si)) size = c.getLong(si)
        }
    }
    return name to size
}

/** Seçilen dosya: küçükse bellekte ([bytes]), büyükse diskte ([file]). */
class PickedSource(val uri: String, val name: String, val size: Long, val bytes: ByteArray?, val file: File?)

/** Uri içeriğini akış olarak [dest] dosyasına kopyalar; kopyalanan bayt sayısını döndürür. RAM kullanımı sabittir. */
suspend fun spoolUriToFile(
    context: Context,
    uri: Uri,
    dest: File,
    expectedSize: Long = -1L,
    onProgress: ((Long) -> Unit)? = null,
): Long = withContext(Dispatchers.IO) {
    dest.parentFile?.let { dir ->
        if (expectedSize >= 0 && dir.usableSpace < expectedSize + Spool.FREE_SPACE_MARGIN) {
            throw IOException("Cihazda yeterli boş alan yok (${formatBytes(expectedSize)} gerekli).")
        }
    }
    var total = 0L
    try {
        val input = context.contentResolver.openInputStream(uri) ?: throw IOException("Dosya açılamadı.")
        input.use { ins ->
            dest.outputStream().use { out ->
                val buf = ByteArray(STREAM_BUFFER)
                var lastReport = 0L
                while (true) {
                    val n = ins.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    total += n
                    if (total - lastReport >= 4L * 1024 * 1024) {
                        lastReport = total
                        coroutineContext.ensureActive()
                        onProgress?.invoke(total)
                    }
                }
                out.flush()
            }
        }
        if (expectedSize > 0 && total != expectedSize) {
            throw IOException("Dosya eksik okundu (${formatBytes(total)} / ${formatBytes(expectedSize)}).")
        }
        onProgress?.invoke(total)
        total
    } catch (e: Throwable) {
        dest.delete()
        throw e
    }
}

/**
 * Dosyayı seçer: [inMemoryLimit] altındaysa belleğe okur, üstündeyse [spoolDir] altına akışla kopyalar.
 * [maxBytes] üstündeki dosyalar için null döner. Okunamayan dosya için IOException fırlatır.
 */
suspend fun readOrSpoolPickedFile(
    context: Context,
    uri: Uri,
    spoolDir: File,
    maxBytes: Long,
    inMemoryLimit: Long = 4L * 1024 * 1024,
): PickedSource? {
    val (name, declared) = withContext(Dispatchers.IO) { queryNameAndSize(context, uri) }
    if (declared > maxBytes) return null
    if (declared in 0..inMemoryLimit) {
        val small = readPickedFile(context, uri, maxBytes) ?: return null
        return PickedSource(small.uri, small.name, small.size, small.bytes, null)
    }
    val dest = File(spoolDir, "f${System.nanoTime()}.bin")
    val copied = spoolUriToFile(context, uri, dest, declared)
    if (copied > maxBytes) { dest.delete(); return null }
    return PickedSource(uri.toString(), name, copied, null, dest)
}
