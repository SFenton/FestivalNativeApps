package com.festivalscoretracker.android.core.rankings

import java.math.BigDecimal
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToLong

// region Formatting

/**
 * Value formatting shared by every rankings surface, mirroring the web's
 * `rankingHelpers.ts` and `packages/core/src/app/formatters.ts`
 * (`formatPercentileTopExact`, `formatRatingValue`) and Apple `RankingFormatting`.
 */
object RankingFormatting {
    /**
     * Primary rating text for a metric.
     *
     * @param value Raw value from `ratingValue`.
     * @param metric Selected metric.
     * @param locale Formatting locale.
     * @return "Top 3%", "97.3%" or a grouped integer.
     */
    fun rating(value: Double, metric: RankingMetric, locale: Locale = Locale.getDefault()): String = when (metric) {
        RankingMetric.Adjusted, RankingMetric.Weighted -> percentile(value)
        RankingMetric.FcRate, RankingMetric.MaxScore -> percentage(value)
        RankingMetric.TotalScore -> wholeNumber(value, locale)
    }

    /**
     * Raw 0–1 percentile (0 = best) as "Top N%", banker's rounding like the web.
     *
     * @param rawPercentile Fraction.
     * @return "Top 0.03%" below one percent, else a whole "Top N%"; "N/A" when non-finite.
     */
    fun percentile(rawPercentile: Double): String {
        if (!rawPercentile.isFinite()) return NOT_AVAILABLE
        val top = (rawPercentile * 100).coerceIn(0.01, 100.0)
        return if (top < 1) {
            "Top ${BigDecimal.valueOf(top).setScale(2, RoundingMode.HALF_EVEN).toPlainString()}%"
        } else {
            "Top ${BigDecimal.valueOf(top).setScale(0, RoundingMode.HALF_EVEN).toPlainString()}%"
        }
    }

    /**
     * Fraction as a one-decimal percentage (web `formatRating`).
     *
     * @param fraction FC Rate or Max Score fraction.
     * @return Text such as "97.3%".
     */
    fun percentage(fraction: Double): String {
        if (!fraction.isFinite()) return NOT_AVAILABLE
        return "${String.format(Locale.US, "%.1f", fraction * 100)}%"
    }

    /**
     * Grouped whole number (web `toLocaleString`).
     *
     * @param value Total.
     * @param locale Formatting locale.
     * @return Text such as "12,345,678".
     */
    fun wholeNumber(value: Double, locale: Locale = Locale.getDefault()): String {
        if (!value.isFinite()) return NOT_AVAILABLE
        return NumberFormat.getIntegerInstance(locale).format(value.roundToLong())
    }

    /**
     * Bayesian rating shown beside a percentile (web `formatRatingValue`).
     *
     * @param value Raw rating.
     * @return 1–4 fraction digits depending on magnitude.
     */
    fun bayesian(value: Double): String {
        if (!value.isFinite()) return NOT_AVAILABLE
        val magnitude = abs(value)
        return when {
            magnitude < 0.1 -> {
                val text = String.format(Locale.US, "%.4f", value).trimEnd('0')
                if (text.endsWith('.')) "${text}0" else text
            }
            magnitude < 1 -> String.format(Locale.US, "%.2f", value)
            else -> String.format(Locale.US, "%.1f", value)
        }
    }

    /**
     * Rank label such as "#1,234" (web `formatRankLabel`).
     *
     * @param rank One-based rank.
     * @param locale Formatting locale.
     * @return Label.
     */
    fun rankLabel(rank: Int, locale: Locale = Locale.getDefault()): String = "#${NumberFormat.getIntegerInstance(locale).format(rank)}"

    /**
     * English spoken ordinal with grouping, e.g. "1,234th", for the "Your rank" label.
     *
     * @param rank One-based rank.
     * @param locale Grouping locale.
     * @return Ordinal text.
     */
    fun ordinal(rank: Int, locale: Locale = Locale.getDefault()): String {
        val suffix = when {
            rank % 100 in 11..13 -> "th"
            rank % 10 == 1 -> "st"
            rank % 10 == 2 -> "nd"
            rank % 10 == 3 -> "rd"
            else -> "th"
        }
        return NumberFormat.getIntegerInstance(locale).format(rank) + suffix
    }

    /**
     * Population subtitle such as "869,000 ranked players".
     *
     * @param count Population.
     * @param noun Singular noun ("player", "band").
     * @param locale Grouping locale.
     * @return Subtitle.
     */
    fun population(count: Int, noun: String, locale: Locale = Locale.getDefault()): String =
        "${NumberFormat.getIntegerInstance(locale).format(count)} ranked ${if (count == 1) noun else "${noun}s"}"

    /**
     * Accessibility label for a rankings row.
     *
     * @param rank One-based rank.
     * @param name Display name or roster.
     * @param rating Rating text.
     * @param songs "X / Y" songs text.
     * @param isSelected Whether this is the selected player's own row.
     * @param locale Grouping locale.
     * @return Spoken label.
     */
    fun rowDescription(rank: Int, name: String, rating: String, songs: String, isSelected: Boolean, locale: Locale = Locale.getDefault()): String {
        val lead = if (isSelected) "Your rank, ${ordinal(rank, locale)}. $name." else "Rank ${ordinal(rank, locale)}, $name."
        return "$lead $rating. $songs songs."
    }

    private const val NOT_AVAILABLE = "N/A"
}

// endregion

// region Spotlight

/** What is known about the selected player's own row on one board. */
sealed interface RankingSpotlightSource {
    /** The own-row read has not completed (or failed; the caller renders the failure). */
    data object NotLoaded : RankingSpotlightSource

    /** 404: no rank on this board. */
    data object Unranked : RankingSpotlightSource

    /**
     * Own row available.
     *
     * @property entry The row.
     */
    data class Available(val entry: AccountRankingEntry) : RankingSpotlightSource
}

/** Where the selected player's row goes relative to one loaded board. */
sealed interface RankingSpotlightPlacement {
    /** No selected player. */
    data object None : RankingSpotlightPlacement

    /** Already visible: highlight in place, no extra row. */
    data object Inline : RankingSpotlightPlacement

    /** Not visible; own row still loading. */
    data object Pending : RankingSpotlightPlacement

    /** Not visible; not ranked on this board. */
    data object Unranked : RankingSpotlightPlacement

    /**
     * Not visible; show this row separately.
     *
     * @property entry Own row.
     */
    data class Footer(val entry: AccountRankingEntry) : RankingSpotlightPlacement
}

/** Pure selected-player spotlight decision (Apple/Windows `RankingSpotlight`, web `RankingCard`). */
object RankingSpotlight {
    /**
     * Whether a row belongs to the selected player (case-insensitive).
     *
     * @param selectedAccountId Selected account, or null.
     * @param accountId Row account.
     * @return True for a match with a nonblank selection.
     */
    fun isSelected(selectedAccountId: String?, accountId: String): Boolean =
        !selectedAccountId.isNullOrBlank() && selectedAccountId.equals(accountId, ignoreCase = true)

    /**
     * Decide how to present the selected player on a loaded board.
     *
     * @param selectedAccountId Selected account, or null.
     * @param visibleEntries Rows rendered for the board (card top ten or current page).
     * @param source What is known about the own row.
     * @return Placement.
     */
    fun placement(selectedAccountId: String?, visibleEntries: List<AccountRankingEntry>, source: RankingSpotlightSource): RankingSpotlightPlacement {
        if (selectedAccountId.isNullOrBlank()) return RankingSpotlightPlacement.None
        if (visibleEntries.any { isSelected(selectedAccountId, it.accountId) }) return RankingSpotlightPlacement.Inline
        return when (source) {
            RankingSpotlightSource.NotLoaded -> RankingSpotlightPlacement.Pending
            RankingSpotlightSource.Unranked -> RankingSpotlightPlacement.Unranked
            // A stale read racing a new selection never surfaces someone else's row.
            is RankingSpotlightSource.Available ->
                if (isSelected(selectedAccountId, source.entry.accountId)) RankingSpotlightPlacement.Footer(source.entry) else RankingSpotlightPlacement.Pending
        }
    }
}

// endregion
