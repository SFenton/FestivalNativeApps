package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Item Shop **Filter Item Shop** sheet on a device (issues #19, #376; accessibility backfill
 * #428), at the device's text size and at 200% system text, with ATF on every step: the sheet
 * reads its heading, Close, the hint, then the **New**, **Available** and **Leaving Tomorrow**
 * switches in sheet order, then Reset; each switch row is one stop with the Switch role, its
 * label, description and On/Off state, at least 48 × 48 dp, with its texts unclipped inside the
 * row; Close, Reset and the page's Filter button are 48 dp targets. Turning a switch off reads
 * "Off", hides that group and makes the Filter button speak "Filters on: hiding …"; Reset turns
 * every switch back on. Run with
 * `device.py test com.festivalscoretracker.android.journeys.ShopFilterAccessibilityJourneyTest --avd …`;
 * reading orders go to logcat `FST_A11Y`.
 *
 * Fixture offers: s-beta (New), s-x (neither: Available), s-alpha (Leaving Tomorrow).
 */
@RunWith(AndroidJUnit4::class)
class ShopFilterAccessibilityJourneyTest {
    /** Sheets compose in their own window, so only the system font scale reaches them. */
    @get:Rule(order = 0)
    val fontScale = SystemFontScaleRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = PUBLICATION) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        on("/api/shop", headers = PUBLICATION) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
    }

    /** The three switches in sheet order. */
    private val switches = listOf(
        SwitchExpectation("fst.shop.filter.new", "New", "Songs that are new in the Item Shop today.", "s-beta"),
        SwitchExpectation("fst.shop.filter.available", "Available", "Songs in the Item Shop today that aren't new or leaving tomorrow.", "s-x"),
        SwitchExpectation("fst.shop.filter.leaving", "Leaving Tomorrow", "Songs that are leaving the Item Shop tomorrow.", "s-alpha"),
    )

    // region Helpers

    private fun reveal(tag: String) = h.reveal("fst.shop.filter.form", tag)

    private fun assertTarget(screen: String, tag: String) = h.assertTouchTarget(screen, tag)

    private fun assertSwitchState(screen: String, switch: SwitchExpectation, on: Boolean) = h.assertSwitchStop(screen, switch.tag, on)

    /**
     * Switch rows in [order], by label.
     *
     * @param order Reading order.
     * @return Labels of the switch stops, in reading order.
     */
    private fun switchStops(order: List<String>): List<String> = order.mapNotNull { spoken -> switches.firstOrNull { it.matches(spoken) }?.label }

    /**
     * Open the sheet and assert its heading, reading order, switch rows, text and targets at
     * the current font scale; leaves the sheet open.
     *
     * @param screen Reading-order log name.
     * @param scale Font scale the sheet's text must be laid out at.
     */
    private fun assertSheet(screen: String, scale: Float) {
        assertTarget(screen, "fst.shop.filter.open")
        h.tap("fst.shop.filter.open")
        h.waitForTag("fst.shop.filter.leaving")
        rule.onNodeWithTag("fst.shop.filter.title").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithTag("fst.shop.filter.done").assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Close")))
        rule.onNodeWithTag("fst.shop.filter.reset").assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        h.awaitAccessibilityTree("fst.shop.filter.new")

        val expected = switches.map { it.label }
        var order = h.readingOrder(screen, fresh = true)
        val heading = order.indexOf("Filter Item Shop")
        val close = order.indexOf("Close")
        val hint = order.indexOfFirst { it.startsWith("Turn a switch off") }
        assertTrue("$screen: heading, Close, hint in $order", heading >= 0 && close > heading && hint > close)
        assertTrue("$screen: switches after the hint in $order", order.indexOfFirst { s -> switches.any { it.matches(s) } } > hint)
        var stops = switchStops(order)
        assertEquals("$screen: switches in sheet order in $order", expected.filter { it in stops }, stops)
        // At large text the form scrolls: read the rest from the bottom of the sheet.
        if (stops != expected || "Reset" !in order) {
            reveal("fst.shop.filter.reset")
            reveal("fst.shop.filter.leaving")
            order = h.readingOrder("$screen-scrolled", fresh = true)
            val more = switchStops(order)
            assertEquals("$screen: switches in sheet order in $order", expected.filter { it in more }, more)
            stops = stops + more.filter { it !in stops }
        }
        assertEquals("$screen: every switch is one stop, in sheet order", expected, stops)
        // Phone portrait keeps Reset under the form; compact-height windows move it into the header, before Close.
        val reset = order.indexOf("Reset")
        val lastSwitch = order.indexOfLast { s -> switches.any { it.matches(s) } }
        assertTrue("$screen: Reset is a stop after the switches or in the header in $order", reset > lastSwitch || (reset >= 0 && reset < order.indexOf("Close")))

        switches.forEach { s ->
            reveal(s.tag)
            assertSwitchState(screen, s, on = true)
            assertTarget(screen, s.tag)
            listOf(s.label, s.description).forEach { text -> h.assertTextUnclipped(screen, s.tag, text, scale) }
        }
        reveal("fst.shop.filter.reset")
        listOf("fst.shop.filter.done", "fst.shop.filter.reset").forEach { assertTarget(screen, it) }
        h.assertNothingStraddles("fst.shop.filter", "fst.shop.filter.done", "fst.shop.filter.reset", *switches.map { it.tag }.toTypedArray())
    }

    private fun closeSheet() {
        h.tap("fst.shop.filter.done")
        h.waitGone("fst.shop.filter.leaving")
    }

    private fun filterButtonState() = rule.onAllNodesWithTag("fst.shop.filter.open", useUnmergedTree = true)[0].fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    private fun awaitOffers() {
        rule.waitUntil(15_000) { h.exists("fst.shop.list") || h.exists("fst.shop.grid") }
        switches.forEach { h.waitForTag("fst.shop.song.${it.offer}") }
    }

    private fun launch() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("shop"), profile = player, stillBackground = true), transport)
        awaitOffers()
        assertEquals("No filters", filterButtonState())
    }

    /**
     * Turn each switch off on its own: it reads Off, the others stay On, its group leaves the
     * page and the Filter button says what is hidden; Reset turns everything back on.
     *
     * @param screen Log prefix.
     */
    private fun assertEachSwitchHidesItsGroup(screen: String) {
        switches.forEach { s ->
            h.tap("fst.shop.filter.open")
            h.waitForTag(s.tag)
            reveal(s.tag)
            h.tap(s.tag)
            assertSwitchState("$screen-off-${s.label}", s, on = false)
            switches.filter { it != s }.forEach { assertSwitchState("$screen-off-${s.label}", it, on = true) }
            h.readingOrder("$screen-off-${s.label}", fresh = true)
            h.waitGone("fst.shop.song.${s.offer}")
            closeSheet()
            assertEquals("Filters on: hiding ${s.label}", filterButtonState())
            h.readingOrder("$screen-filtered-${s.label}", fresh = true)
            h.tap("fst.shop.filter.open")
            h.waitForTag("fst.shop.filter.reset")
            reveal("fst.shop.filter.reset")
            h.tap("fst.shop.filter.reset")
            switches.forEach { reveal(it.tag); assertSwitchState("$screen-reset", it, on = true) }
            closeSheet()
            assertEquals("No filters", filterButtonState())
            awaitOffers()
        }
    }

    // endregion

    /** Device text size: order, roles, states and targets, then each switch's Off state and Reset. */
    @Test
    @DeviceCi
    fun filterSheetReadsInOrderWithSwitchStatesAndTargets() {
        launch()
        assertSheet("shop-filter", scale = rule.activity.resources.configuration.fontScale)
        closeSheet()
        assertEachSwitchHidesItsGroup("shop-filter")
        h.assertAccessible()
    }

    /** 200% system text: the sheet's text grows unclipped, rows stay 48 dp stops in order, actions stay reachable. */
    @Test
    @DeviceCi
    @SystemFontScale(2f)
    fun filterSheetAtDoubleTextKeepsOrderTargetsAndUnclippedText() {
        launch()
        assertEquals(2f, rule.activity.resources.configuration.fontScale, 0.01f)
        assertSheet("shop-filter-2x", scale = 2f)
        closeSheet()
        assertEachSwitchHidesItsGroup("shop-filter-2x")
        h.assertAccessible()
    }

    /**
     * One expected switch row.
     *
     * @property tag Row test tag.
     * @property label Visible label.
     * @property description Visible description under the label.
     * @property offer Fixture offer the switch hides when off.
     */
    private data class SwitchExpectation(val tag: String, val label: String, val description: String, val offer: String) {
        /**
         * Whether a reading-order label is this row's stop (label, description and state).
         *
         * @param spoken Spoken label.
         * @return True for this row.
         */
        fun matches(spoken: String): Boolean = spoken.startsWith(label) && description in spoken
    }

    private companion object {
        val PUBLICATION = mapOf("X-FST-Publication-Id" to "7")
    }
}
