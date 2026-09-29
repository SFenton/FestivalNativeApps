package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility journeys over the player features: Statistics (profile), Leaderboards and
 * Full Rankings, Rivals (hub, detail, rivalry) and Compete. ATF on every screen and
 * interaction; reading orders in logcat `FST_A11Y`
 * (`device.py test com.festivalscoretracker.android.journeys.PlayerAccessibilityJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class PlayerAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val songs: FakeTransport.() -> Unit = {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    @Test
    fun statisticsProfile() {
        h.enableAccessibilityChecks()
        val transport = FakeTransport.standard().apply(songs).also { ProfileFixtures.register(it) }
        h.launch(DebugLaunch(section = FestivalSection.Statistics, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true), transport)
        h.waitForTag("fst.player.available")
        h.readingOrder("statistics")
        h.scrollTo("fst.player.available", "fst.player.top-songs")
        h.readingOrder("statistics-top-songs")
        h.assertAccessible()
    }

    @Test
    fun leaderboardsAndFullRankings() {
        h.enableAccessibilityChecks()
        val transport = RankingsFixtures.install(FakeTransport.standard().apply(songs))
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true), transport)
        h.waitForTag("fst.leaderboards.rank-history")
        h.readingOrder("leaderboards")
        h.scrollTo("fst.leaderboards", "fst.leaderboards.card.Solo_Guitar.view-all")
        h.tap("fst.leaderboards.card.Solo_Guitar.view-all")
        h.waitForTag("fst.full-rankings.pager")
        h.readingOrder("full-rankings")
        h.assertAccessible()
    }

    @Test
    fun rivalsHubDetailAndRivalry() {
        h.enableAccessibilityChecks()
        val transport = RivalsFixtures.transport().apply(songs)
        h.launch(DebugLaunch(route = RivalsRoute, profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true), transport)
        h.waitForTag("fst.rivals.section.common")
        h.readingOrder("rivals")
        h.tap("fst.rivals.row.${RivalsFixtures.RIVALS[1]}")
        h.waitForTag("fst.rival-detail.title")
        h.readingOrder("rival-detail")
        h.tap("fst.rival-detail.see-all.closest_battles")
        h.waitForTag("fst.rivalry.title")
        h.readingOrder("rivalry")
        h.assertAccessible()
    }

    @Test
    fun compete() {
        h.enableAccessibilityChecks()
        val transport = RivalsFixtures.transport().apply(songs).also { RankingsFixtures.install(it) }
        // Compete is a tab only on compact widths; the route works everywhere.
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("compete"), profile = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player"), stillBackground = true), transport)
        h.waitForTag("fst.compete.grid")
        h.readingOrder("compete")
        h.assertAccessible()
    }
}
