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
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
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
 * bar names the player and the page starts at Overview. When there is something to act on,
 * a plain identity row (`fst.player.identity`) sits between them.
 *
 * TalkBack must read the player's name once (the title, never a repeated card heading or
 * initials), then the identity row's stops (Select or Switch, a labelled 48 dp `Button`; the
 * paused-selection notice as text with a silent icon), then the Overview heading with nothing
 * else between them. A selected player's own page and Statistics have no identity row, so
 * Overview is the first page stop after the top bar. At 100% and 200% text the button and
 * notice grow without clipping and keep that order. ATF runs on every step. Fixtures only;
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

    /** A viewed (unselected) player: title → Select Profile → Overview, at every text size. */
    @Test
    fun viewedPlayerReadsTitleThenSelectThenOverviewAtEveryTextSize() {
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
            val order = h.readingOrder("profile-viewed-${s}x", fresh = true)
            assertIdentityRow(order, title(), listOf(SELECT_LABEL), "viewed ${s}x")
            assertButton(SELECT, SELECT_LABEL, "viewed ${s}x")
        }
        assertTrue("200% text did not grow Select Profile ($heights px)", heights[1] > heights[0])
        h.assertAccessible()
    }

    /** Viewing another player while one is selected: title → Switch to This Profile → Overview. */
    @Test
    fun otherPlayerReadsSwitchBeforeOverview() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = PLAYER, route = PlayerRoute(Fixtures.ACCOUNT_B, "Other"), stillBackground = true), transport())
        h.waitForTag(SELECT)
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
        val order = h.readingOrder("profile-switch", fresh = true)
        assertIdentityRow(order, title(), listOf(SWITCH_LABEL), "switch")
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
     * after the top bar, and the name is read once, as the title.
     */
    @Test
    fun selectedPlayerPageStartsAtOverview() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = PLAYER, route = PlayerRoute(Fixtures.ACCOUNT_A), stillBackground = true), transport())
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
        assertFalse("A selected player's page shows the identity row", h.exists(IDENTITY))
        assertIdentityRow(h.readingOrder("profile-selected", fresh = true), title(), emptyList(), "selected")
        h.assertAccessible()
    }

    /** Statistics (the same body under a "Statistics" title) starts at Overview and never reads the name as a page item. */
    @Test
    fun statisticsStartsAtOverview() {
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(section = FestivalSection.Statistics, profile = PLAYER, stillBackground = true), transport())
        h.waitForTag("fst.statistics")
        h.waitForTag(OVERVIEW)
        h.publishTalkBackTree()
        assertFalse("Statistics shows the identity row", h.exists(IDENTITY))
        val order = h.readingOrder("statistics-selected", fresh = true)
        // The selected Statistics tab can repeat the title, so only the name is counted here.
        assertIdentityRow(order, title(), emptyList(), "statistics", titleOnce = false)
        assertTrue("Statistics reads the player's name as a page item: $order", order.none { it == PLAYER.displayName })
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
     * [tag] is one `Button` named [label], at least 48 dp, with its label unclipped.
     *
     * @return The button's height in pixels.
     */
    private fun assertButton(tag: String, label: String, config: String): Int {
        val node = rule.onNodeWithTag(tag)
        node.assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Button))
            .assert(hasText(label))
        val size = node.fetchSemanticsNode().size
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("$config: $tag is $size px, under 48 dp", size.width >= min && size.height >= min)
        assertUnclipped(tag, label, config)
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
        const val UNPINNED_NOTICE = "These scores have no verified publication. Selection is paused."
    }
}
