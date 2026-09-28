package com.festivalscoretracker.android.data

import com.festivalscoretracker.android.core.service.ServiceFreezeReason
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

// region Request and response

/**
 * A platform-neutral outgoing request.
 *
 * @property url Fully qualified URL.
 * @property method HTTP method; the gate only lets `GET` through.
 * @property headers Request headers.
 */
data class HttpRequest(
    val url: String,
    val method: String = "GET",
    val headers: Map<String, String> = emptyMap(),
)

/**
 * Raw status, bytes and case-insensitive headers.
 *
 * @property status HTTP status.
 * @property body Unmodified payload.
 */
class HttpResult(val status: Int, val body: ByteArray, headers: Map<String, String> = emptyMap()) {
    private val normalized = headers.mapKeys { it.key.lowercase() }

    /**
     * Read a header regardless of the server's capitalization.
     *
     * @param name Header name.
     * @return Value or null.
     */
    fun header(name: String): String? = normalized[name.lowercase()]
}

/** Injectable async transport with no implicit persistence. */
fun interface HttpTransport {
    /**
     * Send a request and return the raw response.
     *
     * @param request Outgoing request.
     * @return Status, headers and bytes.
     * @throws IOException on connectivity failures.
     */
    suspend fun send(request: HttpRequest): HttpResult
}

// endregion

// region OkHttp transport

/**
 * Production transport: no HTTP cache (online-only; in-process caches live in the
 * API client) and the shared 30 s timeout. OkHttp adds `Accept-Encoding: gzip` and
 * decompresses transparently.
 *
 * @property client Configured client; shared with the image loader.
 */
class OkHttpTransport(private val client: OkHttpClient = defaultClient()) : HttpTransport {
    override suspend fun send(request: HttpRequest): HttpResult {
        val builder = Request.Builder().url(request.url)
        request.headers.forEach { (name, value) -> builder.header(name, value) }
        builder.method(request.method, null)
        val call = client.newCall(builder.build())
        return suspendCancellableCoroutine { continuation ->
            continuation.invokeOnCancellation { call.cancel() }
            call.enqueue(object : Callback {
                override fun onFailure(call: Call, e: IOException) {
                    continuation.resumeWithException(e)
                }

                override fun onResponse(call: Call, response: Response) {
                    val result = runCatching {
                        response.use {
                            val headers = it.headers.names().associateWith { name -> it.header(name).orEmpty() }
                            HttpResult(it.code, it.body?.bytes() ?: ByteArray(0), headers)
                        }
                    }
                    result.fold(continuation::resume, continuation::resumeWithException)
                }
            })
        }
    }

    companion object {
        /** Idle/read timeout for every service request (Apple `requestTimeout`). */
        const val TIMEOUT_SECONDS = 30L

        /**
         * Build the shared cache-less client.
         *
         * @return Client with 30 s connect/read/write timeouts and no disk cache.
         */
        fun defaultClient(): OkHttpClient = OkHttpClient.Builder()
            .connectTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .readTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .writeTimeout(TIMEOUT_SECONDS, TimeUnit.SECONDS)
            .cache(null)
            .build()
    }
}

// endregion

// region Debug forced freeze

/**
 * Debug-only decorator answering the first request to each `/api/…` path (except
 * `/api/publication`) with a synthetic scrape-freeze 503, then passing through
 * (`FST_DEBUG_FORCE_FREEZE=1`, Apple `ForcedFreezeTransport`).
 *
 * @property wrapped Real transport.
 * @property retryAfter Synthetic `Retry-After`.
 */
class ForcedFreezeTransport(private val wrapped: HttpTransport, private val retryAfter: String = "30") : HttpTransport {
    private val frozenPaths = mutableSetOf<String>()

    override suspend fun send(request: HttpRequest): HttpResult {
        val path = request.url.substringAfter("://").substringAfter('/', "").substringBefore('?').let { "/$it" }
        val freeze = path.startsWith("/api/") && path != "/api/publication" && synchronized(frozenPaths) { frozenPaths.add(path) }
        if (freeze) {
            return HttpResult(
                503,
                """{"title":"Published data unavailable","status":503}""".toByteArray(),
                mapOf("Retry-After" to retryAfter, ServiceFreezeReason.HEADER to "scrape", "Cache-Control" to "no-store"),
            )
        }
        return wrapped.send(request)
    }
}

// endregion
