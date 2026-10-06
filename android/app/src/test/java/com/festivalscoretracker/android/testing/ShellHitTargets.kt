package com.festivalscoretracker.android.testing

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.ComposeTestRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertTrue

// region Probe

/**
 * Forgiving, non-overlapping hit regions for the shell's navigation-bar and toolbar buttons
 * (issues #72, #179): Quick Links, Sort, Filter, global Search, the bell, Profile and ⋮. Each
 * Material `IconButton` draws a 40 dp container and must keep a touch target of at least
 * [MIN_TARGET_DP] dp (Material's minimum, kept on large screens too); neighbouring targets must
 * not overlap, and a touch [OFF_CENTRE_DP] dp from the centre (outside the 40 dp container,
 * inside the 48 dp target) must activate the button. Shared by the Robolectric suite and the
 * connected device test, which supply their own waiting.
 *
 * @property rule The test's compose rule.
 * @property settle Lets the UI settle after an input (Robolectric idles its looper).
 * @property refocus Moves window focus to the top-most window (Robolectric never does).
 */
class ShellHitTargets(
    private val rule: ComposeTestRule,
    private val settle: () -> Unit = { rule.waitForIdle() },
    private val refocus: () -> Unit = {},
) {
    /** Whether a node with [tag] is composed. */
    fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    /** Waits for [condition], settling between polls. */
    fun await(what: String, condition: () -> Boolean) {
        try {
            rule.waitUntil(20_000) { settle(); condition() }
        } catch (timeout: Throwable) {
            throw AssertionError("Timed out waiting for $what", timeout)
        }
    }

    /** Touch bounds (layout bounds plus Material's minimum interactive padding) of [tag]. */
    fun touchBounds(tag: String): Rect = rule.onNodeWithTag(tag).fetchSemanticsNode().touchBoundsInRoot

    /**
     * Every present tag in [tags] has a touch target of at least [MIN_TARGET_DP] dp and no two
     * overlap (sharing an edge is fine).
     *
     * @param tags Candidate tags; absent ones are skipped.
     * @return The measured targets, by tag.
     */
    fun assertTargets(tags: List<String>): Map<String, Rect> {
        val min = with(rule.density) { MIN_TARGET_DP.dp.toPx() } - 1f
        val targets = tags.filter(::exists).associateWith(::touchBounds)
        targets.forEach { (tag, box) ->
            assertTrue("$tag touch target is ${box.width} x ${box.height} px (< $min)", box.width >= min && box.height >= min)
        }
        val list = targets.entries.toList()
        list.forEachIndexed { i, a ->
            list.drop(i + 1).forEach { b ->
                val overlap = a.value.intersect(b.value)
                val overlaps = overlap.width > OVERLAP_TOLERANCE_PX && overlap.height > OVERLAP_TOLERANCE_PX
                assertTrue("${a.key} ${a.value} overlaps ${b.key} ${b.value}", !overlaps)
            }
        }
        return targets
    }

    /** Offsets from a button's centre: up, down, start and end by [OFF_CENTRE_DP] dp. */
    fun offCentre(): List<Offset> {
        val d = with(rule.density) { OFF_CENTRE_DP.dp.toPx() }
        return listOf(Offset(0f, -d), Offset(0f, d), Offset(-d, 0f), Offset(d, 0f))
    }

    /** Touches [tag] at its centre plus [offset] (pixels). */
    fun touch(tag: String, offset: Offset) {
        rule.onNodeWithTag(tag).performTouchInput { click(center + offset) }
        settle()
    }

    /** Touches the centre of [tag]'s unmerged node (e.g. a decorative badge over a button). */
    fun touchCentreOf(tag: String, target: String) {
        val host = rule.onNodeWithTag(target).fetchSemanticsNode().boundsInRoot
        val inner = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot
        touch(target, inner.center - host.center)
    }

    /** Semantics click (no touch geometry), for controls this probe doesn't measure. */
    fun click(tag: String) {
        rule.onAllNodesWithTag(tag, useUnmergedTree = true)[0].performSemanticsAction(SemanticsActions.OnClick)
        settle()
    }

    /**
     * Touches [tool] at each [offCentre] offset (and [extra] offsets) and checks it activates every
     * time: one of [ShellTool.surfaces] appears, then [ShellTool.close] restores the page.
     *
     * @param tool Button under test.
     * @param extra Further touches (offsets from the centre).
     * @return Number of activations.
     */
    fun assertOffCentreTouchesActivate(tool: ShellTool, extra: List<Offset> = emptyList()): Int {
        var activated = 0
        (offCentre() + extra).forEach { offset ->
            await("${tool.tag} on the page") { exists(tool.tag) && tool.surfaces.none(::exists) }
            touch(tool.tag, offset)
            await("${tool.tag} touched at $offset to open ${tool.surfaces}") { tool.surfaces.any(::exists) }
            activated++
            tool.close(this)
            await("${tool.surfaces} to close") { tool.surfaces.none(::exists) }
        }
        return activated
    }

    /** Closes the Quick Links surface: the compact sheet's close button, or a menu item (the current section). */
    fun closeQuickLinks() {
        if (exists("fst.quick-links.sheet")) {
            click("fst.quick-links.close")
            return
        }
        val current = rule.onAllNodes(
            SemanticsMatcher("Quick Links item") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith("fst.quick-links.item.") == true },
        ).fetchSemanticsNodes().first().config[SemanticsProperties.TestTag]
        click(current)
    }

    /** Refocus hook for ⋮'s menu (closes after a tool's window closes, issue #160). */
    fun refocusTop() = refocus()

    companion object {
        /** Material minimum touch target. */
        const val MIN_TARGET_DP = 48

        /** Off-centre touch distance: outside the 40 dp icon-button container, inside the 48 dp target. */
        const val OFF_CENTRE_DP = 22

        /** Rounding allowance when comparing neighbouring targets. */
        const val OVERLAP_TOLERANCE_PX = 1f

        /** The shell's navigation-bar and toolbar buttons, in bar order. */
        val SHELL_TAGS = listOf(
            "fst.nav.drawer",
            "fst.nav.back",
            "fst.nav.overflow",
            "fst.quick-links.open",
            "fst.songs.sort.open",
            "fst.songs.filter.open",
            "fst.suggestions.filter-button",
            "fst.global-search.open",
            "fst.shell.notifications",
            "fst.nav.profile",
        )

        /** Songs' Sort. */
        val SORT = ShellTool("fst.songs.sort.open", "fst.songs.sort.form") { it.click("fst.songs.sort.done") }

        /** Songs' Filter. */
        val FILTER = ShellTool("fst.songs.filter.open", "fst.songs.filter.form") { it.click("fst.songs.filter.done") }

        /** Quick Links: a sheet on compact windows, a menu wider. */
        val QUICK_LINKS = ShellTool("fst.quick-links.open", listOf("fst.quick-links.sheet", "fst.quick-links.menu")) { it.closeQuickLinks() }

        /** Global search. */
        val SEARCH = ShellTool("fst.global-search.open", "fst.global-search.surface") { it.click("fst.global-search.close") }

        /** Notifications bell (a selected player only). */
        val BELL = ShellTool("fst.shell.notifications", "fst.notifications.sheet") { it.click("fst.notifications.close") }

        /** Profile without a selected player: the profile sheet. */
        val PROFILE_CHOOSE = ShellTool("fst.nav.profile", "fst.profile.sheet") { it.click("fst.profile.close") }

        /** Profile with a selected player: its Statistics page; back to Songs from the bar, rail or drawer. */
        val PROFILE_OPEN = ShellTool("fst.nav.profile", "fst.statistics") {
            it.click("fst.nav.tab.songs")
            it.await("Songs again") { it.exists("fst.songs.list") }
        }

        /**
         * ⋮ on a narrow list pane: its menu holds the page tools and closes once a tool's sheet has
         * closed (issue #160), so this closes it through Sort.
         */
        val OVERFLOW = ShellTool("fst.nav.overflow", "fst.nav.overflow-menu") {
            it.refocusTop()
            it.click("fst.songs.sort.open")
            it.await("Sort from ⋮") { it.exists("fst.songs.sort.form") }
            it.refocusTop()
            it.click("fst.songs.sort.done")
            it.await("Sort to close") { !it.exists("fst.songs.sort.form") }
            it.refocusTop()
        }
    }
}

/**
 * One shell button and what activating it shows.
 *
 * @property tag Button test tag.
 * @property surfaces Test tags of which one appears once it activated (a sheet, menu or page).
 * @property close Restores the page.
 */
class ShellTool(val tag: String, val surfaces: List<String>, val close: (ShellHitTargets) -> Unit) {
    constructor(tag: String, surface: String, close: (ShellHitTargets) -> Unit) : this(tag, listOf(surface), close)

    override fun toString() = tag
}

// endregion
