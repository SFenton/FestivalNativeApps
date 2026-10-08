package com.festivalscoretracker.android.testing

import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.SemanticsNodeInteractionsProvider
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import org.junit.Assert.assertTrue
import kotlin.math.abs

/**
 * Checks for the shared empty state's region (`empty-error-states` R2, issue #377): the state
 * fills the usable result region between the page controls above it and the pager or footer
 * below it, and its text block sits in that region's centre at any window height.
 */
object EmptyRegionAssertions {
    /**
     * Window bounds of the first node tagged [tag] (unmerged tree).
     *
     * @param tag Test tag.
     * @return Bounds in the window.
     */
    fun SemanticsNodeInteractionsProvider.boundsOf(tag: String): Rect =
        onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow

    /**
     * Asserts the empty state tagged [regionTag] starts [gapAbove] dp below [above], ends
     * [gapBelow] dp above [belowTop] (both ±2 dp) and centres the text from [firstText] to
     * [lastText] in itself (±2 dp).
     *
     * @param regionTag The empty state's region tag.
     * @param above Bounds of the controls above the region.
     * @param gapAbove List spacing between the controls and the region, in dp.
     * @param belowTop Window y (px) where the usable region ends below: the pager or footer top,
     *   or the list's bottom less its content padding.
     * @param gapBelow List spacing between the region and [belowTop], in dp.
     * @param firstText The empty state's title.
     * @param lastText Its last line (the subtitle, or the title again).
     * @param density Pixels per dp.
     */
    fun SemanticsNodeInteractionsProvider.assertFillsAndCentres(
        regionTag: String,
        above: Rect,
        gapAbove: Float,
        belowTop: Float,
        gapBelow: Float,
        firstText: String,
        lastText: String,
        density: Float,
    ) {
        val region = boundsOf(regionTag)
        val title = onAllNodesWithText(firstText, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow
        val last = onAllNodesWithText(lastText, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow
        fun dp(px: Float) = px / density
        assertTrue("region $region starts ${gapAbove}dp below the controls $above", abs(dp(region.top - above.bottom) - gapAbove) <= 2f)
        assertTrue("region $region ends ${gapBelow}dp above $belowTop", abs(dp(belowTop - region.bottom) - gapBelow) <= 2f)
        val textCentre = (title.top + last.bottom) / 2
        assertTrue("text centre $textCentre in region ${region.top}..${region.bottom}", abs(dp(textCentre - region.center.y)) <= 2f)
        assertTrue("centred horizontally", abs(dp(title.center.x - region.center.x)) <= 2f)
    }
}
