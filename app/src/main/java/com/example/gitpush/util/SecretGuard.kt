package com.example.gitpush.util

class SecretCandidate(val path: String, val bytes: ByteArray)
class SecretFinding(val path: String, val reason: String)

/** Push öncesi gizli bilgi (token, özel anahtar, .env...) taraması. */
object SecretGuard {
    private const val MAX_SCAN_BYTES = 2 * 1024 * 1024

    private val envFile = Regex("""^\.env(\..+)?$""")
    private val safeEnvSuffix = Regex("""\.(example|sample|template|dist|defaults?)$""", RegexOption.IGNORE_CASE)
    private val keyFileExt = Regex("""\.(pem|p12|pfx|jks|keystore|ppk)$""")
    private val sshKey = Regex("""^id_(rsa|dsa|ecdsa|ed25519)$""")
    private val credJson = Regex("""^(service-?account|credentials?)[\w.-]*\.json$""")

    private val patterns: List<Pair<String, Regex>> = listOf(
        "GitHub token" to Regex("""\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b"""),
        "GitHub fine-grained token" to Regex("""\bgithub_pat_[A-Za-z0-9_]{50,}\b"""),
        "AWS access key" to Regex("""\bAKIA[0-9A-Z]{16}\b"""),
        "Google API key" to Regex("""\bAIza[0-9A-Za-z_-]{35}\b"""),
        "Anthropic API key" to Regex("""\bsk-ant-[A-Za-z0-9_-]{20,}\b"""),
        "Slack token" to Regex("""\bxox[baprs]-[A-Za-z0-9-]{10,}\b"""),
        "Özel anahtar (private key)" to Regex("""-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----"""),
    )

    fun isSensitiveFileName(path: String): Boolean {
        val base = path.substringAfterLast('/').lowercase()
        if (envFile.containsMatchIn(base)) return !safeEnvSuffix.containsMatchIn(base)
        if (keyFileExt.containsMatchIn(base)) return true
        if (sshKey.containsMatchIn(base)) return true
        if (base == "key.properties" || base == ".netrc" || base == ".pgpass") return true
        if (credJson.containsMatchIn(base)) return true
        return false
    }

    private fun looksBinary(bytes: ByteArray): Boolean {
        val n = if (bytes.size < 8000) bytes.size else 8000
        for (i in 0 until n) if (bytes[i].toInt() == 0) return true
        return false
    }

    fun scan(files: List<SecretCandidate>): List<SecretFinding> {
        val findings = ArrayList<SecretFinding>()
        for (f in files) {
            if (isSensitiveFileName(f.path)) {
                findings.add(SecretFinding(f.path, "Hassas dosya adı"))
                continue
            }
            if (f.bytes.size > MAX_SCAN_BYTES || looksBinary(f.bytes)) continue
            val text = String(f.bytes, Charsets.UTF_8) // hatalı baytlar U+FFFD olur (allowMalformed)
            for ((name, regex) in patterns) {
                if (regex.containsMatchIn(text)) {
                    findings.add(SecretFinding(f.path, name))
                    break
                }
            }
        }
        return findings
    }

    fun formatError(findings: List<SecretFinding>): String {
        val shown = findings.take(5).joinToString(", ") { "${it.path} (${it.reason})" }
        val more = if (findings.size > 5) " ve ${findings.size - 5} dosya daha" else ""
        return "Gizli bilgi içerebilecek dosya(lar) tespit edildi, push engellendi: " +
            "$shown$more. Bu dosyaları listeden çıkarın veya içindeki anahtarları " +
            "kaldırıp tekrar deneyin."
    }
}
