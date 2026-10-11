package com.festivalscoretracker.android.journeys

import android.graphics.Bitmap
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.RankingsFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Graph card paging (`load-transition` R12, issue #593) on a device, through the Leaderboards
 * Rank History chart (its fixture history pages on a phone). With system animations on, a pager
 * tap slides the chart: 150 ms later the plot shows neither the old nor the new window, and the
 * card and plot keep their size throughout; under the app's Reduce Motion the new window is
 * drawn at once. TalkBack reads the chart (its description follows the new window) before the
 * four 48 dp pager buttons, at the device's text size and at 200%. ATF runs on every step. Run
 * with `device.py test com.festivalscoretracker.android.journeys.ChartPagingAccessibilityJourneyTest --avd …`;
 * reading orders go to logcat `FST_A11Y`.
 */
@DeviceCi
@RunWith(AndroidJUnit4::class)
class ChartPagingAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private var scale by mutableFloatStateOf(1f)

    // region Helpers

    private fun open(reduceMotion: Boolean) {
        h.enableAccessibilityChecks()
        val transport = RankingsFixtures.install(
            FakeTransport.standard().apply {
                on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
            },
        )
        h.launch(
            DebugLaunch(route = DebugLaunch.parseRoute("leaderboards"), profile = SelectedPlayer(RankingsFixtures.SELECTED, "Selected Player"), stillBackground = true),
            transport,
            MemoryPreferences(mutablePreferencesOf(booleanPreferencesKey(SettingsRegistry.REDUCE_MOTION) to reduceMotion)),
            fontScale = { scale },
        )
        h.waitForTag(PLOT)
        reveal()
    }

    /** Bring the whole chart and its pager on screen and let entrances finish. */
    private fun reveal() {
        h.scrollTo(LIST, "$CARD.forward-page")
        rule.waitForIdle()
        rule.mainClock.advanceTimeBy(1_000)
        rule.waitForIdle()
    }

    private fun description(): String = rule.onNodeWithTag(PLOT).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].single()

    private fun capture(): Bitmap = rule.onNodeWithTag(PLOT).captureToImage().asAndroidBitmap()

    /** (card height, plot width, plot height) in px. */
    private fun sizes(): Triple<Int, Int, Int> {
        val plot = rule.onNodeWithTag(PLOT).fetchSemanticsNode().size
        return Triple(rule.onNodeWithTag(CARD).fetchSemanticsNode().size.height, plot.width, plot.height)
    }

    /**
     * Press the pager button [id] with the clock paused and capture the plot before, 150 ms into
     * the 400 ms slide, and settled, checking the card and plot keep their size.
     *
     * @return (before, mid, settled) plot captures.
     */
    private fun page(screen: String, id: String): Triple<Bitmap, Bitmap, Bitmap> {
        val before = capture()
        val size = sizes()
        rule.mainClock.autoAdvance = false
        try {
            rule.onNodeWithTag("$CARD.$id").performSemanticsAction(SemanticsActions.OnClick)
            rule.mainClock.advanceTimeBy(150)
            val mid = capture()
            assertEquals("$screen: card and plot keep their size mid-slide", size, sizes())
            rule.mainClock.advanceTimeBy(800)
            val settled = capture()
            assertEquals("$screen: card and plot keep their size once settled", size, sizes())
            return Triple(before, mid, settled)
        } finally {
            rule.mainClock.autoAdvance = true
            rule.waitForIdle()
        }
    }

    /** TalkBack reads the chart, then the enabled pager buttons (each a 48 dp target) in order. */
    private fun assertChartThenPager(screen: String) {
        PAGER.forEach { h.assertTouchTarget(screen, "$CARD.$it") }
        val stops = h.readingStops(screen, fresh = true)
        val order = stops.map { "${it.id}: ${it.label}" }
        val chart = stops.indexOfFirst { it.id == PLOT && it.label.startsWith("Rank history chart") }
        // Disabled buttons (the window's end) are not stops.
        val buttons = PAGER.map { id -> stops.indexOfFirst { it.id == "$CARD.$id" } }.filter { it >= 0 }
        assertTrue("$screen: chart is read in $order", chart >= 0)
        assertTrue("$screen: the enabled pager buttons are read in $order", buttons.size >= 2)
        assertTrue("$screen: pager reads after the chart, in order, in $order", buttons.all { it > chart } && buttons == buttons.sorted())
    }

    /** Runs [body] with the system animator duration scale at [value] (device CI turns it off), then restores it. */
    private fun withAnimatorScale(value: String, body: () -> Unit) {
        val saved = shell("settings get global animator_duration_scale")
        shell("settings put global animator_duration_scale $value")
        try {
            body()
        } finally {
            shell(if (saved == "null") "settings delete global animator_duration_scale" else "settings put global animator_duration_scale $saved")
        }
    }

    private fun shell(command: String): String =
        InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command).use { fd ->
            java.io.FileInputStream(fd.fileDescriptor).bufferedReader().readText().trim()
        }

    // endregion

    @Test
    fun pagingSlidesTheChartKeepsTheCardSizeAndReadsChartThenPager() = withAnimatorScale("1") {
        open(reduceMotion = false)
        listOf(1f, 2f).forEach { fontScale ->
            val screen = "chart-paging-${(fontScale * 100).toInt()}"
            if (fontScale != scale) {
                scale = fontScale
                rule.waitForIdle()
                reveal()
            }
            assertChartThenPager(screen)
            val newest = description()
            val (before, mid, settled) = page(screen, "back-page")
            // Mid-slide the plot is between the two windows: it matches neither.
            assertFalse("$screen: the chart snapped (mid-slide equals the new window)", mid.sameAs(settled))
            assertFalse("$screen: the chart did not move 150 ms in", mid.sameAs(before))
            assertNotEquals("$screen: TalkBack's chart description follows the new window", newest, description())
            assertChartThenPager("$screen-paged")
            // And back to the newest window, so the next text size starts where this one did.
            page(screen, "forward-page")
            assertEquals(newest, description())
            h.assertAccessible()
        }
    }

    @Test
    fun reduceMotionPagesAtOnce() = withAnimatorScale("1") {
        open(reduceMotion = true)
        val newest = description()
        val (_, mid, settled) = page("chart-paging-reduce-motion", "back-page")
        assertTrue("Reduce Motion: the new window is drawn at once", mid.sameAs(settled))
        assertNotEquals(newest, description())
        assertChartThenPager("chart-paging-reduce-motion")
        h.assertAccessible()
    }

    private companion object {
        const val LIST = "fst.leaderboards"
        const val CARD = "fst.leaderboards.rank-history"
        const val PLOT = "fst.leaderboards.rank-history.plot"
        val PAGER = listOf("back-page", "back-entry", "forward-entry", "forward-page")
    }
}
