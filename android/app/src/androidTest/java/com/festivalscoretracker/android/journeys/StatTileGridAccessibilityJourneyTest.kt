package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.toSize
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Tracker issue #591 (pattern `stat-tile-grid`): the Statistics stat tile grids on the device,
 * at 100% and then 200% text in place. In every grid (overview and each instrument) all tiles
 * are one height, each covers whole slots (a tile whose text would wrap in one slot spans
 * two), rows before the last have no empty slot, and the tiles' visual order is their source
 * order. TalkBack reads the visible tiles as one stop each ("Label: value") in that order,
 * each at least 48 dp tall; ATF runs on every step.
 *
 * Fixtures only; `android-device` runs the class (`@DeviceCi`). Locally:
 * `device.py test com.festivalscoretracker.android.journeys.StatTileGridAccessibilityJourneyTest --avd FST_Phone`;
 * reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class StatTileGridAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    /** One tile as laid out: its tag, unclipped bounds in the window and spoken description. */
    private data class Tile(val tag: String, val box: Rect, val description: String)

    @Test
    fun statTilesKeepOneHeightAndWholeSlotsAtDefaultAndDoubleText() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        val transport = FakeTransport.standard().apply {
            on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            ProfileFixtures.register(this)
        }
        h.launch(DebugLaunch(section = FestivalSection.Statistics, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true), transport, fontScale = { scale })
        h.waitForTag("fst.player.available")
        h.waitForTag(OVERVIEW_PREFIX + "songs-played")
        checkGrids("statistics 1.0x")

        scale = 2f
        rule.waitForIdle()
        h.waitForTag(OVERVIEW_PREFIX + "songs-played")
        checkGrids("statistics 2.0x", fresh = true)
        h.assertAccessible()
    }

    /**
     * Check every stat grid on the page and TalkBack's stops for the visible tiles.
     *
     * @param screen Log name.
     * @param fresh Drop the accessibility node cache first (after the in-place text change).
     */
    private fun checkGrids(screen: String, fresh: Boolean = false) {
        val grids = tiles().groupBy { it.tag.removePrefix(PREFIX).substringBefore('.') }
        assertTrue("$screen: the overview grid is shown: ${grids.keys}", "overview" in grids)
        grids.forEach { (scope, grid) -> checkGrid("$screen $scope", grid) }

        val stops = h.readingStops(screen, fresh).filter { it.id?.startsWith(PREFIX) == true }
        assertTrue("$screen: TalkBack reaches stat tiles", stops.isNotEmpty())
        val order = tiles().map { it.tag }
        val read = stops.mapNotNull { it.id }
        assertEquals("$screen: tiles read in grid order", read, order.filter { it in read })
        val min = with(rule.density) { 48.dp.toPx() } - 1
        stops.forEach { stop ->
            assertTrue("$screen: ${stop.id} reads its label and value: ${stop.label}", stop.label.contains(':'))
            // Partly scrolled-out tiles report only their visible part.
            if (stop.bounds.top > 0 && stop.bounds.bottom < rule.activity.window.decorView.height) {
                assertTrue("$screen: ${stop.id} is ${stop.bounds.height()} px tall, at least 48 dp", stop.bounds.height() >= min)
            }
        }
    }

    /**
     * One grid's rules: one height, whole-slot widths on equal columns, full rows before the
     * last, and visual order = source order.
     *
     * @param screen Log name.
     * @param grid The grid's tiles in source order.
     */
    private fun checkGrid(screen: String, grid: List<Tile>) {
        val boxes = grid.map { it.box }
        assertTrue("$screen: one tile height: $boxes", boxes.maxOf { it.height } - boxes.minOf { it.height } <= 1.5f)
        assertEquals("$screen: visual order is source order", grid.map { it.tag }, grid.sortedWith(compareBy({ it.box.top.toInt() }, { it.box.left })).map { it.tag })
        val left = boxes.minOf { it.left }
        val width = boxes.maxOf { it.right } - left
        val gap = with(rule.density) { 8.dp.toPx() }
        val columns = (1..4).firstOrNull { c ->
            val slot = (width - gap * (c - 1)) / c
            fun onSlot(x: Float) = (0..c).any { i -> abs(x - left - i * (slot + gap)) < 2f }
            boxes.all { box -> onSlot(box.left) && (1..c).any { k -> abs(box.width - (slot * k + gap * (k - 1))) < 2f } }
        }
        assertTrue("$screen: tiles cover whole slots of equal columns: $boxes", columns != null)
        val rows = grid.groupBy { it.box.top.toInt() }.toSortedMap().values.toList()
        rows.dropLast(1).forEach { row ->
            assertEquals("$screen: a row before the last has no empty slot: ${row.map { it.tag }}", width, row.maxOf { it.box.right } - row.minOf { it.box.left }, 2f)
        }
    }

    /** Every stat tile on the page, in composition (source) order, with unclipped bounds. */
    private fun tiles(): List<Tile> = rule.onAllNodes(androidx.compose.ui.test.SemanticsMatcher("stat tile") { node ->
        node.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(PREFIX) == true
    }).fetchSemanticsNodes().map { node ->
        Tile(
            node.config[SemanticsProperties.TestTag],
            Rect(node.positionInWindow, node.size.toSize()),
            node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString().orEmpty(),
        )
    }

    private companion object {
        const val PREFIX = "fst.player.tile."
        const val OVERVIEW_PREFIX = "fst.player.tile.overview."
    }
}
