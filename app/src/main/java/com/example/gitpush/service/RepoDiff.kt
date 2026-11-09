package com.example.gitpush.service

import com.example.gitpush.model.GitFileItem
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.model.RepoTreeIndex
import com.example.gitpush.util.normalizeAndValidateGitPath

/** Önizleme ekranının gösterdiği gönderim planı. */
class PushPlan(
    val adds: List<GitFileItem> = emptyList(),
    val updates: List<GitFileItem> = emptyList(),
    val deletes: List<GitFileItem> = emptyList(),
    val unchanged: List<GitFileItem> = emptyList(),
    val conflicts: List<GitFileItem> = emptyList(),
    /** "Üzerine yazma" kapalıyken atlanan mevcut dosyalar. */
    val skipped: List<GitFileItem> = emptyList(),
    /** Repo ağacı bilinmiyor: gönderim engellenir. */
    val treeUnknown: Boolean = false,
) {
    val hasBlockers get() = conflicts.isNotEmpty() || treeUnknown
    val hasChanges get() = adds.isNotEmpty() || updates.isNotEmpty() || deletes.isNotEmpty()
    val pushItems: List<GitFileItem> get() = adds + updates + deletes

    val approvedDeletePaths: Set<String>
        get() = deletes.map { normalizeAndValidateGitPath(it.repoPath).normalizedPath }.toSet()

    companion object {
        fun build(
            selected: List<GitFileItem>,
            deletes: List<GitFileItem> = emptyList(),
            skipExisting: Boolean = false,
        ): PushPlan {
            val adds = ArrayList<GitFileItem>()
            val updates = ArrayList<GitFileItem>()
            val unchanged = ArrayList<GitFileItem>()
            val conflicts = ArrayList<GitFileItem>()
            val skipped = ArrayList<GitFileItem>()
            var unknown = false
            for (f in selected) {
                if (!f.statusKnown) unknown = true
                when (f.status) {
                    GitFileStatus.IsNew, GitFileStatus.NewFolder -> adds.add(f)
                    GitFileStatus.Update -> if (skipExisting) skipped.add(f) else updates.add(f)
                    GitFileStatus.Unchanged -> unchanged.add(f)
                    GitFileStatus.Conflict -> conflicts.add(f)
                    GitFileStatus.Delete -> Unit
                }
            }
            return PushPlan(adds, updates, deletes, unchanged, conflicts, skipped, unknown)
        }
    }
}

/** ZIP yollarının repodaki gerçek konuma otomatik hizalanması. */
class ZipAlignment(
    val stripSegments: Int,
    val addPrefix: String,
    val matches: Int,
    val baselineMatches: Int,
    val total: Int,
) {
    fun apply(originalPath: String): String {
        val segs = originalPath.split('/')
        val k = if (stripSegments < segs.size) stripSegments else segs.size - 1
        return addPrefix + segs.subList(k, segs.size).joinToString("/")
    }

    fun describe(): String {
        val parts = ArrayList<String>()
        if (stripSegments > 0) parts.add("ZIP yollarından $stripSegments üst klasör kaldırıldı")
        if (addPrefix.isNotEmpty()) parts.add("\"$addPrefix\" öneki eklendi")
        return "Otomatik eşleştirme: ${parts.joinToString(", ")} ($matches/$total dosya repoda bulundu)."
    }
}

private class AlignCandidate(val k: Int, val prefix: String, val votes: Int)

object RepoDiff {
    const val MAX_BLOB_BYTES = 50 * 1024 * 1024

    /** Her dosyayı repo ağacıyla karşılaştırıp durumunu belirler. index == null -> durum bilinmiyor. */
    fun classify(files: List<GitFileItem>, index: RepoTreeIndex?) {
        for (f in files) {
            if (f.status == GitFileStatus.Delete) continue
            classifyOne(f, index)
        }
        markBatchConflicts(files)
    }

    private fun setConflict(f: GitFileItem, message: String) {
        f.status = GitFileStatus.Conflict
        f.conflictMessage = message
        f.statusKnown = true
        f.remoteSha = null
        f.remoteMode = null
    }

    private fun classifyOne(f: GitFileItem, index: RepoTreeIndex?) {
        f.conflictMessage = null

        if (f.needsChoice) {
            setConflict(f, "Birden fazla eşleşme var, seçin.")
            return
        }
        val validation = normalizeAndValidateGitPath(f.targetPath)
        if (!validation.isValid) {
            setConflict(f, validation.error ?: "Geçersiz dosya yolu.")
            return
        }
        val bytes = f.bytes
        if (bytes == null) {
            setConflict(f, "Dosya içeriği okunamadı.")
            return
        }
        if (f.size > MAX_BLOB_BYTES || bytes.size > MAX_BLOB_BYTES) {
            setConflict(f, "Dosya 50 MB sınırını aşıyor; gönderilemez.")
            return
        }
        if (index == null) {
            f.statusKnown = false
            f.remoteSha = null
            f.remoteMode = null
            return
        }

        val path = validation.normalizedPath
        val node = index.nodes[path]
        if (node != null) {
            if (node.isTree) {
                setConflict(f, "Bu yol bir klasör; dosya adı ekleyin (örn. $path/${f.sourceName}).")
                return
            }
            if (!node.isBlob) {
                setConflict(f, "Bu yol bir alt modül (submodule); üzerine yazılamaz.")
                return
            }
            if (f.computedSha == null) f.computedSha = GitHubService.calculateGitBlobSha(bytes)
            f.remoteSha = node.sha
            f.remoteMode = node.mode
            f.statusKnown = true
            f.status = if (f.computedSha == node.sha) GitFileStatus.Unchanged else GitFileStatus.Update
            return
        }

        val fileAncestor = index.findFileAncestor(path)
        if (fileAncestor != null) {
            setConflict(f, "Üst yol \"$fileAncestor\" repoda bir dosya; klasör olarak kullanılamaz.")
            return
        }
        f.remoteSha = null
        f.remoteMode = null
        f.statusKnown = true
        f.status = if (index.hasParentFolder(path)) GitFileStatus.IsNew else GitFileStatus.NewFolder
    }

    /** Aynı gönderim içindeki yol çakışmaları (aynı yol / dosya-klasör). */
    private fun markBatchConflicts(files: List<GitFileItem>) {
        val groups = LinkedHashMap<String, MutableList<GitFileItem>>()
        for (f in files) {
            if (!f.isSelected || f.status == GitFileStatus.Delete) continue
            val v = normalizeAndValidateGitPath(f.targetPath)
            if (!v.isValid) continue
            groups.getOrPut(v.normalizedPath.lowercase()) { ArrayList() }.add(f)
        }
        for (group in groups.values) {
            if (group.size > 1) for (f in group) setConflict(f, "Aynı yola giden birden fazla dosya var.")
        }
        for ((key, items) in groups) {
            var idx = key.lastIndexOf('/')
            while (idx > 0) {
                val parent = key.substring(0, idx)
                val parentGroup = groups[parent]
                if (parentGroup != null) {
                    for (f in items) setConflict(f, "Bu yolun üst yolu (\"$parent\") aynı gönderimde dosya olarak var.")
                    for (f in parentGroup) setConflict(f, "Bu yol, aynı gönderimde klasör olarak da kullanılıyor.")
                }
                idx = parent.lastIndexOf('/')
            }
        }
    }

    /**
     * ZIP yollarını repodaki gerçek konuma uydurmayı dener (üst klasör kırp / önek ekle).
     * Belirsizse veya yeterli kanıt yoksa null.
     */
    fun detectAlignment(
        originalPaths: List<String>,
        currentPaths: List<String>,
        index: RepoTreeIndex,
        maxStrip: Int = 6,
    ): ZipAlignment? {
        val total = originalPaths.size
        if (total == 0 || index.nodes.isEmpty()) return null

        val lowerBlobs = HashSet<String>()
        val suffixPrefixes = HashMap<String, MutableSet<String>>()
        var budget = 300000
        for (node in index.nodes.values) {
            if (!node.isBlob) continue
            val path = node.path
            lowerBlobs.add(path.lowercase())
            var start = 0
            while (true) {
                val suffix = path.substring(start).lowercase()
                suffixPrefixes.getOrPut(suffix) { HashSet() }.add(path.substring(0, start))
                budget--
                val next = path.indexOf('/', start)
                if (next == -1) break
                start = next + 1
            }
            if (budget <= 0) break
        }

        var baseline = 0
        for (p in currentPaths) if (lowerBlobs.contains(p.lowercase())) baseline++
        if (baseline >= total) return null

        val votes = HashMap<String, Int>()
        for (orig in originalPaths) {
            val segs = orig.split('/')
            val maxK = if (segs.size - 1 < maxStrip) segs.size - 1 else maxStrip
            for (k in 0..maxK) {
                val stripped = segs.subList(k, segs.size).joinToString("/").lowercase()
                val prefixes = suffixPrefixes[stripped]
                if (prefixes == null || prefixes.size > 20) continue
                for (pre in prefixes) {
                    val key = "$k|$pre"
                    votes[key] = (votes[key] ?: 0) + 1
                }
            }
        }
        if (votes.isEmpty()) return null

        val candidates = votes.map { (key, v) ->
            val sep = key.indexOf('|')
            AlignCandidate(key.substring(0, sep).toInt(), key.substring(sep + 1), v)
        }.sortedWith(Comparator { a, b ->
            if (a.votes != b.votes) return@Comparator b.votes.compareTo(a.votes)
            if (a.k != b.k) return@Comparator a.k.compareTo(b.k)
            a.prefix.length.compareTo(b.prefix.length)
        })

        val top = candidates.first()
        if (candidates.size > 1) {
            val second = candidates[1]
            if (second.votes == top.votes && second.k == top.k) return null
        }
        val minVotes = if (total == 1) 1 else 2
        if (top.votes < minVotes) return null
        if (top.votes * 100 < total * 40) return null // en az %40 eşleşme
        if (top.votes <= baseline) return null
        return ZipAlignment(top.k, top.prefix, top.votes, baseline, total)
    }

    /**
     * "Repoda olup ZIP'te olmayanları sil" için silinecek dosyalar. Kapsam: hedef klasör önekiyse
     * o klasör, önek yoksa ZIP'in dokunduğu üst klasörler. Kökteki dosyalara asla dokunulmaz.
     */
    fun computeUnlistedDeletes(
        index: RepoTreeIndex,
        zipEffectivePaths: Iterable<String>,
        normalizedPrefix: String,
    ): List<GitFileItem> {
        val zipPaths = HashSet<String>()
        for (raw in zipEffectivePaths) {
            val v = normalizeAndValidateGitPath(raw)
            if (v.isValid) zipPaths.add(v.normalizedPath)
        }
        val scopes = LinkedHashSet<String>()
        if (normalizedPrefix.isNotEmpty()) {
            scopes.add(normalizedPrefix) // "a/b/" biçiminde
        } else {
            for (p in zipPaths) {
                val slash = p.indexOf('/')
                if (slash > 0) scopes.add(p.substring(0, slash) + "/")
            }
        }
        if (scopes.isEmpty()) return emptyList()

        val result = ArrayList<GitFileItem>()
        val candidates = index.nodes.values.filter { it.isBlob }.sortedBy { it.path }
        for (node in candidates) {
            if (zipPaths.contains(node.path)) continue
            if (scopes.any { node.path.startsWith(it) }) result.add(GitFileItem.deletion(node.path))
        }
        return result
    }
}
