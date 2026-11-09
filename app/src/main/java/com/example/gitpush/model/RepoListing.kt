package com.example.gitpush.model

class RepoEntry(
    val name: String,
    val path: String,
    val isDir: Boolean,
    val isSubmodule: Boolean = false,
    /** Dosyada kendi boyutu; klasörde altındaki dosyaların toplamı. */
    val size: Long = 0,
    val fileCount: Int = 0,
    val folderCount: Int = 0,
    val sha: String? = null,
    val mode: String? = null,
) {
    val isHidden get() = name.startsWith(".")

    val extension: String
        get() {
            if (isDir) return ""
            val i = name.lastIndexOf('.')
            if (i <= 0 || i == name.length - 1) return ""
            return name.substring(i + 1).lowercase()
        }
}

class RepoCrumb(val label: String, val path: String)

fun breadcrumbsFor(dir: String, rootLabel: String = "Kök"): List<RepoCrumb> {
    val crumbs = arrayListOf(RepoCrumb(rootLabel, ""))
    if (dir.isEmpty()) return crumbs
    var acc = ""
    for (seg in dir.split('/')) {
        if (seg.isEmpty()) continue
        acc = if (acc.isEmpty()) seg else "$acc/$seg"
        crumbs.add(RepoCrumb(seg, acc))
    }
    return crumbs
}

/** Doğal sıralama: "a2" < "a10", büyük/küçük harf duyarsız. */
fun compareNatural(a: String, b: String): Int {
    val x = a.lowercase()
    val y = b.lowercase()
    var i = 0
    var j = 0
    val leadingZeros = Regex("^0+(?=\\d)")
    while (i < x.length && j < y.length) {
        val cx = x[i].code
        val cy = y[j].code
        val dx = cx in 48..57
        val dy = cy in 48..57
        if (dx && dy) {
            var ei = i
            while (ei < x.length && x[ei].code in 48..57) ei++
            var ej = j
            while (ej < y.length && y[ej].code in 48..57) ej++
            val nx = x.substring(i, ei).replaceFirst(leadingZeros, "")
            val ny = y.substring(j, ej).replaceFirst(leadingZeros, "")
            if (nx.length != ny.length) return nx.length.compareTo(ny.length)
            val c = nx.compareTo(ny)
            if (c != 0) return c
            i = ei
            j = ej
        } else {
            if (cx != cy) return cx.compareTo(cy)
            i++
            j++
        }
    }
    return (x.length - i).compareTo(y.length - j)
}

private class FolderAgg {
    var sha: String? = null
    var files = 0
    var folders = 0
    var size = 0L
}

/** Düz repo ağacından [dir] içindeki doğrudan girdileri çıkarır; klasörler her zaman üstte. */
fun buildDirectoryListing(
    tree: List<TreeEntry>,
    dir: String,
    sort: RepoSortMode = RepoSortMode.NameAsc,
    showHidden: Boolean = true,
): List<RepoEntry> {
    val prefix = if (dir.isEmpty()) "" else "$dir/"
    val folders = LinkedHashMap<String, FolderAgg>()
    val files = ArrayList<RepoEntry>()

    for (e in tree) {
        val path = e.path
        if (prefix.isNotEmpty() && !path.startsWith(prefix)) continue
        val rel = path.substring(prefix.length)
        if (rel.isEmpty()) continue
        val slash = rel.indexOf('/')

        if (slash == -1) {
            if (e.type == "tree") {
                folders.getOrPut(rel) { FolderAgg() }.sha = e.sha
            } else {
                files.add(
                    RepoEntry(
                        name = rel, path = path, isDir = false,
                        isSubmodule = e.type == "commit",
                        size = e.size, sha = e.sha, mode = e.mode,
                    ),
                )
            }
        } else {
            val top = rel.substring(0, slash)
            val agg = folders.getOrPut(top) { FolderAgg() }
            if (e.type == "tree") {
                agg.folders++
            } else {
                agg.files++
                agg.size += e.size
            }
        }
    }

    val dirs = folders.entries.map { f ->
        RepoEntry(
            name = f.key, path = prefix + f.key, isDir = true,
            size = f.value.size, fileCount = f.value.files, folderCount = f.value.folders,
            sha = f.value.sha,
        )
    }

    fun keep(e: RepoEntry) = showHidden || !e.isHidden
    val visibleDirs = dirs.filter(::keep).toMutableList()
    val visibleFiles = files.filter(::keep).toMutableList()

    val byName = Comparator<RepoEntry> { a, b -> compareNatural(a.name, b.name) }

    when (sort) {
        RepoSortMode.NameAsc -> {
            visibleDirs.sortWith(byName)
            visibleFiles.sortWith(byName)
        }
        RepoSortMode.NameDesc -> {
            val desc = Comparator<RepoEntry> { a, b -> byName.compare(b, a) }
            visibleDirs.sortWith(desc)
            visibleFiles.sortWith(desc)
        }
        RepoSortMode.SizeDesc -> {
            val bySize = Comparator<RepoEntry> { a, b ->
                val c = b.size.compareTo(a.size)
                if (c != 0) c else byName.compare(a, b)
            }
            visibleDirs.sortWith(bySize)
            visibleFiles.sortWith(bySize)
        }
        RepoSortMode.Extension -> {
            visibleDirs.sortWith(byName)
            visibleFiles.sortWith(Comparator { a, b ->
                val c = a.extension.compareTo(b.extension)
                if (c != 0) c else byName.compare(a, b)
            })
        }
    }
    return visibleDirs + visibleFiles
}

/** Depo genelinde yol araması: tam ad > önek > içerir; klasörler önce. */
fun searchRepoTree(
    tree: List<TreeEntry>,
    query: String,
    showHidden: Boolean = true,
    limit: Int = 300,
): List<RepoEntry> {
    val q = query.trim().lowercase()
    if (q.isEmpty()) return emptyList()

    val out = ArrayList<RepoEntry>()
    for (e in tree) {
        val path = e.path
        if (!path.lowercase().contains(q)) continue
        if (!showHidden && path.split('/').any { it.startsWith(".") }) continue
        val name = path.substring(path.lastIndexOf('/') + 1)
        out.add(
            RepoEntry(
                name = name, path = path, isDir = e.type == "tree",
                isSubmodule = e.type == "commit", size = e.size, sha = e.sha, mode = e.mode,
            ),
        )
    }

    fun rank(e: RepoEntry): Int {
        val n = e.name.lowercase()
        if (n == q) return 0
        if (n.startsWith(q)) return 1
        if (n.contains(q)) return 2
        return 3
    }

    out.sortWith(Comparator { a, b ->
        if (a.isDir != b.isDir) return@Comparator if (a.isDir) -1 else 1
        val r = rank(a).compareTo(rank(b))
        if (r != 0) r else compareNatural(a.path, b.path)
    })
    return if (out.size > limit) out.subList(0, limit) else out
}

/** [dir] altındaki tüm blob girdileri (klasör silme/taşıma için). */
fun blobsUnder(tree: List<TreeEntry>, dir: String): List<TreeEntry> {
    val prefix = "$dir/"
    return tree.filter { it.path.startsWith(prefix) && it.type == "blob" }
}

enum class PreviewKind { Text, Image, Binary }

private val imageExts = setOf("png", "jpg", "jpeg", "gif", "webp", "bmp")
private val binaryExts = setOf(
    "zip", "gz", "tgz", "rar", "7z", "jar", "aar", "apk", "aab", "so", "dll", "exe", "bin", "class", "dex",
    "pdf", "mp3", "mp4", "mov", "avi", "mkv", "wav", "ogg", "ttf", "otf", "woff", "woff2", "ico", "keystore", "jks",
    "psd", "sketch", "db", "sqlite", "o", "a",
)

fun previewKindFor(fileName: String): PreviewKind {
    val i = fileName.lastIndexOf('.')
    val ext = if (i <= 0) "" else fileName.substring(i + 1).lowercase()
    if (ext in imageExts) return PreviewKind.Image
    if (ext in binaryExts) return PreviewKind.Binary
    return PreviewKind.Text
}
