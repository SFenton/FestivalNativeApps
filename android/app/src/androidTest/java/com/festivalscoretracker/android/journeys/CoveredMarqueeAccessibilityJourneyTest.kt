package com.festivalscoretracker.android.journeys

import android.graphics.Bitmap
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.data.HttpResult
import com.festivalscoretracker.android.presentation.ModalCoverage
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.SongsFixtures
import com.festivalscoretracker.android.ui.common.FestivalMarquee
import com.festivalscoretracker.android.ui.common.MODAL_CLOSE_LABEL
import java.io.ByteArrayOutputStream
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A clipped scrolling title behind a Festival modal on a real device (issue #509, the
 * accessibility tests for #186, `modal-shell` R10 with `song-header` R2–R4). Song Details shows
 * a synthetic title wider than its header, so `FestivalMarqueeText` scrolls it:
 *
 * - Under the first-run tour (the #83/#186 report: every page tour `force` shows on the way
 *   there) and under the Paths sheet the title holds (`Held`) on one line but keeps its whole
 *   text, while the modal is the window TalkBack reads: its title before Close, a labelled
 *   48 dp button, and never the covered page's title.
 * - After close the title scrolls again and TalkBack reads it, whole, as one heading.
 * - At 200% text the title wraps in-page before, under and after the sheet: large text never
 *   holds a clipped line.
 * - With Remove animations (animator scale 0) it stays tail-truncated before, under and after
 *   a modal: it never scrolls or holds.
 *
 * ATF runs on every interaction. Run with `device.py test
 * com.festivalscoretracker.android.journeys.CoveredMarqueeAccessibilityJourneyTest --avd <AVD>`;
 * reading orders go to logcat `FST_A11Y`. `@DeviceCi`: CI's `android-device` check runs it.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class CoveredMarqueeAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) {
            Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null").replace("\"title\":\"Alpha Tune\"", "\"title\":\"$LONG\"")
        }
        on("/api/shop", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.shopJson.replace("\"b.jpg\"", "null") }
        val image = png()
        onRaw("/api/paths/s-alpha/Solo_Guitar/expert") { HttpResult(200, image, mapOf("X-FST-Publication-Id" to "7")) }
        on("/api/paths/s-alpha/Solo_Guitar/expert/data", headers = mapOf("X-FST-Publication-Id" to "7")) { SongsFixtures.pathJson }
    }
    private var animatorScale = "1"

    // region Setup

    private fun shell(command: String): String {
        val pfd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes().decodeToString().trim() }
    }

    private fun png(): ByteArray {
        val bitmap = Bitmap.createBitmap(400, 1_200, Bitmap.Config.ARGB_8888).apply { eraseColor(android.graphics.Color.WHITE) }
        return ByteArrayOutputStream().also { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
    }

    /** Animations on: CI and `device.py` turn them off, which truncates instead of scrolling. */
    @Before
    fun setUp() {
        animatorScale = shell("settings get global animator_duration_scale").takeIf { it != "null" && it.isNotEmpty() } ?: "1"
        shell("settings put global animator_duration_scale 1")
    }

    @After
    fun restore() {
        shell("settings put global animator_duration_scale $animatorScale")
    }

    // endregion

    // region Tests

    /** The first-run tour holds the clipped title whole and keeps it out of TalkBack until it closes. */
    @Test
    fun tourHoldsTheClippedTitleWholeAndOutOfTalkBack() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(songQuery = "s-alpha", firstRun = "force"), transport)
        h.publishTalkBackTree()
        reachTitleUnderTour()
        var tours = 0
        while (h.exists(TOUR)) {
            tours++
            check(tours <= 5) { "tours never ended" }
            assertHeld("tour $tours")
            assertModalReadFirst("tour $tours", close = TOUR_CLOSE, title = text(rule.onAllNodesWithTag(TOUR_TITLE, useUnmergedTree = true)[0].fetchSemanticsNode()))
            h.tap(TOUR_CLOSE)
            h.waitGone(TOUR)
            // Force shows the next page's tour (Song Details after Songs) once this one closes.
            runCatching { rule.waitUntil(3_000) { h.exists(TOUR) } }
        }
        rule.waitUntil(10_000) { ModalCoverage.shared.openCount.value == 0 }
        waitForMode(FestivalMarquee.Mode.Scrolling, "after the tour")
        assertTitleRead("after the tour")
        h.assertAccessible()
    }

    /** The Paths sheet holds the scrolling title at 1.0 and leaves the 2.0 wrapped title wrapped. */
    @Test
    fun pathsSheetHoldsTheTitleAndLargeTextStaysWrapped() {
        var scale by mutableFloatStateOf(SCALES.first())
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(songQuery = "s-alpha"), transport, fontScale = { scale })
        h.waitForTag(LIST)
        h.publishTalkBackTree()
        SCALES.forEach { s ->
            scale = s
            rule.waitForIdle()
            val config = "fs $s"
            val page = if (s > 1f) FestivalMarquee.Mode.Wrapped else FestivalMarquee.Mode.Scrolling
            waitForMode(page, config)
            if (s > 1f) assertTrue("$config: the title wraps in-page", layout(title()).lineCount > 1)
            assertTitleRead(config)
            openPaths()
            if (s > 1f) {
                assertEquals("$config: large text never holds a clipped line", FestivalMarquee.Mode.Wrapped, mode())
                assertTrue("$config: the title still wraps under the sheet", layout(title()).lineCount > 1)
                assertEquals("$config: the wrapped title lost text", listOf(LONG), title().config[SemanticsProperties.Text].map { it.text })
            } else {
                assertHeld("paths $config")
            }
            assertModalReadFirst("paths $config", close = PATHS_CLOSE, title = PATHS_TITLE)
            h.tap(PATHS_CLOSE)
            h.waitGone(PATHS)
            rule.waitUntil(10_000) { ModalCoverage.shared.openCount.value == 0 }
            waitForMode(page, "after paths $config")
            assertTitleRead("after paths $config")
        }
        h.assertAccessible()
    }

    /** Remove animations: the title stays tail-truncated under and after a modal, never held or scrolling. */
    @Test
    fun removeAnimationsKeepsTheTitleTruncatedUnderAndAfterAModal() {
        shell("settings put global animator_duration_scale 0")
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(songQuery = "s-alpha"), transport)
        h.waitForTag(LIST)
        h.publishTalkBackTree()
        waitForMode(FestivalMarquee.Mode.Truncated, "remove animations")
        assertTrue("ends in an ellipsis", layout(title()).isLineEllipsized(0))
        openPaths()
        assertEquals("reduce motion outranks held", FestivalMarquee.Mode.Truncated, mode())
        assertModalReadFirst("paths remove-animations", close = PATHS_CLOSE, title = PATHS_TITLE)
        h.tap(PATHS_CLOSE)
        h.waitGone(PATHS)
        rule.waitUntil(10_000) { ModalCoverage.shared.openCount.value == 0 }
        assertEquals("remove animations after the sheet", FestivalMarquee.Mode.Truncated, mode())
        assertTitleRead("after paths remove-animations")
        h.assertAccessible()
    }

    // endregion

    // region Title

    private fun titles(): List<SemanticsNode> =
        rule.onAllNodes(hasText(LONG) and hasAnyAncestor(hasTestTag(HEADER)), useUnmergedTree = true).fetchSemanticsNodes()

    private fun title(): SemanticsNode = titles().single()

    private fun mode(): FestivalMarquee.Mode? = title().config.getOrNull(FestivalMarquee.ModeKey)

    private fun text(node: SemanticsNode): String = node.config[SemanticsProperties.Text].joinToString { it.text }

    private fun layout(node: SemanticsNode): TextLayoutResult {
        val layouts = mutableListOf<TextLayoutResult>()
        node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        return layouts.single()
    }

    private fun waitForMode(expected: FestivalMarquee.Mode, where: String) {
        runCatching { rule.waitUntil(15_000) { runCatching { mode() }.getOrNull() == expected } }
            .onFailure { throw AssertionError("$where: title never reached $expected (was ${runCatching { mode() }.getOrNull()})", it) }
    }

    /**
     * Force mode shows each visited page's tour: wait until Song Details' title is composed with
     * a tour open above it, closing tours that open before the page does.
     */
    private fun reachTitleUnderTour() {
        val deadline = SystemClock.uptimeMillis() + 30_000
        while (true) {
            rule.waitForIdle()
            val tour = h.exists(TOUR)
            if (tour && titles().isNotEmpty()) return
            if (tour) {
                h.tap(TOUR_CLOSE)
                h.waitGone(TOUR)
            }
            check(SystemClock.uptimeMillis() < deadline) { "no tour over Song Details (tour $tour, title ${titles().size})" }
            Thread.sleep(100)
        }
    }

    /**
     * The covered title holds on one clipped line but keeps its whole text for TalkBack.
     *
     * @param where Name for messages.
     */
    private fun assertHeld(where: String) {
        waitForMode(FestivalMarquee.Mode.Held, where)
        val node = title()
        assertEquals("$where: the held title lost text", listOf(LONG), node.config[SemanticsProperties.Text].map { it.text })
        val layout = layout(node)
        assertEquals("$where: held title lines", 1, layout.lineCount)
        assertTrue("$where: the held title is clipped, not shortened", layout.size.width > node.boundsInRoot.width)
    }

    /**
     * TalkBack reads the page's title, whole, once and as a heading.
     *
     * @param where Name for messages.
     */
    private fun assertTitleRead(where: String) {
        h.awaitAccessibilityTree(present = LIST)
        val stops = h.readingStops("marquee $where", fresh = true).filter { it.label.startsWith(LONG) }
        assertEquals("$where: TalkBack reads the title once: $stops", 1, stops.size)
        assertTrue("$where: the title is not a heading: $stops", stops.single().isHeading)
    }

    /** Opens the Paths sheet and dismisses the fixture's karaoke warning, as ModalCloseJourneyTest does. */
    private fun openPaths() {
        h.tap(PATHS_OPEN)
        h.waitForTag(PATHS_CLOSE)
        if (h.exists(PATHS_WARNING)) {
            h.tap(PATHS_WARNING_OK)
            h.waitGone(PATHS_WARNING)
        }
    }

    /**
     * The open modal is the window TalkBack reads: its title before Close, a labelled 48 dp
     * button, and never the covered page's title.
     *
     * @param screen Reading-order log name.
     * @param close Close button test tag.
     * @param title The modal's title text.
     */
    private fun assertModalReadFirst(screen: String, close: String, title: String) {
        val button = rule.onAllNodesWithTag(close)[0].fetchSemanticsNode()
        assertEquals("$screen: Close label", listOf(MODAL_CLOSE_LABEL), button.config.getOrNull(SemanticsProperties.ContentDescription))
        assertEquals("$screen: Close role", Role.Button, button.config.getOrNull(SemanticsProperties.Role))
        // Compose's touch bounds, as ArtworkBackgroundModalAccessibilityJourneyTest: a sliding sheet's platform node can trail it.
        val min = with(rule.density) { 48.dp.toPx() } - 1
        val target = button.touchBoundsInRoot
        assertTrue("$screen: Close target ${target.width}x${target.height} px < 48 dp", target.width >= min && target.height >= min)
        h.awaitAccessibilityTree(present = close)
        val order = h.readingOrder("marquee-$screen", fresh = true)
        assertTrue("$screen: no TalkBack traversal links followed", h.lastReadingLinks > 0)
        val titleAt = order.indexOfFirst { it.startsWith(title) }
        val closeAt = order.indexOf(MODAL_CLOSE_LABEL)
        assertTrue("$screen: \"$title\" reads before Close: $order", titleAt >= 0 && closeAt > titleAt)
        assertTrue("$screen: TalkBack reads the covered page's title: $order", order.none { it.startsWith(LONG) })
    }

    // endregion

    private companion object {
        /** Default and largest Android font scale (200%). */
        val SCALES = listOf(1f, 2f)

        /** Synthetic overflowing title (no real song data), as `SongHeaderTitleUiTest`. */
        const val LONG = "Through the Fire and Flames of a Synthetic Overflowing Title"
        const val HEADER = "fst.song-detail.header"
        const val LIST = "fst.song-detail.list"
        const val TOUR = "fst.first-run.dialog"
        const val TOUR_CLOSE = "fst.first-run.close"
        const val TOUR_TITLE = "fst.first-run.title"
        const val PATHS = "fst.song-detail.paths"
        const val PATHS_OPEN = "fst.song-detail.paths.open"
        const val PATHS_CLOSE = "fst.paths.close"
        const val PATHS_TITLE = "Paths"
        const val PATHS_WARNING = "fst.paths.karaoke-warning"
        const val PATHS_WARNING_OK = "fst.paths.warning.ok"
    }
}
