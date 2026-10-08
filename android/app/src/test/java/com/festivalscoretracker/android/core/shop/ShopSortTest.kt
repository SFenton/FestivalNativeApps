package com.festivalscoretracker.android.core.shop

import com.festivalscoretracker.android.core.songs.SongSortMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Item Shop sort (issue #379): choice, persistence decode, durations policy and ordering. */
class ShopSortTest {
    private fun offer(id: String, title: String, artist: String, year: Int?) =
        ShopSong(id, title, artist, year, null, "https://www.fortnite.com/item-shop/jam-tracks/$id")

    private val offers = listOf(
        offer("s1", "Beta", "Zed", 2019),
        offer("s2", "alpha", "Abba", 2021),
        offer("s3", "Gamma", "Mid", null),
        offer("s4", "Alpha", "Abba", 2021),
    )
    private val sorter = ShopOfferSort()

    private fun ids(result: ShopSortResult) = result.offers.map { it.songId }

    // region Choice

    @Test
    fun defaultChoiceIsTitleAscendingAndUnchanged() {
        val choice = ShopSortChoice()
        assertEquals(SongSortMode.Title, choice.mode)
        assertTrue(choice.ascending)
        assertFalse(choice.changed)
        assertTrue(ShopSortChoice(SongSortMode.Artist).changed)
        assertTrue(ShopSortChoice(ascending = false).changed)
        assertEquals(listOf(SongSortMode.Title, SongSortMode.Artist, SongSortMode.Year, SongSortMode.Duration), ShopSortChoice.modes)
    }

    @Test
    fun stateDescriptionUsesSongsVocabulary() {
        assertEquals("Artist, descending", ShopSortChoice(SongSortMode.Artist, false).stateDescription)
    }

    @Test
    fun decodeFallsBackToTitleAndDefaultsToAscending() {
        assertEquals(ShopSortChoice(), ShopSortChoice.decode(null, null))
        assertEquals(ShopSortChoice(SongSortMode.Year, false), ShopSortChoice.decode("Year", "false"))
        assertEquals(ShopSortChoice(SongSortMode.Duration), ShopSortChoice.decode("Duration", "true"))
        // Songs-only modes (scores, Item Shop) and unknown names are not Shop sorts.
        assertEquals(ShopSortChoice(), ShopSortChoice.decode(SongSortMode.Score.name, null))
        assertEquals(ShopSortChoice(), ShopSortChoice.decode("Bogus", "garbage"))
    }

    // endregion

    // region Durations policy

    @Test
    fun durationsAreReadyOnlyForTheSamePublication() {
        val lengths = mapOf("s1" to 100)
        assertEquals(ShopDurations.Ready(lengths), ShopDurations.of(lengths, false, 7, 7))
        assertEquals(ShopDurations.Mismatch, ShopDurations.of(lengths, false, 6, 7))
        assertEquals(ShopDurations.Mismatch, ShopDurations.of(lengths, false, null, 7))
        assertEquals(ShopDurations.Loading, ShopDurations.of(null, false, null, 7))
        assertEquals(ShopDurations.Failed, ShopDurations.of(null, true, null, 7))
    }

    // endregion

    // region Ordering

    @Test
    fun titleSortsCaseInsensitivelyWithSongIdTieBreakInBothDirections() {
        val up = sorter.sorted(offers, ShopSortChoice(), ShopDurations.Loading)
        assertEquals(listOf("s2", "s4", "s1", "s3"), ids(up))
        assertEquals(SongSortMode.Title, up.effective)
        assertNull(up.paused)
        assertFalse(up.waiting)
        assertEquals(listOf("s3", "s1", "s4", "s2"), ids(sorter.sorted(offers, ShopSortChoice(ascending = false), ShopDurations.Loading)))
    }

    @Test
    fun artistSortsByArtistThenTitle() {
        assertEquals(listOf("s2", "s4", "s3", "s1"), ids(sorter.sorted(offers, ShopSortChoice(SongSortMode.Artist), ShopDurations.Loading)))
        assertEquals(listOf("s1", "s3", "s4", "s2"), ids(sorter.sorted(offers, ShopSortChoice(SongSortMode.Artist, false), ShopDurations.Loading)))
    }

    @Test
    fun yearSortsMissingYearFirstLikeSongs() {
        assertEquals(listOf("s3", "s1", "s2", "s4"), ids(sorter.sorted(offers, ShopSortChoice(SongSortMode.Year), ShopDurations.Loading)))
        assertEquals(listOf("s4", "s2", "s1", "s3"), ids(sorter.sorted(offers, ShopSortChoice(SongSortMode.Year, false), ShopDurations.Loading)))
    }

    @Test
    fun durationUsesSamePublicationCatalogueLengths() {
        val ready = ShopDurations.Ready(mapOf("s1" to 300, "s2" to 120, "s3" to 240))
        val up = sorter.sorted(offers, ShopSortChoice(SongSortMode.Duration), ready)
        // s4 has no catalogue length and sorts as zero.
        assertEquals(listOf("s4", "s2", "s3", "s1"), ids(up))
        assertEquals(SongSortMode.Duration, up.effective)
        assertNull(up.paused)
        assertEquals(listOf("s1", "s3", "s2", "s4"), ids(sorter.sorted(offers, ShopSortChoice(SongSortMode.Duration, false), ready)))
    }

    @Test
    fun durationWaitsWhileCatalogueLoads() {
        val result = sorter.sorted(offers, ShopSortChoice(SongSortMode.Duration, false), ShopDurations.Loading)
        assertTrue(result.waiting)
        assertNull(result.paused)
        assertEquals(SongSortMode.Title, result.effective)
    }

    @Test
    fun durationPausesToTitleOrderInTheChosenDirection() {
        val failed = sorter.sorted(offers, ShopSortChoice(SongSortMode.Duration, false), ShopDurations.Failed)
        assertEquals(listOf("s3", "s1", "s4", "s2"), ids(failed))
        assertEquals(SongSortMode.Title, failed.effective)
        assertTrue(failed.paused!!.startsWith("Duration sort paused until song details load"))
        assertFalse(failed.waiting)
        val mismatch = sorter.sorted(offers, ShopSortChoice(SongSortMode.Duration), ShopDurations.Mismatch)
        assertEquals(listOf("s2", "s4", "s1", "s3"), ids(mismatch))
        assertTrue(mismatch.paused!!.contains("update together"))
    }

    @Test
    fun otherModesIgnoreDurationState() {
        val result = sorter.sorted(offers, ShopSortChoice(SongSortMode.Artist), ShopDurations.Failed)
        assertNull(result.paused)
        assertEquals(SongSortMode.Artist, result.effective)
    }

    @Test
    fun songsOnlyModesFallBackToTitle() {
        val result = sorter.sorted(offers, ShopSortChoice(SongSortMode.Score), ShopDurations.Loading)
        assertEquals(SongSortMode.Title, result.effective)
        assertEquals(listOf("s2", "s4", "s1", "s3"), ids(result))
    }

    @Test
    fun emptyOffersStayEmpty() {
        assertTrue(sorter.sorted(emptyList(), ShopSortChoice(SongSortMode.Year), ShopDurations.Loading).offers.isEmpty())
    }

    // endregion
}
