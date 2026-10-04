package com.festivalscoretracker.android.design

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.service.ServiceIssue
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.ui.common.ServiceStatusInline
import com.festivalscoretracker.android.ui.common.ServiceStatusView
import com.festivalscoretracker.android.ui.common.countdownLabel
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The service status control's reachable states on a real device (issue #140): TalkBack's
 * linear order, the full page's polite live region, inline silence, 48 dp Retry and double
 * text. Run with `device.py test com.festivalscoretracker.android.design.ServiceStatusDeviceTest
 * --avd <AVD>`; reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class ServiceStatusDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    /** A full-page state: id, issue, countdown and the heading TalkBack reads. */
    private data class State(val id: String, val issue: ServiceIssue, val countdown: Int?, val heading: String)

    private val fallback = "Leaderboards unavailable"

    private val states = listOf(
        State("scrape-freeze-countdown", ServiceIssue.ScrapeInProgress(30), 30, "Scores are updating"),
        State("scrape-freeze-retrying", ServiceIssue.ScrapeInProgress(30), 60, "Scores are updating"),
        State("unavailable", ServiceIssue.Unavailable(45), null, fallback),
        State("offline", ServiceIssue.Offline, null, "You're offline"),
        State("syncing", ServiceIssue.Syncing, null, "Still syncing"),
        State("not-found", ServiceIssue.NotFound, null, fallback),
        State("other", ServiceIssue.Other("Something went wrong."), null, fallback),
    )

    @Test
    fun everyFullPageStateReadsHeadingMessageCountdownThenRetry() {
        h.enableAccessibilityChecks()
        var state by mutableStateOf(states.first())
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxSize().background(BrandTokens.appBackground)) {
                    ServiceStatusView(state.issue, fallback, state.countdown, onRetry = {}, modifier = Modifier.safeDrawingPadding())
                }
            }
        }
        states.forEach { s ->
            state = s
            h.waitForTag("fst.service-status.retry")
            val expected = listOfNotNull(s.heading, s.issue.message, s.countdown?.let(::countdownLabel), if (s.countdown != null) "Retry Now" else "Retry")
            // The platform node tree trails Compose state by a debounce; wait for this state's labels.
            rule.waitUntil(5_000) { expected.all { label -> nodes().any { "${it.contentDescription} ${it.text}".contains(label) } } }
            val order = h.readingOrder("service-status-${s.id}")
            assertInOrder(s.id, expected, order)
            rule.onNodeWithTag("fst.service-status.retry").assertHeightIsAtLeast(48.dp).assertWidthIsAtLeast(48.dp)
            assertTrue("${s.id}: full page is a live region", nodes().any { it.liveRegion != 0 })
        }
        h.assertAccessible()
    }

    @Test
    fun inlineRowsAreSilentAndSpeakSeconds() {
        h.enableAccessibilityChecks()
        rule.setContent {
            FestivalTheme {
                Column(
                    Modifier.fillMaxSize().background(BrandTokens.cardBackground).safeDrawingPadding().padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(16.dp),
                ) {
                    ServiceStatusInline(ServiceIssue.ScrapeInProgress(30), "Lead unavailable", 30, onRetry = {}, retryTag = "row.freeze")
                    ServiceStatusInline(ServiceIssue.Offline, "Bass unavailable", null, onRetry = {}, retryTag = "row.offline")
                }
            }
        }
        h.waitForTag("row.offline")
        val order = h.readingOrder("service-status-inline")
        assertInOrder("inline", listOf("Scores are updating", countdownLabel(30), "Retry Now", "You're offline", ServiceIssue.Offline.message, "Retry"), order)
        assertTrue("inline rows never announce", nodes().none { it.liveRegion != 0 })
        rule.onNodeWithTag("row.freeze").assertHeightIsAtLeast(48.dp)
        rule.onNodeWithTag("row.offline").assertHeightIsAtLeast(48.dp)
        h.assertAccessible()
    }

    @Test
    fun doubleTextKeepsEveryPartOnScreen() {
        rule.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(2f)) {
                FestivalTheme {
                    Column(Modifier.fillMaxSize().background(BrandTokens.appBackground).safeDrawingPadding().padding(16.dp)) {
                        ServiceStatusInline(ServiceIssue.ScrapeInProgress(30), "Lead unavailable", 30, onRetry = {}, retryTag = "row.freeze")
                        Box(Modifier.weight(1f)) {
                            ServiceStatusView(ServiceIssue.ScrapeInProgress(30), fallback, 30, onRetry = {})
                        }
                    }
                }
            }
        }
        h.waitForTag("fst.service-status.retry")
        val root = rule.onRoot().getUnclippedBoundsInRoot()
        listOf("row.freeze", "fst.service-status.title", "fst.service-status.countdown", "fst.service-status.retry").forEach { tag ->
            val b = rule.onNodeWithTag(tag).getUnclippedBoundsInRoot()
            assertTrue("$tag fits the width at 200%", b.left >= root.left && b.right <= root.right)
        }
        val inlineText = rule.onAllNodesWithText("Trying again in 0:30")[0].getUnclippedBoundsInRoot()
        val inlineRetry = rule.onNodeWithTag("row.freeze").getUnclippedBoundsInRoot()
        assertTrue("inline Retry stacks under its text at 200%", inlineRetry.top >= inlineText.bottom)
        rule.onNodeWithTag("row.freeze").assertHeightIsAtLeast(48.dp)
        assertEquals(1, nodes().count { it.liveRegion != 0 })
    }

    /**
     * Asserts that [expected] labels appear in [order] in sequence (other nodes may interleave).
     *
     * @param id State id for the message.
     * @param expected Labels in expected order.
     * @param order Reading order from [JourneyHarness.readingOrder].
     */
    private fun assertInOrder(id: String, expected: List<String>, order: List<String>) {
        var from = 0
        expected.forEach { label ->
            val at = (from until order.size).firstOrNull { order[it].contains(label) }
            assertTrue("$id: '$label' after index $from in $order", at != null)
            from = at!! + 1
        }
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
