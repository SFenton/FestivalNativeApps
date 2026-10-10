package com.festivalscoretracker.android.journeys

import android.util.Log
import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
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
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.testing.BandFixtures
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import kotlinx.coroutines.CompletableDeferred
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Tracker issue #111 accessibility (backfill #502): the Statistics tab (the selected player's
 * own page, root `fst.statistics`). #111 fixed three things a TalkBack or large-text reader
 * meets on Android, and this journey checks each on the real accessibility tree:
 *
 * - **Bands landing hold.** A Quick Links jump to Bands lands before the bands preview has
 *   loaded; when its groups arrive below, the jump's 3 s hold (`QuickLinks.LANDING_HOLD_MS`)
 *   lands the "{name}'s Bands" heading on the 32 dp line again instead of leaving it low on the
 *   screen. At 100% and 200% text: the entry names Bands, the heading stays a heading on the
 *   landing line, unclipped, its 48 dp View All follows it, and TalkBack reads heading → Duos
 *   → the first band card with no leftover "Loading bands".
 * - **Text size changed while loading.** A font-size change recreates the activity, which
 *   cancelled the selected player's read and left Statistics on "Loading player" forever. The
 *   journey holds the read, switches to 200% text and re-creates the app
 *   ([JourneyHarness.recreateApp]); the page must finish loading and read Overview as a
 *   heading, unclipped at 200%.
 * - **Fold split after a jump.** Unfolded (flat) → Top Songs → half open → Quick Links back to
 *   Global Statistics used to keep stale lanes: a gap beside Overview and the Lead card off
 *   screen and out of TalkBack's reach. After the posture change Overview stays in the leading
 *   pane, Lead sits beside it after the hinge, and TalkBack reads Overview then Lead.
 *
 * ATF (labels, 48 dp targets, contrast) runs on every step. Fixtures only; `android-device`
 * runs the class (`@DeviceCi`). The fold case needs a window that is two lanes wide when flat
 * (otherwise half-opening changes the lane count and the stale-lane bug cannot occur), so it is
 * skipped on the CI phone and runs in `android-fold` (`@HalfOpenFoldJourney`, where
 * `fstRequireHinge=true` fails a compact window instead). Postures are synthetic vertical folds
 * at the window centre ([WindowLayoutInfoPublisherRule]). Locally: `device.py test
 * com.festivalscoretracker.android.journeys.StatisticsAccessibilityJourneyTest --avd FST_Phone`
 * and `--avd FST_Book_Fold --posture unfolded`; reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class StatisticsAccessibilityJourneyTest {
    @get:Rule(order = 0)
    val windowInfo = WindowLayoutInfoPublisherRule()

    @get:Rule(order = 1)
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Fixtures

    /** Songs and the synthetic player's profile, rankings and rank history. */
    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
    }

    /**
     * Band previews tall enough to scroll the Bands heading to the landing line: Duos has more
     * than the preview (six cards and View All), Trios is empty and Quads fits.
     *
     * @param transport Transport to extend.
     */
    private fun installGroupedBands(transport: FakeTransport) {
        BandFixtures.install(transport)
        transport.on(BANDS_PATH) { request ->
            val size = Regex("pageSize=(\\d+)").find(request.url)!!.groupValues[1].toInt()
            when (Regex("group=(\\w+)").find(request.url)!!.groupValues[1]) {
                "duos" -> BandFixtures.playerBands(8, 1, size, "duos")
                "quads" -> BandFixtures.playerBands(2, 1, size, "quads", idPrefix = "q-")
                "trios" -> BandFixtures.playerBands(0, 1, size, "trios")
                else -> BandFixtures.playerBands(30, 1, size)
            }
        }
    }

    /**
     * Open the Statistics tab for the selected synthetic player.
     *
     * @param transport Fixture transport.
     * @param scale Font scale, read in composition.
     */
    private fun launchStatistics(transport: FakeTransport, scale: () -> Float) {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Statistics, profile = PLAYER, stillBackground = true), transport, fontScale = scale)
    }

    // endregion

    // region Bands landing

    /** A jump to Bands holds the heading on the landing line while the preview loads, at 100% text. */
    @Test
    fun bandsJumpHoldsItsHeadingWhileThePreviewLoads() = bandsJourney(1f)

    /** The same at 200% text: the heading grows unclipped and the order holds. */
    @Test
    fun bandsJumpAtDoubleTextHoldsItsHeading() = bandsJourney(2f)

    /**
     * Jump to Bands with the preview read held, release it, then check the landed section as
     * TalkBack reads it.
     *
     * @param scale Font scale.
     */
    private fun bandsJourney(scale: Float) {
        val config = "${scale}x"
        val bands = CompletableDeferred<Unit>()
        val transport = transport().also(::installGroupedBands)
        transport.beforeRespond = { request -> if (path(request.url) == BANDS_PATH) bands.await() }
        launchStatistics(transport) { scale }
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
        rule.waitUntil(10_000) { entryLabel()?.startsWith("$TITLE, current section ") == true }

        jumpTo(config, "bands", "Bands")
        // The preview starts reading when the Bands row is first composed: the jump lands on its loading state.
        h.waitForTag(BANDS_LOADING)
        val beforeLoad = headingTop(BANDS)
        bands.complete(Unit)
        h.waitForTag(DUOS)
        // Inside the 3 s hold the groups arrive below the heading; it must land again, then stay.
        Thread.sleep(HOLD_CHECK_MS)
        rule.waitForIdle()
        val held = headingTop(BANDS)
        val line = landingLine()
        Log.i(JourneyHarness.READING_ORDER_TAG, "statistics-bands $config | before load $beforeLoad | held $held | line $line | can scroll ${canScrollForward()}")
        val tolerance = with(rule.density) { LANDING_TOLERANCE_DP.dp.toPx() }
        // A window tall enough to show every group at once ends the list above the line (the end clamps the jump).
        assertTrue(
            "$config: after the bands loaded the Bands heading is at $held px, not on the landing line $line px (it landed at $beforeLoad px)",
            abs(held - line) <= tolerance || (held > line && !canScrollForward()),
        )

        assertEquals("$config: entry label", "$TITLE, current section Bands", entryLabel())
        rule.onNode(hasText(BANDS_HEADING) and hasAnyAncestor(hasTestTag(BANDS)), useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        h.assertTextUnclipped("statistics-bands $config", BANDS, BANDS_HEADING, scale)
        h.assertTouchTarget("$config bands View All", BANDS_LINK)
        rule.onNodeWithTag(DUOS, useUnmergedTree = true).assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        rule.onNodeWithTag(FIRST_BAND).assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        h.assertTouchTarget("$config first band card", FIRST_BAND)

        val order = h.readingOrder("statistics-bands-landed-$config", fresh = true)
        val heading = order.indexOf(BANDS_HEADING)
        val duos = order.indexOf("Duos")
        assertTrue("$config: the landed Bands heading is not read: $order", heading >= 0)
        assertTrue("$config: Duos is not read after the Bands heading: $order", duos > heading)
        val card = rule.onNodeWithTag(FIRST_BAND).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].joinToString(" ")
        assertTrue("$config: the first band card ($card) is not read right after Duos: $order", order.getOrNull(duos + 1)?.startsWith(card) == true)
        assertTrue("$config: the loading state is still read: $order", order.none { it.startsWith("Loading bands") })
        assertTrue("$config: the entry does not name Bands: $order", order.any { it.startsWith("$TITLE, current section Bands") })
        h.assertAccessible()
    }

    // endregion

    // region Text size while loading

    /**
     * A font-size change while the selected player's read is in flight re-creates the activity;
     * the read resumes and Statistics finishes loading at the new size.
     */
    @Test
    fun textSizeChangeWhileLoadingStillFinishesLoading() {
        var scale by mutableFloatStateOf(1f)
        val firstRead = CompletableDeferred<Unit>()
        val transport = transport()
        transport.beforeRespond = { request ->
            if (path(request.url) == PLAYER_PATH && transport.sent(PLAYER_PATH).size == 1) firstRead.await()
        }
        launchStatistics(transport) { scale }
        h.waitForTag(LOADING)
        h.publishTalkBackTree()
        val loading = h.readingOrder("statistics-loading", fresh = true)
        assertTrue("the loading state is unlabelled: $loading", loading.any { it.startsWith(LOADING_LABEL) })

        scale = 2f
        h.recreateApp()
        try {
            h.waitForTag(OVERVIEW)
        } catch (failure: Throwable) {
            throw AssertionError("Statistics never finished loading after the text size changed mid-read (${transport.sent(PLAYER_PATH).size} player reads): ${h.readingOrder("statistics-stuck", fresh = true)}", failure)
        }
        h.waitGone(LOADING)
        rule.waitForIdle()

        val loaded = h.readingOrder("statistics-after-text-size", fresh = true)
        assertTrue("the loading state is still read: $loaded", loaded.none { it.startsWith(LOADING_LABEL) })
        assertTrue("Overview is not read: $loaded", loaded.contains(OVERVIEW_LABEL))
        rule.onNode(hasText(OVERVIEW_LABEL) and hasAnyAncestor(hasTestTag(OVERVIEW)), useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        h.assertTextUnclipped("statistics 2.0x after recreation", OVERVIEW, OVERVIEW_LABEL, 2f)
        firstRead.complete(Unit)
        h.assertAccessible()
    }

    // endregion

    // region Fold split

    /**
     * Flat → Top Songs → half open → Global Statistics: Overview stays in the leading pane and
     * the Lead card sits beside it after the hinge, where TalkBack reaches it next.
     */
    @Test
    @HalfOpenFoldJourney
    fun quickLinksBackToGlobalAfterHalfOpeningKeepLeadBesideOverview() {
        launchStatistics(transport()) { 1f }
        publish(State.FLAT) { h.exists(OVERVIEW) && h.exists(LEAD) }
        h.publishTalkBackTree()
        // One lane may leave Bass below the viewport, uncomposed.
        val twoLanes = h.exists(BASS) && abs(bounds(LEAD).top - bounds(BASS).top) < 2f && bounds(BASS).left > bounds(LEAD).right
        if (InstrumentationRegistry.getArguments().getString(JourneyHarness.REQUIRE_HINGE_ARG) == "true") {
            assertTrue("the fold job needs a window two lanes wide when flat (Lead ${bounds(LEAD)}, Bass ${if (h.exists(BASS)) bounds(BASS) else "not composed"})", twoLanes)
        }
        assumeTrue("flat shows one lane here: half-opening changes the lane count, so stale lanes cannot occur", twoLanes)
        rule.waitUntil(10_000) { entryLabel()?.startsWith("$TITLE, current section ") == true }

        jumpTo("flat", "top-songs", "Top Songs")
        val fold = foldX()
        // Split at the fold, the Top Songs heading takes one pane (either) instead of straddling the hinge.
        publish(State.HALF_OPENED) { h.exists(TOP_SONGS) && bounds(TOP_SONGS).let { it.right <= fold + 1f || it.left >= fold - 1f } }
        jumpTo("half open", "global", "Global Statistics")
        try {
            rule.waitUntil(10_000) { h.exists(LEAD) }
        } catch (failure: Throwable) {
            throw AssertionError("half open: Lead never appeared beside Overview (stale lanes left a gap): ${h.readingOrder("statistics-fold-stale", fresh = true)}", failure)
        }
        rule.waitForIdle()

        val overview = bounds(OVERVIEW)
        val lead = bounds(LEAD)
        val grid = bounds(GRID)
        Log.i(JourneyHarness.READING_ORDER_TAG, "statistics-fold | fold $fold | overview $overview | lead $lead | grid $grid")
        assertTrue("half open: Overview $overview runs past the hinge $fold", overview.right <= fold + 1f)
        assertTrue("half open: Lead $lead is not after the hinge $fold", lead.left >= fold - 1f)
        assertTrue("half open: Lead $lead is not beside Overview $overview (a lane gap hid it)", lead.top < overview.bottom && lead.top >= grid.top)

        val order = h.readingOrder("statistics-fold-global", fresh = true)
        val overviewAt = order.indexOf(OVERVIEW_LABEL)
        val leadAt = order.indexOf(Instrument.Lead.label)
        assertTrue("half open: Overview is not read: $order", overviewAt >= 0)
        assertTrue("half open: Lead is not read after Overview: $order", leadAt > overviewAt)
        rule.onNode(hasText(Instrument.Lead.label) and hasAnyAncestor(hasTestTag(LEAD)), useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        assertEquals("half open: entry label", "$TITLE, current section Global Statistics", entryLabel())
        h.assertAccessible()
    }

    // endregion

    // region Helpers

    /**
     * Open Quick Links, check the row is a named 48 dp target, pick it and wait for the entry to
     * name the section.
     *
     * @param config Configuration name for messages.
     * @param id Section ID.
     * @param title Section title the entry names.
     */
    private fun jumpTo(config: String, id: String, title: String) {
        h.tap(OPEN)
        val sheet = QuickLinks.usesSheet(windowWidthDp())
        val chooser = if (sheet) SHEET else MENU
        h.waitForTag(chooser)
        val item = "$ITEM_PREFIX$id"
        if (sheet) {
            // The > 8-section sheet opens partially expanded; its drag handle's Expand action (TalkBack's path) raises it.
            val expand = rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.Expand), useUnmergedTree = true)
            if (expand.fetchSemanticsNodes().isNotEmpty()) expand.onFirst().performSemanticsAction(SemanticsActions.Expand)
            rule.waitForIdle()
            h.scrollTo(LIST, item)
        } else {
            rule.onNodeWithTag(item).performScrollTo()
        }
        rule.waitForIdle()
        val name = rule.onNodeWithTag(item).fetchSemanticsNode().config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" ").orEmpty()
        assertTrue("$config: Quick Link $id has no name", name.isNotBlank())
        h.assertTouchTarget("$config chooser", item)
        h.tap(item)
        h.waitGone(chooser)
        rule.waitUntil(10_000) { entryLabel() == "$TITLE, current section $title" }
    }

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
            val seen = listOf(OVERVIEW, LEAD, TOP_SONGS, GRID).joinToString { tag -> "$tag ${if (h.exists(tag)) bounds(tag) else "absent"}" }
            throw AssertionError("$state never produced the expected layout (fold ${foldX()}): $seen", failure)
        }
        rule.waitForIdle()
    }

    /** The synthetic fold's x in window pixels (window centre, where [publish] puts it). */
    private fun foldX(): Float = rule.activity.window.decorView.width / 2f

    /** Window bounds of the first node tagged [tag]. */
    private fun bounds(tag: String): Rect = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().first().boundsInWindow

    /** What TalkBack reads for the Quick Links entry. */
    private fun entryLabel(): String? = rule.onAllNodesWithTag(OPEN).fetchSemanticsNodes().firstOrNull()
        ?.config?.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" ")

    /** The window's width in dp. */
    private fun windowWidthDp(): Int = with(rule.density) { rule.activity.window.decorView.width.toDp().value.toInt() }

    /** Top of the section tagged [tag] in window pixels. */
    private fun headingTop(tag: String): Float = bounds(tag).top

    /** Where a Quick Links jump lands a section: 32 dp below the top bar. */
    private fun landingLine(): Float =
        bounds(TOP_BAR).bottom + with(rule.density) { QuickLinks.LANDING_OFFSET_DP.dp.toPx() }

    /** Whether the profile grid can scroll further down. */
    private fun canScrollForward(): Boolean =
        rule.onNodeWithTag(GRID).fetchSemanticsNode().config.getOrNull(SemanticsProperties.VerticalScrollAxisRange)
            ?.let { it.value() < it.maxValue() } ?: false

    /** URL path without the query. */
    private fun path(url: String) = "/" + url.substringAfter("://").substringAfter('/').substringBefore('?')

    // endregion

    private companion object {
        val PLAYER = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        val PLAYER_PATH = "/api/player/${Fixtures.ACCOUNT_A}"
        val BANDS_PATH = "/api/player/${Fixtures.ACCOUNT_A}/bands"
        const val TITLE = "Quick Links"
        const val OPEN = "fst.quick-links.open"
        const val SHEET = "fst.quick-links.sheet"
        const val MENU = "fst.quick-links.menu"
        const val LIST = "fst.quick-links.list"
        const val ITEM_PREFIX = "fst.quick-links.item."
        const val TOP_BAR = "fst.nav.top-bar"
        const val GRID = "fst.player.available"
        const val LOADING = "fst.player.loading"
        const val LOADING_LABEL = "Loading player"
        const val OVERVIEW = "fst.player.overview"
        const val OVERVIEW_LABEL = "Overview"
        const val LEAD = "fst.player.instrument.Solo_Guitar"
        const val BASS = "fst.player.instrument.Solo_Bass"
        const val TOP_SONGS = "fst.player.top-songs"
        const val BANDS = "fst.player.bands"
        const val BANDS_LOADING = "fst.player.bands.loading"
        const val BANDS_LINK = "fst.player.bands-link"
        const val BANDS_HEADING = "Synthetic Player's Bands"
        const val DUOS = "fst.player.bands.header.duos"
        const val FIRST_BAND = "fst.player-bands.row.${BandFixtures.DUO_ID}"

        /** How long after the bands load the heading must still be on its line (inside the 3 s hold). */
        const val HOLD_CHECK_MS = 1_500L

        /** Landing tolerance: twice the controller's 8 dp completion threshold. */
        const val LANDING_TOLERANCE_DP = 16
    }
}
