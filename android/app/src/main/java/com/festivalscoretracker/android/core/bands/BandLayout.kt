package com.festivalscoretracker.android.core.bands

import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import kotlin.math.max
import kotlin.math.min

// region Adaptive geometry

/**
 * Pure adaptive geometry for band pages (all values in dp, unit-tested).
 *
 * Material 3 window classes decide *whether* content splits (expanded width ≥ 840 dp,
 * or a separating hinge such as a half-open book fold); a vertical fold or hinge
 * reported by Jetpack WindowManager decides *where*, so no card, pane or gutter
 * ever straddles the crease.
 */
object BandLayout {
    /** Expanded window-width breakpoint. */
    const val EXPANDED_WIDTH = 840f

    /** Minimum band card width. */
    const val CARD_MIN = 320f

    /** Outer content margin and half-gutter around a hinge. */
    const val EDGE = 16f

    /** Gutter between cards without a hinge. */
    const val GUTTER = 12f

    /** Gap between panes without a hinge. */
    const val PANE_GAP = 24f

    /** Smallest share of the content either side of a flat fold must keep to anchor panes. */
    const val BALANCED_SHARE = 0.4f

    /** Narrowest side a hinge may leave for a pane or column. */
    const val MIN_SIDE = 200f

    /**
     * A vertical fold/hinge in content coordinates.
     *
     * @property left Leading edge.
     * @property right Trailing edge (equal to [left] for a zero-width fold).
     * @property separating Whether WindowManager reports it as separating (half-open, or a physical hinge).
     */
    data class Hinge(val left: Float, val right: Float, val separating: Boolean)

    /**
     * Two-pane decision.
     *
     * @property twoPane Whether content splits.
     * @property leadingWidth Leading pane width when split at a hinge, else null (equal weights).
     * @property gap Gap between panes.
     */
    data class Panes(val twoPane: Boolean, val leadingWidth: Float?, val gap: Float)

    /**
     * Card grid geometry.
     *
     * @property columns Column count.
     * @property start Leading content padding.
     * @property end Trailing content padding.
     * @property gutter Gap between columns.
     */
    data class Grid(val columns: Int, val start: Float, val end: Float, val gutter: Float)

    /**
     * Convert a window-space vertical hinge into content coordinates.
     *
     * @param windowLeft Hinge leading edge in the window.
     * @param windowRight Hinge trailing edge in the window.
     * @param contentLeft Content box's leading edge in the window.
     * @param contentWidth Content width.
     * @param separating WindowManager `isSeparating`.
     * @return The hinge, or null when it leaves less than [MIN_SIDE] on either side of the content.
     */
    fun hingeInContent(windowLeft: Float, windowRight: Float, contentLeft: Float, contentWidth: Float, separating: Boolean): Hinge? {
        val left = windowLeft - contentLeft
        val right = windowRight - contentLeft
        if (left < MIN_SIDE || right > contentWidth - MIN_SIDE) return null
        return Hinge(left, right, separating)
    }

    /**
     * Whether and where Band Detail splits into panes.
     *
     * @param windowWidth Window width.
     * @param contentWidth Content width.
     * @param hinge Vertical hinge in content coordinates.
     * @return Panes.
     */
    fun panes(windowWidth: Float, contentWidth: Float, hinge: Hinge?): Panes {
        val split = windowWidth >= EXPANDED_WIDTH || hinge?.separating == true
        // A flat fold only anchors the split when both panes keep a balanced share (tri-fold outer folds do not).
        val anchor = hinge?.takeIf { it.separating || min(it.left, contentWidth - it.right) >= BALANCED_SHARE * contentWidth }
        return when {
            !split -> Panes(false, null, 0f)
            anchor != null -> Panes(true, anchor.left, anchor.right - anchor.left)
            else -> Panes(true, null, PANE_GAP)
        }
    }

    /**
     * Single-list pages (a song's band leaderboard): split into a controls pane and a rows
     * pane only across a **separating** hinge (half-open fold or physical hinge), meeting
     * exactly at it; a flat fold or a plain wide window keeps one centred column.
     *
     * @param hinge Vertical hinge in content coordinates.
     * @return Panes.
     */
    fun listSplit(hinge: Hinge?): Panes =
        if (hinge?.separating == true) Panes(true, hinge.left, hinge.right - hinge.left) else Panes(false, null, 0f)

    /**
     * The vertical hinge nearest the content's centre (a tri-fold reports two).
     *
     * @param hinges Candidate hinges in content coordinates.
     * @param contentWidth Content width.
     * @return The most central hinge, or null.
     */
    fun central(hinges: List<Hinge>, contentWidth: Float): Hinge? =
        hinges.minByOrNull { kotlin.math.abs((it.left + it.right) / 2 - contentWidth / 2) }

    /**
     * Card grid: as many ≥ [CARD_MIN] columns as fit; with a separating hinge, or a
     * fold when two columns fit anyway, exactly two columns whose gutter is the hinge.
     *
     * @param contentWidth Content width.
     * @param hinge Vertical hinge in content coordinates.
     * @return Grid geometry.
     */
    fun grid(contentWidth: Float, hinge: Hinge?): Grid {
        val fit = max(1, ((contentWidth - 2 * EDGE + GUTTER) / (CARD_MIN + GUTTER)).toInt())
        if (hinge != null && (hinge.separating || fit == 2)) {
            val column = min(hinge.left, contentWidth - hinge.right) - 2 * EDGE
            return Grid(2, hinge.left - EDGE - column, contentWidth - hinge.right - EDGE - column, hinge.right - hinge.left + 2 * EDGE)
        }
        return Grid(fit, EDGE, EDGE, GUTTER)
    }

    /** Statistics tile width at 100% text. */
    const val STAT_TILE_MIN = 150f

    /** Member card column width at large text (name above wrapping icons). */
    const val MEMBER_CARD_MIN = 260f

    /** Narrowest member name beside the instrument icons before the card stacks them under it. */
    const val MEMBER_NAME_MIN = 96f

    /** Instrument icon (28 dp) plus its 6 dp gap on a member card. */
    const val MEMBER_ICON_SLOT = 34f

    /** Member card horizontal padding (12 dp each side). */
    const val MEMBER_CARD_PADDING = 24f

    /**
     * Whether a member card fits its name ([MEMBER_NAME_MIN]) and every instrument icon on one
     * row; otherwise (large text, a half-width fold pane) the icons wrap under the name.
     *
     * @param cardWidth Card width.
     * @param instruments Most charted instruments on any member.
     * @param largeText Whether large-text reflow applies.
     * @return True for the one-row card.
     */
    fun memberInline(cardWidth: Float, instruments: Int, largeText: Boolean): Boolean =
        !largeText && cardWidth >= MEMBER_CARD_PADDING + MEMBER_NAME_MIN + instruments * MEMBER_ICON_SLOT

    /**
     * Members grid columns: as many cards as fit at the one-row width (a 7-instrument member
     * needs ≈ 358 dp), never narrower than [MEMBER_CARD_MIN].
     *
     * @param contentWidth Grid width.
     * @param instruments Most charted instruments on any member.
     * @param largeText Whether large-text reflow applies.
     * @return Column count (≥ 1).
     */
    fun memberColumns(contentWidth: Float, instruments: Int, largeText: Boolean): Int {
        val min = if (largeText) MEMBER_CARD_MIN else max(MEMBER_CARD_MIN, MEMBER_CARD_PADDING + MEMBER_NAME_MIN + instruments * MEMBER_ICON_SLOT)
        return max(1, ((contentWidth + GUTTER_MEMBERS) / (min + GUTTER_MEMBERS)).toInt())
    }

    /**
     * Width of each card in a [columns]-wide members grid.
     *
     * @param contentWidth Grid width.
     * @param columns Column count.
     * @return Card width.
     */
    fun memberCardWidth(contentWidth: Float, columns: Int): Float = (contentWidth - GUTTER_MEMBERS * (columns - 1)) / columns

    /** Gap between member cards. */
    private const val GUTTER_MEMBERS = 8f

    /**
     * Band Statistics tile columns: two to four [STAT_TILE_MIN] tiles normally; at large
     * text the tile minimum grows with the font scale and one column is allowed, so a
     * score such as "839,892,184" is never clipped.
     *
     * @param contentWidth Grid width.
     * @param fontScale System font scale.
     * @param largeText Whether large-text reflow applies.
     * @return Column count (1–4).
     */
    fun statColumns(contentWidth: Float, fontScale: Float, largeText: Boolean): Int {
        if (!largeText) return max(2, (contentWidth / STAT_TILE_MIN).toInt()).coerceAtMost(4)
        return max(1, (contentWidth / (STAT_TILE_MIN * max(1f, fontScale))).toInt()).coerceAtMost(4)
    }
}

// endregion

// region Quick Links

/** Band Detail Quick Links (web `BandPage` `quickLinks`). */
object BandQuickLinks {
    /**
     * Web order and labels: Members, Summary, Statistics, Rank History, Songs (short labels,
     * full landmark names for TalkBack).
     *
     * @return Sections.
     */
    fun sections(): List<QuickLinkSection> = listOf(
        QuickLinkSection("members", "Members", icon = "people"),
        QuickLinkSection("summary", "Summary", icon = "list", spokenTitle = "Band Summary"),
        QuickLinkSection("statistics", "Statistics", icon = "chart", spokenTitle = "Band Statistics"),
        QuickLinkSection("rank-history", "Rank History", icon = "trophy", spokenTitle = "Band Rank History"),
        QuickLinkSection("songs", "Songs", icon = "music", spokenTitle = "Band Songs"),
    )
}

// endregion
