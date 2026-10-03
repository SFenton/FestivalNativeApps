package com.festivalscoretracker.android.rivals

import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.rivals.RivalSettingsScope
import com.festivalscoretracker.android.core.rivals.RivalrySort
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.presentation.LoadState
import com.festivalscoretracker.android.presentation.rivals.AllRivalsViewModel
import com.festivalscoretracker.android.presentation.rivals.RivalDetailViewModel
import com.festivalscoretracker.android.presentation.rivals.RivalsHubTab
import com.festivalscoretracker.android.presentation.rivals.RivalsHubViewModel
import com.festivalscoretracker.android.presentation.rivals.map
import com.festivalscoretracker.android.presentation.valueOrNull
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.MainDispatcherRule
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Hub, All Rivals and Rival Detail/Rivalry view models over synthetic fixtures. */
@OptIn(ExperimentalCoroutinesApi::class)
class RivalsViewModelTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val player = RivalsFixtures.PLAYER
    private val ids = RivalsFixtures.RIVALS
    private val leadBass = setOf(Instrument.Lead, Instrument.Bass)

    private fun repository(transport: FakeTransport = RivalsFixtures.transport()) = RivalsRepository(FestivalApi("https://fixture.test", transport))

    // region Hub

    @Test
    fun hubBuildsCommonComboAndChartCards() = runTest(main.dispatcher) {
        val hub = RivalsHubViewModel(player, leadBass, repository(), ServiceRetryBackoff())
        assertFalse(hub.songContent.value.settled)
        advanceUntilIdle()
        val content = hub.songContent.value
        assertTrue(content.settled)
        assertFalse(content.empty)
        assertNull(content.fullPageIssue)
        assertEquals(listOf("common", "combo", "Solo_Guitar", "Solo_Bass"), content.sections.map { it.id })
        val common = content.sections[0]
        assertEquals("Common Rivals", common.title)
        assertEquals(RivalScopes.song(leadBass), common.seeAll)
        assertEquals(listOf(ids[0], ids[1]), common.state.valueOrNull!!.map { it.rival.accountId })
        val combo = content.sections[1]
        assertEquals("Combined Rivals", combo.title)
        assertEquals(RivalScope.FromSettings(RivalSettingsScope.Combo), combo.seeAll)
        assertEquals(RivalScope.Combo("03"), combo.rowScope)
        val lead = content.sections[2]
        assertEquals(Instrument.Lead, lead.instrument)
        assertEquals(4, lead.state.valueOrNull!!.size)
        assertEquals(RivalsHubTab.Song, hub.tab.value)
    }

    @Test
    fun leaderboardTabLoadsOnFirstSelection() = runTest(main.dispatcher) {
        val transport = RivalsFixtures.transport()
        val hub = RivalsHubViewModel(player, leadBass, repository(transport), ServiceRetryBackoff())
        advanceUntilIdle()
        assertTrue(transport.sent("/api/player/$player/leaderboard-rivals/Solo_Guitar").isEmpty())
        hub.select(RivalsHubTab.Leaderboard)
        advanceUntilIdle()
        assertEquals(RivalsHubTab.Leaderboard, hub.tab.value)
        val content = hub.leaderboardContent.value
        assertEquals(listOf("leaderboard.Solo_Guitar", "leaderboard.Solo_Bass"), content.sections.map { it.id })
        assertEquals(RivalScope.Leaderboard(Instrument.Lead), content.sections[0].rowScope)
        hub.refresh()
        advanceUntilIdle()
        assertEquals(2, transport.sent("/api/player/$player/leaderboard-rivals/Solo_Guitar").size)
    }

    @Test
    fun hubEmptyAndSingleChart() = runTest(main.dispatcher) {
        val hub = RivalsHubViewModel(player, setOf(Instrument.Drums), repository(), ServiceRetryBackoff())
        advanceUntilIdle()
        assertTrue(hub.songContent.value.empty)
        assertTrue(hub.songContent.value.sections.isEmpty())
        val none = RivalsHubViewModel(player, emptySet(), repository(), ServiceRetryBackoff())
        advanceUntilIdle()
        assertTrue(none.songContent.value.empty)
        assertTrue(none.leaderboardContent.value.empty)
    }

    @Test
    fun hubFullPageFreezeCountsDownAndPartialFailureStaysInline() = runTest(main.dispatcher) {
        val transport = FakeTransport.standard()
        var frozen = true
        listOf("Solo_Guitar", "Solo_Bass", "03").forEach { scope ->
            transport.onRaw("/api/player/$player/rivals/$scope") {
                if (frozen) {
                    HttpResult(503, ByteArray(0), mapOf("Retry-After" to "30", "X-FST-Public-Read-Freeze-Reason" to "scrape"))
                } else {
                    HttpResult(200, RivalsFixtures.list(scope, listOf(RivalsFixtures.rival(ids[0], "Synthetic Alpha")), emptyList()).toByteArray())
                }
            }
        }
        val hub = RivalsHubViewModel(player, leadBass, repository(transport), ServiceRetryBackoff())
        runCurrent()
        val content = hub.songContent.value
        assertTrue(content.fullPageIssue is ServiceIssue.ScrapeInProgress)
        assertEquals(30, content.countdown)
        frozen = false
        advanceTimeBy(31_000)
        runCurrent()
        assertNull(hub.songContent.value.fullPageIssue)
        assertEquals(listOf("common", "combo", "Solo_Guitar", "Solo_Bass"), hub.songContent.value.sections.map { it.id })

        val partial = FakeTransport.standard().apply {
            on("/api/player/$player/rivals/Solo_Guitar") { RivalsFixtures.list("Solo_Guitar", listOf(RivalsFixtures.rival(ids[0], "A")), emptyList()) }
            onRaw("/api/player/$player/rivals/Solo_Bass") { HttpResult(500, ByteArray(0)) }
        }
        val mixed = RivalsHubViewModel(player, setOf(Instrument.Lead, Instrument.Bass, Instrument.Karaoke), repository(partial), ServiceRetryBackoff())
        advanceUntilIdle()
        val sections = mixed.songContent.value.sections
        assertNull(mixed.songContent.value.fullPageIssue)
        assertTrue(sections.first { it.id == "Solo_Bass" }.state is LoadState.Failed)
        assertFalse(sections.any { it.id == "common" })
        partial.on("/api/player/$player/rivals/Solo_Bass") { RivalsFixtures.list("Solo_Bass", listOf(RivalsFixtures.rival(ids[0], "A")), emptyList()) }
        mixed.retry("Solo_Bass")
        advanceUntilIdle()
        assertTrue(mixed.songContent.value.sections.any { it.id == "common" })
        mixed.retry("common")
        mixed.retry("combo")
        mixed.retry("leaderboard.Solo_Guitar")
        mixed.retryFailed()
        advanceUntilIdle()
    }

    @Test
    fun loadStateMapKeepsNonLoadedStates() {
        assertEquals(LoadState.Loading, LoadState.Loading.map { 1 })
        val failed = LoadState.Failed(ServiceIssue.Offline)
        assertEquals(failed, failed.map { 1 })
        assertEquals(LoadState.Loaded(2, refreshing = true), LoadState.Loaded(1, refreshing = true).map { it + 1 })
    }

    // endregion

    // region All rivals

    @Test
    fun allRivalsResolvesEveryScopeKind() = runTest(main.dispatcher) {
        val repo = repository()
        val common = AllRivalsViewModel(player, RivalScope.FromSettings(RivalSettingsScope.Common), leadBass, repo, ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals("Common Rivals", common.title)
        assertEquals(listOf(ids[0], ids[1]), common.state.value.valueOrNull!!.entries.map { it.rival.accountId })
        assertEquals("Lead · Bass", common.state.value.valueOrNull!!.subtitle)

        val lead = AllRivalsViewModel(player, RivalScopes.song(listOf(Instrument.Lead)), leadBass, repo, ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals("Lead Rivals", lead.title)
        assertEquals(4, lead.state.value.valueOrNull!!.entries.size)
        assertNull(lead.state.value.valueOrNull!!.subtitle)

        val board = AllRivalsViewModel(player, RivalScope.Leaderboard(Instrument.Lead), leadBass, repo, ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals("Your rank: #42 · Total Score", board.state.value.valueOrNull!!.subtitle)

        val combo = AllRivalsViewModel(player, RivalScope.FromSettings(RivalSettingsScope.Combo), leadBass, repo, ServiceRetryBackoff())
        advanceUntilIdle()
        assertEquals(RivalScope.Combo("03"), combo.scope)
        assertEquals("Lead + Bass Rivals", combo.title)
        assertEquals("Lead · Bass", combo.state.value.valueOrNull!!.subtitle)

        val unresolved = AllRivalsViewModel(player, RivalScope.FromSettings(RivalSettingsScope.Combo), setOf(Instrument.Lead), repo, ServiceRetryBackoff())
        advanceUntilIdle()
        assertNull(unresolved.scope)
        assertEquals("Combined Rivals", unresolved.title)
        assertEquals(LoadState.Loading, unresolved.state.value)
        unresolved.retry()
        combo.retry()
        advanceUntilIdle()
    }

    // endregion

    // region Detail

    @Test
    fun detailCategorizesAndResolvesNames() = runTest(main.dispatcher) {
        val transport = RivalsFixtures.transport()
        val detail = RivalDetailViewModel(player, ids[0], "Route Name", RivalScopes.song(listOf(Instrument.Lead)), false, leadBass, repository(transport), { FestivalApi("https://fixture.test", transport).catalog() }, ServiceRetryBackoff())
        assertEquals("Route Name", detail.displayName.value)
        advanceUntilIdle()
        val content = detail.state.value.valueOrNull!!
        assertEquals("Synthetic Rival", content.rivalName)
        assertEquals("Synthetic Rival", detail.displayName.value)
        assertEquals(6, content.categories.size)
        assertEquals("8 shared songs · 5 ahead / 3 behind", content.summary)
        assertEquals(3, detail.catalog.value.size)
        val category = detail.category(content, "almost_passed", RivalrySort.TheyLead)
        assertEquals(listOf(-9, -2), category!!.songs.map { it.rankDelta })
        assertNull(detail.category(content, "nope", RivalrySort.Category))
        detail.setSort(RivalrySort.Title)
        assertEquals(RivalrySort.Title, detail.sort.value)
        detail.retry()
        advanceUntilIdle()
    }

    @Test
    fun aFrozenDetailRebuildsFromRivalsAllWithCatalogueTitles() = runTest(main.dispatcher) {
        // Issue #95: detail is 503 during a publish freeze; rivals/all supplies the cards.
        val transport = RivalsFixtures.transport().apply {
            onRaw("/api/player/$player/rivals/Solo_Guitar/${ids[0]}") { HttpResult(503, ByteArray(0), mapOf("X-FST-Public-Read-Freeze-Reason" to "post-process")) }
            on("/api/player/$player/rivals/all") {
                """{"accountId":"$player","songs":["zz-unknown","s-alpha"],"combos":[{"combo":"01","above":[{"accountId":"${ids[0]}","displayName":"All Name",""" +
                    """"direction":"above","sharedSongCount":2,"aheadCount":2,"behindCount":0,"rivalScore":1,"samples":[""" +
                    """{"s":0,"i":"Solo_Guitar","ur":10,"rr":12,"us":5,"rs":4},{"s":1,"i":"Solo_Guitar","ur":10,"rr":11,"us":5,"rs":4}]}],"below":[]}]}"""
            }
        }
        val detail = RivalDetailViewModel(player, ids[0], "Route Name", RivalScopes.song(listOf(Instrument.Lead)), false, leadBass, repository(transport), { FestivalApi("https://fixture.test", transport).catalog() }, ServiceRetryBackoff())
        advanceUntilIdle()
        val content = detail.state.value.valueOrNull!!
        assertEquals("All Name", content.rivalName)
        assertEquals("2 shared songs · 2 ahead / 0 behind", content.summary)
        val mode = content.categories.first { it.songs.size == 2 }.key
        assertEquals(listOf(null, null), content.categories.first { it.key == mode }.songs.map { it.title })
        val titled = detail.category(content, mode, RivalrySort.Title)!!.songs
        assertEquals(listOf("Alpha Tune", null), titled.map { it.title })
        assertEquals("Band One", titled[0].artist)
    }

    @Test
    fun findRivalDetailUsesSettingsScopesWithLiveFallback() = runTest(main.dispatcher) {
        val transport = RivalsFixtures.transport()
        val detail = RivalDetailViewModel(
            player, ids[2], "Found", RivalScope.FromSettings(RivalSettingsScope.All), true, leadBass, repository(transport),
            { throw IllegalStateException("catalogue down") }, ServiceRetryBackoff(),
        )
        advanceUntilIdle()
        assertNotNull(detail.state.value.valueOrNull)
        val request = transport.sent("/api/player/$player/rivals/03/${ids[2]}").single()
        assertTrue(request.url.endsWith("allowLiveFallback=true"))
        assertTrue(detail.catalog.value.isEmpty())

        val anonymousName = RivalDetailViewModel(player, ids[3], null, RivalScope.Leaderboard(Instrument.Bass), false, leadBass, repository(FakeTransport.standard()), { throw IllegalStateException() }, ServiceRetryBackoff())
        advanceUntilIdle()
        val empty = anonymousName.state.value.valueOrNull!!
        assertTrue(empty.categories.isEmpty())
        assertNull(empty.rivalName)
    }

    // endregion
}
