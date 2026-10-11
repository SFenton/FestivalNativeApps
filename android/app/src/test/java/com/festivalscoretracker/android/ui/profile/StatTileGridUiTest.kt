package com.festivalscoretracker.android.ui.profile

import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.festivalscoretracker.android.core.profile.PlayerTileAction
import com.festivalscoretracker.android.core.profile.SongsPreset
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.presentation.profile.PlayerStatTile
import com.festivalscoretracker.android.ui.theme.FestivalTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Pattern `stat-tile-grid` on the profile's [StatGrid] (owner, #591): a tile whose text would
 * wrap in one slot spans two and stays one line tall; every tile has the grid's height; at
 * large text a label too wide for two slots wraps instead of truncating.
 */
@RunWith(AndroidJUnit4::class)
// Wide enough for the 700/760 dp grids; narrower grids set their own width.
@Config(qualifiers = "w900dp-h891dp-xxhdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class StatTileGridUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<ComponentActivity>()

    private val filter = PlayerTileAction.FilterSongs(SongsPreset.Overall(SongScoreFilterKind.HasFCs, emptySet()))

    private val overview = listOf(
        PlayerStatTile("songs-played", "Songs Played", "412", action = filter),
        PlayerStatTile("full-combos", "Full Combos", "1,234 (45.6%)", action = filter),
        PlayerStatTile("gold-stars", "Gold Stars", "300"),
        PlayerStatTile("avg-accuracy", "Avg Accuracy", "98.2%"),
        PlayerStatTile("best-rank", "Best Song Rank", "#12"),
    )

    /**
     * [tiles] in a [width]-wide grid at [fontScale] (tagged `grid`, scope `overview`), above
     * an optional [reference] grid (scope `short`).
     */
    private fun show(tiles: List<PlayerStatTile>, width: Dp, fontScale: Float = 1f, reference: List<PlayerStatTile> = emptyList()) {
        rule.setContent {
            Host(width, fontScale) {
                StatGrid(tiles, "overview", canRun = { true }, onAction = {}, modifier = Modifier.testTag("grid"))
                if (reference.isNotEmpty()) StatGrid(reference, "short", canRun = { true }, onAction = {})
            }
        }
    }

    @Composable
    private fun Host(width: Dp, fontScale: Float, content: @Composable () -> Unit) {
        FestivalTheme {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                Column(Modifier.width(width)) { content() }
            }
        }
    }

    private fun bounds(tag: String) = rule.onNodeWithTag(tag).fetchSemanticsNode().boundsInRoot

    private fun tileBounds(scope: String = "overview") = rule.onAllNodes(
        SemanticsMatcher("stat tile") { it.config.getOrElseNullable(SemanticsProperties.TestTag) { null }?.startsWith("fst.player.tile.$scope.") == true },
    ).fetchSemanticsNodes().map { it.config[SemanticsProperties.TestTag].substringAfterLast('.') to it.boundsInRoot }

    @Test
    fun wrappingFullCombosSpansTwoSlotsAndEveryTileKeepsOneHeight() {
        show(overview, 360.dp)
        val grid = bounds("grid")
        val tiles = tileBounds().toMap()
        val combos = tiles.getValue("full-combos")
        // FULL COMBOS' value doesn't fit half a 360 dp grid: it takes the whole row.
        assertEquals(grid.width, combos.width, 2f)
        // Songs Played before it widens to the row's end rather than leaving a hole.
        assertEquals(grid.width, tiles.getValue("songs-played").width, 2f)
        // Tiles after it pair up again.
        assertTrue("${tiles["gold-stars"]}", tiles.getValue("gold-stars").width < grid.width / 2)
        assertEquals(tiles.getValue("gold-stars").top, tiles.getValue("avg-accuracy").top, 1f)
        // Same height everywhere: the wide tile is as tall as a one-line pair.
        val heights = tiles.values.map { it.height }.distinct()
        assertEquals("$tiles", 1, heights.size)
        // Reading order is web order.
        assertEquals(listOf("songs-played", "full-combos", "gold-stars", "avg-accuracy", "best-rank"), tileBounds().sortedWith(compareBy({ it.second.top }, { it.second.left })).map { it.first })
    }

    @Test
    fun wideTileIsAsTallAsAGridOfOneLineTiles() {
        show(overview, 360.dp, reference = listOf(overview[2], overview[3]))
        val spanned = tileBounds().first().second.height
        val oneLine = tileBounds("short").first().second.height
        assertEquals(oneLine, spanned, 1f)
    }

    @Test
    fun tilesThatFitStayInOneSlot() {
        show(overview.filter { it.id != "full-combos" }, 411.dp)
        val grid = bounds("grid")
        tileBounds().forEach { (id, box) -> assertTrue("$id $box", box.width < grid.width / 2) }
    }

    @Test
    fun wideGridsPutAWideTileBesideOthers() {
        show(overview, 760.dp)
        val tiles = tileBounds().toMap()
        val songs = tiles.getValue("songs-played")
        val combos = tiles.getValue("full-combos")
        assertEquals(songs.top, combos.top, 1f)
        assertTrue("$songs $combos", combos.width > songs.width * 1.9f)
        assertEquals(1, tiles.values.map { it.height }.distinct().size)
    }

    @Test
    fun labelTooWideForTwoSlotsWrapsAtLargeText() {
        val long = PlayerStatTile("over-threshold", "Over CHOpt Threshold Songs Played On Every Instrument", "7")
        val short = listOf(PlayerStatTile("a", "Songs", "1"), PlayerStatTile("b", "Stars", "2"))
        show(short + long, 700.dp, fontScale = 2f, reference = short)
        val oneLine = tileBounds("short").first().second.height
        val grid = bounds("grid")
        val tiles = tileBounds().toMap()
        val wide = tiles.getValue("over-threshold")
        assertTrue("two columns: ${tiles["a"]}", tiles.getValue("a").width < grid.width / 2)
        // Two slots (the whole two-column grid) and still taller: its label wrapped, not cut.
        assertEquals(grid.width, wide.width, 2f)
        assertTrue("wrapped $wide vs one line $oneLine", wide.height > oneLine + 10f)
        assertEquals(1, tiles.values.map { it.height }.distinct().size)
        rule.onNodeWithTag("fst.player.tile.overview.over-threshold").assertContentDescriptionEquals("Over CHOpt Threshold Songs Played On Every Instrument: 7")
    }
}
