package com.festivalscoretracker.android.journeys

import com.festivalscoretracker.android.core.settings.SettingsDetail
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.BuildConfig
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.AppBuildInfo
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
        h.tap("fst.song-band-leaderboard.band-type")
        h.waitForTag("fst.song-band-leaderboard.band-type-menu")
        h.tap("fst.song-band-leaderboard.band-type.Band_Trios")
        h.waitForTag("fst.song-band-leaderboard.song")
        h.assertAccessible()
    }

    @Test
    fun settingsTogglesResetAndLicenses() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport)
        h.waitForTag("fst.settings.list")
        h.readingOrder("settings")
        // App Version: one read-only item with this build's identity, plus " · <sha7>" when the
        // build is stamped (FST_GIT_SHA / -PfstGitSha; issues #43/#151).
        h.openSetting(SettingsDetail.Version.rowTag, "fst.settings.app-version")
        val version = AppBuildInfo.versionText(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE, BuildConfig.GIT_SHA)
        rule.onNodeWithTag("fst.settings.app-version").assertTextEquals("App Version", version)
        val stampedCommit = AppBuildInfo.shortCommit(BuildConfig.GIT_SHA)
        assertEquals(stampedCommit != null, version.endsWith("${AppBuildInfo.COMMIT_SEPARATOR}$stampedCommit"))
        // UiAutomation caches nodes and Compose may not invalidate them after a programmatic scroll; read fresh ones.
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) automation.clearCache()
        runCatching { automation.waitForIdle(500, 5_000) }
        val versionOrder = h.readingOrder("settings-version")
        assertTrue("reading order $versionOrder", versionOrder.any { it.contains(version) })
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

    /**
     * #374: Debug Settings (connected journeys run the Debug build, where the Diagnostics section
     * used to appear) shows neither the Diagnostics section and its Quick Link nor the Tap
     * Diagnostics / Tap Telemetry switches. Release parity is `SettingsPanesTest`.
     */
    @Test
    fun debugSettingsHasNoTapDiagnostics() {
        assertTrue("connected journeys must exercise the Debug build", BuildConfig.DEBUG)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport)
        h.waitForTag("fst.settings.list")
        // Lazy lists answer for every key, composed or not: Diagnostics used to sit at index 1.
        val indexForKey = rule.onNodeWithTag("fst.settings.list").fetchSemanticsNode().config[SemanticsProperties.IndexForKey]
        assertEquals(-1, indexForKey(RETIRED_SECTION))
        assertEquals(1, indexForKey("item-shop"))
        assertTrue(indexForKey("reset") > 0)
        // Walk the list past where the section stood down to Reset, checking each viewport.
        listOf("fst.settings.section.app-settings", "fst.settings.section.item-shop", "fst.settings.reset").forEach { anchor ->
            h.scrollTo("fst.settings.list", anchor)
            assertNoTapDiagnostics()
        }
        val order = h.readingOrder("settings-no-diagnostics")
        assertTrue("reading order $order", order.none { it.contains("Tap Diagnostics") || it.contains("Tap Telemetry") })
        // Quick Links: a sheet on compact windows, a menu on wider ones.
        h.tap("fst.quick-links.open")
        rule.waitUntil(15_000) { h.exists("fst.quick-links.sheet") || h.exists("fst.quick-links.menu") }
        h.waitForTag("fst.quick-links.item.app-settings")
        if (h.exists("fst.quick-links.list")) {
            val linkIndex = rule.onNodeWithTag("fst.quick-links.list").fetchSemanticsNode().config[SemanticsProperties.IndexForKey]
            assertEquals(-1, linkIndex(RETIRED_SECTION))
            h.scrollTo("fst.quick-links.list", "fst.quick-links.item.reset")
        }
        h.waitForTag("fst.quick-links.item.reset")
        assertFalse(h.exists("fst.quick-links.item.$RETIRED_SECTION"))
        h.readingOrder("settings-quick-links-no-diagnostics").let { links ->
            assertTrue("quick links $links", links.none { it.contains("Diagnostics") })
        }
        h.assertAccessible()
    }

    private fun assertNoTapDiagnostics() {
        listOf("fst.settings.section.$RETIRED_SECTION", "fst.settings.tap-diagnostics", "fst.settings.tap-telemetry").forEach {
            assertFalse("$it is still shown", h.exists(it))
        }
        listOf("Tap Diagnostics", "Tap Telemetry", "Diagnostics").forEach {
            assertTrue("\"$it\" is still shown", rule.onAllNodesWithText(it, substring = true, useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
        }
    }

    private companion object {
        /** The retired Debug-only section's Quick Links ID and list key (#374). */
        const val RETIRED_SECTION = "diagnostics"
    }
}
