package com.festivalscoretracker.android.journeys

import android.os.Build
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.ComponentActivity
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import kotlinx.coroutines.CompletableDeferred
import org.junit.After
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs

/**
 * Accessibility of the sections that finish loading after the reader has scrolled (issue #60,
 * accessibility backfill #422): Player Profile's Rank History and bands, which start loading
 * when scrolled to, and a Leaderboards card still loading after a scroll. The page's fade
 * window (`FadeInWindow`) shows them in place, so the content TalkBack reaches is fully drawn.
 *
 * Each journey holds the section's read open, scrolls to it with a real swipe, then checks:
 * the labelled loading state where the section will appear; once loaded, its labels, roles and
 * reading order (heading, then content, in place of the loading state); ATF (48 dp targets,
 * labels, contrast) on every screen; and that the section is drawn opaque within two frames of
 * appearing (no fade under the reader). The journeys run at 100% and 200% text with animations on,
 * and Player Profile again under Remove animations (animator scale 0); the animator scale is set
 * for each test and restored. Pixel-level fades at load and under Reduce Motion are covered on the
 * JVM by `FadeInWindowTest`, `FadeInTimingTest` and `StaggerRushTest`.
 *
 * Reading order is TalkBack's linear order: each journey calls
 * [JourneyHarness.publishTalkBackTree] after launch, so `readingOrder` follows the published
 * traversal links and reads a fresh tree after each scroll. `@DeviceCi`, so the `android-device`
 * CI job runs it on a phone.
 *
 * `device.py test com.festivalscoretracker.android.journeys.LoadFadeWindowAccessibilityJourneyTest --avd …`
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class LoadFadeWindowAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private var savedAnimatorScale = "null"

    // region System settings

    private fun shell(command: String): String {
        val pfd = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).use { it.readBytes().decodeToString().trim() }
    }

    private fun setAnimatorScale(scale: String) = shell("settings put global animator_duration_scale $scale")

    @Before
    fun saveAnimatorScale() {
        savedAnimatorScale = shell("settings get global animator_duration_scale").ifEmpty { "null" }
        // Animations on: the fade window only matters while fades run.
        setAnimatorScale("1")
    }

    @After
    fun restoreAnimatorScale() {
        shell(if (savedAnimatorScale == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $savedAnimatorScale")
    }

    // endregion

    // region Player Profile

    @Test
    fun profileSectionsLoadedAfterScrolling() = profileJourney(fontScale = null)

    @Test
    fun profileSectionsLoadedAfterScrollingAtLargeText() = profileJourney(fontScale = 2f)

    @Test
    fun profileSectionsLoadedAfterScrollingUnderRemoveAnimations() {
        setAnimatorScale("0")
        profileJourney(fontScale = null)
    }

    private fun profileJourney(fontScale: Float?) {
        val history = CompletableDeferred<Unit>()
        val bands = CompletableDeferred<Unit>()
        val transport = BandFixtures.install(FakeTransport.standard().apply(songs).also { ProfileFixtures.register(it) })
        transport.beforeRespond = { request ->
            when (path(request.url)) {
                "/api/rankings/Solo_Bass/${Fixtures.ACCOUNT_A}/history" -> history.await()
                "/api/player/${Fixtures.ACCOUNT_A}/bands" -> bands.await()
            }
        }
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(section = FestivalSection.Statistics, profile = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"), stillBackground = true),
            transport,
            fontScale = fontScale?.let { scale -> { scale } },
        )
        h.waitForTag("fst.player.overview")
        h.publishTalkBackTree()
        h.readingOrder("fade-window-profile-load")

        // The reader scrolls (a real drag closes the page's fade window), reaching Bass while its history loads.
        swipe(GRID)
        // Then back to the Bass heading, so its card's heading and hint stay on screen above the chart.
        h.scrollTo(GRID, "$BASS_HISTORY.loading")
        h.scrollTo(GRID, "fst.player.instrument.Solo_Bass")
        settle()
        awaitTree(present = "$BASS_HISTORY.loading")
        val loading = h.readingOrder("fade-window-profile-history-loading")
        assertTrue("Rank History loading state is unlabelled: $loading", loading.any { it.startsWith("Loading rank history") })

        assertShownInPlace(BASS_HISTORY) { history.complete(Unit) }
        awaitTree(present = BASS_HISTORY, absent = "$BASS_HISTORY.loading")
        val loaded = h.readingOrder("fade-window-profile-history-loaded")
        val bass = loaded.indexOf("Bass")
        assertTrue("Bass heading is not read: $loaded", bass >= 0)
        val chart = loaded.drop(bass).indexOfFirst { it.startsWith("Rank history chart, ") }.let { if (it < 0) -1 else bass + it }
        assertTrue("Bass rank history chart is not read after its heading: $loaded", chart >= 0)
        val heading = loaded.subList(0, chart).lastIndexOf("Rank History")
        assertTrue("Rank History heading is not read between Bass and its chart: $loaded", heading > bass)
        assertTrue("Rank History hint is not read between heading and chart: $loaded", loaded.subList(heading, chart).any { it.startsWith("Your ranking progression") })
        assertTrue("Loading state still read after the chart loaded: $loaded", loaded.subList(heading, chart).none { it.startsWith("Loading rank history") })
        assertHeading("Rank History")

        // Further down, the bands preview starts loading when scrolled to.
        h.scrollTo(GRID, "fst.player.bands.loading")
        settle()
        awaitTree(present = "fst.player.bands.loading")
        val bandsLoading = h.readingOrder("fade-window-profile-bands-loading")
        assertTrue("Bands loading state is unlabelled: $bandsLoading", bandsLoading.any { it.startsWith("Loading bands") })

        assertShownInPlace("fst.player.bands") { bands.complete(Unit) }
        h.scrollTo(GRID, "fst.player.bands.header.duos")
        settle()
        awaitTree(present = "fst.player.bands.header.duos", absent = "fst.player.bands.loading")
        val bandsLoaded = h.readingOrder("fade-window-profile-bands-loaded")
        assertTrue("Bands loading state still read: $bandsLoaded", bandsLoaded.none { it.startsWith("Loading bands") })
        val duos = bandsLoaded.indexOf("Duos")
        assertTrue("Duos group heading is not read: $bandsLoaded", duos >= 0)
        val section = bandsLoaded.indexOf("Synthetic Player's Bands")
        assertTrue("Bands section heading is not read before the Duos group: $bandsLoaded", section in 0 until duos)
        // The fixture player has no duos, so the group reads its heading, then its empty state.
        assertTrue("Duos heading is not followed by its group's content: $bandsLoaded", bandsLoaded.getOrNull(duos + 1)?.startsWith("No Bands Yet") == true)
        assertHeading("Duos")
        h.assertAccessible()
    }

    // endregion

    // region Leaderboards

    @Test
    fun leaderboardCardLoadedAfterScrolling() = leaderboardsJourney(fontScale = null)

    @Test
    fun leaderboardCardLoadedAfterScrollingAtLargeText() = leaderboardsJourney(fontScale = 2f)

    private fun leaderboardsJourney(fontScale: Float?) {
        val drums = CompletableDeferred<Unit>()
        val transport = RankingsFixtures.install(FakeTransport.standard().apply(songs))
        transport.beforeRespond = { request -> if (path(request.url) == "/api/rankings/Solo_Drums") drums.await() }
        h.enableAccessibilityChecks()
        h.launch(
            DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true),
            transport,
            fontScale = fontScale?.let { scale -> { scale } },
        )
        h.waitForTag("fst.leaderboards.rank-history")
        h.waitGone("fst.leaderboards.loading")
        settle()
        h.publishTalkBackTree()
        h.readingOrder("fade-window-leaderboards-load")

        swipe(LIST)
        h.scrollTo(LIST, DRUMS_CARD)
        settle()
        awaitTree(present = "fst.rankings.skeleton")
        val loading = h.readingOrder("fade-window-leaderboards-loading")
        val header = loading.indexOf("Drums")
        assertTrue("Drums card header is not read: $loading", header >= 0)
        assertTrue("Drums loading state is not read after its header: $loading", loading.drop(header + 1).firstOrNull()?.startsWith("Loading rankings") == true)

        // Names marquee while animations run, so compare the rank column, which fades with its row.
        assertShownInPlace(DRUMS_CARD, until = "$DRUMS_CARD.view-all", leading = RANK_COLUMN) { drums.complete(Unit) }
        awaitTree(present = DRUMS_CARD, absent = "fst.rankings.skeleton")
        val loaded = h.readingOrder("fade-window-leaderboards-loaded")
        val loadedHeader = loaded.indexOf("Drums")
        assertTrue("Drums card header is not read: $loaded", loadedHeader >= 0)
        val first = loaded.getOrNull(loadedHeader + 1).orEmpty()
        assertTrue("Drums card reads \"$first\" after its header, not its first row: $loaded", first.startsWith("#1. "))
        h.assertAccessible()
    }

    // endregion

    // region Helpers

    private val songs: FakeTransport.() -> Unit = {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
    }

    private fun path(url: String) = "/" + url.substringAfter("://").substringAfter('/').substringBefore('?')

    /** A real drag on [list]: the reader scrolling, which closes the page's fade window. */
    private fun swipe(list: String) {
        h.waitForTag(list)
        rule.onNodeWithTag(list).performTouchInput { swipeUp(startY = centerY + height / 6f, endY = centerY - height / 6f) }
        settle()
    }

    /** Let flings, the hide-on-scroll chrome and running entrances finish. */
    private fun settle() {
        rule.waitForIdle()
        rule.mainClock.advanceTimeBy(SETTLE_MILLIS)
        rule.waitForIdle()
    }

    /**
     * Release a held read and assert that the section [tag] is drawn opaque within two frames of
     * [until] appearing (it does not fade in under the reader).
     *
     * @param tag Section to capture.
     * @param until Tag whose appearance marks the loaded section.
     * @param leading Fraction of the capture's width to compare.
     * @param release Releases the held read.
     */
    private fun assertShownInPlace(tag: String, until: String = tag, leading: Float = 1f, release: () -> Unit) {
        rule.mainClock.autoAdvance = false
        try {
            release()
            val difference = framesUntilSettled(until, capture = tag, leading = leading)
            assertTrue("$tag faded in after the page had scrolled (difference $difference; $lastDifference)", difference < SHOWN)
        } finally {
            rule.mainClock.autoAdvance = true
        }
        rule.waitForIdle()
    }

    /**
     * With the clock paused, step frames until [until] is composed, capture [capture] two frames
     * later and again once any fade would have finished.
     *
     * @param until Tag whose appearance marks the loaded section.
     * @param capture Tag to capture.
     * @param leading Fraction of the capture's width to compare.
     * @return Mean per-channel difference (0–255) between the two captures.
     */
    private fun framesUntilSettled(until: String, capture: String, leading: Float): Double {
        val deadline = SystemClock.uptimeMillis() + 15_000
        while (!h.exists(until)) {
            assertTrue("Timed out waiting for $until", SystemClock.uptimeMillis() < deadline)
            rule.mainClock.advanceTimeByFrame()
            SystemClock.sleep(FRAME_SLEEP_MILLIS)
        }
        repeat(2) { rule.mainClock.advanceTimeByFrame() }
        val early = rule.onNodeWithTag(capture, useUnmergedTree = true).captureToImage()
        rule.mainClock.advanceTimeBy(SETTLE_MILLIS)
        val settled = rule.onNodeWithTag(capture, useUnmergedTree = true).captureToImage()
        return difference(early, settled, leading)
    }

    /**
     * Mean per-channel difference (0–255) between two captures over their [leading] fraction of
     * width; records where the pixels changed in [lastDifference] for the failure message.
     */
    private fun difference(a: ImageBitmap, b: ImageBitmap, leading: Float): Double {
        val full = minOf(a.width, b.width)
        val width = (full * leading).toInt()
        val height = minOf(a.height, b.height)
        if (width == 0 || height == 0) return 0.0
        val first = IntArray(width * height).also { a.asAndroidBitmap().getPixels(it, 0, width, 0, 0, width, height) }
        val second = IntArray(width * height).also { b.asAndroidBitmap().getPixels(it, 0, width, 0, 0, width, height) }
        var total = 0L
        var changed = 0
        var left = width; var top = height; var right = -1; var bottom = -1
        for (i in first.indices) {
            var pixel = 0
            for (shift in intArrayOf(0, 8, 16)) pixel += abs(((first[i] shr shift) and 0xFF) - ((second[i] shr shift) and 0xFF))
            total += pixel
            if (pixel > 48) {
                changed++
                val x = i % width; val y = i / width
                left = minOf(left, x); right = maxOf(right, x); top = minOf(top, y); bottom = maxOf(bottom, y)
            }
        }
        lastDifference = "size ${a.width}x${a.height} vs ${b.width}x${b.height}, changed $changed px in [$left,$top..$right,$bottom]"
        return total / (first.size * 3.0)
    }

    /** Where the last [difference] found changed pixels. */
    private var lastDifference = ""

    /**
     * Wait until the window's accessibility tree shows [present] and not [absent], like
     * [JourneyHarness.awaitAccessibilityTree], but clearing UiAutomation's node cache on each poll
     * (API 34+): on a split fold it can keep the pre-scroll tree. Fails with what TalkBack reads.
     *
     * @param present Test tag that must be in the tree.
     * @param absent Test tag that must have left the tree, or `null`.
     */
    private fun awaitTree(present: String, absent: String? = null) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun ids(node: AccessibilityNodeInfo?, into: MutableSet<String> = mutableSetOf()): Set<String> {
            node ?: return into
            node.viewIdResourceName?.let(into::add)
            for (i in 0 until node.childCount) ids(node.getChild(i), into)
            return into
        }
        val deadline = SystemClock.uptimeMillis() + 15_000
        while (true) {
            rule.waitForIdle()
            if (Build.VERSION.SDK_INT >= 34) automation.clearCache()
            val seen = ids(automation.rootInActiveWindow)
            if (present in seen && (absent == null || absent !in seen)) return
            if (SystemClock.uptimeMillis() > deadline) {
                throw AssertionError(
                    "Accessibility tree never showed $present${absent?.let { " without $it" }.orEmpty()} " +
                        "(composed: ${h.exists(present)}${absent?.let { ", $it composed: ${h.exists(it)}" }.orEmpty()}): ${h.readingOrder("fade-window-timeout")}",
                )
            }
            SystemClock.sleep(100)
        }
    }

    /** The text [label] is exposed as a heading. */
    private fun assertHeading(label: String) {
        val headings = rule.onAllNodes(hasText(label) and SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading), useUnmergedTree = true)
            .fetchSemanticsNodes()
        assertTrue("\"$label\" is not a heading", headings.isNotEmpty())
    }

    private companion object {
        const val GRID = "fst.player.available"
        const val LIST = "fst.leaderboards"
        const val BASS_HISTORY = "fst.player.rank-history.Solo_Bass"
        const val DRUMS_CARD = "fst.leaderboards.card.Solo_Drums"

        /** Longer than any fade (400 ms plus its stagger). */
        const val SETTLE_MILLIS = 1_500L
        const val FRAME_SLEEP_MILLIS = 16L

        /** Mean channel difference below which two captures are the same drawing. */
        const val SHOWN = 2.0

        /** The rank column's share of a Leaderboards card (left of the marquee names). */
        const val RANK_COLUMN = 0.15f
    }

    // endregion
}
