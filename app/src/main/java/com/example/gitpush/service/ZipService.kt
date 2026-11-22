package com.example.gitpush.service

import com.example.gitpush.model.GitFileItem
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.util.STREAM_BUFFER
import com.example.gitpush.util.Spool
import com.example.gitpush.util.formatBytes
import com.example.gitpush.util.normalizeAndValidateGitPath
import java.io.File
import java.io.IOException
import java.io.InputStream
import java.security.MessageDigest
import java.util.zip.CRC32
import java.util.zip.ZipFile
import java.util.zip.ZipInputStream

class ZipServiceException(override val message: String) : Exception(message)

/** ZIP'ten diske açılmış tek dosya. İçerik [file] içinde, RAM'de tutulmaz. */
class ExtractedEntry(
    /** ZIP içindeki özgün ad. */
    val name: String,
    /** Doğrulanmış, normalleştirilmiş yol. */
    val path: String,
    val file: File,
    val size: Long,
    /** Git blob SHA-1 (açılırken akışla hesaplanır). */
    val sha: String,
)

class ZipExtractResult(
    val entries: List<ExtractedEntry>,
    val invalidEntries: List<String>,
    /** Tek dosya sınırını (100 MB) aştığı için açılmayan girdiler. */
    val oversizedEntries: List<String> = emptyList(),
)

object ZipService {
    /** GitHub, Git Data API ile tek blob için en çok 100 MB kabul eder. */
    const val MAX_FILE_BYTES = RepoDiff.MAX_BLOB_BYTES

    private val ignoredPatterns = listOf(
        Regex("""(^|/)(__MACOSX)($|/)"""),
        Regex("""(^|/)(\.DS_Store)$"""),
        Regex("""(^|/)(Thumbs\.db)$"""),
        Regex("""(^|/)(\.git)($|/)"""),
    )

    /** Önemsiz/sistem dosyaları (macOS, Thumbs.db, .git) ZIP'ten ayıklanmaz. */
    fun shouldIgnore(path: String) = ignoredPatterns.any { it.containsMatchIn(path) }

    /**
     * [zip] dosyasını [outDir] altına dosya dosya açar. Hiçbir zaman bütün arşivi ya da bir dosyayı
     * belleğe almaz (RAM kullanımı sabit), diskteki adlar ZIP girdi adlarından türetilmez (zip-slip yok).
     * Önce ZipFile (merkezi dizin, CRC doğrulaması) denenir; açılamazsa akışlı okumaya düşülür.
     */
    fun extractToDir(
        zip: File,
        outDir: File,
        onProgress: ((String) -> Unit)? = null,
    ): ZipExtractResult {
        outDir.mkdirs()
        try {
            return viaZipFile(zip, outDir, onProgress)
        } catch (e: ZipServiceException) {
            throw e
        } catch (_: Exception) {
            // ZipFile bu arşivi açamadı (ör. Zip64 / alışılmadık yapı); akışlı yöntemi dene.
        }
        outDir.deleteRecursively()
        outDir.mkdirs()
        try {
            return viaStream(zip, outDir, onProgress)
        } catch (e: ZipServiceException) {
            throw e
        } catch (e: IOException) {
            if (e.message?.contains("ENOSPC") == true || e.message?.contains("No space") == true) {
                throw ZipServiceException("Cihazda boş alan kalmadı.")
            }
            throw ZipServiceException("ZIP dosyası okunamadı. Dosya bozuk veya şifreli olabilir.")
        } catch (e: Exception) {
            throw ZipServiceException("ZIP dosyası okunamadı. Dosya bozuk veya şifreli olabilir.")
        }
    }

    private fun viaZipFile(zip: File, outDir: File, onProgress: ((String) -> Unit)?): ZipExtractResult {
        val ex = Extractor(outDir, onProgress)
        ZipFile(zip).use { zf ->
            val en = zf.entries()
            while (en.hasMoreElements()) {
                val e = en.nextElement()
                if (e.isDirectory) continue
                zf.getInputStream(e).use { ins -> ex.accept(e.name, e.size, e.crc, ins) }
            }
        }
        return ex.result()
    }

    private fun viaStream(zip: File, outDir: File, onProgress: ((String) -> Unit)?): ZipExtractResult {
        val ex = Extractor(outDir, onProgress)
        ZipInputStream(zip.inputStream().buffered(STREAM_BUFFER)).use { zis ->
            while (true) {
                val e = zis.nextEntry ?: break
                if (e.isDirectory) continue
                // ZipInputStream kendi CRC denetimini yapar; boyut/CRC burada bilinmeyebilir (-1).
                ex.accept(e.name, e.size, -1L, zis)
            }
        }
        return ex.result()
    }

    private class Extractor(val outDir: File, val onProgress: ((String) -> Unit)?) {
        val entries = ArrayList<ExtractedEntry>()
        val invalid = ArrayList<String>()
        val oversized = ArrayList<String>()
        private var counter = 0
        private var used = 0L
        private var seen = 0

        fun result() = ZipExtractResult(entries, invalid, oversized)

        /** [declaredSize]/[expectedCrc] bilinmiyorsa -1. */
        fun accept(rawName: String, declaredSize: Long, expectedCrc: Long, input: InputStream) {
            seen++
            val name = rawName.replace('\\', '/')
            if (shouldIgnore(name)) return
            val validation = normalizeAndValidateGitPath(name)
            // Mutlak yol ve ".." içeren (zip-slip) girdiler atlanır
            if (!validation.isValid || name.startsWith("/")) {
                invalid.add(rawName)
                return
            }
            if (declaredSize > MAX_FILE_BYTES) {
                oversized.add(rawName)
                return
            }
            if (declaredSize >= 0 && outDir.usableSpace < declaredSize + Spool.FREE_SPACE_MARGIN) {
                throw ZipServiceException(
                    "Cihazda yeterli boş alan yok. Şu ana kadar ${formatBytes(used)} açıldı; " +
                        "${formatBytes(declaredSize)} daha gerekiyor.",
                )
            }

            val dest = File(outDir, "e${counter++}.bin")
            val md = MessageDigest.getInstance("SHA-1")
            val crc = CRC32()
            if (declaredSize >= 0) md.update("blob $declaredSize\u0000".toByteArray(Charsets.UTF_8))
            var written = 0L
            var tooBig = false
            try {
                dest.outputStream().use { out ->
                    val buf = ByteArray(STREAM_BUFFER)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        written += n
                        if (written > MAX_FILE_BYTES) { tooBig = true; break }
                        out.write(buf, 0, n)
                        md.update(buf, 0, n)
                        crc.update(buf, 0, n)
                    }
                }
            } catch (e: IOException) {
                dest.delete()
                if (e.message?.contains("ENOSPC") == true || e.message?.contains("No space") == true) {
                    throw ZipServiceException("Cihazda boş alan kalmadı.")
                }
                throw e
            }
            if (tooBig) {
                dest.delete()
                oversized.add(rawName)
                return
            }
            if (declaredSize >= 0 && written != declaredSize) {
                dest.delete()
                throw ZipServiceException("ZIP bozuk: \"$rawName\" boyutu uyuşmuyor.")
            }
            if (expectedCrc >= 0 && crc.value != expectedCrc) {
                dest.delete()
                throw ZipServiceException("ZIP bozuk: \"$rawName\" CRC doğrulaması başarısız.")
            }
            val sha = if (declaredSize >= 0) {
                md.digest().toHex()
            } else {
                shaOfFile(dest, written) // boyut önceden bilinmiyordu; ikinci geçişte hesapla
            }
            used += written
            entries.add(ExtractedEntry(name = rawName, path = validation.normalizedPath, file = dest, size = written, sha = sha))
            if (entries.size % 25 == 0 || written >= 4L * 1024 * 1024) {
                onProgress?.invoke("Arşiv açılıyor: ${entries.size} dosya · ${formatBytes(used)}")
            }
        }
    }

    private fun shaOfFile(file: File, size: Long): String {
        val md = MessageDigest.getInstance("SHA-1")
        md.update("blob $size\u0000".toByteArray(Charsets.UTF_8))
        file.inputStream().use { ins ->
            val buf = ByteArray(STREAM_BUFFER)
            while (true) {
                val n = ins.read(buf)
                if (n < 0) break
                md.update(buf, 0, n)
            }
        }
        return md.digest().toHex()
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it.toInt() and 0xff) }

    /**
     * Açılmış girdilerden gönderilecek öğeleri üretir. Tüm dosyalar tek bir üst klasör altındaysa
     * (ve [stripSingleRootDir] açıksa) o klasör düzleştirilir. Yalnızca yol hesabıdır; dosya okunmaz.
     */
    fun buildItems(entries: List<ExtractedEntry>, stripSingleRootDir: Boolean = true): List<GitFileItem> {
        if (entries.isEmpty()) return emptyList()
        var commonRoot: String? = null
        if (stripSingleRootDir) {
            val first = entries.first().path
            val firstSlash = first.indexOf('/')
            if (firstSlash != -1) {
                val possibleRoot = first.substring(0, firstSlash + 1)
                if (entries.all { it.path.startsWith(possibleRoot) }) commonRoot = possibleRoot
            }
        }
        return entries.map { e ->
            var clean = e.path
            if (commonRoot != null && clean.startsWith(commonRoot)) clean = clean.substring(commonRoot.length)
            GitFileItem(
                localPath = e.name,
                repoPath = clean,
                size = e.size.toInt(),
                file = e.file,
                isSelected = true,
                status = GitFileStatus.IsNew,
                computedSha = e.sha,
            )
        }
    }
}
