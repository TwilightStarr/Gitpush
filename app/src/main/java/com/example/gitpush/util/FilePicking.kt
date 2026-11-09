package com.example.gitpush.util

import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class PickedFile(val uri: String, val name: String, val size: Long, val bytes: ByteArray)

/** Sistem dosya seçicisinden dönen Uri'yi okur. Sınırı aşan dosya için null döner. */
suspend fun readPickedFile(context: Context, uri: Uri, maxBytes: Long = 100L * 1024 * 1024): PickedFile? =
    withContext(Dispatchers.IO) {
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
        if (size > maxBytes) return@withContext null
        val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() } ?: return@withContext null
        if (bytes.size > maxBytes) return@withContext null
        PickedFile(uri.toString(), name, bytes.size.toLong(), bytes)
    }
