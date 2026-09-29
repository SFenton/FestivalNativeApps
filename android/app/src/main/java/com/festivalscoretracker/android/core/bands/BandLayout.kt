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
