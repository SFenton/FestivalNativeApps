package com.festivalscoretracker.android.ui.design

import android.graphics.Bitmap
import android.graphics.Canvas
import android.os.Looper
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsNodeInteraction
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertHeightIsEqualTo
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsNotSelected
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.test.assertWidthIsAtLeast
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.ui.theme.BrandTokens
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Every reachable Instrument Selector state (`.agents/controls/instrument-selector/spec.md`,
 * issue #129): none, selected, required, hidden, disabled, muted, compact, deferred,
 * detail-expanded and reduced-motion, with roles, spoken states, sizes and drawn discs.
 */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class InstrumentSelectorUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val tag = "fst.instrument-selector"
    private val four = listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals)

    /** Last value passed to `onSelect`, and how many times it was called. */
    private var picks = mutableListOf<Instrument?>()

    // region Harness

    /**
     * A selector whose selection is held here, optionally inside a fixed-width box.
     *
     * @param width Box width in dp (null = full window).
     */
    @Composable
    private fun Host(
        instruments: List<Instrument> = four,
        initial: Instrument? = null,
        hidden: Set<Instrument> = emptySet(),
        disabled: Set<Instrument> = emptySet(),
        muted: Set<Instrument> = emptySet(),
        required: Boolean = false,
        compact: Boolean? = null,
        deferSelection: Boolean = false,
        width: Int? = null,
        withDetail: Boolean = false,
    ) {
        var selected by rememberSaveable { mutableStateOf(initial) }
        val modifier = if (width != null) Modifier.width(width.dp) else Modifier
        Box(modifier.background(BrandTokens.cardBackground)) {
            InstrumentSelector(
                instruments = instruments,
                selected = selected,
                onSelect = { picks += it; selected = it },
                hidden = hidden,
                disabled = disabled,
                muted = muted,
                required = required,
                compact = compact,
                deferSelection = deferSelection,
                content = if (withDetail) {
                    { Text("Detail", Modifier.height(120.dp).testTag("detail-body")) }
                } else {
                    null
                },
            )
        }
    }

    private fun show(reduceMotion: Boolean = false, body: @Composable () -> Unit) {
        rule.setContent { FestivalTheme(appReduceMotion = reduceMotion) { body() } }
        rule.waitForIdle()
    }

    private fun chart(instrument: Instrument): SemanticsNodeInteraction = rule.onNodeWithTag("$tag.${instrument.wireId}")

    private fun SemanticsNodeInteraction.role() = fetchSemanticsNode().config.getOrNull(SemanticsProperties.Role)

    private fun SemanticsNodeInteraction.state() = fetchSemanticsNode().config.getOrNull(SemanticsProperties.StateDescription)

    private fun SemanticsNodeInteraction.label() = fetchSemanticsNode().config[SemanticsProperties.ContentDescription].single()

    private fun count(suffix: String) = rule.onAllNodesWithTag("$tag.$suffix").fetchSemanticsNodes().size

    /** ARGB of the window at a point (dp) inside [node]. */
    private fun pixelIn(node: SemanticsNodeInteraction, xDp: Float, yDp: Float): Int {
        val root = rule.activity.window.decorView
        val bitmap = Bitmap.createBitmap(root.width, root.height, Bitmap.Config.ARGB_8888)
        rule.runOnUiThread { root.draw(Canvas(bitmap)) }
        val origin = node.fetchSemanticsNode().positionInWindow
        return bitmap.getPixel((origin.x + xDp * 3f).toInt(), (origin.y + yDp * 3f).toInt())
    }

    /**
     * M3 icon buttons are 40 dp layouts with 48 dp touch bounds (minimumInteractiveComponentSize):
     * a tap 23 dp outward from each arrow's centre, outside its layout, still activates it.
     */
    private fun assertArrowTouchTargets(previous: SemanticsNodeInteraction, next: SemanticsNodeInteraction) {
        previous.assertWidthIsAtLeast(40.dp).assertHeightIsAtLeast(40.dp)
        val before = picks.size
        val outward = 23f * 3f
        previous.performTouchInput { click(Offset(center.x - outward, center.y)) }
        rule.waitForIdle()
        next.performTouchInput { click(Offset(center.x + outward, center.y)) }
        rule.waitForIdle()
        next.performTouchInput { click(Offset(center.x, center.y + outward)) }
        rule.waitForIdle()
        assertEquals("three off-layout taps each moved the selection", before + 3, picks.size)
    }

    // endregion

    // region none / selected / required

    @Test
    fun noneRendersEveryChartAsAnUnselectedLabelledToggleInOneGroup() {
        show { Host() }
        assertEquals(0, count("compact"))
        four.forEach { instrument ->
            chart(instrument).assertIsNotSelected().assertIsEnabled().assertWidthIsEqualTo(64.dp).assertHeightIsEqualTo(64.dp)
            assertEquals(instrument.label, chart(instrument).label())
            // Optional choice: a single-select toggle like Material's FilterChip (web aria-pressed).
            assertEquals(Role.Checkbox, chart(instrument).role())
            assertNull(chart(instrument).state())
        }
        assertEquals(1, rule.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsProperties.SelectableGroup)).fetchSemanticsNodes().size)
        // The disc is not drawn for an unselected chart: the circle edge shows the backdrop.
        assertEquals(BrandTokens.cardBackground.toArgb(), pixelIn(chart(Instrument.Lead), 4f, 32f))
    }

    @Test
    fun selectedFillsTheGreenDiscAndPressingAgainClears() {
        show { Host() }
        chart(Instrument.Drums).performClick()
        rule.waitForIdle()
        chart(Instrument.Drums).assertIsSelected()
        chart(Instrument.Lead).assertIsNotSelected()
        assertEquals(BrandTokens.statusGreen.toArgb(), pixelIn(chart(Instrument.Drums), 4f, 32f))
        chart(Instrument.Drums).performClick()
        rule.waitForIdle()
        chart(Instrument.Drums).assertIsNotSelected()
        assertEquals(listOf(Instrument.Drums, null), picks)
    }

    @Test
    fun requiredReadsAsARadioGroupAndKeepsItsSelection() {
        show { Host(initial = Instrument.Bass, required = true) }
        four.forEach { assertEquals(Role.RadioButton, chart(it).role()) }
        chart(Instrument.Bass).assertIsSelected().performClick()
        rule.waitForIdle()
        chart(Instrument.Bass).assertIsSelected()
        chart(Instrument.Vocals).performClick()
        rule.waitForIdle()
        chart(Instrument.Vocals).assertIsSelected()
        chart(Instrument.Bass).assertIsNotSelected()
        assertEquals(listOf(Instrument.Bass, Instrument.Vocals), picks)
    }

    // endregion

    // region hidden / disabled / muted

    @Test
    fun hiddenChartsAreNotRenderedAndAHiddenSelectionReadsAsNone() {
        show { Host(initial = Instrument.Bass, hidden = setOf(Instrument.Bass), withDetail = true) }
        assertEquals(0, count(Instrument.Bass.wireId))
        listOf(Instrument.Lead, Instrument.Drums, Instrument.Vocals).forEach { chart(it).assertIsNotSelected() }
        assertEquals(0, rule.onAllNodesWithTag("detail-body").fetchSemanticsNodes().size)
    }

    @Test
    fun everyChartHiddenRendersNothing() {
        show { Host(hidden = four.toSet(), compact = true) }
        assertEquals(0, count("compact"))
        four.forEach { assertEquals(0, count(it.wireId)) }
    }

    @Test
    fun disabledChartsAreDimmedUnavailableAndIgnorePresses() {
        show { Host(disabled = setOf(Instrument.Bass)) }
        chart(Instrument.Bass).assertIsNotEnabled()
        assertEquals(UNAVAILABLE_STATE, chart(Instrument.Bass).state())
        chart(Instrument.Bass).performClick()
        rule.waitForIdle()
        chart(Instrument.Bass).assertIsNotSelected()
        assertTrue(picks.isEmpty())
    }

    @Test
    fun mutedChartsStaySelectableAndDropTheConflictStateOnceSelected() {
        show { Host(muted = setOf(Instrument.Drums)) }
        chart(Instrument.Drums).assertIsEnabled()
        assertEquals(MUTED_STATE, chart(Instrument.Drums).state())
        chart(Instrument.Drums).performClick()
        rule.waitForIdle()
        chart(Instrument.Drums).assertIsSelected()
        assertNull(chart(Instrument.Drums).state())
        // Selected muted charts are drawn at full strength on the green disc.
        assertEquals(BrandTokens.statusGreen.toArgb(), pixelIn(chart(Instrument.Drums), 4f, 32f))
    }

    // endregion

    // region compact / deferred

    @Test
    fun narrowRowsSwitchToLabelledCompactArrowsAndWideRowsStayFull() {
        // 4 × 64 + 3 × 12 = 292 dp: 291 dp is compact, 292 dp is the full row.
        show {
            androidx.compose.foundation.layout.Column {
                Host(width = 291)
            }
        }
        assertEquals(1, count("compact"))
        assertEquals(0, count(Instrument.Lead.wireId))
        val previous = rule.onNodeWithTag("$tag.previous")
        val next = rule.onNodeWithTag("$tag.next")
        val arrows = rule.onAllNodes(androidx.compose.ui.test.hasContentDescription("instrument", substring = true)).fetchSemanticsNodes()
            .flatMap { it.config[SemanticsProperties.ContentDescription] }
        assertTrue(arrows.toString(), "Previous instrument" in arrows && "Next instrument" in arrows)
        rule.onNodeWithTag("$tag.preview").assertWidthIsEqualTo(64.dp).assertIsNotSelected()
        assertEquals(LiveRegionMode.Polite, rule.onNodeWithTag("$tag.preview").fetchSemanticsNode().config[SemanticsProperties.LiveRegion])
        assertArrowTouchTargets(previous, next)
    }

    @Test
    fun fullRowAtExactFitWidth() {
        show { Host(width = 292) }
        assertEquals(0, count("compact"))
        four.forEach { chart(it).assertWidthIsEqualTo(64.dp) }
    }

    @Test
    fun forcedModesOverrideTheWidth() {
        show {
            androidx.compose.foundation.layout.Column {
                Box(Modifier.testTag("wide")) { InstrumentSelector(four, null, {}, compact = true, tag = "a") }
                Box(Modifier.width(120.dp)) { InstrumentSelector(four, null, {}, compact = false, tag = "b") }
            }
        }
        assertEquals(1, rule.onAllNodesWithTag("a.compact").fetchSemanticsNodes().size)
        assertEquals(0, rule.onAllNodesWithTag("b.compact").fetchSemanticsNodes().size)
        assertEquals(1, rule.onAllNodesWithTag("b.${Instrument.Vocals.wireId}").fetchSemanticsNodes().size)
    }

    @Test
    fun compactArrowsCycleTheSelectionSkippingDisabledCharts() {
        show { Host(initial = Instrument.Lead, disabled = setOf(Instrument.Bass), required = true, compact = true) }
        val preview = rule.onNodeWithTag("$tag.preview")
        assertEquals("Lead", preview.label())
        assertEquals(Role.RadioButton, preview.role())
        rule.onNodeWithTag("$tag.next").performClick(); rule.waitForIdle()
        assertEquals("Drums", preview.label())
        rule.onNodeWithTag("$tag.previous").performClick(); rule.waitForIdle()
        assertEquals("Lead", preview.label())
        rule.onNodeWithTag("$tag.previous").performClick(); rule.waitForIdle()
        assertEquals("Tap Vocals", preview.label())
        preview.assertIsSelected().performClick(); rule.waitForIdle()
        // Required: the centre does not clear.
        preview.assertIsSelected()
        assertEquals(listOf(Instrument.Drums, Instrument.Lead, Instrument.Vocals), picks)
    }

    @Test
    fun compactWithoutDeferralSelectsOnTheFirstArrowAndTheCentreClears() {
        show { Host(compact = true) }
        rule.onNodeWithTag("$tag.previous").performClick(); rule.waitForIdle()
        val preview = rule.onNodeWithTag("$tag.preview")
        assertEquals("Tap Vocals", preview.label())
        preview.assertIsSelected().performClick(); rule.waitForIdle()
        preview.assertIsNotSelected()
        assertEquals(listOf(Instrument.Vocals, null), picks)
    }

    @Test
    fun compactCentreShowsDisabledAndMutedPreviews() {
        show { Host(disabled = setOf(Instrument.Bass), muted = setOf(Instrument.Drums), compact = true, deferSelection = true) }
        val preview = rule.onNodeWithTag("$tag.preview")
        rule.onNodeWithTag("$tag.next").performClick(); rule.waitForIdle()
        assertEquals("Bass", preview.label())
        preview.assertIsNotEnabled()
        assertEquals(UNAVAILABLE_STATE, preview.state())
        rule.onNodeWithTag("$tag.next").performClick(); rule.waitForIdle()
        assertEquals("Drums", preview.label())
        assertEquals(MUTED_STATE, preview.state())
        preview.performClick(); rule.waitForIdle()
        preview.assertIsSelected()
        assertNull(preview.state())
    }

    @Test
    fun deferredArrowsMoveAPreviewUntilTheCentreCommits() {
        show { Host(compact = true, deferSelection = true, withDetail = true) }
        val preview = rule.onNodeWithTag("$tag.preview")
        rule.onNodeWithTag("$tag.next").performClick(); rule.waitForIdle()
        rule.onNodeWithTag("$tag.next").performClick(); rule.waitForIdle()
        assertEquals("Drums", preview.label())
        preview.assertIsNotSelected()
        assertTrue("arrows only preview", picks.isEmpty())
        assertEquals(0, rule.onAllNodesWithTag("detail-body").fetchSemanticsNodes().size)
        preview.performClick(); rule.waitForIdle()
        preview.assertIsSelected()
        assertEquals(listOf<Instrument?>(Instrument.Drums), picks)
        rule.onNodeWithTag("detail-body").assertHeightIsEqualTo(120.dp)
        // Once selected, arrows change the selection directly.
        rule.onNodeWithTag("$tag.previous").performClick(); rule.waitForIdle()
        assertEquals(listOf(Instrument.Drums, Instrument.Bass), picks)
    }

    @Test
    fun deferredPreviewSurvivesRecreationAndResetsWhenTheChartsChange() {
        val restoration = StateRestorationTester(rule)
        var charts by mutableStateOf(four)
        restoration.setContent { FestivalTheme { Host(instruments = charts, compact = true, deferSelection = true) } }
        rule.onNodeWithTag("$tag.next").performClick(); rule.waitForIdle()
        rule.onNodeWithTag("$tag.next").performClick(); rule.waitForIdle()
        assertEquals("Drums", rule.onNodeWithTag("$tag.preview").label())
        restoration.emulateSavedInstanceStateRestore()
        rule.waitForIdle()
        assertEquals("Drums", rule.onNodeWithTag("$tag.preview").label())
        // Settings change the rendered charts: the preview starts over (web useEffect).
        charts = four + Instrument.ProLead
        rule.waitForIdle()
        assertEquals("Lead", rule.onNodeWithTag("$tag.preview").label())
    }

    // endregion

    // region detail / motion

    @Test
    fun detailContentExpandsOnlyWhileARenderedChartIsSelected() {
        show { Host(withDetail = true) }
        assertEquals(0, rule.onAllNodesWithTag("detail-body").fetchSemanticsNodes().size)
        chart(Instrument.Lead).performClick()
        rule.waitForIdle()
        rule.onNodeWithTag("detail-body").assertHeightIsEqualTo(120.dp)
        rule.onNodeWithTag("$tag.detail").assertHeightIsEqualTo(120.dp)
        chart(Instrument.Lead).performClick()
        rule.waitForIdle()
        assertEquals(0, rule.onAllNodesWithTag("detail-body").fetchSemanticsNodes().size)
    }

    /** Height of the detail container and the disc-edge pixel one frame after selecting Lead. */
    private fun firstFrameAfterSelecting(): Pair<Float, Int> {
        rule.mainClock.autoAdvance = false
        chart(Instrument.Lead).performSemanticsAction(SemanticsActions.OnClick)
        // Robolectric's paused main looper delivers the recomposition; the test clock drives frames.
        repeat(3) {
            shadowOf(Looper.getMainLooper()).idle()
            rule.mainClock.advanceTimeByFrame()
        }
        val height = rule.onNodeWithTag("$tag.detail").fetchSemanticsNode().size.height / 3f
        return height to pixelIn(chart(Instrument.Lead), 4f, 32f)
    }

    @Test
    fun motionAnimatesTheDiscAndDetailOverThreeHundredMilliseconds() {
        show { Host(withDetail = true) }
        val (height, edge) = firstFrameAfterSelecting()
        assertTrue("detail still expanding: $height", height < 120f)
        assertNotEquals(BrandTokens.statusGreen.toArgb(), edge)
        rule.mainClock.advanceTimeBy(400)
        rule.onNodeWithTag("$tag.detail").assertHeightIsEqualTo(120.dp)
    }

    @Test
    fun reducedMotionShowsTheDiscAndDetailAtOnce() {
        show(reduceMotion = true) { Host(withDetail = true) }
        val (height, edge) = firstFrameAfterSelecting()
        assertEquals(120f, height, 0.5f)
        assertEquals(BrandTokens.statusGreen.toArgb(), edge)
    }

    @Test
    @Config(fontScale = 2.0f)
    fun doubleTextKeepsTheCircleAndArrowGeometry() {
        show {
            androidx.compose.foundation.layout.Column {
                Host()
                InstrumentSelector(four, Instrument.Lead, { picks += it }, compact = true, tag = "c")
            }
        }
        four.forEach { chart(it).assertWidthIsEqualTo(64.dp).assertHeightIsEqualTo(64.dp) }
        assertArrowTouchTargets(rule.onNodeWithTag("c.previous"), rule.onNodeWithTag("c.next"))
        rule.onNodeWithTag("c.preview").assertWidthIsEqualTo(64.dp)
    }

    // endregion
}
