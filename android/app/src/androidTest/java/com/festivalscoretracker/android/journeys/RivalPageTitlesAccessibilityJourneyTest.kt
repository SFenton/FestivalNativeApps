package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.testing.RivalsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #604 accessibility: the Rival pages' top app bar names the rival and the section.
 * Rival Detail reads the rival's name over "Rivals", or over "{instrument icon} Lead Rivals" for a
 * single-chart scope; Rivalry reads the section ("Closest Battles") over the rival's name. The
 * title and subtitle are one TalkBack stop after Back, naming each once and in that order; the
 * instrument icon is decorative (no label), sits before the subtitle text and within its line; at
 * 200% text the bar grows so neither line is clipped or ellipsized. ATF runs on every step.
 * Fixtures only; `@DeviceCi` puts it in the `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class RivalPageTitlesAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")
    private val rivalId = RivalsFixtures.RIVALS[1]

    private fun launch(debug: DebugLaunch, fontScale: () -> Float) {
        h.enableAccessibilityChecks()
        h.launch(debug, RivalsFixtures.transport(), fontScale = fontScale)
        h.publishTalkBackTree()
    }

    // region Journeys

    /** Lead song rivals: "Synthetic Rival" over "{guitar icon} Lead Rivals" at 100% and 200% text. */
    @Test
    fun instrumentRivalDetailNamesTheRivalOverItsInstrumentList() {
        var scale by mutableFloatStateOf(1f)
        launch(DebugLaunch(route = RivalRoutes.detail(rivalId, RIVAL, RivalScopes.song(listOf(Instrument.Lead))), profile = player, stillBackground = true)) { scale }
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            assertBar("rival-detail-lead-${fontScale}x", ready = "fst.rival-detail.title", title = RIVAL, subtitle = "Lead Rivals", icon = "fst.rival-detail.subtitle-icon.Solo_Guitar", scale = fontScale)
        }
        h.assertAccessible()
    }

    /** Common rivals span several charts: "Synthetic Rival" over plain "Rivals", no icon. */
    @Test
    fun commonRivalDetailNamesTheRivalOverRivals() {
        launch(DebugLaunch(route = RivalRoutes.detail(rivalId, RIVAL, RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass))), profile = player, stillBackground = true)) { 1f }
        assertBar("rival-detail-common", ready = "fst.rival-detail.title", title = RIVAL, subtitle = "Rivals", icon = null, scale = null)
        h.assertAccessible()
    }

    /** Rivalry: "Closest Battles" over "Synthetic Rival" at 100% and 200% text. */
    @Test
    fun rivalryNamesTheSectionOverTheRival() {
        var scale by mutableFloatStateOf(1f)
        val detail = RivalRoutes.detail(rivalId, RIVAL, RivalScopes.song(listOf(Instrument.Lead)))
        launch(DebugLaunch(route = RivalRoutes.rivalry(detail, "closest_battles", RIVAL), profile = player, stillBackground = true)) { scale }
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            assertBar("rivalry-${fontScale}x", ready = "fst.rivalry.title", title = "Closest Battles", subtitle = RIVAL, icon = null, scale = fontScale)
        }
        h.assertAccessible()
    }

    // endregion

    /**
     * Assert the bar reads [title] over [subtitle] as one TalkBack stop after Back, with [icon]
     * decorative before the subtitle (or no icon at all).
     *
     * @param screen Reading-order log name.
     * @param ready Tag shown once the page has loaded.
     * @param title Expected bar title.
     * @param subtitle Expected bar subtitle.
     * @param icon Expected subtitle icon tag, or null for none.
     * @param scale Font scale to check for clipping, or null to skip.
     */
    private fun assertBar(screen: String, ready: String, title: String, subtitle: String, icon: String?, scale: Float?) {
        h.waitForTag(ready)
        h.awaitAccessibilityTree(present = ready)
        val bar = hasTestTag("fst.nav.title-block")
        assertTrue("$screen: no bar title \"$title\"", rule.onAllNodes(hasText(title) and hasAnyAncestor(bar), useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty())
        val line = rule.onNode(hasTestTag("fst.nav.subtitle"), useUnmergedTree = true).fetchSemanticsNode()
        assertEquals("$screen: subtitle", subtitle, line.config.getOrNull(SemanticsProperties.Text)?.joinToString())
        if (scale != null) {
            h.assertTextUnclipped(screen, "fst.nav.title-block", subtitle, scale)
        }

        if (icon == null) {
            assertFalse("$screen: a multi-chart or Rivalry subtitle has an icon", h.exists("fst.nav.subtitle-icon"))
        } else {
            rule.onNode(hasTestTag(icon) and hasAnyAncestor(hasTestTag("fst.nav.subtitle-icon")), useUnmergedTree = true).assertExists()
            val glyphs = rule.onAllNodes(hasTestTag("fst.nav.subtitle-icon") or hasAnyAncestor(hasTestTag("fst.nav.subtitle-icon")), useUnmergedTree = true).fetchSemanticsNodes()
            assertTrue("$screen: the decorative icon has a label", glyphs.none { it.config.getOrNull(SemanticsProperties.ContentDescription).orEmpty().isNotEmpty() })
            val box = rule.onNode(hasTestTag("fst.nav.subtitle-icon"), useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
            val text = line.boundsInRoot
            assertTrue("$screen: icon ${box.right} not before the subtitle ${text.left}", box.right <= text.left + 1)
            assertTrue("$screen: icon ${box.height} taller than the subtitle line ${text.height}", box.height <= text.height + 2 * rule.density.density)
        }

        val stops = h.readingStops(screen, fresh = true)
        val labels = stops.map { it.label }
        val barOnScreen = android.graphics.Rect().also { r -> checkNotNull(h.accessibilityNode("fst.nav.top-bar")) { "$screen: no bar node" }.getBoundsInScreen(r) }
        val inBar = stops.filter { it.bounds.centerY() in barOnScreen.top..barOnScreen.bottom && it.label.contains(title) }
        assertEquals("$screen: the bar title is read ${inBar.size} times in $labels", 1, inBar.size)
        val stop = inBar.single().label
        assertTrue("$screen: \"$stop\" does not read the title before the subtitle", stop.startsWith(title) && stop.indexOf(subtitle, title.length) > 0)
        assertEquals("$screen: \"$stop\" names the subtitle more than once", 1, Regex("\\b${Regex.escape(subtitle)}\\b").findAll(stop.substring(title.length)).count())
        assertTrue("$screen: TalkBack stops on an unlabelled node: $labels", "<unlabelled>" !in labels)
        val iBack = labels.indexOf("Back")
        assertTrue("$screen: Back is not read before the title: $labels", iBack >= 0 && iBack < labels.indexOf(stop))
    }

    private companion object {
        const val RIVAL = "Synthetic Rival"
    }
}
