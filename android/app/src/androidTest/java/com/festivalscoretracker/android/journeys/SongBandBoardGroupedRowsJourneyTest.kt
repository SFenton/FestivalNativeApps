package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Song band leaderboard rows grouped in one card (owner #543, `leaderboard-row` R10) on a
 * device: each band row inside the shared card is still one TalkBack Button stop at least 48 dp
 * tall, labelled "Open band", with no focusable children, and the rows read in rank order.
 * ATF runs throughout; nothing straddles a hinge
 * (`device.py test com.festivalscoretracker.android.journeys.SongBandBoardGroupedRowsJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class SongBandBoardGroupedRowsJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = BandFixtures.install(FakeTransport.standard())

    // region Accessibility tree

    /** Visible accessibility node whose resource id is [tag] (test tags are resource ids), or null. */
    private fun node(tag: String): AccessibilityNodeInfo? {
        fun find(n: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            n ?: return null
            if (n.viewIdResourceName == tag && n.isVisibleToUser) return n
            for (i in 0 until n.childCount) find(n.getChild(i))?.let { return it }
            return null
        }
        return find(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow)
    }

    /** Whether any descendant of [n] is a separate TalkBack stop. */
    private fun hasFocusableDescendant(n: AccessibilityNodeInfo): Boolean = (0 until n.childCount).any { i ->
        val c = n.getChild(i) ?: return@any false
        c.isClickable || c.isScreenReaderFocusable || hasFocusableDescendant(c)
    }

    private fun assertButtonRow(tag: String, card: android.graphics.Rect) {
        rule.onNode(hasTestTag(tag) and SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button), useUnmergedTree = true).assertExists()
        val n = requireNotNull(node(tag)) { "no visible $tag" }
        assertTrue("$tag not clickable", n.isClickable)
        assertEquals("$tag click label", "Open band", n.actionList.firstOrNull { it.id == AccessibilityNodeInfo.ACTION_CLICK }?.label?.toString())
        assertFalse("$tag has a second stop inside it", hasFocusableDescendant(n))
        val box = android.graphics.Rect().also(n::getBoundsInScreen)
        val minPx = 48 * rule.activity.resources.displayMetrics.density - 1
        assertTrue("$tag is ${box.height()} px tall (< 48 dp)", box.height() >= minPx)
        assertTrue("$tag $box inside the rows card $card", card.contains(box))
    }

    // endregion

    @Test
    fun bandRowsShareOneCardAndStayButtonStops() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("songBandLeaderboard:s-alpha:Band_Duets"), stillBackground = true), transport)
        h.waitForTag("fst.song-band-leaderboard.row.band-2:2")
        h.awaitAccessibilityTree("fst.song-band-leaderboard.row.band-2:2")
        val card = android.graphics.Rect().also(requireNotNull(node("fst.song-band-leaderboard.rows")) { "no rows card" }::getBoundsInScreen)
        assertButtonRow("fst.song-band-leaderboard.row.band-1:1", card)
        assertButtonRow("fst.song-band-leaderboard.row.band-2:2", card)
        val order = h.readingOrder("song-band-board-grouped")
        val first = order.indexOfFirst { it.contains("Rank 1,") }
        val second = order.indexOfFirst { it.contains("Rank 2,") }
        assertTrue("rank order in $order", first >= 0 && second > first)
        h.assertNothingStraddles("fst.song-band-leaderboard.row.band-1:1", "fst.song-band-leaderboard.row.band-2:2")

        h.tap("fst.song-band-leaderboard.row.band-1:1")
        h.waitForTag("fst.band.screen")
        h.assertAccessible()
    }
}
