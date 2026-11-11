package com.example.gitpush.service

import android.util.Base64
import com.example.gitpush.model.ActionRun
import com.example.gitpush.model.ActionSecret
import com.example.gitpush.model.SecretRules
import com.example.gitpush.model.GitFileItem
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.model.GitHubBranch
import com.example.gitpush.model.GitHubRepo
import com.example.gitpush.model.PathCommitInfo
import com.example.gitpush.model.PushResult
import com.example.gitpush.model.RateLimitInfo
import com.example.gitpush.model.RepoMove
import com.example.gitpush.model.RepoNode
import com.example.gitpush.model.RepoTreeIndex
import com.example.gitpush.model.RepoTreeResult
import com.example.gitpush.model.TreeEntry
import com.example.gitpush.util.SealedBox
import com.example.gitpush.util.SecretCandidate
import com.example.gitpush.util.SecretGuard
import com.example.gitpush.util.asArr
import com.example.gitpush.util.asBool
import com.example.gitpush.util.asLong
import com.example.gitpush.util.asObj
import com.example.gitpush.util.asStr
import com.example.gitpush.util.encodeComponent
import com.example.gitpush.util.encodePath
import com.example.gitpush.util.encodeQueryComponent
import com.example.gitpush.util.normalizeAndValidateGitPath
import com.example.gitpush.util.parseJson
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.IOException
import java.io.InterruptedIOException
import java.net.ConnectException
import java.net.SocketException
import java.net.UnknownHostException
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLException

class GitHubApiException(
    val statusCode: Int,
    override val message: String,
    val kind: String? = null,
) : Exception(message) {
    companion object {
        /** Dal, işlem sürerken başka biri tarafından değiştirildi. */
        const val KIND_BRANCH_MOVED = "branch_moved"

        /** Güvenlik ağı: beklenmedik dosya kaybı yakalandı. */
        const val KIND_SAFETY_NET = "safety_net"
    }
}

/** Push planındaki, doğrulanmış tek dosya. */
private class PlannedFile(val item: GitFileItem, val path: String, val bytes: ByteArray) {
    var mode = "100644"
    var existed = false
}

/** commitTreeChanges girdisi. sha == null -> dosya silinir. */
class TreeChange(val path: String, val mode: String, val sha: String?)

/**
 * GitHub REST istemcisi. Token yalnızca https://api.github.com adresine gönderilir.
 * Tüm yazma işlemleri Git Data API ile tek commit olarak yapılır ve ref `force:false` ile güncellenir.
 */
class GitHubService(
    private val transport: HttpTransport = OkHttpTransport(),
    private val sleep: suspend (Long) -> Unit = { delay(it) },
    private val nowMs: () -> Long = { System.currentTimeMillis() },
) {
    companion object {
        const val BASE_URL = "https://api.github.com"
        const val API_VERSION = "2022-11-28"
        const val USER_AGENT = "Gitpush"
        private const val DEFAULT_TIMEOUT_MS = 30_000L
        private const val BLOB_TIMEOUT_MS = 90_000L
        private const val BLOB_MAX_TIMEOUT_MS = 15 * 60_000L
        /** Zaman aşımı hesabında varsayılan en düşük yükleme hızı (bayt/sn). */
        private const val MIN_UPLOAD_BYTES_PER_SEC = 40_000L
        /** Bu boyutun üstündeki dosyalar tek başına (eşzamanlı olmadan) yüklenir. */
        private const val PARALLEL_BATCH_BYTES = 4L * 1024 * 1024

        /** Dosya boyutuna göre ölçeklenen blob zaman aşımı (base64 ~%33 büyütür). */
        fun blobTimeoutMs(rawBytes: Int): Long {
            val encoded = rawBytes.toLong() * 4 / 3
            val t = 60_000L + encoded * 1000 / MIN_UPLOAD_BYTES_PER_SEC
            return t.coerceIn(BLOB_TIMEOUT_MS, BLOB_MAX_TIMEOUT_MS)
        }
        private const val MAX_ATTEMPTS = 4
        /** GitHub ikincil (secondary) oran sınırı genelde 60 sn bekletir; bunu bekleyip devam ederiz. */
        private const val MAX_RETRY_WAIT_SEC = 120L
        /** Tek ağaç isteğindeki en fazla girdi ve satır içi içerik boyutu. */
        private const val TREE_CHUNK_ENTRIES = 150
        private const val TREE_CHUNK_BYTES = 1_000_000L
        /** Blob istekleri arasındaki bekleme: GitHub içerik oluşturmada ~80 istek/dk sınırı uygular. */
        private const val BLOB_PACING_MS = 900L
        /** Bu sayıdan az blob varsa bekleme uygulanmaz. */
        private const val BLOB_PACING_FREE = 20
        private const val BLOB_CONCURRENCY = 2
        private const val MAX_BLOB_BYTES = 50 * 1024 * 1024

        private val nameRe = Regex("^[A-Za-z0-9_.-]{1,100}$")
        private val tokenRe = Regex("^[\\x21-\\x7E]{1,255}$")
        private val shaRe = Regex("^[0-9a-f]{40}$")

        /** Git blob SHA-1: sha1("blob <boyut>\u0000" + içerik). */
        fun calculateGitBlobSha(bytes: ByteArray): String {
            val md = MessageDigest.getInstance("SHA-1")
            md.update("blob ${bytes.size}\u0000".toByteArray(Charsets.UTF_8))
            md.update(bytes)
            return md.digest().joinToString("") { "%02x".format(it.toInt() and 0xff) }
        }

        /**
         * Baytlar birebir geri üretilebilen, boş olmayan UTF-8 metinse String döndürür (tree isteğinde
         * `content` olarak gönderilebilir); aksi halde null (blob olarak yüklenir).
         */
        internal fun decodeInlineText(bytes: ByteArray): String? {
            if (bytes.isEmpty()) return null
            for (b in bytes) if (b.toInt() == 0) return null
            return try {
                val text = Charsets.UTF_8.newDecoder()
                    .onMalformedInput(java.nio.charset.CodingErrorAction.REPORT)
                    .onUnmappableCharacter(java.nio.charset.CodingErrorAction.REPORT)
                    .decode(java.nio.ByteBuffer.wrap(bytes)).toString()
                if (text.toByteArray(Charsets.UTF_8).contentEquals(bytes)) text else null
            } catch (_: java.nio.charset.CharacterCodingException) {
                null
            }
        }

        private fun defaultMode(path: String): String {
            val name = path.substringAfterLast('/')
            val executable = name.endsWith(".sh") || name == "gradlew"
            return if (executable) "100755" else "100644"
        }

        private fun isSafeExistingPath(path: String): Boolean {
            if (path.isEmpty() || path.length > 4096) return false
            if (path.startsWith("/") || path.endsWith("/") || path.contains('\\') || path.contains('\u0000')) return false
            val segs = path.split('/')
            for (seg in segs) if (seg.isEmpty() || seg == "." || seg == "..") return false
            if (segs.first().lowercase() == ".git") return false
            return true
        }
    }

    // ───────────────────────── Düşük seviye HTTP ─────────────────────────

    private fun headers(token: String) = mapOf(
        "Authorization" to "Bearer $token",
        "Accept" to "application/vnd.github+json",
        "X-GitHub-Api-Version" to API_VERSION,
        "User-Agent" to USER_AGENT,
    )

    private fun isRateLimited(res: HttpResult): Boolean {
        if (res.code == 429) return true
        if (res.code != 403) return false
        if (res.headers.containsKey("retry-after")) return true
        if (res.headers["x-ratelimit-remaining"] == "0") return true
        val body = res.body.lowercase()
        return body.contains("rate limit") || body.contains("abuse") || body.contains("secondary")
    }

    /** Bekleme süresi (ms); uzun beklemeyi gerektiriyorsa null (tekrar denenmez). */
    private fun retryDelayMs(res: HttpResult, attempt: Int): Long? {
        val retryAfter = res.headers["retry-after"]?.trim()?.toIntOrNull()
        if (retryAfter != null) {
            if (retryAfter > MAX_RETRY_WAIT_SEC) return null
            return (if (retryAfter < 1) 1 else retryAfter) * 1000L
        }
        if (res.headers["x-ratelimit-remaining"] == "0") {
            val reset = res.headers["x-ratelimit-reset"]?.trim()?.toLongOrNull()
            if (reset != null) {
                val secs = reset - nowMs() / 1000
                if (secs > MAX_RETRY_WAIT_SEC) return null
                return (if (secs < 1) 1 else secs + 1) * 1000L
            }
        }
        return 2000L * (1 shl (attempt - 1)) // 2, 4 sn
    }

    private fun ioToApiException(e: IOException): GitHubApiException = when (e) {
        is InterruptedIOException -> // SocketTimeoutException dahil
            GitHubApiException(0, "İstek zaman aşımına uğradı (yavaş bağlantı veya çok büyük dosya). Bağlantınızı kontrol edip tekrar deneyin.")
        is UnknownHostException, is ConnectException, is SocketException ->
            GitHubApiException(0, "İnternet bağlantısı yok veya kesildi. Lütfen ağınızı kontrol edin.")
        is SSLException -> GitHubApiException(0, "Güvenli bağlantı (SSL) kurulamadı. Ağ ayarlarınızı kontrol edin.")
        else -> GitHubApiException(0, "Sunucuyla bağlantı kurulamadı. Lütfen tekrar deneyin.")
    }

    private suspend fun send(
        method: String,
        path: String,
        token: String,
        body: JsonElement? = null,
        timeoutMs: Long = DEFAULT_TIMEOUT_MS,
        retryIo: Boolean = method == "GET",
    ): HttpResult {
        checkToken(token)
        val url = "$BASE_URL$path"
        if (!url.startsWith("https://api.github.com/")) {
            throw GitHubApiException(0, "Güvenlik: yalnızca api.github.com adresine istek gönderilebilir.")
        }
        val encoded = body?.toString()
        var attempt = 1
        while (true) {
            val res: HttpResult = try {
                transport.execute(method, url, headers(token), encoded, timeoutMs)
            } catch (e: CancellationException) {
                throw e
            } catch (e: IOException) {
                // Tekrar denemesi güvenli (idempotent) isteklerde geçici ağ hatalarını/zaman aşımını yeniden dene.
                val transient = e is InterruptedIOException || e is SocketException ||
                    (e !is UnknownHostException && e !is SSLException)
                if (retryIo && transient && attempt < MAX_ATTEMPTS) {
                    sleep(2000L * (1 shl (attempt - 1)))
                    attempt++
                    continue
                }
                throw ioToApiException(e)
            }
            if (attempt < MAX_ATTEMPTS && isRateLimited(res)) {
                val wait = retryDelayMs(res, attempt) ?: return res
                sleep(wait)
                attempt++
                continue
            }
            return res
        }
    }

    // ───────────────────────── Hata biçimlendirme ─────────────────────────

    private fun messageFrom(rawBody: String): String =
        parseJson(rawBody).asObj?.get("message").asStr ?: ""

    private fun formatError(statusCode: Int, rawBody: String, workflowHint: Boolean = false): String {
        val msg = messageFrom(rawBody)
        val lower = msg.lowercase()
        if (lower.contains("workflow") && (lower.contains("scope") || lower.contains("permission"))) {
            return "Token'ınızda `workflow` yetkisi yok; ayarlardan güncelleyin " +
                "(.github/workflows/ altına dosya göndermek için gerekli)."
        }
        return when (statusCode) {
            401 -> "Token geçersiz veya süresi dolmuş. Lütfen ayarları kontrol edin."
            403 ->
                if (lower.contains("rate limit") || lower.contains("abuse")) {
                    "GitHub API istek limiti aşıldı; birkaç dakika bekleyip tekrar deneyin."
                } else {
                    "Yetki yetersiz ($msg)."
                }
            404 ->
                if (workflowHint) {
                    "Depo, dal veya dosya yolu bulunamadı. .github/workflows/ dosyası " +
                        "gönderiyorsanız token'ınızda `workflow` yetkisi olmayabilir."
                } else {
                    "Depo, dal veya dosya yolu bulunamadı."
                }
            409 -> "Boş depo veya dal çakışması tespit edildi. Depo başlatılmamış olabilir."
            422 -> "Doğrulama hatası ($msg). Lütfen girdi verilerini kontrol edin."
            else ->
                if (msg.isEmpty()) {
                    "Sunucuyla iletişim kurulurken beklenmeyen hata oluştu (Kod: $statusCode)."
                } else {
                    "GitHub API hatası (Kod: $statusCode): $msg"
                }
        }
    }

    private fun apiError(res: HttpResult, workflowHint: Boolean = false) =
        GitHubApiException(res.code, formatError(res.code, res.body, workflowHint))

    private fun jsonObj(res: HttpResult): JsonObject =
        parseJson(res.body).asObj ?: throw GitHubApiException(res.code, "GitHub yanıtı okunamadı.")

    // ───────────────────────── Girdi doğrulama ─────────────────────────

    private fun repoPath(owner: String, repo: String): String {
        fun bad(v: String) = !nameRe.matches(v) || v == "." || v == ".."
        if (bad(owner)) throw GitHubApiException(0, "Geçersiz depo sahibi adı.")
        if (bad(repo)) throw GitHubApiException(0, "Geçersiz depo adı.")
        return "/repos/${encodeComponent(owner)}/${encodeComponent(repo)}"
    }

    private fun checkToken(token: String) {
        if (!tokenRe.matches(token)) {
            throw GitHubApiException(401, "Token geçersiz karakterler içeriyor. Lütfen yeniden kopyalayıp yapıştırın.")
        }
    }

    private fun isEmptyRepo(res: HttpResult) = res.code == 409 && res.body.lowercase().contains("empty")

    // ───────────────────────── Kullanıcı / depo / dal ─────────────────────────

    suspend fun verifyUser(token: String): JsonObject {
        val res = send("GET", "/user", token)
        if (res.code == 200) return jsonObj(res)
        throw apiError(res)
    }

    suspend fun getRepositories(token: String): List<GitHubRepo> {
        val all = ArrayList<GitHubRepo>()
        var page = 1
        val perPage = 100
        while (true) {
            val res = send("GET", "/user/repos?per_page=$perPage&page=$page&sort=updated", token)
            if (res.code != 200) throw apiError(res)
            val list = parseJson(res.body).asArr ?: JsonArray(emptyList())
            if (list.isEmpty()) break
            list.forEach { r -> r.asObj?.let { all.add(GitHubRepo.fromJson(it)) } }
            if (list.size < perPage) break
            page++
        }
        return all
    }

    suspend fun getBranches(token: String, owner: String, repo: String): List<GitHubBranch> {
        val res = send("GET", "${repoPath(owner, repo)}/branches?per_page=100", token)
        if (res.code == 200) {
            val list = parseJson(res.body).asArr ?: return emptyList()
            return list.mapNotNull { it.asObj?.let { o -> GitHubBranch.fromJson(o) } }
        }
        throw apiError(res)
    }

    suspend fun createRepository(token: String, name: String, isPrivate: Boolean): GitHubRepo {
        val res = send(
            "POST", "/user/repos", token,
            body = buildJsonObject {
                put("name", name)
                put("private", isPrivate)
                put("auto_init", true) // İlk commit otomatik atılsın
            },
        )
        if (res.code == 201) return GitHubRepo.fromJson(jsonObj(res))
        throw apiError(res)
    }

    suspend fun createBranch(token: String, owner: String, repo: String, newBranch: String, sourceSha: String) {
        val res = send(
            "POST", "${repoPath(owner, repo)}/git/refs", token,
            body = buildJsonObject {
                put("ref", "refs/heads/$newBranch")
                put("sha", sourceSha)
            },
        )
        if (res.code != 201) throw apiError(res)
    }

    suspend fun deleteBranch(token: String, owner: String, repo: String, branch: String) {
        val res = send("DELETE", "${repoPath(owner, repo)}/git/refs/heads/${encodePath(branch)}", token)
        if (res.code != 204) throw apiError(res)
    }

    // ───────────────────────── Git Data yardımcıları ─────────────────────────

    /** Dalın HEAD commit SHA'sı; dal yoksa veya depo boşsa null. */
    private suspend fun getBranchHeadSha(token: String, owner: String, repo: String, branch: String): String? {
        val res = send("GET", "${repoPath(owner, repo)}/git/ref/heads/${encodePath(branch)}", token)
        if (res.code == 200) {
            return jsonObj(res)["object"].asObj?.get("sha").asStr
                ?: throw GitHubApiException(200, "Dal bilgisi okunamadı.")
        }
        if (res.code == 404 || isEmptyRepo(res)) return null
        throw apiError(res)
    }

    private suspend fun getCommitTreeSha(token: String, owner: String, repo: String, commitSha: String): String {
        val res = send("GET", "${repoPath(owner, repo)}/git/commits/$commitSha", token)
        if (res.code != 200) throw apiError(res)
        return jsonObj(res)["tree"].asObj?.get("sha").asStr
            ?: throw GitHubApiException(200, "Commit ağaç bilgisi okunamadı.")
    }

    private suspend fun getTreeRecursive(token: String, owner: String, repo: String, treeSha: String): RepoTreeResult {
        val res = send("GET", "${repoPath(owner, repo)}/git/trees/$treeSha?recursive=1", token, timeoutMs = BLOB_TIMEOUT_MS)
        if (res.code == 200) {
            val data = jsonObj(res)
            val list = (data["tree"].asArr ?: JsonArray(emptyList())).mapNotNull { e ->
                val o = e.asObj ?: return@mapNotNull null
                val path = o["path"].asStr ?: return@mapNotNull null
                TreeEntry(
                    path = path,
                    type = o["type"].asStr ?: "blob",
                    sha = o["sha"].asStr,
                    mode = o["mode"].asStr,
                    size = o["size"].asLong ?: 0L,
                )
            }
            return RepoTreeResult(list, data["truncated"].asBool == true)
        }
        if (isEmptyRepo(res)) return RepoTreeResult.empty()
        throw apiError(res)
    }

    /** Dalın tüm ağacı (özyinelemeli). Boş depo/yeni dal için boş sonuç. */
    suspend fun getRecursiveTree(token: String, owner: String, repo: String, branch: String): RepoTreeResult {
        val commitSha = getBranchHeadSha(token, owner, repo, branch) ?: return RepoTreeResult.empty()
        val treeSha = getCommitTreeSha(token, owner, repo, commitSha)
        return getTreeRecursive(token, owner, repo, treeSha)
    }

    suspend fun createBlob(
        token: String,
        owner: String,
        repo: String,
        bytes: ByteArray,
        workflowHint: Boolean = false,
    ): String {
        val res = send(
            "POST", "${repoPath(owner, repo)}/git/blobs", token,
            body = buildJsonObject {
                put("content", Base64.encodeToString(bytes, Base64.NO_WRAP))
                put("encoding", "base64")
            },
            timeoutMs = blobTimeoutMs(bytes.size),
            retryIo = true, // blob oluşturma içerik-adresli olduğundan tekrar denemek güvenlidir
        )
        if (res.code == 201) {
            return jsonObj(res)["sha"].asStr ?: throw GitHubApiException(201, "Blob yanıtı okunamadı.")
        }
        throw apiError(res, workflowHint)
    }

    private fun commitBody(message: String, tree: String, parent: String?, name: String?, email: String?): JsonObject {
        val n = name?.trim() ?: ""
        val e = email?.trim() ?: ""
        return buildJsonObject {
            put("message", message)
            put("tree", tree)
            put("parents", JsonArray(if (parent != null) listOf(kotlinx.serialization.json.JsonPrimitive(parent)) else emptyList()))
            if (n.isNotEmpty() && e.isNotEmpty()) {
                val who = buildJsonObject { put("name", n); put("email", e) }
                put("author", who)
                put("committer", who)
            }
        }
    }

    // ───────────────────────── Atomik push ─────────────────────────

    /**
     * Seçili dosyaları (ve onaylı silmeleri) TEK commit olarak gönderir.
     * Güvenlik: yol doğrulama, gizli bilgi taraması, klasör/dosya çakışması, beklenmedik dosya kaybı
     * denetimi (yeni ağaç eski ağaçla karşılaştırılır) ve `force:false` ref güncellemesi.
     */
    suspend fun executeAtomicPush(
        token: String,
        owner: String,
        repo: String,
        branch: String,
        commitMessage: String,
        filesToPush: List<GitFileItem>,
        approvedDeletePaths: Set<String> = emptySet(),
        authorName: String? = null,
        authorEmail: String? = null,
        onProgress: (step: String, current: Int, total: Int) -> Unit,
    ): PushResult {
        val planned = ArrayList<PlannedFile>()
        val requestedDeletes = ArrayList<String>()
        val seen = LinkedHashSet<String>()
        var skipped = 0

        // 1) Yerel doğrulama
        for (item in filesToPush) {
            if (item.status == GitFileStatus.Unchanged) {
                skipped++
                continue
            }
            if (item.status == GitFileStatus.Conflict) {
                throw GitHubApiException(0, "Çakışan dosya var (${item.targetPath}): ${item.conflictMessage ?: "çakışma"}")
            }
            val v = normalizeAndValidateGitPath(item.targetPath)
            if (!v.isValid) throw GitHubApiException(0, "Geçersiz dosya yolu (${item.targetPath}): ${v.error}")
            if (!seen.add(v.normalizedPath.lowercase())) {
                throw GitHubApiException(0, "Aynı yola giden birden fazla dosya var: ${v.normalizedPath}")
            }
            if (item.status == GitFileStatus.Delete) {
                if (!approvedDeletePaths.contains(v.normalizedPath)) {
                    throw GitHubApiException(0, "Onaylanmamış silme işlemi engellendi: ${v.normalizedPath}")
                }
                requestedDeletes.add(v.normalizedPath)
                continue
            }
            val bytes = item.bytes ?: throw GitHubApiException(0, "Dosya içeriği okunamadı: ${v.normalizedPath}")
            if (bytes.size > MAX_BLOB_BYTES) {
                throw GitHubApiException(0, "50 MB üstü dosya gönderilemez: ${v.normalizedPath}")
            }
            planned.add(PlannedFile(item, v.normalizedPath, bytes))
        }

        // Aynı gönderimde bir yol hem dosya hem klasör olamaz
        for (key in seen) {
            var idx = key.lastIndexOf('/')
            while (idx > 0) {
                val parent = key.substring(0, idx)
                if (seen.contains(parent)) {
                    throw GitHubApiException(0, "Aynı gönderimde \"$parent\" hem dosya hem klasör olarak kullanılıyor.")
                }
                idx = parent.lastIndexOf('/')
            }
        }

        // 2) Gizli bilgi taraması
        val secretFindings = SecretGuard.scan(planned.map { SecretCandidate(it.path, it.bytes) })
        if (secretFindings.isNotEmpty()) throw GitHubApiException(0, SecretGuard.formatError(secretFindings))

        val progressTotal = filesToPush.size
        val touchesWorkflows = planned.any { it.path.startsWith(".github/workflows/") } ||
            requestedDeletes.any { it.startsWith(".github/workflows/") }

        // 3) Dal ve taban ağaç
        onProgress("Branch bilgisi alınıyor...", 0, progressTotal)
        val parentSha = getBranchHeadSha(token, owner, repo, branch)
        var baseTreeSha: String? = null
        var baseIndex: RepoTreeIndex? = null
        var baseTruncated = false
        val warnings = ArrayList<String>()
        if (parentSha != null) {
            baseTreeSha = getCommitTreeSha(token, owner, repo, parentSha)
            val baseTree = getTreeRecursive(token, owner, repo, baseTreeSha)
            baseTruncated = baseTree.truncated
            baseIndex = RepoTreeIndex.fromEntries(baseTree.entries)
            if (baseTruncated) {
                warnings.add(
                    "Repo ağacı çok büyük olduğu için kesildi; çakışma ve dosya kaybı " +
                        "denetimleri sınırlı yapıldı.",
                )
            }
        }

        // 4) Klasör/dosya çakışması (taban ağaçla)
        if (baseIndex != null && !baseTruncated) {
            for (p in planned) {
                val node = baseIndex.nodes[p.path]
                if (node != null && node.isTree) {
                    throw GitHubApiException(
                        0,
                        "Bu yol bir klasör; dosya adı ekleyin: ${p.path}. Klasörün içeriği silinmemesi için işlem iptal edildi.",
                    )
                }
                val ancestor = baseIndex.findFileAncestor(p.path)
                if (ancestor != null) {
                    throw GitHubApiException(0, "Üst yol \"$ancestor\" repoda bir dosya; \"${p.path}\" oluşturulamaz.")
                }
            }
        }

        // 5) Silmeleri doğrula
        val deletePaths = ArrayList<String>()
        for (path in requestedDeletes) {
            if (baseIndex == null) {
                skipped++ // yeni dal / boş repo: silinecek bir şey yok
                continue
            }
            if (baseTruncated) {
                throw GitHubApiException(0, "Repo ağacı kesildiği için silme işlemi doğrulanamıyor; işlem iptal edildi.")
            }
            val node = baseIndex.nodes[path]
            if (node == null) {
                skipped++ // zaten yok
                continue
            }
            if (!node.isBlob) {
                throw GitHubApiException(0, "Silinmek istenen yol bir dosya değil ($path); klasör silinmez.")
            }
            deletePaths.add(path)
        }

        // 6) Değişmeyenleri ele (yerel sha == uzak sha)
        val toUpload = ArrayList<PlannedFile>()
        for (p in planned) {
            val node: RepoNode? = baseIndex?.nodes?.get(p.path)
            val blobNode = if (node != null && node.isBlob) node else null
            var knownSha = blobNode?.sha
            if (baseTruncated && knownSha == null) knownSha = p.item.remoteSha
            val localSha = p.item.computedSha ?: calculateGitBlobSha(p.bytes)
            if (knownSha != null && knownSha == localSha) {
                skipped++
                continue
            }
            p.existed = blobNode != null || (baseTruncated && p.item.remoteSha != null)
            p.mode = blobNode?.mode ?: p.item.remoteMode ?: defaultMode(p.path)
            toUpload.add(p)
        }

        if (toUpload.isEmpty() && deletePaths.isEmpty()) {
            onProgress("Değişiklik yok", progressTotal, progressTotal)
            return PushResult(noChanges = true, skipped = skipped, warnings = warnings)
        }

        // 7) Metin dosyaları ağaç isteğine satır içi (content) konur -> dosya başına ayrı istek yok.
        //    Yalnızca ikili / boş / geçerli UTF-8 olmayan dosyalar blob olarak yüklenir.
        //    (1000+ dosyalı projelerde tek tek blob isteği GitHub'ın içerik oluşturma sınırına takılıyordu.)
        val inlineTexts = arrayOfNulls<String>(toUpload.size)
        val blobIdx = ArrayList<Int>()
        for (j in toUpload.indices) {
            val text = decodeInlineText(toUpload[j].bytes)
            if (text != null) inlineTexts[j] = text else blobIdx.add(j)
        }

        val workTotal = toUpload.size
        val blobShas = arrayOfNulls<String>(toUpload.size)
        val processed = AtomicInteger(toUpload.size - blobIdx.size)
        onProgress("Dosyalar hazırlanıyor (${processed.get()}/$workTotal)", processed.get(), workTotal)
        val paced = blobIdx.size > BLOB_PACING_FREE
        var bi = 0
        while (bi < blobIdx.size) {
            // Büyük dosyalar bant genişliğini paylaşıp zaman aşımına düşmesin diye tek tek yüklenir.
            val first = blobIdx[bi]
            var end = bi + 1
            var batchBytes = toUpload[first].bytes.size.toLong()
            while (!paced && end < blobIdx.size && end - bi < BLOB_CONCURRENCY &&
                batchBytes + toUpload[blobIdx[end]].bytes.size <= PARALLEL_BATCH_BYTES
            ) {
                batchBytes += toUpload[blobIdx[end]].bytes.size
                end++
            }
            coroutineScope {
                (bi until end).map { k ->
                    async {
                        val j = blobIdx[k]
                        blobShas[j] = createBlob(token, owner, repo, toUpload[j].bytes, workflowHint = touchesWorkflows)
                        val n = processed.incrementAndGet()
                        onProgress("Dosyalar yükleniyor ($n/$workTotal)", n, workTotal)
                    }
                }.awaitAll()
            }
            bi = end
            if (paced && bi < blobIdx.size) sleep(BLOB_PACING_MS)
        }

        // 8) Ağaç (parça parça, her parça bir öncekinin üstüne kurulur)
        class TreeItem(val json: JsonObject, val weight: Long)
        val treeItems = ArrayList<TreeItem>()
        for (j in toUpload.indices) {
            val text = inlineTexts[j]
            val sha = blobShas[j]
            treeItems.add(
                TreeItem(
                    buildJsonObject {
                        put("path", toUpload[j].path)
                        put("mode", toUpload[j].mode)
                        put("type", "blob")
                        if (text != null) put("content", text) else put("sha", sha)
                    },
                    if (text != null) toUpload[j].bytes.size.toLong() + 200 else 200,
                ),
            )
        }
        for (path in deletePaths) {
            treeItems.add(
                TreeItem(
                    buildJsonObject {
                        put("path", path)
                        put("mode", "100644")
                        put("type", "blob")
                        put("sha", JsonNull) // silme
                    },
                    200,
                ),
            )
        }

        if (parentSha != null && baseTreeSha == null) {
            throw GitHubApiException(0, "Base tree alınamadı; repo dosyalarının silinmemesi için işlem iptal edildi.")
        }

        val chunks = ArrayList<List<JsonObject>>()
        run {
            var cur = ArrayList<JsonObject>()
            var curBytes = 0L
            for (t in treeItems) {
                if (cur.isNotEmpty() && (cur.size >= TREE_CHUNK_ENTRIES || curBytes + t.weight > TREE_CHUNK_BYTES)) {
                    chunks.add(cur)
                    cur = ArrayList()
                    curBytes = 0L
                }
                cur.add(t.json)
                curBytes += t.weight
            }
            if (cur.isNotEmpty()) chunks.add(cur)
        }

        var newTreeSha: String? = baseTreeSha
        for ((ci, chunk) in chunks.withIndex()) {
            onProgress("Git ağacı oluşturuluyor (${ci + 1}/${chunks.size})...", workTotal, workTotal)
            val treeBody = buildJsonObject {
                put("tree", JsonArray(chunk))
                if (newTreeSha != null) put("base_tree", newTreeSha)
            }
            val treeRes = send("POST", "${repoPath(owner, repo)}/git/trees", token, body = treeBody, timeoutMs = BLOB_TIMEOUT_MS)
            if (treeRes.code != 201) throw apiError(treeRes, touchesWorkflows)
            newTreeSha = jsonObj(treeRes)["sha"].asStr ?: throw GitHubApiException(201, "Ağaç yanıtı okunamadı.")
            if (ci < chunks.size - 1) sleep(1000) // içerik oluşturan istekler arasında nefes payı
        }
        val finalTreeSha = newTreeSha ?: throw GitHubApiException(0, "Git ağacı oluşturulamadı.")

        // 9) Güvenlik ağı: eski ağaçtaki hiçbir dosya onaysız kaybolmamalı
        if (baseIndex != null && !baseTruncated) {
            onProgress("Güvenlik denetimi yapılıyor...", workTotal, workTotal)
            val newTree = getTreeRecursive(token, owner, repo, finalTreeSha)
            if (newTree.truncated) {
                warnings.add("Yeni ağaç çok büyük olduğu için kesildi; dosya kaybı denetimi atlandı.")
            } else {
                val newIndex = RepoTreeIndex.fromEntries(newTree.entries)
                val approved = deletePaths.toSet()
                val unexpected = ArrayList<String>()
                for (path in baseIndex.nonTreePaths) {
                    val node = newIndex.nodes[path]
                    val lost = node == null || node.isTree
                    if (lost && !approved.contains(path)) unexpected.add(path)
                }
                if (unexpected.isNotEmpty()) {
                    throw GitHubApiException(
                        0,
                        "${unexpected.size} dosya beklenmedik şekilde silinecekti, işlem iptal edildi. " +
                            "Repoda hiçbir değişiklik yapılmadı.",
                        kind = GitHubApiException.KIND_SAFETY_NET,
                    )
                }
            }
        }

        // 10) Commit
        onProgress("Commit atılıyor...", workTotal, workTotal)
        val commitRes = send(
            "POST", "${repoPath(owner, repo)}/git/commits", token,
            body = commitBody(commitMessage, finalTreeSha, parentSha, authorName, authorEmail),
        )
        if (commitRes.code != 201) throw apiError(commitRes)
        val newCommitSha = jsonObj(commitRes)["sha"].asStr ?: throw GitHubApiException(201, "Commit yanıtı okunamadı.")

        // 11) Ref (force:false -> dal arada değiştiyse 422, hiçbir şey ezilmez)
        onProgress("Branch güncelleniyor...", workTotal, workTotal)
        if (parentSha != null) {
            val refRes = send(
                "PATCH", "${repoPath(owner, repo)}/git/refs/heads/${encodePath(branch)}", token,
                body = buildJsonObject { put("sha", newCommitSha); put("force", false) },
            )
            if (refRes.code != 200) {
                if (refRes.code == 422) {
                    throw GitHubApiException(
                        422, "Dal siz işlem yaparken değişti; yenileyip tekrar deneyin.",
                        kind = GitHubApiException.KIND_BRANCH_MOVED,
                    )
                }
                throw apiError(refRes)
            }
        } else {
            val refRes = send(
                "POST", "${repoPath(owner, repo)}/git/refs", token,
                body = buildJsonObject { put("ref", "refs/heads/$branch"); put("sha", newCommitSha) },
            )
            if (refRes.code != 201) {
                if (refRes.code == 422) {
                    throw GitHubApiException(
                        422, "Dal siz işlem yaparken oluşturuldu; yenileyip tekrar deneyin.",
                        kind = GitHubApiException.KIND_BRANCH_MOVED,
                    )
                }
                throw apiError(refRes)
            }
        }

        onProgress("Tamamlandı!", workTotal, workTotal)
        return PushResult(
            commitSha = newCommitSha,
            added = toUpload.count { !it.existed },
            updated = toUpload.count { it.existed },
            deleted = deletePaths.size,
            skipped = skipped,
            warnings = warnings,
        )
    }

    // ───────────────────────── Actions ─────────────────────────

    suspend fun getActionRuns(token: String, owner: String, repo: String): List<ActionRun> {
        val res = send("GET", "${repoPath(owner, repo)}/actions/runs?per_page=20", token)
        if (res.code == 200) {
            val runs = jsonObj(res)["workflow_runs"].asArr ?: JsonArray(emptyList())
            return runs.mapNotNull { it.asObj?.let { o -> ActionRun.fromJson(o) } }
        }
        throw apiError(res)
    }

    suspend fun triggerWorkflow(token: String, owner: String, repo: String, workflowIdOrFileName: String, ref: String) {
        val res = send(
            "POST",
            "${repoPath(owner, repo)}/actions/workflows/${encodeComponent(workflowIdOrFileName)}/dispatches",
            token,
            body = buildJsonObject { put("ref", ref) },
        )
        if (res.code != 204) throw apiError(res)
    }

    // ───────────────────────── Actions secret'ları ─────────────────────────

    private fun secretsError(res: HttpResult): GitHubApiException {
        if (res.code == 401 || isRateLimited(res)) return apiError(res)
        if (res.code == 403 || res.code == 404) {
            val detail = messageFrom(res.body).ifEmpty { "HTTP ${res.code}" }
            return GitHubApiException(
                res.code,
                "Bu depoda secret yönetilemedi. Token'da `repo` yetkisi ve depoda yazma/yönetici erişimi " +
                    "gerekir (fine-grained token için 'Secrets: Read and write'). Ayrıntı: $detail",
            )
        }
        return apiError(res)
    }

    suspend fun listActionSecrets(token: String, owner: String, repo: String): List<ActionSecret> {
        val res = send("GET", "${repoPath(owner, repo)}/actions/secrets?per_page=100", token)
        if (res.code != 200) throw secretsError(res)
        val arr = jsonObj(res)["secrets"].asArr ?: JsonArray(emptyList())
        return arr.mapNotNull { it.asObj?.let { o -> ActionSecret.fromJson(o) } }
            .sortedBy { it.name.lowercase() }
    }

    /**
     * Secret'ı depo açık anahtarıyla şifreleyip yazar (yoksa oluşturur, varsa üzerine yazar).
     * Değer cihazdan şifrelenmeden çıkmaz. Dönüş: true = yeni oluşturuldu, false = güncellendi.
     */
    suspend fun putActionSecret(token: String, owner: String, repo: String, name: String, value: String): Boolean {
        SecretRules.validateName(name)?.let { throw GitHubApiException(0, it) }
        SecretRules.validateValue(value)?.let { throw GitHubApiException(0, it) }
        val base = repoPath(owner, repo)

        val keyRes = send("GET", "$base/actions/secrets/public-key", token)
        if (keyRes.code != 200) throw secretsError(keyRes)
        val keyJson = jsonObj(keyRes)
        val keyId = keyJson["key_id"].asStr
        val keyB64 = keyJson["key"].asStr
        if (keyId == null || keyB64 == null) throw GitHubApiException(keyRes.code, "GitHub açık anahtarı okunamadı.")
        val publicKey = try {
            Base64.decode(keyB64, Base64.DEFAULT)
        } catch (e: IllegalArgumentException) {
            ByteArray(0)
        }
        if (publicKey.size != 32) throw GitHubApiException(0, "GitHub açık anahtarı geçersiz.")

        val sealed = SealedBox.seal(value.toByteArray(Charsets.UTF_8), publicKey)
        val res = send(
            "PUT",
            "$base/actions/secrets/${encodeComponent(SecretRules.normalizeName(name))}",
            token,
            body = buildJsonObject {
                put("encrypted_value", Base64.encodeToString(sealed, Base64.NO_WRAP))
                put("key_id", keyId)
            },
        )
        if (res.code != 201 && res.code != 204) throw secretsError(res)
        return res.code == 201
    }

    suspend fun deleteActionSecret(token: String, owner: String, repo: String, name: String) {
        SecretRules.validateName(name)?.let { throw GitHubApiException(0, it) }
        val res = send("DELETE", "${repoPath(owner, repo)}/actions/secrets/${encodeComponent(SecretRules.normalizeName(name))}", token)
        if (res.code != 204) throw secretsError(res)
    }

    // ───────────────────────── Dosya işlemleri ─────────────────────────

    suspend fun deleteSingleFile(
        token: String, owner: String, repo: String, path: String, branch: String, sha: String, message: String,
    ) {
        val res = send(
            "DELETE", "${repoPath(owner, repo)}/contents/${encodePath(path)}", token,
            body = buildJsonObject { put("message", message); put("sha", sha); put("branch", branch) },
        )
        if (res.code != 200) throw apiError(res)
    }

    /** Blob içeriği (SHA ile). Boyut sınırı aşılırsa indirilmeden hata verilir. */
    suspend fun getBlobBytes(
        token: String, owner: String, repo: String, sha: String, maxBytes: Long = 100L * 1024 * 1024,
    ): ByteArray {
        if (!shaRe.matches(sha)) throw GitHubApiException(0, "Geçersiz dosya SHA değeri.")
        val res = send("GET", "${repoPath(owner, repo)}/git/blobs/$sha", token, timeoutMs = BLOB_MAX_TIMEOUT_MS, retryIo = true)
        if (res.code != 200) throw apiError(res)
        val data = jsonObj(res)
        val size = data["size"].asLong
        if (size != null && size > maxBytes) throw GitHubApiException(0, "Dosya önizleme sınırından büyük.")
        val content = data["content"].asStr
        if (data["encoding"].asStr != "base64" || content == null) {
            throw GitHubApiException(200, "Dosya içeriği okunamadı.")
        }
        return try {
            Base64.decode(content.replace(Regex("\\s"), ""), Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            throw GitHubApiException(200, "Dosya içeriği çözülemedi.")
        }
    }

    suspend fun getLastCommitForPath(
        token: String, owner: String, repo: String, branch: String, path: String,
    ): PathCommitInfo? {
        val res = send(
            "GET",
            "${repoPath(owner, repo)}/commits?sha=${encodeQueryComponent(branch)}" +
                "&path=${encodeQueryComponent(path)}&per_page=1",
            token,
        )
        if (res.code == 200) {
            val first = parseJson(res.body).asArr?.firstOrNull().asObj ?: return null
            return PathCommitInfo.fromJson(first)
        }
        if (res.code == 404 || isEmptyRepo(res)) return null
        throw apiError(res)
    }

    suspend fun getCommits(
        token: String, owner: String, repo: String, branch: String,
        path: String? = null, page: Int = 1, perPage: Int = 30,
    ): List<PathCommitInfo> {
        val q = StringBuilder("?sha=${encodeQueryComponent(branch)}&per_page=$perPage&page=$page")
        if (!path.isNullOrEmpty()) q.append("&path=${encodeQueryComponent(path)}")
        val res = send("GET", "${repoPath(owner, repo)}/commits$q", token)
        if (res.code == 200) {
            val arr = parseJson(res.body).asArr ?: return emptyList()
            return arr.mapNotNull { it.asObj?.let { o -> PathCommitInfo.fromJson(o) } }
        }
        if (isEmptyRepo(res)) return emptyList()
        throw apiError(res)
    }

    suspend fun getRateLimit(token: String): RateLimitInfo {
        val res = send("GET", "/rate_limit", token)
        if (res.code == 200) return RateLimitInfo.fromJson(jsonObj(res))
        throw apiError(res)
    }

    // ───────────────────────── Tek commit'lik ağaç değişiklikleri ─────────────────────────

    /**
     * Mevcut dal üzerinde TEK commit: silme (sha == null), taşıma ve içerik değiştirme.
     * Dal arada değişirse (`force:false`) hiçbir şey ezilmez.
     */
    suspend fun commitTreeChanges(
        token: String,
        owner: String,
        repo: String,
        branch: String,
        message: String,
        entries: List<TreeChange>,
        authorName: String? = null,
        authorEmail: String? = null,
    ): String {
        if (entries.isEmpty()) throw GitHubApiException(0, "Yapılacak bir değişiklik yok.")
        if (entries.size > 1000) throw GitHubApiException(0, "Tek seferde en fazla 1000 dosya işlenebilir.")
        if (message.trim().isEmpty()) throw GitHubApiException(0, "Commit mesajı boş olamaz.")

        val seen = HashSet<String>()
        var touchesWorkflows = false
        for (e in entries) {
            val raw = e.path
            if (e.sha == null) {
                // Silme: repodaki gerçek yol (büyük/küçük harf korunur)
                if (!isSafeExistingPath(raw)) throw GitHubApiException(0, "Geçersiz dosya yolu: $raw")
            } else {
                val v = normalizeAndValidateGitPath(raw)
                if (!v.isValid || v.normalizedPath != raw) {
                    throw GitHubApiException(0, "Geçersiz dosya yolu ($raw): ${v.error ?: "normalleştirilemedi"}")
                }
            }
            if (!seen.add(raw)) throw GitHubApiException(0, "Aynı yol birden fazla kez geçiyor: $raw")
            if (raw.startsWith(".github/workflows/")) touchesWorkflows = true
            if (e.sha != null && !shaRe.matches(e.sha)) throw GitHubApiException(0, "Geçersiz SHA değeri: $raw")
        }

        val parentSha = getBranchHeadSha(token, owner, repo, branch)
            ?: throw GitHubApiException(404, "Dal bulunamadı: $branch")
        val baseTreeSha = getCommitTreeSha(token, owner, repo, parentSha)

        val treeJson = entries.map { e ->
            buildJsonObject {
                put("path", e.path)
                put("mode", e.mode)
                put("type", "blob")
                put("sha", e.sha)
            }
        }
        val treeRes = send(
            "POST", "${repoPath(owner, repo)}/git/trees", token,
            body = buildJsonObject {
                put("base_tree", baseTreeSha)
                put("tree", JsonArray(treeJson))
            },
        )
        if (treeRes.code != 201) throw apiError(treeRes, touchesWorkflows)
        val newTreeSha = jsonObj(treeRes)["sha"].asStr ?: throw GitHubApiException(201, "Ağaç yanıtı okunamadı.")

        val commitRes = send(
            "POST", "${repoPath(owner, repo)}/git/commits", token,
            body = commitBody(message, newTreeSha, parentSha, authorName, authorEmail),
        )
        if (commitRes.code != 201) throw apiError(commitRes)
        val newCommitSha = jsonObj(commitRes)["sha"].asStr ?: throw GitHubApiException(201, "Commit yanıtı okunamadı.")

        val refRes = send(
            "PATCH", "${repoPath(owner, repo)}/git/refs/heads/${encodePath(branch)}", token,
            body = buildJsonObject { put("sha", newCommitSha); put("force", false) },
        )
        if (refRes.code != 200) {
            if (refRes.code == 422) {
                throw GitHubApiException(
                    422,
                    "Dal siz işlem yaparken değişti; yenileyip tekrar deneyin. Hiçbir değişiklik yapılmadı.",
                    kind = GitHubApiException.KIND_BRANCH_MOVED,
                )
            }
            throw apiError(refRes)
        }
        return newCommitSha
    }

    suspend fun deletePathsInOneCommit(
        token: String, owner: String, repo: String, branch: String, message: String,
        paths: List<String>, authorName: String? = null, authorEmail: String? = null,
    ): String = commitTreeChanges(
        token, owner, repo, branch, message,
        paths.map { TreeChange(it, "100644", null) },
        authorName, authorEmail,
    )

    /** Taşıma/yeniden adlandırma: içerik yeniden yüklenmeden (aynı blob SHA) tek commit. */
    suspend fun movePathsInOneCommit(
        token: String, owner: String, repo: String, branch: String, message: String,
        moves: List<RepoMove>, authorName: String? = null, authorEmail: String? = null,
    ): String {
        val entries = ArrayList<TreeChange>()
        for (m in moves) {
            entries.add(TreeChange(m.from, m.mode, null))
            entries.add(TreeChange(m.to, m.mode, m.sha))
        }
        return commitTreeChanges(token, owner, repo, branch, message, entries, authorName, authorEmail)
    }

    /** Tek dosyanın içeriğini değiştirir/oluşturur (uygulama içi düzenleyici). */
    suspend fun commitFileContent(
        token: String, owner: String, repo: String, branch: String, path: String,
        bytes: ByteArray, message: String, mode: String? = null,
        authorName: String? = null, authorEmail: String? = null,
    ): String {
        if (bytes.size > MAX_BLOB_BYTES) throw GitHubApiException(0, "50 MB üstü dosya gönderilemez.")
        val v = normalizeAndValidateGitPath(path)
        if (!v.isValid) throw GitHubApiException(0, v.error ?: "Geçersiz dosya yolu.")
        val findings = SecretGuard.scan(listOf(SecretCandidate(v.normalizedPath, bytes)))
        if (findings.isNotEmpty()) throw GitHubApiException(0, SecretGuard.formatError(findings))

        val blobSha = createBlob(
            token, owner, repo, bytes,
            workflowHint = v.normalizedPath.startsWith(".github/workflows/"),
        )
        return commitTreeChanges(
            token, owner, repo, branch, message,
            listOf(TreeChange(v.normalizedPath, mode ?: defaultMode(v.normalizedPath), blobSha)),
            authorName, authorEmail,
        )
    }
}
