package com.festivalscoretracker.android.core.service

import com.festivalscoretracker.android.core.model.FestivalApiException
import java.io.IOException
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import kotlinx.coroutines.CancellationException

// region Freeze reason

/**
 * The service's `X-FST-Public-Read-Freeze-Reason` vocabulary
 * (`FSTService/Api/PublicReadGateMiddleware.cs`). Scrape-lifecycle reasons mean
 * "scores are updating"; anything else is a generic outage.
 */
object ServiceFreezeReason {
    /** Response header naming why public reads are frozen. */
    const val HEADER = "X-FST-Public-Read-Freeze-Reason"

    /** Reasons that belong to the normal scrape → publish lifecycle. */
    val scoreUpdateReasons = setOf(
        "scrape", "post-process", "publish", "publication-commit", "publication-commit-deferred",
    )

    /**
     * Whether a freeze reason means "scores are updating" rather than an outage.
     *
     * @param reason Raw header value in any capitalization.
     * @return True for a scrape-lifecycle reason.
     */
    fun isScoreUpdate(reason: String): Boolean = reason.trim().lowercase() in scoreUpdateReasons
}

// endregion

// region Service issue

/**
 * The one user-facing vocabulary for a failed public read (Apple `ServiceIssue`).
 *
 * Screens convert any thrown error with [from] and render it with the shared
 * service-status views instead of interpreting HTTP codes. The app is
 * online-only: [Offline] never implies a cached copy is shown.
 */
sealed interface ServiceIssue {
    /** Public reads are frozen while new scores are scraped and published. */
    data class ScrapeInProgress(val retryAfter: Int?) : ServiceIssue

    /** The service answered 503 for another reason. */
    data class Unavailable(val retryAfter: Int?) : ServiceIssue

    /** HTTP 202 on an endpoint without a syncing envelope. */
    data object Syncing : ServiceIssue

    /** HTTP 404. */
    data object NotFound : ServiceIssue

    /** The device could not reach the service. */
    data object Offline : ServiceIssue

    /** Any other failure, with a readable message that never exposes server text. */
    data class Other(val detail: String) : ServiceIssue

    /** Server-suggested wait, when one was sent. */
    val retryAfterSeconds: Int?
        get() = when (this) {
            is ScrapeInProgress -> retryAfter
            is Unavailable -> retryAfter
            else -> null
        }

    /** Whether the UI should count down and retry on its own (scrape freeze only). */
    val retriesAutomatically: Boolean get() = this is ScrapeInProgress

    /** Heading, or null to use the screen's own "… unavailable" title. */
    val title: String?
        get() = when (this) {
            is ScrapeInProgress -> "Scores are updating"
            Offline -> "You're offline"
            Syncing -> "Still syncing"
            else -> null
        }

    /** Body text for the status view. */
    val message: String
        get() = when (this) {
            is ScrapeInProgress -> "New scores are being published. This page will try again automatically."
            is Unavailable -> if (retryAfter != null) {
                "The service is temporarily unavailable. Try again in $retryAfter seconds."
            } else {
                "The service is temporarily unavailable. Try again."
            }
            Syncing -> "This data is still being prepared. Try again shortly."
            NotFound -> "This content is no longer available."
            Offline -> "Check your connection and try again."
            is Other -> detail
        }

    companion object {
        /**
         * Classify any error thrown by the API client or its transport.
         *
         * @param error A [FestivalApiException], [IOException] or other throwable.
         * @return The matching issue.
         * @throws CancellationException rethrown so structured concurrency is preserved.
         */
        fun from(error: Throwable): ServiceIssue = when (error) {
            is CancellationException -> throw error
            is FestivalApiException.PublicReadFrozen -> {
                val seconds = retryAfterSeconds(error.retryAfter)
                if (ServiceFreezeReason.isScoreUpdate(error.reason)) ScrapeInProgress(seconds) else Unavailable(seconds)
            }
            is FestivalApiException.Unavailable -> Unavailable(retryAfterSeconds(error.retryAfter))
            is FestivalApiException.Syncing -> Syncing
            is FestivalApiException.HttpStatus -> if (error.status == 404) NotFound else Other(error.message.orEmpty())
            is FestivalApiException -> Other(error.message.orEmpty())
            is UnknownHostException, is ConnectException, is SocketTimeoutException -> Offline
            is IOException -> Offline
            else -> Other("Something went wrong. Try again.")
        }

        /**
         * Parse a delta-seconds `Retry-After`; HTTP-date forms are ignored.
         *
         * @param value Raw header value.
         * @return Seconds in `1..86_400`, or null when absent or unusable.
         */
        fun retryAfterSeconds(value: String?): Int? =
            value?.trim()?.toIntOrNull()?.takeIf { it in 1..86_400 }
    }
}

// endregion

// region Retry backoff

/**
 * Consecutive automatic-retry delays per scope, capped with exponential backoff
 * (Apple `ServiceRetryBackoff`): 30 → 60 → 120 → 240 → 300 s. A failure after a
 * quiet period starts over at the server's `Retry-After`.
 *
 * @property clock Milliseconds source; injectable for tests.
 */
class ServiceRetryBackoff(private val clock: () -> Long = System::currentTimeMillis) {
    private data class Attempt(val count: Int, val delay: Int, val atMillis: Long)

    private val attempts = mutableMapOf<String, Attempt>()

    /**
     * Record a failure and return how long to wait before the next automatic retry.
     *
     * @param scope Stable identifier for the screen or request.
     * @param retryAfter Server-suggested delay in seconds.
     * @return Seconds to wait, in `1..CAP`.
     */
    fun nextDelay(scope: String, retryAfter: Int?): Int {
        val now = clock()
        val base = (retryAfter ?: DEFAULT_DELAY).coerceIn(1, CAP)
        val previous = attempts[scope]
        val count = if (previous != null && now - previous.atMillis <= (previous.delay + GRACE) * 1_000L) {
            previous.count + 1
        } else {
            0
        }
        val delay = minOf(CAP, base * (1 shl minOf(count, 8)))
        attempts[scope] = Attempt(count, delay, now)
        return delay
    }

    /**
     * Forget a scope after it loads successfully.
     *
     * @param scope Identifier passed to [nextDelay].
     */
    fun reset(scope: String) {
        attempts.remove(scope)
    }

    companion object {
        /** Delay when the service sent no usable `Retry-After`. */
        const val DEFAULT_DELAY = 30

        /** Longest automatic wait between attempts. */
        const val CAP = 300

        /** Seconds after a countdown during which a failure still counts as consecutive. */
        const val GRACE = 20
    }
}

// endregion
