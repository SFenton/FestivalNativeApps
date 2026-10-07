package com.festivalscoretracker.android.ui.leaderboards

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Pixels of the board's footer edge (issues #93, #308): rows are hidden beneath a transparent
 * floating footer and fade out over the 40 dp linear ramp above it (the web board's `useScrollMask`),
 * unless the board opts out. Accessibility modes keep the cut with no ramp (scroll-edge R7).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w400dp-h800dp-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BoardFooterFadeDrawUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    /** A 400 × 800 dp board of red rows on blue, under a transparent 100 dp footer. */
    private fun board(fade: Boolean, accessibility: FestivalAccessibility = FestivalAccessibility()): Board {
        rule.setContent {
            CompositionLocalProvider(LocalFestivalAccessibility provides accessibility) {
                Box(Modifier.size(400.dp, 800.dp).background(Color.Blue).testTag("board")) {
                    RankingsBoardLayout(
                        hinge = null,
                        measure = Modifier,
                        padding = PaddingValues(),
                        listState = rememberLazyListState(),
                        idPrefix = "fst.t",
                        controls = {},
                        footer = { Box(Modifier.fillMaxWidth().height(100.dp)) },
                        pager = {},
                        fadeAboveFooter = fade,
                    ) {
                        items(100) { Box(Modifier.fillMaxWidth().height(40.dp).background(Color.Red).testTag("row.$it")) }
                    }
                }
            }
        }
        rule.waitForIdle()
        val origin = rule.onNodeWithTag("board").fetchSemanticsNode().positionInWindow
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        return Board(bitmap, origin.x.toInt(), origin.y.toInt())
    }

    /** The window drawn into [bitmap], with the board's top-left at ([x], [y]); 1 px = 1 dp. */
    private class Board(val bitmap: Bitmap, val x: Int, val y: Int) {
        fun redAt(row: Int): Float = android.graphics.Color.red(bitmap.getPixel(x + 200, y + row)) / 255f
        fun redIn(rows: IntRange): Boolean = rows.any { redAt(it) > 0.5f }
    }

    @Test
    fun rowsAreHiddenBeneathTheFooterAndFadeAboveIt() {
        val image = board(fade = true)
        val cut = rule.onNodeWithTag("fst.t.bottom-bar").fetchSemanticsNode().positionInWindow.y.toInt() - image.y
        assertFalse("no row shows beneath the footer", image.redIn(cut + 1 until 800))
        assertTrue("rows above the band are untouched", (cut - 200 until cut - 41).all { image.redAt(it).let { r -> r > 0.95f || r < 0.02f } })
        assertTrue(image.redIn(cut - 200 until cut - 41))
        // The 40 dp linear ramp fades out towards the cut (rows sit 12 dp apart, so gaps read 0).
        val band = (cut - 40 until cut).filter { image.redAt(it) > 0.01f }
        assertTrue(band.size > 20)
        assertTrue(band.zipWithNext().all { (a, b) -> image.redAt(b) <= image.redAt(a) + 0.01f })
        assertTrue("never above the linear ramp", (cut - 40 until cut).all { image.redAt(it) <= (cut - it) / 40f + 0.05f })
        assertTrue("linear, not eased", band.any { image.redAt(it) in 0.3f..0.7f })
        assertTrue(image.redAt(cut - 1) < 0.1f)
    }

    @Test
    fun otherBoardsKeepRowsScrollingUnderTheFooter() {
        assertTrue(board(fade = false).redIn(700 until 800))
    }

    @Test
    fun reduceTransparencyCutsRowsAtAHardEdge() = assertHardEdge(FestivalAccessibility(reduceTransparency = true))

    @Test
    fun increaseContrastCutsRowsAtAHardEdge() = assertHardEdge(FestivalAccessibility(increaseContrast = true))

    @Test
    fun reduceMotionCutsRowsAtAHardEdge() = assertHardEdge(FestivalAccessibility(reduceMotion = true))

    /** R7: no ramp, but rows still never show beneath the footer, and hidden rows leave TalkBack (#190). */
    private fun assertHardEdge(accessibility: FestivalAccessibility) {
        val image = board(fade = true, accessibility)
        val cut = rule.onNodeWithTag("fst.t.bottom-bar").fetchSemanticsNode().positionInWindow.y.toInt() - image.y
        assertFalse("no row shows beneath the footer", image.redIn(cut + 1 until 800))
        assertTrue("rows are opaque up to the cut", (cut - 200 until cut).all { image.redAt(it).let { r -> r > 0.95f || r < 0.02f } })
        assertTrue(image.redIn(cut - 40 until cut))
        rule.onNodeWithTag("row.14").assertIsNotDisplayed()
    }

    /**
     * Rows covered by the bottom bar are neither visible nor reachable under each accessibility
     * hard-edge setting (scroll-edge R7, issue #306): the list still ends at the footer's top.
     */
    private fun assertCoveredRowsLeaveTalkBack(accessibility: FestivalAccessibility) {
        board(fade = true, accessibility)
        rule.onNodeWithTag("row.0").assertIsDisplayed()
        rule.onNodeWithTag("row.14").assertIsNotDisplayed()
        val list = rule.onNodeWithTag("fst.t.list").fetchSemanticsNode().boundsInRoot
        val footer = rule.onNodeWithTag("fst.t.bottom-bar").fetchSemanticsNode().boundsInRoot
        assertTrue("the list ends at the footer's top", list.bottom <= footer.top + 1f)
    }

    @Test
    fun reduceTransparencyHidesCoveredRowsFromTalkBack() = assertCoveredRowsLeaveTalkBack(FestivalAccessibility(reduceTransparency = true))

    @Test
    fun increaseContrastHidesCoveredRowsFromTalkBack() = assertCoveredRowsLeaveTalkBack(FestivalAccessibility(increaseContrast = true))

    @Test
    fun reduceMotionHidesCoveredRowsFromTalkBack() = assertCoveredRowsLeaveTalkBack(FestivalAccessibility(reduceMotion = true))

    /**
     * Rows hidden beneath the footer leave the accessibility tree (issue #104): TalkBack would
     * otherwise skip a row fully covered by the footer and focus hidden rows below it instead
     * of scrolling. Row 14 (736..776 dp, wholly behind the 100 dp footer) is the probe; row 0 stays.
     */
    @Test
    fun rowsHiddenBeneathTheFooterLeaveTalkBack() {
        board(fade = true)
        rule.onNodeWithTag("row.0").assertIsDisplayed()
        rule.onNodeWithTag("row.14").assertIsNotDisplayed()
        val list = rule.onNodeWithTag("fst.t.list").fetchSemanticsNode().boundsInRoot
        val footer = rule.onNodeWithTag("fst.t.bottom-bar").fetchSemanticsNode().boundsInRoot
        assertTrue("the list ends at the footer's top", list.bottom <= footer.top + 1f)
    }

    @Test
    fun rowsUnderAVisibleFooterStayReachable() {
        board(fade = false)
        rule.onNodeWithTag("row.14").assertIsDisplayed()
    }

    /**
     * A board of 30 rows above a 48 dp pager and, when [withScore], a 56 dp pinned score row,
     * scrolled to its end. Returns the gap in dp between the last row and the first footer element.
     */
    private fun endGap(withScore: Boolean): Float {
        rule.setContent {
            Box(Modifier.size(400.dp, 800.dp)) {
                RankingsBoardLayout(
                    hinge = null,
                    measure = Modifier,
                    padding = PaddingValues(bottom = 96.dp),
                    listState = rememberLazyListState(),
                    idPrefix = "fst.t",
                    controls = { Box(Modifier.fillMaxWidth().height(80.dp)) },
                    footer = { if (withScore) Box(Modifier.fillMaxWidth().height(56.dp).testTag("score")) },
                    pager = { Box(Modifier.fillMaxWidth().height(48.dp).testTag("pager")) },
                    fadeAboveFooter = true,
                ) {
                    items(30) { Box(Modifier.fillMaxWidth().height(40.dp).testTag("row.$it")) }
                }
            }
        }
        rule.onNodeWithTag("fst.t.list").performScrollToIndex(30)
        rule.waitForIdle()
        val last = rule.onNodeWithTag("row.29").fetchSemanticsNode()
        val lastBottom = last.positionInRoot.y + last.size.height
        val next = rule.onNodeWithTag(if (withScore) "score" else "pager").fetchSemanticsNode().positionInRoot.y
        return next - lastBottom
    }

    /** Issue #293: the pinned score row follows the last row at the list's own 12 dp item gap. */
    @Test
    fun lastRowSitsOneItemGapAboveThePinnedScore() {
        assertEquals(12f, endGap(withScore = true), 0.5f)
    }

    /** Issue #293: without a score row, the pager follows the last row with no empty score slot. */
    @Test
    fun lastRowSitsOneItemGapAboveThePagerWithoutAScore() {
        assertEquals(12f, endGap(withScore = false), 0.5f)
    }
}
