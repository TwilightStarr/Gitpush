package com.example.gitpush.util

import android.content.Context
import java.io.File

/**
 * Büyük dosyaların geçici olarak tutulduğu önbellek alanı (cacheDir/spool).
 * Gönderim bitince, ekran kapanınca ve uygulama açılışında temizlenir.
 */
object Spool {
    /** Diskte her zaman bırakılacak güvenlik payı. */
    const val FREE_SPACE_MARGIN = 64L * 1024 * 1024

    private fun root(context: Context) = File(context.applicationContext.cacheDir, "spool")

    /** Yeni, boş bir alt klasör açar. */
    fun newDir(context: Context, kind: String): File {
        val dir = File(root(context), "$kind-${System.nanoTime()}")
        if (!dir.mkdirs() && !dir.isDirectory) throw java.io.IOException("Geçici klasör oluşturulamadı.")
        return dir
    }

    fun delete(dir: File?) {
        if (dir == null) return
        try { dir.deleteRecursively() } catch (_: Exception) { }
    }

    /** Silme büyük olabilir; arayüzü bloklamamak için ayrı iş parçacığında yapılır. */
    fun deleteAsync(dir: File?) {
        if (dir == null) return
        Thread { delete(dir) }.apply { isDaemon = true }.start()
    }

    /** Önceki oturumlardan kalan her şeyi siler. */
    fun clearAll(context: Context) {
        try { root(context).deleteRecursively() } catch (_: Exception) { }
    }
}
