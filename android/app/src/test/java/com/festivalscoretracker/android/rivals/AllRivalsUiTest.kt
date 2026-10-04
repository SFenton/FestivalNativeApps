package com.festivalscoretracker.android.rivals

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.data.HttpRequest
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import kotlinx.coroutines.CompletableDeferred
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * All Rivals (`/rivals/all`) on the phone layout against synthetic fixtures: every
 * reachable state (loading, failure and recovery, empty, unresolved, each scope's
 * header), the row's TalkBack semantics and two columns on an expanded window
 * (issue #108). The font-scale 2.0 row wrap is in [RivalRowUiTest].
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class AllRivalsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")
    private val ids = RivalsFixtures.RIVALS
    private val listPath = "/api/player/${RivalsFixtures.PLAYER}/rivals"

    private val transport = RivalsFixtures.transport().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    /** Holds a matching request until the returned deferred completes (null = answer at once). */
    private var hold: (HttpRequest) -> CompletableDeferred<Unit>? = { null }

    // region Harness

    private fun launch(scope: RivalScope, transport: FakeTransport = this.transport) {
        val debug = DebugLaunch(route = RivalRoutes.allRivals(scope), profile = player, stillBackground = true)
        val gated = object : HttpTransport {
            override suspend fun send(request: HttpRequest): HttpResult {
                hold(request)?.await()
                return transport.send(request)
            }
        }
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = gated, settingsStore = InMemoryPreferences())
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
            rule.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun topBarTitle(text: String) = rule.onNode(hasText(text) and hasAnyAncestor(hasTestTag("fst.nav.top-bar")))

    // endregion

    // region Scopes

    @Test
    fun leaderboardListShowsRankLineAndAccessibleRows() {
        launch(RivalScope.Leaderboard(Instrument.Lead))
        waitForTag("fst.all-rivals.list")
        topBarTitle("Lead Rivals").assertIsDisplayed()
        assertEquals("the title is not repeated under the top app bar", 1, rule.onAllNodesWithText("Lead Rivals").fetchSemanticsNodes().size)
        rule.onNodeWithTag("fst.all-rivals.subtitle").assertIsDisplayed()
        rule.onNodeWithText("Your rank: #42 · Total Score", useUnmergedTree = true).assertIsDisplayed()
        // One TalkBack stop per row: name, side, both counts, a button role and a named action.
        val row = rule.onNodeWithTag("fst.rivals.row.${ids[0]}").fetchSemanticsNode()
        assertEquals(
            listOf("Synthetic Neighbour, ahead of you, 4 songs ahead, 5 songs behind"),
            row.config.getOrNull(SemanticsProperties.ContentDescription),
        )
        assertEquals(Role.Button, row.config.getOrNull(SemanticsProperties.Role))
        assertEquals("Open rival", row.config.getOrNull(SemanticsActions.OnClick)?.label)
        assertTrue("row meets the 48 dp target", rule.onNodeWithTag("fst.rivals.row.${ids[0]}").getBoundsInRoot().let { it.bottom - it.top } >= 48.dp)
        rule.onNodeWithTag("fst.rivals.row.${ids[0]}").performClick()
        waitForTag("fst.rival-detail.title")
        assertEquals(1, transport.sent("/api/player/${RivalsFixtures.PLAYER}/leaderboard-rivals/Solo_Guitar/${ids[0]}").size)
    }

    @Test
    fun singleChartListHasNoHeaderAndAnonymousRowsAreNotButtons() {
        launch(RivalScopes.song(listOf(Instrument.Lead)))
        waitForTag("fst.all-rivals.list")
        topBarTitle("Lead Rivals").assertIsDisplayed()
        assertEquals(0, rule.onAllNodesWithTag("fst.all-rivals.subtitle").fetchSemanticsNodes().size)
        waitForTag("fst.rivals.row.anonymous")
        val anonymous = rule.onNodeWithTag("fst.rivals.row.anonymous").fetchSemanticsNode()
        assertEquals(null, anonymous.config.getOrNull(SemanticsProperties.Role))
        assertEquals(null, anonymous.config.getOrNull(SemanticsActions.OnClick))
        ids.take(3).forEach { waitForTag("fst.rivals.row.$it") }
    }

    @Test
    fun commonListNamesItsChartsAndSurvivesAFailedChart() {
        transport.onRaw("$listPath/Solo_Drums") { HttpResult(503, ByteArray(0), mapOf("Retry-After" to "30", "X-FST-Public-Read-Freeze-Reason" to "post-process")) }
        launch(RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums)))
        waitForTag("fst.all-rivals.list")
        topBarTitle("Common Rivals").assertIsDisplayed()
        rule.onNodeWithText("Lead · Bass · Drums", useUnmergedTree = true).assertIsDisplayed()
        waitForTag("fst.rivals.row.${ids[0]}")
        waitForTag("fst.rivals.row.${ids[1]}")
        assertEquals(0, rule.onAllNodesWithTag("fst.service-status.retry").fetchSemanticsNodes().size)
    }

    @Test
    fun comboListNamesItsCharts() {
        launch(RivalScope.Combo("03"))
        waitForTag("fst.rivals.row.${ids[4]}")
        topBarTitle("Lead + Bass Rivals").assertIsDisplayed()
        rule.onNodeWithTag("fst.all-rivals.subtitle").assertIsDisplayed()
        rule.onNodeWithText("Lead · Bass", useUnmergedTree = true).assertIsDisplayed()
    }

    // endregion

    // region States

    @Test
    fun loadingThenRows() {
        val gate = CompletableDeferred<Unit>()
        hold = { if (it.url.contains("/rivals/Solo_Guitar")) gate else null }
        launch(RivalScopes.song(listOf(Instrument.Lead)))
        rule.waitUntil(10_000) {
            settle(100)
            rule.onAllNodesWithContentDescription("Loading rivals").fetchSemanticsNodes().isNotEmpty()
        }
        assertEquals(0, rule.onAllNodesWithTag("fst.all-rivals.list").fetchSemanticsNodes().size)
        gate.complete(Unit)
        waitForTag("fst.rivals.row.${ids[0]}")
    }

    @Test
    fun everyChartFailingShowsStatusThenRetryRecovers() {
        var frozen = true
        listOf("Solo_Guitar", "Solo_Bass").forEach { chart ->
            transport.onRaw("$listPath/$chart") {
                if (frozen) {
                    HttpResult(503, ByteArray(0), mapOf("Retry-After" to "30", "X-FST-Public-Read-Freeze-Reason" to "scrape"))
                } else {
                    HttpResult(200, RivalsFixtures.list(chart, listOf(RivalsFixtures.rival(ids[0], "Synthetic Alpha")), emptyList()).toByteArray())
                }
            }
        }
        launch(RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass)))
        waitForTag("fst.service-status.countdown")
        rule.onNodeWithText("Scores are updating").assertIsDisplayed()
        frozen = false
        rule.onNodeWithTag("fst.service-status.retry").performClick()
        waitForTag("fst.rivals.row.${ids[0]}")
    }

    @Test
    fun emptyListShowsMessage() {
        transport.on("$listPath/Solo_Bass") { RivalsFixtures.list("Solo_Bass", emptyList(), emptyList()) }
        launch(RivalScopes.song(listOf(Instrument.Bass)))
        waitForTag("fst.all-rivals.empty")
        rule.onNodeWithText("Not enough data to identify rivals yet.").assertIsDisplayed()
        topBarTitle("Bass Rivals").assertIsDisplayed()
    }

    @Test
    fun unresolvedComboShowsMessage() {
        launch(RivalScope.FromSettings(com.festivalscoretracker.android.core.rivals.RivalSettingsScope.Combo))
        waitForTag("fst.all-rivals.unresolved")
        rule.onNodeWithText("This rivals list could not be identified.").assertIsDisplayed()
        assertTrue(transport.requests.none { it.url.contains("/rivals/") })
    }

    // endregion

    // region Layout

    @Test
    @Config(qualifiers = "w1280dp-h800dp-mdpi")
    fun expandedWindowUsesTwoColumns() {
        launch(RivalScopes.song(listOf(Instrument.Lead)))
        waitForTag("fst.rivals.row.${ids[1]}")
        val first = rule.onNodeWithTag("fst.rivals.row.${ids[0]}").getBoundsInRoot()
        val second = rule.onNodeWithTag("fst.rivals.row.${ids[1]}").getBoundsInRoot()
        assertEquals(first.top, second.top)
        assertTrue(second.left > first.right)
    }

    // endregion
}
