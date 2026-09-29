package com.festivalscoretracker.android.bands

import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performScrollToNode
import androidx.compose.ui.test.performSemanticsAction
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.AppContainer
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.data.HttpResult
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

/** Whole-shell Bands journeys on Robolectric against synthetic band fixtures. */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class BandsUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val transport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )
    private val player = SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player")
    private val duoRoute = "band:${BandFixtures.DUO_ID}:Band_Duets:${BandFixtures.DUO_KEY}"

    private fun launch(route: String, profile: SelectedPlayer? = null) {
        val debug = DebugLaunch(route = DebugLaunch.parseRoute(route), profile = profile, stillBackground = true)
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
            rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun click(tag: String) {
        rule.onNodeWithTag(tag, useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    private fun scrollTo(list: String, tag: String) {
        rule.onNodeWithTag(list).performScrollToNode(hasTestTag(tag))
        settle()
    }

    // region Landing

    @Test
    fun bandsWithoutAnIdShowsBandNotFound() {
        launch("bands")
        waitForTag("fst.bands.not-found")
        rule.onNodeWithText("Band Not Found").assertIsDisplayed()
        assertTrue(transport.requests.none { it.url.contains("/api/bands") })
    }

    @Test
    fun playerBandsOpensBandDetail() {
        launch("playerBands:${player.accountId}", player)
        waitForTag("fst.player-bands.screen")
        waitForTag("fst.player-bands.row.${BandFixtures.DUO_ID}")
        rule.onNodeWithText("All Bands · 30 bands").assertIsDisplayed()
        click("fst.player-bands.row.${BandFixtures.DUO_ID}")
        waitForTag("fst.band.members-section")
    }

    // endregion

    // region Player bands

    @Test
    fun playerBandsGroupsPagingAndEmpty() {
        launch("playerBands:${BandFixtures.PLAYER}")
        waitForTag("fst.player-bands.row.${BandFixtures.DUO_ID}")
        // Name comes from the account's own member row when the route carries none.
        rule.onNodeWithText("Synthetic Lead's Bands").assertIsDisplayed()
        scrollTo("fst.player-bands.list", "fst.player-bands.page-next")
        click("fst.player-bands.page-next")
        waitForTag("fst.player-bands.row.band-25")
        assertTrue(transport.requests.last().url.contains("page=2"))
        click("fst.player-bands.page-first")
        click("fst.player-bands.group.duos")
        waitForTag("fst.player-bands.empty")
        click("fst.player-bands.group.quads")
        waitForTag("fst.player-bands.row.band-1")
        rule.onNodeWithText("Quads · 2 bands").assertIsDisplayed()
        assertEquals(false, exists("fst.player-bands.page-next"))
    }

    @Test
    fun playerBandsFailureShowsRetry() {
        transport.on("/api/player/${BandFixtures.PLAYER}/bands", status = 500) { "{}" }
        launch("playerBands:${BandFixtures.PLAYER}")
        waitForTag("fst.player-bands.error")
        waitForTag("fst.service-status.retry")
    }

    @Test
    fun invalidPlayerAccountShowsNotFound() {
        launch("playerBands:bad.id")
        waitForTag("fst.player-bands.invalid")
    }

    // endregion

    // region Band detail

    @Test
    fun bandDetailShowsSectionsAndLinks() {
        launch(duoRoute)
        waitForTag("fst.band.members-section")
        rule.onNodeWithText("Synthetic Lead + Synthetic Bass").assertIsDisplayed()
        rule.onNodeWithText("Duos · 29 appearances").assertIsDisplayed()
        assertTrue(exists("fst.band.member.${Fixtures.ACCOUNT_A}"))
        assertTrue(exists("fst.band.stat.rank"))
        rule.onNodeWithText("Total Score Rank").assertIsDisplayed()
        click("fst.band.rank-by")
        click("fst.band.rank-by.fcrate")
        rule.onNodeWithText("FC Rate Rank").assertIsDisplayed()
        waitForTag("fst.band.history-chart")
        assertTrue(exists("fst.band.history-row.2024-01-03"))
        waitForTag("fst.band.song-row.s-alpha")
        assertTrue(exists("fst.band.song-row.s-missing"))
        rule.onNodeWithText("Unknown Song").assertExists()
        click("fst.band.song-row.s-alpha")
        waitForTag("fst.nav.back")
        assertTrue(transport.requests.none { it.url.contains("/api/bands/") })
    }

    @Test
    fun bandMemberOpensPlayerAndStatLinksRankings() {
        launch(duoRoute)
        waitForTag("fst.band.member.${Fixtures.ACCOUNT_A}")
        click("fst.band.member.${Fixtures.ACCOUNT_A}")
        waitForTag("fst.player")
    }

    @Test
    fun bareBandIdIsUnresolvedWithoutRequests() {
        launch("band:${BandFixtures.DUO_ID}")
        waitForTag("fst.band.unresolved")
        assertTrue(transport.requests.none { it.url.contains("/rankings/bands") })
    }

    @Test
    fun unrankedBandAndSectionFailures() {
        transport.onRaw("/api/rankings/bands/Band_Duets/${BandFixtures.DUO_KEY}/songs") { HttpResult(500, ByteArray(0)) }
        transport.on("/api/rankings/bands/Band_Duets/${BandFixtures.DUO_KEY}/history") { BandFixtures.history(status = "stale", empty = true) }
        launch(duoRoute)
        waitForTag("fst.band.history-empty")
        rule.onNodeWithText("behind the latest", substring = true).assertExists()
        waitForTag("fst.service-status.inline")
    }

    @Test
    fun unknownTeamShowsNotFound() {
        launch("band:x:Band_Duets:${Fixtures.ACCOUNT_B}")
        waitForTag("fst.band.error")
    }

    @Test
    @Config(qualifiers = "w1280dp-h800dp-mdpi")
    fun expandedBandDetailSplitsIntoPanes() {
        launch(duoRoute)
        waitForTag("fst.band.pane.leading")
        assertTrue(exists("fst.band.pane.trailing"))
        waitForTag("fst.band.history-chart")
    }

    // endregion

    // region Song band leaderboard

    @Test
    fun songBandLeaderboardSwitchesSizesAndOpensBands() {
        launch("songBandLeaderboard:s-alpha:Band_Duets")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        rule.onNodeWithText("Duos · 30 entries").assertIsDisplayed()
        rule.onNodeWithText("100%", useUnmergedTree = true).assertExists()
        assertTrue(rule.onAllNodesWithText("97.5%", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        waitForTag("fst.song-band-leaderboard.song")
        scrollTo("fst.song-band-leaderboard.list", "fst.song-band-leaderboard.page-last")
        click("fst.song-band-leaderboard.page-last")
        waitForTag("fst.song-band-leaderboard.row.band-26:26")
        rule.onNodeWithTag("fst.song-band-leaderboard.list").performScrollToNode(hasTestTag("fst.song-band-leaderboard.band-type.Band_Quad"))
        click("fst.song-band-leaderboard.band-type.Band_Quad")
        waitForTag("fst.song-band-leaderboard.empty")
        click("fst.song-band-leaderboard.band-type.Band_Trios")
        waitForTag("fst.song-band-leaderboard.row.band-1:1")
        click("fst.song-band-leaderboard.row.band-1:1")
        waitForTag("fst.band.screen")
    }

    @Test
    fun songBandLeaderboardFailureAndSongLink() {
        transport.onRaw("/api/leaderboard/s-alpha/bands/Band_Duets") { HttpResult(500, ByteArray(0)) }
        launch("songBandLeaderboard:s-alpha")
        waitForTag("fst.song-band-leaderboard.error")
        waitForTag("fst.song-band-leaderboard.song")
        click("fst.song-band-leaderboard.song")
        waitForTag("fst.nav.back")
    }

    // endregion

    @Test
    fun debugRoutesParseBandShapes() {
        val band = DebugLaunch.parseRoute("band:id:Band_Trios:a:b:c") as com.festivalscoretracker.android.core.nav.BandRoute
        assertEquals("a:b:c", band.teamKey)
        assertEquals("Band_Trios", band.bandType)
        val bare = DebugLaunch.parseRoute("band:id") as com.festivalscoretracker.android.core.nav.BandRoute
        assertEquals(null, bare.teamKey)
        val board = DebugLaunch.parseRoute("songBandLeaderboard:s-1") as com.festivalscoretracker.android.core.nav.SongBandLeaderboardRoute
        assertEquals("Band_Duets", board.bandType)
        assertEquals(null, DebugLaunch.parseRoute("songBandLeaderboard"))
    }
}
