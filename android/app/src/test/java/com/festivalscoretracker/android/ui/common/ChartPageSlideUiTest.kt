package com.festivalscoretracker.android.ui.common

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.shell.ChartPage
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** `load-transition` R12 (#593): paging a graph card's chart slides its window; reduced motion pages at once. */
@RunWith(AndroidJUnit4::class)
class ChartPageSlideUiTest {
    @get:Rule
    val rule = createComposeRule()

    private var page by mutableStateOf(ChartPage(start = 8, bands = 4, count = 12))
    private var top by mutableStateOf(100f)
    private var key by mutableStateOf<Any>("chart")
    private lateinit var slide: ChartPageSlide

    private fun show(reduceMotion: Boolean = false) {
        rule.setContent {
            FestivalTheme(appReduceMotion = reduceMotion) { slide = rememberChartPageSlide(page, top, key) }
        }
        rule.waitForIdle()
        rule.mainClock.autoAdvance = false
    }

    /** Change the chart's inputs on the UI thread and let Compose see them. */
    private fun change(block: () -> Unit) {
        rule.runOnUiThread { block(); Snapshot.sendApplyNotifications() }
    }

    @Test
    fun pagingSlidesTheWindowAndEasesTheValueTop() {
        show()
        assertEquals(8f, slide.start, 0f)
        assertEquals(0f, slide.labelShift, 0f)
        change { page = page.copy(start = 4); top = 200f }
        rule.mainClock.advanceTimeBy(200)
        // Halfway through the 400 ms slide: between the two windows, dates trailing toward their bars.
        assertTrue("mid-slide start ${slide.start}", slide.start > 4f && slide.start < 8f)
        assertTrue(slide.labelShift < 0f)
        assertTrue("mid-slide top ${slide.valueTop}", slide.valueTop > 100f && slide.valueTop < 200f)
        // A newer page retargets from where it is.
        val from = slide.start
        change { page = page.copy(start = 0) }
        rule.mainClock.advanceTimeByFrame()
        rule.mainClock.advanceTimeByFrame()
        assertTrue(slide.start <= from)
        rule.mainClock.advanceTimeBy(600)
        assertEquals(0f, slide.start, 0f)
        assertEquals(200f, slide.valueTop, 0f)
        assertEquals(0f, slide.labelShift, 0f)
    }

    @Test
    fun aResizeOrNewDataReFitsAtOnce() {
        show()
        change { page = ChartPage(start = 6, bands = 6, count = 12) }
        rule.mainClock.advanceTimeByFrame()
        assertEquals(6f, slide.start, 0f)
        change { key = "other chart"; page = page.copy(start = 2) }
        rule.mainClock.advanceTimeByFrame()
        assertEquals(2f, slide.start, 0f)
    }

    @Test
    fun reducedMotionPagesAtOnce() {
        show(reduceMotion = true)
        change { page = page.copy(start = 4); top = 50f }
        rule.mainClock.advanceTimeByFrame()
        assertEquals(4f, slide.start, 0f)
        assertEquals(50f, slide.valueTop, 0f)
        assertEquals(0f, slide.labelShift, 0f)
    }
}
