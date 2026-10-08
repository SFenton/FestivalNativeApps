package com.festivalscoretracker.android.ui

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.ui.common.FestivalEmptyState
import com.festivalscoretracker.android.ui.common.FestivalLoadGate
import com.festivalscoretracker.android.ui.common.festivalEmptyStateItem
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Shared load gate (6.41) and empty state (6.33). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class LoadGateUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun count(tag: String) = rule.onAllNodesWithTag(tag).fetchSemanticsNodes().size

    @Test
    fun spinnerUntilReadyThenFadeThenContent() {
        var ready by mutableStateOf(false)
        rule.mainClock.autoAdvance = false
        rule.setContent {
            FestivalTheme {
                FestivalLoadGate(ready, Modifier.fillMaxSize()) { Text("Row", Modifier.staggered(0).testTag("row")) }
            }
        }
        rule.mainClock.advanceTimeByFrame()
        assertTrue(count("fst.load-gate.spinner") == 1 && count("row") == 0)
        ready = true
        rule.mainClock.advanceTimeBy(100)
        // Still fading the spinner: content is not composed yet.
        assertTrue(count("fst.load-gate.spinner") == 1 && count("row") == 0)
        rule.mainClock.advanceTimeBy(1_000)
        assertTrue(count("fst.load-gate.spinner") == 0 && count("row") == 1)
        rule.mainClock.autoAdvance = true
        // Content already in stays up through a refresh.
        ready = false
        rule.waitForIdle()
        assertTrue(count("row") == 1)
    }

    @Test
    fun composeWhileLoadingKeepsContentHiddenUnderTheSpinner() {
        var ready by mutableStateOf(false)
        var compositions = 0
        rule.setContent {
            FestivalTheme {
                FestivalLoadGate(ready, Modifier.fillMaxSize(), composeWhileLoading = true) {
                    androidx.compose.runtime.SideEffect { compositions++ }
                    Text("Row", Modifier.staggered(0).testTag("row"))
                }
            }
        }
        rule.waitForIdle()
        // Composed (so it can start loading) but hidden from accessibility under the spinner.
        assertTrue(compositions > 0 && count("row") == 0 && count("fst.load-gate.spinner") == 1)
        ready = true
        rule.waitUntil(5_000) { count("row") == 1 && count("fst.load-gate.spinner") == 0 }
    }

    @Test
    fun readyDataShowsAtOnce() {
        rule.setContent { FestivalTheme { FestivalLoadGate(true, Modifier.fillMaxSize()) { Text("Row", Modifier.staggered(3).testTag("row")) } } }
        rule.onNodeWithTag("row").assertIsDisplayed()
        assertTrue(count("fst.load-gate.spinner") == 0)
    }

    @Test
    fun emptyStateCentresVerticallyInAList() {
        rule.setContent {
            FestivalTheme {
                LazyColumn(Modifier.fillMaxSize().testTag("list")) {
                    item { Text("Header") }
                    festivalEmptyStateItem("No songs", subtitle = "Try another search", tag = "empty")
                }
            }
        }
        val list = rule.onNodeWithTag("list").getBoundsInRoot()
        val title = rule.onNodeWithText("No songs").getBoundsInRoot()
        val centre = (title.top + title.bottom) / 2
        // Vertically near the middle of the viewport, not just below the header row.
        assertTrue("title centre $centre in list ${list.top}..${list.bottom}", centre > list.top + (list.bottom - list.top) / 3)
        rule.onNodeWithText("Try another search").assertIsDisplayed()
    }

    @Test
    fun emptyStateFillsTheRegionBetweenListItems() {
        rule.setContent {
            FestivalTheme {
                val state = rememberLazyListState()
                LazyColumn(Modifier.fillMaxSize().testTag("list"), state = state, contentPadding = PaddingValues(top = 16.dp, bottom = 40.dp)) {
                    item { Text("Header", Modifier.height(120.dp).testTag("header")) }
                    festivalEmptyStateItem("No songs", subtitle = "Try another search", key = "empty", tag = "empty", state = state)
                    item { Text("Pager", Modifier.height(48.dp).testTag("pager")) }
                }
            }
        }
        rule.waitForIdle()
        val list = rule.onNodeWithTag("list").getBoundsInRoot()
        val header = rule.onNodeWithTag("header").getBoundsInRoot()
        val region = rule.onNodeWithTag("empty").getBoundsInRoot()
        val pager = rule.onNodeWithTag("pager").getBoundsInRoot()
        // Fills from the header to the pager, which stays on screen above the bottom padding.
        assertEquals(header.bottom.value, region.top.value, 1f)
        assertEquals(region.bottom.value, pager.top.value, 1f)
        assertEquals(list.bottom.value - 40f, pager.bottom.value, 1f)
        val title = rule.onNodeWithText("No songs").getBoundsInRoot()
        val subtitle = rule.onNodeWithText("Try another search").getBoundsInRoot()
        assertEquals(((region.top + region.bottom) / 2).value, ((title.top + subtitle.bottom) / 2).value, 1f)
    }

    @Test
    fun standaloneEmptyStateWithIcon() {
        rule.setContent { FestivalTheme { FestivalEmptyState("Nothing here", icon = { Text("★") }) } }
        rule.onNodeWithText("Nothing here").assertIsDisplayed()
        rule.onNodeWithText("★").assertIsDisplayed()
    }
}
