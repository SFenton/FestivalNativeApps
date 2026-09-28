package com.festivalscoretracker.android.core

import com.festivalscoretracker.android.core.format.DifficultyMeterSpec
import com.festivalscoretracker.android.core.format.ScoreFormatting
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.songs.SongCatalogSort
import com.festivalscoretracker.android.core.songs.SongListPipeline
import com.festivalscoretracker.android.core.songs.SongListInputs
import com.festivalscoretracker.android.core.songs.SongSearch
import com.festivalscoretracker.android.core.songs.SongSectionIndex
import com.festivalscoretracker.android.core.songs.SongSortMode
import com.festivalscoretracker.android.testing.Fixtures
import java.text.Collator
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SongsLogicTest {
    private val sorter = SongCatalogSort(Collator.getInstance(Locale.US))
    private val songs = listOf(
        Fixtures.song("3", "beta", artist = "Zed", year = 2001, duration = 300),
        Fixtures.song("1", "Alpha", artist = "Ann", year = 2010, duration = 120),
        Fixtures.song("2", "Alpha", artist = "Bob", year = 2010, duration = null),
        Fixtures.song("4", "24 Hours", artist = "Émile", year = null, duration = 90, lead = null),
        Fixtures.song("5", "Öyster", artist = "Carl", year = 1999, duration = 240),
    )

    // region Search

    @Test
    fun searchMatchesRawThenNormalized() {
        val song = Fixtures.song("x", "Don't Stop (Live)", artist = "Beyoncé & Co.")
        assertTrue(SongSearch.matches(song, ""))
        assertTrue(SongSearch.matches(song, "   "))
        assertTrue(SongSearch.matches(song, "STOP"))
        assertTrue(SongSearch.matches(song, "dont stop live"))
        assertTrue(SongSearch.matches(song, "beyonce"))
        assertTrue(SongSearch.matches(song, "'"))
        assertFalse(SongSearch.matches(song, "missing"))
        assertEquals("a b c", SongSearch.normalized("  A--b / (C) "))
        assertEquals("rock n roll", SongSearch.normalized("Rock ’n’ Roll"))
    }

    // endregion

    // region Sort

    @Test
    fun sortsEveryModeWithStableTies() {
        fun ids(mode: SongSortMode, ascending: Boolean = true) = sorter.sorted(songs, mode, ascending).map { it.songId }
        assertEquals(listOf("4", "1", "2", "3", "5"), ids(SongSortMode.Title))
        assertEquals(listOf("5", "3", "2", "1", "4"), ids(SongSortMode.Title, ascending = false))
        assertEquals(listOf("1", "2", "5", "4", "3"), ids(SongSortMode.Artist))
        assertEquals(listOf("4", "5", "3", "1", "2"), ids(SongSortMode.Year))
        assertEquals(listOf("2", "4", "1", "5", "3"), ids(SongSortMode.Duration))
        assertEquals(SongSortMode.Duration, SongSortMode.fromStored("Duration"))
        assertEquals(SongSortMode.Shop, SongSortMode.fromStored("Shop"))
        assertEquals(SongSortMode.Title, SongSortMode.fromStored("Removed"))
        assertEquals(SongSortMode.Title, SongSortMode.fromStored(null))
        assertEquals(listOf("Title", "Artist", "Year", "Duration", "Item Shop"), SongSortMode.entries.filter { it.group == com.festivalscoretracker.android.core.songs.SongSortGroup.Catalog }.map { it.label })
    }

    @Test
    fun pipelineFiltersSearchesAndSorts() {
        val all = SongListPipeline.run(SongListInputs(songs), sorter).songs
        assertEquals(5, all.size)
        val lead = SongListPipeline.run(SongListInputs(songs, filter = com.festivalscoretracker.android.core.songs.SongFilter(Instrument.Lead)), sorter).songs
        assertEquals(listOf("1", "2", "3", "5"), lead.map { it.songId })
        val searched = SongListPipeline.run(SongListInputs(songs, search = "oyster", sort = SongSortMode.Year, ascending = false), sorter).songs
        assertEquals(listOf("5"), searched.map { it.songId })
        assertEquals(5, SongListPipeline.run(SongListInputs(songs)).songs.size)
    }

    // endregion

    // region Section index

    @Test
    fun sectionIndexChunksConsecutiveKeys() {
        val title = sorter.sorted(songs, SongSortMode.Title, true)
        val sections = SongSectionIndex.sections(title, SongSortMode.Title)
        assertEquals(listOf("#", "A", "B", "O"), sections.map { it.label })
        assertEquals(listOf(0, 1, 3, 4), sections.map { it.firstIndex })
        assertEquals(listOf(1, 2, 1, 1), sections.map { it.count })
        assertEquals(listOf(0, 1, 2, 3), sections.map { it.id })
        val artist = SongSectionIndex.sections(sorter.sorted(songs, SongSortMode.Artist, true), SongSortMode.Artist)
        assertEquals(listOf("A", "B", "C", "E", "Z"), artist.map { it.label })
        assertTrue(SongSectionIndex.sections(sorter.sorted(songs, SongSortMode.Year, true), SongSortMode.Year).isEmpty())
        assertTrue(SongSectionIndex.sections(songs, SongSortMode.Duration).isEmpty())
        assertTrue(SongSectionIndex.sections(songs.take(1), SongSortMode.Title).isEmpty())
        assertEquals("#", SongSectionIndex.firstLetter(""))
        assertEquals("#", SongSectionIndex.firstLetter("¿Qué?"))
        assertEquals("E", SongSectionIndex.firstLetter(" éclair"))
    }

    // endregion

    // region Formatting

    @Test
    fun scoreFormatting() {
        assertEquals("95,198", ScoreFormatting.score(95198, Locale.US))
        assertEquals("100", ScoreFormatting.accuracy(1_000_000.0, Locale.US))
        assertEquals("98.8", ScoreFormatting.accuracy(987_654.0, Locale.US))
        assertEquals(0x2ECC71, ScoreFormatting.accuracyTint(1_000_000.0))
        assertEquals(0xDC2828, ScoreFormatting.accuracyTint(0.0))
        assertEquals(0xDC2828, ScoreFormatting.accuracyTint(-5.0))
        assertNull(ScoreFormatting.accuracyTint(Double.NaN))
        assertEquals("Top 1%", ScoreFormatting.percentileBucket(1, 10_000))
        assertEquals("Top 5%", ScoreFormatting.percentileBucket(45, 1_000))
        assertEquals("Top 100%", ScoreFormatting.percentileBucket(10, 10))
        assertNull(ScoreFormatting.percentileBucket(0, 10))
        assertNull(ScoreFormatting.percentileBucket(1, 0))
    }

    @Test
    fun difficultyMeterMatchesSpec() {
        assertEquals(listOf(2f to 0f, 8f to 0f, 6f to 20f, 0f to 20f), DifficultyMeterSpec.barVertices(0))
        assertEquals(listOf(56f to 0f, 62f to 0f, 60f to 20f, 54f to 20f), DifficultyMeterSpec.barVertices(6))
        assertThrows(IllegalArgumentException::class.java) { DifficultyMeterSpec.barVertices(7) }
        assertEquals(6, DifficultyMeterSpec.filledBars(5.9, raw = true))
        assertEquals(7, DifficultyMeterSpec.filledBars(99.0, raw = true))
        assertEquals(1, DifficultyMeterSpec.filledBars(-3.0, raw = true))
        assertEquals(3, DifficultyMeterSpec.filledBars(3.5, raw = false))
        assertEquals(1, DifficultyMeterSpec.filledBars(0.0, raw = false))
        assertNull(DifficultyMeterSpec.filledBars(Double.NaN, raw = true))
        assertEquals("Difficulty 6 of 7", DifficultyMeterSpec.accessibilityLabel(5.9, raw = true))
        assertEquals("Difficulty 3.5 of 7", DifficultyMeterSpec.accessibilityLabel(3.5, raw = false))
        assertEquals("Difficulty 4 of 7", DifficultyMeterSpec.accessibilityLabel(4.0, raw = false))
        assertEquals("Difficulty unavailable", DifficultyMeterSpec.accessibilityLabel(Double.POSITIVE_INFINITY, raw = false))
    }

    // endregion
}
