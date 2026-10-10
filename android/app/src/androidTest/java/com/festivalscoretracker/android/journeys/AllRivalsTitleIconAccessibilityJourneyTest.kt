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
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.rivals.RivalScope
import com.festivalscoretracker.android.core.rivals.RivalScopes
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RivalsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #557 accessibility: a single-chart All Rivals list leads its top app bar title with the
 * chart's icon, sized to the title style's line (28 dp at 100% text, growing at 200%, never taller
 * than the title). The icon is decorative, so
 * TalkBack reads the title once (Back → title → … → rank line → rows) and never stops on the
 * icon; Common lists have no icon. ATF runs on every step. Fixtures only; `@DeviceCi` puts it
 * in the `android-device` job.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class AllRivalsTitleIconAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")

    private fun launch(scope: RivalScope, fontScale: () -> Float) {
        h.enableAccessibilityChecks()
        val transport = RivalsFixtures.transport().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        }
        h.launch(DebugLaunch(route = RivalRoutes.allRivals(scope), profile = player, stillBackground = true), transport, fontScale = fontScale)
        h.publishTalkBackTree()
    }

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    /**
     * Asserts the icon is in the top app bar, left of the title, centred on it and within its
     * line, unlabelled, and that TalkBack reads the title once before the rank line and rows.
     *
     * @param screen Reading-order log name.
     * @return The icon's height in pixels.
     */
    private fun assertTitleIcon(screen: String): Float {
        h.waitForTag(ROW)
        h.awaitAccessibilityTree(present = ROW)
        rule.onNode(hasTestTag(ICON) and hasAnyAncestor(hasTestTag("fst.nav.top-bar")), useUnmergedTree = true).assertExists()
        val node = rule.onNodeWithTag(ICON, useUnmergedTree = true).fetchSemanticsNode()
        assertEquals("$screen: the icon has its own label", null, node.config.getOrNull(SemanticsProperties.ContentDescription))
        val icon = bounds(ICON)
        val title = bounds("fst.nav.title")
        val tolerance = with(rule.density) { 2.dp.toPx() }
        assertTrue("$screen: icon ${icon.right} before title ${title.left}", icon.right <= title.left)
        assertTrue("$screen: icon ${icon.height} within the title line ${title.height}", icon.height <= title.height + tolerance)
        assertEquals("$screen: icon centred on the title", title.center.y, icon.center.y, tolerance)

        val order = h.readingOrder(screen, fresh = true)
        assertEquals("$screen: the title is read once: $order", 1, order.count { it == TITLE })
        assertTrue("$screen: TalkBack stops on an unlabelled node: $order", "<unlabelled>" !in order)
        val iBack = order.indexOf("Back")
        val iTitle = order.indexOf(TITLE)
        val iRank = order.indexOf(RANK)
        val iRow = order.indexOfFirst { it.startsWith("$NEIGHBOUR, ") }
        assertTrue("$screen: TalkBack misses Back, the title, the rank line or a row: $order", listOf(iBack, iTitle, iRank, iRow).all { it >= 0 })
        assertTrue("$screen: read out of order: $order", iBack < iTitle && iTitle < iRank && iRank < iRow)
        return icon.height
    }

    /** The Lead leaderboard list: icon-led title at 100% and 200% text, read once by TalkBack. */
    @Test
    fun singleChartTitleLeadsWithItsIconAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        launch(RivalScope.Leaderboard(Instrument.Lead)) { scale }
        val heights = mutableListOf<Float>()
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            heights += assertTitleIcon("all-rivals-title-icon-${fontScale}x")
        }
        assertEquals("28 dp at 100% text (M3 Title Large line)", 28f, with(rule.density) { heights[0].toDp() }.value, 1f)
        assertTrue("200% text did not grow the icon ($heights px)", heights[1] > heights[0])
        h.assertAccessible()
    }

    /** Common Rivals spans several charts, so its title has no icon (web parity). */
    @Test
    fun commonListTitleHasNoIcon() {
        launch(RivalScopes.song(listOf(Instrument.Lead, Instrument.Bass))) { 1f }
        h.waitForTag("fst.all-rivals.list")
        assertEquals(0, rule.onAllNodesWithTag("fst.nav.title-icon", useUnmergedTree = true).fetchSemanticsNodes().size)
        h.assertAccessible()
    }

    private companion object {
        const val TITLE = "Lead Rivals"
        const val ICON = "fst.all-rivals.title-icon.Solo_Guitar"
        const val RANK = "Your rank: #42 · Total Score"
        const val NEIGHBOUR = "Synthetic Neighbour"
        val ROW = "fst.rivals.row.${RivalsFixtures.RIVALS[0]}"
    }
}
