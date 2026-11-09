package com.example.gitpush.util

data class PathValidationResult(
    val isValid: Boolean,
    val error: String? = null,
    val normalizedPath: String,
)

private val invalidSegmentChars = Regex("[<>:\"|?*\\x00-\\x1F]")
private val multiSlash = Regex("/+")

/** Kullanıcı yolu "/" veya "\" ile bitiyorsa klasör olarak kastedilmiştir. */
fun endsWithPathSeparator(raw: String): Boolean {
    val t = raw.trim()
    return t.endsWith("/") || t.endsWith("\\")
}

/** Yol klasör gibi bitiyorsa dosya adını ekler; aksi halde yolu olduğu gibi döndürür. */
fun appendFileNameIfFolder(raw: String, fileName: String): String {
    if (fileName.isEmpty()) return raw
    val t = raw.trim()
    if (t.isEmpty()) return raw
    if (t.endsWith("/") || t.endsWith("\\")) return "$t$fileName"
    return raw
}

private fun invalid(error: String, normalized: String) =
    PathValidationResult(isValid = false, error = error, normalizedPath = normalized)

/** Git yolunu normalleştirir ve güvenlik açısından doğrular (.., .git, geçersiz karakter, uzunluk). */
fun normalizeAndValidateGitPath(rawPath: String): PathValidationResult {
    if (rawPath.trim().isEmpty()) return invalid("Dosya yolu boş olamaz.", "")

    var p = rawPath.trim().replace('\\', '/')
    p = p.replace(multiSlash, "/")
    p = p.trimStart('/')
    p = p.trimEnd('/')

    if (p.isEmpty()) return invalid("Dosya yolu yalnızca eğik çizgilerden oluşamaz.", "")

    for (seg in p.split('/')) {
        if (seg == "..") return invalid("Dosya yolunda \"..\" (üst dizin yönlendirmesi) kullanılamaz.", p)
        if (seg == ".") return invalid("Dosya yolunda geçersiz \".\" segmenti var.", p)
        if (seg.lowercase() == ".git") return invalid("Dosya yolunda \".git\" klasörü kullanılamaz.", p)
        if (invalidSegmentChars.containsMatchIn(seg)) {
            return invalid("Dosya adı geçersiz karakterler içeriyor ($seg).", p)
        }
    }
    if (p.length > 400) return invalid("Dosya yolu 400 karakter sınırını aşıyor.", p)
    return PathValidationResult(isValid = true, normalizedPath = p)
}

/** Büyük/küçük harf duyarsız yinelenen yolları döndürür. */
fun findDuplicatePaths(paths: List<String>): List<String> {
    val seen = HashSet<String>()
    val duplicates = LinkedHashSet<String>()
    for (raw in paths) {
        val norm = normalizeAndValidateGitPath(raw).normalizedPath.lowercase()
        if (!seen.add(norm)) duplicates.add(norm)
    }
    return duplicates.toList()
}

/** "a//b\\" -> "a/b/" ; boş girdi -> "" (repo kökü). */
fun normalizeFolderPrefix(raw: String): String {
    var p = raw.trim().replace('\\', '/')
    p = p.replace(multiSlash, "/")
    p = p.trimStart('/')
    p = p.trimEnd('/')
    return if (p.isEmpty()) "" else "$p/"
}
