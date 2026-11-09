package com.example.gitpush.service

import com.example.gitpush.model.GitFileItem
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.util.normalizeAndValidateGitPath
import java.io.ByteArrayInputStream
import java.util.zip.ZipInputStream

class ZipServiceException(override val message: String) : Exception(message)

class ZipExtractResult(val items: List<GitFileItem>, val invalidEntries: List<String>)

object ZipService {
    private val ignoredPatterns = listOf(
        Regex("""(^|/)(__MACOSX)($|/)"""),
        Regex("""(^|/)(\.DS_Store)$"""),
        Regex("""(^|/)(Thumbs\.db)$"""),
        Regex("""(^|/)(\.git)($|/)"""),
    )

    /** Önemsiz/sistem dosyaları (macOS, Thumbs.db, .git) ZIP'ten ayıklanmaz. */
    fun shouldIgnore(path: String) = ignoredPatterns.any { it.containsMatchIn(path) }

    private class RawEntry(val name: String, val bytes: ByteArray)

    fun extractZipBytes(zipBytes: ByteArray, stripSingleRootDir: Boolean = true): ZipExtractResult {
        try {
            return extract(zipBytes, stripSingleRootDir)
        } catch (e: ZipServiceException) {
            throw e
        } catch (e: Exception) {
            throw ZipServiceException("ZIP dosyası okunamadı. Dosya bozuk veya şifreli olabilir.")
        }
    }

    private fun readEntries(zipBytes: ByteArray): List<RawEntry> {
        val out = ArrayList<RawEntry>()
        ZipInputStream(ByteArrayInputStream(zipBytes)).use { zis ->
            while (true) {
                val entry = zis.nextEntry ?: break
                if (entry.isDirectory) continue
                out.add(RawEntry(entry.name, zis.readBytes()))
            }
        }
        return out
    }

    private fun extract(zipBytes: ByteArray, stripSingleRootDir: Boolean): ZipExtractResult {
        val entries = readEntries(zipBytes)
        val names = ArrayList<String>()
        val files = ArrayList<RawEntry>()
        val invalid = ArrayList<String>()

        for (file in entries) {
            val name = file.name.replace('\\', '/')
            if (shouldIgnore(name)) continue
            val validation = normalizeAndValidateGitPath(name)
            // Mutlak yol ve ".." içeren (zip-slip) girdiler atlanır
            if (!validation.isValid || name.startsWith("/")) {
                invalid.add(file.name)
                continue
            }
            names.add(validation.normalizedPath)
            files.add(file)
        }

        if (files.isEmpty()) return ZipExtractResult(emptyList(), invalid)

        // Tüm dosyalar tek bir üst klasör altındaysa o klasör düzleştirilir
        var commonRoot: String? = null
        if (stripSingleRootDir) {
            val firstSlash = names.first().indexOf('/')
            if (firstSlash != -1) {
                val possibleRoot = names.first().substring(0, firstSlash + 1)
                if (names.all { it.startsWith(possibleRoot) }) commonRoot = possibleRoot
            }
        }

        val items = ArrayList<GitFileItem>()
        for (i in files.indices) {
            var cleanPath = names[i]
            if (commonRoot != null && cleanPath.startsWith(commonRoot)) {
                cleanPath = cleanPath.substring(commonRoot.length)
            }
            val bytes = files[i].bytes
            items.add(
                GitFileItem(
                    localPath = files[i].name,
                    repoPath = cleanPath,
                    size = bytes.size,
                    bytes = bytes,
                    isSelected = true,
                    status = GitFileStatus.IsNew,
                ),
            )
        }
        return ZipExtractResult(items, invalid)
    }
}
