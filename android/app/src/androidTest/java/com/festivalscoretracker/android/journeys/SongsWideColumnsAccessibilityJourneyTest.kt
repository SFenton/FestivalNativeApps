package com.festivalscoretracker.android.journeys

import android.content.pm.ActivityInfo
import android.content.res.Configuration
import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.SectionIndexFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility of Songs' `wide-columns` layout (issue #581): in a wide landscape or unfolded
 * window the song rows sit in two row-major columns, and TalkBack reads each line's start
 * song, then its end song, then the next line (list order, never down one column first).
 * Every row stays one labelled ≥ 48 dp button, nothing sits across a separating hinge at
 * 100 % (the columns meet at the fold and the search field keeps to the leading pane), ATF
 * finds no errors, and at 200 % text the list drops to one full-width column
 * (`rememberSingleColumn`, as every hinge split does) with the same reading order. Phones are
 * turned to landscape through the activity's requested
 * orientation. Fixtures only (`SectionIndexFixtures`: two songs per title section).
 * `@DeviceCi` runs it on a phone; `@HalfOpenFoldJourney` on a half-open book fold. Locally:
 * `device.py test com.festivalscoretracker.android.journeys.SongsWideColumnsAccessibilityJourneyTest --avd FST_Phone`
 * (or `--avd FST_Book_Fold --posture half --runner-arg fstRequireHinge=true`).
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
@HalfOpenFoldJourney
class SongsWideColumnsAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Helpers

    private fun bounds(tag: String): Rect = rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].fetchSemanticsNode().boundsInWindow

    /**
     * Turn a phone to landscape through the activity's requested orientation (never the global
     * rotation settings, issue #549); large screens may ignore it and run at their own.
     */
    private fun turnToLandscape() {
        val sw = rule.activity.resources.configuration.smallestScreenWidthDp
        rule.runOnUiThread { rule.activity.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE }
        val turned = runCatching {
            rule.waitUntil(10_000) { rule.activity.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE }
        }.isSuccess
        rule.waitForIdle()
        Log.i(JourneyHarness.READING_ORDER_TAG, "songs-wide | landscape $turned (sw${sw}dp, w${rule.activity.resources.configuration.screenWidthDp}dp)")
        if (sw < 600) assertTrue("a phone turns to landscape on request", turned)
    }

    /** Song rows TalkBack visits, in order, once the tree has caught up. */
    private fun rowStops(screen: String): List<JourneyHarness.ReadingStop> {
        if (android.os.Build.VERSION.SDK_INT >= 34) InstrumentationRegistry.getInstrumentation().uiAutomation.clearCache()
        h.awaitAccessibilityTree(present = "$ROW${SECOND}")
        return h.readingStops(screen, fresh = true).filter { it.id?.startsWith(ROW) == true }
    }

    /**
     * Rows are read in list order (`s-<section>-<n>`, section then n), each one labelled
     * ≥ 48 dp button.
     */
    private fun assertRowsReadInListOrder(screen: String) {
        val stops = rowStops(screen)
        val dump = stops.joinToString("\n") { "${it.id} | ${it.label} | ${it.bounds.toShortString()}" }
        val ids = stops.mapNotNull { stop -> stop.id?.removePrefix("${ROW}s-")?.split("-")?.let { (section, n) -> section.toInt() to n.toInt() } }
        assertTrue("$screen: TalkBack reaches the first two songs\n$dump", (0 to 1) in ids && (0 to 2) in ids)
        assertEquals("$screen: rows read in list order\n$dump", ids.sortedWith(compareBy({ it.first }, { it.second })), ids)
        val min = with(rule.density) { 48.dp.toPx() } - 1
        stops.forEach { stop ->
            assertTrue("$screen: ${stop.id} is a button", stop.isClickable)
            assertTrue("$screen: ${stop.id} is labelled", stop.label != "<unlabelled>")
            // TalkBack bounds are clipped to the list; a row cut by its edge is checked by its
            // full height, every fully shown row by what TalkBack reports.
            val full = rule.onAllNodesWithTag(stop.id!!, useUnmergedTree = true)[0].fetchSemanticsNode().size.height
            assertTrue("$screen: ${stop.id} is at least 48 dp tall (full $full px)", full >= min)
            if (stop.bounds.height() >= full - 1) {
                assertTrue("$screen: ${stop.id} is at least 48 dp tall (${stop.bounds})", stop.bounds.height() >= min)
            }
        }
    }

    // endregion

    /**
     * Landscape/unfolded at 100 %: two row-major columns read start-then-end; at 200 %: one
     * column, same order.
     */
    @Test
    fun twoColumnsReadRowMajorStayOffTheFoldAndDropToOneColumnAtLargeText() {
        var scale by mutableFloatStateOf(1f)
        turnToLandscape()
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(stillBackground = true), SectionIndexFixtures.transport(), fontScale = { scale })
        h.waitForTag("$ROW$SECOND")
        h.requireHingeWhenAsked()
        h.publishTalkBackTree()

        val config = rule.activity.resources.configuration
        val fold = h.hinges().firstOrNull()
        val wide = fold != null || (config.screenWidthDp > config.screenHeightDp && config.screenWidthDp >= WIDE_WINDOW_DP)
        val first = bounds("$ROW$FIRST")
        val second = bounds("$ROW$SECOND")
        Log.i(JourneyHarness.READING_ORDER_TAG, "songs-wide | w${config.screenWidthDp}dp h${config.screenHeightDp}dp fold=$fold first=$first second=$second")
        if (wide) {
            assertEquals("two columns: the second song sits beside the first", first.top, second.top, 1f)
            assertTrue("start column first ($first | $second)", first.right <= second.left)
            assertTrue("the next section starts a new line in the leading column", bounds("$ROW$NEXT").top >= first.bottom)
        }
        fold?.let { hinge ->
            assertEquals("the leading column ends at the fold", hinge.left, first.right, 2f)
            assertEquals("the trailing column starts at the fold", hinge.right, second.left, 2f)
        }
        h.assertNothingStraddles("fst.songs.search", "$ROW$FIRST", "$ROW$SECOND", "$ROW$NEXT")
        assertRowsReadInListOrder("songs-wide-100")

        scale = 2f
        rule.waitForIdle()
        h.waitForTag("$ROW$SECOND")
        val big = bounds("$ROW$FIRST")
        val below = bounds("$ROW$SECOND")
        assertTrue("200 %: one column ($big | $below)", below.top >= big.bottom - 1)
        assertEquals("200 %: one column shares the start edge", big.left, below.left, 2f)
        // No straddle check here: at large text the one column is full width even across a fold
        // (`rememberSingleColumn`, as hinge splits elsewhere); the hinge checks run at 100 %.
        assertRowsReadInListOrder("songs-wide-200")
        h.assertAccessible()
    }

    private companion object {
        const val ROW = "fst.songs.row."
        const val FIRST = "s-0-1"
        const val SECOND = "s-0-2"
        const val NEXT = "s-1-1"

        /** A landscape window this wide holds two 320 dp columns beside the navigation rail. */
        const val WIDE_WINDOW_DP = 800
    }
}
