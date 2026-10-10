package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.espresso.Espresso
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility journeys over the Songs area: Songs with its Sort/Filter sheets, Song Detail
 * (band previews, Quick Links), the full song board, Paths, Item Shop and Suggestions. ATF runs
 * on every screen and interaction; reading orders go to logcat `FST_A11Y`
 * (`device.py test com.festivalscoretracker.android.journeys.SongsAccessibilityJourneyTest --avd …`).
 */
@RunWith(AndroidJUnit4::class)
class SongsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val transport = BandFixtures.install(
        FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
            on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
            ProfileFixtures.register(this)
        },
    )

    @Test
    fun songsListSortAndFilter() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        h.readingOrder("songs")
        h.tap("fst.songs.sort.open")
        h.waitForTag("fst.songs.sort")
        h.readingOrder("songs-sort")
        Espresso.pressBack()
        h.waitGone("fst.songs.sort")
        h.tap("fst.songs.filter.open")
        h.waitForTag("fst.songs.filter")
        h.readingOrder("songs-filter")
        h.assertAccessible()
    }

    /**
     * Songs Filter with every section expanded (issue #126): ATF over the score toggles,
     * Selected Instrument Filters and bucket groups, and no part of the sheet across a
     * separating hinge (run with `--avd FST_Book_Fold --posture half` for the hinge check).
     */
    @Test
    fun songsFilterExpandedSectionsStayAccessibleAndClearOfTheHinge() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        h.tap("fst.songs.filter.open")
        h.waitForTag("fst.songs.filter.form")
        h.assertNothingStraddles("fst.songs.filter", "fst.songs.filter.form", "fst.songs.filter.done", "fst.songs.filter.reset")
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.shop")
        h.tap("fst.songs.filter.shop")
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.global")
        h.tap("fst.songs.filter.global")
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.score.chart.Solo_Guitar")
        h.tap("fst.songs.filter.score.chart.Solo_Guitar")
        h.readingOrder("songs-filter-score")
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.instrument")
        h.tap(if (h.exists("fst.songs.filter.instrument.preview")) "fst.songs.filter.instrument.preview" else "fst.songs.filter.instrument.Solo_Guitar")
        h.waitForTag("fst.songs.filter.stars")
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.stars")
        h.tap("fst.songs.filter.stars")
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.stars.6")
        h.readingOrder("songs-filter-instrument")
        h.assertNothingStraddles("fst.songs.filter", "fst.songs.filter.form", "fst.songs.filter.stars.6")
        h.tap("fst.songs.filter.done")
        h.waitGone("fst.songs.filter.form")
        h.waitForTag("fst.songs.filter.open")
        h.assertAccessible()
    }

    /**
     * Songs Filter without a profile (issue #181): only General, every group expanded, ATF over
     * the bucket switches and Select All / Clear All, nothing across a separating hinge
     * (`--posture half`), and the Filter button speaking its applied state.
     */
    @Test
    fun anonymousFilterShowsOnlyGeneralAndSpeaksItsState() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        rule.onNodeWithTag("fst.songs.filter.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "No filters"))
        h.tap("fst.songs.filter.open")
        h.waitForTag("fst.songs.filter.general")
        assertEquals(0, rule.onAllNodesWithTag("fst.songs.filter.score-sections").fetchSemanticsNodes().size)
        for (group in listOf("fst.songs.filter.year", "fst.songs.filter.duration", "fst.songs.filter.shop", "fst.songs.filter.double-bass")) {
            h.scrollTo("fst.songs.filter.form", group)
            h.tap(group)
        }
        h.scrollTo("fst.songs.filter.form", "fst.songs.filter.double-bass.unsupported")
        h.tap("fst.songs.filter.double-bass.unsupported")
        h.readingOrder("songs-filter-anonymous")
        h.assertNothingStraddles("fst.songs.filter", "fst.songs.filter.form", "fst.songs.filter.done", "fst.songs.filter.double-bass.supported")
        h.tap("fst.songs.filter.done")
        h.waitGone("fst.songs.filter.form")
        rule.onNodeWithTag("fst.songs.filter.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Filters on: Double Bass"))
        h.readingOrder("songs-filtered-anonymous")
        h.tap("fst.songs.filter.open")
        h.waitForTag("fst.songs.filter.reset")
        h.tap("fst.songs.filter.reset")
        h.tap("fst.songs.filter.done")
        h.waitGone("fst.songs.filter.form")
        h.assertAccessible()
    }

    /** Sort states on a device (issue #125): live mode/direction/Reset, Item Shop sections and the spoken sort state. */
    @Test
    fun songsSortStates() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.list")
        rule.onNodeWithTag("fst.songs.sort.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Title, ascending"))
        h.tap("fst.songs.sort.open")
        h.waitForTag("fst.songs.sort.form")
        h.tap("fst.songs.sort.artist")
        rule.onNodeWithTag("fst.songs.sort.artist").assertIsSelected()
        h.tap("fst.songs.sort.descending")
        rule.onNodeWithTag("fst.songs.sort.descending").assertIsSelected()
        h.readingOrder("songs-sort-changed")
        h.tap("fst.songs.sort.reset")
        rule.onNodeWithTag("fst.songs.sort.title").assertIsSelected()
        rule.onNodeWithTag("fst.songs.sort.ascending").assertIsSelected()
        h.tap("fst.songs.sort.shop")
        h.tap("fst.songs.sort.done")
        h.waitGone("fst.songs.sort.form")
        h.waitForTag("fst.songs.shop-section.leaving-tomorrow")
        rule.onNodeWithTag("fst.songs.sort.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Item Shop, ascending"))
        h.readingOrder("songs-sort-shop")
        h.assertAccessible()
    }

    /**
     * Instrument status chips (issue #134): ATF over Songs rows with chips (each row one ≥48 dp
     * button whose description speaks every chart's status in service order; the chips are not
     * separate stops), the chip group never across a separating hinge (`--posture half`), and the
     * same on the selected row of the two-pane layout when the window shows one.
     */
    @Test
    fun songsInstrumentStatusChipsReadAsOneRowSummary() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, stillBackground = true), transport)
        h.waitForTag("fst.songs.instrument-status.s-alpha")
        val order = h.readingOrder("songs-instrument-status")
        val alpha = order.firstOrNull { it.contains("Alpha Tune") }.orEmpty()
        assertTrue(order.joinToString("\n"), alpha.contains("Lead, full combo") && alpha.indexOf("Lead, full combo") < alpha.indexOf("Bass, scored"))
        assertTrue(order.joinToString("\n"), order.none { it.contains("fst.songs.instrument-status") })
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue(rule.onNodeWithTag("fst.songs.row.s-alpha").fetchSemanticsNode().size.height >= min)
        h.assertNothingStraddles("fst.songs.instrument-status.s-alpha", "fst.songs.instrument-status.s-beta", "fst.songs.instrument-status.s-gamma")
        h.tap("fst.songs.row.s-alpha")
        h.waitForTag("fst.song-detail.list")
        val selected = rule.onAllNodesWithTag("fst.songs.row.s-alpha").fetchSemanticsNodes()
            .any { it.config.getOrElseNullable(SemanticsProperties.Selected) { null } == true }
        if (selected) {
            h.readingOrder("songs-instrument-status-selected")
            h.assertNothingStraddles("fst.songs.instrument-status.s-alpha")
        }
        h.assertAccessible()
    }

    @Test
    fun songDetailBoardAndPaths() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), transport)
        h.waitForTag("fst.song-detail.list")
        h.waitForTag("fst.song-detail.intensity")
        h.readingOrder("song-detail")
        h.assertNothingStraddles("fst.song-detail.intensity", "fst.song-detail.history", "fst.song-detail.preview.Solo_Guitar")
        h.scrollTo("fst.song-detail.list", "fst.song-detail.band-preview.Band_Duets")
        h.readingOrder("song-detail-bands")
        h.tap("fst.quick-links.open")
        h.readingOrder("song-detail-quick-links")
        h.tap("fst.quick-links.item.intensity")
        h.tap("fst.song-detail.paths.open")
        h.waitForTag("fst.paths.difficulty.open")
        h.readingOrder("paths")
        if (h.exists("fst.paths.karaoke-warning")) {
            h.tap("fst.paths.warning.ok")
            h.waitGone("fst.paths.karaoke-warning")
            h.readingOrder("paths-sheet")
        }
        h.tap("fst.paths.close")
        h.waitGone("fst.paths.close")
        h.scrollTo("fst.song-detail.list", "fst.song-detail.view-all.Solo_Guitar")
        h.tap("fst.song-detail.view-all.Solo_Guitar")
        h.waitForTag("fst.song-leaderboard.list")
        h.readingOrder("song-leaderboard")
        h.assertAccessible()
    }

    /**
     * Issue #169: switching Score History from Lead (two scores) to Bass (one) keeps the card's
     * size on the device, selects Bass, drops to one best-score row and stays accessible.
     */
    @Test
    fun songDetailScoreHistorySwitchKeepsTheCardAndSelectsTheNewChart() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, songQuery = "s-alpha", stillBackground = true), transport)
        h.scrollTo("fst.song-detail.list", "fst.song-detail.history.card")
        h.waitForTag("fst.song-detail.history.top.1")
        fun card() = rule.onNodeWithTag("fst.song-detail.history.card").fetchSemanticsNode().size
        val before = card()
        h.readingOrder("song-detail-history-lead")
        val compact = h.exists("fst.song-detail.history.instrument.compact")
        h.tap(if (compact) "fst.song-detail.history.instrument.next" else "fst.song-detail.history.instrument.Solo_Bass")
        rule.waitUntil(5_000) { !h.exists("fst.song-detail.history.top.1") }
        rule.waitForIdle()
        assertEquals("Score History card size after the switch", before, card())
        val bass = if (compact) "fst.song-detail.history.instrument.preview" else "fst.song-detail.history.instrument.Solo_Bass"
        rule.onNodeWithTag(bass).assertIsSelected().assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Bass")))
        h.waitForTag("fst.song-detail.history.top.0")
        h.readingOrder("song-detail-history-bass")
        h.assertAccessible()
    }

    @Test
    @DeviceCi
    fun itemShop() {
        val offers = arrayOf("fst.shop.song.s-alpha", "fst.shop.song.s-x", "fst.shop.song.s-beta", "fst.shop.external.s-alpha", "fst.shop.external.s-beta")
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("shop"), profile = player, stillBackground = true), transport)
        rule.waitUntil(15_000) { h.exists("fst.shop.list") || h.exists("fst.shop.grid") }
        h.waitForTag("fst.shop.song.s-beta")
        h.readingOrder("shop")
        // Book posture (`device.py test … --posture half`): no card or row on the fold (issue #131).
        h.assertNothingStraddles(*offers)
        // Grid/List only switches on wide panes (compact phones always list).
        if (h.exists("fst.shop.view-toggle")) {
            h.tap("fst.shop.view-toggle")
            h.waitForTag("fst.shop.song.s-beta")
            h.readingOrder("shop-toggled")
            h.assertNothingStraddles(*offers)
        }
        rule.onNodeWithTag("fst.shop.filter.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "No filters"))
        h.tap("fst.shop.filter.open")
        h.waitForTag("fst.shop.filter.leaving")
        h.readingOrder("shop-filter")
        h.tap("fst.shop.filter.leaving")
        h.waitGone("fst.shop.song.s-alpha")
        h.tap("fst.shop.filter.done")
        h.waitGone("fst.shop.filter.leaving")
        h.readingOrder("shop-filtered")
        // Issue #145: TalkBack hears the active filters, not only the gold tint.
        rule.onNodeWithTag("fst.shop.filter.open").assert(SemanticsMatcher.expectValue(SemanticsProperties.StateDescription, "Filters on: hiding Leaving Tomorrow"))
        h.assertAccessible()
    }

    /**
     * Item Shop list rows are the Songs page's shared `SongRowCard` (issue #18; device backfill
     * #397). At 1.0× and again at 2.0× font scale, with ATF on every step: each row is one
     * clickable stop that reads its title, artist line and New / Leaving Tomorrow status and is
     * never "selected" (New is spoken only; the row draws no New label, issue #562); its cart link
     * is the next stop, a separate labelled button; rows read in
     * sort order; row and link are at least 48 × 48 dp and the title stays inside its row.
     */
    @Test
    @DeviceCi
    fun itemShopSharedSongRow() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = DebugLaunch.parseRoute("shop"), profile = player, stillBackground = true), transport, fontScale = { scale })
        rule.waitUntil(15_000) { h.exists("fst.shop.list") || h.exists("fst.shop.grid") }
        // Wide panes open on the grid; the shared row is the list.
        if (h.exists("fst.shop.grid")) h.tap("fst.shop.view-toggle")
        h.waitForTag("fst.shop.list")
        h.waitForTag("fst.shop.song.s-beta")
        val titleHeights = mutableListOf<Float>()
        for (fontScale in listOf(1f, 2f)) {
            scale = fontScale
            rule.waitForIdle()
            titleHeights += assertSharedShopRows("shop-shared-row-${fontScale}x")
        }
        assertTrue("2.0× text renders larger titles than 1.0× ($titleHeights)", titleHeights[1] > titleHeights[0] * 1.5f)
        h.assertAccessible()
    }

    /**
     * Assert the Item Shop rows' TalkBack contract and sizes at the current font scale.
     *
     * @param screen Reading-order log name.
     * @return The first row's title height in pixels, to prove the font scale applied.
     */
    private fun assertSharedShopRows(screen: String): Float {
        val minPx = with(rule.density) { 48.dp.toPx() } - 1
        // Title-ascending sort (ties by song ID): the fixture's three offers.
        val rows = listOf(
            ShopRowExpectation("s-alpha", "Alpha Tune", "Band One", "Leaving Tomorrow"),
            ShopRowExpectation("s-x", "Alpha Tune", "Other", null),
            ShopRowExpectation("s-beta", "Beta Song", "Band Two · 2019", "New"),
        )
        h.scrollTo("fst.shop.list", "fst.shop.song.${rows.first().id}")
        var previous = -1
        var firstTitleHeight = 0f
        rows.forEachIndexed { i, row ->
            val tag = "fst.shop.song.${row.id}"
            var order = h.readingOrder("$screen-${i + 1}", fresh = true)
            var at = order.indexOfFirst { row.matches(it) }
            if (at < 0) {
                h.scrollTo("fst.shop.list", "fst.shop.external.${row.id}")
                order = h.readingOrder("$screen-${i + 1}-scrolled", fresh = true)
                at = order.indexOfFirst { row.matches(it) }
                previous = -1
            }
            assertTrue("$screen: ${row.id} is a reading stop with its texts and badge in $order", at >= 0)
            assertTrue("$screen: ${row.id} reads after the previous offer", at > previous)
            previous = at
            assertEquals("$screen: the cart link is the stop right after ${row.id}", "Open ${row.title} in the Fortnite Item Shop", order.getOrNull(at + 1))
            val node = rule.onNodeWithTag(tag).fetchSemanticsNode()
            assertTrue("$screen: ${row.id} row is clickable", node.config.contains(SemanticsActions.OnClick))
            assertNull("$screen: single-pane rows are never selected", node.config.getOrNull(SemanticsProperties.Selected))
            assertNull("$screen: no hidden description repeats the texts", node.config.getOrNull(SemanticsProperties.ContentDescription))
            listOf(tag, "fst.shop.external.${row.id}").forEach { target ->
                val size = rule.onNodeWithTag(target, useUnmergedTree = true).fetchSemanticsNode().size
                assertTrue("$screen: $target is ${size.width}x${size.height} px, at least 48 dp", size.width >= minPx && size.height >= minPx)
            }
            val box = node.boundsInWindow
            val title = rule.onAllNodes(hasText(row.title) and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true).fetchSemanticsNodes().single().boundsInWindow
            assertTrue("$screen: ${row.id} title $title inside row $box", title.left >= box.left - 1 && title.top >= box.top - 1 && title.bottom <= box.bottom + 1 && title.right <= box.right + 1)
            if (i == 0) firstTitleHeight = title.height
            // Issue #562: New is spoken as the row's state but never drawn (web: gold outline only); Leaving Tomorrow stays visible.
            if (row.badge == "New") {
                assertTrue("$screen: ${row.id} draws no New label", rule.onAllNodesWithTag("fst.shop.badge.new.${row.id}", useUnmergedTree = true).fetchSemanticsNodes().isEmpty())
                assertEquals("$screen: ${row.id} state", "New", node.config.getOrNull(SemanticsProperties.StateDescription))
            } else if (row.badge != null) {
                val pill = rule.onNodeWithTag("fst.shop.badge.leaving.${row.id}", useUnmergedTree = true).fetchSemanticsNode().size
                assertTrue("$screen: ${row.id} shows its Leaving Tomorrow label", pill.width > 0 && pill.height > 0)
            }
        }
        return firstTitleHeight
    }

    /**
     * One expected Item Shop row.
     *
     * @property id Song ID.
     * @property title Title text.
     * @property subtitle Artist line.
     * @property badge Badge text, or null without a highlight.
     */
    private data class ShopRowExpectation(val id: String, val title: String, val subtitle: String, val badge: String?) {
        /**
         * Whether a reading-order label is this row's stop.
         *
         * @param label Spoken label.
         * @return True for this row.
         */
        fun matches(label: String): Boolean =
            !label.startsWith("Open ") && title in label && subtitle in label &&
                (badge == null || badge in label) && (badge != null || ("Leaving Tomorrow" !in label && "New" !in label))
    }

    @Test
    fun suggestions() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Suggestions, profile = player, stillBackground = true), transport)
        h.waitForTag("fst.suggestions.filter-button")
        h.readingOrder("suggestions")
        h.tap("fst.suggestions.filter-button")
        h.waitForTag("fst.suggestions.filter.form")
        h.readingOrder("suggestions-filter")
        h.assertAccessible()
    }
}
