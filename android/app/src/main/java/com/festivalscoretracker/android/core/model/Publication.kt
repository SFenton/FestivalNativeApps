package com.festivalscoretracker.android.core.model

import kotlinx.serialization.Serializable

// region Publication

/** A public data surface that has not yet reached the published generation. */
@Serializable
data class UnreadySurface(val surface: String, val reasons: List<String> = emptyList())

/**
 * The service generation that makes public reads mutually consistent
 * (`GET /api/publication`).
 */
@Serializable
data class Publication(
    val contractVersion: Int,
    val publicationId: Int,
    val publishedScrapeId: Int,
    val readyForPinning: Boolean = false,
    val pinningEnabled: Boolean = false,
    val unreadySurfaces: List<UnreadySurface> = emptyList(),
) {
    /** Whether requests should carry the `X-FST-Publication-Id` pin header. */
    val pins: Boolean get() = readyForPinning && pinningEnabled

    /**
     * Validate required fields before the generation is used.
     *
     * @throws FestivalApiException.InvalidPublication for a malformed generation.
     */
    fun validate() {
        if (contractVersion <= 0 || publicationId <= 0 || publishedScrapeId <= 0) {
            throw FestivalApiException.InvalidPublication()
        }
    }
}

// endregion
