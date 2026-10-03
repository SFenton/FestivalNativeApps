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
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.theme.FestivalAccessibility
import com.festivalscoretracker.android.ui.theme.LocalFestivalAccessibility
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Pixels of the board's footer edge (issue #93): rows are hidden beneath a transparent floating
 * footer and fade out above it, unless the board opts out or an accessibility mode keeps the
 * old hard edge.
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
        assertTrue("rows above the band are untouched", image.redIn(cut - 200 until cut - 41))
        // The 40 dp band eases out towards the cut.
        val band = (cut - 40 until cut).filter { image.redAt(it) > 0.01f }
        assertTrue(band.size > 20)
        assertTrue(band.zipWithNext().all { (a, b) -> image.redAt(b) <= image.redAt(a) + 0.01f })
        assertTrue(image.redAt(cut - 2) < 0.15f)
    }

    @Test
    fun otherBoardsKeepRowsScrollingUnderTheFooter() {
        assertTrue(board(fade = false).redIn(700 until 800))
    }

    @Test
    fun reduceTransparencyKeepsTheHardEdge() {
        assertTrue(board(fade = true, FestivalAccessibility(reduceTransparency = true)).redIn(700 until 800))
    }

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
}
