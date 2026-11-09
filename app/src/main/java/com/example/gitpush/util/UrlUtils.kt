package com.example.gitpush.util

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import java.net.URI
import java.net.URLEncoder

/** Harici bağlantılar yalnızca https + github.com (ve alt alan adları) olabilir. */
fun isSafeExternalUrl(url: String): Boolean {
    return try {
        val uri = URI(url.trim())
        if (uri.scheme != "https") return false
        if (uri.userInfo != null) return false
        val host = uri.host?.lowercase() ?: return false
        host == "github.com" || host.endsWith(".github.com")
    } catch (_: Exception) {
        false
    }
}

/** Güvenli ise tarayıcıda açar; açılamazsa false döner. */
fun openExternalUrl(context: Context, url: String): Boolean {
    val trimmed = url.trim()
    if (trimmed.isEmpty() || !isSafeExternalUrl(trimmed)) return false
    return try {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(trimmed)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
        true
    } catch (_: Exception) {
        false
    }
}

fun copyToClipboard(context: Context, text: String) {
    val cm = context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("Gitpush", text))
}

/** Dart'taki Uri.encodeComponent karşılığı (boşluk -> %20). */
fun encodeComponent(s: String): String =
    URLEncoder.encode(s, "UTF-8").replace("+", "%20").replace("%7E", "~")

/** Yolun her segmentini ayrı ayrı kodlar, "/" korunur. */
fun encodePath(path: String): String = path.split('/').joinToString("/") { encodeComponent(it) }

fun encodeQueryComponent(s: String): String = URLEncoder.encode(s, "UTF-8")
