package com.festivalscoretracker.android.journeys

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.window.layout.FoldingFeature.Orientation
import androidx.window.layout.FoldingFeature.State
import androidx.window.testing.layout.FoldingFeature
import androidx.window.testing.layout.TestWindowLayoutInfo
import androidx.window.testing.layout.WindowLayoutInfoPublisherRule
import com.festivalscoretracker.android.core.model.Instrument
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
 * Issue #584 accessibility: the player page (Statistics tab, root `fst.player.available`) is a
 * row-major grid, so sections side by side start on one top edge however far the page scrolls,
 * under headings that span the whole width. This journey checks the layout on the real
 * accessibility tree:
 *
 * - **Flat, two columns:** Overview spans the grid; Lead and Bass share a top edge beneath it;
 *   TalkBack reads Overview, then Lead, then Bass (row by row, each cell whole); the Top Songs
 *   heading spans the grid, is a heading and its text is unclipped.
 * - **Half open (book posture):** Overview and the Top Songs heading keep to the leading panel
 *   (like Apple's full-width Overview above its `HingeGrid`); the instrument cards start the next
 *   row, Lead before the hinge and Bass after it on one top edge, read Overview, Lead, Bass;
 *   nothing straddles the hinge.
 * - **One column (phone):** portrait and compact windows are unchanged: Lead sits below
 *   Overview and is read after it.
 *
 * ATF (labels, 48 dp targets, contrast) runs on every step. Fixtures only. `@DeviceCi` runs the
 * one-column case on the `android-device` phone; `@HalfOpenFoldJourney` runs the fold case in
 * `android-fold`, where `fstRequireHinge=true` fails a window that shows one column flat. The
 * postures are synthetic vertical folds at the window centre ([WindowLayoutInfoPublisherRule]).
 * Locally: `device.py test com.festivalscoretracker.android.journeys.ProfileRowsAccessibilityJourneyTest
 * --avd FST_Book_Fold --posture half --runner-arg fstRequireHinge=true`; reading orders go to
 * logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
@HalfOpenFoldJourney
class ProfileRowsAccessibilityJourneyTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
    }

    // region Helpers

    /** Window bounds of the first node tagged [tag]. */
    private fun bounds(tag: String): Rect = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow

    /** The synthetic fold's x in window pixels (window centre, where [publish] puts it). */
    private fun foldX(): Float = rule.activity.window.decorView.width / 2f

    /**
     * Publish one vertical fold at the window centre and wait for [ready].
     *
     * @param state Flat (unfolded) or half opened (book posture).
     * @param ready The layout that posture should produce.
     */
    private fun publish(state: State, ready: () -> Boolean) {
        windowInfo.overrideWindowLayoutInfo(
            TestWindowLayoutInfo(listOf(FoldingFeature(rule.activity, state = state, orientation = Orientation.VERTICAL))),
        )
        try {
            rule.waitUntil(15_000) { ready() }
        } catch (failure: Throwable) {
            val seen = listOf(OVERVIEW, LEAD, BASS, GRID).joinToString { tag -> "$tag ${if (h.exists(tag)) bounds(tag) else "absent"}" }
            throw AssertionError("$state never produced the expected layout (fold ${foldX()}): $seen", failure)
        }
        rule.waitForIdle()
    }

    /**
     * Assert [labels] are all read, in that order.
     *
     * @param order Reading order.
     * @param labels Stops, first to last.
     * @param config Configuration, for messages.
     */
    private fun assertReadInOrder(order: List<String>, labels: List<String>, config: String) {
        val at = labels.map { label -> order.indexOfFirst { it == label || it.startsWith("$label, ") } }
        assertTrue("$config: TalkBack misses one of $labels: $order", at.all { it >= 0 })
        assertEquals("$config: $labels aren't read in order: $order", at.sorted(), at)
    }

    // endregion

    /**
     * Flat: full-width Overview over a row of Lead | Bass on one top edge, read row by row; half
     * open: Overview and the Top Songs heading in the leading panel, Lead | Bass on the next row
     * either side of the hinge. A one-column window keeps Lead below Overview.
     */
    @Test
    fun sideBySideSectionsShareARowUnderFullWidthHeadings() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Statistics, profile = PLAYER, stillBackground = true), transport)
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
        publish(State.FLAT) { h.exists(OVERVIEW) && h.exists(LEAD) }
        // One column may leave Bass below the viewport, uncomposed.
        val twoColumns = h.exists(BASS) && abs(bounds(LEAD).top - bounds(BASS).top) < 2f && bounds(BASS).left > bounds(LEAD).right
        if (InstrumentationRegistry.getArguments().getString(JourneyHarness.REQUIRE_HINGE_ARG) == "true") {
            assertTrue("the fold job needs a window two columns wide when flat (Lead ${bounds(LEAD)})", twoColumns)
        }
        h.awaitAccessibilityTree(present = OVERVIEW)
        val grid = bounds(GRID)
        val overview = bounds(OVERVIEW)
        val lead = bounds(LEAD)
        Log.i(JourneyHarness.READING_ORDER_TAG, "profile-rows flat | two columns $twoColumns | grid $grid | overview $overview | lead $lead")
        assertTrue("flat: Lead $lead is not below Overview $overview", lead.top >= overview.bottom)
        rule.onNode(hasText(OVERVIEW_LABEL) and hasAnyAncestor(hasTestTag(OVERVIEW)), useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        if (!twoColumns) {
            assertReadInOrder(h.readingOrder("profile-rows-one-column", fresh = true), listOf(OVERVIEW_LABEL, Instrument.Lead.label), "one column")
            h.assertAccessible()
            return
        }
        assertEquals("flat: Overview $overview doesn't span the grid $grid", grid.width, overview.width, 2f)
        assertEquals("flat: Lead $lead and Bass ${bounds(BASS)} don't share a top edge", lead.top, bounds(BASS).top, 1f)
        assertReadInOrder(h.readingOrder("profile-rows-flat", fresh = true), listOf(OVERVIEW_LABEL, Instrument.Lead.label, Instrument.Bass.label), "flat")
        h.scrollTo(GRID, TOP_SONGS)
        h.awaitAccessibilityTree(present = TOP_SONGS)
        assertEquals("flat: the Top Songs heading ${bounds(TOP_SONGS)} doesn't span the grid $grid", grid.width, bounds(TOP_SONGS).width, 2f)
        rule.onNode(hasText(TOP_SONGS_LABEL) and hasAnyAncestor(hasTestTag(TOP_SONGS)), useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        h.assertTextUnclipped("profile-rows flat", TOP_SONGS, TOP_SONGS_LABEL, 1f)
        h.assertAccessible()

        val fold = foldX()
        h.scrollTo(GRID, OVERVIEW)
        publish(State.HALF_OPENED) { h.exists(OVERVIEW) && h.exists(LEAD) && bounds(OVERVIEW).right <= fold + 1f && bounds(LEAD).right <= fold + 1f }
        h.awaitAccessibilityTree(present = LEAD)
        val halfOverview = bounds(OVERVIEW)
        val halfLead = bounds(LEAD)
        Log.i(JourneyHarness.READING_ORDER_TAG, "profile-rows half open | fold $fold | overview $halfOverview | lead $halfLead")
        assertTrue("half open: Lead $halfLead doesn't start the row under Overview $halfOverview", halfLead.top >= halfOverview.bottom - 1f)
        assertReadInOrder(h.readingOrder("profile-rows-half-open", fresh = true), listOf(OVERVIEW_LABEL, Instrument.Lead.label), "half open")
        h.scrollTo(GRID, BASS)
        h.awaitAccessibilityTree(present = BASS)
        val bass = bounds(BASS)
        assertTrue("half open: Bass $bass doesn't start after the hinge $fold", bass.left >= fold - 1f)
        assertEquals("half open: Lead ${bounds(LEAD)} and Bass $bass don't share a top edge", bounds(LEAD).top, bass.top, 1f)
        h.assertNothingStraddles(LEAD, BASS)
        h.scrollTo(GRID, TOP_SONGS)
        h.awaitAccessibilityTree(present = TOP_SONGS)
        assertTrue("half open: the Top Songs heading ${bounds(TOP_SONGS)} crosses the hinge $fold", bounds(TOP_SONGS).right <= fold + 1f)
        h.assertNothingStraddles(TOP_SONGS, LEAD, OVERVIEW)
        h.assertTextUnclipped("profile-rows half open", TOP_SONGS, TOP_SONGS_LABEL, 1f)
        h.assertAccessible()
    }

    private companion object {
        val PLAYER = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        const val GRID = "fst.player.available"
        const val OVERVIEW = "fst.player.overview"
        const val OVERVIEW_LABEL = "Overview"
        const val LEAD = "fst.player.instrument.Solo_Guitar"
        const val BASS = "fst.player.instrument.Solo_Bass"
        const val TOP_SONGS = "fst.player.top-songs"
        const val TOP_SONGS_LABEL = "Top Songs Per Instrument"
    }
}
