package com.festivalscoretracker.android.journeys

import androidx.activity.ComponentActivity
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Issue #97 accessibility (backfill #446): the player page has no avatar/name card; the top
 * bar names the player and the page starts at Overview. When there is something to say (a
 * paused selection or a failed Select), a plain identity row (`fst.player.identity`) sits
 * between them.
 *
 * TalkBack must read the player's name once (the title, never a repeated card heading or
 * initials), then the identity row's stops (the paused-selection notice as text with a
 * silent icon), then the Overview heading with nothing else between them. Since #590 Select,
 * Switch and Deselect are not in the page: they are their own pill beside Quick Links in the
 * floating toolbar row, a `Button` named "Select Profile" / "Switch to This Profile" /
 * "Deselect Profile" (visible "Select" / "Switch" / "Deselect"), read immediately before Quick
 * Links, with a 48 dp target that never overlaps
 * Quick Links'. At 100% and 200% text the pill and notice grow without clipping and keep that
 * order. ATF runs on every step. Fixtures only;
 * `@DeviceCi` puts it in the `android-device` job. Run with `device.py test
 * com.festivalscoretracker.android.journeys.ProfileIdentityAccessibilityJourneyTest --avd
 * FST_Phone`; reading orders go to logcat `FST_A11Y`.
 */
@RunWith(AndroidJUnit4::class)
@DeviceCi
class ProfileIdentityAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    // region Fixtures

    /**
     * Songs and both synthetic players' profiles.
     *
     * @param pinnedB Whether player B's profile carries a publication header; without it the
     *   page previews the scores but pauses selection with a notice.
     * @return Fixture transport.
     */
    private fun transport(pinnedB: Boolean = true) = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
        if (pinnedB) ProfileFixtures.register(this, Fixtures.ACCOUNT_B) else ProfileFixtures.register(this, Fixtures.ACCOUNT_B, headers = emptyMap())
    }

    // endregion

    // region Tests

    /**
     * A viewed (unselected) player: title → Overview with no identity row, and Select Profile
     * as its own pill read just before Quick Links, at every text size (#590).
     */
    @Test
    fun viewedPlayerReadsSelectPillBeforeQuickLinksAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true), transport(), fontScale = { scale })
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
        val heights = SCALES.map { s ->
            scale = s
            rule.waitForIdle()
            h.waitForTag(SELECT)
            h.waitForTag(OVERVIEW)
            assertFalse("Select brought back the in-page identity row", h.exists(IDENTITY))
            assertIdentityRow(h.readingOrder("profile-viewed-${s}x", fresh = true), title(), emptyList(), "viewed ${s}x")
            assertPillBesideQuickLinks("profile-viewed-${s}x", SELECT_LABEL)
            assertButton(SELECT, SELECT_LABEL, "viewed ${s}x")
        }
        assertTrue("200% text did not grow the Select pill ($heights px)", heights[1] > heights[0])
        h.assertAccessible()
    }

    /** Viewing another player while one is selected: the pill reads "Switch to This Profile", before Quick Links. */
    @Test
    fun otherPlayerReadsSwitchPillBeforeQuickLinks() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = PLAYER, route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true), transport())
        h.waitForTag(SELECT)
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
        assertFalse("Switch brought back the in-page identity row", h.exists(IDENTITY))
        assertIdentityRow(h.readingOrder("profile-switch", fresh = true), title(), emptyList(), "switch")
        assertPillBesideQuickLinks("profile-switch", SWITCH_LABEL)
        assertButton(SELECT, SWITCH_LABEL, "switch")
        h.assertAccessible()
    }

    /**
     * An unpinned profile is previewed but not selectable: the notice is read as text (its
     * icon silent) between the title and Overview, and wraps unclipped at 200%.
     */
    @Test
    fun pausedNoticeIsReadBeforeOverviewAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true), transport(pinnedB = false), fontScale = { scale })
                h.waitForTag(OVERVIEW)
                h.publishTalkBackTree()
                val heights = SCALES.map { s ->
            scale = s
            rule.waitForIdle()
            h.waitForTag(NOTICE)
            h.waitForTag(OVERVIEW)
            assertFalse("A paused profile offers Select", h.exists(SELECT))
            val order = h.readingOrder("profile-paused-${s}x", fresh = true)
            assertIdentityRow(order, title(), listOf(UNPINNED_NOTICE), "paused ${s}x")
            assertUnclipped(NOTICE, UNPINNED_NOTICE, "paused ${s}x")
            rule.onNodeWithTag(NOTICE, useUnmergedTree = true).fetchSemanticsNode().size.height
        }
        assertTrue("200% text did not grow the notice ($heights px)", heights[1] > heights[0])
        h.assertAccessible()
    }

    /**
     * The selected player's own page has no identity row: Overview is the first page stop
     * after the top bar, and the name is read once, as the title. Deselect Profile is its own
     * pill read immediately before Quick Links (#590 acceptance), a 48 dp `Button` at every
     * text size.
     */
    @Test
    fun selectedPlayerPageReadsDeselectPillBeforeQuickLinksAtEveryTextSize() {
        var scale by mutableFloatStateOf(1f)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = PLAYER, route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport(), fontScale = { scale })
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
        val heights = SCALES.map { s ->
            scale = s
            rule.waitForIdle()
            h.waitForTag(DESELECT)
            h.waitForTag(OVERVIEW)
            assertFalse("A selected player's page shows the identity row", h.exists(IDENTITY))
            assertFalse("A selected player's page offers Select", h.exists(SELECT))
            assertIdentityRow(h.readingOrder("profile-selected-${s}x", fresh = true), title(), emptyList(), "selected ${s}x")
            assertPillBesideQuickLinks("profile-selected-${s}x", DESELECT_LABEL, DESELECT)
            assertButton(DESELECT, DESELECT_LABEL, "selected ${s}x")
        }
        assertTrue("200% text did not grow the Deselect pill ($heights px)", heights[1] > heights[0])
        h.assertAccessible()
    }

    /**
     * Statistics (the same body under a "Statistics" title) starts at Overview and never reads
     * the name as a page item. Deselect Profile is its own pill read just before Quick Links (#590).
     */
    @Test
    fun statisticsStartsAtOverview() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Statistics, profile = PLAYER, stillBackground = true), transport())
        h.waitForTag("fst.statistics")
        h.waitForTag(OVERVIEW)
        h.waitForTag(DESELECT)
        h.publishTalkBackTree()
        assertFalse("Statistics shows the identity row", h.exists(IDENTITY))
        val order = h.readingOrder("statistics-selected", fresh = true)
        // The selected Statistics tab can repeat the title, so only the name is counted here.
        assertIdentityRow(order, title(), emptyList(), "statistics", titleOnce = false)
        assertTrue("Statistics reads the player's name as a page item: $order", order.none { it == PLAYER.displayName })
        assertPillBesideQuickLinks("statistics-selected", DESELECT_LABEL, DESELECT)
        assertButton(DESELECT, DESELECT_LABEL, "statistics")
        h.assertAccessible()
    }

    // endregion

    // region Assertions

    /** The page title's text (the player's name on the player page). */
    private fun title(): String = rule.onNodeWithTag(TITLE, useUnmergedTree = true).fetchSemanticsNode().text()

    /** Text of [this] node. */
    private fun SemanticsNode.text(): String = config.getOrNull(SemanticsProperties.Text)?.joinToString("") { it.text }.orEmpty()

    /**
     * Labels of the top bar's own stops (navigation, title, search, profile, actions), which
     * TalkBack may read between the title and the page.
     */
    private fun chromeLabels(): Set<String> = rule.onAllNodes(hasAnyAncestor(hasTestTag(TOP_BAR)), useUnmergedTree = true)
        .fetchSemanticsNodes()
        .flatMap { node ->
            listOfNotNull(node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(", "), node.text())
        }
        .filter { it.isNotBlank() }
        .toSet()

    /**
     * The title is read once, then only top-bar chrome, then exactly [identity] in order, then
     * the Overview heading; no avatar initials and no second copy of the title anywhere.
     *
     * @param order Reading order.
     * @param title Page title.
     * @param identity Identity-row stops expected between the title and Overview.
     * @param config Configuration name for messages.
     * @param titleOnce Whether the title text must be read exactly once.
     */
    private fun assertIdentityRow(order: List<String>, title: String, identity: List<String>, config: String, titleOnce: Boolean = true) {
        val t = order.indexOf(title)
        val o = order.indexOf(OVERVIEW_LABEL)
        assertTrue("$config: TalkBack never reads the title \"$title\": $order", t >= 0)
        assertTrue("$config: TalkBack never reads the Overview heading: $order", o > t)
        if (titleOnce) assertEquals("$config: the title \"$title\" is read more than once (a name card is back): $order", 1, order.count { it == title })
        val initials = SelectedPlayer("", title).initials
        assertTrue("$config: avatar initials \"$initials\" are read: $order", initials.isEmpty() || order.none { it == initials })
        val first = if (identity.isEmpty()) o else order.indexOf(identity.first())
        assertTrue("$config: ${identity.firstOrNull()} is not read between the title and Overview: $order", first in (t + 1)..o)
        assertEquals("$config: the identity row reads differently: $order", identity, order.subList(first, o))
        val chrome = chromeLabels()
        order.subList(t + 1, first).forEach { stop ->
            assertTrue("$config: \"$stop\" is read between the title and the page's first stop: $order", chrome.any { it == stop || it in stop || stop in it })
        }
        rule.onNode(hasText(OVERVIEW_LABEL).and(hasAnyAncestor(hasTestTag(OVERVIEW))), useUnmergedTree = true)
            .assert(SemanticsMatcher.keyIsDefined(SemanticsProperties.Heading))
    }

    /**
     * The identity pill ([tag], named [label]) and Quick Links are separate TalkBack stops, the
     * pill read immediately before Quick Links; both have 48 dp targets that do not overlap, in one row.
     */
    private fun assertPillBesideQuickLinks(screen: String, label: String, tag: String = SELECT) {
        val stops = h.readingStops(screen)
        val pill = stops.indexOfFirst { it.id == tag }
        val links = stops.indexOfFirst { it.id == QUICK_LINKS }
        assertTrue("$screen: TalkBack never reaches the identity pill: ${stops.map { it.label }}", pill >= 0)
        assertEquals("$screen: the pill is not read just before Quick Links: ${stops.map { it.label }}", pill + 1, links)
        assertEquals("$screen: pill label", label, stops[pill].label)
        h.assertTouchTarget(screen, tag)
        h.assertTouchTarget(screen, QUICK_LINKS)
        val a = stops[pill].bounds
        val b = stops[links].bounds
        assertFalse("$screen: the pill ($a) overlaps Quick Links ($b)", android.graphics.Rect.intersects(a, b))
        assertTrue("$screen: the pill ($a) is not before Quick Links ($b) in one row", a.right <= b.left && a.centerY() in b.top..b.bottom)
        assertFalse("$screen: the pill is inside the Quick Links pill", rule.onAllNodes(hasTestTag(tag).and(hasAnyAncestor(hasTestTag(TOOLBAR)))).fetchSemanticsNodes().isNotEmpty())
        assertTrue("$screen: the pill is not in the companion slot", rule.onAllNodes(hasTestTag(tag).and(hasAnyAncestor(hasTestTag(COMPANION)))).fetchSemanticsNodes().isNotEmpty())
    }

    /**
     * [tag] is one `Button` named [label] (its short visible text is silent, so TalkBack reads
     * the name once), at least 48 dp and wholly on screen. The visible text has no line limit
     * and the pill wraps it, so it grows with the text size instead of clipping.
     *
     * @return The button's height in pixels.
     */
    private fun assertButton(tag: String, label: String, config: String): Int {
        val node = rule.onNodeWithTag(tag)
        node.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(hasContentDescription(label))
        assertTrue("$config: $tag also reads its short text", node.fetchSemanticsNode().config.getOrNull(SemanticsProperties.Text).isNullOrEmpty())
        val size = node.fetchSemanticsNode().size
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("$config: $tag is $size px, under 48 dp", size.width >= min && size.height >= min)
        val box = node.fetchSemanticsNode().boundsInRoot
        val root = rule.onRoot().fetchSemanticsNode().boundsInRoot
        assertTrue("$config: $tag ($box) is not wholly on screen ($root)", box.left >= root.left && box.right <= root.right && box.bottom <= root.bottom)
        return size.height
    }

    /**
     * The text [label] inside [tag] is fully shown: no line ellipsized, no height overflow and
     * its bounds inside the container's. (The semantics text layout of a plain `Text` reports
     * the constraint width as its paragraph width, so its `didOverflowWidth` is not usable.)
     */
    private fun assertUnclipped(tag: String, label: String, config: String) {
        val text = rule.onNode(hasText(label).and(hasAnyAncestor(hasTestTag(tag)).or(hasTestTag(tag))), useUnmergedTree = true)
        val node = text.fetchSemanticsNode()
        val layouts = mutableListOf<TextLayoutResult>()
        node.config[SemanticsActions.GetTextLayoutResult].action?.invoke(layouts)
        assertTrue("$config: no text layout for \"$label\"", layouts.isNotEmpty())
        val layout = layouts.first()
        assertFalse("$config: \"$label\" overflows its height (${layout.size}, ${layout.lineCount} lines)", layout.didOverflowHeight)
        assertTrue("$config: \"$label\" is ellipsized", (0 until layout.lineCount).none { layout.isLineEllipsized(it) })
        val box = node.boundsInRoot
        val container = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        assertTrue(
            "$config: \"$label\" ($box) extends outside $tag ($container)",
            box.left >= container.left - 1 && box.top >= container.top - 1 && box.right <= container.right + 1 && box.bottom <= container.bottom + 1,
        )
    }

    // endregion

    private companion object {
        val SCALES = listOf(1f, 2f)
        val PLAYER = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        const val TOP_BAR = "fst.nav.top-bar"
        const val TITLE = "fst.nav.title"
        const val IDENTITY = "fst.player.identity"
        const val SELECT = "fst.player.select"
        const val NOTICE = "fst.player.identity-notice"
        const val OVERVIEW = "fst.player.overview"
        const val OVERVIEW_LABEL = "Overview"
        const val SELECT_LABEL = "Select Profile"
        const val SWITCH_LABEL = "Switch to This Profile"
        const val QUICK_LINKS = "fst.quick-links.open"
        const val TOOLBAR = "fst.nav.floating-toolbar"
        const val COMPANION = "fst.nav.floating-toolbar.companion"
        const val DESELECT = "fst.player.deselect"
        const val DESELECT_LABEL = "Deselect Profile"
        const val UNPINNED_NOTICE = "These scores have no verified publication. Selection is paused."
    }
}
