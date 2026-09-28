package com.festivalscoretracker.android

import androidx.compose.material3.windowsizeclass.WindowWidthSizeClass
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.junit4.createComposeRule
import com.festivalscoretracker.android.data.CatalogSource
import com.festivalscoretracker.android.data.MonotonicClock
import com.festivalscoretracker.android.data.Song
import com.festivalscoretracker.android.data.SongCatalog
import com.festivalscoretracker.android.data.SongCatalogRepository
import org.junit.Rule
import org.junit.Test

/** Fixture-only native navigation and accessible meter scaffolding; requires coordinated device run. */
class FestivalAppTest {
    @get:Rule val rule = createComposeRule()

    @Test fun compactSongsSelectionAndSettingsNavigation() {
        val model = CatalogViewModel(
            SongCatalogRepository(
                CatalogSource { SongCatalog("Preview", listOf(Song("a", "First", "Artist", 3))) },
                MonotonicClock { 0L },
            ),
        )
        model.load()
        rule.setContent {
            FestivalApp(model, WindowWidthSizeClass.Compact, separatingHinge = false)
        }
        rule.waitUntil(5_000) { model.state.value is CatalogState.Ready }
        rule.onNodeWithTag("fst.songs.row.a").performClick()
        rule.onNodeWithTag("fst.songs.detail").assertIsDisplayed()
        rule.onNodeWithTag("fst.nav.settings").performClick()
        rule.onNodeWithTag("fst.settings").assertExists()
        rule.onNodeWithTag("fst.settings.contrast").performClick()
    }
}
