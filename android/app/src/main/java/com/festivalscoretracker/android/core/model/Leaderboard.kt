package com.festivalscoretracker.android.core.model

import kotlinx.serialization.Serializable

// region Leaderboard

/** A score row in the service's solo chart response. */
@Serializable
data class LeaderboardEntry(
    val accountId: String,
    val displayName: String? = null,
    val score: Int,
    val rank: Int,
    val accuracy: Double? = null,
    val isFullCombo: Boolean? = null,
    val stars: Int? = null,
    val season: Int? = null,
    val difficulty: Double? = null,
)

/** `/api/leaderboard/{songId}/{instrument}` page. */
@Serializable
data class LeaderboardResponse(
    val songId: String,
    val instrument: String,
    val count: Int,
    val totalEntries: Int,
    val localEntries: Int? = null,
    val entries: List<LeaderboardEntry>,
) {
    /**
     * Number of pages of [pageSize] rows, using the service's local/total fallback.
     *
     * @param pageSize Rows per page.
     * @return At least one page, even for an empty board.
     */
    fun pageCount(pageSize: Int = LeaderboardPaging.PAGE_SIZE): Int {
        val total = maxOf(0, localEntries ?: totalEntries)
        return if (total == 0) 1 else (total - 1) / pageSize + 1
    }

    /**
     * Reject mismatched request data and invalid counts.
     *
     * @param songId Requested song.
     * @param instrument Requested chart.
     * @param top Maximum rows requested.
     * @throws FestivalApiException.InvalidLeaderboard on a corrupt response.
     */
    fun validate(songId: String, instrument: Instrument, top: Int) {
        val valid = this.songId == songId && this.instrument == instrument.wireId &&
            count == entries.size && count in 0..top && totalEntries >= 0 &&
            (localEntries ?: 0) >= 0
        if (!valid) throw FestivalApiException.InvalidLeaderboard()
    }
}

/** Pure paging rules for song leaderboards. */
object LeaderboardPaging {
    /** Rows per full leaderboard page, matching the web. */
    const val PAGE_SIZE = 25

    /** Rows in a Song Detail preview card. */
    const val PREVIEW_SIZE = 10

    /**
     * Clamp a requested page into the available range.
     *
     * @param requested One-based page requested.
     * @param totalPages Maximum valid page.
     * @return Page inside `1..totalPages`.
     */
    fun corrected(requested: Int, totalPages: Int): Int = requested.coerceIn(1, maxOf(1, totalPages))

    /**
     * Map a one-based rank to the page that contains it.
     *
     * @param rank One-based rank.
     * @param pageSize Rows per page.
     * @return One-based page, or 1 for invalid input.
     */
    fun pageForRank(rank: Int, pageSize: Int = PAGE_SIZE): Int =
        if (rank <= 0 || pageSize <= 0) 1 else (rank - 1) / pageSize + 1
}

// endregion
