package com.festivalscoretracker.android.core.shell

// region Bottom chrome spacing

/**
 * Where a page's content ends above the bottom chrome (`page-tools-and-nav-chrome` R7, issue #578):
 * one standard gap above the chrome that is actually shown, never a band kept for chrome that is not.
 *
 * The bottom chrome is the shell's floating toolbar while the page has tools in it, otherwise the
 * bottom navigation bar (or the window's bottom safe edge beside a rail or drawer). A board's
 * pinned row and pager are anchored at this padding, so they rest one gap above that chrome
 * and the rows end one item gap above them (`leaderboard-row` R5, issue #293).
 */
object BottomChromeSpacing {
    /** Floating toolbar height (M3 Expressive floating toolbar), assumed until it has been drawn. */
    const val TOOLBAR_HEIGHT_DP = 64

    /**
     * One standard gap (Material 3's 16 dp compact margin): between the toolbar and the bottom bar,
     * and between the page's last content and the chrome below it.
     */
    const val GAP_DP = 16

    /**
     * The page content's bottom padding.
     *
     * @param baseDp Bottom chrome the content area does not already clear (the system navigation
     *   bar beside a rail or drawer; 0 above the bottom bar, which pads the gesture area itself).
     * @param toolbarHeightDp Height of the page's floating toolbar as drawn, 0 when it shows no tools.
     * @return The base, then the toolbar with the gap below it when it shows, then one gap.
     */
    fun contentBottomDp(baseDp: Float, toolbarHeightDp: Float): Float =
        baseDp + GAP_DP + if (toolbarHeightDp > 0f) toolbarHeightDp + GAP_DP else 0f
}

// endregion
