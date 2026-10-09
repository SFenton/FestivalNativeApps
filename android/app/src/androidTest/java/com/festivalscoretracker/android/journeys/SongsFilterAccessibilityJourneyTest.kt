package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Songs **Filter Songs** sheet without a selected player (issue #77, web `FilterModal` General
 * section; accessibility backfill #432), at the device's text size and at 200% system text,
 * with ATF on every step. The page's Filter button is a 48 dp "Filter songs" button that speaks
 * its state ("No filters" ⇄ "Filters on: …", issue #181). The sheet reads its heading, Close,
 * the **General** heading and hint, then the **Year**, **Duration**, **Item Shop** and
 * **Double Bass** group headers in sheet order, then Reset, with no player-only section. Each
 * group header is a 48 dp heading button that speaks Collapsed/Expanded; each switch inside is
 * one 48 dp stop with the Switch role, its label and On/Off state, read in sheet order, with its
 * text unclipped; Select All / Clear All are 48 dp buttons. Turning switches off reads "Off" and
 * updates the Filter button; Reset turns them back on. Run with
 * `device.py test com.festivalscoretracker.android.journeys.SongsFilterAccessibilityJourneyTest --avd …`;
 * reading orders go to logcat `FST_A11Y`.
 *
 * Fixture songs: s-alpha (2021, 3 min, double bass), s-beta (2019, 4 min, no double bass),
 * s-gamma (2023, 1 min, double bass unknown).
 */
@RunWith(AndroidJUnit4::class)
class SongsFilterAccessibilityJourneyTest {
    /** Sheets compose in their own window, so only the system font scale reaches them. */
    @get:Rule(order = 0)
    val fontScale = SystemFontScaleRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = PUBLICATION) {
            Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null")
                .replace("\"sig\":\"Guitar\"", "\"sig\":\"Guitar\",\"doubleBassSupported\":true")
                .replace("\"sig\":\"Keyboard\"", "\"sig\":\"Keyboard\",\"doubleBassSupported\":false")
        }
        on("/api/shop", headers = PUBLICATION) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
    }

    /** The General groups in sheet order (the fixture catalogue's decades and minute buckets). */
    private val groups = listOf(
        Group("fst.songs.filter.year", "Year", listOf(2010, 2020).map { Toggle("fst.songs.filter.year.$it", "${it}s") }, bulk = true),
        Group(
            "fst.songs.filter.duration",
            "Duration",
            (0 until 10).map { Toggle("fst.songs.filter.duration.$it", if (it == 0) "Under 1 Minute" else "$it-${it + 1} Minutes") },
            bulk = true,
        ),
        Group(
            "fst.songs.filter.shop",
            "Item Shop",
            listOf(Toggle("fst.songs.filter.shop-available", "Available in Item Shop"), Toggle("fst.songs.filter.shop-unavailable", "Not Available in Item Shop")),
            bulk = false,
        ),
        Group(
            "fst.songs.filter.double-bass",
            "Double Bass",
            listOf(Toggle("fst.songs.filter.double-bass.supported", "Double Bass Support"), Toggle("fst.songs.filter.double-bass.unsupported", "No Double Bass Support")),
            bulk = false,
        ),
    )

    // region Helpers

    private fun reveal(tag: String) = h.reveal(FORM, tag)

    private fun filterButtonState() =
        rule.onAllNodesWithTag("fst.songs.filter.open", useUnmergedTree = true)[0].fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    private fun assertHeaderState(tag: String, expanded: Boolean) =
        rule.onNodeWithTag(tag).assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, if (expanded) "Expanded" else "Collapsed"))

    /**
     * Group headers in [order], by title.
     *
     * @param order Reading order.
     * @return Titles of the header stops, in reading order.
     */
    private fun headerStops(order: List<String>): List<String> = order.mapNotNull { spoken -> groups.firstOrNull { it.isHeader(spoken) }?.title }

    private fun launch() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(stillBackground = true), transport)
        h.waitForTag("fst.songs.row.s-beta")
        assertEquals("No filters", filterButtonState())
    }

    private fun openSheet() {
        h.tap("fst.songs.filter.open")
        h.waitForTag("fst.songs.filter.general")
    }

    private fun closeSheet() {
        h.tap("fst.songs.filter.done")
        h.waitGone(FORM)
    }

    /**
     * Open the sheet and assert the Filter button, the sheet's headings, its reading order with
     * every group collapsed and the absence of player sections at the current font scale; leaves
     * the sheet open.
     *
     * @param screen Reading-order log name.
     */
    private fun assertSheetAtRest(screen: String) {
        rule.onNodeWithTag("fst.songs.filter.open")
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Filter songs")))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        h.assertTouchTarget(screen, "fst.songs.filter.open")
        openSheet()
        rule.onNodeWithTag("fst.songs.filter.title").assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithTag("fst.songs.filter.done").assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Close")))
        rule.onNodeWithTag("fst.songs.filter.reset").assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        rule.onNode(hasText("General") and hasAnyAncestor(hasTestTag("fst.songs.filter.general")), useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        // No player: only General (web 6415d3e3).
        assertEquals(0, rule.onAllNodesWithTag("fst.songs.filter.score-sections", useUnmergedTree = true).fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithTag("fst.songs.filter.instrument", useUnmergedTree = true).fetchSemanticsNodes().size)
        groups.forEach { assertHeaderState(it.tag, expanded = false) }
        h.awaitAccessibilityTree("fst.songs.filter.year")

        val expected = groups.map { it.title }
        var order = h.readingOrder(screen, fresh = true)
        val heading = order.indexOf("Filter Songs")
        val close = order.indexOf("Close")
        val general = order.indexOf("General")
        val hint = order.indexOf("General filters that apply to all songs.")
        assertTrue("$screen: heading, Close, General, hint in $order", heading >= 0 && close > heading && general > close && hint > general)
        assertTrue("$screen: groups after the hint in $order", order.indexOfFirst { s -> groups.any { it.isHeader(s) } } > hint)
        var stops = headerStops(order)
        assertEquals("$screen: groups in sheet order in $order", expected.filter { it in stops }, stops)
        // At large text the form scrolls: read the rest from the bottom of the sheet.
        if (stops != expected || "Reset" !in order) {
            reveal("fst.songs.filter.reset")
            reveal(groups.last().tag)
            order = h.readingOrder("$screen-scrolled", fresh = true)
            val more = headerStops(order)
            assertEquals("$screen: groups in sheet order in $order", expected.filter { it in more }, more)
            stops = stops + more.filter { it !in stops }
        }
        assertEquals("$screen: every group header is one stop, in sheet order", expected, stops)
        assertFalse("$screen: no player section in $order", order.any { "Score & FC" in it || it.startsWith("Selected Instrument") })
        // Phone portrait keeps Reset under the form; compact-height windows move it into the header, before Close.
        val reset = order.indexOf("Reset")
        val lastHeader = order.indexOfLast { s -> groups.any { it.isHeader(s) } }
        assertTrue("$screen: Reset is a stop after the groups or in the header in $order", reset > lastHeader || (reset >= 0 && reset < order.indexOf("Close")))
        listOf("fst.songs.filter.done", "fst.songs.filter.reset").forEach { h.assertTouchTarget(screen, it) }
    }

    /**
     * Expand each group and assert its header, bulk actions and switch rows: roles, states,
     * targets, unclipped text at [scale] and the switches' reading order. Leaves every group open.
     *
     * @param screen Reading-order log name.
     * @param scale Font scale the sheet's text must be laid out at.
     */
    private fun assertGroups(screen: String, scale: Float) {
        groups.forEach { g ->
            reveal(g.tag)
            rule.onNodeWithTag(g.tag)
                .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
                .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
            assertTrue("$screen: ${g.tag} is a heading for TalkBack", checkNotNull(h.accessibilityNode(g.tag)) { "$screen: ${g.tag} in the tree" }.isHeading)
            h.assertTouchTarget(screen, g.tag)
            h.assertTextUnclipped(screen, g.tag, g.title, scale)
            h.tap(g.tag)
            h.waitForTag("${g.tag}.content")
            assertHeaderState(g.tag, expanded = true)
            if (g.bulk) {
                listOf("${g.tag}.select-all", "${g.tag}.clear-all").forEach { tag ->
                    reveal(tag)
                    // performScrollTo leaves the 40 dp button flush with the viewport edge, which clips
                    // its 48 dp touch bounds; bring the first switch row below it into view as well.
                    reveal(g.toggles.first().tag)
                    rule.onNodeWithTag(tag).assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
                    h.assertTouchTarget(screen, tag)
                }
            }
            g.toggles.forEach { t ->
                reveal(t.tag)
                h.assertSwitchStop(screen, t.tag, on = true)
                h.assertTouchTarget(screen, t.tag)
                h.assertTextUnclipped(screen, t.tag, t.label, scale)
            }
            reveal(g.toggles.last().tag)
            val order = h.readingOrder("$screen-${g.title}", fresh = true)
            val stops = order.mapNotNull { s -> g.toggles.firstOrNull { it.matches(s) }?.label }
            assertTrue("$screen: ${g.title} switches are stops in $order", stops.isNotEmpty())
            assertEquals("$screen: ${g.title} switches, each one stop, in sheet order in $order", g.toggles.map { it.label }.filter { it in stops }, stops)
            val header = order.indexOfFirst { g.isHeader(it) }
            val first = order.indexOfFirst { s -> g.toggles.any { it.matches(s) } }
            if (header >= 0) assertTrue("$screen: ${g.title} header before its switches in $order", header < first)
        }
        h.assertNothingStraddles("fst.songs.filter", FORM, "fst.songs.filter.done", "fst.songs.filter.reset", *groups.map { it.tag }.toTypedArray())
    }

    /**
     * With every group open: switch rows read Off when turned off, Clear All / Select All flip
     * a group's switches, the Filter button speaks the applied group, saved groups reopen
     * expanded, and Reset turns everything back on.
     *
     * @param screen Log prefix.
     */
    private fun assertStateChanges(screen: String) {
        reveal("fst.songs.filter.year.2020")
        h.tap("fst.songs.filter.year.2020")
        h.assertSwitchStop("$screen-year-off", "fst.songs.filter.year.2020", on = false)
        h.assertSwitchStop("$screen-year-off", "fst.songs.filter.year.2010", on = true)
        reveal("fst.songs.filter.year.clear-all")
        h.tap("fst.songs.filter.year.clear-all")
        listOf(2010, 2020).forEach { h.assertSwitchStop("$screen-year-clear", "fst.songs.filter.year.$it", on = false) }
        h.tap("fst.songs.filter.year.select-all")
        listOf(2010, 2020).forEach { h.assertSwitchStop("$screen-year-select", "fst.songs.filter.year.$it", on = true) }
        for (tag in listOf("fst.songs.filter.duration.3", "fst.songs.filter.shop-unavailable")) {
            reveal(tag)
            h.tap(tag)
            h.assertSwitchStop("$screen-off", tag, on = false)
            h.tap(tag)
            h.assertSwitchStop("$screen-on", tag, on = true)
        }
        // Double Bass Support only: the unsupported and unknown songs leave the list.
        reveal("fst.songs.filter.double-bass.unsupported")
        h.tap("fst.songs.filter.double-bass.unsupported")
        h.assertSwitchStop("$screen-double-bass-off", "fst.songs.filter.double-bass.unsupported", on = false)
        h.assertSwitchStop("$screen-double-bass-off", "fst.songs.filter.double-bass.supported", on = true)
        h.readingOrder("$screen-double-bass-off", fresh = true)
        h.waitGone("fst.songs.row.s-beta")
        h.waitGone("fst.songs.row.s-gamma")
        closeSheet()
        h.waitForTag("fst.songs.row.s-alpha")
        assertEquals("Filters on: Double Bass", filterButtonState())
        h.readingOrder("$screen-filtered", fresh = true)

        openSheet()
        assertHeaderState("fst.songs.filter.double-bass", expanded = true)
        listOf("fst.songs.filter.year", "fst.songs.filter.duration", "fst.songs.filter.shop").forEach { assertHeaderState(it, expanded = false) }
        reveal("fst.songs.filter.reset")
        h.tap("fst.songs.filter.reset")
        reveal("fst.songs.filter.double-bass.unsupported")
        h.assertSwitchStop("$screen-reset", "fst.songs.filter.double-bass.unsupported", on = true)
        closeSheet()
        assertEquals("No filters", filterButtonState())
        h.waitForTag("fst.songs.row.s-beta")
    }

    // endregion

    /** Device text size: Filter button, sheet order, headers, switches, targets, then state changes and Reset. */
    @Test
    @DeviceCi
    fun anonymousFilterSheetReadsInOrderWithStatesAndTargets() {
        launch()
        val scale = rule.activity.resources.configuration.fontScale
        assertSheetAtRest("songs-filter-general")
        assertGroups("songs-filter-general", scale)
        assertStateChanges("songs-filter-general")
        h.assertAccessible()
    }

    /** 200% system text: the sheet's text grows unclipped, stops stay 48 dp and in order, actions stay reachable. */
    @Test
    @DeviceCi
    @SystemFontScale(2f)
    fun anonymousFilterSheetAtDoubleTextKeepsOrderTargetsAndUnclippedText() {
        launch()
        assertEquals(2f, rule.activity.resources.configuration.fontScale, 0.01f)
        assertSheetAtRest("songs-filter-general-2x")
        assertGroups("songs-filter-general-2x", scale = 2f)
        assertStateChanges("songs-filter-general-2x")
        h.assertAccessible()
    }

    /**
     * One switch row.
     *
     * @property tag Row test tag.
     * @property label Visible label.
     */
    private data class Toggle(val tag: String, val label: String) {
        /**
         * Whether a reading-order label is this row's stop (label, then state).
         *
         * @param spoken Spoken label.
         * @return True for this row.
         */
        fun matches(spoken: String): Boolean = spoken == label || spoken.startsWith("$label,")
    }

    /**
     * One collapsible General group.
     *
     * @property tag Header test tag.
     * @property title Header title.
     * @property toggles Switch rows in sheet order.
     * @property bulk Whether the group has Select All / Clear All.
     */
    private data class Group(val tag: String, val title: String, val toggles: List<Toggle>, val bulk: Boolean) {
        /**
         * Whether a reading-order label is this group's header stop (title and expansion state).
         *
         * @param spoken Spoken label.
         * @return True for the header.
         */
        fun isHeader(spoken: String): Boolean = spoken.startsWith(title) && ("Collapsed" in spoken || "Expanded" in spoken)
    }

    private companion object {
        const val FORM = "fst.songs.filter.form"
        val PUBLICATION = mapOf("X-FST-Publication-Id" to "7")
    }
}
