package com.festivalscoretracker.android.ui.search

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertHasClickAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.GlobalSongResult
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.presentation.search.GlobalSearchUiState
import com.festivalscoretracker.android.presentation.search.SectionPhase
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/** Stateless search content: progress rings and one full-height region for every state (6.21). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-mdpi")
class GlobalSearchContentUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun show(ui: GlobalSearchUiState) {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxWidth().height(600.dp)) {
                    GlobalSearchContent(ui, { null }, {}, {}, {}, {})
                }
            }
        }
    }

    @Test
    fun playersProgressIsARingNotALine() {
        show(GlobalSearchUiState(query = "alpha", settledQuery = "alpha", songsPhase = SectionPhase.Empty, playersPhase = SectionPhase.Loading))
        val ring = rule.onNodeWithTag(GlobalSearchTags.PLAYERS_LOADING)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
            .fetchSemanticsNode().boundsInRoot
        // A 24 dp ring (mdpi: 1 px per dp), not a full-width line.
        assertEquals(24f, ring.width, 0.5f)
        assertEquals(ring.width, ring.height, 0.5f)
    }

    @Test
    fun wholePanelProgressIsCentredInTheFullRegion() {
        show(GlobalSearchUiState(query = "alpha", scope = SearchScope.All, debouncing = true))
        val spinner = rule.onNodeWithTag(GlobalSearchTags.LOADING).fetchSemanticsNode().boundsInRoot
        // Centred in the region below the pills, not pinned to a small box at the top.
        assertTrue("spinner at ${spinner.center.y}", spinner.center.y > 250f)
    }

    private val song = GlobalSongResult("s-the", "The Song", "Band One", null)

    @Test
    fun playersScopeEmptyIsACentredTitleSubtitleAndRetry() {
        show(GlobalSearchUiState(query = "The", settledQuery = "The", scope = SearchScope.Players, songs = listOf(song), songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Empty))
        // Issue #99: no "Players" section with a left-aligned inline row.
        rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Players)).assertDoesNotExist()
        val region = rule.onNodeWithTag(GlobalSearchTags.EMPTY).fetchSemanticsNode().boundsInRoot
        val title = rule.onNodeWithText(GlobalSearchResults.EMPTY_PLAYERS_TITLE)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
            .fetchSemanticsNode().boundsInRoot
        val subtitle = rule.onNodeWithText(GlobalSearchResults.EMPTY_PLAYERS_SUBTITLE).fetchSemanticsNode().boundsInRoot
        val retry = rule.onNodeWithTag(GlobalSearchTags.RETRY).assertHasClickAction().fetchSemanticsNode().boundsInRoot
        // Horizontally centred text, Retry centred under the subtitle.
        assertEquals(region.center.x, title.center.x, 1f)
        assertEquals(region.center.x, subtitle.center.x, 1f)
        assertEquals(region.center.x, retry.center.x, 1f)
        assertTrue(title.bottom <= subtitle.top && subtitle.bottom <= retry.top)
        // Vertically centred: the block's middle is the region's middle.
        val block = (title.top + retry.bottom) / 2
        assertEquals(region.center.y, block, 2f)
        assertTrue(retry.height >= 48f)
    }

    @Test
    fun allScopeHidesAnEmptyPlayersSectionNextToSongs() {
        show(GlobalSearchUiState(query = "The", settledQuery = "The", songs = listOf(song), songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Empty))
        rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Songs)).assertExists()
        rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Players)).assertDoesNotExist()
        rule.onNodeWithTag(GlobalSearchTags.EMPTY).assertDoesNotExist()
        rule.onNodeWithTag(GlobalSearchTags.RETRY).assertDoesNotExist()
    }

    @Test
    fun allEmptyHasTitleSubtitleAndRetry() {
        show(GlobalSearchUiState(query = "zzzz", settledQuery = "zzzz", songsPhase = SectionPhase.Empty, playersPhase = SectionPhase.Empty))
        rule.onNodeWithText(GlobalSearchResults.EMPTY_ALL_TITLE).assertIsDisplayed()
        rule.onNodeWithText(GlobalSearchResults.EMPTY_ALL_SUBTITLE).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.RETRY).assertIsDisplayed()
    }

    @Test
    fun songsEmptyHasTitleSubtitleWithoutRetry() {
        show(GlobalSearchUiState(query = "zzzz", settledQuery = "zzzz", scope = SearchScope.Songs, songsPhase = SectionPhase.Empty, playersPhase = SectionPhase.Loaded))
        rule.onNodeWithText(GlobalSearchResults.EMPTY_SONGS_TITLE).assertIsDisplayed()
        rule.onNodeWithText(GlobalSearchResults.EMPTY_SONGS_SUBTITLE).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.RETRY).assertDoesNotExist()
    }

    @Test
    fun largeTextScrollsTheEmptyStateInsteadOfClipping() {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalDensity provides Density(1f, fontScale = 3f)) {
                    Box(Modifier.fillMaxWidth().height(220.dp)) {
                        GlobalSearchContent(
                            GlobalSearchUiState(query = "The", settledQuery = "The", scope = SearchScope.Players, songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Empty),
                            { null }, {}, {}, {}, {},
                        )
                    }
                }
            }
        }
        rule.onNodeWithTag(GlobalSearchTags.RETRY).performScrollTo().assertIsDisplayed()
    }

    private fun showChips(fontScale: Float, widthDp: Int) {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalDensity provides Density(1f, fontScale = fontScale)) {
                    Box(Modifier.width(widthDp.dp).height(400.dp)) {
                        GlobalSearchContent(GlobalSearchUiState(), { null }, {}, {}, {}, {})
                    }
                }
            }
        }
    }

    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun scopeChipsShareTheRowWhenTheirLabelsFit() {
        showChips(fontScale = 1f, widthDp = 360)
        rule.onNodeWithTag(GlobalSearchTags.SCOPES).assert(SemanticsMatcher.keyNotDefined(SemanticsProperties.HorizontalScrollAxisRange))
        val widths = SearchScope.chips.map { rule.onNodeWithTag(GlobalSearchTags.scope(it)).fetchSemanticsNode().boundsInRoot.width }
        assertEquals(widths.first(), widths.last(), 0.5f)
    }

    @Test
    @GraphicsMode(GraphicsMode.Mode.NATIVE)
    fun largeTextOnANarrowWindowScrollsTheChipsInsteadOfClippingLabels() {
        // Issue #141: TriFold folded (360 dp) at font scale 2 cut "Players" to "Playe".
        showChips(fontScale = 2f, widthDp = 300)
        rule.onNodeWithTag(GlobalSearchTags.SCOPES).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.HorizontalScrollAxisRange))
        SearchScope.chips.forEach { chip ->
            val layouts = mutableListOf<TextLayoutResult>()
            rule.onNode(hasText(chip.title).and(hasAnyAncestor(hasTestTag(GlobalSearchTags.scope(chip)))), useUnmergedTree = true)
                .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val label = layouts.single()
            val needed = label.multiParagraph.intrinsics.maxIntrinsicWidth
            assertTrue("${chip.title} needs $needed px, has ${label.size.width}", needed <= label.size.width + 0.5f)
        }
    }
}
