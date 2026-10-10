package com.festivalscoretracker.android.core.bands

import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import kotlin.math.max
import kotlin.math.min

// region Adaptive geometry

/**
 * Pure adaptive geometry for band pages (all values in dp, unit-tested).
 *
 * Material 3 window classes decide *whether* content splits (expanded width ≥ 840 dp,
 * or a separating hinge such as a half-open book fold). Only a **separating** vertical
 * fold or hinge reported by Jetpack WindowManager decides *where*, so no card, pane or
 * gutter straddles the crease in book posture. A flat (fully unfolded) fold is ignored:
 * panes and columns divide at the midpoint of the free content area, not the fold
 * (owner override, issue #361; Material 3 "Flat (unfolded): treat as Medium or Expanded").
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
     * Whether Band Detail shows two panes: an expanded window or a separating vertical hinge,
     * unless the page is forced to one column (screen reader, or large text on a narrow window).
     * The page decides this once so its pane layout and its Quick Links action always agree.
     *
     * @param windowWidth Window width.
     * @param separatingHinge Whether the window has a separating vertical hinge.
     * @param singleColumn Whether the page must stay one column.
     * @return True for two panes.
     */
    fun splits(windowWidth: Float, separatingHinge: Boolean, singleColumn: Boolean): Boolean =
        !singleColumn && (windowWidth >= EXPANDED_WIDTH || separatingHinge)

    /**
     * Whether and where Band Detail splits into panes: at a separating [hinge] (book
     * posture), otherwise into equal panes meeting at the content midpoint, including
     * across a flat fold (issue #361).
     *
     * @param windowWidth Window width.
     * @param hinge Vertical hinge in content coordinates.
     * @param split Whether to split; defaults to an expanded window or a separating [hinge].
     * @return Panes.
     */
    fun panes(windowWidth: Float, hinge: Hinge?, split: Boolean = windowWidth >= EXPANDED_WIDTH || hinge?.separating == true): Panes {
        val anchor = hinge?.takeIf { it.separating }
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
     * Card grid: as many ≥ [CARD_MIN] columns as fit; with a separating hinge, exactly two
     * columns whose gutter is the hinge. A flat fold keeps the natural grid, centred on the
     * content area (issue #361).
     *
     * @param contentWidth Content width.
     * @param hinge Vertical hinge in content coordinates.
     * @return Grid geometry.
     */
    fun grid(contentWidth: Float, hinge: Hinge?): Grid {
        val fit = max(1, ((contentWidth - 2 * EDGE + GUTTER) / (CARD_MIN + GUTTER)).toInt())
        if (hinge != null && hinge.separating) {
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

// region Band card members

/**
 * Member lines on band cards (web `PlayerBandCard` `BandMemberRow`): one member per line, the
 * name leading so every name in a card starts on the same edge, and the member's value and
 * instrument icons trailing. A card is either inline (name beside icons) or, when any member
 * can't fit, stacked (each name on its own line, its icons under it), never a mix, so the names
 * stay aligned row to row (issue #589). All values in dp.
 */
object BandMemberFit {
    /** Widest name a card reserves beside the icons (web `MAX_MEMBER_NAME_INLINE_WIDTH`); longer names scroll or truncate. */
    const val NAME_MAX = 180f

    /** Gap between a name, its value and its icons (web `BAND_MEMBER_INLINE_GAP`, `Gap.md`). */
    const val INLINE_GAP = 8f

    /** Gap between instrument icons on a band card. */
    const val ICON_GAP = 4f

    /** Gap between member lines (web `memberList` `Gap.md`). */
    const val LINE_GAP = 8f

    /**
     * What one member needs on an inline line.
     *
     * @property nameWidth Laid-out one-line name width.
     * @property valueWidth Laid-out value width (a member's song score), 0 for none.
     * @property instruments Charted instrument icons.
     */
    data class Member(val nameWidth: Float, val valueWidth: Float = 0f, val instruments: Int = 0)

    /**
     * Width of a row of icons.
     *
     * @param count Icons.
     * @param iconSize Icon size.
     * @return Width, 0 for none.
     */
    fun iconRowWidth(count: Int, iconSize: Float): Float = if (count <= 0) 0f else count * iconSize + (count - 1) * ICON_GAP

    /**
     * Width one member needs inline: its name clamped to [BandLayout.MEMBER_NAME_MIN]…[NAME_MAX]
     * (web `estimateMemberNameInlineWidth`), then its value and icons, each after [INLINE_GAP].
     *
     * @param member Member.
     * @param iconSize Icon size.
     * @return Width.
     */
    fun inlineWidth(member: Member, iconSize: Float): Float {
        val name = member.nameWidth.coerceIn(BandLayout.MEMBER_NAME_MIN, NAME_MAX)
        val value = if (member.valueWidth > 0f) INLINE_GAP + member.valueWidth else 0f
        val icons = iconRowWidth(member.instruments, iconSize).let { if (it > 0f) INLINE_GAP + it else 0f }
        return name + value + icons
    }

    /**
     * Whether the whole card draws its members inline (web `resolveBandCardMemberLayouts`: one
     * member that doesn't fit stacks every member). Large text always stacks, like Band Detail's
     * member cards ([BandLayout.memberInline]).
     *
     * @param contentWidth Width of the members column.
     * @param members Every member line in the card.
     * @param iconSize Icon size.
     * @param largeText Whether large-text reflow applies.
     * @return True for name-beside-icons lines.
     */
    fun inline(contentWidth: Float, members: List<Member>, iconSize: Float, largeText: Boolean): Boolean =
        !largeText && members.all { inlineWidth(it, iconSize) <= contentWidth }
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
