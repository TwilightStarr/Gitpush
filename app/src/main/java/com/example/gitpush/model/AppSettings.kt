package com.example.gitpush.model

import com.example.gitpush.util.asBool
import com.example.gitpush.util.asDouble
import com.example.gitpush.util.asLong
import com.example.gitpush.util.asObj
import com.example.gitpush.util.asStr
import com.example.gitpush.util.parseJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.Locale

enum class RepoSortMode(val label: String) {
    NameAsc("Ad (A → Z)"),
    NameDesc("Ad (Z → A)"),
    SizeDesc("Boyut (büyükten küçüğe)"),
    Extension("Dosya türü"),
}

enum class RepoListSort(val label: String) {
    Recent("Son güncellenen"),
    Name("Ada göre"),
    PrivateFirst("Özel depolar önce"),
}

data class AppSettings(
    val accentIndex: Int = 0,
    val amoledDark: Boolean = false,
    val defaultCommitMessage: String = "",
    val haptics: Boolean = true,
    val repoSort: RepoSortMode = RepoSortMode.NameAsc,
    val showHiddenFiles: Boolean = true,
    val repoListSort: RepoListSort = RepoListSort.Recent,
    val rememberLastRepo: Boolean = true,
    val previewMaxKb: Int = 512,
    val previewWrapLines: Boolean = false,
    val previewFontSize: Double = 12.0,
    val historyLimit: Int = 50,
    val appLockEnabled: Boolean = false,
    /** Arka plandan dönünce kilitlenme süresi (sn). 0 = her seferinde. */
    val lockTimeoutSeconds: Int = 30,
    /** Bu kadar gün açılmazsa token silinir. 0 = kapalı. */
    val autoLogoutDays: Int = 0,
) {
    val accentColorValue: Long get() = accentPalette[clampIndex(accentIndex)]

    fun toJson(): String = buildJsonObject {
        put("accentIndex", accentIndex)
        put("amoledDark", amoledDark)
        put("defaultCommitMessage", defaultCommitMessage)
        put("haptics", haptics)
        put("repoSort", repoSort.name)
        put("showHiddenFiles", showHiddenFiles)
        put("repoListSort", repoListSort.name)
        put("rememberLastRepo", rememberLastRepo)
        put("previewMaxKb", previewMaxKb)
        put("previewWrapLines", previewWrapLines)
        put("previewFontSize", previewFontSize)
        put("historyLimit", historyLimit)
        put("appLockEnabled", appLockEnabled)
        put("lockTimeoutSeconds", lockTimeoutSeconds)
        put("autoLogoutDays", autoLogoutDays)
    }.toString()

    companion object {
        val previewMaxKbOptions = listOf(128, 512, 1024, 2048, 5120, 10240, 25600, 51200, 102400)
        const val PREVIEW_MAX_KB_MIN = 16
        const val PREVIEW_MAX_KB_MAX = 102400

        val historyLimitOptions = listOf(25, 50, 100, 200)
        val lockTimeoutOptions = listOf(0, 30, 60, 300)
        val autoLogoutOptions = listOf(0, 7, 30, 90)

        val accentPalette = listOf(
            0xFF5B6CFFL, // İndigo (marka)
            0xFF00B8A9L, // Turkuaz
            0xFF2EA043L, // Yeşil
            0xFFE8A200L, // Kehribar
            0xFFE5484DL, // Mercan
            0xFFB455F0L, // Mor
        )
        val accentNames = listOf("İndigo", "Turkuaz", "Yeşil", "Kehribar", "Mercan", "Mor")

        fun formatKb(kb: Int): String {
            if (kb < 1024) return "$kb KB"
            val mb = kb / 1024.0
            val text = if (mb == Math.rint(mb)) String.format(Locale.US, "%.0f", mb) else String.format(Locale.US, "%.1f", mb)
            return "$text MB"
        }

        private fun clampIndex(i: Int) = if (i < 0 || i >= accentPalette.size) 0 else i

        private fun validPreviewKb(kb: Int): Int? =
            if (kb in PREVIEW_MAX_KB_MIN..PREVIEW_MAX_KB_MAX) kb else null

        fun fromJson(source: String?): AppSettings {
            if (source.isNullOrEmpty()) return AppSettings()
            val obj = parseJson(source).asObj ?: return AppSettings()
            return fromMap(obj)
        }

        fun fromMap(m: JsonObject): AppSettings {
            val d = AppSettings()
            fun b(k: String, def: Boolean) = m[k].asBool ?: def
            fun i(k: String, def: Int) = m[k].asLong?.toInt() ?: def
            fun pick(k: String, allowed: List<Int>, def: Int): Int {
                val v = i(k, def)
                return if (allowed.contains(v)) v else def
            }
            fun <T : Enum<T>> enumOf(k: String, values: Array<T>, def: T): T {
                val raw = m[k].asStr ?: return def
                return values.firstOrNull { it.name == raw } ?: def
            }

            val fs = m["previewFontSize"].asDouble ?: d.previewFontSize
            val commit = m["defaultCommitMessage"].asStr
            return AppSettings(
                accentIndex = clampIndex(i("accentIndex", d.accentIndex)),
                amoledDark = b("amoledDark", d.amoledDark),
                defaultCommitMessage = commit?.trim() ?: d.defaultCommitMessage,
                haptics = b("haptics", d.haptics),
                repoSort = enumOf("repoSort", RepoSortMode.values(), d.repoSort),
                showHiddenFiles = b("showHiddenFiles", d.showHiddenFiles),
                repoListSort = enumOf("repoListSort", RepoListSort.values(), d.repoListSort),
                rememberLastRepo = b("rememberLastRepo", d.rememberLastRepo),
                previewMaxKb = validPreviewKb(i("previewMaxKb", d.previewMaxKb)) ?: d.previewMaxKb,
                previewWrapLines = b("previewWrapLines", d.previewWrapLines),
                previewFontSize = fs.coerceIn(10.0, 18.0),
                historyLimit = pick("historyLimit", historyLimitOptions, d.historyLimit),
                appLockEnabled = b("appLockEnabled", d.appLockEnabled),
                lockTimeoutSeconds = pick("lockTimeoutSeconds", lockTimeoutOptions, d.lockTimeoutSeconds),
                autoLogoutDays = pick("autoLogoutDays", autoLogoutOptions, d.autoLogoutDays),
            )
        }
    }
}
