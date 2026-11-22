package com.example.gitpush.service

import android.util.Base64
import com.example.gitpush.util.ContentSource
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import java.util.concurrent.TimeUnit

/** [headers] anahtarları küçük harfe çevrilmiş durumdadır. */
class HttpResult(val code: Int, val body: String, val headers: Map<String, String> = emptyMap())

/** HTTP katmanı; testlerde sahte uygulama verilebilir. IO hataları IOException olarak fırlar. */
interface HttpTransport {
    suspend fun execute(
        method: String,
        url: String,
        headers: Map<String, String>,
        body: String?,
        timeoutMs: Long,
    ): HttpResult

    suspend fun postForm(
        url: String,
        headers: Map<String, String>,
        form: Map<String, String>,
        timeoutMs: Long,
    ): HttpResult

    /**
     * `{"content":"<base64>","encoding":"base64"}` gövdesini [source]'tan AKIŞLA gönderir (POST).
     * Varsayılan uygulama (sahte/test taşıyıcıları için) içeriği belleğe alır; [OkHttpTransport] almaz.
     */
    suspend fun postBase64Blob(
        url: String,
        headers: Map<String, String>,
        source: ContentSource,
        timeoutMs: Long,
    ): HttpResult {
        val raw = source.open().use { it.readBytes() }
        val json = "{\"content\":\"" + Base64.encodeToString(raw, Base64.NO_WRAP) + "\",\"encoding\":\"base64\"}"
        return execute("POST", url, headers, json, timeoutMs)
    }
}

/**
 * Base64 JSON gövdesini dosyadan parça parça üretir; bellekte yalnızca küçük bir tampon tutulur.
 * [isOneShot] false: yeniden deneme/yönlendirmede akış baştan açılır.
 */
private class Base64BlobBody(private val source: ContentSource) : RequestBody() {
    private val prefix = "{\"content\":\"".toByteArray(Charsets.US_ASCII)
    private val suffix = "\",\"encoding\":\"base64\"}".toByteArray(Charsets.US_ASCII)
    private val declaredSize = source.size

    override fun contentType(): MediaType = "application/json; charset=utf-8".toMediaType()

    override fun contentLength(): Long = prefix.size + (declaredSize + 2) / 3 * 4 + suffix.size

    override fun isOneShot(): Boolean = false

    override fun writeTo(sink: BufferedSink) {
        sink.write(prefix)
        // Her parça 3'ün katı olmalı ki base64 ara parçalarda dolgu (=) üretmesin.
        val buf = ByteArray(3 * 32 * 1024)
        var total = 0L
        source.open().use { ins ->
            while (true) {
                var filled = 0
                while (filled < buf.size) {
                    val n = ins.read(buf, filled, buf.size - filled)
                    if (n < 0) break
                    filled += n
                }
                if (filled == 0) break
                total += filled
                sink.write(Base64.encode(buf, 0, filled, Base64.NO_WRAP))
                if (filled < buf.size) break
            }
        }
        if (total != declaredSize) {
            throw java.io.IOException("Dosya yükleme sırasında değişti ($total / $declaredSize bayt).")
        }
        sink.write(suffix)
    }
}

class OkHttpTransport(
    private val client: OkHttpClient = OkHttpClient.Builder()
        // Varsayılan 10 sn'lik bağlan/oku/yaz süreleri büyük gövdelerde yavaş ağda hataya yol açıyordu.
        // Toplam süre sınırı istek başına callTimeout ile verilir.
        .connectTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(120, TimeUnit.SECONDS)
        .readTimeout(120, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build(),
) : HttpTransport {

    private val jsonType = "application/json; charset=utf-8".toMediaType()

    private fun toResult(resp: okhttp3.Response): HttpResult {
        val headers = HashMap<String, String>()
        for (name in resp.headers.names()) {
            headers[name.lowercase()] = resp.header(name) ?: ""
        }
        return HttpResult(resp.code, resp.body?.string().orEmpty(), headers)
    }

    override suspend fun execute(
        method: String,
        url: String,
        headers: Map<String, String>,
        body: String?,
        timeoutMs: Long,
    ): HttpResult = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(url)
        headers.forEach { (k, v) -> builder.header(k, v) }
        val reqBody = body?.toRequestBody(jsonType)
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post(reqBody ?: "".toRequestBody(jsonType))
            "PUT" -> builder.put(reqBody ?: "".toRequestBody(jsonType))
            "PATCH" -> builder.patch(reqBody ?: "".toRequestBody(jsonType))
            "HEAD" -> builder.head()
            "DELETE" -> if (reqBody != null) builder.delete(reqBody) else builder.delete()
            else -> throw IllegalArgumentException("Desteklenmeyen HTTP yöntemi: $method")
        }
        val call = client.newBuilder().callTimeout(timeoutMs, TimeUnit.MILLISECONDS).build()
            .newCall(builder.build())
        call.execute().use { toResult(it) }
    }

    override suspend fun postBase64Blob(
        url: String,
        headers: Map<String, String>,
        source: ContentSource,
        timeoutMs: Long,
    ): HttpResult = withContext(Dispatchers.IO) {
        val builder = Request.Builder().url(url).post(Base64BlobBody(source))
        headers.forEach { (k, v) -> builder.header(k, v) }
        val call = client.newBuilder().callTimeout(timeoutMs, TimeUnit.MILLISECONDS).build()
            .newCall(builder.build())
        call.execute().use { toResult(it) }
    }

    override suspend fun postForm(
        url: String,
        headers: Map<String, String>,
        form: Map<String, String>,
        timeoutMs: Long,
    ): HttpResult = withContext(Dispatchers.IO) {
        val fb = FormBody.Builder()
        form.forEach { (k, v) -> fb.add(k, v) }
        val builder = Request.Builder().url(url).post(fb.build())
        headers.forEach { (k, v) -> builder.header(k, v) }
        val call = client.newBuilder().callTimeout(timeoutMs, TimeUnit.MILLISECONDS).build()
            .newCall(builder.build())
        call.execute().use { toResult(it) }
    }
}
