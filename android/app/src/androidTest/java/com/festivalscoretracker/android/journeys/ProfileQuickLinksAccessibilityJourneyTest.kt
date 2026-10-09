package com.festivalscoretracker.android.journeys

import android.util.Log
import androidx.activity.ComponentActivity
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
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #106 accessibility (backfill #501): the Player Profile page's Quick Links and the shell
 * drawer that hosts it.
 *
 * #106 made a Quick Links jump *hold* its section on the landing line while cards above it load
 * (Rank History composes on the jump and used to push Top Songs half a screen down), and made
 * the shell host every page inside one `ModalNavigationDrawer` that stays closed (and empty at
 * permanent-drawer widths) across layout changes. On the real profile page, at 100% and 200%
 * text, this journey checks what TalkBack gets:
 * - the entry is one 48 dp `Button` named "Quick Links, current section …";
 * - the chooser (sheet on compact windows, menu on wider ones) reads its rows in page order
 *   (Global Statistics, the instruments, Top Songs, Bands), each named by its spoken title, the
 *   current row selected with "Current section", every whole row at least 48 dp (`quick-links` R6);
 *   the > 8-section sheet opens partially expanded, and its lower rows come up through the drag
 *   handle's Expand action, the path TalkBack offers;
 * - after a jump to Top Songs the entry names Top Songs, and the "Top Songs Per Instrument"
 *   heading stays a heading on the 32 dp landing line, unclipped, after the cards above have
 *   loaded (`section-jump-landing` R2, R6);
 * - the closed drawer and its scrim are never in the reading order, the hidden modal sheet is
 *   empty at permanent widths even when launched open, and Back hands an open drawer back to
 *   the page.
 *
 * ATF runs on every step. Fixtures only; `@DeviceCi` and the `android-device` job run it. Run with
 * `device.py test com.festivalscoretracker.android.journeys.ProfileQuickLinksAccessibilityJourneyTest
 * --avd FST_Book_Fold` (folded: sheet; `--posture unfolded`: menu); reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class ProfileQuickLinksAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Fixtures

    /** Songs and the synthetic player's profile, rank history and bands. */
    private fun transport() = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
    }

    /**
     * Open the selected player's own page (no identity row) at [scale] text.
     *
     * @param scale Font scale.
     * @param opensDrawer Launch with the navigation drawer open.
     */
    private fun launchProfile(scale: Float, opensDrawer: Boolean = false) {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = PLAYER, route = PlayerRoute(Fixtures.ACCOUNT_A), opensDrawer = opensDrawer, stillBackground = true), transport(), fontScale = { scale })
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
    }

    // endregion

    // region Tests

    /** Entry, chooser and a held jump to Top Songs at 100% text. */
    @Test
    fun quickLinksReadInPageOrderAndAJumpHoldsItsHeading() = quickLinksJourney(1f)

    /** The same at 200% text: rows stay 48 dp and in order, the landed heading grows unclipped. */
    @Test
    fun quickLinksAtDoubleTextKeepTargetsOrderAndLanding() = quickLinksJourney(2f)

    /**
     * The closed drawer is out of TalkBack's order. At permanent widths the modal sheet that
     * hosts the pages stays closed and empty even when launched open; otherwise the open drawer
     * reads its rows and Back returns TalkBack to the page.
     */
    @Test
    fun closedDrawerStaysOutOfTheReadingOrder() {
        launchProfile(1f, opensDrawer = true)
        if (h.exists(PERMANENT_DRAWER)) {
            rule.waitUntil(5_000) { h.accessibilityNode(MODAL_DRAWER) == null }
            val rows = rule.onAllNodes(drawerRow and hasAnyAncestor(hasTestTag(MODAL_DRAWER)), useUnmergedTree = true).fetchSemanticsNodes()
            assertTrue("permanent: the hidden modal sheet holds ${rows.size} drawer rows", rows.isEmpty())
        } else {
            h.waitForTag("${DRAWER_ROW}deselect")
            rule.waitUntil(5_000) { h.accessibilityNode(MODAL_DRAWER) != null }
            val open = h.readingOrder("profile-drawer-open")
            assertTrue("modal: the open drawer does not read Deselect profile: $open", open.any { it.startsWith(DESELECT_LABEL) })
            rule.runOnUiThread { rule.activity.onBackPressedDispatcher.onBackPressed() }
            rule.waitUntil(10_000) { h.accessibilityNode(MODAL_DRAWER) == null }
        }
        assertNull("the closed drawer's sheet is visible to TalkBack", h.accessibilityNode(MODAL_DRAWER))
        val closed = h.readingOrder("profile-drawer-closed", fresh = true)
        assertTrue("the closed drawer's scrim is read: $closed", closed.none { it.contains(SCRIM_LABEL) })
        if (!h.exists(PERMANENT_DRAWER)) {
            assertTrue("modal: a closed drawer's rows are read: $closed", closed.none { it.startsWith(DESELECT_LABEL) })
        }
        assertTrue("the page's Overview heading is not read: $closed", closed.contains(OVERVIEW_LABEL))
        h.assertAccessible()
    }

    // endregion

    // region Journey

    /**
     * Entry → chooser → jump to Top Songs, checked as TalkBack reads it.
     *
     * @param scale Font scale.
     */
    private fun quickLinksJourney(scale: Float) {
        val config = "${scale}x"
        launchProfile(scale)
        rule.waitUntil(10_000) { entryLabel()?.startsWith("$TITLE, current section ") == true }
        assertEntry(config, current = "Global Statistics")
        assertTrue("$config: the drawer is in the page's reading order", h.readingOrder("profile-quick-links-$config").none { it.contains(SCRIM_LABEL) })

        h.tap(OPEN)
        val sheet = QuickLinks.usesSheet(windowWidthDp())
        val chooser = if (sheet) SHEET else MENU
        h.waitForTag(chooser)
        assertChooser(config, current = "global")

        if (sheet) {
            // The > 8-section sheet opens partially expanded (M3 default): its lower rows sit below the
            // screen until the drag handle's Expand action, the path TalkBack offers, raises it.
            rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.Expand), useUnmergedTree = true)
                .onFirst().performSemanticsAction(SemanticsActions.Expand)
            rule.waitForIdle()
            h.scrollTo(LIST, TOP_SONGS_ITEM)
        } else {
            rule.onNodeWithTag(TOP_SONGS_ITEM).performScrollTo()
        }
        rule.waitForIdle()
        rule.onNodeWithTag(TOP_SONGS_ITEM)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf(TOP_SONGS_HEADING)))
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Selected, false))
        h.assertTouchTarget("$config chooser", TOP_SONGS_ITEM)
        h.tap(TOP_SONGS_ITEM)
        h.waitGone(chooser)

        rule.waitUntil(10_000) { entryLabel() == "$TITLE, current section Top Songs" }
        val landed = headingTop()
        // #106: the cards above (Rank History) load after the jump; the section must stay put.
        Thread.sleep(HOLD_CHECK_MS)
        rule.waitForIdle()
        val held = headingTop()
        Log.i(JourneyHarness.READING_ORDER_TAG, "profile-quick-links $config | landed $landed | held $held | line ${landingLine()}")
        val tolerance = with(rule.density) { LANDING_TOLERANCE_DP.dp.toPx() }
        assertTrue("$config: Top Songs landed at $landed px, not on the landing line ${landingLine()} px", abs(landed - landingLine()) <= tolerance)
        assertTrue("$config: Top Songs moved from $landed to $held px as the cards above loaded", abs(held - landed) <= tolerance)
        assertEntry(config, current = "Top Songs")
        rule.onNode(hasText(TOP_SONGS_HEADING) and hasAnyAncestor(hasTestTag(TOP_SONGS)), useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
        h.assertTextUnclipped("profile-quick-links $config", TOP_SONGS, TOP_SONGS_HEADING, scale)

        val after = h.readingOrder("profile-quick-links-jumped-$config", fresh = true)
        assertTrue("$config: the landed heading is not read: $after", after.contains(TOP_SONGS_HEADING))
        assertTrue("$config: the entry does not name Top Songs: $after", after.any { it.startsWith("$TITLE, current section Top Songs") })
        h.assertAccessible()
    }

    // endregion

    // region Assertions

    /**
     * The entry is one 48 dp `Button` named after the current section.
     *
     * @param config Configuration name for messages.
     * @param current Current section's title.
     */
    private fun assertEntry(config: String, current: String) {
        assertEquals("$config: entry label", "$TITLE, current section $current", entryLabel())
        rule.onAllNodesWithTag(OPEN)[0].assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
        h.assertTouchTarget("$config entry", OPEN)
    }

    /**
     * The open chooser's rows are in page order (Global Statistics, instruments, Top Songs,
     * Bands) both on screen and as TalkBack reads them; the current row is selected and says so;
     * every shown row is a named target of at least 48 dp.
     *
     * @param config Configuration name for messages.
     * @param current Current section ID.
     */
    private fun assertChooser(config: String, current: String) {
        val items = rule.onAllNodes(quickLinkItem, useUnmergedTree = true).fetchSemanticsNodes()
            // Unclipped: rows scrolled out of the chooser's viewport collapse to its edge in boundsInWindow.
            .sortedBy { it.positionInWindow.y }
            .map { it.config[SemanticsProperties.TestTag].removePrefix(ITEM_PREFIX) to it }
        val ids = items.map { it.first }
        assertEquals("$config: the chooser starts at Global Statistics: $ids", "global", ids.first())
        assertEquals("$config: chooser rows out of page order: $ids", ids.sortedBy(::sectionRank), ids)
        items.forEach { (id, node) ->
            val name = node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" ").orEmpty()
            assertTrue("$config: Quick Link $id has no name", name.isNotBlank())
            assertEquals("$config: Quick Link $id selected", id == current, node.config.getOrNull(SemanticsProperties.Selected))
            assertEquals("$config: Quick Link $id state", if (id == current) "Current section" else null, node.config.getOrNull(SemanticsProperties.StateDescription))
        }
        val order = h.readingOrder("profile-quick-links-chooser-$config")
        val shown = items.filter { (id, _) -> h.accessibilityNode("$ITEM_PREFIX$id") != null }
        assertTrue("$config: fewer than two chooser rows are shown: ${shown.map { it.first }}", shown.size >= 2)
        val positions = shown.map { (id, node) ->
            val name = node.config[SemanticsProperties.ContentDescription].joinToString(" ")
            order.indexOfFirst { it.startsWith(name) }.also { assertTrue("$config: TalkBack never reads Quick Link $id ($name): $order", it >= 0) }
        }
        assertEquals("$config: TalkBack reads the rows out of page order: $order", positions.sorted(), positions)
        assertTrue("$config: the current row is not read as current: $order", order.any { it.startsWith("Global Statistics") && it.contains("Current section") })
        // A row cut by the chooser's scroll edge reports its clipped bounds; measure whole rows.
        shown.filter { (_, node) -> node.boundsInWindow.height >= node.size.height - 1 }
            .also { assertTrue("$config: no whole chooser row is shown", it.isNotEmpty()) }
            .forEach { (id, _) -> h.assertTouchTarget("$config chooser", "$ITEM_PREFIX$id") }
    }

    // endregion

    // region Helpers

    /** Chooser rows. */
    private val quickLinkItem = SemanticsMatcher("Quick Links row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(ITEM_PREFIX) == true }

    /** Navigation drawer rows. */
    private val drawerRow = SemanticsMatcher("drawer row") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(DRAWER_ROW) == true }

    /**
     * Page-order rank of a profile Quick Link ID (`ProfileSections.quickLinks`).
     *
     * @param id Section ID.
     * @return Rank.
     */
    private fun sectionRank(id: String): Int = when {
        id == "global" -> 0
        id.startsWith("instrument:") -> 1
        id == "top-songs" -> 2
        id == "bands" -> 3
        else -> throw AssertionError("unexpected profile Quick Link $id")
    }

    /** What TalkBack reads for the Quick Links entry. */
    private fun entryLabel(): String? = rule.onAllNodesWithTag(OPEN).fetchSemanticsNodes().firstOrNull()
        ?.config?.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" ")

    /** The window's width in dp. */
    private fun windowWidthDp(): Int = with(rule.density) { rule.activity.window.decorView.width.toDp().value.toInt() }

    /** Top of the Top Songs section in window pixels. */
    private fun headingTop(): Float = rule.onNodeWithTag(TOP_SONGS, useUnmergedTree = true).fetchSemanticsNode().boundsInWindow.top

    /** Where a Quick Links jump lands a section: 32 dp below the top bar. */
    private fun landingLine(): Float =
        rule.onNodeWithTag(TOP_BAR, useUnmergedTree = true).fetchSemanticsNode().boundsInWindow.bottom +
            with(rule.density) { QuickLinks.LANDING_OFFSET_DP.dp.toPx() }

    // endregion

    private companion object {
        val PLAYER = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        const val TITLE = "Quick Links"
        const val OPEN = "fst.quick-links.open"
        const val SHEET = "fst.quick-links.sheet"
        const val MENU = "fst.quick-links.menu"
        const val LIST = "fst.quick-links.list"
        const val ITEM_PREFIX = "fst.quick-links.item."
        const val TOP_SONGS_ITEM = "${ITEM_PREFIX}top-songs"
        const val TOP_SONGS = "fst.player.top-songs"
        const val TOP_SONGS_HEADING = "Top Songs Per Instrument"
        const val OVERVIEW = "fst.player.overview"
        const val OVERVIEW_LABEL = "Overview"
        const val TOP_BAR = "fst.nav.top-bar"
        const val MODAL_DRAWER = "fst.nav.modal-drawer"
        const val PERMANENT_DRAWER = "fst.nav.permanent-drawer"
        const val DRAWER_ROW = "fst.nav.drawer."
        const val DESELECT_LABEL = "Deselect profile"

        /** Material's label for the open drawer's scrim. */
        const val SCRIM_LABEL = "Close navigation menu"

        /** How long after landing the section must still be on its line (cards above load in this time with fixtures). */
        const val HOLD_CHECK_MS = 1_500L

        /** Landing tolerance: twice the controller's 8 dp completion threshold. */
        const val LANDING_TOLERANCE_DP = 16
    }
}
