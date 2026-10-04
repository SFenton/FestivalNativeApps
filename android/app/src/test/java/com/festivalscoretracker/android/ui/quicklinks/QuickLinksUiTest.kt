package com.festivalscoretracker.android.ui.quicklinks

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.DeviceConfigurationOverride
import androidx.compose.ui.test.FontScale
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.compose.ui.unit.width
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.testing.QuickLinksHarness
import com.festivalscoretracker.android.testing.QuickLinksHarnessPage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * The Quick Links control's reachable states (contract `quick-links`: hidden-single-section,
 * menu-closed, menu-open, active-section, jumped) on a synthetic page, for both compact
 * (bottom sheet) and medium (anchored menu) presentations, with TalkBack semantics and
 * 48 dp touch targets (issue #137).
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class QuickLinksUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private lateinit var controller: QuickLinksController
    private lateinit var listState: LazyListState

    // region Helpers

    private fun show(sections: Int = 6, windowWidthDp: Int = COMPACT, fontScale: Float = 1f) {
        rule.setContent {
            DeviceConfigurationOverride(DeviceConfigurationOverride.FontScale(fontScale)) {
                listState = androidx.compose.foundation.lazy.rememberLazyListState()
                QuickLinksHarnessPage(sections, windowWidthDp, listState) { controller = it }
            }
        }
        rule.waitForIdle()
    }

    private fun exists(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()

    private fun waitForTag(tag: String) = rule.waitUntil(5_000) { exists(tag) }

    private fun waitGone(tag: String) = rule.waitUntil(5_000) { !exists(tag) }

    private fun entryLabel(): String =
        rule.onNodeWithTag(OPEN).fetchSemanticsNode().config[SemanticsProperties.ContentDescription].single()

    private fun open(surface: String) {
        rule.onNodeWithTag(OPEN).performClick()
        waitForTag(surface)
    }

    private fun item(id: String) = rule.onNodeWithTag("fst.quick-links.item.$id", useUnmergedTree = true)

    private fun itemTags(): List<String> =
        rule.onAllNodes(SemanticsMatcher("quick link item") { it.config.getOrNull(SemanticsProperties.TestTag)?.startsWith(ITEM_PREFIX) == true }, useUnmergedTree = true)
            .fetchSemanticsNodes()
            .sortedBy { it.boundsInRoot.top }
            .map { it.config[SemanticsProperties.TestTag].removePrefix(ITEM_PREFIX) }

    /** Asserts exactly [id] is the selected item, with the spoken "Current section" state. */
    private fun assertCurrent(id: String, ids: List<String>) {
        ids.forEach { other ->
            val node = item(other).fetchSemanticsNode().config
            assertEquals("selected for $other", other == id, node.getOrNull(SemanticsProperties.Selected))
            assertEquals(if (other == id) "Current section" else null, node.getOrNull(SemanticsProperties.StateDescription))
        }
    }

    private fun headerOffsetDp(id: String): Float {
        val list = rule.onNodeWithTag(QuickLinksHarness.LIST_TAG).getUnclippedBoundsInRoot().top
        return (rule.onNodeWithTag(QuickLinksHarness.headerTag(id)).getUnclippedBoundsInRoot().top - list).value
    }

    // endregion

    // region hidden-single-section

    @Test
    fun hiddenWithFewerThanTwoSectionsAndShownFromTwo() {
        val count = mutableIntStateOf(0)
        rule.setContent { QuickLinksHarnessPage(count.intValue, COMPACT) { controller = it } }
        rule.waitForIdle()
        assertFalse(exists(OPEN))
        count.intValue = 1
        rule.waitForIdle()
        assertFalse("one section: a jump list would do nothing", exists(OPEN))
        assertFalse(controller.available)
        count.intValue = 2
        waitForTag(OPEN)
        assertTrue(controller.available)
        count.intValue = 1
        waitGone(OPEN)
    }

    // endregion

    // region menu-closed

    @Test
    fun closedEntryIsALabelledButtonNamingTheCurrentSection() {
        show()
        val node = rule.onNodeWithTag(OPEN).fetchSemanticsNode()
        assertEquals("Quick Links, current section Section 1", entryLabel())
        assertEquals(Role.Button, node.config.getOrNull(SemanticsProperties.Role))
        // The 40 dp M3 icon button reserves a 48 dp touch target (what TalkBack and ATF measure).
        val touch = node.touchBoundsInRoot
        val min = with(rule.density) { 48.dp.toPx() } - 1
        assertTrue("touch target ${touch.width} × ${touch.height} px", touch.width >= min && touch.height >= min)
        assertFalse(exists(SHEET))
        assertFalse(exists(MENU))
    }

    // endregion

    // region menu-open

    @Test
    fun compactOpensASheetListingSectionsInPageOrder() {
        show()
        open(SHEET)
        assertFalse(exists(MENU))
        val sheet = rule.onNodeWithTag(SHEET, useUnmergedTree = true).fetchSemanticsNode().config
        assertEquals("Quick Links", sheet.getOrNull(SemanticsProperties.PaneTitle))
        val ids = QuickLinksHarness.sections(6).map { it.id }
        assertEquals(ids, itemTags())
        assertCurrent("section-0", ids)
        // Spoken labels follow the web landmarkLabel, and every row is a 48 dp+ target.
        assertEquals(listOf("Section 3 (spoken)"), item("section-2").fetchSemanticsNode().config[SemanticsProperties.ContentDescription])
        ids.forEach { id ->
            val bounds = item(id).getUnclippedBoundsInRoot()
            assertTrue("$id height ${bounds.height}", bounds.height.value >= 48f)
        }
        // The selected indicator is inset equally from both sheet edges (24 dp, like the title and close glyph).
        val list = rule.onNodeWithTag("fst.quick-links.list", useUnmergedTree = true).getUnclippedBoundsInRoot()
        val row = item("section-0").getUnclippedBoundsInRoot()
        assertEquals(24f, (row.left - list.left).value, 0.5f)
        assertEquals(24f, (list.right - row.right).value, 0.5f)
        // Close returns to the closed state without moving the page.
        rule.onNodeWithTag("fst.quick-links.close", useUnmergedTree = true).performSemanticsAction(SemanticsActions.OnClick)
        waitGone(SHEET)
        assertEquals(0, listState.firstVisibleItemIndex)
        assertEquals("Quick Links, current section Section 1", entryLabel())
    }

    @Test
    fun mediumOpensAnAnchoredMenuListingSectionsInPageOrder() {
        show(windowWidthDp = MEDIUM)
        open(MENU)
        assertFalse(exists(SHEET))
        val ids = QuickLinksHarness.sections(6).map { it.id }
        assertEquals(ids, itemTags())
        assertCurrent("section-0", ids)
        ids.forEach { id ->
            val bounds = item(id).getUnclippedBoundsInRoot()
            assertTrue("$id height ${bounds.height}", bounds.height.value >= 48f)
        }
    }

    // endregion

    // region active-section

    @Test
    fun scrollingPastASectionMakesItCurrent() {
        show()
        rule.onNodeWithTag(QuickLinksHarness.LIST_TAG).performScrollToIndex(QuickLinksHarness.headerIndex("section-2")!!)
        rule.waitUntil(5_000) { controller.activeId == "section-2" }
        assertEquals("Quick Links, current section Section 3", entryLabel())
        rule.onNodeWithTag(OPEN).performSemanticsAction(SemanticsActions.OnClick)
        waitForTag(SHEET)
        assertCurrent("section-2", QuickLinksHarness.sections(6).map { it.id })
    }

    // endregion

    // region jumped

    @Test
    fun sheetJumpClosesLandsThe32DpLineAndOwnsTheSection() {
        show()
        open(SHEET)
        item("section-3").performSemanticsAction(SemanticsActions.OnClick)
        waitGone(SHEET)
        rule.waitForIdle()
        assertEquals(32f, headerOffsetDp("section-3"), 1f)
        assertEquals("section-3", controller.activeId)
        rule.onNodeWithTag(OPEN).assert(SemanticsMatcher.expectValue(SemanticsProperties.ContentDescription, listOf("Quick Links, current section Section 4")))
    }

    @Test
    fun menuJumpClosesAndOwnsTheSection() {
        show(windowWidthDp = MEDIUM)
        open(MENU)
        item("section-1").performSemanticsAction(SemanticsActions.OnClick)
        waitGone(MENU)
        rule.waitForIdle()
        assertEquals(32f, headerOffsetDp("section-1"), 1f)
        assertEquals("Quick Links, current section Section 2", entryLabel())
    }

    @Test
    fun aNearEndTargetThatCannotReachTheTopStaysCurrentWhileVisible() {
        show()
        open(SHEET)
        item("section-5").performSemanticsAction(SemanticsActions.OnClick)
        waitGone(SHEET)
        rule.waitForIdle()
        // The list hit its end, so the last heading sits below the activation line, yet it owns the jump.
        assertFalse(listState.canScrollForward)
        assertTrue(headerOffsetDp("section-5") > 32f)
        assertEquals("section-5", controller.activeId)
        // Scrolling it out of view releases ownership to the natural section.
        rule.onNodeWithTag(QuickLinksHarness.LIST_TAG).performScrollToIndex(0)
        rule.waitUntil(5_000) { controller.activeId == "section-0" }
    }

    @Test
    fun jumpsTeleportRatherThanAnimate() {
        show()
        assertFalse(controller.animate)
    }

    // endregion

    // region Large text

    @Test
    fun doubleTextKeepsTheSameStatesAndTargets() {
        // Robolectric does not wrap at real glyph widths here; 200% wrapping is proven on the emulator.
        show(fontScale = 2f)
        assertEquals("Quick Links, current section Section 1", entryLabel())
        open(SHEET)
        val ids = QuickLinksHarness.sections(6).map { it.id }
        assertCurrent("section-0", ids)
        ids.take(3).forEach { id ->
            val row = item(id).getUnclippedBoundsInRoot()
            assertTrue("$id height ${row.height}", row.height.value >= 56f)
        }
    }

    @Test
    fun menuMarksTheCurrentSectionUnderItsTitleNotBesideIt() {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.width(MENU_TEXT_SLOT.dp)) { QuickLinkMenuLabel("Show Instrument Metadata", current = true) }
            }
        }
        val title = rule.onNodeWithTag(MENU_TITLE_TAG, useUnmergedTree = true).getUnclippedBoundsInRoot()
        val marker = rule.onNodeWithTag(MENU_CURRENT_TAG, useUnmergedTree = true).getUnclippedBoundsInRoot()
        // Below the title, so the title keeps the menu item's whole text width.
        assertTrue("marker top ${marker.top} vs title bottom ${title.bottom}", marker.top >= title.bottom)
    }

    @Test
    fun menuLabelOfOtherSectionsHasNoMarker() {
        rule.setContent { FestivalTheme { QuickLinkMenuLabel("Diagnostics", current = false) } }
        assertFalse(exists(MENU_CURRENT_TAG))
    }

    // endregion

    private companion object {
        /** M3 menu item text slot: 280 dp cap − 2 × 12 dp padding − 24 dp icon − 12 dp gap. */
        const val MENU_TEXT_SLOT = 220
        const val OPEN = "fst.quick-links.open"
        const val SHEET = "fst.quick-links.sheet"
        const val MENU = "fst.quick-links.menu"
        const val ITEM_PREFIX = "fst.quick-links.item."
        const val COMPACT = 411
        const val MEDIUM = 700
    }
}
