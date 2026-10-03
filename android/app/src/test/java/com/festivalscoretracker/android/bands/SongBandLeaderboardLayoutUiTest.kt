package com.festivalscoretracker.android.bands

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.performClick
import com.festivalscoretracker.android.ui.bands.BandScoreRow
import com.festivalscoretracker.android.ui.bands.bandScoreAnnouncement
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.SongBandLeaderboardEntry
import com.festivalscoretracker.android.ui.bands.BandMemberScoreLine
import com.festivalscoretracker.android.ui.bands.BandScoreFooter
import com.festivalscoretracker.android.ui.bands.SongBandLeaderboardLayout
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Song Band Leaderboard layout states the whole-shell journeys cannot reach on Robolectric:
 * the half-open fold split and 200% font scale in a narrow card (issue #103).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class SongBandLeaderboardLayoutUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val entry = SongBandLeaderboardEntry(
        bandId = "b",
        members = listOf(BandMember("a".repeat(32), "T3MP3ST_11", listOf("Solo_Guitar"), score = 156_912)),
        score = 931_020,
        rank = 1,
        accuracy = 1_000_000.0,
        isFullCombo = true,
        stars = 6,
    )

    private fun show(fontScale: Float, width: Int, content: @Composable () -> Unit) {
        rule.setContent {
            FestivalTheme {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    Box(Modifier.width(width.dp).testTag("container")) { content() }
                }
            }
        }
    }

    @Test
    fun halfOpenFoldKeepsControlsAndRowsOnOppositeSides() {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.size(700.dp, 600.dp)) {
                    SongBandLeaderboardLayout(BandLayout.Panes(true, 340f, 20f), PaddingValues(0.dp), controls = { Text("Header") }) {
                        item { Text("Row") }
                    }
                }
            }
        }
        val controls = rule.onNodeWithTag("fst.song-band-leaderboard.controls-pane").getUnclippedBoundsInRoot()
        val rows = rule.onNodeWithTag("fst.song-band-leaderboard.list").getUnclippedBoundsInRoot()
        assertEquals(340f, controls.right.value, 0.5f)
        assertEquals(360f, rows.left.value, 0.5f)
        val header = rule.onNodeWithText("Header").getUnclippedBoundsInRoot()
        val row = rule.onNodeWithText("Row").getUnclippedBoundsInRoot()
        assertTrue("header $header", header.right <= controls.right)
        assertTrue("row $row", row.left >= rows.left)
    }

    @Test
    fun singlePaneKeepsControlsAboveTheRows() {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.size(700.dp, 600.dp)) {
                    SongBandLeaderboardLayout(BandLayout.listSplit(null), PaddingValues(0.dp), controls = { Text("Header") }) {
                        item { Text("Row") }
                    }
                }
            }
        }
        assertEquals(0, rule.onAllNodesWithTagCount("fst.song-band-leaderboard.controls-pane"))
        val header = rule.onNodeWithText("Header").getUnclippedBoundsInRoot()
        val row = rule.onNodeWithText("Row").getUnclippedBoundsInRoot()
        assertTrue("header $header row $row", header.bottom <= row.top)
    }

    @Test
    fun footerWrapsGoldStarsInsteadOfClippingThemAt200Percent() {
        show(2f, 260) { BandScoreFooter(entry) }
        val container = rule.onNodeWithTag("container").getUnclippedBoundsInRoot()
        val stars = rule.onNodeWithContentDescription("Gold stars").getUnclippedBoundsInRoot()
        val score = rule.onNodeWithText("931,020").getUnclippedBoundsInRoot()
        // Five 14 dp stars with 2 dp gaps keep their full width, inside the card, under the score.
        assertEquals(78f, (stars.right - stars.left).value, 0.5f)
        assertTrue("stars $stars container $container", stars.right <= container.right)
        assertTrue("stars $stars score $score", stars.top >= score.bottom)
    }

    @Test
    fun footerKeepsOneLineAtDefaultText() {
        show(1f, 260) { BandScoreFooter(entry) }
        val stars = rule.onNodeWithContentDescription("Gold stars").getUnclippedBoundsInRoot()
        val score = rule.onNodeWithText("931,020").getUnclippedBoundsInRoot()
        assertTrue("stars $stars score $score", stars.top < score.bottom)
    }

    @Test
    fun memberScoreMovesUnderTheNameAt200Percent() {
        show(2f, 200) { BandMemberScoreLine(entry.members.first(), keyboard = false) }
        val name = rule.onNodeWithText("T3MP3ST_11", useUnmergedTree = true)
        val layouts = mutableListOf<TextLayoutResult>()
        name.fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        assertEquals("name must not break mid-word", 1, layouts.first().lineCount)
        val score = rule.onNodeWithText("156,912", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue("score $score name ${name.getUnclippedBoundsInRoot()}", score.top >= name.getUnclippedBoundsInRoot().bottom)
    }

    @Test
    fun memberScoreStaysBesideTheNameAtDefaultText() {
        show(1f, 260) { BandMemberScoreLine(entry.members.first(), keyboard = false) }
        val name = rule.onNodeWithText("T3MP3ST_11", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val score = rule.onNodeWithText("156,912", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue("score $score name $name", score.left >= name.right)
    }

    @Test
    fun rowIsAnOpenBandButtonThatReadsItsScore() {
        var opened = 0
        show(1f, 411) { BandScoreRow(entry, song = null, onClick = { opened++ }) }
        val row = rule.onNodeWithTag("fst.song-band-leaderboard.row.${entry.key}")
        row.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        row.assertContentDescriptionEquals(bandScoreAnnouncement(entry))
        assertEquals("Open band", row.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
        row.performClick()
        assertEquals(1, opened)
    }

    private fun androidx.compose.ui.test.junit4.ComposeContentTestRule.onAllNodesWithTagCount(tag: String) =
        onAllNodes(androidx.compose.ui.test.hasTestTag(tag)).fetchSemanticsNodes().size
}
