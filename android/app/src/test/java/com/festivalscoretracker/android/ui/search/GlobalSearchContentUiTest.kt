package com.festivalscoretracker.android.ui.search

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.search.SearchScope
import com.festivalscoretracker.android.presentation.search.GlobalSearchUiState
import com.festivalscoretracker.android.presentation.search.SectionPhase
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Stateless search content: progress rings and one full-height region for every state (6.21). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp-mdpi")
class GlobalSearchContentUiTest {
    @get:Rule
    val rule = createComposeRule()

    private fun show(ui: GlobalSearchUiState) {
        rule.setContent {
            FestivalTheme {
                Box(Modifier.fillMaxWidth().height(600.dp)) {
                    GlobalSearchContent(ui, { null }, {}, {}, {}, {})
                }
            }
        }
    }

    @Test
    fun playersProgressIsARingNotALine() {
        show(GlobalSearchUiState(query = "alpha", settledQuery = "alpha", songsPhase = SectionPhase.Empty, playersPhase = SectionPhase.Loading))
        val ring = rule.onNodeWithTag(GlobalSearchTags.PLAYERS_LOADING)
            .assert(SemanticsMatcher.expectValue(SemanticsProperties.ProgressBarRangeInfo, ProgressBarRangeInfo.Indeterminate))
            .fetchSemanticsNode().boundsInRoot
        // A 24 dp ring (mdpi: 1 px per dp), not a full-width line.
        assertEquals(24f, ring.width, 0.5f)
        assertEquals(ring.width, ring.height, 0.5f)
    }

    @Test
    fun wholePanelProgressIsCentredInTheFullRegion() {
        show(GlobalSearchUiState(query = "alpha", scope = SearchScope.All, debouncing = true))
        val spinner = rule.onNodeWithTag(GlobalSearchTags.LOADING).fetchSemanticsNode().boundsInRoot
        // Centred in the region below the pills, not pinned to a small box at the top.
        assertTrue("spinner at ${spinner.center.y}", spinner.center.y > 250f)
    }
}
