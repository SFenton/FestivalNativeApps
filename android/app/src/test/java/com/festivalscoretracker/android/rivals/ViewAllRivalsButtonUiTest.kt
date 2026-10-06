package com.festivalscoretracker.android.rivals

import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.rivals.RivalDirection
import com.festivalscoretracker.android.core.rivals.RivalEntry
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.core.rivals.RivalText
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.design.VIEW_FULL_LEADERBOARD
import com.festivalscoretracker.android.ui.design.ViewFullLeaderboardButton
import com.festivalscoretracker.android.ui.design.viewAllSpokenName
import com.festivalscoretracker.android.ui.rivals.RivalPreviewRows
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Issues #68/#176: every "View All Rivals" button (Rivals hub cards and Compete Rivals
 * cards, both drawn by [RivalPreviewRows]) is the shared purple
 * [ViewFullLeaderboardButton], so it matches "View Full Leaderboard(s)" in size, fill,
 * role and large-text behaviour.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class ViewAllRivalsButtonUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val entry = RivalEntry(RivalSummary(RivalsFixtures.RIVALS[0], "Synthetic Alpha", 1.0, sharedSongCount = 10, aheadCount = 6, behindCount = 4), RivalDirection.Above)

    /** Renders the hub/Compete "View All Rivals" and Compete's "View Full Leaderboards" in equal-width lanes. */
    private fun renderPair(fontScale: Float = 1f, width: Int = 379, viewAllLabel: String = RivalText.VIEW_ALL_RIVALS, onViewAll: () -> Unit = {}) {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                FestivalTheme {
                    Column {
                        Box(Modifier.requiredWidth(width.dp)) { RivalPreviewRows(listOf(entry), onRival = {}, onViewAll = onViewAll, viewAllLabel = viewAllLabel) }
                        Box(Modifier.requiredWidth(width.dp)) {
                            ViewFullLeaderboardButton(onClick = {}, label = CompeteText.VIEW_FULL_LEADERBOARDS, testTag = "fst.compete.view-full-leaderboards")
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun layout(text: String): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        rule.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action!!.invoke(results)
        return results.single()
    }

    private fun assertClose(expected: Color, actual: Color, what: String) {
        val close = abs(expected.red - actual.red) < 0.02f && abs(expected.green - actual.green) < 0.02f && abs(expected.blue - actual.blue) < 0.02f
        assertTrue("$what: expected $expected, got $actual", close)
    }

    @Test
    fun viewAllRivalsHasTheViewFullLeaderboardSizeFillAndRole() {
        var opened = 0
        renderPair(onViewAll = { opened++ })
        val rivals = rule.onNodeWithTag("fst.rivals.view-all").fetchSemanticsNode()
        val board = rule.onNodeWithTag("fst.compete.view-full-leaderboards").fetchSemanticsNode()

        assertEquals("same bounds as View Full Leaderboards", board.size, rivals.size)
        assertTrue("48 dp minimum target", rivals.size.height >= with(rule.density) { 48.dp.roundToPx() })
        assertEquals(Role.Button, rivals.config[SemanticsProperties.Role])
        assertEquals(RivalText.VIEW_ALL_RIVALS, rivals.config[SemanticsProperties.Text].joinToString())

        // Draw the window (native graphics) and sample the fill clear of the rounded corners and the centred label.
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        fun pixel(node: androidx.compose.ui.semantics.SemanticsNode, x: Int): Color {
            val origin = node.positionInWindow
            return Color(bitmap.getPixel(origin.x.toInt() + x, origin.y.toInt() + node.size.height / 2))
        }
        for (x in listOf(rivals.size.width / 20, rivals.size.width - rivals.size.width / 20)) {
            assertClose(BrandTokens.accentPurple, pixel(rivals, x), "View All Rivals fill at $x")
            assertEquals("fill at $x", pixel(board, x), pixel(rivals, x))
        }

        rule.onNodeWithTag("fst.rivals.view-all").performSemanticsAction(SemanticsActions.OnClick)
        assertEquals(1, opened)
    }

    @Test
    fun competeLabelUsesTheSameButton() {
        renderPair(viewAllLabel = CompeteText.VIEW_ALL_RIVALS)
        val rivals = rule.onNodeWithTag("fst.rivals.view-all").fetchSemanticsNode()
        assertEquals("View All Rivals", rivals.config[SemanticsProperties.Text].joinToString())
        assertEquals(rule.onNodeWithTag("fst.compete.view-full-leaderboards").fetchSemanticsNode().size, rivals.size)
    }

    @Test
    fun largeTextGrowsBothButtonsAlikeWithoutClipping() = assertLargeTextFits(379)

    /** A Book Fold half-open lane (about 260 dp): the labels wrap and the buttons grow instead of clipping. */
    @Test
    fun largeTextInANarrowLaneWrapsWithoutClipping() = assertLargeTextFits(260)

    private fun assertLargeTextFits(width: Int) {
        renderPair(fontScale = 2f, width = width)
        val rivals = rule.onNodeWithTag("fst.rivals.view-all").fetchSemanticsNode()
        val board = rule.onNodeWithTag("fst.compete.view-full-leaderboards").fetchSemanticsNode()
        val label = layout(RivalText.VIEW_ALL_RIVALS)

        for ((name, result) in listOf("View All Rivals" to label, "View Full Leaderboards" to layout(CompeteText.VIEW_FULL_LEADERBOARDS))) {
            // didOverflowWidth is an artefact of the centred label's slow-path layout; height and ellipsis are what clip.
            assertFalse("$name label cut off vertically at font scale 2.0", result.didOverflowHeight)
            assertFalse("$name label ellipsized at font scale 2.0", result.isLineEllipsized(result.lineCount - 1))
        }
        val text = rule.onNodeWithText(RivalText.VIEW_ALL_RIVALS, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        val button = rivals.boundsInRoot
        assertTrue("label $text inside button $button", text.left >= button.left && text.right <= button.right && text.top >= button.top && text.bottom <= button.bottom)
        assertEquals("same width at font scale 2.0", board.size.width, rivals.size.width)
        assertTrue("48 dp minimum target", rivals.size.height >= with(rule.density) { 48.dp.roundToPx() })
    }

    @Test
    fun noViewAllWithoutAnAction() {
        rule.setContent { FestivalTheme { RivalPreviewRows(listOf(entry), onRival = {}, onViewAll = null) } }
        assertEquals(0, rule.onAllNodesWithTag("fst.rivals.view-all").fetchSemanticsNodes().size)
    }

    /** `view-all-cta` R4: TalkBack reads the visible label first, then the card; the visible label is unchanged. */
    @Test
    fun spokenNameStartsWithTheLabelThenNamesTheCard() {
        rule.setContent {
            FestivalTheme {
                Column {
                    RivalPreviewRows(listOf(entry), onRival = {}, onViewAll = {}, cardName = "Lead")
                    ViewFullLeaderboardButton(onClick = {}, label = CompeteText.VIEW_FULL_LEADERBOARDS, testTag = "fst.compete.view-full-leaderboards", cardName = "Lead")
                    ViewFullLeaderboardButton(onClick = {}, testTag = "fst.unnamed")
                }
            }
        }
        val rivals = rule.onNodeWithTag("fst.rivals.view-all").fetchSemanticsNode().config
        assertEquals(listOf("View All Rivals, Lead"), rivals[SemanticsProperties.ContentDescription])
        // TalkBack hears the name once: the visible label stays on screen but leaves the merged semantics (as SeeAllButton).
        assertFalse("label not read twice", rivals.contains(SemanticsProperties.Text))
        rule.onNodeWithTag("fst.rivals.view-all.label", useUnmergedTree = true).assertIsDisplayed()
        val board = rule.onNodeWithTag("fst.compete.view-full-leaderboards").fetchSemanticsNode().config
        assertEquals(listOf("View Full Leaderboards, Lead"), board[SemanticsProperties.ContentDescription])
        assertEquals(Role.Button, board[SemanticsProperties.Role])
        val unnamed = rule.onNodeWithTag("fst.unnamed").fetchSemanticsNode().config
        assertFalse("no card: the label alone", unnamed.contains(SemanticsProperties.ContentDescription))
        assertEquals(VIEW_FULL_LEADERBOARD, unnamed[SemanticsProperties.Text].joinToString())
    }

    @Test
    fun spokenNameFallsBackToTheLabel() {
        assertEquals("View All Rivals", viewAllSpokenName("View All Rivals", null))
        assertEquals("View All Rivals", viewAllSpokenName("View All Rivals", "  "))
        assertEquals("View All Rivals, Lead Guitar", viewAllSpokenName("View All Rivals", " Lead Guitar "))
    }
}
