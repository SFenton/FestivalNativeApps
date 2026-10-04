package com.festivalscoretracker.android.design

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.journeys.MemoryPreferences
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.design.DifficultyMeter
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The difficulty meter's eight states on a real device (issue #123): what TalkBack's linear
 * order reads, the platform class it sees, Accessibility Test Framework checks, double text
 * and the Songs filter's intensity switches. Run with `device.py test
 * com.festivalscoretracker.android.design.DifficultyMeterDeviceTest --avd <AVD>`; reading orders
 * go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class DifficultyMeterDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val expected = (1..7).map { "Difficulty $it of 7" } + "Difficulty unavailable"

    @Test
    fun everyStateIsOneLabelledImageInOrder() {
        h.enableAccessibilityChecks()
        rule.setContent {
            FestivalTheme {
                Column(Modifier.fillMaxSize().background(BrandTokens.cardBackground).safeDrawingPadding().padding(16.dp)) {
                    (0..6).forEach { DifficultyMeter(it.toDouble(), Modifier.padding(vertical = 8.dp)) }
                    DifficultyMeter(Double.NaN, Modifier.padding(vertical = 8.dp))
                }
            }
        }
        h.waitForTag("fst.songs.difficulty-unavailable")
        assertEquals(expected, h.readingOrder("difficulty-meter"))
        (1..7).forEach { level ->
            val node = nodes().single { it.contentDescription?.toString() == "Difficulty $level of 7" }
            assertEquals("android.widget.ImageView", node.className?.toString())
            assertFalse(node.isClickable)
        }
        h.assertAccessible()
    }

    @Test
    fun doubleTextKeepsTheMeterAndWrapsUnavailable() {
        rule.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(2f)) {
                FestivalTheme {
                    Column(Modifier.fillMaxSize().background(BrandTokens.cardBackground).safeDrawingPadding().padding(16.dp)) {
                        DifficultyMeter(4.0)
                        Column(Modifier.width(96.dp)) { DifficultyMeter(Double.NaN) }
                    }
                }
            }
        }
        h.waitForTag("fst.songs.difficulty-unavailable")
        rule.onNodeWithTag("fst.songs.difficulty-meter").assertWidthIsEqualTo(62.dp).assertHeightIsEqualTo(20.dp)
        val layouts = mutableListOf<TextLayoutResult>()
        rule.onNodeWithTag("fst.songs.difficulty-unavailable").performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        assertTrue(layouts.single().lineCount > 1)
        assertFalse(layouts.single().hasVisualOverflow)
    }

    @Test
    fun songIntensityFilterSwitchesReadTheirLevelOnce() {
        h.enableAccessibilityChecks()
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
            ProfileFixtures.register(this)
        }
        // A saved hidden "No Score" intensity bucket opens the Song Intensity group.
        val preferences = MemoryPreferences(
            mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_FILTERS) to """{"instrument":"Solo_Guitar","excludedIntensities":[0]}"""),
        )
        h.launch(DebugLaunch(profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true), transport, preferences)
        h.waitForTag("fst.songs.list")
        h.tap("fst.songs.filter.open")
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.intensity.7")
        val order = h.readingOrder("songs-filter-intensity")
        (1..7).forEach { assertTrue(order.toString(), "Intensity $it of 7, On" in order) }
        assertTrue(order.toString(), "No Score, Off" in order)
        assertFalse(order.toString(), order.any { it.contains("Difficulty") })
        h.assertAccessible()
    }

    /** Every visible node of the active window, depth-first. */
    private fun nodes(): List<AccessibilityNodeInfo> {
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo) {
            if (!n.isVisibleToUser) return
            out += n
            for (i in 0 until n.childCount) n.getChild(i)?.let(::walk)
        }
        InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow?.let(::walk)
        return out
    }
}