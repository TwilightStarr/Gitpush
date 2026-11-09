package com.example.gitpush.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.gitpush.model.GitFileItem
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.model.HistoryItem
import com.example.gitpush.model.PushResult
import com.example.gitpush.model.RepoTreeIndex
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.service.GitHubService
import com.example.gitpush.service.PushPlan
import com.example.gitpush.service.RepoDiff
import com.example.gitpush.service.StorageService
import com.example.gitpush.service.ZipAlignment
import com.example.gitpush.service.ZipServiceException
import com.example.gitpush.service.ZipService
import com.example.gitpush.util.appendFileNameIfFolder
import com.example.gitpush.util.normalizeAndValidateGitPath
import com.example.gitpush.util.normalizeFolderPrefix
import kotlinx.coroutines.CancellationException

enum class PreviewSource { Zip, Multi }

/**
 * ZIP (Mod A) ve çoklu dosya (Mod B) gönderim durumu. GitFileItem alanları değişebilir olduğundan
 * ekranlar [revision] değerini okuyarak yeniden çizilir.
 */
class UploadProvider(private val github: GitHubService, private val storage: StorageService) {

    var revision by mutableStateOf(0)
        private set

    private fun changed() { revision++ }

    private var index: RepoTreeIndex? = null
    private var treeTruncated = false

    // ── ZIP ──
    var zipFileName: String? = null
        private set
    var zipFileSize = 0
        private set
    private var zipBytes: ByteArray? = null
    private var zipRaw: List<GitFileItem> = emptyList()
    var zipFiles: List<GitFileItem> = emptyList()
        private set
    var zipDeleteItems: List<GitFileItem> = emptyList()
        private set
    var zipInvalidEntries: List<String> = emptyList()
        private set
    var zipStripRootDir = true
        private set
    var zipPrefix = ""
        private set
    var zipOverwriteExisting = true
        private set
    var zipDeleteUnlisted = false
        private set
    var zipAutoAlign = true
        private set
    var zipAlignment: ZipAlignment? = null
        private set
    private var zipCaseFixes = 0
    var zipDeleteNotice: String? = null
        private set

    val zipAlignNotice: String?
        get() {
            val parts = ArrayList<String>()
            zipAlignment?.let { parts.add(it.describe()) }
            if (zipCaseFixes > 0) parts.add("$zipCaseFixes dosyanın harf büyüklüğü repodaki yola uyduruldu.")
            return if (parts.isEmpty()) null else parts.joinToString(" ")
        }

    // ── Çoklu dosya ──
    val multiFiles = ArrayList<GitFileItem>()

    // ── Gönderim ──
    var isUploading by mutableStateOf(false)
        private set
    var uploadStep by mutableStateOf("")
        private set
    var uploadProgressCurrent by mutableStateOf(0)
        private set
    var uploadProgressTotal by mutableStateOf(0)
        private set
    var uploadError by mutableStateOf<String?>(null)
        private set
    var uploadErrorKind: String? = null
        private set
    var lastResult: PushResult? = null
        private set
    var lastCommitUrl: String? = null
        private set

    var historyItems by mutableStateOf<List<HistoryItem>>(emptyList())
        private set

    suspend fun loadHistory() {
        historyItems = storage.getHistory()
    }

    suspend fun clearHistory() {
        storage.clearHistory()
        historyItems = emptyList()
    }

    /** Repo ağacı değişince tüm listeleri yeniden sınıflandırır. */
    fun reclassifyAll(newIndex: RepoTreeIndex?, truncated: Boolean = false) {
        index = newIndex
        treeTruncated = truncated
        rebuildZipPreview()
        for (f in multiFiles) autoMatchMulti(f)
        RepoDiff.classify(multiFiles, index)
        changed()
    }

    // ───────────────────────── ZIP ─────────────────────────

    fun setZipArchive(fileName: String, bytes: ByteArray) {
        val result = ZipService.extractZipBytes(bytes, zipStripRootDir)
        zipFileName = fileName
        zipFileSize = bytes.size
        zipBytes = bytes
        zipRaw = result.items
        zipInvalidEntries = result.invalidEntries
        rebuildZipPreview()
        changed()
    }

    fun setZipStripRootDir(value: Boolean) {
        zipStripRootDir = value
        val bytes = zipBytes
        if (bytes != null) {
            val previous = zipRaw.associate { it.localPath to it.isSelected }
            try {
                val result = ZipService.extractZipBytes(bytes, value)
                for (f in result.items) f.isSelected = previous[f.localPath] ?: true
                zipRaw = result.items
                zipInvalidEntries = result.invalidEntries
            } catch (_: ZipServiceException) {
                // bellekteki ZIP artık okunamıyorsa mevcut liste korunur
            }
        }
        rebuildZipPreview()
        changed()
    }

    fun setZipPrefix(value: String) { zipPrefix = value; rebuildZipPreview(); changed() }
    fun setZipAutoAlign(value: Boolean) { zipAutoAlign = value; rebuildZipPreview(); changed() }
    fun setZipOverwriteExisting(value: Boolean) { zipOverwriteExisting = value; changed() }
    fun setZipDeleteUnlisted(value: Boolean) { zipDeleteUnlisted = value; rebuildZipPreview(); changed() }

    fun toggleZipFileSelection(i: Int, selected: Boolean) {
        if (i in zipRaw.indices) {
            zipRaw[i].isSelected = selected
            rebuildZipPreview()
            changed()
        }
    }

    fun selectAllZipFiles(selected: Boolean) {
        for (f in zipRaw) f.isSelected = selected
        rebuildZipPreview()
        changed()
    }

    fun resetZip(notify: Boolean = true) {
        zipFileName = null
        zipFileSize = 0
        zipBytes = null
        zipRaw = emptyList()
        zipFiles = emptyList()
        zipDeleteItems = emptyList()
        zipInvalidEntries = emptyList()
        zipStripRootDir = true
        zipPrefix = ""
        zipOverwriteExisting = true
        zipDeleteUnlisted = false
        zipDeleteNotice = null
        zipAutoAlign = true
        zipAlignment = null
        zipCaseFixes = 0
        if (notify) changed()
    }

    /**
     * Ham ZIP listesinden önizleme listesini yeniden üretir (öneki TEK kez uygular), otomatik hizalama
     * ve harf büyüklüğü düzeltmesi yapar, repoyla karşılaştırır, isteniyorsa silinecekleri hesaplar.
     */
    private fun rebuildZipPreview() {
        val prefix = normalizeFolderPrefix(zipPrefix)
        val idx = index
        var basePaths = zipRaw.map { it.repoPath }
        zipAlignment = null

        if (zipAutoAlign && prefix.isEmpty() && idx != null && idx.nodes.isNotEmpty() && zipRaw.isNotEmpty()) {
            val originals = zipRaw.map { normalizeAndValidateGitPath(it.localPath).normalizedPath }
            val alignment = RepoDiff.detectAlignment(originals, basePaths, idx)
            if (alignment != null) {
                zipAlignment = alignment
                basePaths = originals.map { alignment.apply(it) }
            }
        }

        zipCaseFixes = 0
        val fullPaths = ArrayList<String>()
        for (base in basePaths) {
            var full = "$prefix$base"
            if (idx != null && !idx.nodes.containsKey(full)) {
                val real = idx.uniqueBlobIgnoreCase(full)
                if (real != null && real != full) {
                    full = real
                    zipCaseFixes++
                }
            }
            fullPaths.add(full)
        }

        zipFiles = zipRaw.mapIndexed { i, f -> f.copyWith(repoPath = fullPaths[i]) }
        RepoDiff.classify(zipFiles, index)
        for (i in zipRaw.indices) {
            if (zipRaw[i].computedSha == null) zipRaw[i].computedSha = zipFiles[i].computedSha
        }

        zipDeleteItems = emptyList()
        zipDeleteNotice = null
        if (zipDeleteUnlisted) {
            if (idx == null) {
                zipDeleteNotice = "Repo dosya listesi bilinmediği için silinecek dosyalar hesaplanamadı."
            } else if (treeTruncated) {
                zipDeleteNotice = "Repo ağacı kesildiği için silinecek dosyalar güvenle hesaplanamıyor; silme yapılmayacak."
            } else {
                zipDeleteItems = RepoDiff.computeUnlistedDeletes(idx, zipFiles.map { it.repoPath }, prefix)
            }
        }
    }

    // ───────────────────────── Çoklu dosya ─────────────────────────

    fun addMultiFiles(items: List<GitFileItem>) {
        for (item in items) {
            autoMatchMulti(item)
            multiFiles.add(item)
        }
        RepoDiff.classify(multiFiles, index)
        changed()
    }

    /** Repoda aynı adlı dosya varsa hedef yolu otomatik ayarlar; birden fazlaysa kullanıcıya bırakır. */
    private fun autoMatchMulti(item: GitFileItem) {
        val idx = index ?: return
        val wasAuto = item.needsChoice ||
            (item.suggestions.size == 1 && item.repoPath == item.suggestions.first())
        val matches = idx.findBlobsByName(item.sourceName)
        item.suggestions = matches
        if (item.pathManual) return
        if (matches.size == 1) {
            item.repoPath = matches.first()
            item.needsChoice = false
        } else if (matches.size > 1) {
            item.repoPath = item.sourceName
            item.needsChoice = true
        } else {
            if (wasAuto) item.repoPath = item.sourceName
            item.needsChoice = false
        }
    }

    fun restoreMultiFiles(items: List<GitFileItem>, atIndex: Int? = null) {
        val existing = multiFiles.map { it.id }.toSet()
        val toAdd = items.filter { it.id !in existing }
        if (atIndex != null && atIndex in 0..multiFiles.size) multiFiles.addAll(atIndex, toAdd) else multiFiles.addAll(toAdd)
        RepoDiff.classify(multiFiles, index)
        changed()
    }

    fun updateMultiFilePathById(id: Int, newPath: String) {
        val item = multiFiles.firstOrNull { it.id == id } ?: return
        item.repoPath = newPath
        item.needsChoice = false
        item.pathManual = true
        RepoDiff.classify(multiFiles, index)
        changed()
    }

    fun removeMultiFile(i: Int) {
        if (i in multiFiles.indices) {
            multiFiles.removeAt(i)
            RepoDiff.classify(multiFiles, index)
            changed()
        }
    }

    fun removeMultiFilesByIds(ids: Set<Int>) {
        multiFiles.removeAll { it.id in ids }
        RepoDiff.classify(multiFiles, index)
        changed()
    }

    fun clearMultiFiles(): List<GitFileItem> {
        val removed = multiFiles.toList()
        multiFiles.clear()
        changed()
        return removed
    }

    /** Kısayolu seçili dosyalara (seçim yoksa tümüne) uygular. */
    fun applyShortcutToMultiFiles(prefix: String, selectedIds: Set<Int>) {
        val targets = if (selectedIds.isEmpty()) multiFiles.toList() else multiFiles.filter { it.id in selectedIds }
        for (item in targets) {
            if (prefix == "Repo kökü" || prefix == "/") {
                item.repoPath = item.sourceName
            } else {
                item.repoPath = normalizeFolderPrefix(prefix) + item.sourceName
            }
            item.needsChoice = false
            item.pathManual = true
        }
        RepoDiff.classify(multiFiles, index)
        changed()
    }

    /**
     * Metinle toplu yol komutları:
     *   dosya.dart=lib/screens/dosya.dart
     *   lib/models/: a.dart b.dart
     * '#' ile başlayan satırlar yorumdur.
     */
    fun parseAndApplyTextCommands(raw: String) {
        for (rawLine in raw.split('\n')) {
            val line = rawLine.trim()
            if (line.isEmpty() || line.startsWith("#")) continue
            val eq = line.indexOf('=')
            val colon = line.indexOf(':')
            if (eq > 0) {
                val targetFile = line.substring(0, eq).trim()
                val targetPath = line.substring(eq + 1).trim()
                if (targetPath.isEmpty()) continue
                for (item in multiFiles) {
                    if (item.sourceName == targetFile) {
                        item.repoPath = appendFileNameIfFolder(targetPath, item.sourceName)
                        item.needsChoice = false
                        item.pathManual = true
                    }
                }
            } else if (colon > 0) {
                val folder = line.substring(0, colon).trim()
                val files = line.substring(colon + 1).trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
                val cleanFolder = normalizeFolderPrefix(folder)
                for (f in files) {
                    for (item in multiFiles) {
                        if (item.sourceName == f) {
                            item.repoPath = cleanFolder + item.sourceName
                            item.needsChoice = false
                            item.pathManual = true
                        }
                    }
                }
            }
        }
        RepoDiff.classify(multiFiles, index)
        changed()
    }

    // ───────────────────────── Plan / gönderim ─────────────────────────

    fun planFor(source: PreviewSource): PushPlan = when (source) {
        PreviewSource.Zip -> PushPlan.build(
            zipFiles.filter { it.isSelected },
            deletes = if (zipDeleteUnlisted) zipDeleteItems else emptyList(),
            skipExisting = !zipOverwriteExisting,
        )
        PreviewSource.Multi -> PushPlan.build(multiFiles.toList())
    }

    fun resetAfterPush() {
        resetZip(notify = false)
        multiFiles.clear()
        changed()
    }

    fun resetAll() {
        index = null
        treeTruncated = false
        lastResult = null
        lastCommitUrl = null
        uploadError = null
        uploadErrorKind = null
        resetZip(notify = false)
        multiFiles.clear()
        changed()
    }

    /** Başka bir yoldan (silme, taşıma, düzenleme) atılan commit'i yerel geçmişe yazar. */
    suspend fun recordExternalCommit(
        owner: String, repo: String, branch: String, commitMessage: String, commitSha: String, filesCount: Int,
    ) {
        storage.addHistoryItem(
            HistoryItem(
                id = System.currentTimeMillis().toString(),
                repoFullName = "$owner/$repo",
                branch = branch,
                commitMessage = commitMessage,
                commitSha = commitSha,
                filesCount = filesCount,
                timestamp = System.currentTimeMillis(),
                commitUrl = "https://github.com/$owner/$repo/commit/$commitSha",
            ),
        )
        loadHistory()
    }

    /** Atomik push'u çalıştırır. Başarıda true; hata [uploadError] içinde. */
    suspend fun executePush(
        token: String, owner: String, repo: String, branch: String, commitMessage: String,
        plan: PushPlan, authorName: String? = null, authorEmail: String? = null,
    ): Boolean {
        if (isUploading) return false // çift çağrı koruması
        val items = plan.pushItems
        isUploading = true
        uploadError = null
        uploadErrorKind = null
        uploadStep = "Başlatılıyor..."
        uploadProgressCurrent = 0
        uploadProgressTotal = items.size
        try {
            val result = github.executeAtomicPush(
                token = token, owner = owner, repo = repo, branch = branch,
                commitMessage = commitMessage, filesToPush = items,
                approvedDeletePaths = plan.approvedDeletePaths,
                authorName = authorName, authorEmail = authorEmail,
                onProgress = { step, current, total ->
                    uploadStep = step
                    uploadProgressCurrent = current
                    uploadProgressTotal = total
                },
            )
            lastResult = result
            val sha = result.commitSha
            if (!result.noChanges && sha != null) {
                lastCommitUrl = "https://github.com/$owner/$repo/commit/$sha"
                storage.addHistoryItem(
                    HistoryItem(
                        id = System.currentTimeMillis().toString(),
                        repoFullName = "$owner/$repo", branch = branch,
                        commitMessage = commitMessage, commitSha = sha,
                        filesCount = result.changedCount,
                        timestamp = System.currentTimeMillis(),
                        commitUrl = lastCommitUrl!!,
                    ),
                )
                loadHistory()
            }
            isUploading = false
            return true
        } catch (e: GitHubApiException) {
            uploadError = e.message
            uploadErrorKind = e.kind
            isUploading = false
            return false
        } catch (e: CancellationException) {
            isUploading = false
            throw e
        } catch (e: Exception) {
            uploadError = "Beklenmeyen hata: $e"
            isUploading = false
            return false
        }
    }
}
