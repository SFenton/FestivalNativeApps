package com.festivalscoretracker.android.quicklinks

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import com.festivalscoretracker.android.ui.quicklinks.MENU_TITLE_TAG
import com.festivalscoretracker.android.ui.quicklinks.QuickLinkMenuLabel
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.unit.Density
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.journeys.JourneyHarness
import com.festivalscoretracker.android.testing.QuickLinksHarness
import com.festivalscoretracker.android.testing.QuickLinksHarnessPage
import com.festivalscoretracker.android.ui.quicklinks.QuickLinksController
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Quick Links control on a real device (issue #137): every reachable state
 * (`hidden-single-section`, `menu-closed`, `menu-open`, `active-section`, `jumped`) for the
 * compact sheet and the medium menu, with the Accessibility Test Framework over each state
 * (48 dp targets, labels, contrast) and TalkBack's reading order logged under `FST_A11Y`.
 * Run with `device.py test com.festivalscoretracker.android.quicklinks.QuickLinksDeviceTest --avd <AVD>`.
 */
@RunWith(AndroidJUnit4::class)
class QuickLinksDeviceTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val h = JourneyHarness(rule)

    private var controller: QuickLinksController? = null

    // region Helpers

    private fun show(sections: Int, widthDp: Int, fontScale: Float = 1f) {
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, density.fontScale * fontScale)) {
                QuickLinksHarnessPage(sections, widthDp, onController = { controller = it })
            }
        }
        rule.waitForIdle()
    }

    private fun itemTag(i: Int) = "fst.quick-links.item.section-$i"

    private fun entryLabel(order: List<String>, current: String) =
        assertTrue("entry announces $current: $order", order.any { it.contains("${QuickLinksHarness.TITLE}, current section $current") })

    private fun assertPageOrder(order: List<String>, titles: List<String>) {
        val positions = titles.map { title -> order.indexOfFirst { it.startsWith(title) } }
        assertTrue("every section is read: $order", positions.none { it < 0 })
        assertEquals("sections read in page order: $order", positions.sorted(), positions)
    }

    // endregion

    // region States

    /** `hidden-single-section`: one section shows no entry at all. */
    @Test
    fun hiddenWithOneSection() {
        show(1, COMPACT)
        assertFalse(h.exists("fst.quick-links.open"))
    }

    /** Compact: `menu-closed` → `menu-open` (sheet) → `jumped` → `active-section`. */
    @Test
    fun compactSheetStatesReadInOrder() {
        h.enableAccessibilityChecks()
        show(SECTIONS, COMPACT)
        entryLabel(h.readingOrder("closed"), "Section 1")

        h.tap("fst.quick-links.open")
        h.waitForTag("fst.quick-links.sheet")
        val open = h.readingOrder("sheet")
        assertPageOrder(open, (1..SECTIONS).map { if (it == 3) "Section 3 (spoken)" else "Section $it" })
        assertTrue("current announced: $open", open.any { it.startsWith("Section 1") && it.contains("Current section") })

        h.tap(itemTag(3))
        h.waitGone("fst.quick-links.sheet")
        rule.waitUntil(5_000) { controller?.activeId == "section-3" }
        entryLabel(h.readingOrder("jumped"), "Section 4")
        assertEquals(false, controller?.animate)
        h.assertAccessible()
    }

    /** Medium: scrolling makes a section current; the menu marks it and jumps back. */
    @Test
    fun mediumMenuStatesReadInOrder() {
        h.enableAccessibilityChecks()
        show(SECTIONS, MEDIUM)
        rule.onNodeWithTag(QuickLinksHarness.LIST_TAG).performScrollToIndex(QuickLinksHarness.headerIndex("section-2")!!)
        rule.waitUntil(5_000) { controller?.activeId == "section-2" }
        entryLabel(h.readingOrder("active"), "Section 3")

        h.tap("fst.quick-links.open")
        h.waitForTag("fst.quick-links.menu")
        val open = h.readingOrder("menu")
        assertTrue("current announced: $open", open.any { it.startsWith("Section 3 (spoken)") && it.contains("Current section") })

        h.tap(itemTag(1))
        h.waitGone("fst.quick-links.menu")
        rule.waitUntil(5_000) { controller?.activeId == "section-1" }
        entryLabel(h.readingOrder("jumped"), "Section 2")
        h.assertAccessible()
    }

    /** Double text keeps every sheet row a reachable ≥ 48 dp target and the same order. */
    @Test
    fun doubleTextSheetKeepsTargets() {
        h.enableAccessibilityChecks()
        show(SECTIONS, COMPACT, fontScale = 2f)
        h.tap("fst.quick-links.open")
        h.waitForTag("fst.quick-links.sheet")
        assertPageOrder(h.readingOrder("sheet-2x"), listOf("Section 1", "Section 2", "Section 3 (spoken)"))
        h.assertAccessible()
    }

    /** Double text in the menu's 220 dp text slot wraps long titles at spaces, never mid-word. */
    @Test
    fun doubleTextMenuTitlesBreakOnlyBetweenWords() {
        val titles = listOf("Show Instrument Metadata", "Festival Score Tracker Version")
        rule.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, density.fontScale * 2f)) {
                FestivalTheme { Column(Modifier.width(220.dp)) { titles.forEach { QuickLinkMenuLabel(it, current = true) } } }
            }
        }
        titles.forEachIndexed { i, title ->
            val layouts = mutableListOf<TextLayoutResult>()
            rule.onAllNodesWithTag(MENU_TITLE_TAG, useUnmergedTree = true)[i].performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
            val layout = layouts.single()
            assertTrue("$title wraps at 2.0: ${layout.lineCount} lines", layout.lineCount > 1)
            (0 until layout.lineCount - 1).forEach { line ->
                val end = layout.getLineEnd(line)
                assertTrue("$title breaks mid-word at $end", title[end - 1] == ' ' || title.getOrNull(end) == ' ')
            }
            assertFalse(layout.hasVisualOverflow)
        }
    }

    // endregion

    private companion object {
        const val SECTIONS = 6
        const val COMPACT = 411
        const val MEDIUM = 700
    }
}
