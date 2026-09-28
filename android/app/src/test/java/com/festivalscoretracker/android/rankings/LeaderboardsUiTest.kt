package com.festivalscoretracker.android.rankings

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.rankings.LeaderboardPreferences
import com.festivalscoretracker.android.presentation.InMemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.shell.FestivalApp
import java.time.Duration
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Shared harness for the Leaderboards journeys on Robolectric against synthetic rankings. */
abstract class LeaderboardsHarness {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    protected val transport: FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
        unranked = setOf("Solo_Bass"),
    )
    protected val store = InMemoryPreferences()
    protected val selected = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")

    protected fun launch(route: String, profile: SelectedPlayer? = null) {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute(route), profile = profile, stillBackground = true)
        val container = AppContainer(rule.activity, OkHttpClient(), debug, transport = transport, settingsStore = store)
        rule.setContent { FestivalApp(container, debug) }
        settle()
    }

    protected fun settle(millis: Long = 400) {
        repeat(4) {
            shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis / 4))
            rule.waitForIdle()
        }
    }

    protected fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    protected fun waitForTag(tag: String) {
        rule.waitUntil(10_000) { settle(100); exists(tag) }
    }

    protected fun waitForText(text: String) {
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithText(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    }

    protected fun waitForDescription(text: String) {
        rule.waitUntil(10_000) { settle(100); rule.onAllNodesWithContentDescription(text, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() }
    }

    /** First node with a tag (the same account can appear on several overview cards). */
    protected fun node(tag: String): SemanticsNodeInteraction = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0]

    protected fun click(tag: String) {
        node(tag).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    protected fun scrollTo(list: String, tag: String) {
        rule.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        settle()
    }

    protected fun isClickable(tag: String) = node(tag).fetchSemanticsNode().config.getOrNull(SemanticsActions.OnClick) != null

    protected fun description(tag: String) = node(tag).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString()
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class LeaderboardsUiTest : LeaderboardsHarness() {
    private val lead = "fst.leaderboards.card.Solo_Guitar"

    @Test
    fun overviewCardsRankByAndViewAll() {
        launch("leaderboards")
        waitForTag("fst.rankings.row.${RankingsFixtures.accountId(1)}")
        assertTrue(exists(lead))
        assertEquals("Rank 1st, Synthetic Player 1. 49,999,000. 199 / 250 songs.", description("fst.rankings.row.${RankingsFixtures.accountId(1)}"))
        // Anonymous production rows read "Unknown User" and do nothing.
        val anonymous = "fst.rankings.row.anonymous-3-3-3"
        assertTrue(description(anonymous)!!.contains("Unknown User"))
        assertFalse(isClickable(anonymous))
        assertTrue(isClickable("fst.rankings.row.${RankingsFixtures.accountId(1)}"))
        // Twelve top-ten reads (nine charts + three band sizes), none of them account-scoped.
        assertEquals(12, transport.requests.count { it.url.contains("/api/rankings/") && it.url.contains("pageSize=10") })
        assertTrue(transport.requests.none { it.url.contains(RankingsFixtures.SELECTED) })

        click("fst.rankings.rank-by-menu")
        click("fst.rankings.rank-by.fcrate")
        rule.waitUntil(10_000) { settle(100); transport.requests.any { it.url.contains("rankBy=fcrate") } }
        waitForText("FC Rate")
        assertEquals("fcrate", store.current[LeaderboardPreferences.KEY_RANK_BY])

        scrollTo("fst.leaderboards", "$lead.view-all")
        click("$lead.view-all")
        waitForText("Lead Rankings")
        waitForTag("fst.full-rankings.population")
        waitForDescription("Page 1 of 3")
        assertTrue(transport.requests.last { it.url.contains("/api/rankings/Solo_Guitar") }.url.contains("rankBy=fcrate&page=1&pageSize=25"))
        click("fst.full-rankings.page-next")
        waitForDescription("Page 2 of 3")
        click("fst.full-rankings.page-last")
        waitForDescription("Page 3 of 3")
        click("fst.full-rankings.page-first")
        waitForDescription("Page 1 of 3")
        click("fst.full-rankings.instrument-menu")
        click("fst.full-rankings.instrument-menu.1")
        waitForText("Bass Rankings")
        click("fst.nav.back")
        waitForTag(lead)
    }

    @Test
    fun spotlightFooterAndYourPage() {
        launch("leaderboards", selected)
        waitForTag("$lead.spotlight")
        assertTrue(description("$lead.spotlight")!!.startsWith("Your rank, 40th. Synthetic Player 40."))
        waitForTag("fst.leaderboards.card.Solo_Bass.spotlight.unranked")
        // The selected player's row opens Statistics, like the web.
        click("$lead.spotlight")
        rule.waitUntil(10_000) { settle(100); !exists(lead) }
    }

    @Test
    fun fullRankingsPinsTheSelectedRowAndJumpsToItsPage() {
        launch("fullRankings:Solo_Guitar", selected)
        waitForTag("fst.full-rankings.spotlight-jump")
        click("fst.full-rankings.spotlight-jump")
        waitForDescription("Page 2 of 3")
        waitForTag("fst.rankings.row.${RankingsFixtures.SELECTED}")
        rule.waitUntil(5_000) { settle(100); !exists("fst.full-rankings.spotlight-footer") }
    }

    @Test
    fun failedCardRetriesInline() {
        var fail = true
        transport.onRaw("/api/rankings/Solo_Guitar") { request ->
            if (fail) {
                HttpResult(500, ByteArray(0))
            } else {
                HttpResult(200, RankingsFixtures.rankings("Solo_Guitar", "totalscore", 1, 10).toByteArray(), mapOf("X-FST-Publication-Id" to "7"))
            }
        }
        launch("leaderboards")
        waitForTag("fst.service-status.inline")
        fail = false
        rule.onAllNodesWithText("Retry", useUnmergedTree = true)[0].performClick()
        waitForTag("fst.rankings.row.${RankingsFixtures.accountId(1)}")
    }

    @Test
    fun bandRankingsPagesSwitchSizeAndOpenBands() {
        launch("bandRankings:Band_Trios", selected)
        waitForText("Trios Rankings")
        waitForTag("fst.band-rankings.population")
        waitForDescription("Page 1 of 2")
        val second = "fst.band-rankings.row.${RankingsFixtures.SELECTED}:${RankingsFixtures.accountId(2002)}"
        assertTrue(description(second)!!.startsWith("Your rank, 2nd. Member 2A + Unknown User."))
        click("fst.band-rankings.page-next")
        waitForDescription("Page 2 of 2")
        click("fst.band-rankings.band-type-menu")
        click("fst.band-rankings.band-type-menu.2")
        waitForText("Quads Rankings")
        waitForDescription("Page 1 of 2")
        click("fst.band-rankings.rank-by-menu")
        click("fst.band-rankings.rank-by-menu.2")
        rule.waitUntil(10_000) { settle(100); transport.requests.any { it.url.contains("/api/rankings/bands/Band_Quad?rankBy=fcrate") } }
        val first = "fst.band-rankings.row.${RankingsFixtures.accountId(1001)}:${RankingsFixtures.accountId(2001)}"
        waitForTag(first)
        click(first)
        rule.waitUntil(10_000) { settle(100); !exists("fst.band-rankings.list") }
        assertTrue(transport.requests.none { it.url.contains("/api/bands/") })
    }

    @Test
    fun songLeaderboardRowsOpenPlayers() {
        launch("songLeaderboard:s-alpha:Solo_Guitar")
        waitForDescription("Page 1 of 3")
        val row = "fst.song-leaderboard.row.${Fixtures.ACCOUNT_A.dropLast(2)}10"
        waitForTag(row)
        click(row)
        rule.waitUntil(10_000) { settle(100); !exists("fst.song-leaderboard.list") }
    }
}

@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w1280dp-h800dp-xhdpi")
class LeaderboardsExpandedUiTest : LeaderboardsHarness() {
    @Test
    fun expandedOverviewUsesAGrid() {
        launch("leaderboards")
        waitForTag("fst.leaderboards.card.Solo_Bass")
        val lead = node("fst.leaderboards.card.Solo_Guitar").fetchSemanticsNode().boundsInRoot
        val bass = node("fst.leaderboards.card.Solo_Bass").fetchSemanticsNode().boundsInRoot
        assertEquals(lead.top, bass.top, 1f)
        assertTrue(bass.left > lead.right)
    }

    @Test
    fun expandedBoardsUseASupportingPane() {
        launch("fullRankings:Solo_Drums")
        waitForTag("fst.full-rankings.supporting-pane")
        waitForDescription("Page 1 of 3")
        assertFalse(exists("fst.full-rankings.bottom-bar"))
    }
}
