package com.festivalscoretracker.android.core.rankings

import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.LeaderboardEntry
import java.util.Locale

// region Section content

/** Which kind of row a leaderboard section holds. */
enum class LeaderboardRowKind {
    /** Score rows (web `LeaderboardEntry`): rank · name · season · score · accuracy · stars. */
    Score,

    /** Rankings rows (web `RankingEntry`): rank · name · songs label · rating. */
    Ranking,
}

/**
 * What every row of one leaderboard section holds (issue #37; web `computeRankWidth`, the
 * score `ch` width and `topScoresLayout`), measured once over all of the section's rows
 * *and* its pinned selected-player row, so every row gets the same columns at the same
 * widths. Widths are the UI's measured text widths in dp (bold, as the selected row draws
 * them), so they already include the font scale.
 *
 * @property kind Row kind.
 * @property rankWidth Widest rank text; 0 when no row has a rank.
 * @property metaWidth Widest season (`S15`) or songs label (`123 / 456`); 0 when no row has one.
 * @property valueWidth Widest score or rating text.
 * @property hasAccuracy Whether any score row has an accuracy badge.
 * @property hasStars Whether any score row has stars to draw.
 * @property nameWidth Widest name in a rankings section whose songs label yields to names
 *   (Compete, issue #38); 0 keeps the songs label at any width.
 * @property stackNarrowNames Whether a rankings section stacks its rows (name over rating
 *   and songs) when the one-line columns leave the name less than
 *   [LeaderboardColumnLayout.MIN_NAME_WIDTH] (Band Rankings in a half-opened fold's pane,
 *   issue #116).
 * @property keepsNameMinimum Whether a rankings section keeps at least
 *   [LeaderboardColumnLayout.MIN_NAME_WIDTH] for names in a known row width: the songs label
 *   yields first, then rows stack (Full Rankings in a narrow pane beside a hinge, issue #115).
 */
data class LeaderboardSection(
    val kind: LeaderboardRowKind,
    val rankWidth: Float,
    val metaWidth: Float,
    val valueWidth: Float,
    val hasAccuracy: Boolean = false,
    val hasStars: Boolean = false,
    val nameWidth: Float = 0f,
    val stackNarrowNames: Boolean = false,
    val keepsNameMinimum: Boolean = false,
) {
    /** Whether any row has a season (score sections) or songs label (rankings sections). */
    val hasMeta: Boolean get() = metaWidth > 0f
}

/**
 * The texts a score section's columns are measured from (every row plus the pinned row).
 *
 * @property ranks Rank labels (`#1,234`).
 * @property seasons Season labels (`S15`) of rows that have one.
 * @property scores Grouped scores.
 * @property hasAccuracy Whether any row draws an accuracy badge (an accuracy value, or a full
 *   combo, which shows `FC` without one).
 * @property hasStars Whether any row has 1–6 stars (anything else draws nothing).
 */
data class ScoreSectionTexts(
    val ranks: List<String>,
    val seasons: List<String>,
    val scores: List<String>,
    val hasAccuracy: Boolean,
    val hasStars: Boolean,
) {
    companion object {
        /**
         * Collects a section's texts.
         *
         * @param entries Section rows, including the pinned selected-player row.
         * @param locale Grouping locale.
         * @return Texts to measure.
         */
        fun of(entries: List<LeaderboardEntry>, locale: Locale = Locale.getDefault()): ScoreSectionTexts = ScoreSectionTexts(
            ranks = entries.map { RankingFormatting.rankLabel(it.rank, locale) },
            seasons = entries.mapNotNull { it.season?.let(LeaderboardColumnLayout::seasonLabel) },
            scores = entries.map { ScoreFormatting.score(it.score, locale) },
            hasAccuracy = entries.any { it.accuracy != null || it.isFullCombo == true },
            hasStars = entries.any { (it.stars ?: 0) in 1..LeaderboardColumnLayout.GOLD_STARS },
        )
    }
}

// endregion

// region Column plan

/**
 * The columns every row of a section shows and their shared widths in dp. A shown column
 * keeps its width on a row without a value (a blank badge or star slot), so values line up
 * vertically down the section like the web's `visibility: hidden` placeholders.
 *
 * @property gap Spacing between columns (8 below 420 dp, else 12; web `NARROW_BREAKPOINT`).
 * @property rankWidth Rank column width (0 for rows without ranks).
 * @property showMeta Whether the season or songs column shows.
 * @property metaWidth Season or songs column width (0 when hidden).
 * @property valueWidth Score or rating column width.
 * @property showAccuracy Whether the accuracy column is reserved.
 * @property accuracyWidth Accuracy column width (0 when hidden).
 * @property showStars Whether the stars column shows.
 * @property starsWidth Stars column width (0 when hidden).
 * @property stacked Whether rankings rows stack (rank and name, then rating and songs) instead of
 *   squeezing the name ([LeaderboardSection.stackNarrowNames], [LeaderboardSection.keepsNameMinimum]).
 */
data class LeaderboardColumnPlan(
    val gap: Float,
    val rankWidth: Float,
    val showMeta: Boolean,
    val metaWidth: Float,
    val valueWidth: Float,
    val showAccuracy: Boolean,
    val accuracyWidth: Float,
    val showStars: Boolean,
    val starsWidth: Float,
    val stacked: Boolean = false,
) {
    /** Whether the narrow (8 dp gap) layout applies. */
    val compact: Boolean get() = gap < LeaderboardColumnLayout.WIDE_GAP
}

// endregion

// region Fitting

/**
 * The one per-section column fitter for Android leaderboard rows (issue #37). Ports the
 * web's rules: the season column from a 520 dp row (`MEDIUM_BREAKPOINT`), stars from 700 dp
 * (`MOBILE_BREAKPOINT` 768 less the page chrome), tighter gaps below 420 dp, the accuracy
 * column always reserved in a section that has accuracy, and the rankings songs label kept
 * unless the section asks it to yield to names ([LeaderboardSection.nameWidth], Compete on
 * portrait phones, issue #38). When the fixed columns would squeeze the name below its
 * minimum, stars go first, then the season.
 */
object LeaderboardColumnLayout {
    /** Row chrome: the 4 dp highlight inset plus 8 dp padding on each side. */
    const val ROW_CHROME = 24f

    /** Narrowest score-row rank column. */
    const val MIN_SCORE_RANK_WIDTH = 28f

    /** Narrowest rankings rank column (fits "#99" without moving names). */
    const val MIN_RANKING_RANK_WIDTH = 44f

    /** Accuracy badge slot (`AccuracyPill` minimum width). */
    const val ACCURACY_WIDTH = 56f

    /** Five 20 dp star images (web `StarSize.rowWidth`). */
    const val STARS_WIDTH = 116f

    /** In-row chevron (or its empty slot). */
    const val CHEVRON_WIDTH = 20f

    /** Narrowest name before optional columns drop. */
    const val MIN_NAME_WIDTH = 72f

    /** Row width below which gaps tighten (web `NARROW_BREAKPOINT`). */
    const val COMPACT_BREAKPOINT = 420f

    /** Row width from which the season shows (web `MEDIUM_BREAKPOINT`). */
    const val SEASON_BREAKPOINT = 520f

    /** Row width from which stars show (web `MOBILE_BREAKPOINT` less the page chrome). */
    const val STARS_BREAKPOINT = 700f

    /** Normal column gap. */
    const val WIDE_GAP = 12f

    /** Compact column gap. */
    const val COMPACT_GAP = 8f

    /** The service's gold-star value. */
    const val GOLD_STARS = 6

    /** Rankings row chrome: 8 dp padding on each side (`RankingRowLayout`). */
    const val RANKING_ROW_CHROME = 16f

    /** Rankings row column spacing (`RankingRowLayout`; it never tightens). */
    const val RANKING_GAP = 12f

    /**
     * Season label (`S15`).
     *
     * @param season Season number.
     * @return Label.
     */
    fun seasonLabel(season: Int): String = "S$season"

    /**
     * Fits a section's columns into a row width.
     *
     * A rankings section with a [LeaderboardSection.nameWidth] shows its songs label only when
     * every name fits in full beside it (rank · name · songs · rating · chevron at the rankings
     * row's own padding and spacing); otherwise, or before the first layout, the whole section
     * hides it so names are not truncated and the remaining columns stay aligned (issue #38).
     * A section that [keeps a name minimum][LeaderboardSection.keepsNameMinimum] drops the songs
     * label, then stacks its rows, rather than squeeze names below [MIN_NAME_WIDTH] (issue #115).
     * A section that [stacks narrow names][LeaderboardSection.stackNarrowNames] keeps its songs
     * label and stacks its rows when the one-line columns leave the name less than
     * [MIN_NAME_WIDTH] (Band Rankings, issue #116).
     *
     * @param section Section content (every row plus the pinned row).
     * @param rowWidth Row width in dp, including its chrome; NaN or 0 before the first layout (no optional columns).
     * @param fontScale System font scale; grows the name minimum and the badge slot (measured texts already include it).
     * @return Columns and widths for every row of the section.
     */
    fun fit(section: LeaderboardSection, rowWidth: Float, fontScale: Float = 1f): LeaderboardColumnPlan {
        val known = rowWidth.isFinite() && rowWidth > 0f
        val scale = if (fontScale.isFinite()) maxOf(1f, fontScale) else 1f
        val score = section.kind == LeaderboardRowKind.Score
        val gap = if (known && rowWidth < COMPACT_BREAKPOINT) COMPACT_GAP else WIDE_GAP
        val minRank = if (score) MIN_SCORE_RANK_WIDTH else MIN_RANKING_RANK_WIDTH
        val rank = if (section.rankWidth <= 0f) 0f else maxOf(section.rankWidth, minRank)
        val accuracy = if (score && section.hasAccuracy) ACCURACY_WIDTH * scale else 0f
        var showMeta = section.hasMeta && (!score || (known && rowWidth >= SEASON_BREAKPOINT))
        var showStars = score && section.hasStars && known && rowWidth >= STARS_BREAKPOINT
        if (!score && showMeta && section.nameWidth > 0f) {
            val columns = listOf(rank, section.nameWidth, section.metaWidth, section.valueWidth, CHEVRON_WIDTH).filter { it > 0f }
            showMeta = known && RANKING_ROW_CHROME + columns.sum() + RANKING_GAP * (columns.size - 1) <= rowWidth
        }
        var stacked = false
        if (!score && section.keepsNameMinimum && known) {
            fun fitsName(withMeta: Boolean): Boolean {
                val columns = listOf(rank, MIN_NAME_WIDTH * scale, if (withMeta) section.metaWidth else 0f, section.valueWidth, CHEVRON_WIDTH).filter { it > 0f }
                return RANKING_ROW_CHROME + columns.sum() + RANKING_GAP * (columns.size - 1) <= rowWidth
            }
            if (showMeta && !fitsName(withMeta = true)) showMeta = false
            stacked = !fitsName(withMeta = false)
        }

        fun required(): Float {
            val columns = listOf(rank, MIN_NAME_WIDTH * scale, if (showMeta) section.metaWidth else 0f, section.valueWidth, accuracy,
                if (showStars) STARS_WIDTH else 0f, CHEVRON_WIDTH).filter { it > 0f }
            return ROW_CHROME + columns.sum() + gap * (columns.size - 1)
        }

        if (showStars && required() > rowWidth) showStars = false
        if (score && showMeta && required() > rowWidth) showMeta = false
        if (!score && section.stackNarrowNames && known && rankingNameRoom(section, showMeta, rowWidth) < MIN_NAME_WIDTH) stacked = true
        return LeaderboardColumnPlan(
            gap = gap,
            rankWidth = rank,
            showMeta = showMeta,
            metaWidth = if (showMeta) section.metaWidth else 0f,
            valueWidth = section.valueWidth,
            showAccuracy = accuracy > 0f,
            accuracyWidth = accuracy,
            showStars = showStars,
            starsWidth = if (showStars) STARS_WIDTH else 0f,
            stacked = stacked,
        )
    }

    /**
     * The width a one-line rankings row leaves its name (rank · name · songs · rating ·
     * chevron at the rankings row's padding and spacing).
     *
     * @param section Rankings section.
     * @param showMeta Whether the songs column shows.
     * @param rowWidth Row width in dp.
     * @return Name width in dp (negative when the fixed columns already overflow).
     */
    fun rankingNameRoom(section: LeaderboardSection, showMeta: Boolean, rowWidth: Float): Float {
        val rank = if (section.rankWidth <= 0f) 0f else maxOf(section.rankWidth, MIN_RANKING_RANK_WIDTH)
        val fixed = listOf(rank, if (showMeta) section.metaWidth else 0f, section.valueWidth, CHEVRON_WIDTH).filter { it > 0f }
        return rowWidth - RANKING_ROW_CHROME - fixed.sum() - RANKING_GAP * fixed.size
    }
}

// endregion
