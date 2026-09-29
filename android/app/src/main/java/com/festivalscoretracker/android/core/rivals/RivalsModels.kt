package com.festivalscoretracker.android.core.rivals

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.ProfileSearchText
import kotlinx.serialization.Serializable

// region Ranking metric

/**
 * `rankBy` values accepted by the leaderboard-rivals endpoints (web `RankingMetric`).
 * Production sanitizes experimental metrics off, so the hub always uses [TotalScore];
 * routes still carry the metric so a deep link keeps its scope.
 *
 * @property wireId Query value.
 * @property label User-facing name (web `rankings.metric.*`).
 */
enum class RivalRankMetric(val wireId: String, val label: String) {
    TotalScore("totalscore", "Total Score"),
    Adjusted("adjusted", "Adjusted Percentile"),
    Weighted("weighted", "Popularity-Weighted Percentile"),
    FcRate("fcrate", "FC Rate"),
    MaxScore("maxscore", "Max Score %");

    companion object {
        /**
         * Parse a query value.
         *
         * @param wireId Value such as `totalscore`.
         * @return The metric, or null when unknown.
         */
        fun fromWireId(wireId: String?): RivalRankMetric? = entries.firstOrNull { it.wireId == wireId }
    }
}

// endregion

// region Rival rows

/**
 * Common shape of a song or leaderboard rival row (web `RivalLike`).
 */
sealed interface RivalRowData {
    /** Rival account ID; empty or malformed for an anonymous production row. */
    val accountId: String

    /** Display name, if the service knows one. */
    val displayName: String?

    /** Songs both players have scored. */
    val sharedSongCount: Int

    /** Songs on which the rival leads the player. */
    val aheadCount: Int

    /** Songs on which the player leads the rival. */
    val behindCount: Int

    /** Whether the row names a real account that can be opened (not anonymous). */
    val isNavigable: Boolean get() = ProfileSearchText.isValidAccountId(accountId)

    /** Name to show: the display name, "Unknown User" for anonymous rows, else "Unknown Player". */
    val shownName: String
        get() = when {
            !isNavigable -> RivalText.UNKNOWN_USER
            displayName.isNullOrBlank() -> RivalText.UNKNOWN_PLAYER
            else -> displayName!!.trim()
        }
}

/**
 * One rival from `GET /api/player/{id}/rivals/{scope}`. `rivalScore` and
 * `avgSignedDelta` are server floats.
 */
@Serializable
data class RivalSummary(
    override val accountId: String = "",
    override val displayName: String? = null,
    val rivalScore: Double = 0.0,
    override val sharedSongCount: Int = 0,
    override val aheadCount: Int = 0,
    override val behindCount: Int = 0,
    val avgSignedDelta: Double = 0.0,
) : RivalRowData

/** `GET /api/player/{id}/rivals/{scope}` envelope; HTTP 404 means "no rivals yet" and becomes [empty]. */
@Serializable
data class RivalsListResponse(
    val combo: String? = null,
    val above: List<RivalSummary> = emptyList(),
    val below: List<RivalSummary> = emptyList(),
) {
    /** Whether neither side has rivals. */
    val isEmpty: Boolean get() = above.isEmpty() && below.isEmpty()

    /**
     * Drop rows with negative counts or non-finite scores.
     *
     * @return Validated copy.
     */
    fun validated(): RivalsListResponse = copy(
        above = above.filter(::isValid),
        below = below.filter(::isValid),
    )

    private fun isValid(row: RivalSummary): Boolean =
        row.sharedSongCount >= 0 && row.aheadCount >= 0 && row.behindCount >= 0 && row.rivalScore.isFinite()

    companion object {
        /**
         * The normalized empty list for a scope.
         *
         * @param scope Requested scope token.
         * @return Empty response.
         */
        fun empty(scope: String) = RivalsListResponse(scope, emptyList(), emptyList())
    }
}

/** One neighbour from `GET /api/player/{id}/leaderboard-rivals/{instrument}`. */
@Serializable
data class LeaderboardRivalSummary(
    override val accountId: String = "",
    override val displayName: String? = null,
    override val sharedSongCount: Int = 0,
    override val aheadCount: Int = 0,
    override val behindCount: Int = 0,
    val avgSignedDelta: Double = 0.0,
    val leaderboardRank: Int = 0,
    val userLeaderboardRank: Int = 0,
) : RivalRowData

/** `GET /api/player/{id}/leaderboard-rivals/{instrument}` envelope. */
@Serializable
data class LeaderboardRivalsListResponse(
    val instrument: String? = null,
    val rankBy: String? = null,
    val userRank: Int? = null,
    val above: List<LeaderboardRivalSummary> = emptyList(),
    val below: List<LeaderboardRivalSummary> = emptyList(),
) {
    /** Whether neither side has rivals. */
    val isEmpty: Boolean get() = above.isEmpty() && below.isEmpty()

    /**
     * Drop rows with negative counts.
     *
     * @return Validated copy.
     */
    fun validated(): LeaderboardRivalsListResponse = copy(
        above = above.filter { it.sharedSongCount >= 0 && it.aheadCount >= 0 && it.behindCount >= 0 },
        below = below.filter { it.sharedSongCount >= 0 && it.aheadCount >= 0 && it.behindCount >= 0 },
    )

    companion object {
        /**
         * The normalized empty list for an instrument.
         *
         * @param instrument Chart.
         * @return Empty response.
         */
        fun empty(instrument: Instrument) = LeaderboardRivalsListResponse(instrument.wireId)
    }
}

/**
 * Which half of a list a rival came from: [Above] = the rival is ahead of the
 * player (red tint); [Below] = the player is ahead (green tint).
 */
enum class RivalDirection { Above, Below }

/**
 * A row ready to render: the rival plus the side of the list it came from.
 *
 * @property rival Row data.
 * @property direction List side.
 */
data class RivalEntry(val rival: RivalRowData, val direction: RivalDirection) {
    /** Stable lazy-list key; anonymous rows fall back to their position-independent name. */
    fun key(index: Int): String = if (rival.isNavigable) "${direction.name}:${rival.accountId}" else "${direction.name}:anon:$index"
}

/**
 * Above rows first, then below rows (web order).
 *
 * @param above Rivals ahead.
 * @param below Rivals behind.
 * @param limit Rows kept from each side, or null for all.
 * @return Entries.
 */
fun rivalEntries(above: List<RivalRowData>, below: List<RivalRowData>, limit: Int? = null): List<RivalEntry> =
    (limit?.let(above::take) ?: above).map { RivalEntry(it, RivalDirection.Above) } +
        (limit?.let(below::take) ?: below).map { RivalEntry(it, RivalDirection.Below) }

// endregion

// region Rival detail

/** Rival identity echoed by the detail endpoints. */
@Serializable
data class RivalIdentity(val accountId: String = "", val displayName: String? = null)

/**
 * One shared song compared against a rival. [rankDelta] > 0 means the player leads.
 */
@Serializable
data class RivalSongComparison(
    val songId: String,
    val title: String? = null,
    val artist: String? = null,
    val instrument: String,
    val userInstrument: String? = null,
    val rivalInstrument: String? = null,
    val userRank: Int = 0,
    val rivalRank: Int = 0,
    val rankDelta: Int = 0,
    val userScore: Long? = null,
    val rivalScore: Long? = null,
) {
    /** Dedupe key (web `rivalDetailFetch.dedupeSongs`). */
    val key: String get() = "$songId:$instrument:${userInstrument.orEmpty()}:${rivalInstrument.orEmpty()}"

    /** The compared chart, or null when the service sent an unknown key. */
    val chart: Instrument? get() = Instrument.fromWireId(instrument)

    /** The player's chart (differs from [rivalChart] in mixed Pro Drums family comparisons). */
    val userChart: Instrument? get() = Instrument.fromWireId(userInstrument ?: instrument)

    /** The rival's chart. */
    val rivalChart: Instrument? get() = Instrument.fromWireId(rivalInstrument ?: instrument)
}

/**
 * Shared shape of the song-scope and leaderboard rival detail envelopes
 * (`combo`/`offset`/`limit` vs `instrument`/`rankBy`; both optional here).
 */
@Serializable
data class RivalDetailResponse(
    val rival: RivalIdentity = RivalIdentity(),
    val combo: String? = null,
    val instrument: String? = null,
    val rankBy: String? = null,
    val source: String? = null,
    val totalSongs: Int = 0,
    val sort: String? = null,
    val songs: List<RivalSongComparison> = emptyList(),
) {
    /**
     * Keep only songs with a safe ID, a known chart and non-negative ranks; blank
     * names become null.
     *
     * @param rivalId Requested rival.
     * @return Validated copy.
     * @throws FestivalApiException.InvalidResponse when the echoed rival differs from the request.
     */
    fun validated(rivalId: String): RivalDetailResponse {
        if (rival.accountId.isNotEmpty() && !rival.accountId.equals(rivalId, ignoreCase = true)) {
            throw FestivalApiException.InvalidResponse()
        }
        return copy(
            rival = RivalIdentity(rivalId, rival.displayName?.trim()?.takeIf { it.isNotEmpty() }),
            songs = songs.filter {
                it.songId.isNotBlank() && it.songId.length <= 200 && it.chart != null && it.userRank >= 0 && it.rivalRank >= 0
            },
        )
    }

    companion object {
        /**
         * The normalized result for HTTP 404 "no precomputed song data".
         *
         * @param rivalId Requested rival.
         * @return Empty detail.
         */
        fun empty(rivalId: String) = RivalDetailResponse(RivalIdentity(rivalId, null), sort = "closest")

        /**
         * Merge several scope reads (web `fetchCombinedRivalDetail`): songs deduped
         * by [RivalSongComparison.key] in read order, the first known display name.
         *
         * @param parts Successful reads, in scope order.
         * @param scopes Scope tokens, joined into [combo].
         * @return Merged detail.
         */
        fun merge(parts: List<RivalDetailResponse>, scopes: List<String>): RivalDetailResponse {
            val first = parts.first()
            val seen = HashSet<String>()
            val songs = parts.flatMap { it.songs }.filter { seen.add(it.key) }
            val name = parts.firstNotNullOfOrNull { it.rival.displayName } ?: first.rival.displayName
            return first.copy(rival = first.rival.copy(displayName = name), combo = scopes.joinToString(","), totalSongs = songs.size, songs = songs)
        }
    }
}

// endregion

// region Text

/** Rivals copy from the web `en.json` `rivals.*` table. */
object RivalText {
    const val UNKNOWN_USER = "Unknown User"
    const val UNKNOWN_PLAYER = "Unknown Player"
    const val NO_PLAYER = "Track a player to see their rivals."
    const val NO_RIVALS = "Not enough data to identify rivals yet."
    const val NO_RIVALS_SINGLE = "Play more songs on your selected instrument to generate a roster of Rivals."
    const val NO_RIVALS_PLURAL = "Play more songs on your selected instruments to generate a roster of Rivals."
    const val LEADERBOARD_EMPTY = "No ranking data available."
    const val NO_SONGS = "No song data for this rival."
    const val COMMON_RIVALS = "Common Rivals"
    const val COMBINED = "Combined"
    const val PRO_DRUMS_FAMILY = "Pro Drums Family"
    const val SONG_TAB = "Song Rivals"
    const val LEADERBOARD_TAB = "Leaderboard Rivals"
    const val FIND_RIVAL = "Find Rival"
    const val SEE_ALL = "See All"
    const val VIEW_ALL_RIVALS = "View All Rivals"

    /**
     * `rivals.instrumentRivalsShort`.
     *
     * @param label Scope label.
     * @return "{label} Rivals".
     */
    fun rivalsTitle(label: String) = "$label Rivals"

    /**
     * `rivals.sharedSongs`.
     *
     * @param count Shared songs.
     * @return Text.
     */
    fun sharedSongs(count: Int) = "${"%,d".format(count)} shared songs"

    /**
     * Empty-hub subtitle for the number of visible charts.
     *
     * @param visibleCount Visible charts.
     * @return Subtitle, or null with no charts.
     */
    fun noRivalsSubtitle(visibleCount: Int): String? = when (visibleCount) {
        0 -> null
        1 -> NO_RIVALS_SINGLE
        else -> NO_RIVALS_PLURAL
    }
}

// endregion
