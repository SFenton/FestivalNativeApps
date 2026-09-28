package com.festivalscoretracker.android.core.model

import com.festivalscoretracker.android.core.service.ServiceFreezeReason

// region Errors

/**
 * Distinct transport and consistency failures, mirroring Apple's `FestivalAPIError`.
 * Messages never expose server text.
 */
sealed class FestivalApiException(message: String) : Exception(message) {
    /** A non-HTTPS, non-loopback origin was configured. */
    class InsecureBaseUrl : FestivalApiException("A secure service connection is required.")

    /** The publication was malformed or moved backwards. */
    class InvalidPublication : FestivalApiException("The current scores could not be verified. Try again.")

    /** A body did not decode. */
    class InvalidResponse : FestivalApiException("The service returned data we could not read. Try again.")

    /** A path segment or paging argument was rejected before sending. */
    class InvalidResource : FestivalApiException("That song or chart is unavailable.")

    /** The songs envelope was inconsistent. */
    class InvalidCatalogue : FestivalApiException("The service returned data we could not read. Try again.")

    /** A leaderboard page was inconsistent with its request. */
    class InvalidLeaderboard : FestivalApiException("The service returned data we could not read. Try again.")

    /** A search query was out of bounds. */
    class InvalidSearchQuery : FestivalApiException("Enter 2 to 200 characters to search players.")

    /** Unexpected HTTP status. */
    class HttpStatus(val status: Int) : FestivalApiException(
        when {
            status == 404 -> "That song or chart is no longer available."
            status == 429 -> "Too many requests. Try again shortly."
            status in 500..599 -> "The service is temporarily unavailable. Try again."
            else -> "The service could not load this content (HTTP $status)."
        },
    )

    /** A 304 arrived without a matching cached body. */
    class UnexpectedNotModified : FestivalApiException("The service returned an incomplete update. Try again.")

    /** HTTP 503 without a freeze reason. */
    class Unavailable(val retryAfter: String?) :
        FestivalApiException("The service is temporarily unavailable. Try again.")

    /** HTTP 503 while public reads are frozen, carrying `X-FST-Public-Read-Freeze-Reason`. */
    class PublicReadFrozen(val reason: String, val retryAfter: String?) : FestivalApiException(
        if (ServiceFreezeReason.isScoreUpdate(reason)) {
            "Scores are updating. Try again shortly."
        } else {
            "The service is temporarily unavailable. Try again."
        },
    )

    /** HTTP 202 from an endpoint without a syncing envelope. */
    class Syncing : FestivalApiException("This data is still syncing. Try again shortly.")

    /** The request gate refused a non-GET or a privileged/selected-profile header. */
    class ForbiddenRequest : FestivalApiException("The app blocked an unsafe request.")
}

// endregion
