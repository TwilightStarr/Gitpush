package com.example.gitpush.service

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
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
            "DELETE" -> if (reqBody != null) builder.delete(reqBody) else builder.delete()
            else -> throw IllegalArgumentException("Desteklenmeyen HTTP yöntemi: $method")
        }
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
