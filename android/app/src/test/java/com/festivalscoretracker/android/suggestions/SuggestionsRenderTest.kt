package com.festivalscoretracker.android.suggestions

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.model.SongDifficulty
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.suggestions.SuggestionCategory
import com.festivalscoretracker.android.core.suggestions.SuggestionCategoryType
import com.festivalscoretracker.android.core.suggestions.SuggestionFilterSettings
import com.festivalscoretracker.android.core.suggestions.SuggestionRowPresentation
import com.festivalscoretracker.android.core.suggestions.SuggestionScore
import com.festivalscoretracker.android.core.suggestions.SuggestionSongItem
import com.festivalscoretracker.android.presentation.suggestions.SuggestionCard
import com.festivalscoretracker.android.presentation.suggestions.SuggestionRow
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsPhase
import com.festivalscoretracker.android.presentation.suggestions.SuggestionsUiState
import com.festivalscoretracker.android.ui.common.LocalShellActions
import com.festivalscoretracker.android.ui.common.ShellActions
import com.festivalscoretracker.android.ui.suggestions.HingeSplitCells
import com.festivalscoretracker.android.ui.suggestions.SuggestionsActions
import com.festivalscoretracker.android.ui.suggestions.SuggestionsFilterSheet
import com.festivalscoretracker.android.ui.suggestions.SuggestionsScreenContent
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import java.time.Duration
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Hosted render tests for every Suggestions phase, row layout and sheet state (hoisted state, no network). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class SuggestionsRenderTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val events = mutableListOf<String>()
    private val actions = SuggestionsActions(
        retry = { events += "retry" },
        loadMore = { events += "more" },
        startNewMix = { events += "mix" },
        applyFilter = { events += "filter:${it.isActive}" },
    )

    private fun settle() = repeat(4) {
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
        rule.waitForIdle()
    }

    private fun show(state: SuggestionsUiState) {
        rule.setContent {
            FestivalTheme(appReduceMotion = true) {
                CompositionLocalProvider(LocalShellActions provides ShellActions(openProfile = { events += "profile" })) {
                    SuggestionsScreenContent(state, isRoot = true, artworkUrl = { null }, onSong = { events += "song:$it" }, actions = actions)
                }
            }
        }
        settle()
    }

    private fun song(id: String) = Song(id, "Render Track $id", "Render Artist", year = 1999, difficulty = SongDifficulty(guitar = 2.0))

    private val scores = mapOf(
        "a" to mapOf(Instrument.Lead to SuggestionScore(1, stars = 6, isFullCombo = true, season = 4), Instrument.Bass to SuggestionScore(1, stars = 3, season = 2)),
    )

    /** One card per row layout, each with every variant that layout draws. */
    private fun cards(): List<SuggestionCard> {
        fun card(key: String, instrument: Instrument?, vararg items: SuggestionSongItem): SuggestionCard {
            val category = SuggestionCategory(key, "Title $key", "Description $key", SuggestionCategoryType.NearFC, instrument, items.toList())
            val rows = items.map { SuggestionRow(it.id, SuggestionRowPresentation.create(category, it, scores, Instrument.entries.take(3)), it.song.songId, null, false) }
            return SuggestionCard(key, category, rows)
        }
        val a = song("a")
        return listOf(
            card("song_rival_gap_r", null, SuggestionSongItem(a, Instrument.Lead, rivalName = "Rival Person", rivalRankDelta = -4), SuggestionSongItem(song("b"), Instrument.Bass, rivalName = "R", rivalRankDelta = 6)),
            card("song_rival_battleground", null, SuggestionSongItem(a, Instrument.Lead, rivalName = "Mixed Rival", rivalRankDelta = 1)),
            card("unfc_Solo_Guitar", Instrument.Lead, SuggestionSongItem(a, percent = 97.2)),
            card("stale_global_2", null, SuggestionSongItem(a)),
            card("pct_push", null, SuggestionSongItem(a, Instrument.Lead, percentileDisplay = "Top 1%"), SuggestionSongItem(song("b"), Instrument.Bass, percentileDisplay = "Top 4%"), SuggestionSongItem(song("c"), percentileDisplay = "Top 30%")),
            card("star_gains", null, SuggestionSongItem(a, Instrument.Lead, stars = 6), SuggestionSongItem(song("b"), Instrument.Bass, stars = 3)),
            card("other_chips", null, SuggestionSongItem(a)),
            card("variety_pack", null, SuggestionSongItem(a)),
        )
    }

    @Test
    fun loadedCardsDrawEveryLayoutAndTheMixLimitFooter() {
        show(SuggestionsUiState(SuggestionsPhase.Loaded, cards = cards(), reachedLimit = true))
        rule.onNodeWithTag("fst.suggestions.category.song_rival_gap_r").assertIsDisplayed()
        // Single-rival card: no name badge, but TalkBack still names the rival (issue #29).
        assertNull(cards().first().rows.first().presentation.rivalName)
        rule.onNodeWithContentDescription("Render Track a, Render Artist · 1999, Lead, 4 ranks behind Rival Person").assertIsDisplayed()
        rule.onNodeWithTag("fst.suggestions.list").performScrollToNode(hasTestTag("fst.suggestions.category.song_rival_battleground"))
        rule.onNodeWithContentDescription("Render Track a, Render Artist · 1999, Lead, rival Mixed Rival, ahead by 1 rank").assertIsDisplayed()
        rule.onAllNodesWithTag("fst.suggestions.row.a|Solo_Guitar")[0].performSemanticsAction(SemanticsActions.OnClick)
        assertTrue("song:a" in events)
        rule.onNodeWithTag("fst.suggestions.list").performScrollToNode(hasTestTag("fst.suggestions.mix-limit"))
        rule.onNodeWithText("You've reached 1,000 suggestions in this mix.").assertIsDisplayed()
        rule.onNodeWithTag("fst.suggestions.start-new-mix").performSemanticsAction(SemanticsActions.OnClick)
        assertTrue("mix" in events)
        assertEquals(0, rule.onAllNodesWithTag("fst.suggestions.loading-more").fetchSemanticsNodes().size)
    }

    @Test
    fun hasMoreShowsTheLoadingFooterAndRequestsMore() {
        show(SuggestionsUiState(SuggestionsPhase.Loaded, cards = cards().take(2), hasMore = true))
        rule.onNodeWithTag("fst.suggestions.list").performScrollToNode(hasTestTag("fst.suggestions.loading-more"))
        settle()
        assertTrue("more" in events)
    }

    @Test
    fun statusPhases() {
        show(SuggestionsUiState(SuggestionsPhase.Loading))
        rule.onNodeWithTag("fst.suggestions.loading").assertIsDisplayed()
    }

    @Test
    fun syncingRetries() {
        show(SuggestionsUiState(SuggestionsPhase.Syncing))
        rule.onNodeWithText("Still syncing").assertIsDisplayed()
        rule.onNodeWithTag("fst.service-status.retry").performClick()
        assertEquals(listOf("retry"), events)
    }

    @Test
    fun failureWithCountdownAndWithoutIssue() {
        show(SuggestionsUiState(SuggestionsPhase.Failed, issue = ServiceIssue.ScrapeInProgress(30), countdown = 12))
        rule.onNodeWithTag("fst.service-status.countdown").assertIsDisplayed()
        rule.onNodeWithText("Retry Now").assertIsDisplayed()
    }

    @Test
    fun failureFallsBackToAGenericIssue() {
        show(SuggestionsUiState(SuggestionsPhase.Failed))
        rule.onNodeWithText("Something went wrong. Try again.").assertIsDisplayed()
    }

    @Test
    fun emptyStatesAndNoPlayer() {
        show(SuggestionsUiState(SuggestionsPhase.Empty, filteredOut = true, filter = SuggestionFilterSettings.DEFAULTS.withInstrument(Instrument.Lead, false)))
        rule.onNodeWithContentDescription("Filter Suggestions, filters on").assertIsDisplayed()
        rule.onNodeWithText("Try changing your filters to see more suggestions.").assertIsDisplayed()
        // No Reset Filters button in the shared empty state (#377).
        assertEquals(0, rule.onAllNodesWithTag("fst.suggestions.reset-filters").fetchSemanticsNodes().size)
        assertEquals(emptyList<String>(), events)
    }

    @Test
    fun noPlayerHidesTheFilterAndOpensProfiles() {
        show(SuggestionsUiState(SuggestionsPhase.NoPlayer))
        assertEquals(0, rule.onAllNodesWithTag("fst.suggestions.filter-button").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.suggestions.choose-profile").performClick()
        assertEquals(listOf("profile"), events)
    }

    @Test
    fun filterButtonOpensTheSheetAndChangesApplyLive() {
        show(SuggestionsUiState(SuggestionsPhase.Empty))
        rule.onNodeWithText("Play some songs first!").assertIsDisplayed()
        rule.onNodeWithTag("fst.suggestions.filter-button").performClick()
        settle()
        rule.onNodeWithTag("fst.suggestions.filter.instrument.Solo_Bass").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        assertEquals(listOf("filter:true"), events)
        rule.onNodeWithTag("fst.suggestions.filter.done").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        assertEquals(0, rule.onAllNodesWithTag("fst.suggestions.filter.form").fetchSemanticsNodes().size)
    }

    @Test
    fun sheetWithoutVisibleChartsAppliesEachToggleAndSwipeCloses() {
        var dismissed = false
        val changes = mutableListOf<SuggestionFilterSettings>()
        rule.setContent {
            FestivalTheme {
                SuggestionsFilterSheet(SuggestionFilterSettings.DEFAULTS, emptyList(), onChange = { changes += it }, onDismiss = { dismissed = true })
            }
        }
        settle()
        assertEquals(0, rule.onAllNodesWithTag("fst.suggestions.filter.instrument-specific").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.suggestions.filter.type.nearFC").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        rule.onNodeWithTag("fst.suggestions.filter.type.nearFC").performSemanticsAction(SemanticsActions.OnClick)
        settle()
        // Each toggle builds on the previous one before the applied state round-trips.
        assertEquals(2, changes.size)
        assertEquals(SuggestionFilterSettings.DEFAULTS, changes.last())
        rule.onNodeWithTag("fst.suggestions.filter.title").performTouchInput { swipeDown(startY = centerY, endY = centerY + 1500f, durationMillis = 200) }
        settle()
        assertTrue(dismissed)
    }

    @Test
    fun hingeSplitSizesEachSideOfTheFold() {
        val cells = HingeSplitCells(400)
        val sizes = with(cells) { Density(1f).calculateCrossAxisCellSizes(1000, 40) }
        assertArrayEquals(intArrayOf(400, 560), sizes)
        val clamped = with(HingeSplitCells(2000)) { Density(1f).calculateCrossAxisCellSizes(1000, 40) }
        assertArrayEquals(intArrayOf(960, 0), clamped)
    }
}

/** Wide cards keep metadata on the title line. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-land-xhdpi")
class SuggestionsWideRenderTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun wideRowsRender() {
        val song = Song("w", "Wide Track", "Wide Artist", difficulty = SongDifficulty(guitar = 1.0))
        val item = SuggestionSongItem(song, Instrument.Lead, percentileDisplay = "Top 2%")
        val category = SuggestionCategory("pct_push", "Percentile Push", "Desc", SuggestionCategoryType.PercentilePush, null, listOf(item))
        val row = SuggestionRow(item.id, SuggestionRowPresentation.create(category, item, null, emptyList()), "w", null, true)
        rule.setContent {
            FestivalTheme {
                SuggestionsScreenContent(
                    SuggestionsUiState(SuggestionsPhase.Loaded, cards = listOf(SuggestionCard("pct_push", category, listOf(row)))),
                    isRoot = false, artworkUrl = { null }, onSong = {}, actions = SuggestionsActions(),
                )
            }
        }
        rule.waitForIdle()
        rule.onNodeWithTag("fst.suggestions.row.w|Solo_Guitar").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.back").assertIsDisplayed()
    }
}
