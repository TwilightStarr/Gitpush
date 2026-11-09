package com.example.gitpush.model

import com.example.gitpush.util.appendFileNameIfFolder
import com.example.gitpush.util.asBool
import com.example.gitpush.util.asInt
import com.example.gitpush.util.asLong
import com.example.gitpush.util.asObj
import com.example.gitpush.util.asStr
import com.example.gitpush.util.parseJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.time.Instant
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger

fun parseIsoMillis(s: String?): Long? =
    if (s == null) null else try { Instant.parse(s).toEpochMilli() } catch (_: Exception) { null }

// ───────────────────────── Actions ─────────────────────────

class ActionRun(
    val id: Long,
    val name: String,
    val headBranch: String,
    val headSha: String,
    val status: String, // queued, in_progress, waiting, pending, completed
    val conclusion: String?, // success, failure, cancelled, timed_out, startup_failure
    val event: String,
    val htmlUrl: String,
    val createdAt: Long,
    val commitMessage: String,
) {
    val isCompleted get() = status == "completed"
    val isSuccess get() = conclusion == "success"
    val isFailed get() = conclusion == "failure"
    val isCancelled get() = conclusion == "cancelled"
    val isTimedOut get() = conclusion == "timed_out"
    val isStartupFailure get() = conclusion == "startup_failure"
    val isRunning get() = !isCompleted
    val isQueued get() = status == "queued" || status == "waiting" || status == "pending" || status == "requested"

    val statusLabel: String
        get() {
            if (!isCompleted) return if (isQueued) "Sırada" else "Çalışıyor"
            if (isSuccess) return "Başarılı"
            if (isFailed) return "Başarısız"
            if (isCancelled) return "İptal edildi"
            if (isTimedOut) return "Zaman aşımı"
            if (isStartupFailure) return "Başlatılamadı"
            if (conclusion == "skipped") return "Atlandı"
            return conclusion ?: "Tamamlandı"
        }

    companion object {
        fun fromJson(json: JsonObject): ActionRun {
            val commit = json["head_commit"].asObj
            return ActionRun(
                id = json["id"].asLong ?: 0L,
                name = json["name"].asStr ?: "Workflow",
                headBranch = json["head_branch"].asStr ?: "main",
                headSha = json["head_sha"].asStr ?: "",
                status = json["status"].asStr ?: "queued",
                conclusion = json["conclusion"].asStr,
                event = json["event"].asStr ?: "push",
                htmlUrl = json["html_url"].asStr ?: "",
                createdAt = parseIsoMillis(json["created_at"].asStr) ?: System.currentTimeMillis(),
                commitMessage = commit?.get("message").asStr ?: "No commit message",
            )
        }
    }
}

// ───────────────────────── Commit / limit ─────────────────────────

class PathCommitInfo(
    val sha: String,
    val message: String,
    val authorName: String? = null,
    val date: Long? = null,
    val htmlUrl: String? = null,
) {
    val title: String
        get() {
            val i = message.indexOf('\n')
            return (if (i == -1) message else message.substring(0, i)).trim()
        }

    companion object {
        fun fromJson(json: JsonObject): PathCommitInfo {
            val commit = json["commit"].asObj
            val author = commit?.get("author").asObj
            return PathCommitInfo(
                sha = json["sha"].asStr ?: "",
                message = commit?.get("message").asStr ?: "",
                authorName = author?.get("name").asStr,
                date = parseIsoMillis(author?.get("date").asStr),
                htmlUrl = json["html_url"].asStr,
            )
        }
    }
}

class RepoMove(val from: String, val to: String, val sha: String, val mode: String = "100644")

class RateLimitInfo(val limit: Int, val remaining: Int, val resetAt: Long? = null) {
    val used get() = limit - remaining

    companion object {
        fun fromJson(json: JsonObject): RateLimitInfo {
            val core = json["resources"].asObj?.get("core").asObj
            return RateLimitInfo(
                limit = core?.get("limit").asInt ?: 0,
                remaining = core?.get("remaining").asInt ?: 0,
                resetAt = core?.get("reset").asLong?.let { it * 1000 },
            )
        }
    }
}

class PushResult(
    val commitSha: String? = null,
    val added: Int = 0,
    val updated: Int = 0,
    val deleted: Int = 0,
    val skipped: Int = 0,
    val noChanges: Boolean = false,
    val warnings: List<String> = emptyList(),
) {
    val changedCount get() = added + updated + deleted
}

// ───────────────────────── Repo / branch ─────────────────────────

class GitHubRepo(
    val id: Long,
    val name: String,
    val fullName: String,
    val owner: String,
    val isPrivate: Boolean,
    val defaultBranch: String,
    val description: String? = null,
    val updatedAt: Long? = null,
    val isEmpty: Boolean = false,
) {
    companion object {
        fun fromJson(json: JsonObject) = GitHubRepo(
            id = json["id"].asLong ?: 0L,
            name = json["name"].asStr ?: "",
            fullName = json["full_name"].asStr ?: "",
            owner = json["owner"].asObj?.get("login").asStr ?: "",
            isPrivate = json["private"].asBool ?: false,
            defaultBranch = json["default_branch"].asStr ?: "main",
            description = json["description"].asStr,
            updatedAt = parseIsoMillis(json["updated_at"].asStr),
            isEmpty = json["size"].asLong == 0L,
        )
    }
}

class GitHubBranch(val name: String, val commitSha: String) {
    companion object {
        fun fromJson(json: JsonObject) = GitHubBranch(
            name = json["name"].asStr ?: "",
            commitSha = json["commit"].asObj?.get("sha").asStr ?: "",
        )
    }
}

// ───────────────────────── Geçmiş ─────────────────────────

class HistoryItem(
    val id: String,
    val repoFullName: String,
    val branch: String,
    val commitMessage: String,
    val commitSha: String,
    val filesCount: Int,
    val timestamp: Long,
    val commitUrl: String,
) {
    fun toJsonObject(): JsonObject = buildJsonObject {
        put("id", id)
        put("repoFullName", repoFullName)
        put("branch", branch)
        put("commitMessage", commitMessage)
        put("commitSha", commitSha)
        put("filesCount", filesCount)
        put("timestamp", Instant.ofEpochMilli(timestamp).toString())
        put("commitUrl", commitUrl)
    }

    companion object {
        fun fromJsonObject(o: JsonObject): HistoryItem? {
            return HistoryItem(
                id = o["id"].asStr ?: return null,
                repoFullName = o["repoFullName"].asStr ?: return null,
                branch = o["branch"].asStr ?: return null,
                commitMessage = o["commitMessage"].asStr ?: return null,
                commitSha = o["commitSha"].asStr ?: return null,
                filesCount = o["filesCount"].asInt ?: return null,
                timestamp = parseIsoMillis(o["timestamp"].asStr) ?: return null,
                commitUrl = o["commitUrl"].asStr ?: return null,
            )
        }

        fun fromJson(source: String): HistoryItem? = parseJson(source).asObj?.let { fromJsonObject(it) }
    }
}

// ───────────────────────── Gönderilecek dosya ─────────────────────────

enum class GitFileStatus {
    IsNew, // Repoda yok (Yeni)
    Update, // Repoda var, içerik farklı
    Delete, // Silinecek (yalnızca açıkça onaylanırsa)
    NewFolder, // Yeni klasör oluşturulacak
    Unchanged, // Değişmedi (yerel sha == uzak sha)
    Conflict, // Çakışma / geçersiz yol: push engellenir
}

class GitFileItem(
    id: Int? = null,
    val localPath: String,
    var repoPath: String,
    val size: Int,
    val bytes: ByteArray? = null,
    sourceName: String? = null,
    var isSelected: Boolean = true,
    var status: GitFileStatus = GitFileStatus.IsNew,
    /** Repo ağacıyla karşılaştırma yapıldı mı? */
    var statusKnown: Boolean = false,
    var computedSha: String? = null,
    var remoteSha: String? = null,
    var remoteMode: String? = null,
    var conflictMessage: String? = null,
    /** Repoda birden fazla eşleşme var; kullanıcı seçmeli. */
    var needsChoice: Boolean = false,
    /** Yol kullanıcı tarafından elle verildi; otomatik eşleştirme dokunmaz. */
    var pathManual: Boolean = false,
    var suggestions: List<String> = emptyList(),
) {
    val id: Int = id ?: nextId.getAndIncrement()
    val sourceName: String = sourceName ?: lastSegment(localPath)

    fun copyWith(repoPath: String? = null, isSelected: Boolean? = null, status: GitFileStatus? = null) =
        GitFileItem(
            id = id,
            localPath = localPath,
            repoPath = repoPath ?: this.repoPath,
            size = size,
            bytes = bytes,
            sourceName = sourceName,
            isSelected = isSelected ?: this.isSelected,
            status = status ?: this.status,
            statusKnown = statusKnown,
            computedSha = computedSha,
            remoteSha = remoteSha,
            remoteMode = remoteMode,
            conflictMessage = conflictMessage,
            needsChoice = needsChoice,
            pathManual = pathManual,
            suggestions = suggestions.toList(),
        )

    val fileName: String get() = sourceName

    /** Yol "/" ile bitiyorsa dosya adı eklenir. */
    val targetPath: String get() = appendFileNameIfFolder(repoPath, sourceName)

    val directoryPath: String
        get() {
            val idx = repoPath.lastIndexOf('/')
            return if (idx == -1) "" else repoPath.substring(0, idx + 1)
        }

    val formattedSize: String
        get() = when {
            size < 1024 -> "$size B"
            size < 1024 * 1024 -> String.format(Locale.US, "%.1f KB", size / 1024.0)
            else -> String.format(Locale.US, "%.1f MB", size / (1024.0 * 1024.0))
        }

    companion object {
        private val nextId = AtomicInteger(1)

        private fun lastSegment(path: String): String {
            val normalized = path.replace('\\', '/')
            val idx = normalized.lastIndexOf('/')
            return if (idx == -1) normalized else normalized.substring(idx + 1)
        }

        fun deletion(path: String) = GitFileItem(
            localPath = path,
            repoPath = path,
            size = 0,
            status = GitFileStatus.Delete,
            statusKnown = true,
        )
    }
}
