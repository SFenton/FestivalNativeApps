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
import com.festivalscoretracker.android.testing.FakeTransport
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlinx.coroutines.runBlocking
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
 * #308, #462) keep rows out from behind the pinned title. The section push (issue #288; test
 * backfill, issue #452): while the next header slides through the edge band and pushes the pinned
 * one out, both ways, with the fade, at 200% text and with the hard cut each R7 setting forces on
 * its own (the app's Reduce Transparency, the app's Reduce Motion, the system's Remove
 * animations), both stay opaque headings that TalkBack reads once each, in order, and with the hard
 * cut no row shows behind the pinned title afterwards. The list end (issue #560): with short last
 * sections the last push finishes, leaving one whole pinned heading, read first, ATF clean, at
 * 100% and 200% text. Fixture-only
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
     * @return The app's settings store, to change a setting live.
     */
    private fun launch(
        sort: String,
        fontScale: (() -> Float)? = null,
        hardEdge: String? = null,
        transport: FakeTransport = BucketHeaderFixtures.transport(),
    ): MemoryPreferences {
        val preferences = mutablePreferencesOf(stringPreferencesKey(SettingsRegistry.SONG_SORT) to sort)
        if (hardEdge != null) preferences[booleanPreferencesKey(hardEdge)] = true
        val store = MemoryPreferences(preferences)
        h.launch(DebugLaunch(stillBackground = true), transport, store, fontScale)
        h.waitForTag("fst.songs.row.s-0")
        // From here readingOrder follows Compose's traversal links: TalkBack's order, not tree order.
        h.publishTalkBackTree()
        return store
    }

    /** Sets the app's boolean setting [key] in [store], live. */
    private fun MemoryPreferences.set(key: String, on: Boolean) {
        runBlocking { updateData { it.toMutablePreferences().apply { this[booleanPreferencesKey(key)] = on } } }
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

    /** Runs [body] with the system animator duration scale at [scale], then restores the saved one. */
    private fun withAnimatorScale(scale: String, body: () -> Unit) {
        val saved = shell("settings get global animator_duration_scale")
        shell("settings put global animator_duration_scale $scale")
        try {
            body()
        } finally {
            shell(if (saved == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $saved")
        }
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
     * then "1 to 2 minutes. Heading" and its rows. Both orders are checked: the stops ordered by
     * their shown top, and the same stops' positions in [JourneyHarness.readingOrder], which
     * [launch] made TalkBack's linear order ([JourneyHarness.publishTalkBackTree]; the raw tree
     * places a `LazyColumn`'s sticky headers after its items). A row's shown top is clipped to the
     * pinned header's bottom edge, because rows above that edge are hidden. A row wholly behind
     * the pinned header is skipped.
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
            stops += Stop(node.boundsInRoot.top, section, spoken, labels.indexOf(read.single()))
        }
        val pinnedBottom = shown.filter { abs(it.boundsInRoot.top - list.top) <= rule.density.density * 2 }
            .maxOfOrNull { it.boundsInRoot.bottom } ?: list.top
        rule.onAllNodes(isSongRow).fetchSemanticsNodes().forEach { row ->
            val bounds = row.boundsInRoot
            val song = row.config[SemanticsProperties.TestTag].substringAfterLast("s-").toInt()
            val top = maxOf(bounds.top, pinnedBottom)
            if (top >= minOf(bounds.bottom, list.bottom)) return@forEach
            val spoken = labels.indexOfFirst { ROW_TITLE.find(it)?.groupValues?.get(1)?.toInt() == song }
            assertTrue("$screen: song $song is read: $labels", spoken >= 0)
            stops += Stop(top, song / BucketHeaderFixtures.SECTION_SIZE, null, spoken)
        }
        val order = stops.sortedWith(compareBy<Stop> { it.top }.thenBy { it.heading == null })
        assertTrue("$screen: rows are read: $labels", order.any { it.heading == null })
        order.forEachIndexed { position, stop ->
            if (stop.heading != null) return@forEachIndexed
            val headerAt = { section: Int -> order.indexOfFirst { it.heading != null && it.section == section } }
            headerAt(stop.section).takeIf { it >= 0 }?.let { assertTrue("$screen: section ${stop.section}'s header precedes its rows: $order", it < position) }
            headerAt(stop.section + 1).takeIf { it >= 0 }?.let { assertTrue("$screen: the next header follows section ${stop.section}'s rows: $order", it > position) }
            // The same in TalkBack's linear order.
            val spokenAt = { section: Int -> order.firstOrNull { it.heading != null && it.section == section }?.spoken }
            spokenAt(stop.section)?.let { assertTrue("$screen: TalkBack reads section ${stop.section}'s header before its rows: $labels", it < stop.spoken) }
            spokenAt(stop.section + 1)?.let { assertTrue("$screen: TalkBack reads the next header after section ${stop.section}'s rows: $labels", it > stop.spoken) }
        }
        return order.mapNotNull { it.heading }
    }

    /**
     * One list stop.
     *
     * @property top Shown top in root px.
     * @property section Section index.
     * @property heading Spoken label, for a header.
     * @property spoken Position in TalkBack's linear order.
     */
    private data class Stop(val top: Float, val section: Int, val heading: String?, val spoken: Int)

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

    /**
     * The Duration push with the edge forced to a hard cut (Reduce Transparency, Reduce Motion or
     * system Remove animations; `rememberScrollEdgeHardEdge`): the push guarantees of
     * [assertPushIsAccessible], then, with the first header pinned again over scrolled rows, no row
     * shows behind it ([assertPinnedHeaderBare]) and the edge under it is the hard cut
     * ([assertEdgeIsHard]).
     *
     * @param screen Reading-order log prefix and failure label.
     * @param release Turns the setting that forces the hard cut off, live.
     * @param restore Turns it back on, live.
     */
    private fun assertHardEdgePushIsAccessible(screen: String, release: () -> Unit, restore: () -> Unit) {
        h.waitForTag("$HEADER_PREFIX$DURATION.1to2")
        assertPushIsAccessible(screen, "$HEADER_PREFIX$DURATION.1to2", "$HEADER_PREFIX$DURATION.2to3", DURATION_TOKENS)
        assertTrue("$screen: the first header pins again", pinnedHeader().config[SemanticsProperties.TestTag].endsWith("1to2"))
        assertPinnedHeaderBare("$screen after the push")
        assertEdgeIsHard(screen, release, restore)
    }

    /** Luminance of every pixel in the [EDGE_BAND_DP] band of rows right under the pinned header. */
    private fun edgeBand(): FloatArray {
        val header = pinnedHeader().boundsInRoot
        val list = listBounds()
        val pixels = rule.onRoot().captureToImage().toPixelMap()
        val top = header.bottom.roundToInt()
        val bottom = minOf(pixels.height, (header.bottom + EDGE_BAND_DP * rule.density.density).roundToInt())
        val left = list.left.toInt().coerceAtLeast(0)
        val right = list.right.toInt().coerceAtMost(pixels.width)
        return FloatArray((bottom - top) * (right - left)) { i -> pixels[left + i % (right - left), top + i / (right - left)].luminance() }
    }

    /** The largest luminance change of one pixel between two captures of the band. */
    private fun largestChange(a: FloatArray, b: FloatArray): Float = a.indices.maxOfOrNull { abs(a[it] - b[it]) } ?: 0f

    /**
     * The rows right under the pinned header are drawn at full opacity because the setting forces
     * the hard cut: with the first header pinned over scrolled rows, turning the setting off brings
     * back the 40 dp ramp (those rows dim) and turning it on again restores the same pixels. Proves
     * the push above ran with the hard edge (scroll-edge R7), not the fade.
     */
    private fun assertEdgeIsHard(screen: String, release: () -> Unit, restore: () -> Unit) {
        scrollTo(5)
        rule.waitForIdle()
        val hard = edgeBand()
        release()
        runCatching { rule.waitUntil(5_000) { largestChange(hard, edgeBand()) > EDGE_CHANGE } }
        val fade = edgeBand()
        assertTrue("$screen: releasing the setting brings the ramp back under the pinned header (largest pixel change ${largestChange(hard, fade)})", largestChange(hard, fade) > EDGE_CHANGE)
        restore()
        runCatching { rule.waitUntil(5_000) { largestChange(hard, edgeBand()) < EDGE_SAME } }
        assertTrue("$screen: restoring the setting brings the hard cut back (largest pixel change ${largestChange(hard, edgeBand())})", largestChange(hard, edgeBand()) < EDGE_SAME)
    }

    /**
     * Scrolls to the very end of the list as TalkBack's scroll-forward and a fling do, again once
     * the end space has been measured (issue #560), and waits for TalkBack's tree.
     */
    private fun scrollToEnd() {
        repeat(3) {
            rule.onNodeWithTag(LIST).performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, END_SCROLL_PX) }
            rule.waitForIdle()
        }
        awaitTalkBackRows()
    }

    /**
     * The list's end rest (issue #560, section-headers R4/R5): exactly one header sits at the
     * list's top edge, whole ([fullHeight] tall, not half pushed off) and opaque over no row, no
     * other header is cut by the top edge, and the last row is fully shown above the list's end
     * padding (reachable).
     *
     * @param what Failure label.
     * @param fullHeight A header's resting height in px at the current text size.
     * @param lastRow Tag of the list's last row.
     */
    private fun assertEndRestsWhole(what: String, fullHeight: Float, lastRow: String) {
        val list = listBounds()
        val slack = rule.density.density * 2
        val atTop = headers().filter { it.boundsInRoot.top <= list.top + slack && it.boundsInRoot.bottom > list.top + slack }
        assertEquals("$what: one header rests at the top edge: ${atTop.map { it.boundsInRoot }}", 1, atTop.size)
        val pinned = atTop.single().boundsInRoot
        assertEquals("$what: the pinned header is whole, not half pushed off", fullHeight, pinned.height, slack)
        val row = rule.onNodeWithTag(lastRow, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue("$what: the last row ($row) is fully shown above the end padding", row.bottom <= list.bottom - LIST_BOTTOM_PADDING_DP * rule.density.density + slack)
        assertTrue("$what: the last row is below the pinned header", row.top >= pinned.bottom - slack)
        assertPinnedHeaderBare("$what at the end")
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

    /**
     * The section push with the fade on (system animations on, the default; issue #288): the next
     * Duration header slides up through the band and pushes the pinned one out, both ways, as two
     * opaque headings read in order.
     */
    @Test
    fun durationPushKeepsBothHeadingsOpaqueAndInOrder() = withAnimatorScale("1") {
        h.enableAccessibilityChecks()
        launch("Duration")
        h.waitForTag("$HEADER_PREFIX$DURATION.1to2")
        assertPushIsAccessible("songs-duration-fade", "$HEADER_PREFIX$DURATION.1to2", "$HEADER_PREFIX$DURATION.2to3", DURATION_TOKENS)
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
    fun reduceTransparencyPushKeepsBothHeadingsOpaqueAndInOrder() = withAnimatorScale("1") {
        h.enableAccessibilityChecks()
        val store = launch("Duration", hardEdge = SettingsRegistry.REDUCE_TRANSPARENCY)
        assertHardEdgePushIsAccessible(
            "songs-duration-hard",
            release = { store.set(SettingsRegistry.REDUCE_TRANSPARENCY, false) },
            restore = { store.set(SettingsRegistry.REDUCE_TRANSPARENCY, true) },
        )
    }

    /**
     * The section push under the app's Reduce Motion with system animations on: Reduce Motion
     * alone makes the edge a hard cut (scroll-edge R7), and the push keeps the same guarantees.
     */
    @Test
    fun reduceMotionPushKeepsBothHeadingsOpaqueAndInOrder() = withAnimatorScale("1") {
        h.enableAccessibilityChecks()
        val store = launch("Duration", hardEdge = SettingsRegistry.REDUCE_MOTION)
        assertHardEdgePushIsAccessible(
            "songs-duration-reduce-motion",
            release = { store.set(SettingsRegistry.REDUCE_MOTION, false) },
            restore = { store.set(SettingsRegistry.REDUCE_MOTION, true) },
        )
    }

    /**
     * The section push with the system's Remove animations (animator scale 0) and no app setting:
     * the system preference alone makes the hard cut (scroll-edge R7), with the same guarantees.
     */
    @Test
    fun removeAnimationsPushKeepsBothHeadingsOpaqueAndInOrder() = withAnimatorScale("0") {
        h.enableAccessibilityChecks()
        launch("Duration")
        assertHardEdgePushIsAccessible(
            "songs-duration-remove-animations",
            release = { shell("settings put global animator_duration_scale 1") },
            restore = { shell("settings put global animator_duration_scale 0") },
        )
    }

    /**
     * The list end with short last sections (issue #560): on a phone the last scroll position
     * falls inside the push of the second Duration header against the first. The list leaves room
     * for that push to finish, so the second header rests whole at its pin line, the first has
     * left, the last row is reachable, the headers stay headings read before their rows and ATF
     * stays clean. Before the fix the first title rested half pushed off the top.
     */
    @Test
    fun durationListEndRestsWithAWholePinnedHeading() {
        h.enableAccessibilityChecks()
        launch("Duration", transport = BucketHeaderFixtures.sectionsTransport(END_SECTIONS))
        val first = "$HEADER_PREFIX$DURATION.1to2"
        h.waitForTag(first)
        val fullHeight = header(first).boundsInRoot.height
        scrollToEnd()
        assertEndRestsWhole("Duration end", fullHeight, END_LAST_ROW)
        assertHeadersAreHeadings("Duration end")
        assertHeadersLeadTheirRows("songs-duration-end", DURATION_TOKENS)
        h.assertAccessible()
    }

    /** The same list end at 200% text (Year): taller headers still finish the last push, unclipped and in order. */
    @Test
    fun yearListEndRestsWithAWholePinnedHeadingAtDoubleText() {
        h.enableAccessibilityChecks()
        launch("Year", fontScale = { 2f }, transport = BucketHeaderFixtures.sectionsTransport(END_SECTIONS))
        val first = "$HEADER_PREFIX$YEAR.1970"
        h.waitForTag(first)
        val fullHeight = header(first).boundsInRoot.height
        scrollToEnd()
        assertEndRestsWhole("Year 200% end", fullHeight, END_LAST_ROW)
        assertHeadersAreHeadings("Year 200% end")
        assertHeadersLeadTheirRows("songs-year-200-end", YEAR_TOKENS)
        h.assertAccessible()
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

        /** Height of the band under the pinned header that the fade's ramp covers (`ScrollEdgeFade.TOP_DP`). */
        const val EDGE_BAND_DP = 40f

        /** Largest pixel luminance change in the band that shows the ramp came back (rows near the cut dim). */
        const val EDGE_CHANGE = 0.2f

        /** Largest pixel luminance change in the band still counted as the same pixels. */
        const val EDGE_SAME = 0.02f

        /**
         * Songs per section for the list-end journeys ([BucketHeaderFixtures.sectionsTransport]):
         * one full section, then three short ones, so on a phone (FST_Phone, CI's Pixel 6) the
         * list's last scroll position falls mid-way through the second header's push against the
         * first (issue #560; about 29 dp on FST_Phone, 20 dp on a Pixel 6).
         */
        val END_SECTIONS = listOf(10, 2, 2, 1)

        /** Tag of the list's last row with [END_SECTIONS]. */
        const val END_LAST_ROW = "${ROW_PREFIX}30"

        /** A scroll far past any list's end, as a fling or TalkBack's scroll-forward reaches it. */
        const val END_SCROLL_PX = 100_000f
    }
}
