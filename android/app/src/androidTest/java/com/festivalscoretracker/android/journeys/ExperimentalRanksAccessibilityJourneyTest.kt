package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.state.ToggleableState
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.RankingsFixtures
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Settings → Enable Experimental Leaderboard Ranks and the Rank By control it gates (#541,
 * `experimental-ranks` R1), with the Accessibility Test Framework on every interaction:
 *
 * - The setting is one enabled TalkBack switch, off by default, at least 48 dp, that reads its
 *   title and turns on (and saves) at font scale 1.0 and 2.0.
 * - Off: Leaderboards has no Rank By, and TalkBack reads none.
 * - On: Rank By is a readable, full-size control that speaks "Rank By, Total Score".
 *
 * Run with `device.py test com.festivalscoretracker.android.journeys.ExperimentalRanksAccessibilityJourneyTest --avd <AVD>`;
 * reading orders go to logcat `FST_A11Y`. `@DeviceCi`: both CI device checks run it.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class ExperimentalRanksAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player")
    private val key = booleanPreferencesKey(SettingsRegistry.EXPERIMENTAL_RANKS)

    // region Tests

    @Test
    fun settingIsAnEnabledSwitchThatTurnsOnAtEveryTextSize() {
        val preferences = MemoryPreferences()
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), FakeTransport.standard(), preferences, fontScale = { scale })
        h.waitForTag("fst.settings.list")
        listOf(1f, 2f).forEach { s ->
            scale = s
            rule.waitForIdle()
            h.scrollTo("fst.settings.list", TAG)
            val node = rule.onNodeWithTag(TAG).fetchSemanticsNode()
            assertEquals("fs $s: switch role", Role.Switch, node.config[SemanticsProperties.Role])
            val expected = if (s == 1f) ToggleableState.Off else ToggleableState.On
            assertEquals("fs $s: state", expected, node.config[SemanticsProperties.ToggleableState])
            val a11y = accessibilityNode(TAG)
            assertNotNull("fs $s: setting is in the accessibility tree", a11y)
            assertTrue("fs $s: setting is enabled", a11y!!.isEnabled)
            assertTrue("fs $s: setting is checkable", a11y.isCheckable)
            val box = android.graphics.Rect().also(a11y::getBoundsInScreen)
            assertTrue("fs $s: ${box.height()} px under 48 dp", box.height() >= with(rule.density) { 48.dp.toPx() } - 1)
            val order = h.readingOrder("settings-experimental-ranks fs $s", fresh = true)
            assertEquals("fs $s: one stop names the setting ($order)", 1, order.count { it.contains(TITLE) })
            if (s == 1f) {
                h.tap(TAG)
                rule.waitUntil(5_000) { runBlocking { preferences.data.first()[key] } == true }
            }
        }
        h.assertAccessible()
    }

    @Test
    fun rankByIsHiddenWhileTheSettingIsOff() {
        h.enableAccessibilityChecks()
        launchLeaderboards(experimentalRanks = false)
        val order = h.readingOrder("leaderboards-experimental-off", fresh = true)
        assertFalse("Rank By offered with Experimental Ranks off", h.exists(RANK_BY))
        assertTrue("TalkBack reads Rank By with Experimental Ranks off: $order", order.none { it.startsWith("Rank By") })
        h.assertAccessible()
    }

    @Test
    fun rankByIsAFullSizeControlWhileTheSettingIsOn() {
        h.enableAccessibilityChecks()
        launchLeaderboards(experimentalRanks = true)
        val node = accessibilityNode(RANK_BY)
        assertNotNull("Rank By missing with Experimental Ranks on", node)
        assertEquals("Rank By, Total Score", node!!.contentDescription?.toString())
        val box = android.graphics.Rect().also(node::getBoundsInScreen)
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("Rank By is ${box.width()}×${box.height()} px, under 48 dp", box.width() >= min && box.height() >= min)
        h.readingOrder("leaderboards-experimental-on", fresh = true)
        h.tap(RANK_BY)
        h.waitForTag("$RANK_BY_ITEM.adjusted")
        h.readingOrder("leaderboards-rank-by-menu")
        h.assertAccessible()
    }

    // endregion

    // region Helpers

    private fun launchLeaderboards(experimentalRanks: Boolean) {
        val preferences = MemoryPreferences(mutablePreferencesOf(key to experimentalRanks))
        val transport = RankingsFixtures.install(FakeTransport.standard())
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = player, stillBackground = true), transport, preferences)
        h.waitForTag("fst.leaderboards.rank-history")
        h.waitGone("fst.leaderboards.loading")
        h.awaitAccessibilityTree(present = "fst.leaderboards.rank-history", absent = "fst.leaderboards.loading")
    }

    /**
     * The visible accessibility node exposing [tag] as its resource id.
     *
     * @param tag Test tag.
     * @return The node, or `null`.
     */
    private fun accessibilityNode(tag: String): AccessibilityNodeInfo? {
        rule.waitForIdle()
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        fun find(n: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            n ?: return null
            if (n.viewIdResourceName == tag && n.isVisibleToUser) return n
            for (i in 0 until n.childCount) find(n.getChild(i))?.let { return it }
            return null
        }
        return find(automation.rootInActiveWindow)
    }

    // endregion

    private companion object {
        const val TAG = "fst.settings.experimental-ranks"
        const val TITLE = "Enable Experimental Leaderboard Ranks"
        const val RANK_BY = "fst.rankings.rank-by-menu"
        const val RANK_BY_ITEM = "fst.rankings.rank-by"
    }
}
