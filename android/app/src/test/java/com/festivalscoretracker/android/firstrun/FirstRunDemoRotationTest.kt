package com.festivalscoretracker.android.firstrun

import com.festivalscoretracker.android.core.firstrun.FirstRunCatalog
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoMetaLayout
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoPools
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoRotation
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoScorePattern
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoScoreState
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSong
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSongs
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoSuggestionTemplate
import com.festivalscoretracker.android.core.firstrun.FirstRunDemoTiming
import com.festivalscoretracker.android.core.firstrun.FirstRunMetadataRotation
import com.festivalscoretracker.android.core.firstrun.FirstRunPageKey
import com.festivalscoretracker.android.core.firstrun.FirstRunRotatingDemos
import com.festivalscoretracker.android.core.firstrun.FirstRunRowRotation
import com.festivalscoretracker.android.core.firstrun.FirstRunSlotRotation
import com.festivalscoretracker.android.core.firstrun.FirstRunWindowRotation
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.settings.MetadataField
import com.festivalscoretracker.android.core.songs.SongPercentileTier
import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** Issue #58: first-run demo rotation core (web `useDemoSongs` timing, swap rules and pools). */
class FirstRunDemoRotationTest {
    private val S = FirstRunDemoScoreState.Scored
    private val N = FirstRunDemoScoreState.NoScore
    private val F = FirstRunDemoScoreState.FullCombo

    private fun songs(count: Int) = List(count) { FirstRunDemoSong("s$it", "Song $it", "Epic Games") }

    @Test
    fun timingMatchesTheWebTheme() {
        assertEquals(5_000L, FirstRunDemoTiming.SWAP_INTERVAL_MS)
        assertEquals(400, FirstRunDemoTiming.FADE_MS)
        assertEquals(2_500L, FirstRunDemoTiming.BAR_SELECT_INTERVAL_MS)
        assertEquals(300, FirstRunDemoTiming.BAR_SELECT_FADE_MS)
        assertEquals(listOf(0.25f, 0.1f, 0.25f, 1f), FirstRunDemoTiming.EASE.toList())
    }

    @Test
    fun swapCountFollowsTheWebPoolSizes() {
        assertEquals(listOf(0, 0, 1, 1, 1, 2, 2, 2, 3, 3), listOf(-1, 0, 1, 2, 3, 4, 5, 6, 7, 12).map(FirstRunDemoRotation::swapCount))
    }

    @Test
    fun swapIndicesAreDistinctInRangeDeterministicAndAvoidTheLastSet() {
        for (rows in 1..9) {
            var previous = emptySet<Int>()
            for (tick in 0 until 40) {
                val picked = FirstRunDemoRotation.swapIndices(rows, tick, previous)
                assertEquals(FirstRunDemoRotation.swapCount(rows), picked.size)
                assertEquals(picked.size, picked.toSet().size)
                assertTrue(picked.all { it in 0 until rows })
                assertEquals(picked.sorted(), picked)
                assertEquals(picked, FirstRunDemoRotation.swapIndices(rows, tick, previous))
                if (rows > 1) assertNotEquals("rows=$rows tick=$tick", previous, picked.toSet())
                previous = picked.toSet()
            }
        }
        assertEquals(listOf(0), FirstRunDemoRotation.swapIndices(1, 3, setOf(0)))
        assertTrue(FirstRunDemoRotation.swapIndices(0, 0).isEmpty())
    }

    @Test
    fun swapIndicesVaryAcrossTicks() {
        val seen = (0 until 30).map { FirstRunDemoRotation.swapIndices(5, it) }.toSet()
        assertTrue("random-looking selection, not a fixed turn", seen.size > 3)
    }

    @Test
    fun rowRotationWalksThePoolWithoutDuplicates() {
        var rotation = FirstRunRowRotation.start(songs(8), 3) { it.id }
        assertEquals(listOf("s0", "s1", "s2"), rotation.rows.map { it.id })
        val shown = rotation.rows.map { it.id }.toMutableSet()
        repeat(12) {
            val indices = rotation.nextIndices()
            assertEquals(1, indices.size)
            val before = rotation.rows
            rotation = rotation.swapped(indices)
            assertEquals(3, rotation.rows.map { it.id }.toSet().size)
            assertNotEquals(before[indices[0]].id, rotation.rows[indices[0]].id)
            shown += rotation.rows.map { it.id }
        }
        assertEquals("every pool song appears", 8, shown.size)
    }

    @Test
    fun rowRotationNeedsALargerPool() {
        val rotation = FirstRunRowRotation.start(songs(3), 3) { it.id }
        assertFalse(rotation.canRotate)
        assertTrue(rotation.nextIndices().isEmpty())
        assertTrue(FirstRunRowRotation.start(emptyList<FirstRunDemoSong>(), 3).rows.isEmpty())
        val empty = FirstRunRowRotation.start(emptyList<FirstRunDemoSong>(), 3)
        assertTrue(empty.swapped(listOf(0)) === empty)
        // Out-of-range indices are ignored.
        val rows = FirstRunRowRotation.start(songs(5), 2) { it.id }
        assertEquals(rows.rows, rows.swapped(listOf(7)).rows)
    }

    @Test
    fun windowRotationPagesAndWraps() {
        var window = FirstRunWindowRotation(listOf(1, 2, 3, 4, 5), 2)
        assertEquals(listOf(1, 2), window.rows)
        window = window.advanced()
        assertEquals(listOf(3, 4), window.rows)
        window = window.advanced()
        assertEquals(listOf(5, 1), window.rows)
        assertEquals(listOf(1, 2, 3), FirstRunWindowRotation(listOf(1, 2, 3), 9).rows)
        val empty = FirstRunWindowRotation(emptyList<Int>(), 2)
        assertTrue(empty.rows.isEmpty())
        assertEquals(empty, empty.advanced())
    }

    @Test
    fun slotRotationSwapsTwoOfSixSlotsToTheirNextRival() {
        var slots = FirstRunSlotRotation(List(6) { 3 })
        repeat(9) {
            val indices = slots.nextIndices()
            assertEquals(2, indices.size)
            val before = slots.positions
            slots = slots.swapped(indices)
            indices.forEach { assertEquals((before[it] + 1) % 3, slots.positions[it]) }
            (0 until 6).filter { it !in indices }.forEach { assertEquals(before[it], slots.positions[it]) }
        }
        assertTrue(FirstRunSlotRotation(List(6) { 1 }).nextIndices().isEmpty())
    }

    @Test
    fun scorePatternMatchesTheWebHash() {
        assertEquals(2113, FirstRunDemoScorePattern.hash("Ab"))
        assertEquals(listOf(S, N, N, S, N, N), FirstRunDemoScorePattern.states("Ab", 6))
        assertEquals(-483_769_719, FirstRunDemoScorePattern.hash("Through the Fire and Flames"))
        assertEquals(listOf(F, S, F, S, S, F), FirstRunDemoScorePattern.states("Through the Fire and Flames", 6))
        assertTrue(FirstRunDemoScorePattern.states("x", -1).isEmpty())
    }

    @Test
    fun rotatingSlidesAreExactlyTheTwelveWebTimers() {
        assertEquals(12, FirstRunRotatingDemos.IDS.size)
        val all = FirstRunPageKey.entries.flatMap { FirstRunCatalog.slides(it, true) }.map { it.id }.toSet()
        assertTrue(all.containsAll(FirstRunRotatingDemos.IDS))
        listOf("songs-sort", "songs-filter", "songs-navigation", "songs-shop-highlight", "songinfo-chart", "shop-overview")
            .forEach { assertFalse(it, it in FirstRunRotatingDemos.IDS) }
    }

    @Test
    fun poolKeepsEpicGamesSongsWithArt() {
        val catalogue = listOf(
            Song("a", "One", "Epic Games", albumArt = "a.jpg"),
            Song("b", "Two", "Someone Else", albumArt = "b.jpg"),
            Song("c", "Three", "epic games feat. X", albumArt = "c.jpg"),
            Song("d", "Four", "Epic Games"),
            Song("e", "Five", "Epic Games", albumArt = "bad"),
        )
        val pool = FirstRunDemoSongs.pool(catalogue) { raw -> raw?.takeIf { it.endsWith(".jpg") }?.let { "https://cdn/$it" } }
        assertEquals(listOf("a", "c"), pool.map { it.id })
        assertEquals("https://cdn/a.jpg", pool[0].artUrl)
        assertEquals(FirstRunDemoSongs.FALLBACK, FirstRunDemoSongs.orFallback(emptyList()))
        assertEquals(pool, FirstRunDemoSongs.orFallback(pool))
        assertTrue(FirstRunDemoSongs.FALLBACK.size > 3)
    }

    @Test
    fun webPoolsAndLabels() {
        assertEquals(10, FirstRunDemoPools.RANKINGS.size)
        assertEquals("You", FirstRunDemoPools.PLAYER.name)
        assertEquals(6, FirstRunDemoPools.RIVALS_ABOVE.size)
        assertEquals(6, FirstRunDemoPools.RIVALS_BELOW.size)
        assertEquals(setOf(Instrument.Lead, Instrument.Drums, Instrument.Vocals), FirstRunDemoPools.INSTRUMENT_RIVALS.keys)
        assertEquals(
            listOf("Closest Battles", "Almost Passed", "Slipping Away", "Barely Winning", "Pulling Forward", "Dominating Them"),
            FirstRunDemoPools.RIVAL_DETAIL_CATEGORIES.map { it.title },
        )
        assertTrue(FirstRunDemoPools.RIVAL_DETAIL_CATEGORIES.all { it.ranks.size == 4 })
        assertTrue(FirstRunDemoPools.RIVAL_DETAIL_CATEGORIES[0].ranks[0].playerWins)
        assertFalse(FirstRunDemoPools.RIVAL_DETAIL_CATEGORIES[1].ranks[0].playerWins)
        assertEquals(listOf("Top 1.2%", "Top 3.5%", "Top 48.9%", "Top 1.2%"), listOf(0, 1, 6, 7).map(FirstRunDemoPools::topSongPercentile))
        assertEquals(SongPercentileTier.TopOne, FirstRunDemoPools.percentileTier("Top 1%"))
        assertEquals(SongPercentileTier.TopFive, FirstRunDemoPools.percentileTier("Top 3.5%"))
        assertEquals(SongPercentileTier.Ordinary, FirstRunDemoPools.percentileTier("Top 15%"))
        assertEquals(SongPercentileTier.Ordinary, FirstRunDemoPools.percentileTier("n/a"))
        assertEquals("Adjusted Percentile", FirstRunDemoPools.EXPERIMENTAL_METRICS.first().first)
    }

    @Test
    fun suggestionTemplatesCycleSongsAndDetails() {
        val templates = FirstRunDemoSuggestionTemplate.TEMPLATES
        assertEquals(listOf("unfc_guitar", "pct_push_bass", "near_fc_any", "unplayed_drums"), templates.map { it.key })
        val pool = songs(7)
        val lead = templates[0].items(0, pool)
        assertEquals(listOf("100%", "98%", "96%", "94%", "92%"), lead.map { it.detail })
        assertTrue(lead.all { it.instrument == Instrument.Lead })
        val bass = templates[1].items(1, pool, count = 3)
        assertEquals(listOf("s5", "s6", "s0"), bass.map { it.song.id })
        assertEquals(listOf("Top 3%", "Top 4%", "Top 5%"), bass.map { it.detail })
        assertEquals(listOf(Instrument.Lead, Instrument.Bass, Instrument.Drums, Instrument.Vocals, Instrument.Lead), templates[2].items(2, pool).map { it.instrument })
        assertTrue(templates[3].items(3, pool).all { it.instrument == Instrument.Drums && it.detail == null })
        assertTrue(templates[0].items(0, emptyList()).isEmpty())
    }

    @Test
    fun metadataSwapsSongMetaAndToAnUnusedLayout() {
        var rotation = FirstRunMetadataRotation.start(songs(6), 2)
        assertEquals(listOf(FirstRunDemoMetaLayout.ScoreAccuracy, FirstRunDemoMetaLayout.StarsDifficulty), rotation.rows.map { it.layout })
        repeat(10) {
            val indices = rotation.nextIndices()
            assertEquals(1, indices.size)
            val before = rotation.rows
            rotation = rotation.swapped(indices)
            val index = indices[0]
            assertNotEquals(before[index].song, rotation.rows[index].song)
            assertNotEquals(before[index].meta, rotation.rows[index].meta)
            assertFalse("layout not shown by the other row", rotation.rows[index].layout == before[1 - index].layout)
            assertNotEquals(before[index].layout, rotation.rows[index].layout)
        }
    }

    @Test
    fun metadataPillsFollowTheLayout() {
        val fc = FirstRunMetadataRotation.META[0]
        val plain = FirstRunMetadataRotation.META[1]
        val us = Locale.US
        val scoreAccuracy = FirstRunMetadataRotation.pills(fc, FirstRunDemoMetaLayout.ScoreAccuracy, us)
        assertEquals(listOf("198,942", "100% FC"), scoreAccuracy.map { it.text })
        assertTrue(scoreAccuracy[1].fullCombo)
        assertEquals("98%", FirstRunMetadataRotation.pills(plain, FirstRunDemoMetaLayout.AccuracyDifficulty, us)[0].text)
        val stars = FirstRunMetadataRotation.pills(fc, FirstRunDemoMetaLayout.StarsDifficulty, us)
        assertTrue(stars[0].goldStars)
        assertEquals(4.0, stars[1].intensityRaw)
        assertEquals(4, FirstRunMetadataRotation.pills(FirstRunMetadataRotation.META[4], FirstRunDemoMetaLayout.ScoreStars, us)[1].starCount)
        val percentile = FirstRunMetadataRotation.pills(fc, FirstRunDemoMetaLayout.PercentileSeason, us)
        assertEquals(listOf(MetadataField.Percentile, MetadataField.Season), percentile.map { it.kind })
        assertEquals(SongPercentileTier.TopOne, percentile[0].percentile)
        assertEquals("S12", percentile[1].text)
        assertEquals(listOf(MetadataField.Percentile, MetadataField.Score), FirstRunMetadataRotation.pills(plain, FirstRunDemoMetaLayout.PercentileScore, us).map { it.kind })
    }
}
