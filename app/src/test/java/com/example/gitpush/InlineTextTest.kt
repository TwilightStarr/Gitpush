package com.example.gitpush

import com.example.gitpush.service.GitHubService
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class InlineTextTest {
    @Test fun utf8TextIsInlined() {
        val src = "merhaba dünya\r\nçğış €\n"
        assertEquals(src, GitHubService.decodeInlineText(src.toByteArray(Charsets.UTF_8)))
    }

    @Test fun emptyBinaryAndInvalidUtf8GoThroughBlobs() {
        assertNull(GitHubService.decodeInlineText(ByteArray(0)))
        assertNull(GitHubService.decodeInlineText(byteArrayOf(0x50, 0x4B, 0x00, 0x03)))
        assertNull(GitHubService.decodeInlineText(byteArrayOf(0x41, 0xFF.toByte(), 0xFE.toByte())))
    }

    @Test fun bomIsPreserved() {
        val bytes = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte(), 0x61)
        assertNotNull(GitHubService.decodeInlineText(bytes))
    }
}
