package com.festivalscoretracker.android.firstrun

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemo
import com.festivalscoretracker.android.ui.firstrun.FirstRunDemoCatalog
import com.festivalscoretracker.android.ui.firstrun.LocalFirstRunDemoCatalog
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config

/** Song demos show catalogue songs, or placeholders while the catalogue is loading/unavailable (issue #57). */
@RunWith(AndroidJUnit4::class)
@Config(qualifiers = "w411dp-h891dp")
class FirstRunDemoSongsUiTest {
    @get:Rule
    val rule = createComposeRule()

    private val songs = listOf(
        Fixtures.song("other", "Other Song", artist = "Someone").copy(albumArt = "other.jpg"),
        Fixtures.song("epic1", "First Epic", artist = "Epic Games").copy(albumArt = "e1.jpg"),
        Fixtures.song("epic2", "Second Epic", artist = "Epic Games").copy(albumArt = "e2.jpg"),
        Fixtures.song("noart", "No Art", artist = "Epic Games"),
    )

    private fun count(tag: String) = rule.onAllNodesWithTag(tag, useUnmergedTree = true).fetchSemanticsNodes().size

    /** Rows of a song: a demo Songs row, or a real Suggestions card row (`fst.suggestions.row.<songId>[|instrument]`). */
    private fun songRows(id: String) = count("fst.first-run.demo.song.$id") + rule.onAllNodes(
        SemanticsMatcher("suggestion row $id") { node -> node.config.getOrNull(SemanticsProperties.TestTag)?.let { it == "fst.suggestions.row.$id" || it.startsWith("fst.suggestions.row.$id|") } == true },
        useUnmergedTree = true,
    ).fetchSemanticsNodes().size

    /** Highest/lowest-ranked songs (Statistics) and the other song demos. */
    private val songDemos = listOf("statistics-top-songs", "songs-song-list", "rivals-detail", "suggestions-category-card", "songs-metadata", "shop-highlighting")

    @Test
    fun songDemosSwapPlaceholdersForCatalogueSongsWhenTheCatalogueArrives() {
        var catalog by mutableStateOf(FirstRunDemoCatalog())
        var id by mutableStateOf(songDemos.first())
        rule.setContent { FestivalTheme { CompositionLocalProvider(LocalFirstRunDemoCatalog provides catalog) { FirstRunDemo(id, active = false) } } }
        for (demo in songDemos) {
            catalog = FirstRunDemoCatalog()
            id = demo
            rule.waitForIdle()
            assert(count("fst.first-run.demo.placeholder") > 0) { "$demo renders placeholders while loading" }
            assertEquals("$demo shows no song while loading", 0, rule.onAllNodesWithText("Epic", substring = true).fetchSemanticsNodes().size)

            catalog = FirstRunDemoCatalog(songs, artworkUrl = { it })
            rule.waitForIdle()
            assertEquals("$demo has no placeholders once loaded", 0, count("fst.first-run.demo.placeholder"))
            assert(songRows("epic1") == 1) { "$demo shows Epic Games songs first" }
            assertEquals(0, songRows("noart"))
        }
    }

    @Test
    fun topSongsShowsRealSongsInPreferenceOrder() {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFirstRunDemoCatalog provides FirstRunDemoCatalog(songs, artworkUrl = { it })) {
                    FirstRunDemo("statistics-top-songs", active = false)
                }
            }
        }
        // The rows that fit the 220 dp frame, Epic Games songs first.
        listOf("epic1", "epic2").forEach { assertEquals(it, 1, count("fst.first-run.demo.song.$it")) }
        assertEquals(0, count("fst.first-run.demo.song.other"))
    }

    @Test
    fun shopDemosPreferCurrentShopSongs() {
        rule.setContent {
            FestivalTheme {
                CompositionLocalProvider(LocalFirstRunDemoCatalog provides FirstRunDemoCatalog(songs, shopSongIds = listOf("other"), artworkUrl = { it })) {
                    FirstRunDemo("songs-new-in-shop", active = false)
                }
            }
        }
        assertEquals(1, count("fst.first-run.demo.song.other"))
        rule.onAllNodesWithText("Other Song").fetchSemanticsNodes().let { assertEquals(1, it.size) }
    }
}
