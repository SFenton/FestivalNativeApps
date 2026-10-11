package com.festivalscoretracker.android.ui.songs

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollToIndex
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/**
 * [rememberPinnedHeaderEndSpace] on a real `LazyColumn` with sticky headers (issue #560): at the
 * end of a list whose last scroll position falls inside a section push, the incoming title still
 * pins whole at the list's top edge and the outgoing one leaves completely (section-headers R4/R5),
 * and the last row stays reachable above the end padding. Without the space Compose leaves the
 * pinned title half pushed off the top (the control case), which is the reported rest state.
 *
 * Geometry as the Songs list: 40 dp headers, 80 dp rows, 4 dp spacing, 16 dp base end padding.
 * Header A heads five rows and header B two, in a 244 dp list, so B would rest 20 dp below the
 * pin line with A half pushed out. The space is saveable, so a restored list (Back to Songs, a
 * configuration change) keeps the finished rest.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
class PinnedHeaderEndSpaceUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private lateinit var state: LazyListState

    @Composable
    private fun SectionList(endSpace: Boolean) {
        state = rememberLazyListState()
        val first = "header:a"
        val extra = if (endSpace) rememberPinnedHeaderEndSpace(state, first, SPACING, BASE, IS_HEADER) else 0.dp
        Box(Modifier.height(LIST_HEIGHT)) {
            LazyColumn(
                state = state,
                contentPadding = PaddingValues(bottom = BASE + extra),
                verticalArrangement = Arrangement.spacedBy(SPACING),
                modifier = Modifier.fillMaxWidth().testTag(LIST),
            ) {
                listOf("a" to 5, "b" to 2).forEach { (name, rows) ->
                    stickyHeader(key = "header:$name") {
                        Text(
                            "Section $name",
                            Modifier.fillMaxWidth().height(HEADER).testTag("header.$name").semantics { heading() },
                        )
                    }
                    items(rows, key = { "$name-$it" }) { Text("Row $name$it", Modifier.fillMaxWidth().height(ROW).testTag("row.$name$it")) }
                }
            }
        }
    }

    private fun bounds(tag: String): Rect = rule.onNodeWithTag(tag, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot

    private fun px(dp: Dp): Float = dp.value * rule.density.density

    /** Scrolls to the very end with a fling and a programmatic jump past the last item. */
    private fun scrollToEnd() {
        rule.onNodeWithTag(LIST).performTouchInput { swipeUp() }
        rule.onNodeWithTag(LIST).performScrollToIndex(LAST)
        rule.waitForIdle()
        assertTrue("the list rests at its end", !state.canScrollForward)
    }

    /** With the space, B pins whole at the top edge, A has left, and the last row clears the base padding. */
    @Test
    fun theLastPushFinishesAtTheListEnd() {
        rule.setContent { SectionList(endSpace = true) }
        scrollToEnd()
        val list = bounds(LIST)
        val b = bounds("header.b")
        assertEquals("B pins at the list's top edge", list.top, b.top, 1f)
        assertEquals("B is whole", px(HEADER), b.height, 1f)
        val a = rule.onNodeWithTag("header.a", useUnmergedTree = true).let { runCatching { it.fetchSemanticsNode().boundsInRoot }.getOrNull() }
        assertTrue("A is not left half pushed ($a)", a == null || a.bottom <= list.top + 1f)
        // B's first row sits right below it, and the last row is fully reachable above the base padding.
        assertEquals("B's first row sits right below it", b.bottom + px(SPACING), bounds("row.b0").top, 1f)
        assertTrue("the last row is on screen above the end padding", bounds("row.b1").bottom <= list.bottom - px(BASE) + 1f)
    }

    /** Back to Songs or a configuration change: the restored list still rests with B whole at the pin line. */
    @Test
    fun theFinishedPushSurvivesStateRestoration() {
        val restoration = StateRestorationTester(rule)
        restoration.setContent { SectionList(endSpace = true) }
        scrollToEnd()
        restoration.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        val list = bounds(LIST)
        val b = bounds("header.b")
        assertEquals("B still pins at the list's top edge", list.top, b.top, 1f)
        assertEquals("B is whole", px(HEADER), b.height, 1f)
        assertEquals("B's first row sits right below it", b.bottom + px(SPACING), bounds("row.b0").top, 1f)
    }

    /** Control: without the space Compose leaves A half pushed off the top with B under it (the bug). */
    @Test
    fun withoutTheSpaceThePushStopsHalfway() {
        rule.setContent { SectionList(endSpace = false) }
        scrollToEnd()
        val list = bounds(LIST)
        val b = bounds("header.b")
        assertEquals("B rests 20 dp below the pin line", list.top + px(20.dp), b.top, 1f)
        val a = bounds("header.a")
        // Bounds are clipped to the list: A shows only its bottom 20 dp at the top edge.
        assertTrue("A is half pushed off the top ($a)", a.bottom > list.top + 1f && a.height < px(HEADER) - 1f)
    }

    private companion object {
        const val LIST = "list"
        const val LAST = 8
        val IS_HEADER: (Any) -> Boolean = { it is String && it.startsWith("header:") }
        val SPACING = 4.dp
        val BASE = 16.dp
        val HEADER = 40.dp
        val ROW = 80.dp
        val LIST_HEIGHT = 244.dp
    }
}
