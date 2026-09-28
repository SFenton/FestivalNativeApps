package com.festivalscoretracker.android.core.bands

import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import java.text.NumberFormat
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.roundToLong

// region Formatting

/**
 * Display text for band statistics, matching the web Band page formatters
 * (`BandPage.tsx`) and Windows `BandFormatting`.
 */
object BandFormatting {
    /** Placeholder for an absent value. */
    const val NONE = "—"

    /** Expanded accuracy ÷ 10,000 = percent (web `ACCURACY_SCALE`). */
    const val ACCURACY_SCALE = 10_000.0

    /**
     * Grouped count `12,345`.
     *
     * @param value Count.
     * @param locale Locale.
     * @return Grouped digits.
     */
    fun count(value: Long, locale: Locale = Locale.getDefault()): String = NumberFormat.getIntegerInstance(locale).format(value)

    /**
     * `#1,234`, or [NONE] when unranked.
     *
     * @param rank One-based rank.
     * @param locale Locale.
     * @return Rank text.
     */
    fun rank(rank: Int, locale: Locale = Locale.getDefault()): String = if (rank > 0) "#" + count(rank.toLong(), locale) else NONE

    /**
     * `#1.5`, or [NONE].
     *
     * @param rank Mean rank.
     * @param locale Locale.
     * @return Rank with one decimal.
     */
    fun averageRank(rank: Double, locale: Locale = Locale.getDefault()): String =
        if (rank.isFinite() && rank > 0) "#" + decimal(rank, 1, locale) else NONE

    /**
     * `99.2%` from expanded accuracy, or [NONE].
     *
     * @param expanded Accuracy in ten-thousandths of a percent.
     * @param locale Locale.
     * @return Percent with one decimal.
     */
    fun accuracy(expanded: Double?, locale: Locale = Locale.getDefault()): String =
        if (expanded != null && expanded.isFinite() && expanded > 0) decimal(expanded / ACCURACY_SCALE, 1, locale) + "%" else NONE

    /**
     * `4.9` stars, or [NONE].
     *
     * @param stars Mean stars.
     * @param locale Locale.
     * @return Stars with one decimal.
     */
    fun stars(stars: Double, locale: Locale = Locale.getDefault()): String =
        if (stars.isFinite() && stars > 0) decimal(stars, 1, locale) else NONE

    /**
     * `97.3%` from a 0–1 fraction.
     *
     * @param fraction Fraction.
     * @param locale Locale.
     * @return Percent with one decimal, or [NONE] when not finite.
     */
    fun percentage(fraction: Double, locale: Locale = Locale.getDefault()): String =
        if (fraction.isFinite()) decimal(fraction * 100, 1, locale) + "%" else NONE

    /**
     * `Top 3%` (two decimals below 1%), matching web `formatPercentileTopExact`.
     *
     * @param raw Fraction where 0 is the best rank.
     * @param locale Locale.
     * @return Percentile text.
     */
    fun percentile(raw: Double, locale: Locale = Locale.getDefault()): String {
        if (!raw.isFinite()) return NONE
        val top = (raw * 100).coerceIn(0.01, 100.0)
        return "Top " + decimal(top, if (top < 1) 2 else 0, locale) + "%"
    }

    /**
     * `36 / 40`.
     *
     * @param part Numerator.
     * @param total Denominator.
     * @param locale Locale.
     * @return Fraction text.
     */
    fun fraction(part: Int, total: Int, locale: Locale = Locale.getDefault()): String =
        "${count(part.toLong(), locale)} / ${count(total.toLong(), locale)}"

    /**
     * `42 appearances` / `1 appearance`.
     *
     * @param count Appearances.
     * @param locale Locale.
     * @return Text.
     */
    fun appearances(count: Int, locale: Locale = Locale.getDefault()): String =
        "${count(count.toLong(), locale)} ${if (count == 1) "appearance" else "appearances"}"

    /**
     * A metric's value as shown in rank-history rows.
     *
     * @param value Rating, fraction or score.
     * @param metric Metric.
     * @param locale Locale.
     * @return Percentile, percentage or grouped score.
     */
    fun metricValue(value: Double?, metric: BandRankingMetric, locale: Locale = Locale.getDefault()): String {
        if (value == null || !value.isFinite()) return NONE
        return when (metric) {
            BandRankingMetric.Adjusted, BandRankingMetric.Weighted -> percentile(value, locale)
            BandRankingMetric.FcRate -> percentage(value, locale)
            BandRankingMetric.TotalScore -> count(value.roundToLong(), locale)
        }
    }

    /**
     * A `yyyy-MM-dd` snapshot date as `Sep 27`, or the raw text otherwise.
     *
     * @param date Service date.
     * @param locale Locale.
     * @return Short date.
     */
    fun shortDate(date: String, locale: Locale = Locale.getDefault()): String = try {
        LocalDate.parse(date).format(DateTimeFormatter.ofPattern("MMM d", locale))
    } catch (_: DateTimeParseException) {
        date
    }

    private fun decimal(value: Double, digits: Int, locale: Locale): String =
        NumberFormat.getNumberInstance(locale).apply {
            minimumFractionDigits = digits
            maximumFractionDigits = digits
            isGroupingUsed = true
        }.format(value)
}

// endregion

// region Detail projection

/**
 * A labelled statistic, optionally a link.
 *
 * @property id Stable ID suffix (`fst.band.stat.<id>`).
 * @property label Title Case label.
 * @property value Display value.
 * @property route Destination when the card navigates.
 */
data class BandStat(val id: String, val label: String, val value: String, val route: AppRoute? = null)

/**
 * A rank-history chart vertex: [x] 0–1 oldest to newest, [y] 0–1 with the best rank at 0 (top).
 *
 * @property rank Rank at this snapshot.
 */
data class BandHistoryPoint(val x: Float, val y: Float, val rank: Int)

/**
 * One recent snapshot row.
 *
 * @property date Snapshot date (`yyyy-MM-dd`).
 * @property dateText Short date.
 * @property rankText `#1`.
 * @property valueText Metric value.
 */
data class BandHistoryRow(val date: String, val dateText: String, val rankText: String, val valueText: String)

/**
 * A best/worst song row resolved against the catalogue.
 *
 * @property performance Wire row.
 * @property song Catalogue song, when known.
 */
data class BandSongRow(val performance: BandSongPerformance, val song: Song?) {
    /** Title, or `Unknown Song`. */
    val title: String get() = song?.title ?: "Unknown Song"

    /** `artist · year`. */
    val subtitle: String get() = song?.let { listOfNotNull(it.artist.ifEmpty { null }, it.year?.toString()).joinToString(" · ") }.orEmpty()

    /** Song Detail route when the song is in the catalogue. */
    val route: AppRoute? get() = song?.let { SongDetailRoute(it.songId) }
}

/** Pure projections for Band Detail (unit-tested; no Android imports). */
object BandDetailProjection {
    /** Rank-history window in days (web default). */
    const val HISTORY_DAYS = 30

    /** Songs per best/worst list (web default). */
    const val SONG_LIMIT = 5

    /** Most recent snapshots listed under the chart. */
    const val RECENT_ROWS = 10

    /**
     * Summary cards: type, appearances, members.
     *
     * @param detail Band row.
     * @param bandType Band size.
     * @return Cards.
     */
    fun summary(detail: BandDetail, bandType: BandType): List<BandStat> = listOf(
        BandStat("type", "Type", bandType.label),
        BandStat("appearances", "Appearances", BandFormatting.count(detail.songsPlayed.toLong())),
        BandStat("members", "Members", BandFormatting.count(BandMember.distinct(detail.displayMembers).size.toLong())),
    )

    /**
     * Statistics cards (web Band Statistics section).
     *
     * @param detail Band row.
     * @param bandType Band size.
     * @param metric Selected rank-by metric.
     * @param bestSong Best song resolved in the catalogue, when known.
     * @return Cards; the rank card links to Band Rankings, Best Song Rank to Song Detail.
     */
    fun statistics(detail: BandDetail, bandType: BandType, metric: BandRankingMetric, bestSong: Song?): List<BandStat> {
        val rank = detail.rank(metric)
        return listOf(
            BandStat("rank", "${metric.label} Rank", BandFormatting.rank(rank), if (rank > 0) BandRankingsRoute(bandType.wireId) else null),
            BandStat("songs-played", "Songs Played", BandFormatting.fraction(detail.songsPlayed, detail.totalChartedSongs)),
            BandStat("full-combos", "Full Combos", BandFormatting.fraction(detail.fullComboCount, detail.totalChartedSongs)),
            BandStat("total-score", "Total Score", BandFormatting.count(detail.totalScore)),
            BandStat("fc-rate", "FC Rate", BandFormatting.percentage(detail.fcRate)),
            BandStat("avg-accuracy", "Avg Accuracy", BandFormatting.accuracy(detail.avgAccuracy)),
            BandStat("avg-stars", "Avg Stars", BandFormatting.stars(detail.avgStars)),
            BandStat(
                "best-rank",
                "Best Song Rank",
                BandFormatting.rank(detail.bestRank),
                if (bestSong != null && detail.bestRank > 0) SongDetailRoute(bestSong.songId) else null,
            ),
            BandStat("avg-rank", "Avg Rank", BandFormatting.averageRank(detail.avgRank)),
        )
    }

    /**
     * Snapshots ranked for a metric, oldest first.
     *
     * @param history Snapshots in any order.
     * @param metric Metric.
     * @return Ranked snapshots sorted by date.
     */
    fun ranked(history: List<BandRankHistoryEntry>, metric: BandRankingMetric): List<BandRankHistoryEntry> =
        history.filter { it.rank(metric) > 0 }.sortedBy { it.snapshotDate }

    /**
     * Normalize ranked snapshots (oldest first) into chart space.
     *
     * @param ranked Output of [ranked].
     * @param metric Metric.
     * @return Points; a single snapshot or a flat line sits mid-height.
     */
    fun points(ranked: List<BandRankHistoryEntry>, metric: BandRankingMetric): List<BandHistoryPoint> {
        if (ranked.isEmpty()) return emptyList()
        val ranks = ranked.map { it.rank(metric) }
        val min = ranks.min()
        val max = ranks.max()
        return ranks.mapIndexed { index, rank ->
            val x = if (ranks.size == 1) 0.5f else index.toFloat() / (ranks.size - 1)
            val y = if (max == min) 0.5f else (rank - min).toFloat() / (max - min)
            BandHistoryPoint(x, y, rank)
        }
    }

    /**
     * The most recent snapshots, newest first.
     *
     * @param ranked Output of [ranked].
     * @param metric Metric.
     * @param locale Locale.
     * @return Up to [RECENT_ROWS] rows.
     */
    fun recentRows(ranked: List<BandRankHistoryEntry>, metric: BandRankingMetric, locale: Locale = Locale.getDefault()): List<BandHistoryRow> =
        ranked.asReversed().take(RECENT_ROWS).map {
            BandHistoryRow(
                it.snapshotDate,
                BandFormatting.shortDate(it.snapshotDate, locale),
                BandFormatting.rank(it.rank(metric), locale),
                BandFormatting.metricValue(it.value(metric), metric, locale),
            )
        }

    /**
     * Freshness note for a history response (web `band.rankHistory*` strings).
     *
     * @param response History response.
     * @return Note, or null when current.
     */
    fun historyNote(response: BandRankHistoryResponse): String? {
        if (response.historyStatus == "failed") return "Rank history is temporarily unavailable."
        response.historyMessage?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        return when (response.historyStatus) {
            "catching_up" -> "History is catching up. Current rankings are already fresh."
            "stale" -> "Rank history is behind the latest current rankings."
            "disabled" -> "Rank history is disabled while current rankings remain available."
            else -> null
        }
    }
}

// endregion
