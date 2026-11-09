package com.example.gitpush.model

/** GitHub git/trees API girdisi. type: blob | tree | commit(submodule). */
data class TreeEntry(
    val path: String,
    val type: String,
    val sha: String? = null,
    val mode: String? = null,
    val size: Long = 0,
)

class RepoNode(
    val path: String,
    val type: String, // blob | tree | commit
    val sha: String? = null,
    val mode: String? = null,
) {
    val isTree get() = type == "tree"
    val isBlob get() = type == "blob"
}

class RepoTreeResult(val entries: List<TreeEntry>, val truncated: Boolean = false) {
    companion object {
        fun empty() = RepoTreeResult(emptyList(), false)
    }
}

/** Yol -> düğüm indeksi; çakışma ve eşleştirme sorguları için. */
class RepoTreeIndex(val nodes: Map<String, RepoNode>) {

    val nonTreePaths: List<String> get() = nodes.values.filter { !it.isTree }.map { it.path }

    fun findBlobsByName(name: String): List<String> {
        val exact = nodes.values
            .filter { it.isBlob && (it.path == name || it.path.endsWith("/$name")) }
            .map { it.path }
            .sorted()
        if (exact.isNotEmpty()) return exact

        val key = nameKey(name)
        return nodes.values
            .filter { it.isBlob && nameKey(lastSegment(it.path)) == key }
            .map { it.path }
            .sorted()
    }

    private val lowerBlobs: Map<String, List<String>> by lazy {
        val map = HashMap<String, MutableList<String>>()
        for (n in nodes.values) {
            if (n.isBlob) map.getOrPut(n.path.lowercase()) { ArrayList() }.add(n.path)
        }
        map
    }

    /** Tam eşleşen blob; yoksa harf büyüklüğü farkıyla TEK eşleşme; aksi halde null. */
    fun uniqueBlobIgnoreCase(path: String): String? {
        val exact = nodes[path]
        if (exact != null && exact.isBlob) return path
        val list = lowerBlobs[path.lowercase()]
        if (list != null && list.size == 1) return list.first()
        return null
    }

    /** Yolun üst klasörlerinden biri repoda DOSYA ise onun yolunu döndürür. */
    fun findFileAncestor(path: String): String? {
        var idx = path.lastIndexOf('/')
        while (idx > 0) {
            val parent = path.substring(0, idx)
            val node = nodes[parent]
            if (node != null && !node.isTree) return parent
            idx = parent.lastIndexOf('/')
        }
        return null
    }

    /** Doğrudan üst klasör repoda var mı? (kökteki dosyalar için true) */
    fun hasParentFolder(path: String): Boolean {
        val idx = path.lastIndexOf('/')
        if (idx <= 0) return true
        val node = nodes[path.substring(0, idx)]
        return node != null && node.isTree
    }

    companion object {
        private val dupSuffix = Regex("""\s*\(\d+\)(?=(\.[^./]+)?$)""")

        private fun lastSegment(path: String): String {
            val i = path.lastIndexOf('/')
            return if (i == -1) path else path.substring(i + 1)
        }

        /** "Foo (1).dart" ile "foo.dart" aynı anahtar. */
        private fun nameKey(name: String) = name.lowercase().replace(dupSuffix, "")

        fun fromEntries(entries: List<TreeEntry>): RepoTreeIndex {
            val map = LinkedHashMap<String, RepoNode>()
            for (e in entries) {
                map[e.path] = RepoNode(path = e.path, type = e.type, sha = e.sha, mode = e.mode)
            }
            return RepoTreeIndex(map)
        }
    }
}
