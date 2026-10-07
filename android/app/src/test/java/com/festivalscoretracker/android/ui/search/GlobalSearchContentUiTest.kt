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
import com.festivalscoretracker.android.core.bands.BandMember
import com.festivalscoretracker.android.core.bands.PlayerBandEntry
import com.festivalscoretracker.android.core.search.GlobalBandResult
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
 * no Retry buttons (issue #299), and Songs / Players / Bands section titles only in All (issue #348).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-mdpi")
class GlobalSearchContentUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val song = GlobalSongResult("s-the", "The Song", "Band One", null)
    private val player = GlobalPlayerResult("0123456789abcdef0123456789abcdef", "The Player", isSelected = false)
    private val band = GlobalBandResult(
        PlayerBandEntry(
            bandId = "band-the",
            teamKey = "0123456789abcdef0123456789abcdef:fedcba9876543210fedcba9876543210",
            bandType = "Band_Duets",
            appearanceCount = 3,
            members = listOf(
                BandMember("0123456789abcdef0123456789abcdef", "The Lead", listOf("Solo_Guitar")),
                BandMember("fedcba9876543210fedcba9876543210", "The Bass", listOf("Solo_Bass")),
            ),
        ),
    )

    private fun show(ui: GlobalSearchUiState) {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxWidth().height(600.dp)) {
                    GlobalSearchContent(ui, { null }, {}, {})
                }
            }
        }
    }

    private val sectionTitle = isHeading().and(hasText("Songs") or hasText("Players") or hasText("Bands"))

    private fun assertNoRetry() {
        rule.onAllNodes(hasText("Retry", substring = true) and hasClickAction(), useUnmergedTree = true).assertCountEquals(0)
    }

    private fun assertNoRetryOrSectionTitle() {
        assertNoRetry()
        rule.onAllNodes(sectionTitle).assertCountEquals(0)
    }

    /** Asserts exactly [scopes] are titled, in that order, each as a heading above its first row. */
    private fun assertSectionTitles(vararg scopes: SearchScope) {
        assertNoRetry()
        rule.onAllNodes(sectionTitle).assertCountEquals(scopes.size)
        var previousBottom = Float.NEGATIVE_INFINITY
        scopes.forEach { scope ->
            val title = rule.onNodeWithTag(GlobalSearchTags.section(scope)).performScrollTo()
                .assert(isHeading()).assert(hasText(scope.title))
                .fetchSemanticsNode().boundsInRoot
            assertTrue("${scope.title} title follows the previous section", title.top >= previousBottom - 1f)
            previousBottom = title.bottom
        }
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
    fun allResultsAreGroupedUnderSectionTitlesInWebOrder() {
        // Issue #348: mixed results were indistinguishable; All titles each shown category like the web.
        show(GlobalSearchUiState(query = "The", settledQuery = "The", songs = listOf(song), songsPhase = SectionPhase.Loaded, players = listOf(player), playersPhase = SectionPhase.Loaded))
        val songsTitle = rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Songs)).fetchSemanticsNode().boundsInRoot
        val songRow = rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val playersTitle = rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Players)).fetchSemanticsNode().boundsInRoot
        val playerRow = rule.onNodeWithTag(GlobalSearchTags.RESULT_PLAYER).assertIsDisplayed().fetchSemanticsNode().boundsInRoot
        val chips = rule.onNodeWithTag(GlobalSearchTags.SCOPES).fetchSemanticsNode().boundsInRoot
        assertTrue(songsTitle.top >= chips.bottom)
        assertTrue(songsTitle.bottom <= songRow.top + 1f)
        assertTrue(playersTitle.top >= songRow.bottom - 1f)
        assertTrue(playersTitle.bottom <= playerRow.top + 1f)
        // The shared section header (section-headers R1) aligns with the rows' 16 dp inset.
        assertEquals(songRow.left + 16f, songsTitle.left, 1f)
        assertSectionTitles(SearchScope.Songs, SearchScope.Players)
    }

    @Test
    fun singleScopeResultsHaveNoSectionTitle() {
        // Issue #299: the chip already names a single scope.
        val loaded = GlobalSearchUiState(
            query = "The", settledQuery = "The", songs = listOf(song), songsPhase = SectionPhase.Loaded,
            players = listOf(player), playersPhase = SectionPhase.Loaded, bands = listOf(band), bandsPhase = SectionPhase.Loaded,
        )
        var ui by mutableStateOf(loaded.copy(scope = SearchScope.Songs))
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxWidth().height(600.dp)) { GlobalSearchContent(ui, { null }, {}, {}) }
            }
        }
        SearchScope.chips.forEach { scope ->
            ui = loaded.copy(scope = scope)
            rule.waitForIdle()
            assertNoRetryOrSectionTitle()
        }
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
        // Web omits an empty category in All: no Players title and no per-category "no results" row.
        assertSectionTitles(SearchScope.Songs)
        rule.onNodeWithText(GlobalSearchResults.EMPTY_PLAYERS_TITLE).assertDoesNotExist()
    }

    @Test
    fun allEmptyAndSongsEmptyHaveNoRetry() {
        show(GlobalSearchUiState(query = "zzzz", settledQuery = "zzzz", songsPhase = SectionPhase.Empty, playersPhase = SectionPhase.Empty, bandsPhase = SectionPhase.Empty))
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
        // Like the web, a failed category keeps its title in All, with the failure under it.
        assertSectionTitles(SearchScope.Songs, SearchScope.Players)
        val playersTitle = rule.onNodeWithTag(GlobalSearchTags.section(SearchScope.Players)).fetchSemanticsNode().boundsInRoot
        assertTrue(playersTitle.bottom <= rule.onNodeWithTag(GlobalSearchTags.PLAYERS_ERROR).fetchSemanticsNode().boundsInRoot.top + 1f)
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
                Box(Modifier.fillMaxWidth().height(600.dp)) { GlobalSearchContent(ui, { null }, {}, {}) }
            }
        }
        expected.forEach { (scope, hint) ->
            ui = GlobalSearchUiState(query = "a", scope = scope)
            rule.waitForIdle()
            rule.onNodeWithTag(GlobalSearchTags.HINT).assert(hasText(hint))
        }
    }

    @Test
    fun allScopeWaitsForBandsBehindTheOneSpinner() {
        show(GlobalSearchUiState(query = "The", settledQuery = "The", songs = listOf(song), songsPhase = SectionPhase.Loaded, players = listOf(player), playersPhase = SectionPhase.Loaded, bandsPhase = SectionPhase.Loading))
        rule.onNodeWithTag(GlobalSearchTags.LOADING).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).assertDoesNotExist()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_BAND).assertDoesNotExist()
    }

    @Test
    fun bandsFollowSongsAndPlayersAsPlayerBandCards() {
        show(
            GlobalSearchUiState(
                query = "The", settledQuery = "The", songs = listOf(song), songsPhase = SectionPhase.Loaded,
                players = listOf(player), playersPhase = SectionPhase.Loaded, bands = listOf(band), bandsPhase = SectionPhase.Loaded,
            ),
        )
        val playerRow = rule.onNodeWithTag(GlobalSearchTags.RESULT_PLAYER).fetchSemanticsNode().boundsInRoot
        val bandCard = rule.onNodeWithTag(GlobalSearchTags.RESULT_BAND).performScrollTo().assertIsDisplayed()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("The Lead + The Bass, Duos, 3 appearances")))
            .fetchSemanticsNode().boundsInRoot
        assertTrue(bandCard.top >= playerRow.bottom - 1f)
        assertSectionTitles(SearchScope.Songs, SearchScope.Players, SearchScope.Bands)
    }

    @Test
    fun bandsScopeShowsOnlyBands() {
        show(
            GlobalSearchUiState(
                query = "The", settledQuery = "The", scope = SearchScope.Bands, songs = listOf(song), songsPhase = SectionPhase.Loaded,
                players = listOf(player), playersPhase = SectionPhase.Loading, bands = listOf(band), bandsPhase = SectionPhase.Loaded,
            ),
        )
        // Bands scope waits only for bands: a pending players read draws no spinner here.
        rule.onNodeWithTag(GlobalSearchTags.LOADING).assertDoesNotExist()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_BAND).assertIsDisplayed()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_SONG).assertDoesNotExist()
        rule.onNodeWithTag(GlobalSearchTags.RESULT_PLAYER).assertDoesNotExist()
        rule.onNodeWithTag(GlobalSearchTags.HINT).assertDoesNotExist()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun bandsScopeEmptyIsNoBandsFoundWithoutRetry() {
        show(GlobalSearchUiState(query = "zzzz", settledQuery = "zzzz", scope = SearchScope.Bands, songsPhase = SectionPhase.Empty, playersPhase = SectionPhase.Empty, bandsPhase = SectionPhase.Empty))
        rule.onNodeWithTag(GlobalSearchTags.EMPTY).assertIsDisplayed()
        rule.onNodeWithText(GlobalSearchResults.EMPTY_BANDS_TITLE).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithText(GlobalSearchResults.EMPTY_BANDS_SUBTITLE).assertIsDisplayed()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun bandsFailureIsNotEmptyAndHasNoRetry() {
        show(
            GlobalSearchUiState(
                query = "The", settledQuery = "The", scope = SearchScope.Bands, songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Loaded,
                bandsPhase = SectionPhase.Failed, bandsIssue = ServiceIssue.Offline,
            ),
        )
        rule.onNodeWithTag(GlobalSearchTags.BANDS_ERROR).assertIsDisplayed()
        rule.onNodeWithText(GlobalSearchResults.EMPTY_BANDS_TITLE).assertDoesNotExist()
        rule.onNodeWithTag(GlobalSearchTags.EMPTY).assertDoesNotExist()
        assertNoRetryOrSectionTitle()
    }

    @Test
    fun largeTextScrollsTheEmptyStateInsteadOfClipping() {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalDensity provides Density(1f, fontScale = 3f)) {
                    Box(Modifier.fillMaxWidth().height(220.dp)) {
                        GlobalSearchContent(
                            GlobalSearchUiState(query = "The", settledQuery = "The", scope = SearchScope.Players, songsPhase = SectionPhase.Loaded, playersPhase = SectionPhase.Empty),
                            { null }, {}, {},
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
                        GlobalSearchContent(GlobalSearchUiState(), { null }, {}, {})
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
                Box(Modifier.fillMaxWidth().height(400.dp)) { GlobalSearchContent(ui, { null }, {}, {}) }
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
