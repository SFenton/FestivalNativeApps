package com.festivalscoretracker.android.journeys

import android.os.Build
import android.util.Log
import android.view.View
import android.view.ViewGroup
import androidx.activity.ComponentActivity
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.graphics.Outline
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.hasAnyAncestor
import androidx.compose.ui.test.hasContentDescriptionExactly
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.isHeading
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.testing.FakeTransport
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.ProfileFixtures
import com.festivalscoretracker.android.ui.shell.concentricDrawerShape
import com.festivalscoretracker.android.ui.shell.readWindowCorners
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Accessibility of the modal navigation drawer's concentric corners (issue #419 for #55): the
 * sheet's start corners follow the display corners (≈44–50 dp on the FST phones and folds)
 * instead of Material's square start, so this journey checks nothing readable or tappable is
 * cut off by them. At the device's text size and at 200 %, every drawer row and the title lie
 * wholly inside the sheet's drawn outline, rows keep 48 dp targets, their labels, tab role and
 * selected state, TalkBack reads title → entries → footer, the text grows, and the footer's
 * Settings row scrolls fully into view. ATF runs on every state. Run with `device.py test
 * com.festivalscoretracker.android.journeys.DrawerCornersAccessibilityJourneyTest --avd …`;
 * skipped where the window shows the permanent drawer instead of the modal one.
 */
@RunWith(AndroidJUnit4::class)
class DrawerCornersAccessibilityJourneyTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)
    private val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
    private val transport = FakeTransport.standard().apply {
        on("/api/songs", headers = mapOf("X-FST-Publication-Id" to "7")) { Fixtures.songsJson.replace("\"alpha-512.jpg\"", "null") }
        ProfileFixtures.register(this)
    }

    /** Drawer rows (entries, profile row, Deselect, Settings) inside the modal sheet. */
    private val drawerRow = SemanticsMatcher("modal drawer row") {
        it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(ROW_PREFIX) == true
    } and hasAnyAncestor(hasTestTag(MODAL_SHEET))

    /** The drawer's title heading. */
    private val drawerTitle = hasText(TITLE) and isHeading() and hasAnyAncestor(hasTestTag(MODAL_SHEET))

    @Test
    @DeviceCi
    fun drawerContentClearsTheConcentricCorners() {
        val deviceScale = rule.activity.resources.configuration.fontScale
        var scale by mutableFloatStateOf(deviceScale)
        h.enableAccessibilityChecks()
        h.launch(DebugLaunch(profile = player, opensDrawer = true, stillBackground = true), transport, fontScale = { scale })
        h.waitForTag("fst.songs.list")
        h.waitForTag("fst.nav.drawer-sheet")
        assumeTrue("this window shows the permanent drawer, not the modal sheet", h.exists(MODAL_SHEET) && h.exists("$ROW_PREFIX$SETTINGS"))
        val settingsTextHeights = mutableListOf<Float>()
        listOf(deviceScale, LARGE_TEXT).distinct().forEach { s ->
            scale = s
            rule.waitForIdle()
            h.waitForTag("$ROW_PREFIX$SETTINGS")
            assertRolesAndState("fs $s")
            scrollDrawerTo(drawerTitle)
            assertInsideOutline("fs $s top", mustShow = "${ROW_PREFIX}songs")
            assertReadingOrder("fs $s")
            scrollDrawerTo(hasTestTag("$ROW_PREFIX$SETTINGS"))
            assertInsideOutline("fs $s bottom", mustShow = "$ROW_PREFIX$SETTINGS")
            h.readingOrder("drawer-corners fs $s bottom")
            settingsTextHeights += rule.onNode(hasText("Settings") and hasAnyAncestor(hasTestTag("$ROW_PREFIX$SETTINGS")), useUnmergedTree = true)
                .fetchSemanticsNode().boundsInRoot.height
        }
        if (deviceScale < LARGE_TEXT) assertTrue("drawer text grows at 200 % ($settingsTextHeights)", settingsTextHeights.last() > settingsTextHeights.first())
        h.assertAccessible()
    }

    // region Checks

    /**
     * Every drawer row has a label; entries are tabs with Songs selected and Settings not.
     *
     * @param config Configuration name for messages.
     */
    private fun assertRolesAndState(config: String) {
        rule.onNode(drawerTitle, useUnmergedTree = true).assertExists("$config: the drawer title is a heading")
        rule.onNodeWithTag("${ROW_PREFIX}songs").assertIsSelected()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
        rule.onNodeWithTag("$ROW_PREFIX$SETTINGS").assertIsNotSelected()
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Tab))
        rule.onAllNodes(drawerRow).fetchSemanticsNodes().forEach { node ->
            val label = listOfNotNull(
                node.config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" "),
                node.config.getOrNull(SemanticsProperties.Text)?.joinToString(" ") { it.text },
            ).joinToString(" ").trim()
            assertTrue("$config: ${node.tag} has no label", label.isNotEmpty())
        }
        rule.onNodeWithTag("${ROW_PREFIX}player").assert(hasContentDescriptionExactly("Profile: Synthetic Player"))
        rule.onNodeWithTag("${ROW_PREFIX}deselect").assert(hasContentDescriptionExactly("Deselect profile"))
    }

    /**
     * Each row and the title shown wholly within the drawer's scroll viewport lies inside the
     * sheet's drawn outline (all four corners of its bounds, 1 px in), and each row is at least
     * 48 dp in both directions.
     *
     * @param config Configuration name for messages.
     * @param mustShow A row tag that must be wholly shown at this scroll position.
     */
    private fun assertInsideOutline(config: String, mustShow: String) {
        val sheet = rule.onNodeWithTag(MODAL_SHEET).fetchSemanticsNode().boundsInRoot
        val viewport = rule.onNodeWithTag("fst.nav.drawer-sheet").fetchSemanticsNode().boundsInRoot
        val outline = drawerOutline(sheet)
        Log.i(JourneyHarness.READING_ORDER_TAG, "drawer-corners $config | sheet $sheet | outline $outline")
        val min = with(rule.density) { 48.dp.toPx() } - 1
        val nodes = rule.onAllNodes(drawerRow, useUnmergedTree = true).fetchSemanticsNodes() +
            rule.onAllNodes(drawerTitle, useUnmergedTree = true).fetchSemanticsNodes()
        val shown = nodes.filter { viewport.inflate(0.5f).contains(it.boundsInRoot) }
        assertTrue("$config: $mustShow is not wholly shown in $viewport", shown.any { it.tag == mustShow })
        shown.forEach { node ->
            val box = node.boundsInRoot.translate(-sheet.left, -sheet.top).deflate(1f)
            listOf(box.topLeft, box.topRight, box.bottomRight, box.bottomLeft).forEach { point ->
                assertTrue("$config: ${node.label} reaches outside the drawer outline at $point ($outline)", outline.contains(point))
            }
            if (node.config.contains(SemanticsActions.OnClick)) {
                val size = node.boundsInRoot
                assertTrue("$config: ${node.label} is ${size.width} × ${size.height} px, under 48 dp", size.width >= min && size.height >= min)
            }
        }
    }

    /**
     * TalkBack reads the title, then the shown entries, profile row, Deselect and Settings in
     * that order (the drawer is one traversal group, so they follow the title contiguously).
     *
     * @param config Configuration name for messages.
     */
    private fun assertReadingOrder(config: String) {
        val viewport = rule.onNodeWithTag("fst.nav.drawer-sheet").fetchSemanticsNode().boundsInRoot
        val shownTags = rule.onAllNodes(drawerRow, useUnmergedTree = true).fetchSemanticsNodes()
            .filter { viewport.inflate(0.5f).contains(it.boundsInRoot) }.map { it.tag }.toSet()
        val expected = READING_ORDER.filter { (tag, _) -> tag in shownTags }.map { it.second }
        // UiAutomation's node cache keeps bounds and text from before the font-scale switch.
        if (Build.VERSION.SDK_INT >= 34) InstrumentationRegistry.getInstrumentation().uiAutomation.clearCache()
        val labels = h.readingOrder("drawer-corners $config")
        var at = labels.indexOfFirst { it.startsWith(TITLE) }
        assertTrue("$config: the drawer title is not read ($labels)", at >= 0)
        expected.forEach { name ->
            val next = (at + 1 until labels.size).firstOrNull { labels[it].startsWith(name) }
            assertTrue("$config: \"$name\" is not read after \"${labels[at]}\" ($labels)", next != null)
            at = next!!
        }
        assertEquals("$config: Songs is read first after the title", "Songs", labels[labels.indexOfFirst { it.startsWith(TITLE) } + 1].substringBefore(","))
    }

    // endregion

    // region Helpers

    /**
     * The modal sheet's drawn outline in sheet coordinates: the same concentric shape the app
     * passes to `ModalDrawerSheet`, from this window's reported display corners, over Material's
     * `DrawerDefaults.shape` (square start, 16 dp end).
     *
     * @param sheet The sheet's bounds in the root.
     * @return The outline as a rounded rectangle.
     */
    private fun drawerOutline(sheet: Rect): RoundRect {
        val fallback = RoundedCornerShape(topStart = 0.dp, topEnd = 16.dp, bottomEnd = 16.dp, bottomStart = 0.dp)
        val composeView = rule.activity.findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
        val window = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) rule.runOnUiThread { readWindowCorners(composeView) } else null
        val rtl = rule.activity.resources.configuration.layoutDirection == View.LAYOUT_DIRECTION_RTL
        val outline = concentricDrawerShape(window, fallback).createOutline(sheet.size, if (rtl) LayoutDirection.Rtl else LayoutDirection.Ltr, rule.density)
        return when (outline) {
            is Outline.Rounded -> outline.roundRect
            is Outline.Rectangle -> RoundRect(outline.rect, CornerRadius.Zero)
            is Outline.Generic -> throw AssertionError("the drawer shape is not a rounded rectangle")
        }
    }

    /**
     * Scroll the drawer's single scrolling column so [target] is shown.
     *
     * @param target Matcher for a node inside the drawer.
     */
    private fun scrollDrawerTo(target: SemanticsMatcher) {
        rule.onAllNodes(target and hasAnyAncestor(hasTestTag(MODAL_SHEET)), useUnmergedTree = true)[0].performScrollTo()
        rule.waitForIdle()
    }

    /** Whether this rectangle wholly contains [other]. */
    private fun Rect.contains(other: Rect) = other.left >= left && other.top >= top && other.right <= right && other.bottom <= bottom

    /** The node's test tag. */
    private val SemanticsNode.tag get() = config.getOrNull(SemanticsProperties.TestTag)

    /** The node's tag or, for the title, its text. */
    private val SemanticsNode.label get() = tag ?: config.getOrNull(SemanticsProperties.Text)?.joinToString(" ") { it.text } ?: "?"

    // endregion

    private companion object {
        /** The modal sheet's test tag. */
        const val MODAL_SHEET = "fst.nav.modal-drawer"

        /** Prefix of the modal drawer's row tags. */
        const val ROW_PREFIX = "fst.nav.drawer."

        /** Settings row tag suffix. */
        const val SETTINGS = "settings"

        /** The drawer's title text. */
        const val TITLE = "Festival Score Tracker"

        /** 200 % text. */
        const val LARGE_TEXT = 2f

        /** Drawer row tags and the start of what TalkBack reads for each, in reading order. */
        val READING_ORDER = listOf(
            "${ROW_PREFIX}songs" to "Songs",
            "${ROW_PREFIX}suggestions" to "Suggestions",
            "${ROW_PREFIX}statistics" to "Statistics",
            "${ROW_PREFIX}rivals" to "Rivals",
            "${ROW_PREFIX}leaderboards" to "Leaderboards",
            "${ROW_PREFIX}shop" to "Item Shop",
            "${ROW_PREFIX}player" to "Profile: Synthetic Player",
            "${ROW_PREFIX}deselect" to "Deselect profile",
            "$ROW_PREFIX$SETTINGS" to "Settings",
        )
    }
}
