package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.PathDisplayMode
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Settings › CHOpt Path Default View on a real device (issue #164): ATF over the inline radio
 * group, what the platform accessibility tree hands TalkBack (radio-button class, checked state,
 * heading), the options clear of a separating hinge, and the saved choice opening the Paths
 * sheet. Run with `device.py test com.festivalscoretracker.android.journeys.PathDefaultViewDeviceTest
 * --avd <AVD> [--posture half]`; reading orders log under `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class PathDefaultViewDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
        onRaw("/api/paths/s-alpha/Solo_Guitar/expert") { HttpResult(200, SongsFixtures.png(), mapOf("X-FST-Publication-Id" to "7")) }
    }

    /** Karaoke hidden: the Paths sheet opens without its warning. */
    private val preferences = MemoryPreferences(mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.VISIBLE_INSTRUMENTS) to "Solo_Guitar,Solo_Bass"))

    private fun saved(): PathDisplayMode = runBlocking { SettingsRepository.decode(preferences.data.first()).pathDefaultView }

    /** The node TalkBack reads for [tag] (test tags are exposed as resource ids). */
    private fun accessibilityNode(tag: String): AccessibilityNodeInfo? {
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            node ?: return null
            if (node.viewIdResourceName == tag) return node
            for (i in 0 until node.childCount) find(node.getChild(i))?.let { return it }
            return null
        }
        return find(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow)
    }

    private fun assertRadio(tag: String, checked: Boolean) {
        rule.waitUntil(15_000) { accessibilityNode(tag)?.isChecked == checked }
        val node = checkNotNull(accessibilityNode(tag)) { "$tag in the accessibility tree" }
        assertEquals("android.widget.RadioButton", node.className?.toString())
        assertTrue("$tag is checkable", node.isCheckable)
        assertEquals(checked, node.isChecked)
    }

    @Test
    fun inlineGroupIsAccessibleAndSavesWithoutLeavingSettings() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport, preferences)
        h.scrollTo("fst.settings.list", "fst.settings.path-default-view.text")
        h.awaitAccessibilityTree("fst.settings.path-default-view.text")
        val order = h.readingOrder("settings-path-default-view")
        val heading = order.indexOfFirst { it == "CHOpt Path Default View" }
        val image = order.indexOfFirst { it.startsWith("Image") }
        val text = order.indexOfFirst { it.startsWith("Text") }
        assertTrue("reading order $order", heading >= 0 && image > heading && text > image)
        assertRadio("fst.settings.path-default-view.image", checked = true)
        assertRadio("fst.settings.path-default-view.text", checked = false)
        h.assertNothingStraddles("fst.settings.path-default-view.image", "fst.settings.path-default-view.text")

        h.tap("fst.settings.path-default-view.text")
        assertRadio("fst.settings.path-default-view.text", checked = true)
        assertRadio("fst.settings.path-default-view.image", checked = false)
        assertTrue("stays on Settings", h.exists("fst.settings.list"))
        assertEquals(PathDisplayMode.Text, saved())
        h.readingOrder("settings-path-default-view-text")
        h.assertAccessible()
    }

    @Test
    fun savedTextDefaultOpensEveryPathsSheetAsTheTable() {
        h.enableAccessibilityChecks()
        runBlocking {
            preferences.updateData { it.toMutablePreferences().apply { this[stringPreferencesKey(SettingsRegistry.PATH_DEFAULT_VIEW)] = PathDisplayMode.Text.token } }
        }
        h.launch(DebugLaunch(songQuery = "s-alpha", stillBackground = true), transport, preferences)
        h.waitForTag("fst.song-detail.paths.open")
        h.tap("fst.song-detail.paths.open")
        h.waitForTag("fst.paths.row.1")
        assertTrue("no image in Text default", !h.exists("fst.paths.image"))
        h.readingOrder("paths-text-default")
        // A switch to Image lasts for this opening only.
        h.tap("fst.paths.display.open")
        h.tap("fst.paths.display.image")
        h.waitForTag("fst.paths.image")
        h.tap("fst.paths.close")
        h.waitGone("fst.paths.close")
        h.tap("fst.song-detail.paths.open")
        h.waitForTag("fst.paths.row.1")
        assertTrue("reopened in Text", !h.exists("fst.paths.image"))
        h.assertAccessible()
    }
}
