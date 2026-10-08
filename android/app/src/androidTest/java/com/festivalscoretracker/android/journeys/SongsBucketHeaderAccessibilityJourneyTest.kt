package com.festivalscoretracker.android.journeys

import android.os.Build
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.PixelMap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.BucketHeaderFixtures
import kotlin.math.abs
import kotlin.math.roundToInt
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
 * app's Reduce Transparency keeps rows out from behind the pinned title. The section push (issue
 * #288; test backfill, issue #452): while the next header slides through the edge band and pushes
 * the pinned one out, both ways, with the fade, the hard cut and at 200% text, both stay opaque
 * headings that TalkBack reads once each, in order. Fixture-only
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
     * @param lessTransparency The app's Reduce Transparency setting.
     */
    private fun launch(sort: String, fontScale: (() -> Float)? = null, lessTransparency: Boolean = false) {
        val preferences = mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to sort)
        if (lessTransparency) preferences[booleanPreferencesKey(SettingsRegistry.REDUCE_TRANSPARENCY)] = true
        h.launch(DebugLaunch(stillBackground = true), BucketHeaderFixtures.transport(), MemoryPreferences(preferences), fontScale)
        h.waitForTag("fst.songs.row.s-0")
    }

    private val isBucketHeader = SemanticsMatcher("Songs bucket header") {
        it.config.getOrNull(SemanticsProperties.TestTag).orEmpty().startsWith(HEADER_PREFIX) && isLive(it)
    }

    /**
     * A placed, active node. After small scrolls the lazy list keeps a scrolled-out item's node
     * for reuse with its last bounds (it can overlap live rows); TalkBack's tree leaves it out.
     */
    private fun isLive(node: SemanticsNode): Boolean = node.layoutInfo.isPlaced && !node.layoutInfo.isDeactivated

    /** Runs a device shell command (system settings) and returns its trimmed output. */
    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).bufferedReader().readText().trim()
        }

    private fun headers(): List<SemanticsNode> = rule.onAllNodes(isBucketHeader, useUnmergedTree = true).fetchSemanticsNodes()

    private fun listBounds(): Rect = rule.onNodeWithTag(LIST).fetchSemanticsNode().boundsInRoot

    /**
     * The part of the list whose rows TalkBack's tree exposes: Compose leaves out a row that has
     * only reached the list's bottom content padding ([LIST_BOTTOM_PADDING_DP]; the shell adds
     * none above the navigation bar), and TalkBack scrolls forward to reach it.
     */
    private fun shownListBounds(): Rect {
        val list = listBounds()
        return list.copy(bottom = list.bottom - LIST_BOTTOM_PADDING_DP * rule.density.density)
    }

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
        val list = shownListBounds()
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
            assertTrue("$screen: song $song (shown ${top}..${minOf(bounds.bottom, list.bottom)} of list ${list.top}..${list.bottom}) is read: $labels", labels.any { ROW_TITLE.find(it)?.groupValues?.get(1)?.toInt() == song })
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
        it.config.getOrNull(SemanticsProperties.TestTag).orEmpty().startsWith(ROW_PREFIX) && isLive(it)
    }

    /**
     * Moves the list's content by [dy] px (positive scrolls toward the end), as TalkBack's scroll
     * actions do.
     */
    private fun scrollBy(dy: Float) {
        rule.onNodeWithTag(LIST).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, dy) }
        rule.waitForIdle()
        awaitTalkBackRows()
    }

    /**
     * Waits up to 5 s until TalkBack's tree shows the song rows on screen as visible and no row
     * that has left it: Compose refreshes that tree on a throttled loop after a scroll, which
     * `waitForIdle` does not wait for. A row that never appears still fails the reading-order
     * assertions that follow, with their details.
     */
    private fun awaitTalkBackRows() {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val list = shownListBounds()
        val extent = { node: SemanticsNode -> minOf(node.boundsInRoot.bottom, list.bottom) - maxOf(node.boundsInRoot.top, list.top) }
        val rows = rule.onAllNodes(isSongRow).fetchSemanticsNodes()
        val shown = rows.filter { extent(it) >= 1f }.map { it.config[SemanticsProperties.TestTag] }.toSet()
        val onScreen = rows.filter { extent(it) > 0f }.map { it.config[SemanticsProperties.TestTag] }.toSet()
        fun visible(node: AccessibilityNodeInfo?, into: MutableSet<String> = mutableSetOf()): Set<String> {
            node ?: return into
            node.viewIdResourceName?.takeIf { node.isVisibleToUser && it.startsWith(ROW_PREFIX) }?.let(into::add)
            for (i in 0 until node.childCount) visible(node.getChild(i), into)
            return into
        }
        runCatching {
            rule.waitUntil(5_000) {
                if (Build.VERSION.SDK_INT >= 34) automation.clearCache()
                val seen = visible(automation.rootInActiveWindow)
                seen.containsAll(shown) && onScreen.containsAll(seen)
            }
        }
    }

    private fun header(tag: String): SemanticsNode =
        rule.onAllNodes(hasTestTag(tag), useUnmergedTree = true).fetchSemanticsNodes().first(::isLive)

    /**
     * The brightest luminance in each pixel row of [bounds] (white title glyphs reach about 1;
     * rows with no glyph show only the dark page behind the transparent header). Rows outside
     * the image read 0.
     */
    private fun rowInk(pixels: PixelMap, bounds: Rect): List<Float> {
        val left = bounds.left.toInt().coerceAtLeast(0)
        val right = bounds.right.toInt().coerceAtMost(pixels.width)
        val top = bounds.top.roundToInt()
        return (0 until bounds.height.roundToInt()).map { row ->
            val y = top + row
            if (y !in 0 until pixels.height || left >= right) 0f else (left until right).maxOf { x -> pixels[x, y].luminance() }
        }
    }

    /**
     * The header's title is drawn whole and fully opaque: every pixel row that carries glyph ink
     * in [reference] (the same header drawn by itself, with no edge) still does, wherever the
     * header is shown below [visibleFrom] (the list's top edge). Before issue #288 the incoming
     * header faded inside the ramp and its part above the cut was cleared, so those rows read as
     * the dark page instead of the white title (text contrast lost mid-push).
     */
    private fun assertTitleOpaque(what: String, pixels: PixelMap, bounds: Rect, reference: List<Float>, visibleFrom: Float) {
        // Semantics bounds are clipped to the list, so a header pushed above it is placed by its bottom edge.
        val placed = bounds.copy(top = bounds.bottom - reference.size)
        val now = rowInk(pixels, placed)
        val top = placed.top.roundToInt()
        var checked = 0
        for (row in 1 until minOf(reference.size, now.size) - 1) {
            if (top + row < visibleFrom || (row - 1..row + 1).any { reference[it] < INK }) continue
            checked++
            assertTrue("$what: title row $row drew at luminance ${"%.2f".format(now[row])}, alone ${"%.2f".format(reference[row])}", now[row] >= INK - INK_TOLERANCE)
        }
        if (placed.top >= visibleFrom) assertTrue("$what: no title row was on screen to check", checked > 0)
    }

    /**
     * Steps the next section's header ([incoming]) from below the ramp, through the edge band and
     * over the pinned header ([outgoing]) until it pins, then back down (issue #288). The rows are
     * scrolled under [outgoing] the whole time, so the cut and ramp are active. At every step:
     * both headers stay headings with spoken, unclipped labels; each is one TalkBack stop (the
     * redrawn header layer adds no node); [outgoing] is read before [incoming] and each before its
     * own rows; both titles render fully opaque; and ATF stays clean.
     *
     * @param screen Reading-order log prefix.
     * @param outgoing Tag of the header pinned at the start (section 0).
     * @param incoming Tag of the next header (section 1, list item [SECTION_ONE_HEADER]).
     * @param tokens Bucket tokens in list order.
     */
    private fun assertPushIsAccessible(screen: String, outgoing: String, incoming: String, tokens: List<String>) {
        val list = listBounds()
        // Small in-place scrolls: publish what TalkBack sees so the tree tracks every step.
        h.publishTalkBackTree()
        val outgoingAlone = rowInk(rule.onRoot().captureToImage().toPixelMap(), header(outgoing).boundsInRoot)
        // The next header pinned with its first row right below: no edge, so it draws by itself.
        scrollTo(SECTION_ONE_HEADER)
        val pinned = header(incoming).boundsInRoot
        assertEquals("$incoming pins at the list top", list.top, pinned.top, rule.density.density * 2)
        val incomingAlone = rowInk(rule.onRoot().captureToImage().toPixelMap(), pinned)
        val height = pinned.height
        // From below the band (1.5 header heights down) to almost pinned, then back.
        val steps = listOf(1.5f, 1.0f, 0.75f, 0.5f, 0.25f, 0.5f, 1.0f, 1.5f)
        var at = 0f
        steps.forEachIndexed { index, step ->
            scrollBy((at - step) * height)
            at = step
            val name = "$screen-push-$index"
            val now = header(incoming).boundsInRoot
            assertEquals("$name: $incoming sits ${step}x its height down", list.top + step * height, now.top, rule.density.density * 2)
            assertHeadersAreHeadings(name)
            val read = assertHeadersLeadTheirRows(name, tokens)
            val incomingSpoken = header(incoming).config[SemanticsProperties.ContentDescription].joinToString(", ")
            assertTrue("$name: the incoming header is read: $read", incomingSpoken in read)
            val out = rule.onAllNodes(hasTestTag(outgoing), useUnmergedTree = true).fetchSemanticsNodes().firstOrNull(::isLive)
            val pixels = rule.onRoot().captureToImage().toPixelMap()
            assertTitleOpaque("$name incoming", pixels, now, incomingAlone, list.top)
            if (out != null && out.boundsInRoot.bottom > list.top + 1) {
                val outBounds = out.boundsInRoot
                assertTrue("$name: $outgoing is pushed up by $incoming, not overlapped", outBounds.bottom <= now.top + rule.density.density * 2)
                val spoken = out.config[SemanticsProperties.ContentDescription].joinToString(", ")
                val labels = h.readingOrder("$name-outgoing", fresh = true)
                assertEquals("$name: \"$spoken\" is one TalkBack stop in $labels", 1, labels.count { it == spoken || it.startsWith("$spoken, ") })
                assertTitleOpaque("$name outgoing", pixels, outBounds, outgoingAlone, list.top)
            }
        }
        h.assertAccessible()
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
    fun reduceTransparencyKeepsRowsOutFromBehindThePinnedHeading() {
        h.enableAccessibilityChecks()
        launch("Duration", lessTransparency = true)
        h.waitForTag("$HEADER_PREFIX$DURATION.1to2")
        scrollTo(5)
        assertPinnedHeaderBare("Reduce Transparency pinned")
        assertHeadersAreHeadings("Reduce Transparency pinned")
        assertHeadersLeadTheirRows("songs-duration-less-transparency", DURATION_TOKENS)
        h.assertAccessible()
    }

    /**
     * The section push with the fade on (system animations on, the default; issue #288): the next
     * Duration header slides up through the band and pushes the pinned one out, both ways, as two
     * opaque headings read in order.
     */
    @Test
    fun durationPushKeepsBothHeadingsOpaqueAndInOrder() {
        val saved = shell("settings get global animator_duration_scale")
        shell("settings put global animator_duration_scale 1")
        try {
            h.enableAccessibilityChecks()
            launch("Duration")
            h.waitForTag("$HEADER_PREFIX$DURATION.1to2")
            assertPushIsAccessible("songs-duration-fade", "$HEADER_PREFIX$DURATION.1to2", "$HEADER_PREFIX$DURATION.2to3", DURATION_TOKENS)
        } finally {
            shell(if (saved == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $saved")
        }
    }

    /** The section push at 200% text: taller headers push each other the same way, unclipped and in order. */
    @Test
    fun yearPushKeepsBothHeadingsOpaqueAndInOrderAtDoubleText() {
        h.enableAccessibilityChecks()
        launch("Year", fontScale = { 2f })
        h.waitForTag("$HEADER_PREFIX$YEAR.1970")
        assertPushIsAccessible("songs-year-200", "$HEADER_PREFIX$YEAR.1970", "$HEADER_PREFIX$YEAR.1980", YEAR_TOKENS)
    }

    /** The section push under the app's Reduce Transparency (hard cut, no ramp): the same guarantees. */
    @Test
    fun reduceTransparencyPushKeepsBothHeadingsOpaqueAndInOrder() {
        h.enableAccessibilityChecks()
        launch("Duration", lessTransparency = true)
        h.waitForTag("$HEADER_PREFIX$DURATION.1to2")
        assertPushIsAccessible("songs-duration-hard", "$HEADER_PREFIX$DURATION.1to2", "$HEADER_PREFIX$DURATION.2to3", DURATION_TOKENS)
    }

    // endregion

    private companion object {
        const val LIST = "fst.songs.list"

        /** The Songs list's bottom content padding in dp (`SongsScreen`, over a zero shell inset). */
        const val LIST_BOTTOM_PADDING_DP = 16f
        const val HEADER_PREFIX = "fst.songs.section."
        const val ROW_PREFIX = "fst.songs.row.s-"
        const val DURATION = "duration"
        const val YEAR = "year"
        val DURATION_TOKENS = listOf("1to2", "2to3", "3to4", "4to5")
        val YEAR_TOKENS = listOf("1970", "1980", "1990", "2000")

        /** A song row's spoken title, "Song n". */
        val ROW_TITLE = Regex("""\bSong (\d+)\b""")

        /** Largest channel difference (of 1.0) between the header end and the background. */
        const val TOLERANCE = 0.03f

        /** List index of section 1's header: section 0's header and its rows come first. */
        const val SECTION_ONE_HEADER = BucketHeaderFixtures.SECTION_SIZE + 1

        /** Luminance of a row carrying white title glyphs (the page behind is dark). */
        const val INK = 0.85f

        /** How far a title row may dim from [INK] and still count as fully opaque. */
        const val INK_TOLERANCE = 0.15f
    }
}
