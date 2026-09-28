package com.festivalscoretracker.android.core.bands

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import kotlinx.serialization.Serializable

// region Members

/**
 * One band member as embedded in player-bands, band-ranking and song-band-leaderboard
 * rows (`BandMemberDto`). Per-song stats are only present on song-band-leaderboard members.
 *
 * Production rows can carry an anonymous member with an empty `accountId` and no
 * name: it shows "Unknown User" and is never a link.
 *
 * @property accountId Public account key (may be empty).
 * @property displayName Display name, when known.
 * @property instruments Observed service instrument IDs (may repeat or be unknown).
 * @property score Per-song member score.
 * @property accuracy Per-song accuracy in ten-thousandths of a percent.
 * @property isFullCombo Per-song full-combo flag.
 * @property stars Per-song stars.
 */
@Serializable
data class BandMember(
    val accountId: String = "",
    val displayName: String? = null,
    val instruments: List<String> = emptyList(),
    val score: Long? = null,
    val accuracy: Double? = null,
    val isFullCombo: Boolean? = null,
    val stars: Int? = null,
) {
    /** Readable name with the web's `common.unknownUser` fallback. */
    val resolvedName: String get() = displayName?.trim()?.takeIf { it.isNotEmpty() } ?: UNKNOWN_USER

    /** Distinct charts this app can render, in first-seen order. */
    val chartedInstruments: List<Instrument> get() = instruments.mapNotNull(Instrument::fromWireId).distinct()

    /** Whether the member can open a player profile (a safe, non-empty account ID). */
    val isLinkable: Boolean get() = BandText.isValidMemberId(accountId)

    companion object {
        /** Web `common.unknownUser`. */
        const val UNKNOWN_USER = "Unknown User"

        /**
         * Distinct members: repeated account IDs collapse, anonymous (empty-ID) members are all kept.
         *
         * @param members Members, possibly repeated.
         * @return Members in first-seen order.
         */
        fun distinct(members: List<BandMember>): List<BandMember> {
            val seen = HashSet<String>()
            return members.filter { it.accountId.isEmpty() || seen.add(it.accountId) }
        }

        /**
         * Join distinct members' names with ` + ` (web `formatPlayerBandNames`).
         *
         * @param members Members, possibly repeated.
         * @return `A + B`, or `Band` when empty.
         */
        fun joinNames(members: List<BandMember>): String =
            distinct(members).joinToString(" + ") { it.resolvedName }.ifEmpty { "Band" }
    }
}

// endregion

// region Player bands

/**
 * One of a player's deduplicated bands (`PlayerBandEntryDto`).
 *
 * @property bandId One-way band hash.
 * @property teamKey Member-account roster key.
 * @property bandType Band size service ID.
 * @property appearanceCount Songs this lineup has played.
 * @property members Members with observed instruments.
 */
@Serializable
data class PlayerBandEntry(
    val bandId: String = "",
    val teamKey: String = "",
    val bandType: String = "",
    val appearanceCount: Int = 0,
    val members: List<BandMember> = emptyList(),
) {
    /** Stable row key (band ID, or team key when absent). */
    val key: String get() = bandId.ifEmpty { teamKey }

    /** Joined member names. */
    val membersLabel: String get() = BandMember.joinNames(members)
}

/**
 * Page from `GET /api/player/{accountId}/bands` (`PlayerBandListResponseDto`).
 *
 * @property accountId Requested account.
 * @property totalCount Bands across all pages.
 * @property entries This page.
 */
@Serializable
data class PlayerBandListResponse(
    val accountId: String = "",
    val totalCount: Int = 0,
    val entries: List<PlayerBandEntry> = emptyList(),
) {
    /**
     * Pages of [pageSize] rows, at least one.
     *
     * @param pageSize Rows per page.
     * @return Page count.
     */
    fun pageCount(pageSize: Int): Int = BandPaging.pageCount(totalCount, pageSize)

    /**
     * Reject a response for another account or with impossible counts.
     *
     * @param accountId Requested account.
     * @param pageSize Requested page size.
     * @throws FestivalApiException.InvalidResponse when invalid.
     */
    fun validate(accountId: String, pageSize: Int) {
        if (this.accountId != accountId || totalCount < 0 || entries.size > pageSize || entries.any { it.teamKey.isEmpty() }) {
            throw FestivalApiException.InvalidResponse()
        }
    }
}

// endregion

// region Band detail

/**
 * A band's ranking row: `selectedBandEntry` of `GET /api/rankings/bands/{bandType}?teamKey=`.
 *
 * Band Detail never reads `/api/bands/{bandId}` or the bare
 * `/api/rankings/bands/{bandType}/{teamKey}`: both call `GetBandConfigurations`,
 * which rebuilds `band_team_configurations` on a cache miss (a write from a GET,
 * `.agents/platforms/service-safety.md`). `bandId` is a one-way hash, so the
 * route must carry `bandType`/`teamKey` from the originating row.
 */
@Serializable
data class BandDetail(
    val bandId: String = "",
    val teamKey: String = "",
    val members: List<BandMember> = emptyList(),
    val teamMembers: List<BandMember>? = null,
    val songsPlayed: Int = 0,
    val totalChartedSongs: Int = 0,
    val adjustedSkillRank: Int = 0,
    val weightedRank: Int = 0,
    val fcRate: Double = 0.0,
    val fcRateRank: Int = 0,
    val totalScore: Long = 0,
    val totalScoreRank: Int = 0,
    val avgAccuracy: Double = 0.0,
    val fullComboCount: Int = 0,
    val avgStars: Double = 0.0,
    val bestRank: Int = 0,
    val avgRank: Double = 0.0,
    val totalRankedTeams: Int? = null,
) {
    /** Members to show: [members], or roster names without instruments. */
    val displayMembers: List<BandMember> get() = members.ifEmpty { teamMembers.orEmpty() }

    /**
     * Rank for a metric.
     *
     * @param metric Metric.
     * @return One-based rank (0 when unranked).
     */
    fun rank(metric: BandRankingMetric): Int = when (metric) {
        BandRankingMetric.Adjusted -> adjustedSkillRank
        BandRankingMetric.Weighted -> weightedRank
        BandRankingMetric.FcRate -> fcRateRank
        BandRankingMetric.TotalScore -> totalScoreRank
    }
}

/** Envelope of `GET /api/rankings/bands/{bandType}?teamKey=`; only the selected team matters here. */
@Serializable
data class BandProfileEnvelope(val bandType: String = "", val selectedBandEntry: BandDetail? = null)

// endregion

// region Rank history

/** One daily snapshot (`BandRankHistoryDto`). */
@Serializable
data class BandRankHistoryEntry(
    val snapshotDate: String = "",
    val adjustedSkillRank: Int = 0,
    val weightedRank: Int = 0,
    val fcRateRank: Int = 0,
    val totalScoreRank: Int = 0,
    val adjustedSkillRating: Double? = null,
    val weightedRating: Double? = null,
    val fcRate: Double? = null,
    val totalScore: Long? = null,
) {
    /**
     * Rank for a metric.
     *
     * @param metric Metric.
     * @return One-based rank (0 when unranked).
     */
    fun rank(metric: BandRankingMetric): Int = when (metric) {
        BandRankingMetric.Adjusted -> adjustedSkillRank
        BandRankingMetric.Weighted -> weightedRank
        BandRankingMetric.FcRate -> fcRateRank
        BandRankingMetric.TotalScore -> totalScoreRank
    }

    /**
     * The metric's value at this snapshot.
     *
     * @param metric Metric.
     * @return Rating fraction, FC fraction or score; null when absent.
     */
    fun value(metric: BandRankingMetric): Double? = when (metric) {
        BandRankingMetric.Adjusted -> adjustedSkillRating
        BandRankingMetric.Weighted -> weightedRating
        BandRankingMetric.FcRate -> fcRate
        BandRankingMetric.TotalScore -> totalScore?.toDouble()
    }
}

/** Response of `GET /api/rankings/bands/{bandType}/{teamKey}/history?days=`. */
@Serializable
data class BandRankHistoryResponse(
    val bandType: String = "",
    val teamKey: String = "",
    val days: Int = 0,
    val history: List<BandRankHistoryEntry> = emptyList(),
    val historyStatus: String? = null,
    val historyMessage: String? = null,
)

// endregion

// region Best and worst songs

/** One song performance (`BandSongPerformanceDto`); `percentile` 0 is the best rank. */
@Serializable
data class BandSongPerformance(
    val songId: String = "",
    val rank: Int = 0,
    val totalEntries: Int = 0,
    val percentile: Double = 0.0,
    val score: Long = 0,
)

/** Response of `GET /api/rankings/bands/{bandType}/{teamKey}/songs?limit=` (503 until published). */
@Serializable
data class BandSongExtremesResponse(
    val bandType: String = "",
    val teamKey: String = "",
    val best: List<BandSongPerformance> = emptyList(),
    val worst: List<BandSongPerformance> = emptyList(),
)

// endregion

// region Song band leaderboard

/** One band score on a song (`SongBandLeaderboardEntryDto`). */
@Serializable
data class SongBandLeaderboardEntry(
    val bandId: String = "",
    val bandType: String = "",
    val teamKey: String = "",
    val members: List<BandMember> = emptyList(),
    val score: Long = 0,
    val rank: Int = 0,
    val accuracy: Double? = null,
    val isFullCombo: Boolean? = null,
    val stars: Int? = null,
) {
    /** Stable row key. */
    val key: String get() = "${bandId.ifEmpty { teamKey }}:$rank"

    /** Joined member names. */
    val membersLabel: String get() = BandMember.joinNames(members)
}

/** Page from `GET /api/leaderboard/{songId}/bands/{bandType}?top=&offset=`. */
@Serializable
data class SongBandLeaderboardResponse(
    val songId: String = "",
    val bandType: String = "",
    val count: Int = 0,
    val totalEntries: Int = 0,
    val localEntries: Int? = null,
    val entries: List<SongBandLeaderboardEntry> = emptyList(),
) {
    /** Paging population (`localEntries ?: totalEntries`, never negative). */
    val population: Int get() = maxOf(0, localEntries ?: totalEntries)

    /**
     * Pages of [pageSize] rows, at least one.
     *
     * @param pageSize Rows per page.
     * @return Page count.
     */
    fun pageCount(pageSize: Int): Int = BandPaging.pageCount(population, pageSize)

    /**
     * Reject a response for another board or with impossible counts.
     *
     * @param songId Requested song.
     * @param bandType Requested size.
     * @param top Requested page size.
     * @throws FestivalApiException.InvalidResponse when invalid.
     */
    fun validate(songId: String, bandType: BandType, top: Int) {
        if (this.songId != songId || this.bandType != bandType.wireId || count != entries.size || count > top ||
            totalEntries < 0 || (localEntries ?: 0) < 0
        ) {
            throw FestivalApiException.InvalidResponse()
        }
    }
}

// endregion

// region Paging

/** Shared 25-row paging math for band lists. */
object BandPaging {
    /** Rows per page on every band list (web page size). */
    const val PAGE_SIZE = 25

    /**
     * Pages for a population, at least one.
     *
     * @param total Rows across all pages.
     * @param pageSize Rows per page.
     * @return Page count.
     */
    fun pageCount(total: Int, pageSize: Int): Int = if (total <= 0) 1 else (total - 1) / maxOf(1, pageSize) + 1
}

// endregion
