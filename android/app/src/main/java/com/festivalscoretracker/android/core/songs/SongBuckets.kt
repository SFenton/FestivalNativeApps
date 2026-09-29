package com.festivalscoretracker.android.core.songs

// region Bucket filters

/**
 * The web Filter's "Selected Instrument Filters" sections (`FilterModal.tsx`
 * `SeasonToggles`/`PercentileToggles`/`StarsToggles`/`DifficultyToggles`). Each is a
 * set of buckets shown by default; turning one off hides songs in it (web
 * `Record<number, boolean>` entries set to `false`). They apply only while Songs is
 * filtered to one visible instrument.
 *
 * @property title Section title.
 * @property hint Section hint.
 * @property playerScoped Reads the selected player's score (cleared on deselection).
 */
enum class SongBucketKind(val title: String, val hint: String, val playerScoped: Boolean) {
    Season("Season", "Filter by the season in which the score was achieved.", true),
    Percentile("Percentile", "Show or hide songs based on their leaderboard ranking bracket.", true),
    Stars("Stars", "Filter songs by the number of stars on your high score.", true),
    Intensity("Song Intensity", "Filter by the song's difficulty rating for the selected instrument.", false),
}

/** Star buckets (web `StarsToggles`: 6 = gold five stars, 0 = no score). */
object SongStarsBucket {
    /** Keys in menu order. */
    val KEYS: List<Int> = listOf(6, 5, 4, 3, 2, 1, 0)

    /**
     * A score's bucket.
     *
     * @param stars Stars (6 = gold), or null without a score.
     * @return Key.
     */
    fun of(stars: Int?): Int = (stars ?: 0).coerceIn(0, 6)
}

/** Percentile buckets (web `PERCENTILE_THRESHOLDS`, 0 = no score or no rank). */
object SongPercentileBucket {
    /** Web thresholds. */
    val THRESHOLDS: List<Int> = listOf(1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100)

    /** Keys in menu order. */
    val KEYS: List<Int> = listOf(0) + THRESHOLDS

    /**
     * A score's bucket: the first threshold at or above `rank / totalEntries × 100`.
     *
     * @param scored The chart has a positive score.
     * @param rank One-based rank, or null.
     * @param totalEntries Board population, or null.
     * @return Key.
     */
    fun of(scored: Boolean, rank: Int?, totalEntries: Int?): Int {
        if (!scored || rank == null || totalEntries == null || rank <= 0 || totalEntries <= 0) return 0
        val percent = minOf(rank.toDouble() / totalEntries * 100, 100.0)
        return THRESHOLDS.first { percent <= it }
    }
}

/** Season buckets (web `SeasonToggles`: the player's seasons, then 0 = no score). */
object SongSeasonBucket {
    /** Highest accepted season key (bounded saved data). */
    const val MAX_SEASON = 999

    /**
     * Keys in menu order.
     *
     * @param available Seasons in the player's scores.
     * @return Ascending seasons, then 0.
     */
    fun keys(available: Collection<Int>): List<Int> = available.filter { it in 1..MAX_SEASON }.distinct().sorted() + 0

    /**
     * A score's bucket.
     *
     * @param scored The chart has a positive score.
     * @param season Season, or null.
     * @return Key.
     */
    fun of(scored: Boolean, season: Int?): Int = if (scored) (season ?: 0).coerceIn(0, MAX_SEASON) else 0
}

/** Intensity buckets (web `DifficultyToggles`: 1–7 display bars, 0 = no chart value). */
object SongIntensityBucket {
    /** Keys in menu order. */
    val KEYS: List<Int> = listOf(1, 2, 3, 4, 5, 6, 7, 0)

    /**
     * A chart's bucket (web `Math.trunc(raw) + 1`, clamped to 1–7).
     *
     * @param raw Raw 0–6 chart difficulty, or null.
     * @return Key.
     */
    fun of(raw: Double?): Int = if (raw == null || !raw.isFinite()) 0 else (raw.toInt() + 1).coerceIn(1, 7)
}

// endregion
