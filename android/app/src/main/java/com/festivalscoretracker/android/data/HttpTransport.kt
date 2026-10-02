package com.festivalscoretracker.android.data

import com.festivalscoretracker.android.core.service.ServiceFreezeReason
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.suspendCancellableCoroutine
import okhttp3.Call
import okhttp3.Callback
import okhttp3.MediaType
import okhttp3.MediaType.Companion.toMediaTypeOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.Response
import okio.BufferedSink
import java.io.IOException
import java.io.OutputStream
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

// region Request and response

/**
 * A streamed request body. Only the user-initiated feedback POST carries one
 * (`RequestGate.sendFeedback`); every read is a body-less GET.
 */
interface HttpBody {
    /** Full `Content-Type` value, including any multipart boundary. */
    val contentType: String

    /** Exact byte count, or -1 when unknown (sent chunked). */
    val contentLength: Long

    /**
     * Write the body. May be called more than once (e.g. on a transport retry).
     *
     * @param sink Destination stream; not closed by the body.
     * @throws IOException when a source cannot be read.
     */
    fun writeTo(sink: OutputStream)
}

/**
 * A platform-neutral outgoing request.
 *
 * @property url Fully qualified URL.
 * @property method HTTP method; the gate only lets `GET` through, plus the one feedback `POST`.
 * @property headers Request headers.
 * @property body Request body (feedback POST only).
 * @property readTimeoutSeconds Response wait override (feedback POST only; the service may transcode media first).
 */
data class HttpRequest(
    val url: String,
    val method: String = "GET",
    val headers: Map<String, String> = emptyMap(),
    val body: HttpBody? = null,
    val readTimeoutSeconds: Long? = null,
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
        builder.method(request.method, request.body?.let(::OkHttpBody))
        val callClient = request.readTimeoutSeconds?.let { client.newBuilder().readTimeout(it, TimeUnit.SECONDS).build() } ?: client
        val call = callClient.newCall(builder.build())
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

/** Adapts an [HttpBody] to OkHttp's streaming body. */
private class OkHttpBody(private val body: HttpBody) : RequestBody() {
    override fun contentType(): MediaType? = body.contentType.toMediaTypeOrNull()

    override fun contentLength(): Long = body.contentLength

    override fun writeTo(sink: BufferedSink) {
        body.writeTo(sink.outputStream())
        sink.flush()
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
