package com.festivalscoretracker.android.ui.search

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.search.GlobalPlayerResult
import com.festivalscoretracker.android.core.search.GlobalSearchResults
import com.festivalscoretracker.android.core.search.GlobalSongResult
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.core.service.ServiceIssue
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

/**
 * Stateless search content: one centred spinner, one full-height region for every state (6.21),
 * and no section titles or Retry buttons (issue #299).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-mdpi")
class GlobalSearchContentUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val song = GlobalSongResult("s-the", "The Song", "Band One", null)
    private val player = GlobalPlayerResult("0123456789abcdef0123456789abcdef", "The Player", isSelected = false)

    private fun show(ui: GlobalSearchUiState) {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxWidth().height(600.dp)) {
                    GlobalSearchContent(ui, { null }, {}, {}, {})
                }
            }
        }
    }

    private fun assertNoRetryOrSectionTitle() {
        rule.onAllNodes(hasText("Retry", substring = true) and hasClickAction(), useUnmergedTree = true).assertCountEquals(0)
        rule.onAllNodes(isHeading().and(hasText("Songs") or hasText("Players") or hasText("Bands"))).assertCountEquals(0)
    }

    @Test
    fun spinnerIsCentredBetweenTheScopeChipsAndTheBottomEdge() {
        show(GlobalSearchUiState(query = "alpha", settledQuery = "alpha", songs = listOf(song), songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Loading))
        val spinner = rule.onNodeWithTag(GlobalSearchTags.LOADING)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
            .fetchSemanticsNode().boundsInRoot
        val chips = rule.onNodeWithTag(GlobalSearchTags.SCOPES).fetchSemanticsNode().boundsInRoot
        val root = rule.onRoot().fetchSemanticsNode().boundsInRoot
        // All waits for every scope (web parity): no song rows or inline ring beside the spinner.
        assertEquals(0, rule.onAllNodesWithTag(GlobalSearchTags.RESULT_SONG).fetchSemanticsNodes().size)
        assertEquals(36f, spinner.width, 0.5f)
        assertEquals(root.center.x, spinner.center.x, 1f)
        // The chip row keeps its 4 dp bottom padding; the content region starts below it.
        assertEquals((chips.bottom + 4f + 600f) / 2, spinner.center.y, 1f)
    }

    @Test
    fun debounceShowsTheSameCentredSpinner() {
        show(GlobalSearchUiState(query = "alpha", scope = SearchScope.All, debouncing = true))
        val spinner = rule.onNodeWithTag(GlobalSearchTags.LOADING).fetchSemanticsNode().boundsInRoot
        val chips = rule.onNodeWithTag(GlobalSearchTags.SCOPES).fetchSemanticsNode().boundsInRoot
        // The chip row keeps its 4 dp bottom padding; the content region starts below it.
        assertEquals((chips.bottom + 4f + 600f) / 2, spinner.center.y, 1f)
    }

    @Test
    fun songsScopeDoesNotWaitForPlayers() {
        show(GlobalSearchUiState(query = "The", settledQuery = "The", scope = SearchScope.Songs, songs = listOf(song), songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Loading))
        rule.onNodeWithTag(GlobalSearchTags.LOADING).assertDoesNotExist()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).assertIsDisplayed()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun allResultsHaveNoSectionTitles() {
        show(GlobalSearchUiState(query = "The", settledQuery = "The", songs = listOf(song), songsPhase = SectionPhase.Loaded, players = listOf(player), playersPhase = SectionPhase.Loaded))
        val songRow = rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val chips = rule.onNodeWithTag(GlobalSearchTags.SCOPES).fetchSemanticsNode().boundsInRoot
        rule.onNodeWithTag(GlobalSearchTags.RESULT_PLAYER).assertIsDisplayed()
        // The first row sits directly under the scope chips' 4 dp padding: no title row between them.
        assertEquals(chips.bottom + 4f, songRow.top, 1f)
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun playersScopeEmptyIsACentredTitleAndSubtitleWithoutRetry() {
        show(GlobalSearchUiState(query = "The", settledQuery = "The", scope = SearchScope.Players, songs = listOf(song), songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Empty))
        val region = rule.onNodeWithTag(GlobalSearchTags.EMPTY).fetchSemanticsNode().boundsInRoot
        val title = rule.onNodeWithText(GlobalSearchResults.EMPTY_PLAYERS_TITLE)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
            .fetchSemanticsNode().boundsInRoot
        val subtitle = rule.onNodeWithText(GlobalSearchResults.EMPTY_PLAYERS_SUBTITLE).fetchSemanticsNode().boundsInRoot
        assertEquals(region.center.x, title.center.x, 1f)
        assertEquals(region.center.x, subtitle.center.x, 1f)
        assertTrue(title.bottom <= subtitle.top)
        // Vertically centred: the block's middle is the region's middle.
        assertEquals(region.center.y, (title.top + subtitle.bottom) / 2, 2f)
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun allScopeHidesAnEmptyPlayersSectionNextToSongs() {
        show(GlobalSearchUiState(query = "The", settledQuery = "The", songs = listOf(song), songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Empty))
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.EMPTY).assertDoesNotExist()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun allEmptyAndSongsEmptyHaveNoRetry() {
        show(GlobalSearchUiState(query = "zzzz", settledQuery = "zzzz", songsPhase = SectionPhase.Empty, playersPhase = SectionPhase.Empty))
        rule.onNodeWithText(GlobalSearchResults.EMPTY_ALL_TITLE).assertIsDisplayed()
        rule.onNodeWithText(GlobalSearchResults.EMPTY_ALL_SUBTITLE).assertIsDisplayed()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun songsEmptyHasTitleSubtitleWithoutRetry() {
        show(GlobalSearchUiState(query = "zzzz", settledQuery = "zzzz", scope = SearchScope.Songs, songsPhase = SectionPhase.Empty, playersPhase = SectionPhase.Loaded))
        rule.onNodeWithText(GlobalSearchResults.EMPTY_SONGS_TITLE).assertIsDisplayed()
        rule.onNodeWithText(GlobalSearchResults.EMPTY_SONGS_SUBTITLE).assertIsDisplayed()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun playersFailureShowsItsMessageWithoutRetry() {
        show(
            GlobalSearchUiState(
                query = "The", settledQuery = "The", songs = listOf(song), songsPhase = SectionPhase.Loaded,
                playersPhase = SectionPhase.Failed, playersIssue = ServiceIssue.Offline,
            ),
        )
        rule.onNodeWithTag(GlobalSearchTags.PLAYERS_ERROR).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).assertIsDisplayed()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun scrapeFreezeCountdownHasNoRetryNow() {
        show(
            GlobalSearchUiState(
                query = "The", settledQuery = "The", scope = SearchScope.Players, songsPhase = SectionPhase.Loaded,
                playersPhase = SectionPhase.Failed, playersIssue = ServiceIssue.Offline, playersCountdown = 30,
            ),
        )
        rule.onNodeWithTag(GlobalSearchTags.PLAYERS_ERROR).assertIsDisplayed()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun shortQueryHintNamesTheScope() {
        val expected = mapOf(
            SearchScope.All to "Enter at least two characters to search for songs, players, or bands.",
            SearchScope.Songs to "Enter at least two characters to search for songs.",
            SearchScope.Players to "Enter at least two characters to search for players.",
            SearchScope.Bands to "Enter at least two characters to search for bands.",
        )
        var ui by mutableStateOf(GlobalSearchUiState(query = "a"))
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxWidth().height(600.dp)) { GlobalSearchContent(ui, { null }, {}, {}, {}) }
            }
        }
        expected.forEach { (scope, hint) ->
            ui = GlobalSearchUiState(query = "a", scope = scope)
            rule.waitForIdle()
            rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(hint))
            rule.onNodeWithTag(GlobalSearchTags.BANDS_UNAVAILABLE).assertDoesNotExist()
        }
    }

    @Test
    fun bandsScopeExplainsOnceTheQueryIsLongEnough() {
        show(GlobalSearchUiState(query = "alpha", scope = SearchScope.Bands))
        rule.onNodeWithTag(GlobalSearchTags.BANDS_UNAVAILABLE).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.HINT).assertDoesNotExist()
    }

    @Test
    fun largeTextScrollsTheEmptyStateInsteadOfClipping() {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalDensity provides Density(1f, fontScale = 3f)) {
                    Box(Modifier.fillMaxWidth().height(220.dp)) {
                        GlobalSearchContent(
                            GlobalSearchUiState(query = "The", settledQuery = "The", scope = SearchScope.Players, songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Empty),
                            { null }, {}, {}, {},
                        )
                    }
                }
            }
        }
        rule.onNodeWithText(GlobalSearchResults.EMPTY_PLAYERS_SUBTITLE).performScrollTo().assertIsDisplayed()
    }

    private fun showChips(fontScale: Float, widthDp: Int) {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalDensity provides Density(1f, fontScale = fontScale)) {
                    Box(Modifier.width(widthDp.dp).height(400.dp)) {
                        GlobalSearchContent(GlobalSearchUiState(), { null }, {}, {}, {})
                    }
                }
            }
        }
    }

    @Test
    fun returningToAllScopeStartsAtTheSongs() {
        // Issue #141: Players → All kept the first player as the first visible item.
        val songs = (1..4).map { GlobalSongResult("s-$it", "Daft Song $it", "Band", null) }
        val players = (1..10).map { GlobalPlayerResult("%032x".format(it), "Daft $it", false) }
        val all = GlobalSearchUiState(query = "daft", settledQuery = "daft", songs = songs, players = players, songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Loaded)
        var ui by mutableStateOf(all.copy(scope = SearchScope.Players))
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxWidth().height(400.dp)) { GlobalSearchContent(ui, { null }, {}, {}, {}) }
            }
        }
        rule.onNodeWithText("Daft 1").assertIsDisplayed()
        ui = all
        rule.waitForIdle()
        rule.onNodeWithText("Daft Song 1", substring = true).assertIsDisplayed()
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
