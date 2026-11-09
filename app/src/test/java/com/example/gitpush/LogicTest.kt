package com.example.gitpush

import com.example.gitpush.model.AppSettings
import com.example.gitpush.model.GitFileItem
import com.example.gitpush.model.GitFileStatus
import com.example.gitpush.model.RepoSortMode
import com.example.gitpush.model.RepoTreeIndex
import com.example.gitpush.model.TreeEntry
import com.example.gitpush.model.buildDirectoryListing
import com.example.gitpush.model.compareNatural
import com.example.gitpush.model.searchRepoTree
import com.example.gitpush.service.AppLockService
import com.example.gitpush.service.GitHubService
import com.example.gitpush.service.PushPlan
import com.example.gitpush.service.RepoDiff
import com.example.gitpush.util.FilePreviewStatus
import com.example.gitpush.util.SecretCandidate
import com.example.gitpush.util.SecretGuard
import com.example.gitpush.util.appendFileNameIfFolder
import com.example.gitpush.util.findDuplicatePaths
import com.example.gitpush.util.isSafeExternalUrl
import com.example.gitpush.util.normalizeAndValidateGitPath
import com.example.gitpush.util.normalizeFolderPrefix
import com.example.gitpush.util.prepareFilePreview
import com.example.gitpush.util.splitIntoChunks
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LogicTest {

    // ── Yol doğrulama ──
    @Test fun pathNormalization() {
        val r = normalizeAndValidateGitPath("\\lib//screens/a.dart/")
        assertTrue(r.isValid)
        assertEquals("lib/screens/a.dart", r.normalizedPath)
    }

    @Test fun pathRejectsTraversalAndGit() {
        assertFalse(normalizeAndValidateGitPath("a/../b").isValid)
        assertFalse(normalizeAndValidateGitPath(".git/config").isValid)
        assertFalse(normalizeAndValidateGitPath("a/./b").isValid)
        assertFalse(normalizeAndValidateGitPath("a/b?.txt").isValid)
        assertFalse(normalizeAndValidateGitPath("   ").isValid)
        assertFalse(normalizeAndValidateGitPath("a".repeat(401)).isValid)
    }

    @Test fun folderSuffixAppendsFileName() {
        assertEquals("lib/a.dart", appendFileNameIfFolder("lib/", "a.dart"))
        assertEquals("lib/x.dart", appendFileNameIfFolder("lib/x.dart", "a.dart"))
        assertEquals("a/b/", normalizeFolderPrefix("\\a//b"))
        assertEquals("", normalizeFolderPrefix(" / "))
    }

    @Test fun duplicatesAreCaseInsensitive() {
        assertEquals(listOf("a/b.txt"), findDuplicatePaths(listOf("a/b.txt", "A/B.txt", "c.txt")))
    }

    // ── Gizli bilgi ──
    @Test fun secretGuardFindsTokensAndEnvFiles() {
        val token = "ghp_" + "a".repeat(36)
        val f = SecretGuard.scan(
            listOf(
                SecretCandidate("a.txt", "x=$token".toByteArray()),
                SecretCandidate(".env", "A=1".toByteArray()),
                SecretCandidate(".env.example", "A=1".toByteArray()),
                SecretCandidate("ok.txt", "merhaba".toByteArray()),
            ),
        )
        assertEquals(setOf("a.txt", ".env"), f.map { it.path }.toSet())
        assertTrue(SecretGuard.isSensitiveFileName("keys/server.pem"))
        assertFalse(SecretGuard.isSensitiveFileName("lib/main.dart"))
    }

    // ── Git blob SHA ──
    @Test fun gitBlobSha() {
        assertEquals("e69de29bb2d1d6434b8b29ae775ad8c2e48c5391", GitHubService.calculateGitBlobSha(ByteArray(0)))
        assertEquals("ce013625030ba8dba906f756967f9e9ca394464a", GitHubService.calculateGitBlobSha("hello\n".toByteArray()))
    }

    // ── Ayarlar ──
    @Test fun settingsRoundTripAndSanitize() {
        val s = AppSettings(accentIndex = 3, amoledDark = true, repoSort = RepoSortMode.SizeDesc, previewMaxKb = 2048)
        val back = AppSettings.fromJson(s.toJson())
        assertEquals(s, back)
        val broken = AppSettings.fromJson("""{"accentIndex":99,"historyLimit":7,"previewFontSize":50,"previewMaxKb":1}""")
        assertEquals(0, broken.accentIndex)
        assertEquals(50, broken.historyLimit)
        assertEquals(18.0, broken.previewFontSize, 0.0)
        assertEquals(512, broken.previewMaxKb)
        assertEquals(AppSettings(), AppSettings.fromJson("bozuk"))
    }

    // ── PIN ──
    @Test fun pinRules() {
        assertTrue(AppLockService.isWeakPin("111111"))
        assertTrue(AppLockService.isWeakPin("123456"))
        assertTrue(AppLockService.isWeakPin("12345"))
        assertFalse(AppLockService.isWeakPin("493817"))
        assertEquals(0L, AppLockService.lockoutFor(4))
        assertEquals(30_000L, AppLockService.lockoutFor(5))
        assertEquals(60_000L, AppLockService.lockoutFor(6))
        assertEquals(30_000L * 64, AppLockService.lockoutFor(50))
        assertTrue(AppLockService.constantTimeEquals("abc", "abc"))
        assertFalse(AppLockService.constantTimeEquals("abc", "abd"))
        assertFalse(AppLockService.constantTimeEquals("abc", "abcd"))
    }

    // ── Listeleme ──
    private val tree = listOf(
        TreeEntry("lib", "tree", "t1"),
        TreeEntry("lib/a10.dart", "blob", "s1", "100644", 10),
        TreeEntry("lib/a2.dart", "blob", "s2", "100644", 20),
        TreeEntry("lib/sub", "tree", "t2"),
        TreeEntry("lib/sub/x.txt", "blob", "s3", "100644", 5),
        TreeEntry(".hidden", "blob", "s4", "100644", 1),
        TreeEntry("README.md", "blob", "s5", "100644", 7),
    )

    @Test fun naturalSort() {
        assertTrue(compareNatural("a2", "a10") < 0)
        assertTrue(compareNatural("File", "file") == 0)
    }

    @Test fun directoryListing() {
        val root = buildDirectoryListing(tree, "", RepoSortMode.NameAsc, showHidden = false)
        assertEquals(listOf("lib", "README.md"), root.map { it.name })
        assertTrue(root.first().isDir)
        assertEquals(3, root.first().fileCount)
        val lib = buildDirectoryListing(tree, "lib")
        assertEquals(listOf("sub", "a2.dart", "a10.dart"), lib.map { it.name })
        assertEquals(1, buildDirectoryListing(tree, "", showHidden = true).count { it.isHidden })
    }

    @Test fun searchRanksExactFirst() {
        val r = searchRepoTree(tree, "a2")
        assertEquals("lib/a2.dart", r.first().path)
        assertTrue(searchRepoTree(tree, "  ").isEmpty())
    }

    // ── Repo farkı ──
    private fun item(path: String, content: String) =
        GitFileItem(localPath = path, repoPath = path, size = content.length, bytes = content.toByteArray())

    @Test fun classifyNewUpdateUnchangedConflict() {
        val same = "hello\n"
        val idx = RepoTreeIndex.fromEntries(
            listOf(
                TreeEntry("lib", "tree", "t"),
                TreeEntry("lib/same.txt", "blob", GitHubService.calculateGitBlobSha(same.toByteArray()), "100644", 6),
                TreeEntry("lib/changed.txt", "blob", "0000000000000000000000000000000000000000", "100644", 1),
                TreeEntry("file.txt", "blob", "1111111111111111111111111111111111111111", "100644", 1),
            ),
        )
        val files = listOf(
            item("lib/same.txt", same),
            item("lib/changed.txt", "yeni"),
            item("lib/new.txt", "x"),
            item("newdir/a.txt", "x"),
            item("file.txt/inside.txt", "x"), // üst yol dosya
        )
        RepoDiff.classify(files, idx)
        assertEquals(GitFileStatus.Unchanged, files[0].status)
        assertEquals(GitFileStatus.Update, files[1].status)
        assertEquals(GitFileStatus.IsNew, files[2].status)
        assertEquals(GitFileStatus.NewFolder, files[3].status)
        assertEquals(GitFileStatus.Conflict, files[4].status)

        // Yol repoda klasörse (dosya adı eklenmemişse) çakışma
        val folderAsFile = listOf(item("lib", "x"))
        RepoDiff.classify(folderAsFile, idx)
        assertEquals(GitFileStatus.Conflict, folderAsFile[0].status)
    }

    @Test fun classifyWithoutTreeIsUnknownAndBlocksPush() {
        val f = listOf(item("a.txt", "x"))
        RepoDiff.classify(f, null)
        assertFalse(f[0].statusKnown)
        assertTrue(PushPlan.build(f).treeUnknown)
    }

    @Test fun batchDuplicatePathsConflict() {
        val f = listOf(item("a/b.txt", "1"), item("A/B.txt", "2"))
        RepoDiff.classify(f, RepoTreeIndex.fromEntries(emptyList()))
        assertTrue(f.all { it.status == GitFileStatus.Conflict })
    }

    @Test fun zipAlignmentFindsPrefix() {
        val idx = RepoTreeIndex.fromEntries(
            listOf(
                TreeEntry("app", "tree"),
                TreeEntry("app/src/main/a.kt", "blob", "s1", "100644", 1),
                TreeEntry("app/src/main/b.kt", "blob", "s2", "100644", 1),
            ),
        )
        val originals = listOf("src/main/a.kt", "src/main/b.kt")
        val al = RepoDiff.detectAlignment(originals, originals, idx)
        assertNotNull(al)
        assertEquals("app/src/main/a.kt", al!!.apply("src/main/a.kt"))
        // Zaten eşleşiyorsa öneri yok
        val exact = listOf("app/src/main/a.kt", "app/src/main/b.kt")
        assertNull(RepoDiff.detectAlignment(exact, exact, idx))
    }

    @Test fun unlistedDeletesStayInScope() {
        val idx = RepoTreeIndex.fromEntries(
            listOf(
                TreeEntry("README.md", "blob", "s0"),
                TreeEntry("lib/a.dart", "blob", "s1"),
                TreeEntry("lib/old.dart", "blob", "s2"),
                TreeEntry("docs/x.md", "blob", "s3"),
            ),
        )
        val del = RepoDiff.computeUnlistedDeletes(idx, listOf("lib/a.dart"), "lib/")
        assertEquals(listOf("lib/old.dart"), del.map { it.repoPath })
        // Önek yoksa yalnızca ZIP'in dokunduğu üst klasörler; kök dosyaya dokunulmaz
        val del2 = RepoDiff.computeUnlistedDeletes(idx, listOf("lib/a.dart"), "")
        assertEquals(listOf("lib/old.dart"), del2.map { it.repoPath })
    }

    // ── Önizleme ──
    @Test fun previewHandlesBinaryAndInvalidUtf8() {
        assertEquals(FilePreviewStatus.Binary, prepareFilePreview(byteArrayOf(65, 0, 66)).status)
        assertEquals(FilePreviewStatus.NotUtf8, prepareFilePreview(byteArrayOf(0xC3.toByte(), 0x28)).status)
        val ok = prepareFilePreview("a\r\nb\nc".toByteArray())
        assertEquals(FilePreviewStatus.Ok, ok.status)
        assertEquals(3, ok.totalLines)
        assertEquals("a\nb\nc", ok.displayText)
    }

    @Test fun chunksJoinBackToOriginal() {
        val text = (1..2500).joinToString("\n") { "satır $it" }
        val c = splitIntoChunks(text, maxLines = 1000)
        assertEquals(text, c.chunks.joinToString("\n"))
        assertEquals(2500, c.lineCounts.sum())
    }

    // ── URL güvenliği ──
    @Test fun externalUrlAllowList() {
        assertTrue(isSafeExternalUrl("https://github.com/a/b"))
        assertTrue(isSafeExternalUrl("https://gist.github.com/x"))
        assertFalse(isSafeExternalUrl("http://github.com"))
        assertFalse(isSafeExternalUrl("https://evil.com/github.com"))
        assertFalse(isSafeExternalUrl("https://user@github.com"))
        assertFalse(isSafeExternalUrl("https://notgithub.com"))
        assertFalse(isSafeExternalUrl("javascript:alert(1)"))
    }
}
