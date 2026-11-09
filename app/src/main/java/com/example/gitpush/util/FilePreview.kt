package com.example.gitpush.util

import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

enum class FilePreviewStatus { Ok, Binary, NotUtf8 }

class FilePreviewData(
    val status: FilePreviewStatus,
    val fullText: String = "",
    val displayText: String = "",
    val totalLines: Int = 0,
    val shownLines: Int = 0,
    val truncated: Boolean = false,
)

object FilePreviewLimits {
    const val MAX_LINES = 3000
    const val MAX_LINE_CHARS = 2000
    const val MAX_TOTAL_CHARS = 200000
}

/** Ağır iş: arka plan iş parçacığında çağrılmalıdır. */
fun prepareFilePreview(bytes: ByteArray): FilePreviewData {
    for (b in bytes) if (b.toInt() == 0) return FilePreviewData(FilePreviewStatus.Binary)

    var decoded: String
    try {
        val decoder = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
        decoded = decoder.decode(ByteBuffer.wrap(bytes)).toString()
    } catch (_: CharacterCodingException) {
        return FilePreviewData(FilePreviewStatus.NotUtf8)
    }
    if (decoded.isNotEmpty() && decoded[0].code == 0xFEFF) decoded = decoded.substring(1)

    val sb = StringBuilder()
    var total = 0
    var shown = 0
    var chars = 0
    var cut = false
    var pos = 0
    while (pos < decoded.length) {
        val nl = decoded.indexOf('\n', pos)
        val end = if (nl == -1) decoded.length else nl
        total++
        if (shown < FilePreviewLimits.MAX_LINES && chars < FilePreviewLimits.MAX_TOTAL_CHARS) {
            var lineEnd = end
            if (lineEnd > pos && decoded[lineEnd - 1].code == 0x0D) lineEnd--
            var line = decoded.substring(pos, lineEnd)
            if (line.length > FilePreviewLimits.MAX_LINE_CHARS) {
                var keep = FilePreviewLimits.MAX_LINE_CHARS
                if (Character.isHighSurrogate(line[keep - 1])) keep--
                line = line.substring(0, keep) + "… [satır kısaltıldı]"
                cut = true
            }
            if (shown > 0) sb.append('\n')
            sb.append(line)
            chars += line.length + 1
            shown++
        }
        if (nl == -1) break
        pos = nl + 1
    }
    return FilePreviewData(
        status = FilePreviewStatus.Ok,
        fullText = decoded,
        displayText = sb.toString(),
        totalLines = total,
        shownLines = shown,
        truncated = cut || shown < total,
    )
}

class ChunkedText(val chunks: List<String>, val lineCounts: List<Int>)

/** Büyük metni satır sınırlarında bölümlere ayırır; chunks.joinToString("\n") == text. */
fun splitIntoChunks(text: String, maxLines: Int = 1000, maxChars: Int = 100000): ChunkedText {
    val chunks = ArrayList<String>()
    val counts = ArrayList<Int>()
    var chunkStart = 0
    var lines = 0
    var chars = 0
    var pos = 0
    while (true) {
        val nl = text.indexOf('\n', pos)
        val lineEnd = if (nl == -1) text.length else nl
        lines++
        chars += lineEnd - pos + 1
        if (nl == -1) {
            chunks.add(text.substring(chunkStart))
            counts.add(lines)
            break
        }
        if (lines >= maxLines || chars >= maxChars) {
            chunks.add(text.substring(chunkStart, lineEnd))
            counts.add(lines)
            chunkStart = nl + 1
            lines = 0
            chars = 0
        }
        pos = nl + 1
    }
    return ChunkedText(chunks, counts)
}
