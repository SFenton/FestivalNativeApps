package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import kotlinx.coroutines.CompletableDeferred
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Song Details page tools wait for the load gate on a real device (issue #585, patterns
 * `load-transition` and `page-tools-and-nav-chrome`). The chart previews are held open, so
 * the page shows the shared spinner:
 *
 * - While it loads, neither the screen nor TalkBack has View Paths, Quick Links or the Item
 *   Shop action.
 * - Once the previews settle, View Paths appears with the page: a labelled button TalkBack
 *   reads next to Quick Links, both with 48 dp touch targets, and the Item Shop action is in
 *   the page.
 *
 * Runs at 100% and 200% text; ATF checks every interaction. Run with `device.py test
 * com.festivalscoretracker.android.journeys.SongDetailPageToolsAccessibilityJourneyTest --avd <AVD>`;
 * reading orders go to logcat `FST_A11Y`. `@DeviceCi`: CI's `android-device` check runs it.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class SongDetailPageToolsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val previews = CompletableDeferred<Unit>()
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        beforeRespond = { request -> if ("/api/leaderboard/" in request.url) previews.await() }
    }

    /** Two charts keep the page short; Lead has a path. */
    private val preferences
        get() = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_Drums"))

    @Test
    fun pageToolsWaitForTheLoadGate() = journey(1f)

    @Test
    fun pageToolsWaitForTheLoadGateAtLargeText() = journey(2f)

    private fun journey(scale: Float) {
        val config = "fs $scale"
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true), transport, preferences, fontScale = { scale })
        h.waitForTag(SPINNER)
        h.publishTalkBackTree()
        h.awaitAccessibilityTree(SPINNER, absent = PATHS)
        listOf(PATHS, QUICK_LINKS, SHOP).forEach { assertFalse("$config: $it shows while the page loads", h.exists(it)) }
        val loading = h.readingOrder("song-detail-tools-loading $config")
        assertFalse("$config: TalkBack reads View Paths while the page loads: $loading", loading.any { it.startsWith(PATHS_LABEL) })
        assertFalse("$config: TalkBack reads Quick Links while the page loads: $loading", loading.any { it.startsWith(QUICK_LINKS_LABEL) })

        previews.complete(Unit)
        h.waitForTag(PATHS)
        h.awaitAccessibilityTree(PATHS, absent = SPINNER)
        h.waitForTag(QUICK_LINKS)
        h.waitForTag(SHOP)
        val stops = h.readingStops("song-detail-tools-loaded $config", fresh = true)
        val paths = stops.indexOfFirst { it.id == PATHS }
        val links = stops.indexOfFirst { it.id == QUICK_LINKS }
        assertTrue("$config: TalkBack reads View Paths: ${stops.map { it.label }}", paths >= 0)
        assertEquals("$config: View Paths label", PATHS_LABEL, stops[paths].label)
        assertTrue("$config: View Paths is a button", stops[paths].isClickable)
        assertEquals("$config: Quick Links follows View Paths: ${stops.map { it.label }}", paths + 1, links)
        assertTrue("$config: Quick Links label", stops[links].label.startsWith(QUICK_LINKS_LABEL))
        h.assertTouchTarget(config, PATHS)
        h.assertTouchTarget(config, QUICK_LINKS)
        h.assertAccessible()
    }

    private companion object {
        const val SPINNER = "fst.load-gate.spinner"
        const val PATHS = "fst.song-detail.paths.open"
        const val QUICK_LINKS = "fst.quick-links.open"
        const val SHOP = "fst.song-detail.shop"
        const val PATHS_LABEL = "View Paths"
        const val QUICK_LINKS_LABEL = "Quick Links"
    }
}
