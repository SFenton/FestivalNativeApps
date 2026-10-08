package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.text.TextLayoutResult
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.BucketHeaderFixtures
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility of the Songs bucket headers that issue #91 made transparent (Duration, Year and
 * the other Quick Links sorts; test backfill, issue #441). With no backing behind them, rows are
 * hidden above the pinned header's bottom edge by `pinnedHeaderEdgeFade`, a drawing-only mask; these
 * journeys pin that it changed nothing TalkBack sees: ATF stays clean at rest, pinned and with two
 * headers on screen; each header is one heading stop with its spoken label, read before its own
 * rows and after the previous section's; text at 200% grows unclipped in the same order; and the
 * app's Reduce Transparency, Increase Contrast and Reduce Motion (the scroll-edge R7 hard cut,
 * #308, #462) keep rows out from behind the pinned title. Fixture-only
 * ([BucketHeaderFixtures]); `device.py test com.festivalscoretracker.android.journeys.SongsBucketHeaderAccessibilityJourneyTest --avd FST_Phone`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class SongsBucketHeaderAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Helpers

    /**
     * Launch Songs in [sort] over the still artwork background.
     *
     * @param sort Saved sort mode (`Duration`, `Year`, …).
     * @param fontScale Font scale provider, or `null` for the device's.
     * @param hardEdge The app's hard-edge setting to turn on (Reduce Transparency, Increase
     *   Contrast or Reduce Motion; scroll-edge R7), or null.
     */
    private fun launch(sort: String, fontScale: (() -> Float)? = null, hardEdge: String? = null) {
        val preferences = mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to sort)
        if (hardEdge != null) preferences[booleanPreferencesKey(hardEdge)] = true
        h.launch(DebugLaunch(stillBackground = true), BucketHeaderFixtures.transport(), MemoryPreferences(preferences), fontScale)
        h.waitForTag("fst.songs.row.s-0")
    }

    private val isBucketHeader = SemanticsMatcher("Songs bucket header") {
        it.config.getOrNull(SemanticsProperties.TestTag).orEmpty().startsWith(HEADER_PREFIX)
    }

    private fun headers(): List<SemanticsNode> = rule.onAllNodes(isBucketHeader, useUnmergedTree = true).fetchSemanticsNodes()

    private fun listBounds(): Rect = rule.onNodeWithTag(LIST).fetchSemanticsNode().boundsInRoot

    private fun scrollTo(index: Int) {
        rule.onNodeWithTag(LIST).performScrollToIndex(index)
        rule.waitForIdle()
    }

    /**
     * Every composed header is a heading with a spoken label, its text is not clipped, and none is
     * a touch target (a header is not interactive, so it needs no 48 dp minimum).
     */
    private fun assertHeadersAreHeadings(what: String) {
        val nodes = headers()
        assertTrue("$what: a header is composed", nodes.isNotEmpty())
        nodes.forEach { node ->
            val tag = node.config[SemanticsProperties.TestTag]
            assertTrue("$what: $tag is a heading", node.config.contains(SemanticsProperties.Heading))
            assertFalse("$what: $tag has a spoken label", node.config.getOrNull(SemanticsProperties.ContentDescription).isNullOrEmpty())
            assertFalse("$what: $tag is not clickable", node.config.contains(SemanticsActions.OnClick))
            val layouts = mutableListOf<TextLayoutResult>()
            node.config.getOrNull(SemanticsActions.GetTextLayoutResult)?.action?.invoke(layouts)
            layouts.forEach { assertFalse("$what: $tag text is clipped", it.hasVisualOverflow) }
        }
    }

    /**
     * The list's reading order. Each header on screen is one TalkBack stop that speaks its label
     * once (the redrawn header layer adds no node). It is read before every shown row of its own
     * section and after every shown row of the section before it.
     *
     * TalkBack reads the list's stops in on-screen order: a real `talkback_walk.py` walk of
     * Duration on FST_Phone (live service, 2026-10-08) read "Under 1 Minute. Heading", its rows,
     * then "1 to 2 minutes. Heading" and its rows. [JourneyHarness.readingOrder] walks the raw tree,
     * where a `LazyColumn` places sticky headers after its items, so the stops are ordered by their
     * shown top here. A row's shown top is clipped to the pinned header's bottom edge, because
     * rows above that edge are hidden. A row wholly behind the pinned header is skipped.
     * Fixture song `s-n` (title "Song n") is in section `n / 10`, and sections follow [tokens].
     *
     * @param screen Reading-order log name.
     * @param tokens Bucket tokens in list order.
     * @return Spoken header labels in reading order.
     */
    private fun assertHeadersLeadTheirRows(screen: String, tokens: List<String>): List<String> {
        val list = listBounds()
        val shown = headers().filter { it.boundsInRoot.top >= list.top - 1 && it.boundsInRoot.bottom <= list.bottom }
        assertTrue("$screen: a header is on screen", shown.isNotEmpty())
        // The node cache trails a scroll or a font-scale switch, so read a fresh tree.
        val labels = h.readingOrder(screen, fresh = true)
        val stops = mutableListOf<Stop>()
        shown.forEach { node ->
            val tag = node.config[SemanticsProperties.TestTag]
            val section = tokens.indexOf(tag.substringAfterLast('.'))
            assertTrue("$screen: $tag is a known bucket", section >= 0)
            val spoken = node.config[SemanticsProperties.ContentDescription].joinToString(", ")
            val read = labels.filter { it == spoken || it.startsWith("$spoken, ") }
            assertEquals("$screen: \"$spoken\" is one TalkBack stop in $labels", 1, read.size)
            stops += Stop(node.boundsInRoot.top, section, spoken)
        }
        val pinnedBottom = shown.filter { abs(it.boundsInRoot.top - list.top) <= rule.density.density * 2 }
            .maxOfOrNull { it.boundsInRoot.bottom } ?: list.top
        rule.onAllNodes(isSongRow).fetchSemanticsNodes().forEach { row ->
            val bounds = row.boundsInRoot
            val song = row.config[SemanticsProperties.TestTag].substringAfterLast("s-").toInt()
            val top = maxOf(bounds.top, pinnedBottom)
            if (top >= minOf(bounds.bottom, list.bottom)) return@forEach
            assertTrue("$screen: song $song is read: $labels", labels.any { ROW_TITLE.find(it)?.groupValues?.get(1)?.toInt() == song })
            stops += Stop(top, song / BucketHeaderFixtures.SECTION_SIZE, null)
        }
        val order = stops.sortedWith(compareBy<Stop> { it.top }.thenBy { it.heading == null })
        assertTrue("$screen: rows are read: $labels", order.any { it.heading == null })
        order.forEachIndexed { position, stop ->
            if (stop.heading != null) return@forEachIndexed
            val headerAt = { section: Int -> order.indexOfFirst { it.heading != null && it.section == section } }
            headerAt(stop.section).takeIf { it >= 0 }?.let { assertTrue("$screen: section ${stop.section}'s header precedes its rows: $order", it < position) }
            headerAt(stop.section + 1).takeIf { it >= 0 }?.let { assertTrue("$screen: the next header follows section ${stop.section}'s rows: $order", it > position) }
        }
        return order.mapNotNull { it.heading }
    }

    /** One list stop: its shown top, section and, for a header, its spoken label. */
    private data class Stop(val top: Float, val section: Int, val heading: String?)

    private val isSongRow = SemanticsMatcher("Songs row") {
        it.config.getOrNull(SemanticsProperties.TestTag).orEmpty().startsWith("fst.songs.row.s-")
    }

    /** The header whose top sits on the list's top edge (pinned or at rest there). */
    private fun pinnedHeader(): SemanticsNode {
        val list = listBounds()
        return headers().first { abs(it.boundsInRoot.top - list.top) <= rule.density.density * 2 }
    }

    /**
     * Nothing shows behind the pinned header's empty trailing end: it matches the list's own start
     * padding at the same height, so its bare title never sits over a row's text or artwork.
     */
    private fun assertPinnedHeaderBare(what: String) {
        rule.waitForIdle()
        val header = pinnedHeader().boundsInRoot
        val list = listBounds()
        val pixels = rule.onRoot().captureToImage().toPixelMap()
        val y = header.center.y.toInt()
        val inside = pixels[header.right.toInt() - 2, y]
        val outside = pixels[(list.left + 4 * rule.density.density).toInt(), y]
        val diff = maxOf(abs(inside.red - outside.red), abs(inside.green - outside.green), abs(inside.blue - outside.blue))
        assertTrue("$what: the pinned header end $inside differs from the background $outside", diff <= TOLERANCE)
    }

    // endregion

    // region Journeys

    /**
     * Duration (the reported sort): ATF and reading order at rest, with a header pinned over
     * scrolled rows, and with the next header about to push it away.
     */
    @Test
    fun durationHeadersAreHeadingsReadBeforeTheirRows() {
        h.enableAccessibilityChecks()
        launch("Duration")
        h.waitForTag("$HEADER_PREFIX$DURATION.1to2")
        assertHeadersAreHeadings("Duration at rest")
        assertHeadersLeadTheirRows("songs-duration-rest", DURATION_TOKENS)
        scrollTo(5)
        assertTrue("the first header pins", pinnedHeader().config[SemanticsProperties.TestTag].endsWith("1to2"))
        assertHeadersAreHeadings("Duration pinned")
        assertHeadersLeadTheirRows("songs-duration-pinned", DURATION_TOKENS)
        scrollTo(BucketHeaderFixtures.SECTION_SIZE)
        val read = assertHeadersLeadTheirRows("songs-duration-handoff", DURATION_TOKENS)
        assertTrue("two headers are read during the handoff: $read", read.size >= 2)
        h.assertAccessible()
    }

    /**
     * Year at 200% text, switched in place: the headers grow, stay unclipped headings, keep their
     * reading order at rest and pinned, and ATF stays clean.
     */
    @Test
    fun yearHeadersGrowUnclippedAndKeepTheirOrderAtDoubleText() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        launch("Year", fontScale = { scale })
        val first = "$HEADER_PREFIX$YEAR.1970"
        h.waitForTag(first)
        val before = rule.onNodeWithTag(first, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.height
        scale = 2f
        rule.waitForIdle()
        val after = rule.onNodeWithTag(first, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.height
        // Android 14+ scales large text non-linearly, so a title grows by less than 2x.
        assertTrue("the header grows at 200% ($before -> $after px)", after >= before * 1.25f)
        assertHeadersAreHeadings("Year 200% at rest")
        assertHeadersLeadTheirRows("songs-year-200-rest", YEAR_TOKENS)
        scrollTo(BucketHeaderFixtures.SECTION_SIZE + 4)
        assertHeadersAreHeadings("Year 200% pinned")
        assertHeadersLeadTheirRows("songs-year-200-pinned", YEAR_TOKENS)
        h.assertAccessible()
    }

    /**
     * The app's Reduce Transparency (hard cut, no fade): the pinned title stays bare with no row
     * behind it, is still a heading read before its rows, and ATF stays clean.
     */
    @Test
    fun reduceTransparencyKeepsRowsOutFromBehindThePinnedHeading() =
        hardEdgeKeepsRowsOutFromBehindThePinnedHeading("Reduce Transparency", "songs-duration-less-transparency", SettingsRegistry.REDUCE_TRANSPARENCY)

    /** The app's Increase Contrast: the same hard cut as Reduce Transparency (scroll-edge R7, #308). */
    @Test
    fun increaseContrastKeepsRowsOutFromBehindThePinnedHeading() =
        hardEdgeKeepsRowsOutFromBehindThePinnedHeading("Increase Contrast", "songs-duration-more-contrast", SettingsRegistry.INCREASE_CONTRAST)

    /** The app's Reduce Motion: the same hard cut, so no ramp grows while scrolling (scroll-edge R7, #308). */
    @Test
    fun reduceMotionKeepsRowsOutFromBehindThePinnedHeading() =
        hardEdgeKeepsRowsOutFromBehindThePinnedHeading("Reduce Motion", "songs-duration-reduce-motion", SettingsRegistry.REDUCE_MOTION)

    /**
     * One hard-edge setting: the pinned title stays bare with no row behind it, is still a
     * heading read before its rows, and ATF stays clean.
     *
     * @param what Setting name for failure messages.
     * @param screen Reading-order log name.
     * @param setting Settings key turned on.
     */
    private fun hardEdgeKeepsRowsOutFromBehindThePinnedHeading(what: String, screen: String, setting: String) {
        h.enableAccessibilityChecks()
        launch("Duration", hardEdge = setting)
        h.waitForTag("$HEADER_PREFIX$DURATION.1to2")
        scrollTo(5)
        assertPinnedHeaderBare("$what pinned")
        assertHeadersAreHeadings("$what pinned")
        assertHeadersLeadTheirRows(screen, DURATION_TOKENS)
        h.assertAccessible()
    }

    // endregion

    private companion object {
        const val LIST = "fst.songs.list"
        const val HEADER_PREFIX = "fst.songs.section."
        const val DURATION = "duration"
        const val YEAR = "year"
        val DURATION_TOKENS = listOf("1to2", "2to3", "3to4", "4to5")
        val YEAR_TOKENS = listOf("1970", "1980", "1990", "2000")

        /** A song row's spoken title, "Song n". */
        val ROW_TITLE = Regex("""\bSong (\d+)\b""")

        /** Largest channel difference (of 1.0) between the header end and the background. */
        const val TOLERANCE = 0.03f
    }
}
