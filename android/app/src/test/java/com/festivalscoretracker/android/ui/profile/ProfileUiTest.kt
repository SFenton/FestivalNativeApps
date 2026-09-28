package com.festivalscoretracker.android.ui.profile

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
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
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.data.RequestGate
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Profile journeys on the whole shell against synthetic fixtures. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class ProfileUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val store = InMemoryPreferences()
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
        ProfileFixtures.register(this, Fixtures.ACCOUNT_B)
        on("/api/player/${Fixtures.ACCOUNT_B}/history", status = 404) { "{}" }
    }

    private fun launch(debug: DebugLaunch = DebugLaunch(stillBackground = true)) {
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = store)
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

    private fun waitGone(tag: String) {
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isEmpty()
        }
    }

    private fun tap(tag: String) {
        waitForTag(tag)
        rule.onNodeWithTag(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    @Test
    fun searchViewSelectStatisticsDeselect() {
        launch()
        waitForTag("fst.songs.row.s-alpha")
        tap("fst.nav.profile")
        waitForTag("fst.profile.hint")
        rule.onNodeWithTag("fst.profile.search").performTextInput("syn")
        waitForTag("fst.profile.result.${Fixtures.ACCOUNT_A}")
        tap("fst.profile.result.${Fixtures.ACCOUNT_A}")

        // A result views the player; nothing is selected yet.
        waitForTag("fst.player.select")
        // Selection state shows only through the header action (no "Public Profile" line, as on the web).
        assertEquals(0, rule.onAllNodesWithText("Public Profile").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.player.select").assertIsDisplayed()
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.tab.statistics").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.player.available").performScrollToNode(hasTestTag("fst.player.global-rank.Solo_Guitar.available"))
        waitForTag("fst.player.rank-history.Solo_Guitar")
        rule.onNodeWithTag("fst.player.available").performScrollToNode(hasTestTag("fst.player.percentiles.Solo_Guitar"))
        rule.onNodeWithTag("fst.player.available").performScrollToNode(hasTestTag("fst.player.instrument-empty.Solo_Drums"))

        // Select stays on the page and adds the profile tabs.
        rule.onNodeWithTag("fst.player.available").performScrollToNode(hasTestTag("fst.player.select"))
        tap("fst.player.select")
        waitForTag("fst.player.deselect")
        waitForTag("fst.nav.tab.statistics")
        assertEquals(0, rule.onAllNodesWithText("This Is Me").fetchSemanticsNodes().size)
        assertEquals(1, transport.sent("/api/player/${Fixtures.ACCOUNT_A}").size)

        // Statistics shows the same selected profile without another read.
        tap("fst.nav.tab.statistics")
        waitForTag("fst.statistics")
        waitForTag("fst.player.deselect")
        assertEquals(1, transport.sent("/api/player/${Fixtures.ACCOUNT_A}").size)

        // Deselect is confirmed; the Statistics tab then disappears.
        tap("fst.player.deselect")
        waitForTag("fst.player.deselect-confirm")
        tap("fst.player.deselect-confirm.ok")
        waitGone("fst.nav.tab.statistics")
        transport.requests.forEach { request ->
            RequestGate.validateKeyless(request)
            assertTrue(request.headers.keys.none { it.lowercase().startsWith("x-fst-selected") })
        }
    }

    @Test
    fun switchIsConfirmedAndBandsScopeExplains() {
        launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true))
        waitForTag("fst.player.select")
        rule.onNodeWithText("Switch to This Profile").assertIsDisplayed()
        tap("fst.player.select")
        waitForTag("fst.player.switch-confirm")
        tap("fst.player.switch-confirm.cancel")
        waitGone("fst.player.switch-confirm")
        tap("fst.player.select")
        tap("fst.player.switch-confirm.ok")
        waitForTag("fst.player.deselect")

        rule.onNodeWithTag("fst.nav.back").performClick()
        settle()
        tap("fst.nav.profile")
        waitForTag("fst.profile.selected")
        tap("fst.profile.scope.bands")
        waitForTag("fst.profile.bands-unavailable")
        assertEquals(0, transport.requests.count { it.url.contains("/api/bands") })
        tap("fst.profile.deselect")
        tap("fst.profile.deselect-confirm.ok")
        waitGone("fst.nav.tab.statistics")
    }

    @Test
    fun selectionPersistsAcrossColdStart() {
        launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true))
        tap("fst.player.select")
        waitForTag("fst.nav.tab.statistics")
        // A new container over the same preferences is a cold start.
        val container = AppContainer(rule.activity, OkHttpClient(), DebugLaunch(stillBackground = true), transport = transport, settingsStore = store)
        assertEquals(Fixtures.ACCOUNT_A, runBlocking { container.settings.settings.first() }.selectedPlayer?.accountId)
    }

    @Test
    fun scoreHistoryStatesAndSort() {
        launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), route = PlayerHistoryRoute("s-alpha", "Solo_Guitar"), stillBackground = true))
        waitForTag("fst.history.rows")
        waitForTag("fst.history.chart")
        rule.onNodeWithText("Alpha Tune · Lead").assertIsDisplayed()
        tap("fst.history.sort.open")
        waitForTag("fst.history.sort.mode.date")
        tap("fst.history.sort.mode.date")
        tap("fst.history.sort.direction.ascending")
        tap("fst.history.sort.reset")
        rule.onNodeWithText("Sort Scores").assertIsDisplayed()
    }

    @Test
    fun scoreHistoryUnregisteredAndSyncingProfile() {
        transport.on("/api/player/${Fixtures.ACCOUNT_B}", status = 202) { ProfileFixtures.syncing(Fixtures.ACCOUNT_B) }
        launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_B, "Other"), route = PlayerHistoryRoute("s-alpha", "Solo_Guitar"), stillBackground = true))
        waitForTag("fst.history.message")
        rule.onNodeWithText("Score history is only available for registered users.").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.back").performClick()
        settle()
        tap("fst.nav.tab.statistics")
        waitForTag("fst.player.syncing")
        tap("fst.player.retry")
        waitForTag("fst.player.syncing")
    }
}

/** The same journey on an expanded window (permanent drawer, multi-column profile grid). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-mdpi")
class ProfileExpandedUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun statisticsUsesTheSelectedProfileAndFailedReadsRetry() {
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            ProfileFixtures.register(this)
            on("/api/rankings/Solo_Bass/${Fixtures.ACCOUNT_A}", status = 404) { "{}" }
            on("/api/rankings/Solo_Guitar/${Fixtures.ACCOUNT_A}", status = 500) { "{}" }
        }
        val debug = DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = InMemoryPreferences())
        rule.setContent { FestivalApp(container, debug) }
        fun settle() = repeat(4) { shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(100)); rule.waitForIdle() }
        fun waitForTag(tag: String) = rule.waitUntil(10_000) { settle(); rule.onAllNodesWithTag(tag).fetchSemanticsNodes().isNotEmpty() }
        waitForTag("fst.nav.tab.statistics")
        rule.onNodeWithTag("fst.nav.tab.statistics").performClick()
        waitForTag("fst.player.overview")
        waitForTag("fst.player.global-rank.Solo_Guitar.error")
        rule.onNodeWithTag("fst.player.available").performScrollToNode(hasTestTag("fst.player.global-rank.Solo_Bass.unranked"))
        rule.onNodeWithText("Not yet ranked globally on Bass.").assertIsDisplayed()
    }
}
