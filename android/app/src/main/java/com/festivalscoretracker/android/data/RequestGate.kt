package com.festivalscoretracker.android.data

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.service.ServiceFreezeReason
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.ensureActive

// region Status mapping

/** How a response status should be interpreted by the caller. */
enum class ServiceStatus {
    /** 2xx other than an accepted 202: decode the body. */
    Success,

    /** Accepted HTTP 202 syncing envelope. */
    Syncing,
}

// endregion

// region Request gate

/**
 * The single keyless gate every service GET passes through (Apple
 * `FestivalAPI.send`): GET-only, never `X-API-Key` or `x-fst-selected-*`
 * headers, cancellation checked on both sides of the wire, and one shared
 * status vocabulary. Never create another transport path for service reads.
 *
 * @property transport Wrapped transport.
 */
class RequestGate(private val transport: HttpTransport) {
    /**
     * Validate and send one request.
     *
     * @param request Request built by [makeRequest], optionally with pin/ETag headers.
     * @return Raw response.
     * @throws FestivalApiException.ForbiddenRequest for an unsafe request.
     */
    suspend fun send(request: HttpRequest): HttpResult {
        validateKeyless(request)
        coroutineContext.ensureActive()
        val result = transport.send(request)
        coroutineContext.ensureActive()
        return result
    }

    companion object {
        /** Header names that must never leave the app (case-insensitive). */
        val FORBIDDEN_HEADER_NAMES = setOf("x-api-key")

        /** Header prefixes that must never leave the app: selected-profile headers register activity. */
        val FORBIDDEN_HEADER_PREFIXES = listOf("x-fst-selected-")

        /** Publication pin header, sent only while the service enables pinning. */
        const val PUBLICATION_HEADER = "X-FST-Publication-Id"

        /**
         * Build the one keyless GET shape every read uses.
         *
         * @param url Allowlisted endpoint URL.
         * @param extraHeaders Pin or `If-None-Match` headers.
         * @return A no-cache GET without credentials.
         */
        fun makeRequest(url: String, extraHeaders: Map<String, String> = emptyMap()): HttpRequest =
            HttpRequest(url, "GET", mapOf("Cache-Control" to "no-cache") + extraHeaders)

        /**
         * Reject a request carrying a privileged key, a selected-profile header or a non-GET method.
         *
         * @param request Request about to be sent.
         * @throws FestivalApiException.ForbiddenRequest when unsafe.
         */
        fun validateKeyless(request: HttpRequest) {
            val unsafeHeader = request.headers.keys.any { name ->
                val lowered = name.lowercase()
                lowered in FORBIDDEN_HEADER_NAMES || FORBIDDEN_HEADER_PREFIXES.any(lowered::startsWith)
            }
            if (unsafeHeader || request.method != "GET") throw FestivalApiException.ForbiddenRequest()
        }

        /**
         * Map a response status onto the shared error vocabulary.
         *
         * @param result Raw response.
         * @param acceptsSyncing Whether this endpoint documents a 202 envelope.
         * @return [ServiceStatus.Success] or an accepted [ServiceStatus.Syncing].
         * @throws FestivalApiException for 202 (unexpected), 304, 503 (freeze or outage) and other non-2xx.
         */
        fun mapStatus(result: HttpResult, acceptsSyncing: Boolean): ServiceStatus = when (result.status) {
            202 -> if (acceptsSyncing) ServiceStatus.Syncing else throw FestivalApiException.Syncing()
            in 200..299 -> ServiceStatus.Success
            304 -> throw FestivalApiException.UnexpectedNotModified()
            503 -> {
                val retryAfter = result.header("Retry-After")
                val reason = result.header(ServiceFreezeReason.HEADER)
                if (!reason.isNullOrEmpty()) {
                    throw FestivalApiException.PublicReadFrozen(reason, retryAfter)
                }
                throw FestivalApiException.Unavailable(retryAfter)
            }
            else -> throw FestivalApiException.HttpStatus(result.status)
        }
    }
}

// endregion
