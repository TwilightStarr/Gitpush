package com.example.gitpush.state

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.example.gitpush.model.GitHubBranch
import com.example.gitpush.model.GitHubRepo
import com.example.gitpush.model.PathCommitInfo
import com.example.gitpush.model.RepoEntry
import com.example.gitpush.model.RepoMove
import com.example.gitpush.model.RepoTreeIndex
import com.example.gitpush.model.TreeEntry
import com.example.gitpush.model.blobsUnder
import com.example.gitpush.service.GitHubApiException
import com.example.gitpush.service.GitHubService
import com.example.gitpush.service.StorageService
import com.example.gitpush.util.normalizeAndValidateGitPath
import kotlinx.coroutines.CancellationException

class DeleteResult(val commitSha: String, val fileCount: Int)

/** Depo / dal seçimi ve seçili dalın dosya ağacı. */
class RepoProvider(private val github: GitHubService, private val storage: StorageService) {

    var repositories by mutableStateOf<List<GitHubRepo>>(emptyList())
        private set
    var branches by mutableStateOf<List<GitHubBranch>>(emptyList())
        private set
    var selectedRepo by mutableStateOf<GitHubRepo?>(null)
        private set
    var selectedBranch by mutableStateOf<String?>(null)
        private set
    var isLoading by mutableStateOf(false)
        private set
    var errorMessage by mutableStateOf<String?>(null)
        private set

    var currentTree by mutableStateOf<List<TreeEntry>>(emptyList())
        private set
    var treeIndex by mutableStateOf<RepoTreeIndex?>(null)
        private set
    var isTreeLoading by mutableStateOf(false)
        private set
    var treeError by mutableStateOf<String?>(null)
        private set
    var treeTruncated by mutableStateOf(false)
        private set

    /** Ağaç her değiştiğinde artar; ekranlar buna bakarak yeniden sınıflandırır. */
    var treeRevision by mutableStateOf(0)
        private set

    private var treeRequestId = 0
    private var selectionEpoch = 0

    private fun clearTree() {
        treeRequestId++ // uçuştaki eski isteklerin sonucu yok sayılsın
        currentTree = emptyList()
        treeIndex = null
        treeError = null
        treeTruncated = false
        isTreeLoading = false
        treeRevision++
    }

    suspend fun loadRepositories(token: String) {
        isLoading = true
        errorMessage = null
        try {
            repositories = github.getRepositories(token)
            val (savedName, savedBranch) = storage.getLastRepoAndBranch()
            val found = savedName?.let { n -> repositories.firstOrNull { it.fullName == n } }
            if (found != null) {
                selectedRepo = found
                selectedBranch = savedBranch ?: found.defaultBranch
            } else if (repositories.isNotEmpty()) {
                selectedRepo = repositories.first()
                selectedBranch = repositories.first().defaultBranch
            } else {
                selectedRepo = null
                selectedBranch = null
            }
            selectedRepo?.let { loadBranches(token, it) }
        } catch (e: GitHubApiException) {
            errorMessage = e.message
        } finally {
            isLoading = false
        }
    }

    suspend fun loadBranches(token: String, repo: GitHubRepo) {
        val epoch = selectionEpoch
        try {
            val list = github.getBranches(token, repo.owner, repo.name)
            if (epoch != selectionEpoch) return // arada repo değişti
            branches = list
            if (selectedBranch == null || branches.none { it.name == selectedBranch }) {
                selectedBranch = repo.defaultBranch
            }
        } catch (e: GitHubApiException) {
            if (epoch != selectionEpoch) return
            errorMessage = e.message
            return
        }
        refreshTree(token)
    }

    suspend fun selectRepository(token: String, repo: GitHubRepo) {
        selectionEpoch++
        selectedRepo = repo
        selectedBranch = repo.defaultBranch
        branches = emptyList()
        errorMessage = null
        clearTree()
        storage.saveLastRepoAndBranch(repo.fullName, repo.defaultBranch)
        loadBranches(token, repo)
    }

    suspend fun selectBranch(token: String, branch: String) {
        selectionEpoch++
        selectedBranch = branch
        clearTree()
        val repo = selectedRepo
        if (repo != null) {
            storage.saveLastRepoAndBranch(repo.fullName, branch)
            refreshTree(token)
        }
    }

    /** Seçili dalın ağacını yeniden yükler. Eski (geçersiz) isteklerin sonucu yok sayılır. */
    suspend fun refreshTree(token: String): Boolean {
        val repo = selectedRepo
        val branch = selectedBranch
        if (repo == null || branch == null) return false
        val requestId = ++treeRequestId
        isTreeLoading = true
        treeError = null
        var success = false
        try {
            val result = github.getRecursiveTree(token, repo.owner, repo.name, branch)
            if (requestId != treeRequestId) return false // eski istek
            currentTree = result.entries
            treeIndex = RepoTreeIndex.fromEntries(result.entries)
            treeTruncated = result.truncated
            success = true
        } catch (e: CancellationException) {
            throw e
        } catch (e: GitHubApiException) {
            if (requestId != treeRequestId) return false
            currentTree = emptyList(); treeIndex = null; treeTruncated = false
            treeError = e.message
        } catch (e: Exception) {
            if (requestId != treeRequestId) return false
            currentTree = emptyList(); treeIndex = null; treeTruncated = false
            treeError = "Repo dosya listesi alınamadı: $e"
        } finally {
            if (requestId == treeRequestId) {
                isTreeLoading = false
                treeRevision++
            }
        }
        return success
    }

    suspend fun createNewRepo(token: String, name: String, isPrivate: Boolean): GitHubRepo? {
        isLoading = true
        errorMessage = null
        try {
            val newRepo = github.createRepository(token, name, isPrivate)
            selectionEpoch++
            repositories = listOf(newRepo) + repositories
            selectedRepo = newRepo
            selectedBranch = newRepo.defaultBranch
            branches = emptyList()
            clearTree() // önceki reponun ağacı kalmasın
            storage.saveLastRepoAndBranch(newRepo.fullName, newRepo.defaultBranch)
            loadBranches(token, newRepo)
            return newRepo
        } catch (e: GitHubApiException) {
            errorMessage = e.message
            return null
        } finally {
            isLoading = false
        }
    }

    /** Seçili dalın ucundan yeni dal açar ve ona geçer. */
    suspend fun createNewBranch(token: String, newBranchName: String): Boolean {
        val repo = selectedRepo ?: return false
        val current = selectedBranch ?: return false
        isLoading = true
        try {
            val src = branches.firstOrNull { it.name == current }
            if (src == null) {
                errorMessage = "Kaynak dal bulunamadı; dal listesini yenileyin."
                return false
            }
            github.createBranch(token, repo.owner, repo.name, newBranchName, src.commitSha)
            selectedBranch = newBranchName
            storage.saveLastRepoAndBranch(repo.fullName, newBranchName)
            loadBranches(token, repo)
            return true
        } catch (e: GitHubApiException) {
            errorMessage = e.message
            return false
        } finally {
            isLoading = false
        }
    }

    private fun requireRepo(): GitHubRepo {
        val repo = selectedRepo
        if (repo == null || selectedBranch == null) throw GitHubApiException(0, "Önce bir depo ve dal seçin.")
        return repo
    }

    suspend fun readFileBytes(token: String, file: RepoEntry, maxBytes: Long = 512L * 1024): ByteArray {
        val repo = requireRepo()
        val sha = file.sha ?: throw GitHubApiException(0, "Bu dosyanın SHA bilgisi yok; ağacı yenileyin.")
        if (file.size > maxBytes) throw GitHubApiException(0, "Dosya önizleme sınırından büyük.")
        return github.getBlobBytes(token, repo.owner, repo.name, sha, maxBytes)
    }

    suspend fun lastCommitFor(token: String, path: String): PathCommitInfo? {
        val repo = requireRepo()
        return github.getLastCommitForPath(token, repo.owner, repo.name, selectedBranch!!, path)
    }

    /** Dosya ve klasörleri TEK commit ile siler. */
    suspend fun deleteEntries(
        token: String, entries: List<RepoEntry>, message: String,
        authorName: String? = null, authorEmail: String? = null,
    ): DeleteResult {
        val repo = requireRepo()
        val paths = LinkedHashSet<String>()
        for (e in entries) {
            if (e.isDir) blobsUnder(currentTree, e.path).forEach { paths.add(it.path) } else paths.add(e.path)
        }
        if (paths.isEmpty()) throw GitHubApiException(0, "Silinecek dosya bulunamadı (klasör boş olabilir).")
        val sha = github.deletePathsInOneCommit(
            token, repo.owner, repo.name, selectedBranch!!, message, paths.sorted(), authorName, authorEmail,
        )
        refreshTree(token)
        return DeleteResult(sha, paths.size)
    }

    private class MoveSource(val path: String, val sha: String?, val mode: String?)

    /** Taşıma/yeniden adlandırma planı; çakışmaları (hedef var, dosya/klasör, harf büyüklüğü) denetler. */
    fun planMove(entry: RepoEntry, newPath: String): List<RepoMove> {
        val index = treeIndex ?: throw GitHubApiException(0, "Depo ağacı yüklenmedi; yenileyip tekrar deneyin.")
        if (treeTruncated) throw GitHubApiException(0, "Depo çok büyük olduğu için ağaç eksik; taşıma güvenli değil.")
        val v = normalizeAndValidateGitPath(newPath)
        if (!v.isValid) throw GitHubApiException(0, v.error ?: "Geçersiz yol.")
        val target = v.normalizedPath
        if (target == entry.path) throw GitHubApiException(0, "Yeni yol eskisiyle aynı.")
        if (entry.isDir && target.startsWith("${entry.path}/")) throw GitHubApiException(0, "Klasör kendi içine taşınamaz.")

        val sources = ArrayList<MoveSource>()
        if (entry.isDir) {
            val prefix = "${entry.path}/"
            for (e in currentTree) {
                if (e.path.startsWith(prefix)) {
                    if (e.type == "commit") throw GitHubApiException(0, "Alt modül içeren klasör taşınamaz.")
                    if (e.type == "blob") sources.add(MoveSource(e.path, e.sha, e.mode))
                }
            }
            if (sources.isEmpty()) throw GitHubApiException(0, "Klasör boş; taşınacak dosya yok.")
        } else {
            val node = index.nodes[entry.path]
            if (node == null || !node.isBlob || node.sha == null) {
                throw GitHubApiException(0, "Dosya bulunamadı; ağacı yenileyin.")
            }
            sources.add(MoveSource(node.path, node.sha, node.mode))
        }

        val moving = sources.map { it.path.lowercase() }.toSet()
        val existing = index.nodes.values.map { it.path.lowercase() }.filter { it !in moving }.toSet()

        val moves = ArrayList<RepoMove>()
        for (src in sources) {
            val from = src.path
            val to = if (entry.isDir) target + from.substring(entry.path.length) else target
            val lower = to.lowercase()
            if (existing.contains(lower)) throw GitHubApiException(0, "Hedefte zaten bir öğe var: $to")

            var idx = lower.lastIndexOf('/')
            while (idx > 0) {
                if (existing.contains(lower.substring(0, idx))) {
                    val parent = to.substring(0, idx)
                    val node = index.nodes[parent]
                        ?: throw GitHubApiException(0, "Harf büyüklüğü farkıyla çakışan bir yol var: $parent")
                    if (!node.isTree) throw GitHubApiException(0, "\"$parent\" bir dosya; altında klasör oluşturulamaz.")
                }
                idx = lower.lastIndexOf('/', idx - 1)
            }
            val asDir = "$lower/"
            if (existing.any { it.startsWith(asDir) }) throw GitHubApiException(0, "Hedef bir klasör: $to")

            moves.add(RepoMove(from, to, src.sha!!, src.mode ?: "100644"))
        }
        return moves
    }

    suspend fun applyMoves(
        token: String, moves: List<RepoMove>, message: String,
        authorName: String? = null, authorEmail: String? = null,
    ): String {
        val repo = requireRepo()
        val sha = github.movePathsInOneCommit(
            token, repo.owner, repo.name, selectedBranch!!, message, moves, authorName, authorEmail,
        )
        refreshTree(token)
        return sha
    }

    suspend fun saveFile(
        token: String, path: String, bytes: ByteArray, message: String, mode: String? = null,
        authorName: String? = null, authorEmail: String? = null,
    ): String {
        val repo = requireRepo()
        val sha = github.commitFileContent(
            token, repo.owner, repo.name, selectedBranch!!, path, bytes, message, mode, authorName, authorEmail,
        )
        refreshTree(token)
        return sha
    }

    /** Yeni dosya yolu uygunsa null, değilse kullanıcıya gösterilecek sorun metni. */
    fun newFilePathProblem(rawPath: String): String? {
        val v = normalizeAndValidateGitPath(rawPath)
        if (!v.isValid) return v.error ?: "Geçersiz yol."
        val index = treeIndex ?: return "Depo ağacı yüklenmedi; yenileyin."
        val lower = v.normalizedPath.lowercase()
        for (n in index.nodes.values) {
            val p = n.path.lowercase()
            if (p == lower) return "Bu yolda zaten bir öğe var."
            if (p.startsWith("$lower/")) return "Bu yol bir klasör."
        }
        val fileParent = index.findFileAncestor(v.normalizedPath)
        if (fileParent != null) return "\"$fileParent\" bir dosya; altında oluşturulamaz."
        return null
    }

    suspend fun loadCommits(token: String, path: String? = null, page: Int = 1): List<PathCommitInfo> {
        val repo = requireRepo()
        return github.getCommits(token, repo.owner, repo.name, selectedBranch!!, path, page)
    }

    suspend fun deleteBranch(token: String, branch: String) {
        val repo = requireRepo()
        if (branch == repo.defaultBranch) throw GitHubApiException(0, "Varsayılan dal silinemez.")
        github.deleteBranch(token, repo.owner, repo.name, branch)
        if (selectedBranch == branch) selectBranch(token, repo.defaultBranch) else loadBranches(token, repo)
    }

    fun reset() {
        selectionEpoch++
        repositories = emptyList()
        branches = emptyList()
        selectedRepo = null
        selectedBranch = null
        errorMessage = null
        isLoading = false
        clearTree()
    }
}
