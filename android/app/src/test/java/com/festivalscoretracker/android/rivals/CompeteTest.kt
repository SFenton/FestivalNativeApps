package com.festivalscoretracker.android.rivals

import com.festivalscoretracker.android.testing.CompeteFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
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
import com.festivalscoretracker.android.presentation.compete.CompeteReads
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
        // Phone card (~379 dp): a combo board without See All keeps its title beside the icons...
        assertFalse(CompeteHeaderLayout.stacks(379f, 4, hasSeeAll = false, largeText = false))
        // ...but beside See All the title would wrap to three lines, so the icons stack.
        assertTrue(CompeteHeaderLayout.stacks(379f, 4, hasSeeAll = true, largeText = false))
        // Half-open book fold panel (~260 dp): the combo title would get a few dp, so the icons stack above it.
        assertTrue(CompeteHeaderLayout.stacks(260f, 4, hasSeeAll = true, largeText = false))
        assertTrue(CompeteHeaderLayout.stacks(250f, 4, hasSeeAll = false, largeText = false))
        // One instrument plus See All still fits that panel.
        assertFalse(CompeteHeaderLayout.stacks(260f, 1, hasSeeAll = true, largeText = false))
        // Boundaries: combo icons 4×36 + 3×2, gap 8, combo title 140, gap 8 + link 80; single icon 36, gap 8, title 100, link 88.
        assertFalse(CompeteHeaderLayout.stacks(386f, 4, hasSeeAll = true, largeText = false))
        assertTrue(CompeteHeaderLayout.stacks(385.9f, 4, hasSeeAll = true, largeText = false))
        assertFalse(CompeteHeaderLayout.stacks(232f, 1, hasSeeAll = true, largeText = false))
        assertTrue(CompeteHeaderLayout.stacks(231.9f, 1, hasSeeAll = true, largeText = false))
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
        rule.onNodeWithTag("fst.compete.board.see-all.Solo_Guitar").performSemanticsAction(SemanticsActions.OnClick)
        rule.waitUntil(10_000) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(50))
            rule.onAllNodesWithTag("fst.compete.grid").fetchSemanticsNodes().isEmpty()
        }
    }

    @Test
    fun rowsKeepTheSongsCountInTheirDescription() {
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        waitForTag("fst.compete.leaderboard-card.Solo_Guitar")
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.spotlight.Solo_Guitar"))
        // Narrow cards may hide the songs column (issue #38); TalkBack still hears the count.
        val spoken = rule.onNodeWithTag("fst.compete.spotlight.Solo_Guitar").fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString()
        assertTrue(spoken, spoken.contains("160 / 250 songs"))
    }

    @Test
    fun sectionsShowProgressIndicatorsUntilRowsOrErrorsArrive() {
        val gate = CompletableDeferred<Unit>()
        // Holds every Compete read until released; Bass's board then fails so its spinner gives way to the inline error.
        val gated = object : HttpTransport {
            override suspend fun send(request: HttpRequest): HttpResult {
                val path = request.url.substringBefore('?')
                if ("/api/rankings" in path || "/rivals/" in path) gate.await()
                if (path.endsWith("/api/rankings/Solo_Bass")) throw IOException("offline")
                return transport.send(request)
            }
        }
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true), gated)
        waitForTag("fst.compete.leaderboard-card.Solo_Guitar.loading")
        rule.onNodeWithTag("fst.compete.leaderboard-card.0f.loading").assertIsDisplayed()
        rule.onNodeWithContentDescription("Loading Lead leaderboard")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(hasTestTag("fst.compete.rivals-card.Solo_Guitar"))
        rule.onNodeWithTag("fst.compete.rivals-card.Solo_Guitar.loading").assertIsDisplayed()

        gate.complete(Unit)
        awaitInCard("fst.compete.rivals-card.Solo_Guitar", hasTestTag("fst.rivals.row.${RivalsFixtures.RIVALS[0]}"))
        assertTrue(rule.onAllNodesWithTag("fst.compete.rivals-card.Solo_Guitar.loading").fetchSemanticsNodes().isEmpty())
        awaitInCard("fst.compete.leaderboard-card.Solo_Guitar", hasTestTag("fst.compete.spotlight.Solo_Guitar"))
        assertTrue(rule.onAllNodesWithTag("fst.compete.leaderboard-card.Solo_Guitar.loading").fetchSemanticsNodes().isEmpty())
        awaitInCard("fst.compete.leaderboard-card.Solo_Bass", hasTestTag("fst.service-status.inline"))
        assertTrue(rule.onAllNodesWithTag("fst.compete.leaderboard-card.Solo_Bass.loading").fetchSemanticsNodes().isEmpty())
    }

    @Test
    fun spinnersGiveWayToEmptyCopyAndRivalsErrors() {
        val gate = CompletableDeferred<Unit>()
        // Drums has no ranked accounts (empty copy); Bass rivals fail (inline error).
        transport.onRaw("/api/rankings/Solo_Drums") {
            HttpResult(200, RankingsFixtures.rankings("Solo_Drums", "totalscore", 1, 10, total = 0).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
        }
        transport.onRaw("/api/rankings/Solo_Drums/${CompeteFixtures.PLAYER}") { HttpResult(404, "{}".toByteArray()) }
        transport.beforeRespond = { request ->
            val path = request.url.substringBefore('?')
            if ("/api/rankings" in path || "/rivals/" in path) gate.await()
            if (path.endsWith("/rivals/Solo_Bass")) throw IOException("offline")
        }
        launch(DebugLaunch(route = CompeteRoute, profile = SelectedPlayer(CompeteFixtures.PLAYER, "Synthetic Player"), stillBackground = true))
        awaitInCard("fst.compete.leaderboard-card.Solo_Drums", hasTestTag("fst.compete.leaderboard-card.Solo_Drums.loading"))
        rule.onNodeWithContentDescription("Loading Drums leaderboard")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
        awaitInCard("fst.compete.rivals-card.Solo_Bass", hasTestTag("fst.compete.rivals-card.Solo_Bass.loading"))
        rule.onNodeWithContentDescription("Loading Bass rivals")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))

        gate.complete(Unit)
        awaitInCard("fst.compete.leaderboard-card.Solo_Drums", hasText(CompeteText.noRankings("Drums")))
        assertTrue(rule.onAllNodesWithTag("fst.compete.leaderboard-card.Solo_Drums.loading").fetchSemanticsNodes().isEmpty())
        awaitInCard("fst.compete.rivals-card.Solo_Bass", hasTestTag("fst.service-status.inline"))
        assertTrue(rule.onAllNodesWithTag("fst.compete.rivals-card.Solo_Bass.loading").fetchSemanticsNodes().isEmpty())
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
        }
        rule.mainClock.autoAdvance = true
        assertTrue("Compete never reappeared", positions.isNotEmpty())
        assertEquals("Compete re-read its boards or rivals on return", readsAway, reads())
        assertTrue("Opening the full board reads only its own page", readsAway >= readsBefore)
        // Kept on the back stack, the grid comes back already laid out at the scroll position it had.
        assertTrue("Compete moved on return: $before -> ${positions.distinct()}", positions.all { it == before })
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
        // One instrument and its See All link still fit beside each other.
        rule.onNodeWithTag("fst.compete.grid").performScrollToNode(header("row", "fst.compete.leaderboard-card.Solo_Guitar"))
        rule.onNode(header("row", "fst.compete.leaderboard-card.Solo_Guitar")).assertIsDisplayed()
    }
}

// endregion
