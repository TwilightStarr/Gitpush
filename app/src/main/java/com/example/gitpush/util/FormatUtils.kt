package com.example.gitpush.util

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private fun f1(v: Double) = String.format(Locale.US, "%.1f", v)
private fun f2(v: Double) = String.format(Locale.US, "%.2f", v)

fun formatBytes(bytes: Long): String {
    if (bytes < 1024) return "$bytes B"
    if (bytes < 1024L * 1024) return "${f1(bytes / 1024.0)} KB"
    if (bytes < 1024L * 1024 * 1024) return "${f1(bytes / (1024.0 * 1024))} MB"
    return "${f2(bytes / (1024.0 * 1024 * 1024))} GB"
}

fun formatBytes(bytes: Int): String = formatBytes(bytes.toLong())

fun formatDurationMinutes(totalMinutes: Long): String {
    if (totalMinutes < 1) return "< 1 dk"
    val hours = totalMinutes / 60
    val minutes = totalMinutes % 60
    if (hours <= 0) return "$minutes dk"
    if (minutes == 0L) return "$hours sa"
    return "$hours sa $minutes dk"
}

fun shortSha(sha: String, length: Int = 7): String =
    if (sha.length <= length) sha else sha.substring(0, length)

fun formatDateTime(epochMs: Long): String =
    SimpleDateFormat("dd.MM.yyyy HH:mm", Locale.getDefault()).format(Date(epochMs))

fun formatDate(epochMs: Long): String =
    SimpleDateFormat("dd.MM.yyyy", Locale.getDefault()).format(Date(epochMs))

fun formatHhmm(epochMs: Long): String =
    SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(epochMs))

/** "az önce", "5 dk önce"... ; 30 günden eskiyse tarih. */
fun timeAgo(epochMs: Long?, now: Long = System.currentTimeMillis()): String {
    if (epochMs == null) return ""
    val diffMin = (now - epochMs) / 60_000
    val diffHours = diffMin / 60
    val diffDays = diffHours / 24
    if (diffMin < 1) return "az önce"
    if (diffHours < 1) return "$diffMin dk önce"
    if (diffDays < 1) return "$diffHours sa önce"
    if (diffDays < 30) return "$diffDays gün önce"
    return formatDate(epochMs)
}
