package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.rivals.ColumnSpec
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.core.songs.SongShopFilter
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.testing.ProfileFixtures
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Top songs, tile presets, fold-aware columns, sections and chart geometry. */
class ProfileParityCoreTest {
    private fun profile(rows: List<String>) =
        FestivalApi.JSON.decodeFromString(PlayerProfileResponse.serializer(), ProfileFixtures.profile(rows = rows))

    // region Top songs

    @Test
    fun topFiveSortsByPlacementAndBottomFiveOnlyBeyondFive() {
        val rows = (1..7).map { ProfileFixtures.score("s-$it", "01", rank = 8 - it, total = 100) } +
            ProfileFixtures.score("s-bass", "02", rank = 1, total = 10) +
            ProfileFixtures.score("s-unranked", "01", rank = 0, total = 100)
        val songs = mapOf("s-7" to Song("s-7", "Seventh", "Band", year = 2020, albumArt = "seven.jpg"))
        val top = PlayerTopSongs.build(profile(rows), Instrument.Lead, songs) { raw -> raw?.let { "https://art/$it" } }
        assertEquals(listOf("s-7", "s-6", "s-5", "s-4", "s-3"), top.top.map { it.songId })
        // Worst first, and overlapping the top list when only seven are ranked (web slice(-5).reverse()).
        assertEquals(listOf("s-1", "s-2", "s-3", "s-4", "s-5"), top.bottom.map { it.songId })
        val best = top.top.first()
        assertEquals("Seventh", best.title)
        assertEquals("Band · 2020", best.subtitle)
        assertEquals("https://art/seven.jpg", best.artUrl)
        assertEquals("Top 1%", best.bucket)
        assertTrue(best.isTopFive)
        assertEquals("Seventh, Band · 2020, Top 1%", best.announcement)
        // Missing catalogue rows fall back to the first eight ID characters and no subtitle.
        val missing = top.bottom.first()
        assertEquals("s-1", missing.title)
        assertEquals("", missing.subtitle)
        assertNull(missing.artUrl)
        assertEquals("s-1, Top 10%", missing.announcement)
        assertFalse(missing.isTopFive)
        assertFalse(top.isEmpty)
    }

    @Test
    fun fewRankedSongsHaveNoBottomListAndTiesKeepProfileOrder() {
        val rows = listOf(
            ProfileFixtures.score("b-song", "01", rank = 2, total = 10),
            ProfileFixtures.score("a-song", "01", rank = 20, total = 100),
            ProfileFixtures.score("capped", "01", rank = 150, total = 100),
        )
        val top = PlayerTopSongs.build(profile(rows), Instrument.Lead, emptyMap())
        assertEquals(listOf("b-song", "a-song", "capped"), top.top.map { it.songId })
        assertTrue(top.bottom.isEmpty())
        assertEquals(100.0, top.top.last().percent, 0.0)
        assertEquals("Top 100%", top.top.last().bucket)
        assertTrue(PlayerTopSongs.build(profile(rows), Instrument.Drums, emptyMap()).isEmpty)
        val placement = PlayerSongPlacement("x", Instrument.Lead, "X", "", null, null, 0, 0)
        assertEquals("—", placement.bucket)
    }

    // endregion

    // region Songs presets

    @Test
    fun overallPresetsResetEverythingAndCheckEveryVisibleChart() {
        val current = SongsFilterState(
            filter = SongFilter(Instrument.Bass, 2, 5),
            shopFilter = SongShopFilter(inShop = true),
            playerFilter = SongPlayerScoreFilter(missingFCs = setOf(Instrument.Drums)),
            sort = SongSortMode.Shop,
            ascending = false,
        )
        val visible = setOf(Instrument.Lead, Instrument.Bass)
        val played = SongsPreset.Overall(SongScoreFilterKind.HasScores, visible).apply(current)
        assertEquals(SongsFilterState(playerFilter = SongPlayerScoreFilter(hasScores = visible)), played)
        val combos = SongsPreset.Overall(SongScoreFilterKind.HasFCs, visible).apply(current)
        assertEquals(visible, combos.playerFilter.hasFCs)
        assertEquals(SongSortMode.Title, combos.sort)
        assertTrue(combos.ascending)
    }

    @Test
    fun instrumentPresetsClearOnlyThatChartKeepShopAndSortByScore() {
        val current = SongsFilterState(
            filter = SongFilter(Instrument.Bass, 2, 5),
            shopFilter = SongShopFilter(inShop = true, leavingTomorrow = true),
            playerFilter = SongPlayerScoreFilter(
                missingScores = setOf(Instrument.Lead),
                missingFCs = setOf(Instrument.Lead, Instrument.Drums),
                hasFCs = setOf(Instrument.Lead),
            ),
            sort = SongSortMode.Year,
            ascending = false,
        )
        val next = SongsPreset.ForInstrument(SongScoreFilterKind.HasScores, Instrument.Lead).apply(current)
        assertEquals(SongFilter(Instrument.Lead), next.filter)
        assertEquals(current.shopFilter, next.shopFilter)
        assertEquals(SongPlayerScoreFilter(hasScores = setOf(Instrument.Lead), missingFCs = setOf(Instrument.Drums)), next.playerFilter)
        // Web instSongsPlayedUpdater sorts by score, ascending.
        assertEquals(SongSortMode.Score, next.sort)
        assertTrue(next.ascending)
        val fcs = SongsPreset.ForInstrument(SongScoreFilterKind.HasFCs, Instrument.Drums).apply(current)
        assertEquals(setOf(Instrument.Lead, Instrument.Drums), fcs.playerFilter.hasFCs)
        assertEquals(emptySet<Instrument>(), fcs.playerFilter.missingFCs - Instrument.Lead)
    }

    @Test
    fun onlySongsFiltersRequireSelection() {
        assertTrue(PlayerTileAction.FilterSongs(SongsPreset.Overall(SongScoreFilterKind.HasScores, emptySet())).requiresSelection)
        assertFalse(PlayerTileAction.OpenSong("s", Instrument.Lead).requiresSelection)
        val rankings = PlayerTileAction.OpenRankings(Instrument.Bass)
        assertFalse(rankings.requiresSelection)
        assertEquals(RankingMetric.TotalScore, rankings.metric)
    }

    @Test
    fun averageStarsAndTwoDecimals() {
        val rows = listOf(
            ProfileFixtures.score("a", "01", stars = 6),
            ProfileFixtures.score("b", "01", stars = 5),
            ProfileFixtures.score("c", "01", stars = 0),
        )
        assertEquals(5.5, PlayerStatistics.forInstrument(profile(rows), Instrument.Lead).averageStars!!, 0.0)
        assertNull(PlayerStatistics.forInstrument(profile(rows), Instrument.Bass).averageStars)
        assertEquals("5.5", ProfileFormatting.twoDecimals(5.5, java.util.Locale.US))
        assertEquals("4.33", ProfileFormatting.twoDecimals(13.0 / 3, java.util.Locale.US))
        assertEquals("5", ProfileFormatting.twoDecimals(5.0, java.util.Locale.US))
    }

    // endregion

    // region Columns

    @Test
    fun columnsFollowWidthWithoutHinges() {
        val narrow = ProfileColumns.resolve(0, 400, emptyList(), 340, 16, 3)
        assertEquals(ColumnSpec(listOf(400), 16), narrow.spec)
        assertFalse(narrow.splitAtFold)
        val wide = ProfileColumns.resolve(0, 1100, emptyList(), 340, 16, 3)
        assertEquals(3, wide.spec.count)
        assertFalse(wide.splitAtFold)
    }

    @Test
    fun oneHingeSplitsTwoColumnsAtTheFold() {
        // Grid starts at x=100; a 20 px hinge at 600–620 window pixels.
        val grid = ProfileColumns.resolve(100, 1000, listOf(600 to 620), 340, 16, 3)
        assertEquals(ColumnSpec(listOf(500, 480), 20), grid.spec)
        assertTrue(grid.splitAtFold)
        // A hinge outside the grid is ignored.
        val outside = ProfileColumns.resolve(100, 400, listOf(1200 to 1200), 340, 16, 3)
        assertFalse(outside.splitAtFold)
        assertEquals(1, outside.spec.count)
        // A hinge too close to the edge for a column on each side is not honoured.
        val edge = ProfileColumns.resolve(0, 800, listOf(100 to 100), 340, 16, 3)
        assertFalse(edge.splitAtFold)
    }

    @Test
    fun twoHingesGiveOneColumnPerPanel() {
        val grid = ProfileColumns.resolve(0, 2160, listOf(1440 to 1440, 720 to 720), 340, 16, 3)
        assertEquals(16, grid.spec.spacing)
        assertEquals(listOf(712, 704, 712), grid.spec.widths)
        assertTrue(grid.splitAtFold)
        val wideHinge = ProfileColumns.resolve(0, 2160, listOf(700 to 740, 1420 to 1460), 340, 16, 3)
        assertEquals(40, wideHinge.spec.spacing)
        assertEquals(listOf(700, 680, 700), wideHinge.spec.widths)
        // Panels narrower than half a column fall back to width rules (no split).
        val cramped = ProfileColumns.resolve(0, 500, listOf(100 to 100, 400 to 400), 340, 16, 3)
        assertEquals(1, cramped.spec.count)
        assertFalse(cramped.splitAtFold)
    }

    // endregion

    // region Sections

    @Test
    fun rowsAndQuickLinksFollowTheWebOrder() {
        val visible = listOf(Instrument.Lead, Instrument.Drums)
        val rows = ProfileSections.rows(visible)
        assertEquals(
            listOf("header", "overview", "instrument:Solo_Guitar", "instrument:Solo_Drums", "top-songs", "top-songs:Solo_Guitar", "top-songs:Solo_Drums", "bands"),
            rows.map { it.key },
        )
        assertEquals(listOf(true, true, false, false, true, false, false, true), rows.map { it.fullWidth })
        val links = ProfileSections.quickLinks(visible, "Synthetic Player")
        assertEquals(listOf("global", "instrument:Solo_Guitar", "instrument:Solo_Drums", "top-songs", "bands"), links.map { it.id })
        assertEquals(listOf("Global Statistics", "Lead", "Drums", "Top Songs", "Bands"), links.map { it.title })
        assertEquals("Synthetic Player's Bands", links.last().accessibleTitle)
        assertEquals(Instrument.Drums, links[2].instrument)
        // Every link lands on a row.
        links.forEach { link -> assertTrue(rows.any { it.key == ProfileSections.rowKey(link.id) }) }
    }

    // endregion

    // region Chart geometry

    @Test
    fun chartGeometryMapsUnitsToPixels() {
        assertEquals(10f, ChartGeometry.x(0f, 200f, 10f))
        assertEquals(190f, ChartGeometry.x(1f, 200f, 10f))
        assertEquals(100f, ChartGeometry.x(0.5f, 200f, 10f))
        assertEquals(24f, ChartGeometry.barWidth(1, 400f, 24f))
        assertEquals(2f, ChartGeometry.barWidth(1_000, 400f, 24f))
        assertEquals(12.5f, ChartGeometry.barWidth(10, 200f, 24f))
        assertEquals(2f, ChartGeometry.barWidth(0, 1f, 1f))
        assertEquals(ChartRect(95f, 55f, 10f, 45f), ChartGeometry.bar(ChartBar(0.5f, 1f), 200f, 100f, 10f, 10f))
        assertEquals(ChartOffset(10f, 25f), ChartGeometry.point(ChartPoint(0f, 0.25f), 200f, 100f, 10f))
        assertEquals(63f, ChartGeometry.labelTop(ChartTick(0.5f, "#2"), 140f, 14f))
        assertEquals(0.02f, ChartGeometry.percentileFraction(0f))
        assertEquals(1f, ChartGeometry.percentileFraction(3f))
        assertEquals(0.5f, ChartGeometry.percentileFraction(0.5f))
    }

    // endregion
}
