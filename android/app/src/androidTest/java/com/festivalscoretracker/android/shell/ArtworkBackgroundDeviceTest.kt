package com.festivalscoretracker.android.shell

import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.platform.ViewRootForTest
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.background.ARTWORK_BACKGROUND_TAG
import com.festivalscoretracker.android.ui.background.ArtworkBackgroundStateKey
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The shared album-art backdrop on a real device (issue #124):
 * `device.py test com.festivalscoretracker.android.shell.ArtworkBackgroundDeviceTest --avd …`.
 * Follows the system animator scale and Data Saver live (no restart), pauses while the
 * activity is not resumed, and never reaches TalkBack. Covers point at `art.invalid`, so no
 * image is fetched; the state machine does not depend on a cover loading.
 */
@RunWith(AndroidJUnit4::class)
class ArtworkBackgroundDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.songsJson.replace("\"alpha-512.jpg\"", "\"https://art.invalid/alpha.jpg\"")
        }
    }
    private var animatorScale = "1"
    private var restrictBackground = false

    private fun shell(command: String): String {
        val pfd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes().decodeToString().trim() }
    }

    @Before
    fun saveSystemSettings() {
        animatorScale = shell("settings get global animator_duration_scale").takeIf { it != "null" && it.isNotEmpty() } ?: "1"
        restrictBackground = shell("cmd netpolicy get restrict-background").contains("enabled")
        shell("settings put global animator_duration_scale 1")
        shell("cmd netpolicy set restrict-background false")
    }

    @After
    fun restoreSystemSettings() {
        shell("settings put global animator_duration_scale $animatorScale")
        shell("cmd netpolicy set restrict-background $restrictBackground")
    }

    private fun state(): String = rule.onNodeWithTag(ARTWORK_BACKGROUND_TAG, useUnmergedTree = true).fetchSemanticsNode().config[ArtworkBackgroundStateKey]

    private fun waitForState(expected: String) = rule.waitUntil(10_000) { runCatching { state() }.getOrNull() == expected }

    /**
     * The state read straight from the activity's Compose root: while another activity covers
     * this one the test rule finds no hierarchy, but the paused composition still updates.
     */
    private fun rootState(): String? {
        var found: String? = null
        InstrumentationRegistry.getInstrumentation().runOnMainSync {
            fun view(v: View): ViewRootForTest? = v as? ViewRootForTest ?: (v as? ViewGroup)?.let { g -> (0 until g.childCount).firstNotNullOfOrNull { view(g.getChildAt(it)) } }
            fun node(n: SemanticsNode): SemanticsNode? =
                if (n.config.getOrNull(SemanticsProperties.TestTag) == ARTWORK_BACKGROUND_TAG) n else n.children.firstNotNullOfOrNull(::node)
            val root = view(rule.activity.window.decorView) ?: return@runOnMainSync
            found = node(root.semanticsOwner.unmergedRootSemanticsNode)?.config?.getOrNull(ArtworkBackgroundStateKey)
        }
        return found
    }

    private fun lifecycleOf(): String {
        var state = "?"
        InstrumentationRegistry.getInstrumentation().runOnMainSync { state = rule.activity.lifecycle.currentState.name }
        return state
    }

    private fun waitForRootState(expected: String) {
        val deadline = SystemClock.uptimeMillis() + 10_000
        while (rootState() != expected) {
            assertTrue("backdrop never reached $expected (was ${rootState()}, activity ${lifecycleOf()})", SystemClock.uptimeMillis() < deadline)
            // Recomposition runs on the test's frame clock, which only the rule advances.
            rule.mainClock.advanceTimeBy(100)
            SystemClock.sleep(100)
        }
    }

    /** No node TalkBack can reach carries the backdrop's resource ID, label or role. */
    private fun assertHiddenFromTalkBack() {
        val root = InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow ?: return
        val found = mutableListOf<AccessibilityNodeInfo>()
        fun walk(node: AccessibilityNodeInfo) {
            if (node.viewIdResourceName?.endsWith(ARTWORK_BACKGROUND_TAG) == true) found += node
            for (i in 0 until node.childCount) node.getChild(i)?.let(::walk)
        }
        walk(root)
        found.forEach { node ->
            assertTrue("backdrop is focusable", !node.isFocusable && !node.isScreenReaderFocusable && !node.isClickable)
            assertTrue("backdrop has a label", node.text.isNullOrEmpty() && node.contentDescription.isNullOrEmpty())
            assertTrue("backdrop has children", node.childCount == 0)
        }
    }

    @Test
    fun followsAnimatorScaleDataSaverAndVisibilityLive() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings), transport)
        h.waitForTag(ARTWORK_BACKGROUND_TAG)
        waitForState("animated")
        val order = h.readingOrder("artwork-background-settings")
        assertTrue(order.none { it.contains("artwork", ignoreCase = true) })
        assertHiddenFromTalkBack()

        shell("settings put global animator_duration_scale 0")
        waitForState("reduced-motion")
        shell("settings put global animator_duration_scale 1")
        waitForState("animated")

        shell("cmd netpolicy set restrict-background true")
        waitForState("save-data")
        assertHiddenFromTalkBack()
        shell("cmd netpolicy set restrict-background false")
        waitForState("animated")

        rule.activityRule.scenario.moveToState(Lifecycle.State.STARTED)
        waitForRootState("not-visible")
        rule.activityRule.scenario.moveToState(Lifecycle.State.RESUMED)
        waitForState("animated")
        h.assertAccessible()
    }
}
