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
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.bands.BandLayout
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.ui.bands.BandMemberChips
import com.festivalscoretracker.android.ui.bands.BandSegmentedControl
import com.festivalscoretracker.android.ui.bands.PlayerBandCard
import com.festivalscoretracker.android.ui.bands.PlayerBandsLayout
import com.festivalscoretracker.android.ui.bands.playerBandAnnouncement
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Player Bands layout states the whole-shell journeys cannot reach on Robolectric: the
 * half-open fold split, 200% font scale in a narrow card or segmented control, and the
 * card's TalkBack button semantics (issue #117).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PlayerBandsLayoutUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val sixCharts = listOf("Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "Solo_PeripheralGuitar", "Solo_PeripheralBass")
    private val entry = PlayerBandEntry(
        bandId = "band-x",
        teamKey = "a:b",
        bandType = "Band_Duets",
        appearanceCount = 142,
        members = listOf(BandMember("a".repeat(32), "SFentonX", sixCharts), BandMember("b".repeat(32), "Phankie.ToT", sixCharts.take(5))),
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

    private fun lineCount(text: String): Int {
        val layouts = mutableListOf<TextLayoutResult>()
        rule.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        return layouts.first().lineCount
    }

    private fun overflows(text: String): Boolean {
        val layouts = mutableListOf<TextLayoutResult>()
        rule.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        return layouts.first().let {
            assertFalse("$text clipped vertically", it.didOverflowHeight)
            // Robolectric reports didOverflowWidth for sub-pixel rounding; compare the full width instead.
            it.isLineEllipsized(0) || it.multiParagraph.intrinsics.maxIntrinsicWidth > it.layoutInput.constraints.maxWidth
        }
    }

    @Composable
    private fun groups(selected: PlayerBandGroup) {
        BandSegmentedControl(
            options = PlayerBandGroup.entries,
            selected = selected,
            label = { if (it == PlayerBandGroup.All) "All" else it.label },
            tag = { "group.${it.wireId}" },
            onSelect = {},
        )
    }

    // region Fold split

    @Test
    fun halfOpenFoldKeepsControlsAndCardsOnOppositeSides() {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.size(700.dp, 600.dp)) {
                    PlayerBandsLayout(BandLayout.Panes(true, 340f, 20f), BandLayout.grid(700f, null), PaddingValues(0.dp), "list", controls = { Text("Header") }) {
                        item { Text("Card") }
                    }
                }
            }
        }
        val controls = rule.onNodeWithTag("list.controls-pane").getUnclippedBoundsInRoot()
        val cards = rule.onNodeWithTag("list").getUnclippedBoundsInRoot()
        assertEquals(340f, controls.right.value, 0.5f)
        assertEquals(360f, cards.left.value, 0.5f)
        val header = rule.onNodeWithText("Header").getUnclippedBoundsInRoot()
        val card = rule.onNodeWithText("Card").getUnclippedBoundsInRoot()
        assertTrue("header $header", header.right <= controls.right)
        assertTrue("card $card", card.left >= cards.left)
    }

    @Test
    fun singlePaneKeepsControlsAboveTheCardGrid() {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.size(700.dp, 600.dp)) {
                    PlayerBandsLayout(BandLayout.listSplit(null), BandLayout.grid(700f, null), PaddingValues(0.dp), "list", controls = { Text("Header") }) {
                        item { Text("Card A") }
                        item { Text("Card B") }
                    }
                }
            }
        }
        assertEquals(0, rule.onAllNodes(hasTestTag("list.controls-pane")).fetchSemanticsNodes().size)
        val header = rule.onNodeWithText("Header").getUnclippedBoundsInRoot()
        val a = rule.onNodeWithText("Card A").getUnclippedBoundsInRoot()
        val b = rule.onNodeWithText("Card B").getUnclippedBoundsInRoot()
        assertTrue("header $header card $a", header.bottom <= a.top)
        // 700 dp fits two 320 dp columns side by side.
        assertEquals(a.top.value, b.top.value, 0.5f)
        assertTrue("a $a b $b", b.left > a.right)
    }

    // endregion

    // region Large text

    @Test
    fun groupLabelsFitAPhoneAt200Percent() {
        show(2f, 379) { groups(PlayerBandGroup.Quads) }
        listOf("All", "Duos", "Trios", "Quads").forEach { assertFalse("$it is ellipsized", overflows(it)) }
        rule.onNodeWithTag("group.${PlayerBandGroup.Quads.wireId}").assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, true))
        assertTrue(rule.onNodeWithTag("group.${PlayerBandGroup.All.wireId}").getUnclippedBoundsInRoot().let { it.bottom - it.top } >= 48.dp)
    }

    @Test
    fun memberNameMovesUnderItsIconsAt200Percent() {
        show(2f, 240) { BandMemberChips(entry.members.take(1)) }
        assertEquals("name must not break mid-word", 1, lineCount("SFentonX"))
    }

    @Test
    fun cardAppearancesStayOnOneLineAt200Percent() {
        show(2f, 300) { PlayerBandCard(entry, onClick = {}) }
        assertEquals(1, lineCount("142 appearances"))
        assertEquals(1, lineCount("Phankie.ToT"))
    }

    @Test
    fun cardKeepsDefaultLayoutAtDefaultText() {
        show(1f, 379) { PlayerBandCard(entry, onClick = {}) }
        val pill = rule.onNodeWithText("Duos", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val appearances = rule.onNodeWithText("142 appearances", useUnmergedTree = true).getUnclippedBoundsInRoot()
        assertTrue("pill $pill appearances $appearances", appearances.left >= pill.right && appearances.top < pill.bottom)
    }

    // endregion

    // region Semantics

    @Test
    fun cardIsAnOpenBandButtonThatReadsTheBand() {
        var opened = 0
        show(1f, 411) { PlayerBandCard(entry, onClick = { opened++ }) }
        val card = rule.onNodeWithTag("fst.player-bands.row.band-x")
        card.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        card.assertContentDescriptionEquals("SFentonX + Phankie.ToT, Duos, 142 appearances")
        assertEquals(playerBandAnnouncement(entry), "SFentonX + Phankie.ToT, Duos, 142 appearances")
        assertEquals("Open band", card.fetchSemanticsNode().config[SemanticsActions.OnClick].label)
        card.performClick()
        assertEquals(1, opened)
    }

    @Test
    fun unknownBandTypeReadsAsBand() {
        assertEquals("SFentonX + Phankie.ToT, Band, 142 appearances", playerBandAnnouncement(entry.copy(bandType = "Band_Unknown")))
    }

    // endregion
}
