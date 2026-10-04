package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Band Rankings device journey with Accessibility Test Framework checks on every interaction
 * (`device.py test com.festivalscoretracker.android.journeys.BandRankingsJourneyTest --avd …`,
 * adding `--posture half` on book folds). Logs the page's and both menus' TalkBack reading
 * order, pages, switches band size and Rank By, checks nothing crosses a separating hinge and
 * opens a band through the safe `?teamKey=` read (never `/api/bands/{bandId}`).
 */
@RunWith(AndroidJUnit4::class)
class BandRankingsJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")
    private val transport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )

    private fun row(rank: Int, selected: Boolean = false): String {
        val first = if (selected) RankingsFixtures.SELECTED else RankingsFixtures.accountId(1000 + rank)
        return "fst.band-rankings.row.$first:${RankingsFixtures.accountId(2000 + rank)}"
    }

    private fun waitForDescription(text: String) =
        rule.waitUntil(15_000) { rule.onAllNodesWithContentDescription(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    private fun waitForText(text: String) =
        rule.waitUntil(15_000) { rule.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }

    @Test
    fun pagesSwitchesAndOpensABandAccessibly() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("bandRankings:Band_Duets"), profile = player, stillBackground = true), transport)
        h.waitForTag("fst.band-rankings.population")
        h.waitForTag(row(1))
        waitForDescription("Page 1 of 2")
        h.readingOrder("band-rankings")
        h.assertNothingStraddles("fst.band-rankings.population", "fst.band-rankings.pager", "fst.band-rankings.bottom-bar", row(1), row(2, selected = true))

        h.tap("fst.band-rankings.page-next")
        waitForDescription("Page 2 of 2")
        h.waitForTag(row(26))
        h.readingOrder("band-rankings-page-2")

        h.tap("fst.band-rankings.band-type-menu")
        h.waitForTag("fst.band-rankings.band-type-menu.1")
        h.readingOrder("band-rankings-band-size-menu")
        h.tap("fst.band-rankings.band-type-menu.1")
        waitForText("Trios Leaderboards")
        waitForDescription("Page 1 of 2")

        h.tap("fst.band-rankings.rank-by-menu")
        h.waitForTag("fst.band-rankings.rank-by-menu.2")
        h.readingOrder("band-rankings-rank-by-menu")
        h.tap("fst.band-rankings.rank-by-menu.2")
        rule.waitUntil(15_000) { transport.requests.any { it.url.contains("/api/rankings/bands/Band_Trios?rankBy=fcrate") } }

        h.waitForTag(row(1))
        h.tap(row(1))
        h.waitGone("fst.band-rankings.list")
        assertTrue(transport.requests.none { it.url.contains("/api/bands/") })
        h.assertAccessible()
    }
}
