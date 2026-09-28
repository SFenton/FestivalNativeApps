package com.festivalscoretracker.android.rivals

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Rivals journeys on the phone layout against synthetic fixtures. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class RivalsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")
    private val ids = RivalsFixtures.RIVALS

    private val transport = RivalsFixtures.transport().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/account/search") { """{"results":[{"accountId":"${RivalsFixtures.PLAYER}","displayName":"Synthetic Player"},{"accountId":"${ids[2]}","displayName":"Synthetic Gamma"}]}""" }
        on("/api/player/${RivalsFixtures.PLAYER}/rivals/0f/${ids[2]}") { RivalsFixtures.detail(ids[2], deltas = listOf(3, -3)) }
    }

    private fun launch(debug: DebugLaunch, transport: FakeTransport = this.transport) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    private fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    private fun waitForTag(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitForText(text: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun scrollTo(grid: String, tag: String) {
        rule.onNodeWithTag(grid).performScrollToNode(hasTestTag(tag))
        settle(100)
    }

    @Test
    fun hubShowsCommonAndChartCardsThenDetailAndRivalry() {
        launch(DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true))
        waitForTag("fst.rivals.section.common")
        rule.onNodeWithTag("fst.rivals.tab").assertIsDisplayed()
        rule.onNodeWithTag("fst.rivals.jump").assertIsDisplayed()
        scrollTo("fst.rivals.grid", "fst.rivals.section.Solo_Guitar")
        assertTrue(rule.onAllNodesWithTag("fst.rivals.row.anonymous").fetchSemanticsNodes().isNotEmpty())
        scrollTo("fst.rivals.grid", "fst.rivals.section.common")
        rule.onNodeWithTag("fst.rivals.section.common").assertIsDisplayed()
        rule.onAllNodesWithTag("fst.rivals.row.${ids[1]}")[0].performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rival-detail.title")
        rule.onNodeWithText("Synthetic Player vs. Synthetic Rival").assertIsDisplayed()
        rule.onNodeWithTag("fst.rival-detail.summary").assertIsDisplayed()
        rule.onNodeWithTag("fst.rival-detail.category.closest_battles").assertIsDisplayed()
        rule.onNodeWithTag("fst.rival-detail.see-all.closest_battles").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rivalry.title")
        rule.onNodeWithText("vs. Synthetic Rival").assertIsDisplayed()
        rule.onNodeWithTag("fst.rivalry.sort").performClick()
        settle()
        rule.onNodeWithTag("fst.rivalry.sort.title").performClick()
        settle()
        waitForTag("fst.rivals.song.s-alpha.Solo_Guitar")
        rule.onNodeWithTag("fst.rivals.song.s-alpha.Solo_Guitar").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.song-detail.intensity")
        // Common detail merged both charts' comparisons (typed scope on the route).
        assertEquals(1, transport.sent("/api/player/${RivalsFixtures.PLAYER}/rivals/Solo_Bass/${ids[1]}").size)
    }

    @Test
    fun seeAllOpensTheScopeListAndLeaderboardTab() {
        launch(DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true))
        waitForTag("fst.rivals.section.Solo_Guitar")
        scrollTo("fst.rivals.grid", "fst.rivals.see-all.Solo_Guitar")
        rule.onNodeWithTag("fst.rivals.see-all.Solo_Guitar").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.all-rivals.title")
        rule.onNodeWithTag("fst.all-rivals.title").assertTextEquals("Lead Rivals")
        waitForTag("fst.rivals.row.anonymous")
        rule.onNodeWithTag("fst.rivals.row.${ids[2]}").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rival-detail.title")
        rule.onNodeWithTag("fst.nav.back").performClick()
        settle()
        rule.onNodeWithTag("fst.nav.back").performClick()
        waitForTag("fst.rivals.tab.leaderboard")
        rule.onNodeWithTag("fst.rivals.tab.leaderboard").performClick()
        waitForTag("fst.rivals.section.leaderboard.Solo_Guitar")
        rule.onAllNodesWithTag("fst.rivals.row.${ids[0]}")[0].performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rival-detail.title")
        assertEquals(1, transport.sent("/api/player/${RivalsFixtures.PLAYER}/leaderboard-rivals/Solo_Guitar/${ids[0]}").size)
    }

    @Test
    fun findRivalOpensDetailWithLiveFallback() {
        launch(DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true))
        waitForTag("fst.rivals.findRival")
        rule.onNodeWithTag("fst.rivals.findRival").performClick()
        waitForTag("fst.rivals.find.search")
        rule.onNodeWithTag("fst.rivals.find.search").performTextInput("Synth")
        settle(800)
        waitForTag("fst.rivals.find.result.${ids[2]}")
        assertEquals(0, rule.onAllNodesWithTag("fst.rivals.find.result.${RivalsFixtures.PLAYER}").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.rivals.find.result.${ids[2]}").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rival-detail.title")
        val sent = transport.sent("/api/player/${RivalsFixtures.PLAYER}/rivals/0f/${ids[2]}").single()
        assertTrue(sent.url.endsWith("allowLiveFallback=true"))
        assertTrue(transport.requests.none { it.url.contains("allowLiveFallback") && !it.url.contains(ids[2]) })
    }

    @Test
    fun deepLinkedDetailWithoutSongsAndNoPlayerStates() {
        launch(DebugLaunch(route = RivalRoutes.detail(ids[3], "Synthetic Delta", RivalScope.Leaderboard(Instrument.Bass)), profile = player, stillBackground = true))
        waitForTag("fst.rival-detail.empty")
        rule.onNodeWithText("No song data for this rival.").assertIsDisplayed()
        rule.onNodeWithTag("fst.rival-detail.view-profile").performClick()
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithTag("fst.rival-detail.empty").fetchSemanticsNodes().isEmpty() }
    }

    @Test
    fun anonymousShowsChooseProfile() {
        launch(DebugLaunch(route = RivalRoutes.allRivals(RivalScopes.song(listOf(Instrument.Lead))), anonymous = true, stillBackground = true))
        waitForTag("fst.rivals.chooseProfile")
        rule.onNodeWithText("Track a player to see their rivals.").assertIsDisplayed()
        rule.onNodeWithTag("fst.rivals.chooseProfile.action").performClick()
        waitForTag("fst.profile.sheet")
    }

    @Test
    fun scrapeFreezeShowsCountdownThenRecovers() {
        launch(DebugLaunch(route = RivalsRoute, profile = player, forceFreeze = true, stillBackground = true))
        waitForTag("fst.service-status.countdown")
        rule.onNodeWithText("Scores are updating").assertIsDisplayed()
        rule.onNodeWithTag("fst.service-status.retry").performClick()
        waitForTag("fst.rivals.section.common")
    }

    @Test
    fun unresolvableListAndUnknownRivalryMode() {
        launch(DebugLaunch(route = RivalRoutes.allRivals(RivalScope.FromSettings(com.festivalscoretracker.android.core.rivals.RivalSettingsScope.All)), profile = player, stillBackground = true))
        waitForTag("fst.all-rivals.unresolved")
    }

    @Test
    fun rivalryWithUnknownModeShowsEmpty() {
        launch(DebugLaunch(route = com.festivalscoretracker.android.core.nav.RivalryRoute(ids[0], "weird"), profile = player, section = FestivalSection.Songs, stillBackground = true))
        waitForTag("fst.rivalry.empty")
        rule.onNodeWithText("weird").assertIsDisplayed()
    }

    @Test
    fun quickLinksJumpOnHubAndDetail() {
        launch(DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true))
        waitForTag("fst.rivals.jump")
        rule.onNodeWithTag("fst.rivals.jump").performClick()
        waitForTag("fst.rivals.jump.Solo_Bass")
        rule.onNodeWithTag("fst.rivals.jump.Solo_Bass").performClick()
        waitForTag("fst.rivals.section.Solo_Bass")
        rule.onNodeWithTag("fst.rivals.section.Solo_Bass").assertIsDisplayed()
        scrollTo("fst.rivals.grid", "fst.rivals.row.${ids[3]}")
        rule.onNodeWithTag("fst.rivals.row.${ids[3]}").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rival-detail.jump")
        rule.onNodeWithTag("fst.rival-detail.jump").performClick()
        waitForTag("fst.rival-detail.jump.almost_passed")
        rule.onNodeWithTag("fst.rival-detail.jump.almost_passed").performClick()
        waitForTag("fst.rival-detail.category.almost_passed")
    }

    @Test
    fun emptyHubAndInlineCardFailureRecovers() {
        val empty = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        launch(DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true), empty)
        waitForTag("fst.rivals.empty")
        rule.onNodeWithText("Not enough data to identify rivals yet.").assertIsDisplayed()
        rule.onNodeWithTag("fst.rivals.tab.leaderboard").performClick()
        waitForText("No ranking data available.")
    }

    @Test
    fun failingChartShowsInlineStatusAndRetries() {
        var failing = true
        transport.onRaw("/api/player/${RivalsFixtures.PLAYER}/rivals/Solo_Bass") {
            if (failing) {
                com.festivalscoretracker.android.data.HttpResult(500, ByteArray(0))
            } else {
                com.festivalscoretracker.android.data.HttpResult(200, RivalsFixtures.list("Solo_Bass", listOf(RivalsFixtures.rival(ids[3], "Synthetic Delta")), emptyList()).toByteArray())
            }
        }
        launch(DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true))
        waitForTag("fst.rivals.section.Solo_Guitar")
        scrollTo("fst.rivals.grid", "fst.rivals.section.Solo_Bass")
        waitForTag("fst.service-status.inline")
        failing = false
        rule.onNodeWithText("Retry").performSemanticsAction(SemanticsActions.OnClick)
        waitForTag("fst.rivals.row.${ids[3]}")
    }

    @Test
    fun mixedChartComparisonShowsBothIcons() {
        val mixed = RivalsFixtures.detail(ids[0]).replace("\"userInstrument\":null,\"rivalInstrument\":null", "\"userInstrument\":\"Solo_PeripheralCymbals\",\"rivalInstrument\":\"Solo_PeripheralDrums\"")
        transport.on("/api/player/${RivalsFixtures.PLAYER}/rivals/Solo_Guitar/${ids[0]}") { mixed }
        launch(DebugLaunch(route = RivalRoutes.detail(ids[0], null, RivalScopes.song(listOf(Instrument.Lead))), profile = player, stillBackground = true))
        waitForTag("fst.rival-detail.category.closest_battles")
        assertTrue(rule.onAllNodesWithTag("fst.rivals.song.s-alpha.Solo_Guitar").fetchSemanticsNodes().isNotEmpty())
    }
}
