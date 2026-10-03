package com.festivalscoretracker.android.ui.quicklinks

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.quicklinks.QuickLinkSection
import com.festivalscoretracker.android.core.quicklinks.QuickLinks
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** [rememberQuickLinks] keeps one controller per list while its title and sections change. */
@RunWith(AndroidJUnit4::class)
class QuickLinksControllerUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    @Test
    fun titleChangeKeepsTheControllerAndUpdatesItsState() {
        val title = mutableStateOf("Title Quick Links")
        val sections = mutableStateOf(emptyList<QuickLinkSection>())
        val seen = mutableListOf<QuickLinksController>()
        rule.setContent {
            val controller = rememberQuickLinks(rememberLazyListState(), title.value, sections.value) { null }
            seen += controller
        }
        rule.waitForIdle()
        val first = seen.last()
        assertFalse(first.available)

        // Songs: the saved Duration sort can arrive after the catalogue (title and sections change).
        title.value = "Duration Quick Links"
        sections.value = listOf(QuickLinkSection("duration:1to2", "1-2 min"), QuickLinkSection("duration:4to5", "4-5 min"))
        rule.waitForIdle()

        // The floating toolbar keeps the controller it first composed, so it must be this one.
        assertSame(first, seen.last())
        assertEquals("Duration Quick Links", first.title)
        assertTrue(first.available)
    }

    // region Landing hold

    private val grown = mutableStateOf(false)
    private lateinit var listState: LazyListState
    private lateinit var controller: QuickLinksController
    private var landingPx = 0
    private var thresholdPx = 0

    /** Ten 200 dp sections; the one above the target grows 600 dp once [grown] flips (lazily loaded content). */
    private fun setGrowingList() {
        rule.setContent {
            listState = rememberLazyListState()
            val sections = (0 until 10).map { QuickLinkSection("s$it", "S$it") }
            controller = rememberQuickLinks(listState, "Quick Links", sections) { id -> id.removePrefix("s").toIntOrNull() }
            with(LocalDensity.current) {
                landingPx = QuickLinks.LANDING_OFFSET_DP.dp.roundToPx()
                thresholdPx = QuickLinks.COMPLETE_THRESHOLD_DP.dp.roundToPx()
            }
            LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                items(10) { index ->
                    val height = if (index == 5 && grown.value) 800.dp else 200.dp
                    Box(Modifier.fillMaxWidth().height(height))
                }
            }
        }
        rule.waitForIdle()
    }

    private fun targetTop(index: Int): Int? = listState.layoutInfo.visibleItemsInfo.firstOrNull { it.index == index }?.offset

    @Test
    fun jumpRelandsWhenContentAboveTheTargetGrowsAfterLanding() {
        setGrowingList()
        rule.runOnIdle { controller.jump("s6") }
        rule.waitForIdle()
        assertEquals(landingPx.toFloat(), targetTop(6)!!.toFloat(), thresholdPx.toFloat())

        // The section above (the first visible item) finishes loading and grows.
        grown.value = true
        rule.waitForIdle()

        assertEquals(landingPx.toFloat(), targetTop(6)!!.toFloat(), thresholdPx.toFloat())
        assertEquals("s6", controller.activeId)
    }

    @Test
    fun landingHoldEndsAfterItsWindow() {
        setGrowingList()
        rule.runOnIdle { controller.jump("s6") }
        rule.waitForIdle()
        rule.mainClock.advanceTimeBy(QuickLinks.LANDING_HOLD_MS + 500)

        grown.value = true
        rule.waitForIdle()

        // Without the hold, the lazy list keeps the grown first item in place and the target sinks.
        assertTrue(targetTop(6) == null || targetTop(6)!! > landingPx + thresholdPx)
    }

    // endregion
}
