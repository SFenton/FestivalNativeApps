package com.festivalscoretracker.android.journeys

import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.text.TextLayoutResult
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.serviceinfo.ServiceInfoText
import com.festivalscoretracker.android.testing.FakeTransport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Settings → Service Info on a real device (issue #184), against deterministic
 * `/api/service-info` fixtures: a determinate registered-band discovery phase and an
 * indeterminate rivals phase. At font scale 1.0 and 2.0 the journey scrolls to the card and
 * checks the state row follows the `settings-value-row` fit rule with the device's own font
 * metrics (inline only when "Leaderboard Service State" fits beside "Updating" and its spinner,
 * otherwise stacked under the description, never a squeezed title), the phase row's progress
 * semantics (determinate range or indeterminate, exposed as `android.widget.ProgressBar`) and
 * TalkBack's reading order (heading → hint → state → phase → last publication), with the
 * Accessibility Test Framework on every interaction. Run with `device.py test
 * com.festivalscoretracker.android.journeys.ServiceInfoJourneyTest --avd <AVD>`; reading orders
 * go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
class ServiceInfoJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val published = """"lastCompletedUpdate":{"publishedAt":"2026-09-28T17:00:00Z"}"""

    /** Registered-band discovery with phase-level units and attempt progress (24.8%). */
    private val determinate = """{"contractVersion":2,$published,"workerStatus":{"status":"online"},"currentUpdate":{
        "status":"updating","scrapeId":2,"operationId":"op","phaseId":"${ServiceInfoText.REGISTERED_BAND_DISCOVERY_PHASE_ID}",
        "phaseOrdinal":5,"phaseAttempt":1,"unitsKind":"accounts","unitsCompleted":1240,"unitsTotal":5000,"unitsTotalFinal":true,
        "phasePercent":24.8,"attemptProgress":{"schemaVersion":1,"attemptedThisPass":1310,"retryableUnavailableThisPass":70}}}"""

    /** Rivals post-processing with no total: an indeterminate bar. */
    private val indeterminate = """{"contractVersion":2,$published,"workerStatus":{"status":"online"},"currentUpdate":{
        "status":"updating","scrapeId":1,"phaseId":"post_rivals","subphaseId":"per_song_rivals"}}"""

    private val scales = listOf(1f, 2f)

    @Test
    fun determinatePhaseFitsReadsInOrderAndIsAProgressBar() = journey(determinate, "Registered Player Band Discovery") { phase ->
        phase.assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo(0.248f, 0f..1f)))
        val node = accessibilityNode("fst.settings.service-info.phase")
        assertEquals("android.widget.ProgressBar", node?.className?.toString())
        assertEquals(0.248f, node?.rangeInfo?.current ?: -1f, 0.001f)
        assertTrue(h.exists("fst.settings.service-info.attempt"))
    }

    @Test
    fun indeterminatePhaseFitsReadsInOrderAndIsAProgressBar() = journey(indeterminate, "Computing Player Rivals · Calculating Player Rivals") { phase ->
        phase.assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
        phase.assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, ServiceInfoText.PROGRESS_INDETERMINATE))
        assertEquals("android.widget.ProgressBar", accessibilityNode("fst.settings.service-info.phase")?.className?.toString())
        assertTrue(!h.exists("fst.settings.service-info.attempt"))
    }

    /**
     * Launches Settings on [body], then at each font scale reaches the card and runs the shared
     * layout and reading-order checks plus [progress].
     *
     * @param body `/api/service-info` fixture.
     * @param phaseTitle The phase row's visible title.
     * @param progress State-specific progress checks on the phase row.
     */
    private fun journey(body: String, phaseTitle: String, progress: (SemanticsNodeInteraction) -> Unit) {
        val transport = FakeTransport.standard().apply { on("/api/service-info") { body } }
        var scale by mutableFloatStateOf(scales.first())
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Settings, stillBackground = true), transport, fontScale = { scale })
        h.waitForTag("fst.settings.list")
        scales.forEach { s ->
            scale = s
            rule.waitForIdle()
            h.scrollTo("fst.settings.list", "fst.settings.service-info")
            h.waitForTag("fst.settings.service-info.phase")
            h.waitForTag("fst.settings.service-info.last-published")
            assertStateRowFits("fs $s", s)
            progress(rule.onNodeWithTag("fst.settings.service-info.phase"))
            assertReadingOrder("fs $s", phaseTitle)
        }
        assertTrue(transport.sent("/api/service-info").isNotEmpty())
        h.assertAccessible()
    }

    // region Layout

    /**
     * The state row obeys `settings-value-row` R1 with this device's fonts: inline exactly when
     * the title's natural one-line width, the 12 dp gap and the value fit the row; inline keeps
     * the title on one line, stacked puts the value 4 dp under the description at the start.
     *
     * @param config Configuration name for messages.
     * @param scale Font scale the app renders at.
     */
    private fun assertStateRowFits(config: String, scale: Float) {
        rule.onNodeWithTag("fst.settings.service-info.state").performScrollTo()
        rule.waitForIdle()
        val row = bounds(hasTestTag("fst.settings.service-info.state"))
        val inState = hasAnyAncestor(hasTestTag("fst.settings.service-info.state"))
        val titleMatcher = hasText(ServiceInfoText.SERVICE_STATE_TITLE) and inState
        val title = bounds(titleMatcher)
        val texts = rule.onNodeWithTag("fst.settings.service-info.state").fetchSemanticsNode().config[SemanticsProperties.Text].map { it.text }
        assertEquals("$config: state row reads title, description, process ($texts)", 3, texts.size)
        val description = bounds(hasText(texts[1]) and inState)
        val value = bounds(hasTestTag("fst.settings.service-info.state.value"))
        val layout = textLayout(titleMatcher)
        val px = rule.density.density
        val natural = layout.multiParagraph.intrinsics.maxIntrinsicWidth
        val expectInline = natural + 12 * px + value.width <= row.width
        val inline = value.top < title.bottom && value.left > title.left
        val windowDp = rule.activity.resources.configuration.screenWidthDp
        android.util.Log.i(JourneyHarness.READING_ORDER_TAG, "service-info $config | window ${windowDp}dp row ${row.width / px}dp title ${natural / px}dp value ${value.width / px}dp inline $inline")
        // Skip the 1 px rounding band where the two measurements may disagree.
        if (kotlin.math.abs(natural + 12 * px + value.width - row.width) > 1f) {
            assertEquals("$config: inline when the title fits beside the value (row ${row.width}, title $natural, value ${value.width})", expectInline, inline)
        }
        if (inline) {
            assertEquals("$config: an inline title stays on one line", 1, layout.lineCount)
            assertTrue("$config: value after the title with the gap", value.left >= title.right + 12 * px - 1)
            assertEquals("$config: value at the row's end", row.right, value.right, 1f)
        } else {
            assertTrue("$config: stacked value under the description", value.top >= description.bottom + 4 * px - 1)
            assertEquals("$config: stacked value at the start", row.left, value.left, 1f)
        }
        // Large text on a compact window has no room beside the title; an expanded column does.
        if (scale >= 2f && windowDp < 600) assertTrue("$config: stacks on a compact window", !inline)
    }

    /**
     * Bounds in the root of the single unmerged node matching [matcher].
     *
     * @param matcher Node matcher.
     * @return Bounds in px.
     */
    private fun bounds(matcher: SemanticsMatcher): Rect =
        rule.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInRoot

    /**
     * Text layout of the unmerged text node matching [matcher].
     *
     * @param matcher Node matcher.
     * @return Its laid-out text.
     */
    private fun textLayout(matcher: SemanticsMatcher): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        val node = rule.onAllNodes(matcher, useUnmergedTree = true).fetchSemanticsNodes().first()
        node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(results)
        return results.single()
    }

    // endregion

    // region Accessibility

    /**
     * TalkBack meets the card's items in web order. A tall card at 2.0 may not fit the window,
     * so the order is read three times (with the heading, the state row and then the last
     * publication on screen); each dump must keep the visible items in order, and together they
     * must cover all five.
     *
     * @param config Configuration name for messages.
     * @param phaseTitle Phase row title.
     */
    private fun assertReadingOrder(config: String, phaseTitle: String) {
        val expected = listOf<(String) -> Boolean>(
            { it == ServiceInfoText.TITLE },
            { it == ServiceInfoText.HINT },
            { it.startsWith(ServiceInfoText.SERVICE_STATE_TITLE) && it.contains("Updating") },
            { it.startsWith(phaseTitle) },
            { it.startsWith(ServiceInfoText.LAST_PUBLISHED_TITLE) },
        )
        val seen = BooleanArray(expected.size)
        val anchors = listOf(
            "heading" to (hasText(ServiceInfoText.TITLE) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading)),
            "state" to hasTestTag("fst.settings.service-info.state"),
            "last-published" to hasTestTag("fst.settings.service-info.last-published"),
        )
        anchors.forEach { (anchor, matcher) ->
            rule.onAllNodes(matcher)[0].performScrollTo()
            refreshAccessibilityTree()
            val order = h.readingOrder("settings-service-info $config at $anchor")
            val at = expected.map { match -> order.indexOfFirst(match) }
            val visible = at.withIndex().filter { it.value >= 0 }
            visible.forEach { seen[it.index] = true }
            assertEquals("$config: Service Info items out of order at $anchor: $order", visible.map { it.value }.sorted(), visible.map { it.value })
            // The state row is one item that reads its title before the process state.
            order.getOrNull(at[2])?.let { state ->
                assertTrue("$config: state row reads the title before Updating ($state)", state.indexOf("Updating") > ServiceInfoText.SERVICE_STATE_TITLE.length)
            }
        }
        assertTrue("$config: every Service Info item was read (${seen.toList()})", seen.all { it })
    }

    /** UiAutomation caches nodes and Compose may not invalidate them after a programmatic scroll; read fresh ones. */
    private fun refreshAccessibilityTree() {
        rule.waitForIdle()
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) automation.clearCache()
        runCatching { automation.waitForIdle(500, 5_000) }
    }

    /**
     * The visible accessibility node exposing [tag] as its resource id.
     *
     * @param tag Test tag.
     * @return The node, or `null`.
     */
    private fun accessibilityNode(tag: String): AccessibilityNodeInfo? {
        refreshAccessibilityTree()
        fun find(n: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            n ?: return null
            if (n.viewIdResourceName == tag && n.isVisibleToUser) return n
            for (i in 0 until n.childCount) find(n.getChild(i))?.let { return it }
            return null
        }
        rule.onNodeWithTag(tag).performScrollTo()
        refreshAccessibilityTree()
        return find(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow)
    }

    // endregion
}
