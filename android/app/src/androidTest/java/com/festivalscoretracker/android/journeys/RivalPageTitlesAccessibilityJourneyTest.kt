package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.testing.RivalsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #604 accessibility: the pages under one rival name the rival and the section in the top
 * app bar. Rival Detail reads the rival's name over "Rivals", or over "{Instrument} Rivals" led by
 * the chart's decorative icon when the rival came from a single-chart list; Rivalry reads the
 * section ("Closest Battles") over the rival's name. TalkBack reaches the title and subtitle as
 * one stop after Back that names each once, the icon has no label, sits left of the subtitle
 * within its line and grows with the text, and at 200% text the subtitle is neither clipped nor
 * ellipsized. ATF runs on every step. Fixtures only; `@DeviceCi` puts it in the
 * `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class RivalPageTitlesAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")

    private fun launch(scope: RivalScope, fontScale: () -> Float) {
        h.enableAccessibilityChecks()
        val route = RivalRoutes.detail(RivalsFixtures.RIVALS[0], RIVAL, scope)
        h.launch(DebugLaunch(route = route, profile = player, stillBackground = true), RivalsFixtures.transport(), fontScale = fontScale)
        h.publishTalkBackTree()
    }

    private fun bounds(tag: String): Rect = rule.onNode(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNode().boundsInWindow

    /**
     * Asserts the bar's title and subtitle, the subtitle icon and the TalkBack stop.
     *
     * @param screen Reading-order log name.
     * @param title Expected bar title.
     * @param subtitle Expected subtitle.
     * @param icon Expected subtitle icon tag, or null for none.
     * @param scale Font scale the page renders at.
     * @return The icon's height in pixels (0 without one).
     */
    private fun assertBar(screen: String, title: String, subtitle: String, icon: String?, scale: Float): Float {
        h.waitForTag("fst.nav.subtitle")
        h.awaitAccessibilityTree(present = "fst.nav.title-block")
        val block = hasAnyAncestor(hasTestTag("fst.nav.title-block"))
        assertTrue("$screen: the bar does not read \"$title\"", rule.onAllNodes(hasText(title) and block, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        val line = rule.onNode(hasTestTag("fst.nav.subtitle"), useUnmergedTree = true).fetchSemanticsNode()
        assertEquals("$screen: subtitle", subtitle, line.config.getOrNull(SemanticsProperties.Text)?.joinToString())
        val bar = bounds("fst.nav.top-bar")
        assertTrue("$screen: subtitle ${line.boundsInWindow} outside the bar $bar", line.boundsInWindow.top >= bar.top - 1 && line.boundsInWindow.bottom <= bar.bottom + 1)
        h.assertTextUnclipped(screen, "fst.nav.title-block", subtitle, scale)

        var iconHeight = 0f
        if (icon == null) {
            assertFalse("$screen: a multi-chart or section subtitle has an icon", h.exists("fst.nav.subtitle-icon"))
        } else {
            assertTrue("$screen: the icon is not in the top bar", rule.onAllNodes(hasTestTag(icon) and hasAnyAncestor(hasTestTag("fst.nav.top-bar")), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
            val glyph = rule.onAllNodes(hasAnyAncestor(hasTestTag("fst.nav.subtitle-icon")) or hasTestTag("fst.nav.subtitle-icon"), useUnmergedTree = true).fetchSemanticsNodes()
            assertTrue("$screen: the decorative icon has a label", glyph.none { it.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().isNotEmpty() })
            val box = bounds("fst.nav.subtitle-icon")
            val text = line.boundsInWindow
            val tolerance = with(rule.density) { 2.dp.toPx() }
            assertTrue("$screen: icon ${box.right} not left of the subtitle ${text.left}", box.right <= text.left + tolerance)
            assertTrue("$screen: icon ${box.height} taller than the subtitle line ${text.height}", box.height <= text.height + tolerance)
            assertEquals("$screen: icon not centred on the subtitle", text.center.y, box.center.y, tolerance)
            assertFalse("$screen: the title also has an icon", h.exists("fst.nav.title-icon"))
            iconHeight = box.height
        }

        // TalkBack: Back, then one bar stop naming the title then the subtitle, once each.
        val stops = h.readingStops(screen, fresh = true)
        val barOnScreen = android.graphics.Rect().also { r -> checkNotNull(h.accessibilityNode("fst.nav.top-bar")) { "$screen: no bar node" }.getBoundsInScreen(r) }
        val inBar = stops.filter { it.bounds.centerY() in barOnScreen.top..barOnScreen.bottom && it.label.contains(subtitle) }
        assertEquals("$screen: the bar's title is read ${inBar.size} times in ${stops.map { it.label }}", 1, inBar.size)
        val stop = inBar.single().label
        assertEquals("$screen: \"$stop\" names the title once", 1, Regex(Regex.escape(title)).findAll(stop).count())
        assertTrue("$screen: \"$stop\" reads the subtitle before the title", stop.indexOf(title) < stop.lastIndexOf(subtitle))
        assertTrue("$screen: TalkBack stops on an unlabelled node", stops.none { it.label == "<unlabelled>" })
        val labels = stops.map { it.label }
        assertTrue("$screen: Back is not read before the title: $labels", labels.indexOf("Back") in 0 until labels.indexOf(stop))
        h.assertAccessible()
        return iconHeight
    }

    /** Lead rival: "Synthetic Rival" over "{guitar} Lead Rivals" at 100% and 200%, then Rivalry. */
    @Test
    fun singleChartDetailAndRivalryNameTheRivalAndSection() {
        var scale by mutableFloatStateOf(1f)
        launch(RivalScopes.song(listOf(Instrument.Lead))) { scale }
        val heights = mutableListOf<Float>()
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            h.waitForTag(DETAIL)
            heights += assertBar("rival-detail-bar-${fontScale}x", RIVAL, "Lead Rivals", "fst.rival.subtitle-icon.Solo_Guitar", fontScale)
        }
        assertTrue("200% text did not grow the subtitle icon ($heights px)", heights[1] > heights[0])

        scale = 1f
        rule.waitForIdle()
        h.tap(SEE_ALL_CLOSEST)
        h.waitForTag(RIVALRY)
        h.awaitAccessibilityTree(present = RIVALRY, absent = DETAIL)
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            h.waitForTag(RIVALRY)
            assertBar("rivalry-bar-${fontScale}x", "Closest Battles", RIVAL, null, fontScale)
        }
    }

    /** Common rival: the plain "Rivals" subtitle with no icon. */
    @Test
    fun multiChartDetailReadsRivals() {
        launch(RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass))) { 1f }
        h.waitForTag(DETAIL)
        assertBar("rival-detail-common-bar", RIVAL, "Rivals", null, 1f)
    }

    private companion object {
        const val RIVAL = "Synthetic Rival"
        const val DETAIL = "fst.rival-detail.title"
        const val RIVALRY = "fst.rivalry.title"
        const val SEE_ALL_CLOSEST = "fst.rival-detail.see-all.closest_battles"
    }
}
