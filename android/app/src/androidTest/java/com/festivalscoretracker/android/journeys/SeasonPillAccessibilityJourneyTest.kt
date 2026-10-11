package com.festivalscoretracker.android.journeys

import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerHistoryRoute
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The shared season pill on a device (pattern `metadata-pills`, issue #606), on Score History:
 * each row is one TalkBack stop that names its season, and the row from the catalogue's
 * current season (15 in the fixture) reads "Current season 15" — the visual inversion has a
 * spoken equivalent — while an older season reads "Season 9". ATF (contrast, labels, targets)
 * passes at the device's text size and at 200% system text. Run with
 * `device.py test com.festivalscoretracker.android.journeys.SeasonPillAccessibilityJourneyTest --avd …`;
 * reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class SeasonPillAccessibilityJourneyTest {
    @get:Rule(order = 0)
    val fontScale = SystemFontScaleRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
        on("/api/player/${Fixtures.ACCOUNT_A}/history") {
            """{"accountId":"${Fixtures.ACCOUNT_A}","count":2,"history":[
              {"songId":"s-alpha","instrument":"Solo_Guitar","oldScore":700000,"newScore":850000,"oldRank":9,"newRank":4,"accuracy":991200,"isFullCombo":true,"stars":5,"season":15,"scoreAchievedAt":"2024-01-05T00:00:00Z","changedAt":"2024-01-05T00:00:00Z"},
              {"songId":"s-alpha","instrument":"Solo_Guitar","newScore":700000,"newRank":9,"accuracy":954500,"isFullCombo":false,"stars":4,"season":9,"changedAt":"2024-01-01T00:00:00Z"}]}"""
        }
    }

    private fun assertSeasonStops(screen: String) {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, route = PlayerHistoryRoute("s-alpha", "Solo_Guitar"), stillBackground = true), transport)
        h.waitForTag("fst.history.rows")
        h.waitForTag("fst.history.row")
        h.assertNothingStraddles("fst.history.row")
        fun settled(order: List<String>) = order.any { "Current season 15" in it } && order.any { "Season 9" in it && "Current season 9" !in it }
        val deadline = SystemClock.uptimeMillis() + 10_000
        var order = h.readingOrder(screen, fresh = true)
        while (!settled(order) && SystemClock.uptimeMillis() < deadline) {
            Thread.sleep(250)
            order = h.readingOrder(screen, fresh = true)
        }
        assertTrue("$screen: the current-season row reads \"Current season 15\" in $order", order.any { "Current season 15" in it })
        assertTrue("$screen: the old-season row reads \"Season 9\" in $order", order.any { "Season 9" in it && "Current season 9" !in it })
        val current = order.indexOfFirst { "Current season 15" in it }
        val old = order.indexOfFirst { "Season 9" in it }
        assertTrue("$screen: rows read in page order (best score first) in $order", current in 0 until old)
        h.assertAccessible()
    }

    /** Device text size. */
    @Test
    @DeviceCi
    fun historyRowsNameTheirSeasonAndTheCurrentOne() {
        assertSeasonStops("season-pill")
    }

    /** 200% system text: the pills grow with the text and the rows still read their seasons. */
    @Test
    @DeviceCi
    @SystemFontScale(2f)
    fun historyRowsNameTheirSeasonAtDoubleText() {
        assertEquals(2f, rule.activity.resources.configuration.fontScale, 0.01f)
        assertSeasonStops("season-pill-2x")
    }
}
