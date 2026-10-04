package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Bands and Settings device journeys with Accessibility Test Framework checks on every
 * interaction (`device.py test com.festivalscoretracker.android.journeys.BandsSettingsJourneyTest
 * --avd FST_Phone`, and `--avd FST_Book_Fold --posture half`). Each screen logs its TalkBack
 * reading order ([JourneyHarness.readingOrder]).
 */
@RunWith(AndroidJUnit4::class)
class BandsSettingsJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(BandFixtures.PLAYER, "Synthetic Player")
    private val transport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )

    @Test
    fun bandsWithoutAnIdIsAccessibleAndClearOfTheFold() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("bands"), stillBackground = true), transport)
        h.waitForTag("fst.bands.not-found")
        val order = h.readingOrder("bands-not-found")
        val title = order.indexOfFirst { it.contains("Band not found") }
        val message = order.indexOfFirst { it.contains("missing an ID") }
        assertTrue("reading order $order", title >= 0 && message > title)
        h.assertNothingStraddles("fst.bands.not-found.pane")
        assertTrue(transport.requests.none { it.url.contains("/api/bands") || it.url.contains("/rankings/bands") })
        h.assertAccessible()
    }

    @Test
    fun playerBandsToBandDetailAndTheSongBoard() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("playerBands:${BandFixtures.PLAYER}"), profile = player, stillBackground = true), transport)
        h.waitForTag("fst.player-bands.list")
        h.readingOrder("player-bands")
        h.tap("fst.player-bands.row.${BandFixtures.DUO_ID}")
        h.waitForTag("fst.band.members-section")
        h.waitForTag("fst.band.history-chart")
        h.readingOrder("band-detail")
        h.assertNothingStraddles("fst.band.members-section", "fst.band.history-chart", "fst.band.songs-section")
        if (h.exists("fst.quick-links.open")) {
            h.tap("fst.quick-links.open")
            h.tap("fst.quick-links.item.songs")
        }
        h.waitForTag("fst.band.song-row.s-alpha")
        h.tap("fst.band.song-row.s-alpha")
        h.waitForTag("fst.song-detail.list")
        h.scrollTo("fst.song-detail.list", "fst.song-detail.band-view-all.Band_Duets")
        h.tap("fst.song-detail.band-view-all.Band_Duets")
        h.waitForTag("fst.song-band-leaderboard.list")
        h.readingOrder("song-band-leaderboard")
        h.tap("fst.song-band-leaderboard.band-type.Band_Trios")
        h.waitForTag("fst.song-band-leaderboard.subtitle")
        h.assertAccessible()
    }

    @Test
    fun settingsTogglesResetAndLicenses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport)
        h.waitForTag("fst.settings.list")
        h.readingOrder("settings")
        h.scrollTo("fst.settings.list", "fst.settings.reset")
        h.tap("fst.settings.reset")
        h.waitForTag("fst.settings.reset.dialog")
        h.readingOrder("settings-reset-dialog")
        h.tap("fst.settings.reset.cancel")
        h.waitGone("fst.settings.reset.dialog")
        h.scrollTo("fst.settings.list", "fst.settings.licenses")
        h.tap("fst.settings.licenses")
        h.waitForTag("fst.licenses.list")
        h.readingOrder("licenses")
        assertTrue(h.exists("fst.licenses.list"))
        h.assertAccessible()
    }
}
