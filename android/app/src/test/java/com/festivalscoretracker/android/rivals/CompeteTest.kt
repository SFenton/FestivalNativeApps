package com.festivalscoretracker.android.rivals

import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.assertIsDisplayed
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.compete.ComboRankingsResponse
import com.festivalscoretracker.android.core.compete.CompeteHeaderLayout
import com.festivalscoretracker.android.core.compete.CompeteScope
import com.festivalscoretracker.android.core.compete.CompeteScopes
import com.festivalscoretracker.android.core.compete.CompeteText
import com.festivalscoretracker.android.core.model.FestivalApiException
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.CompeteRoute
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.rankings.AccountRankingEntry
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalSummary
import com.festivalscoretracker.android.core.rivals.rivalEntries
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpRequest
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.data.compete.comboRankings
import com.festivalscoretracker.android.data.compete.playerComboRanking
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.compete.CompeteBoard
import com.festivalscoretracker.android.presentation.compete.CompeteContent
import com.festivalscoretracker.android.presentation.compete.CompeteReads
import com.festivalscoretracker.android.presentation.compete.CompeteSection
import com.festivalscoretracker.android.presentation.compete.CompeteStaggerPlan
import com.festivalscoretracker.android.presentation.compete.CompeteViewModel
import com.festivalscoretracker.android.presentation.valueOrNull
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.io.IOException
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

// region Logic

/** Compete scopes, combo reads and view model. */
@OptIn(ExperimentalCoroutinesApi::class)
class CompeteLogicTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val player = CompeteFixtures.PLAYER
    private val api get() = FestivalApi("https://fixture.test", CompeteFixtures.transport())

    @Test
    fun scopesFollowRankingFamilies() {
        val all = CompeteScopes.resolve(Instrument.entries)
        assertEquals(listOf("0f", "Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals", "30", "Solo_PeripheralGuitar", "Solo_PeripheralBass", "Solo_PeripheralVocals", "Solo_PeripheralCymbals", "Solo_PeripheralDrums"), all.map { it.key })
        assertEquals("Lead + Bass + Drums + Tap Vocals", all[0].label)
        assertEquals(RivalScope.Combo("0f"), all[0].rivalScope)
        assertEquals(RivalScope.Song(listOf(Instrument.Lead)), all[1].rivalScope)
        assertEquals(listOf("Solo_Bass"), CompeteScopes.resolve(setOf(Instrument.Bass)).map { it.key })
        assertEquals(listOf("Solo_PeripheralCymbals", "Solo_PeripheralDrums"), CompeteScopes.resolve(setOf(Instrument.ProDrums, Instrument.ProCymbals)).map { it.key })
        assertTrue(CompeteScopes.resolve(emptySet()).isEmpty())
        assertEquals("No rivals found for Lead yet.", CompeteText.noRivals("Lead"))
        assertEquals("Track a player to see your closest rivals for Lead.", CompeteText.trackForRivals("Lead"))
        assertEquals("No scores recorded yet for Lead.", CompeteText.noRankings("Lead"))
    }

    @Test
    fun scopeHeaderStacksInNarrowLanesAndLargeText() {
        // Phone card (~379 dp): a combo board without View All keeps its title beside the icons...
        assertFalse(CompeteHeaderLayout.stacks(379f, 4, hasSeeAll = false, largeText = false))
        // ...but beside View All the title would wrap to three lines, so the icons stack.
        assertTrue(CompeteHeaderLayout.stacks(379f, 4, hasSeeAll = true, largeText = false))
        // Half-open book fold panel (~260 dp): the combo title would get a few dp, so the icons stack above it.
        assertTrue(CompeteHeaderLayout.stacks(260f, 4, hasSeeAll = true, largeText = false))
        assertTrue(CompeteHeaderLayout.stacks(250f, 4, hasSeeAll = false, largeText = false))
        // One instrument plus View All still fits that panel.
        assertFalse(CompeteHeaderLayout.stacks(260f, 1, hasSeeAll = true, largeText = false))
        // Boundaries: combo icons 4×36 + 3×2, gap 8, combo title 140, gap 8 + link 88; single icon 36, gap 8, title 100, link 96.
        assertFalse(CompeteHeaderLayout.stacks(394f, 4, hasSeeAll = true, largeText = false))
        assertTrue(CompeteHeaderLayout.stacks(393.9f, 4, hasSeeAll = true, largeText = false))
        assertFalse(CompeteHeaderLayout.stacks(240f, 1, hasSeeAll = true, largeText = false))
        assertTrue(CompeteHeaderLayout.stacks(239.9f, 1, hasSeeAll = true, largeText = false))
        assertFalse(CompeteHeaderLayout.stacks(108f, 0, hasSeeAll = false, largeText = false))
        // Large text always stacks.
        assertTrue(CompeteHeaderLayout.stacks(2000f, 1, hasSeeAll = false, largeText = true))
    }

    @Test
    fun comboReadsValidate() = runTest {
        val transport = CompeteFixtures.transport()
        val client = FestivalApi("https://fixture.test", transport)
        val board = client.comboRankings("03", RankingMetric.TotalScore, 1, 10)
        assertEquals(3, board.entries.size)
        assertEquals(1, board.entries[0].asAccountEntry().totalScoreRank)
        assertEquals("combo=03&rankBy=totalscore&page=1&pageSize=10", transport.sent("/api/rankings/combo").single().url.substringAfter('?'))
        assertEquals(2, client.playerComboRanking(player, "03", RankingMetric.TotalScore)!!.rank)
        listOf<suspend () -> Unit>(
            { client.comboRankings("41", RankingMetric.TotalScore, 1, 10) },
            { client.comboRankings("03", RankingMetric.TotalScore, 0, 10) },
            { client.playerComboRanking("bad id", "03", RankingMetric.TotalScore) },
            { client.playerComboRanking(player, "zz", RankingMetric.TotalScore) },
        ).forEach { call ->
            try {
                call()
                fail("expected InvalidResource")
            } catch (_: FestivalApiException.InvalidResource) {
            }
        }
        transport.onRaw("/api/rankings/combo") { HttpResult(404, "{}".toByteArray()) }
        assertTrue(client.comboRankings("30", RankingMetric.TotalScore, 1, 10).entries.isEmpty())
        transport.onRaw("/api/rankings/combo") { HttpResult(500, "{}".toByteArray()) }
        try {
            client.comboRankings("30", RankingMetric.TotalScore, 1, 10)
            fail("expected HttpStatus")
        } catch (_: FestivalApiException.HttpStatus) {
        }
        transport.onRaw("/api/rankings/combo/$player") { HttpResult(404, "{}".toByteArray()) }
        assertNull(client.playerComboRanking(player, "03", RankingMetric.TotalScore))
        transport.onRaw("/api/rankings/combo/$player") { HttpResult(500, "{}".toByteArray()) }
        try {
            client.playerComboRanking(player, "03", RankingMetric.TotalScore)
            fail("expected HttpStatus")
        } catch (_: FestivalApiException.HttpStatus) {
        }
        transport.on("/api/rankings/combo/$player", headers = mapOf("X-FST-Publication-Id" to "7")) { """{"rank":1,"accountId":"${RivalsFixtures.RIVALS[0]}"}""" }
        try {
            client.playerComboRanking(player, "03", RankingMetric.TotalScore)
            fail("expected InvalidResponse")
        } catch (_: FestivalApiException.InvalidResponse) {
        }
        assertThrows(FestivalApiException.InvalidResponse::class.java) { ComboRankingsResponse("30").validate("03") }
    }

    @Test
    fun viewModelBuildsBoardsSpotlightAndRivals() = runTest(main.dispatcher) {
        val client = api
        val model = CompeteViewModel(player, setOf(Instrument.Lead, Instrument.Bass, Instrument.Karaoke), CompeteReads.from(client), RivalsRepository(client), ServiceRetryBackoff())
        advanceUntilIdle()
        val sections = model.content.value.sections
        assertEquals(listOf("03", "Solo_Guitar", "Solo_Bass", "Solo_PeripheralVocals"), sections.map { it.scope.key })
        val combo = sections[0].board.valueOrNull!!
        assertEquals(3, combo.entries.size)
        assertEquals(2, combo.spotlight!!.totalScoreRank)
        val lead = sections[1].board.valueOrNull!!
        assertEquals(10, lead.entries.size)
        assertEquals(40, lead.spotlight!!.totalScoreRank)
        assertNull(sections[3].board.valueOrNull!!.spotlight)
        assertEquals(2, sections[1].rivals!!.valueOrNull!!.size)
        assertTrue(sections[2].rivals!!.valueOrNull!!.isEmpty())
        assertNull(model.content.value.fullPageIssue)
        model.retryBoard("Solo_Guitar")
        model.retryRivals("03")
        model.retryFailed()
        advanceUntilIdle()
    }

    @Test
    fun anonymousAndAllFailed() = runTest(main.dispatcher) {
        val anonymous = CompeteViewModel(null, setOf(Instrument.Lead), CompeteReads.from(api), RivalsRepository(api), ServiceRetryBackoff())
        advanceUntilIdle()
        assertNull(anonymous.content.value.sections.single().rivals)
        assertNull(anonymous.content.value.sections.single().board.valueOrNull!!.spotlight)
        val failing = CompeteReads(board = { throw IOException("offline") }, playerRow = { _, _ -> throw IOException("offline") })
        val down = CompeteViewModel(player, setOf(Instrument.Lead, Instrument.Bass), failing, RivalsRepository(api), ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals(ServiceIssue.Offline, down.content.value.fullPageIssue)
        assertTrue(down.content.value.sections.all { it.board is LoadState.Failed })
        val none = CompeteViewModel(player, emptySet(), failing, RivalsRepository(api), ServiceRetryBackoff())
        assertTrue(none.content.value.sections.isEmpty())
        assertFalse(none.scopes.any { it is CompeteScope.Combo })
    }

    @Test
    fun pageIsReadyOnlyOnceEveryBoardAndRivalsReadSettles() = runTest(main.dispatcher) {
        var boardGate = CompletableDeferred<Unit>()
        val reads = CompeteReads(
            board = { scope ->
                boardGate.await()
                if (scope.key == "Solo_Bass") throw IOException("offline")
                listOf(AccountRankingEntry(accountId = scope.key, totalScoreRank = 1))
            },
            playerRow = { _, _ -> null },
        )
        val model = CompeteViewModel(player, setOf(Instrument.Lead, Instrument.Bass), reads, RivalsRepository(api), ServiceRetryBackoff())
        runCurrent()
        // Web `CompetePage` `isReady`: still waiting for the boards, so the page shows only its spinner (#354).
        assertFalse(model.content.value.settled)
        assertFalse(model.content.value.ready)
        boardGate.complete(Unit)
        advanceUntilIdle()
        // One board failed inline; every read has finished, so the page reveals.
        assertTrue(model.content.value.settled)
        assertTrue(model.content.value.ready)
        assertNull(model.content.value.fullPageIssue)
        // A retry makes the page not ready again, so it runs the swap rather than a card spinner.
        boardGate = CompletableDeferred()
        model.retryBoard("Solo_Bass")
        runCurrent()
        assertFalse(model.content.value.ready)
        boardGate.complete(Unit)
        advanceUntilIdle()
        assertTrue(model.content.value.ready)
    }

    @Test
    fun everyBoardFailingIsReadyWhileRivalsStillLoad() = runTest(main.dispatcher) {
        val rivalsGate = CompletableDeferred<Unit>()
        val transport = CompeteFixtures.transport().apply {
            beforeRespond = { request -> if ("/rivals/" in request.url) rivalsGate.await() }
        }
        val client = FestivalApi("https://fixture.test", transport)
        val failing = CompeteReads(board = { throw IOException("offline") }, playerRow = { _, _ -> null })
        val model = CompeteViewModel(player, setOf(Instrument.Lead), failing, RivalsRepository(client), ServiceRetryBackoff())
        runCurrent()
        // Web `liveReady = (leaderboardReady && rivalsReady) || allLeaderboardsErrored`.
        assertFalse(model.content.value.settled)
        assertEquals(ServiceIssue.Offline, model.content.value.fullPageIssue)
        assertTrue(model.content.value.ready)
        rivalsGate.complete(Unit)
        advanceUntilIdle()
    }

    @Test
    fun staggerPlanNumbersHeadersAndRowsInReadingOrder() {
        fun entry(id: String, rank: Int) = AccountRankingEntry(accountId = id, totalScoreRank = rank)
        val combo = CompeteScope.Combo("03", listOf(Instrument.Lead, Instrument.Bass))
        val lead = CompeteScope.Single(Instrument.Lead)
        val bass = CompeteScope.Single(Instrument.Bass)
        val rival = rivalEntries(listOf(RivalSummary(RivalsFixtures.RIVALS[0])), listOf(RivalSummary(RivalsFixtures.RIVALS[1])))
        val sections = listOf(
            // Combo: 3 rows + the player's row, no View Full Leaderboards; 2 rivals + View All.
            CompeteSection(combo, LoadState.Loaded(CompeteBoard(List(3) { entry("c$it", it + 1) }, entry("me", 9))), LoadState.Loaded(rival)),
            // Lead: 2 rows (player inside) + View Full Leaderboards; no rivals (empty card).
            CompeteSection(lead, LoadState.Loaded(CompeteBoard(List(2) { entry("l$it", it + 1) }, null)), LoadState.Loaded(emptyList())),
            // Bass: failed board and failed rivals (one inline error card each).
            CompeteSection(bass, LoadState.Failed(ServiceIssue.Offline), LoadState.Failed(ServiceIssue.Offline)),
        )
        val plan = CompeteContent(sections, null, null).stagger
        assertEquals(0, plan.leaderboardsHeader)
        // Combo header 1, body 2..5; Lead header 6, body 7..9; Bass header 10, error 11.
        assertEquals(listOf(1, 6, 10), plan.boards)
        assertEquals(12, plan.rivalsHeader)
        // Combo rivals header 13, rows 14..15 + View All 16; Lead 17 + empty 18; Bass 19 + error 20.
        assertEquals(listOf(13, 17, 19), plan.rivals)
        // Anonymous: each rivals card is one "track a player" card.
        val anonymous = CompeteContent(listOf(sections[1].copy(rivals = null)), null, null).stagger
        assertEquals(CompeteStaggerPlan(0, listOf(1), 5, listOf(6)), anonymous)
        assertTrue(CompeteContent(emptyList(), null, null).ready)
        assertFalse(CompeteContent(emptyList(), null, null, settled = false).ready)
    }

    @Test
    fun newerPublicationRefreshesInPlaceAndSamePublicationDoesNot() = runTest(main.dispatcher) {
        val publications = MutableStateFlow<Int?>(7)
        var boardReads = 0
        var gate: CompletableDeferred<Unit>? = null
        val reads = CompeteReads(
            board = { scope ->
                boardReads++
                gate?.await()
                listOf(AccountRankingEntry(accountId = "${scope.key}-$boardReads", totalScoreRank = if (boardReads > 1) 2 else 1))
            },
            playerRow = { _, _ -> null },
        )
        val model = CompeteViewModel(null, setOf(Instrument.Lead), reads, RivalsRepository(api), ServiceRetryBackoff(), publications)
        advanceUntilIdle()
        assertEquals(1, boardReads)
        val first = model.content.value.sections.single().board

        // Returning to Compete or re-observing the same publication keeps the loaded cards without a read.
        publications.value = 7
        advanceUntilIdle()
        assertEquals(1, boardReads)
        assertEquals(first, model.content.value.sections.single().board)

        // A newer publication refreshes in place: the loaded card stays visible (never Loading) until new rows land.
        gate = CompletableDeferred()
        publications.value = 8
        runCurrent()
        assertEquals(2, boardReads)
        val during = model.content.value.sections.single().board
        assertTrue("refresh replaced the card with a placeholder: $during", during is LoadState.Loaded && during.refreshing)
        assertEquals(first.valueOrNull, during.valueOrNull)
        gate!!.complete(Unit)
        advanceUntilIdle()
        val after = model.content.value.sections.single().board
        assertEquals(2, after.valueOrNull!!.entries.single().totalScoreRank)
        assertFalse((after as LoadState.Loaded).refreshing)
    }

    @Test
    fun firstObservedPublicationDoesNotReloadAndNewerOneRetriesFailures() = runTest(main.dispatcher) {
        val publications = MutableStateFlow<Int?>(null)
        var boardReads = 0
        var down = true
        val reads = CompeteReads(
            board = { scope ->
                boardReads++
                if (down) throw IOException("offline")
                listOf(AccountRankingEntry(accountId = scope.key, totalScoreRank = 1))
            },
            playerRow = { _, _ -> null },
        )
        val model = CompeteViewModel(null, setOf(Instrument.Lead), reads, RivalsRepository(api), ServiceRetryBackoff(), publications)
        advanceUntilIdle()
        assertTrue(model.content.value.sections.single().board is LoadState.Failed)
        // The first publication seen (from Compete's own reads) is the one they already used.
        publications.value = 7
        advanceUntilIdle()
        assertEquals(1, boardReads)
        down = false
        publications.value = 8
        advanceUntilIdle()
        assertEquals(2, boardReads)
        assertEquals(1, model.content.value.sections.single().board.valueOrNull!!.entries.size)
        assertNull(model.content.value.fullPageIssue)
    }
}

// endregion

// region UI

/** Compete on the phone layout. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class CompeteUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = CompeteFixtures.transport()

    private fun launch(debug: DebugLaunch, http: HttpTransport = transport) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = http, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
    }

    private fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            repeat(2) {
                shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
                rule.waitForIdle()
            }
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun competeTabShowsBoardsAndRivalsThenDrillsIn() {
        launch(DebugLaunch(section = FestivalSection.Compete, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.leaderboard-card.0f")
        rule.onNodeWithTag("fst.compete.section.leaderboards").assertIsDisplayed()
        rule.onNodeWithTag("fst.quick-links.open").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.quick-links.item.leaderboards")
        rule.onNodeWithTag("fst.quick-links.item.rivals").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.compete.rivals-card.Solo_Guitar")
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.rivals-card.Solo_Guitar"))
        waitForTag("fst.rivals.row.${RivalsFixtures.RIVALS[0]}")
        rule.onNodeWithTag("fst.rivals.row.${RivalsFixtures.RIVALS[0]}").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rival-detail.title")
    }

    @Test
    fun pushedCompeteSpotlightsThePlayerAndOpensFullRankings() {
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.leaderboard-card.Solo_Guitar")
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.spotlight.Solo_Guitar"))
        rule.onNodeWithTag("fst.compete.spotlight.Solo_Guitar").assertIsDisplayed()
        // Issue #321: the board header link reads "View All", label first.
        rule.onNodeWithTag("fst.compete.board.see-all.Solo_Guitar").assert(hasContentDescription("View All: Lead"))
        rule.onNodeWithTag("fst.compete.board.see-all.Solo_Guitar").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.onAllNodesWithTag("fst.compete.grid").fetchSemanticsNodes().isEmpty()
        }
    }

    /**
     * Issue #370 (`leaderboard-row` R7, owner variant): the selected player's row under a
     * Compete preview opens the full board on the page holding their rank (#40, page 2) and
     * reveals the highlighted row, like Song Detail's appended row; other rows open profiles.
     */
    @Test
    fun selectedPreviewRowJumpsToItsFullBoardPage() {
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.leaderboard-card.Solo_Guitar")
        val own = "fst.compete.spotlight.Solo_Guitar"
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag(own))
        assertEquals("Jump to your position", clickLabel(own))
        assertEquals("Open profile", clickLabel("fst.compete.rank.Solo_Guitar.${RankingsFixtures.accountId(1)}"))
        // Combo boards have no full board on Android, so their row still opens Statistics.
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.spotlight.0f"))
        assertEquals("Open your statistics", clickLabel("fst.compete.spotlight.0f"))
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag(own))
        rule.onNodeWithTag(own).performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) {
            repeat(2) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
            rule.onAllNodesWithContentDescription("Page 2 of 3").fetchSemanticsNodes().isNotEmpty()
        }
        val row = "fst.rankings.row.${RankingsFixtures.SELECTED}"
        waitForTag(row)
        // The reveal centres the highlighted row above the pinned footer and pager.
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100))
            rule.waitForIdle()
            val bounds = rule.onNodeWithTag(row).fetchSemanticsNode().boundsInRoot
            val list = rule.onNodeWithTag("fst.full-rankings.list").fetchSemanticsNode().boundsInRoot
            val footer = rule.onNodeWithTag("fst.full-rankings.bottom-bar").fetchSemanticsNode().boundsInRoot
            bounds.height > 0f && bounds.top >= list.top && bounds.bottom <= footer.top
        }
        rule.onNodeWithTag(row).assertIsDisplayed()
    }

    private fun clickLabel(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().config.getOrNull(SemanticsActions.OnClick)?.label

    @Test
    fun rowsKeepTheSongsCountInTheirDescription() {
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.leaderboard-card.Solo_Guitar")
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.spotlight.Solo_Guitar"))
        // Narrow cards may hide the songs column (issue #38); TalkBack still hears the count.
        val spoken = rule.onNodeWithTag("fst.compete.spotlight.Solo_Guitar").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue(spoken, spoken.contains("160 / 250 songs"))
    }

    /**
     * Issue #354 (web `CompetePage` `usePageTransition`): one centred page spinner, no headers or
     * cards, until every board and rivals read has finished; then headers and cards come in
     * together, a failed board as its inline error. No card ever shows its own spinner.
     */
    @Test
    fun firstLoadShowsOnePageSpinnerUntilEveryReadSettles() {
        val gate = CompletableDeferred<Unit>()
        // Holds every Compete read until released; Bass's board then fails inline.
        val gated = object : HttpTransport {
            override suspend fun send(request: HttpRequest): HttpResult {
                val path = request.url.substringBefore('?')
                if ("/api/rankings" in path || "/rivals/" in path) gate.await()
                if (path.endsWith("/api/rankings/Solo_Bass")) throw IOException("offline")
                return transport.send(request)
            }
        }
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true), gated)
        waitForTag("fst.compete.loading")
        rule.onNodeWithTag("fst.compete.loading").assertIsDisplayed()
        rule.onNodeWithContentDescription(CompeteText.LOADING)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
        repeat(10) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        listOf("fst.compete.grid", "fst.compete.section.leaderboards", "fst.compete.section.rivals", "fst.compete.leaderboard-card.0f", "fst.quick-links.open").forEach { tag ->
            assertTrue("$tag shown while Compete loads", rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty())
        }
        assertNoCardSpinners()

        gate.complete(Unit)
        waitForTag("fst.compete.section.leaderboards")
        assertTrue("page spinner stayed with the content", rule.onAllNodesWithTag("fst.compete.loading").fetchSemanticsNodes().isEmpty())
        awaitInCard("fst.compete.leaderboard-card.Solo_Guitar", hasTestTag("fst.compete.spotlight.Solo_Guitar"))
        awaitInCard("fst.compete.leaderboard-card.Solo_Bass", hasTestTag("fst.service-status.inline"))
        awaitInCard("fst.compete.rivals-card.Solo_Guitar", hasTestTag("fst.rivals.row.${RivalsFixtures.RIVALS[0]}"))
        assertNoCardSpinners()
    }

    @Test
    fun settledCardsShowEmptyCopyAndRivalsErrorsAndRetryUsesThePageSwap() {
        val gate = CompletableDeferred<Unit>()
        // Drums has no ranked accounts and no rivals (empty copy in both cards); Bass rivals fail (inline error).
        transport.onRaw("/api/rankings/Solo_Drums") {
            HttpResult(200, RankingsFixtures.rankings("Solo_Drums", "totalscore", 1, 10, total = 0).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
        }
        transport.onRaw("/api/rankings/Solo_Drums/${CompeteFixtures.PLAYER}") { HttpResult(404, "{}".toByteArray()) }
        transport.on("/api/player/${CompeteFixtures.PLAYER}/rivals/Solo_Drums") { RivalsFixtures.list("Solo_Drums", emptyList(), emptyList()) }
        transport.on("/api/player/${CompeteFixtures.PLAYER}/rivals/Solo_Bass") { RivalsFixtures.list("Solo_Bass", listOf(RivalsFixtures.rival(RivalsFixtures.RIVALS[1], "Synthetic Beta")), emptyList()) }
        var bassDown = true
        var retryGate: CompletableDeferred<Unit>? = null
        transport.beforeRespond = { request ->
            val path = request.url.substringBefore('?')
            if ("/api/rankings" in path || "/rivals/" in path) gate.await()
            if (path.endsWith("/rivals/Solo_Bass")) {
                retryGate?.await()
                if (bassDown) throw IOException("offline")
            }
        }
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.loading")
        assertTrue(rule.onAllNodesWithText(CompeteText.noRivals("Drums")).fetchSemanticsNodes().isEmpty())

        gate.complete(Unit)
        awaitInCard("fst.compete.leaderboard-card.Solo_Drums", hasText(CompeteText.noRankings("Drums")))
        awaitInCard("fst.compete.rivals-card.Solo_Drums", hasText(CompeteText.noRivals("Drums")))
        awaitInCard("fst.compete.rivals-card.Solo_Bass", hasTestTag("fst.service-status.inline"))
        assertNoCardSpinners()

        // Retrying the card reloads the page through the same swap (load-transition R1): never a card spinner.
        bassDown = false
        retryGate = CompletableDeferred()
        val retry = hasText("Retry").and(hasAnyAncestor(hasTestTag("fst.compete.rivals-card.Solo_Bass")))
        rule.onNode(retry).performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.compete.loading")
        assertNoCardSpinners()
        retryGate!!.complete(Unit)
        awaitInCard("fst.compete.rivals-card.Solo_Bass", hasTestTag("fst.rivals.row.${RivalsFixtures.RIVALS[1]}"))
        assertTrue(rule.onAllNodesWithTag("fst.compete.loading").fetchSemanticsNodes().isEmpty())
        assertNoCardSpinners()
    }

    private fun assertNoCardSpinners() {
        val cardSpinner = SemanticsMatcher("card spinner") { node ->
            val tag = node.config.getOrElse(SemanticsProperties.TestTag) { "" }
            tag.startsWith("fst.compete.") && tag.endsWith(".loading") && tag != "fst.compete.loading"
        }
        assertTrue("a Compete card showed its own spinner", rule.onAllNodes(cardSpinner).fetchSemanticsNodes().isEmpty())
    }
    /** Scrolls the lazy Compete grid to [cardTag] until a descendant matching [child] is composed. */
    private fun awaitInCard(cardTag: String, child: SemanticsMatcher) {
        val matcher = child.and(hasAnyAncestor(hasTestTag(cardTag)))
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.waitForIdle()
            rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag(cardTag))
            rule.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
        }
    }

    @Test
    fun returningFromFullLeaderboardKeepsCompeteInPlaceWithoutReloading() {
        launch(DebugLaunch(section = FestivalSection.Compete, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        val card = "fst.compete.leaderboard-card.Solo_Guitar"
        val button = hasTestTag("fst.compete.view-full-leaderboards").and(hasAnyAncestor(hasTestTag(card)))
        awaitInCard(card, button)
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(button)
        repeat(20) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        val before = rule.onNode(button).fetchSemanticsNode().boundsInRoot
        fun reads() = transport.requests.count { "/api/rankings" in it.url || "/rivals/" in it.url }
        val readsBefore = reads()

        rule.onNode(button).performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.onAllNodesWithTag("fst.compete.grid").fetchSemanticsNodes().isEmpty()
        }
        repeat(10) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        val readsAway = reads()

        rule.mainClock.autoAdvance = false
        rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
        // Sample every frame of the return transition and the settle afterwards: the card must
        // never move, show a loading placeholder or re-request its rows.
        val positions = mutableListOf<Rect>()
        repeat(120) {
            rule.mainClock.advanceTimeByFrame()
            shadowOf(Looper.getMainLooper()).idle()
            rule.onAllNodes(button).fetchSemanticsNodes().firstOrNull()?.let { positions += it.boundsInRoot }
            assertTrue("Compete showed a loading placeholder on return", rule.onAllNodes(hasTestTag("$card.loading")).fetchSemanticsNodes().isEmpty())
            assertTrue("Compete showed its page spinner on return", rule.onAllNodesWithTag("fst.compete.loading").fetchSemanticsNodes().isEmpty())
        }
        rule.mainClock.autoAdvance = true
        assertTrue("Compete never reappeared", positions.isNotEmpty())
        assertEquals("Compete re-read its boards or rivals on return", readsAway, reads())
        assertTrue("Opening the full board reads only its own page", readsAway >= readsBefore)
        // Kept on the back stack, the grid comes back already laid out at the scroll position it had.
        assertTrue("Compete moved on return: $before -> ${positions.distinct()}", positions.all { it == before })
    }

    /**
     * Web `CompetePage` has no Leaderboards Overview link (issue #66, revalidated in #174): Quick
     * Links list only the two groups, no Compete card names an overview, and each
     * single-instrument board's View Full Leaderboards opens that instrument's Full Rankings.
     * Combo boards offer no full-board path.
     */
    @Test
    fun competeHasNoOverviewButtonAndEachBoardOpensItsFullRankings() {
        launch(DebugLaunch(section = FestivalSection.Compete, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.leaderboard-card.0f")
        val overview = SemanticsMatcher("names an overview") { node ->
            val config = node.config
            val words = config.getOrElse(SemanticsProperties.Text) { emptyList() }.map { it.text } +
                config.getOrElse(SemanticsProperties.ContentDescription) { emptyList() } +
                config.getOrElse(SemanticsProperties.TestTag) { "" }
            words.any { it.contains("overview", ignoreCase = true) }
        }
        fun assertNoOverview(where: String) =
            assertTrue("Overview control on Compete ($where)", rule.onAllNodes(overview, useUnmergedTree = true).fetchSemanticsNodes().isEmpty())

        rule.onNodeWithTag("fst.quick-links.open").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.quick-links.item.leaderboards")
        val quickLinkItems = rule.onAllNodes(SemanticsMatcher("quick link item") { node ->
            node.config.getOrElse(SemanticsProperties.TestTag) { "" }.startsWith("fst.quick-links.item.")
        }).fetchSemanticsNodes().map { it.config[SemanticsProperties.TestTag] }.toSet()
        assertEquals(setOf("fst.quick-links.item.leaderboards", "fst.quick-links.item.rivals"), quickLinkItems)
        assertNoOverview("Quick Links")
        rule.onNodeWithTag("fst.quick-links.item.leaderboards").performSemanticsAction(SemanticsActions.OnClick)
        repeat(5) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }

        CompeteScopes.resolve(Instrument.entries).forEach { scope ->
            val card = "fst.compete.leaderboard-card.${scope.key}"
            val button = hasTestTag("fst.compete.view-full-leaderboards").and(hasAnyAncestor(hasTestTag(card)))
            val single = (scope as? CompeteScope.Single)?.instrument
            if (single == null) {
                // Combo boards stay previews: no native full combo board yet.
                rule.waitUntil(10_000) {
                    shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
                    rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag(card))
                    rule.onAllNodesWithTag("$card.loading").fetchSemanticsNodes().isEmpty()
                }
                assertNoOverview(scope.key)
                assertTrue("${scope.key} offers a full board", rule.onAllNodes(button).fetchSemanticsNodes().isEmpty())
                assertTrue("${scope.key} offers See All", rule.onAllNodesWithTag("fst.compete.board.see-all.${scope.key}").fetchSemanticsNodes().isEmpty())
                return@forEach
            }
            awaitInCard(card, button)
            rule.onNodeWithTag("fst.compete.grid").performScrollToNode(button)
            assertNoOverview(scope.key)
            rule.onNode(button).performSemanticsAction(SemanticsActions.OnClick)
            waitForTag("fst.full-rankings.title-icon.${single.wireId}")
            rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
            waitForTag("fst.compete.grid")
        }

        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.section.rivals"))
        CompeteScopes.resolve(Instrument.entries).forEach { scope ->
            rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.rivals-card.${scope.key}"))
            assertNoOverview("rivals ${scope.key}")
        }
    }

    @Test
    fun viewAllRivalsMatchesViewFullLeaderboardsAndOpensTheList() {
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        val boardButton = hasTestTag("fst.compete.view-full-leaderboards").and(hasAnyAncestor(hasTestTag("fst.compete.leaderboard-card.Solo_Guitar")))
        awaitInCard("fst.compete.leaderboard-card.Solo_Guitar", boardButton)
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(boardButton)
        val board = rule.onNode(boardButton).fetchSemanticsNode()
        // Read now: the board card leaves composition once the grid scrolls to the rivals card.
        val boardSize = board.size
        val boardLeft = board.boundsInRoot.left
        // Issues #68/#176: Compete's View All Rivals is the same shared button as View Full Leaderboards.
        val rivalsButton = hasTestTag("fst.rivals.view-all").and(hasAnyAncestor(hasTestTag("fst.compete.rivals-card.Solo_Guitar")))
        awaitInCard("fst.compete.rivals-card.Solo_Guitar", rivalsButton)
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(rivalsButton)
        val rivals = rule.onNode(rivalsButton).fetchSemanticsNode()
        assertEquals(boardSize, rivals.size)
        assertEquals(boardLeft, rivals.boundsInRoot.left)
        assertEquals(androidx.compose.ui.semantics.Role.Button, rivals.config[SemanticsProperties.Role])
        // view-all-cta R4: both CTAs read their label, then the card.
        assertEquals(listOf("View All Rivals, Lead"), rivals.config[SemanticsProperties.ContentDescription])
        assertEquals(listOf("View Full Leaderboards, Lead"), board.config[SemanticsProperties.ContentDescription])
        rule.onNode(rivalsButton).performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.all-rivals.list")
    }

    @Test
    fun emptyRivalsCardShowsWebCopy() {
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.leaderboard-card.0f")
        rule.onNodeWithTag("fst.quick-links.open").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.quick-links.item.leaderboards")
        rule.onNodeWithTag("fst.quick-links.item.rivals").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.compete.rivals-card.0f")
        rule.onNodeWithText(CompeteText.noRivals("Lead + Bass + Drums + Tap Vocals")).assertIsDisplayed()
        waitForTag("fst.compete.rivals-card.Solo_Bass")
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.rivals-card.Solo_Bass"))
        rule.onNodeWithText(CompeteText.noRivals("Bass")).assertIsDisplayed()
    }

    @Test
    fun phoneCardsKeepComboTitlesBesideTheirIcons() {
        launch(DebugLaunch(section = FestivalSection.Compete, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.leaderboard-card.0f")
        rule.onNode(hasTestTag("fst.compete.scope-header.row").and(hasAnyAncestor(hasTestTag("fst.compete.leaderboard-card.0f")))).assertIsDisplayed()
    }
}

/** Compete in a narrow lane (issue #120): a combo title moves below its icons instead of breaking after every word. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w280dp-h700dp-xhdpi")
class CompeteNarrowUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun narrowCardsStackComboIconsAboveTheTitle() {
        val debug = DebugLaunch(section = FestivalSection.Compete, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = CompeteFixtures.transport(), settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.waitForIdle()
            rule.onAllNodesWithTag("fst.compete.leaderboard-card.0f").fetchSemanticsNodes().isNotEmpty()
        }
        fun header(kind: String, card: String) = hasTestTag("fst.compete.scope-header.$kind").and(hasAnyAncestor(hasTestTag(card)))
        rule.onNode(header("stacked", "fst.compete.leaderboard-card.0f")).assertIsDisplayed()
        // One instrument and its View All link still fit beside each other.
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(header("row", "fst.compete.leaderboard-card.Solo_Guitar"))
        rule.onNode(header("row", "fst.compete.leaderboard-card.Solo_Guitar")).assertIsDisplayed()
    }
}

// endregion
