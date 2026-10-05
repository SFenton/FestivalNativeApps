package com.festivalscoretracker.android.data.suggestions

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.suggestions.RivalsAllResponse
import com.festivalscoretracker.android.core.suggestions.SuggestionScore
import com.festivalscoretracker.android.core.suggestions.SuggestionScoreIndex
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ServiceEndpoint
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// region Endpoints

/**
 * The two keyless GETs Suggestions needs (`.agents/platforms/service-safety.md`):
 *
 * - `GET /api/player/{accountId}`: allowlisted pure read (live-probed 200 on
 *   2026-09-28); publication-bound, HTTP 202 = syncing envelope. Never sends
 *   selected-profile headers (the request gate rejects them).
 * - `GET /api/player/{accountId}/rivals/all`: allowlisted pure read
 *   (`FSTService/Api/RivalsEndpoints.cs:207-273`); 404 "No rivals found." is empty.
 */
internal object SuggestionEndpoints {
    /**
     * `GET /api/player/{accountId}`.
     *
     * @param accountId Validated account.
     * @return Pinned endpoint accepting 202.
     */
    fun player(accountId: String): ServiceEndpoint {
        requireAccount(accountId)
        return ServiceEndpoint.Feature(listOf("player", accountId), acceptsSyncing = true)
    }

    /**
     * `GET /api/player/{accountId}/rivals/all`.
     *
     * @param accountId Validated account.
     * @return Endpoint.
     */
    fun rivalsAll(accountId: String): ServiceEndpoint {
        requireAccount(accountId)
        return ServiceEndpoint.Feature(listOf("player", accountId, "rivals", "all"))
    }

    private fun requireAccount(accountId: String) {
        if (!ProfileSearchText.isValidAccountId(accountId)) throw FestivalApiException.InvalidResource()
    }
}

// endregion

// region Player score wire

/** Compact `/api/player` score row (only the fields Suggestions reads; Apple `PlayerScore`). */
@Serializable
internal data class CompactScoreWire(
    @SerialName("si") val songId: String,
    @SerialName("ins") val instrument: String,
    @SerialName("sc") val score: Long,
    @SerialName("acc") val accuracy: Double? = null,
    @SerialName("fc") val fullCombo: Boolean? = null,
    @SerialName("st") val stars: Int? = null,
    @SerialName("sn") val season: Int? = null,
    @SerialName("rk") val rank: Int? = null,
    @SerialName("te") val totalEntries: Int? = null,
)

/** Compact `/api/player` envelope (or its HTTP 202 syncing form). */
@Serializable
internal data class PlayerProfileWire(
    val accountId: String,
    val totalScores: Int,
    val scores: List<CompactScoreWire>,
    val status: String? = null,
    val notYetPublished: Boolean? = null,
)

/** Result of the selected player's score read. */
sealed interface SuggestionScoresRead {
    /**
     * Published scores.
     *
     * @property index songId → chart → score.
     * @property observedPublicationId Publication observed while reading.
     */
    data class Available(val index: SuggestionScoreIndex, val observedPublicationId: Int) : SuggestionScoresRead

    /** HTTP 202: the service is still syncing this player. */
    data object Syncing : SuggestionScoresRead
}

/** Validation and expansion of the compact wire (Apple `PlayerProfileResponse.validate`). */
internal object PlayerScoreWire {
    /** Wire accuracy is thousandths of a percent; generator accuracy is ten-thousandths. */
    private const val ACCURACY_SCALE = 1_000

    /**
     * Decode one solo instrument bit (`01`…`100`); composite or unknown bits are invalid.
     *
     * @param hex Canonical lowercase two- or three-digit hex mask.
     * @return Chart.
     * @throws FestivalApiException.InvalidResponse for anything else.
     */
    fun instrument(hex: String): Instrument {
        val mask = if (hex.length in 2..3) hex.toIntOrNull(16) else null
        if (mask == null || mask <= 0 || Integer.bitCount(mask) != 1) throw FestivalApiException.InvalidResponse()
        val bit = Integer.numberOfTrailingZeros(mask)
        if (bit >= Instrument.entries.size || hex.lowercase() != mask.toString(16).padStart(2, '0')) {
            throw FestivalApiException.InvalidResponse()
        }
        return Instrument.entries[bit]
    }

    /**
     * Validate an envelope and build the generator's score index.
     *
     * @param wire Decoded envelope.
     * @param requestedAccountId Account that must own every row.
     * @param status HTTP status (200 or an accepted 202).
     * @param observedPublicationId Publication observed while reading.
     * @return Available index or syncing.
     * @throws FestivalApiException.InvalidResponse for mixed identity, counts or corrupt rows.
     */
    fun toRead(wire: PlayerProfileWire, requestedAccountId: String, status: Int, observedPublicationId: Int): SuggestionScoresRead {
        val valid = wire.accountId.equals(requestedAccountId, ignoreCase = true) &&
            wire.totalScores in 0..20_000 && wire.totalScores == wire.scores.size
        if (!valid) throw FestivalApiException.InvalidResponse()
        if (wire.status == "syncing") {
            if (status != 202 || wire.notYetPublished != true || wire.scores.isNotEmpty()) throw FestivalApiException.InvalidResponse()
            return SuggestionScoresRead.Syncing
        }
        if (status != 200 || wire.status != null || wire.notYetPublished == true) throw FestivalApiException.InvalidResponse()
        val index = LinkedHashMap<String, MutableMap<Instrument, SuggestionScore>>()
        for (row in wire.scores) {
            val instrument = instrument(row.instrument)
            val accuracy = row.accuracy?.times(ACCURACY_SCALE)
            val ok = row.songId.isNotEmpty() && row.songId.length <= 200 &&
                row.score in 0..Int.MAX_VALUE.toLong() &&
                (row.rank ?: 0) >= 0 && (row.totalEntries ?: 0) >= 0 && (row.season ?: 0) >= 0 &&
                (row.stars == null || row.stars in 0..6) &&
                (accuracy == null || (accuracy.isFinite() && accuracy in 0.0..1_000_000.0))
            if (!ok) throw FestivalApiException.InvalidResponse()
            val perSong = index.getOrPut(row.songId) { LinkedHashMap() }
            if (instrument in perSong) throw FestivalApiException.InvalidResponse()
            perSong[instrument] = SuggestionScore(
                row.score.toInt(), accuracy, row.fullCombo, row.stars, row.season, row.rank, row.totalEntries,
            )
        }
        return SuggestionScoresRead.Available(index, observedPublicationId)
    }
}

// endregion

// region Reads

/**
 * Read the selected player's compact scores for Suggestions (publication-bound;
 * 202 = syncing).
 *
 * @param accountId Selected account.
 * @return Available scores or syncing.
 */
suspend fun FestivalApi.suggestionScores(accountId: String): SuggestionScoresRead {
    val read = readPinnedResponse(SuggestionEndpoints.player(accountId))
    return decode(PlayerProfileWire.serializer(), read.body) { wire ->
        PlayerScoreWire.toRead(wire, accountId, read.status, read.observedPublicationId)
    }
}

/**
 * Read every combo's rivals in one call for the `song_rival_*` families;
 * 404 "No rivals found." becomes an empty response.
 *
 * @param accountId Selected account.
 * @return Rivals (possibly empty).
 */
suspend fun FestivalApi.suggestionRivals(accountId: String): RivalsAllResponse {
    val body = try {
        readPinned(SuggestionEndpoints.rivalsAll(accountId)).first
    } catch (error: FestivalApiException.HttpStatus) {
        if (error.status == 404) return RivalsAllResponse.empty(accountId)
        throw error
    }
    return decode(RivalsAllResponse.serializer(), body)
}

// endregion
