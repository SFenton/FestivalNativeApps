package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import java.time.Instant
import java.time.OffsetDateTime
import java.time.format.DateTimeParseException
import kotlinx.serialization.Serializable

// region Wire

/**
 * One tracked score change (`ServerScoreHistoryEntry`, `packages/core/src/api/serverTypes.ts:860-888`).
 *
 * @property accuracy Ten-thousandths of a percent (leaderboard scale), never a 0–1 fraction.
 * @property scoreAchievedAt Preferred display date.
 * @property changedAt When the change was recorded (fallback date).
 */
@Serializable
data class ScoreHistoryEntry(
    val songId: String = "",
    val instrument: String = "",
    val oldScore: Long? = null,
    val newScore: Long = 0,
    val oldRank: Int? = null,
    val newRank: Int = 0,
    val accuracy: Double? = null,
    val isFullCombo: Boolean? = null,
    val stars: Int? = null,
    val percentile: Double? = null,
    val season: Int? = null,
    val scoreAchievedAt: String? = null,
    val seasonRank: Int? = null,
    val allTimeRank: Int? = null,
    val difficulty: Double? = null,
    val changedAt: String = "",
) {
    /** Sort/display key: achieved time, else recorded time (ISO-8601 sorts lexically). */
    val dateKey: String get() = scoreAchievedAt ?: changedAt

    /** Parsed display instant, or null. */
    val displayDate: Instant?
        get() = try {
            OffsetDateTime.parse(dateKey).toInstant()
        } catch (_: DateTimeParseException) {
            try {
                Instant.parse(dateKey)
            } catch (_: DateTimeParseException) {
                null
            }
        }
}

/**
 * `GET /api/player/{accountId}/history` envelope (202 adds `status`/`notYetPublished`).
 *
 * @property accountId Account.
 * @property count Declared row count.
 * @property history Rows.
 */
@Serializable
data class PlayerHistoryResponse(
    val accountId: String = "",
    val count: Int = 0,
    val history: List<ScoreHistoryEntry> = emptyList(),
    val status: String? = null,
    val notYetPublished: Boolean? = null,
) {
    /**
     * Reject another account or an inconsistent count.
     *
     * @param accountId Requested account.
     * @throws FestivalApiException.InvalidResponse when inconsistent.
     */
    fun validate(accountId: String) {
        if (!this.accountId.equals(accountId, ignoreCase = true) || count < 0 || count != history.size) {
            throw FestivalApiException.InvalidResponse()
        }
    }
}

/** Availability of a player's score history. */
enum class PlayerHistoryState {
    /** Rows (possibly none). */
    Available,

    /** HTTP 202: registered, not yet computed. */
    Syncing,

    /** HTTP 404: not a registered user — never "no history". */
    Unregistered,
}

/**
 * A history read.
 *
 * @property response Validated envelope (empty when unregistered).
 * @property state Availability.
 */
data class PlayerHistoryPayload(val response: PlayerHistoryResponse, val state: PlayerHistoryState) {
    /**
     * Rows for exactly one song and chart (the server already filters; re-filtered like the web).
     *
     * @param songId Song.
     * @param instrument Chart.
     * @return Matching rows.
     */
    fun entries(songId: String, instrument: Instrument): List<ScoreHistoryEntry> =
        response.history.filter { it.songId == songId && it.instrument == instrument.wireId }
}

// endregion

// region Sort

/** Score-history sort keys (web `PlayerScoreSortModal`). */
enum class PlayerScoreSortMode(val label: String) {
    /** Achieved/recorded date. */
    Date("Date"),

    /** New score (default, descending). */
    Score("Score"),

    /** Accuracy; ties by FC, score, date. */
    Accuracy("Accuracy"),

    /** Season. */
    Season("Season"),
}

/** Pure history ordering (`useSortedScoreHistory.ts`). */
object PlayerScoreHistorySort {
    /**
     * Order rows; stable for equal keys.
     *
     * @param entries Rows for one song/chart.
     * @param mode Key.
     * @param ascending Direction.
     * @return New list.
     */
    fun sorted(entries: List<ScoreHistoryEntry>, mode: PlayerScoreSortMode, ascending: Boolean): List<ScoreHistoryEntry> {
        val comparator = Comparator<ScoreHistoryEntry> { a, b -> compare(a, b, mode) }
        return entries.sortedWith(if (ascending) comparator else comparator.reversed())
    }

    /**
     * Index of the highest `newScore` in the displayed order (first wins ties).
     *
     * @param sorted Displayed rows.
     * @return Index, or null when empty.
     */
    fun highScoreIndex(sorted: List<ScoreHistoryEntry>): Int? {
        if (sorted.isEmpty()) return null
        var best = 0
        for (i in 1 until sorted.size) if (sorted[i].newScore > sorted[best].newScore) best = i
        return best
    }

    private fun compare(a: ScoreHistoryEntry, b: ScoreHistoryEntry, mode: PlayerScoreSortMode): Int = when (mode) {
        PlayerScoreSortMode.Date -> a.dateKey.compareTo(b.dateKey)
        PlayerScoreSortMode.Score -> a.newScore.compareTo(b.newScore)
        PlayerScoreSortMode.Season -> (a.season ?: 0).compareTo(b.season ?: 0)
        PlayerScoreSortMode.Accuracy -> listOf(
            (a.accuracy ?: 0.0).compareTo(b.accuracy ?: 0.0),
            (a.isFullCombo == true).compareTo(b.isFullCombo == true),
            a.newScore.compareTo(b.newScore),
            a.dateKey.compareTo(b.dateKey),
        ).firstOrNull { it != 0 } ?: 0
    }
}

// endregion
