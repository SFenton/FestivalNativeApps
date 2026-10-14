package com.festivalscoretracker.android.ui.common

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.material3.adaptive.HingeInfo
import androidx.compose.material3.adaptive.Posture
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** One placement rule for page, load-gate and reload spinners, including lazy result regions (#624). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w800dp-h1000dp")
class LoadingPlacementUiTest {
    @get:Rule
    val rule = createComposeRule()

    private var kind by mutableIntStateOf(0)
    private var hinge by mutableStateOf<HingeInfo?>(null)

    private fun launch(direction: LayoutDirection = LayoutDirection.Ltr) {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(
                    LocalShellPosture provides Posture(hingeList = listOfNotNull(hinge)),
                    LocalLayoutDirection provides direction,
                ) {
                    Box(Modifier.fillMaxSize().padding(start = 72.dp, end = 16.dp, top = 80.dp, bottom = 96.dp).testTag("region")) {
                        key(kind) {
                            when (kind) {
                                0 -> LoadingView(LABEL)
                                1 -> FestivalLoadGate(false, Modifier.fillMaxSize(), LABEL) { Text("Hidden") }
                                else -> LoadSwapSpinner(rememberLoadSwap(null, false), LABEL)
                            }
                        }
                    }
                }
            }
        }
        rule.waitForIdle()
    }

    private fun region(): Rect = rule.onNodeWithTag("region").fetchSemanticsNode().boundsInWindow

    private fun assertAllCentred(expected: Rect) {
        repeat(3) { next ->
            rule.runOnIdle { kind = next }
            rule.waitForIdle()
            val nodes = rule.onAllNodes(hasContentDescription(LABEL), useUnmergedTree = true).fetchSemanticsNodes()
            assertEquals("one indicator in component $next", 1, nodes.size)
            val indicator = nodes.single()
            assertEquals(ProgressBarRangeInfo.Indeterminate, indicator.config.getOrNull(SemanticsProperties.ProgressBarRangeInfo))
            assertEquals("component $next horizontal centre", expected.center.x, indicator.boundsInWindow.center.x, 1f)
            assertEquals("component $next vertical centre", expected.center.y, indicator.boundsInWindow.center.y, 1f)
        }
    }

    @Test
    fun coverAndFlatCentreInTheFreeAreaBesideChrome() {
        launch()
        val area = region()
        assertAllCentred(area)
        rule.runOnIdle {
            hinge = HingeInfo(Rect(area.center.x, 0f, area.center.x, 5000f), isVertical = true, isFlat = true, isSeparating = false, isOccluding = false)
        }
        assertAllCentred(area)
    }

    @Test
    fun bookUsesTheWiderSide() {
        launch()
        val area = region()
        val left = area.left + area.width * 0.4f
        val right = left + 20f
        rule.runOnIdle { hinge = HingeInfo(Rect(left, 0f, right, 5000f), isVertical = true, isFlat = false, isSeparating = true, isOccluding = true) }
        assertAllCentred(area.copy(left = right))
    }

    @Test
    fun equalBookSidesUseTheLeadingSide() {
        launch()
        val area = region()
        rule.runOnIdle { hinge = HingeInfo(Rect(area.center.x, 0f, area.center.x, 5000f), isVertical = true, isFlat = false, isSeparating = true, isOccluding = false) }
        assertAllCentred(area.copy(right = area.center.x))
    }

    @Test
    fun equalBookSidesUseTheRightSideInRtl() {
        launch(LayoutDirection.Rtl)
        val area = region()
        rule.runOnIdle { hinge = HingeInfo(Rect(area.center.x, 0f, area.center.x, 5000f), isVertical = true, isFlat = false, isSeparating = true, isOccluding = false) }
        assertAllCentred(area.copy(left = area.center.x))
    }

    @Test
    fun tabletopUsesTheLowerSideEvenWhenItIsSmaller() {
        launch()
        val area = region()
        val top = area.top + area.height * 0.6f
        val bottom = top + 20f
        rule.runOnIdle { hinge = HingeInfo(Rect(0f, top, 5000f, bottom), isVertical = false, isFlat = false, isSeparating = true, isOccluding = true) }
        assertAllCentred(area.copy(top = bottom))
    }

    @Test
    fun aPaneAlreadyBeyondTheHingeKeepsItsOwnCentre() {
        launch()
        val area = region()
        rule.runOnIdle { hinge = HingeInfo(Rect(area.left - 20f, 0f, area.left, 5000f), isVertical = true, isFlat = false, isSeparating = true, isOccluding = true) }
        assertAllCentred(area)
    }

    @Test
    fun gateSpinnerPaddingDoesNotShrinkTheRevealedContent() {
        var ready by mutableStateOf(false)
        rule.setContent {
            FestivalTheme {
                FestivalLoadGate(ready, Modifier.fillMaxSize().testTag("gate"), LABEL, spinnerPadding = PaddingValues(bottom = 96.dp)) {
                    Box(Modifier.fillMaxSize().testTag("content"))
                }
            }
        }
        val gate = rule.onNodeWithTag("gate").fetchSemanticsNode().boundsInWindow
        val inset = with(rule.density) { 96.dp.toPx() }
        val spinner = rule.onAllNodes(hasContentDescription(LABEL), useUnmergedTree = true).fetchSemanticsNodes().single().boundsInWindow
        assertEquals((gate.top + gate.bottom - inset) / 2f, spinner.center.y, 1f)
        rule.runOnIdle { ready = true }
        rule.waitForIdle()
        assertEquals(gate, rule.onNodeWithTag("content").fetchSemanticsNode().boundsInWindow)
    }

    @Test
    fun inCardSpinnerKeepsItsMinimumHeightInABoundedParent() {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxSize()) {
                    LoadSwapSpinner(
                        rememberLoadSwap(null, false),
                        LABEL,
                        Modifier.heightIn(min = 96.dp),
                        avoidHinge = false,
                    )
                }
            }
        }
        val card = rule.onNodeWithTag(LOAD_SWAP_SPINNER_TAG).fetchSemanticsNode().boundsInWindow
        val indicator = rule.onAllNodes(hasContentDescription(LABEL), useUnmergedTree = true).fetchSemanticsNodes().single().boundsInWindow
        assertEquals(with(rule.density) { 96.dp.toPx() }, card.height, 1f)
        assertEquals(card.center.y, indicator.center.y, 1f)
    }

    @Test
    fun lazySpinnerFillsTheRegionBetweenHeaderAndPager() {
        rule.setContent {
            FestivalTheme {
                val state = rememberLazyListState()
                val swap = rememberLoadSwap(null, false)
                LazyColumn(Modifier.fillMaxSize().testTag("list"), state = state, contentPadding = PaddingValues(top = 16.dp, bottom = 40.dp)) {
                    item { Text("Header", Modifier.height(120.dp).testTag("header")) }
                    loadSwapSpinnerItem(swap, LABEL, state = state)
                    item { Text("Pager", Modifier.height(48.dp).testTag("pager")) }
                }
            }
        }
        rule.waitForIdle()
        val list = rule.onNodeWithTag("list").fetchSemanticsNode().boundsInWindow
        val header = rule.onNodeWithTag("header").fetchSemanticsNode().boundsInWindow
        val pager = rule.onNodeWithTag("pager").fetchSemanticsNode().boundsInWindow
        val spinner = rule.onAllNodes(hasContentDescription(LABEL), useUnmergedTree = true).fetchSemanticsNodes().single().boundsInWindow
        assertEquals(list.bottom - with(rule.density) { 40.dp.toPx() }, pager.bottom, 1f)
        assertEquals((header.bottom + pager.top) / 2f, spinner.center.y, 1f)
    }

    private companion object {
        const val LABEL = "Loading test content"
    }
}
