package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import com.festivalscoretracker.android.ui.common.FestivalMarquee
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #597 (`page-tools-and-nav-chrome` R21) on a device: a page title wider than the top app
 * bar ("Lead Leaderboards" on Instrument Leaderboards at 200% text) scrolls on one line instead
 * of ending in "…", with the instrument icon still before it; at 100% text it scrolls only if it
 * really overflows the bar; under Reduce Motion it tail-truncates. In every case TalkBack reads
 * the full title once, after Back, and never stops on the decorative icon. ATF runs throughout.
 * `@DeviceCi`: the `android-device` job runs it
 * (`device.py test com.festivalscoretracker.android.journeys.PageBarTitleMarqueeJourneyTest --avd …`).
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class PageBarTitleMarqueeJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private fun transport(): FakeTransport = RankingsFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        },
    )

    // region Helpers

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).bufferedReader().readText().trim()
        }

    /** Runs [body] with the system animator duration scale at [scale] (device CI turns it off), then restores it. */
    private fun withAnimatorScale(scale: String, body: () -> Unit) {
        val saved = shell("settings get global animator_duration_scale")
        shell("settings put global animator_duration_scale $scale")
        try {
            body()
        } finally {
            shell(if (saved == "null" || saved.isEmpty()) "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $saved")
        }
    }

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInWindow

    private fun title(): SemanticsNode = rule.onNode(hasTestTag(TITLE_TAG) and hasText(TITLE), useUnmergedTree = true).fetchSemanticsNode()

    private fun layout(node: SemanticsNode): TextLayoutResult {
        val layouts = mutableListOf<TextLayoutResult>()
        node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        return layouts.single()
    }

    /**
     * Asserts the bar title is one line in [expected] mode (or, when null, `Scrolling` exactly
     * when it overflows), led by the unlabelled icon, and read once by TalkBack after Back.
     *
     * @param screen Reading-order log name.
     * @param expected Expected marquee mode, or null to derive it from the measured overflow.
     */
    private fun assertBarTitle(screen: String, expected: FestivalMarquee.Mode?) {
        h.waitForTag(ROW)
        h.awaitAccessibilityTree(present = ROW)
        rule.waitForIdle()
        val node = title()
        val box = node.boundsInWindow
        val text = layout(node)
        assertEquals("$screen: one line", 1, text.lineCount)
        val overflows = text.size.width > box.width + 1f
        val mode = node.config.getOrNull(FestivalMarquee.ModeKey)
        assertEquals("$screen: marquee mode (text ${text.size.width} px in a ${box.width} px box)", expected ?: if (overflows) FestivalMarquee.Mode.Scrolling else FestivalMarquee.Mode.Static, mode)
        if (mode == FestivalMarquee.Mode.Truncated) assertTrue("$screen: ends in an ellipsis", text.isLineEllipsized(0))
        val bar = bounds("fst.nav.top-bar")
        assertTrue("$screen: title $box inside the bar $bar", box.top >= bar.top - 1f && box.bottom <= bar.bottom + 1f)

        val icon = bounds(ICON)
        val tolerance = with(rule.density) { 2.dp.toPx() }
        assertTrue("$screen: icon ${icon.right} before title ${box.left}", icon.right <= box.left + 1f)
        assertEquals("$screen: icon centred on the title", box.center.y, icon.center.y, tolerance)
        val iconNode = rule.onNodeWithTag(ICON, useUnmergedTree = true).fetchSemanticsNode()
        assertEquals("$screen: the icon has its own label", null, iconNode.config.getOrNull(SemanticsProperties.ContentDescription))

        val order = h.readingOrder(screen, fresh = true)
        assertEquals("$screen: the full title is read once: $order", 1, order.count { it == TITLE })
        assertTrue("$screen: TalkBack stops on an unlabelled node: $order", "<unlabelled>" !in order)
        val iBack = order.indexOf("Back")
        assertTrue("$screen: Back before the title: $order", iBack in 0 until order.indexOf(TITLE))
        h.assertAccessible()
    }

    // endregion

    /** Animations on: the long title scrolls at 200% text and follows its measured overflow at 100%. */
    @Test
    fun longTitleScrollsAtLargeTextAndFitsStill() = withAnimatorScale("1") {
        var scale by mutableFloatStateOf(2f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("fullRankings:Solo_Guitar"), stillBackground = true), transport(), fontScale = { scale })
        h.publishTalkBackTree()
        assertBarTitle("bar-title-marquee-2x", FestivalMarquee.Mode.Scrolling)
        scale = 1f
        rule.waitForIdle()
        assertBarTitle("bar-title-marquee-1x", null)
    }

    /** Reduce Motion: the overflowing title tail-truncates instead of scrolling. */
    @Test
    fun reduceMotionTruncatesTheLongTitle() {
        h.enableAccessibilityChecks()
        val preferences = MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to true))
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("fullRankings:Solo_Guitar"), stillBackground = true), transport(), preferences, fontScale = { 2f })
        h.publishTalkBackTree()
        assertBarTitle("bar-title-reduce-motion-2x", FestivalMarquee.Mode.Truncated)
    }

    private companion object {
        const val TITLE = "Lead Leaderboards"
        const val TITLE_TAG = "fst.nav.title"
        const val ICON = "fst.full-rankings.title-icon.Solo_Guitar"
        val ROW = "fst.rankings.row.${RankingsFixtures.accountId(1)}"
    }
}
