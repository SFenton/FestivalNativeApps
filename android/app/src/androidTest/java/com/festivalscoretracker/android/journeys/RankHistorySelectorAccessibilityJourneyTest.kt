package com.festivalscoretracker.android.journeys

import android.view.KeyEvent
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.assertIsFocused
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.requestFocus
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Leaderboards Rank History uses the shared Instrument Selector (issue #592, web `GraphCard`):
 * every chart is a 64 dp radio button named by its chart in one group (compact ‹ chart ›
 * arrows with 48 dp targets when the row does not fit), TalkBack reads the arrows around the
 * chart, a hardware keyboard moves the selection, and ATF passes at 100% and 200% text
 * (`device.py test com.festivalscoretracker.android.journeys.RankHistorySelectorAccessibilityJourneyTest --avd …`).
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class RankHistorySelectorAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val tag = "fst.leaderboards.rank-history.picker"

    /** The selected chart's label as the selector exposes it. */
    private fun selectedLabel(): String? {
        val charts = listOf("$tag.preview") + Instrument.entries.map { "$tag.${it.wireId}" }
        return charts.filter(h::exists).map { rule.onNodeWithTag(it).fetchSemanticsNode().config }
            .firstOrNull { it.getOrNull(SemanticsProperties.Selected) == true }
            ?.get(SemanticsProperties.ContentDescription)?.single()
    }

    /** Asserts every rendered chart is a 64 dp radio button and the arrows (if any) are 48 dp targets. */
    private fun assertSelectorGeometry(screen: String) {
        val side = with(rule.density) { 64.dp.toPx() }
        val charts = (listOf("$tag.preview") + Instrument.entries.map { "$tag.${it.wireId}" }).filter(h::exists)
        assertTrue("$screen: no selector charts", charts.isNotEmpty())
        charts.forEach { chart ->
            val node = rule.onNodeWithTag(chart).fetchSemanticsNode()
            assertEquals("$screen: $chart width", side, node.size.width.toFloat(), 1.5f)
            assertEquals("$screen: $chart height", side, node.size.height.toFloat(), 1.5f)
            val platform = checkNotNull(h.accessibilityNode(chart)) { "$screen: $chart in the accessibility tree" }
            // Compose exposes the role's legacy class on an unmerged child of the focusable circle.
            fun classes(n: android.view.accessibility.AccessibilityNodeInfo): List<String> =
                listOfNotNull(n.className?.toString()) + (0 until n.childCount).flatMap { i -> n.getChild(i)?.let(::classes).orEmpty() }
            val subtree = classes(platform)
            assertTrue("$screen: $chart is checkable", platform.isCheckable)
            assertEquals("$screen: $chart radio roles in $subtree", 1, subtree.count { it == "android.widget.RadioButton" })
            assertTrue("$screen: $chart is no checkbox in $subtree", "android.widget.CheckBox" !in subtree)
            h.assertTouchTarget(screen, chart)
        }
        if (h.exists("$tag.compact")) {
            h.assertTouchTarget(screen, "$tag.previous")
            h.assertTouchTarget(screen, "$tag.next")
        }
    }

    /**
     * Activates [target] from a hardware keyboard: a real Tab leaves touch mode (Compose clickables
     * take focus only outside it), focus moves to [target], then a real Enter presses it.
     */
    private fun pressEnterOn(target: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_TAB)
        rule.waitForIdle()
        rule.onNodeWithTag(target).requestFocus().assertIsFocused()
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_ENTER)
        rule.waitForIdle()
    }

    @Test
    fun rankHistoryUsesTheSharedSelectorWithRadioRolesKeyboardAndLargeText() {
        h.enableAccessibilityChecks()
        var scale by mutableFloatStateOf(1f)
        val transport = RankingsFixtures.install(
            FakeTransport.standard().apply {
                on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            },
        )
        h.launch(
            DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true),
            transport,
            fontScale = { scale },
        )
        h.waitForTag(tag)
        h.scrollTo("fst.leaderboards", tag)
        assertEquals("Lead", selectedLabel())
        assertSelectorGeometry("rank-history")
        val stops = h.readingStops("leaderboards-rank-history")
        val order = stops.map { "${it.id}: ${it.label}" }
        if (h.exists("$tag.compact")) {
            // Compact: TalkBack reads Previous, the chart, then Next.
            val previous = stops.indexOfFirst { it.id == "$tag.previous" && it.label.startsWith("Previous instrument") }
            val chart = stops.indexOfFirst { it.id == "$tag.preview" && it.label.startsWith("Lead") }
            val next = stops.indexOfFirst { it.id == "$tag.next" && it.label.startsWith("Next instrument") }
            assertTrue("compact selector order in $order", previous in 0 until chart && chart < next)
            // A hardware keyboard activates the focused arrow (Enter), moving to the next chart.
            pressEnterOn("$tag.next")
        } else {
            // Full row: the charts read in their Settings order.
            val lead = stops.indexOfFirst { it.id == "$tag.${Instrument.Lead.wireId}" && it.label.startsWith("Lead") }
            val bass = stops.indexOfFirst { it.id == "$tag.${Instrument.Bass.wireId}" && it.label.startsWith("Bass") }
            assertTrue("full selector order in $order", lead in 0 until bass)
            pressEnterOn("$tag.${Instrument.Bass.wireId}")
        }
        rule.waitUntil(5_000) { selectedLabel() == "Bass" }
        // 200% text: the circles keep the web geometry and nothing clips.
        scale = 2f
        rule.waitForIdle()
        h.scrollTo("fst.leaderboards", tag)
        assertSelectorGeometry("rank-history-200")
        h.readingOrder("leaderboards-rank-history-200", fresh = true)
        h.assertAccessible()
    }
}
