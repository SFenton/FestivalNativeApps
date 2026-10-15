package com.festivalscoretracker.android.journeys

import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.RivalsRoute
import com.festivalscoretracker.android.testing.RivalsFixtures
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Issue #649 (`load-transition` R1, `quick-links`): on the Rivals hub, Quick Links acts on the
 * tab's cards, so TalkBack never meets it beside the "Loading rivals" spinner, on the first load
 * or a tab switch; it arrives with the cards as an enabled 48 dp stop. ATF runs on each state.
 * Fixtures only; `@DeviceCi` puts it in the `android-device` job.
 *
 * `device.py test com.festivalscoretracker.android.journeys.RivalsHubQuickLinksAccessibilityJourneyTest --avd …`
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class RivalsHubQuickLinksAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(RivalsFixtures.PLAYER, "Synthetic Player")
    private val holds = CopyOnWriteArrayList<Pair<(String) -> Boolean, CompletableDeferred<Unit>>>()
    private val transport = RivalsFixtures.transport().apply {
        beforeRespond = { request -> holds.firstOrNull { (matches, gate) -> !gate.isCompleted && matches(request.url) }?.second?.await() }
    }

    @After
    fun release() = holds.forEach { it.second.complete(Unit) }

    private fun hold(matches: (String) -> Boolean): CompletableDeferred<Unit> = CompletableDeferred<Unit>().also { holds += matches to it }

    /** Visible accessibility nodes whose resource id is [id]. */
    private fun visible(id: String): List<AccessibilityNodeInfo> {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (android.os.Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val out = mutableListOf<AccessibilityNodeInfo>()
        fun walk(n: AccessibilityNodeInfo?) {
            n ?: return
            if (n.isVisibleToUser && n.viewIdResourceName == id) out += n
            for (i in 0 until n.childCount) walk(n.getChild(i))
        }
        walk(automation.rootInActiveWindow)
        return out
    }

    /** The spinner is one "Loading rivals" stop and Quick Links is not in TalkBack's tree. */
    private fun assertSpinnerWithoutQuickLinks(screen: String) {
        h.waitForTag(SPINNER)
        h.awaitAccessibilityTree(present = SPINNER, absent = QUICK_LINKS)
        val order = h.readingOrder(screen, fresh = true)
        assertEquals("the spinner is not one stop in $order", 1, order.count { it.startsWith("Loading rivals") })
        assertTrue("Quick Links read beside the spinner: $order", order.none { it.startsWith(QUICK_LINKS_LABEL) })
        assertTrue("Quick Links in the tree beside the spinner", visible(QUICK_LINKS).isEmpty())
        h.assertAccessible()
    }

    /** Quick Links is back with the cards: one enabled, labelled stop at least 48 dp. */
    private fun assertQuickLinksWithCards(screen: String, section: String) {
        h.waitForTag(section)
        h.waitGone(SPINNER)
        h.awaitAccessibilityTree(present = QUICK_LINKS, absent = SPINNER)
        val order = h.readingOrder(screen, fresh = true)
        assertTrue("Quick Links not read with the cards: $order", order.any { it.startsWith(QUICK_LINKS_LABEL) })
        val button = visible(QUICK_LINKS).single()
        val box = android.graphics.Rect().also(button::getBoundsInScreen)
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("Quick Links is ${box.width()}×${box.height()} px, under 48 dp", box.width() >= min && box.height() >= min)
        assertTrue("Quick Links is disabled", button.isEnabled)
        h.assertAccessible()
    }

    @Test
    fun quickLinksArriveWithEachTabsCards() {
        h.enableAccessibilityChecks()
        val song = hold { it.contains("/api/player/${RivalsFixtures.PLAYER}/rivals/") }
        h.launch(DebugLaunch(route = RivalsRoute, profile = player, stillBackground = true), transport)
        assertSpinnerWithoutQuickLinks("rivals-hub-first-load")
        song.complete(Unit)
        assertQuickLinksWithCards("rivals-hub-song", "fst.rivals.section.Solo_Guitar")

        val leaderboard = hold { it.contains("/api/player/${RivalsFixtures.PLAYER}/leaderboard-rivals/") }
        h.tap("fst.rivals.tab.leaderboard")
        assertSpinnerWithoutQuickLinks("rivals-hub-tab-switch")
        leaderboard.complete(Unit)
        assertQuickLinksWithCards("rivals-hub-leaderboard", "fst.rivals.section.leaderboard.Solo_Guitar")
    }

    private companion object {
        const val SPINNER = "fst.rivals.loading"
        const val QUICK_LINKS = "fst.quick-links.open"
        const val QUICK_LINKS_LABEL = "Quick Links"
    }
}
