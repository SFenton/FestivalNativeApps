package com.festivalscoretracker.android.presentation.profile

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.SongsResponse
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRankingPayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerRankHistory
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import com.festivalscoretracker.android.testing.ProfileFixtures
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Every viewed account uses the same effective scores as Statistics, without re-reading. */
@OptIn(ExperimentalCoroutinesApi::class)
class ProfileInvalidScoresTest {
    @get:Rule
    val main = MainDispatcherRule()

    @Test
    fun viewedAndSelectedProfilesRebuildAllScoreFiguresAtTheLeewayWithoutReloading() = runTest(main.dispatcher) {
        val player = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player")
        val settings = MutableStateFlow<AppSettings?>(AppSettings(visibleInstruments = setOf(Instrument.Lead)))
        val publications = MutableStateFlow<Int?>(7)
        val raw = FestivalApi.JSON.decodeFromString(PlayerProfileResponse.serializer(), ProfileFixtures.invalidScoresProfile())
        val songs = FestivalApi.JSON.decodeFromString(SongsResponse.serializer(), ProfileFixtures.invalidScoresSongs).songs
        var profileReads = 0
        var catalogReads = 0
        var rankingReads = 0
        var historyReads = 0
        val reads = ProfileReads(
            profile = { account ->
                profileReads++
                PlayerProfilePayload(raw.copy(accountId = account), PlayerProfileState.Available, 7, 7)
            },
            ranking = { _, account ->
                rankingReads++
                PlayerInstrumentRankingPayload(FestivalApi.JSON.decodeFromString(PlayerInstrumentRanking.serializer(), ProfileFixtures.ranking(account)))
            },
            rankHistory = { _, _ -> historyReads++; PlayerRankHistory() },
            catalog = { catalogReads++; songs },
        )
        val store = SelectedProfileStore(reads.profile, publications, ServiceRetryBackoff())
        store.start(backgroundScope, settings.map { it?.selectedPlayer })
        fun vm(account: String?) = PlayerProfileViewModel(
            account, null, reads, store, settings, publications, ServiceRetryBackoff(), {}, {},
        )
        val viewed = vm(Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertEquals("#1", viewed.state.value.overview.single { it.id == "best-rank" }.value)
        viewed.ensureInstrument(Instrument.Lead)
        advanceUntilIdle()
        assertEquals("#8", RankLoad.tile(viewed.ranks.value[Instrument.Lead]).value)
        settings.value = settings.value!!.copy(filterInvalidScores = true)
        advanceUntilIdle()
        assertFiltered(viewed.state.value, alphaRank = 40, alphaPopulation = 600, alphaBucket = 10)
        settings.value = settings.value!!.copy(filterInvalidScores = false)
        advanceUntilIdle()

        settings.value = settings.value!!.copy(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_B, "Other Player"))
        advanceUntilIdle()
        assertFalse(viewed.state.value.isSelected)
        val readsBeforeFiltering = profileReads
        settings.value = settings.value!!.copy(filterInvalidScores = true, leeway = 1.0)
        advanceUntilIdle()
        assertFiltered(viewed.state.value, alphaRank = 40, alphaPopulation = 600, alphaBucket = 10)
        assertEquals(readsBeforeFiltering, profileReads)
        assertEquals("#8", RankLoad.tile(viewed.ranks.value[Instrument.Lead]).value)
        assertEquals(1, rankingReads)
        assertEquals(1, historyReads)

        settings.value = settings.value!!.copy(leeway = 0.0)
        advanceUntilIdle()
        assertEquals("2", viewed.state.value.overview.single { it.id == "songs-played" }.value)
        assertEquals(listOf("s-delta", "s-gamma"), viewed.state.value.topSongs.single().top.map { it.songId })
        settings.value = settings.value!!.copy(leeway = 5.0)
        advanceUntilIdle()
        assertEquals("#1", viewed.state.value.overview.single { it.id == "best-rank" }.value)
        assertEquals("4", viewed.state.value.overview.single { it.id == "songs-played" }.value)

        settings.value = settings.value!!.copy(leeway = 2.0)
        advanceUntilIdle()
        assertFiltered(viewed.state.value, alphaRank = 30, alphaPopulation = 800, alphaBucket = 4)
        assertEquals(readsBeforeFiltering, profileReads)

        settings.value = settings.value!!.copy(selectedPlayer = player)
        val statistics = vm(null)
        advanceUntilIdle()
        assertTrue(viewed.state.value.isSelected)
        assertEquals(viewed.state.value.overview, statistics.state.value.overview)
        assertEquals(viewed.state.value.instruments, statistics.state.value.instruments)
        assertEquals(viewed.state.value.topSongs, statistics.state.value.topSongs)
        assertEquals(raw.scores, store.state.value.payload!!.profile.scores)
        val selectedReads = profileReads
        settings.value = settings.value!!.copy(filterInvalidScores = false)
        advanceUntilIdle()
        assertEquals("#1", viewed.state.value.overview.single { it.id == "best-rank" }.value)
        assertEquals("4", viewed.state.value.overview.single { it.id == "songs-played" }.value)
        assertEquals(4, viewed.state.value.topSongs.single().top.size)
        assertEquals(viewed.state.value.overview, statistics.state.value.overview)
        assertEquals(selectedReads, profileReads)
        assertEquals(2, catalogReads)
    }

    private fun assertFiltered(state: PlayerProfileUiState, alphaRank: Int, alphaPopulation: Int, alphaBucket: Int) {
        assertEquals("#6", state.overview.single { it.id == "best-rank" }.value)
        assertEquals("3", state.overview.single { it.id == "songs-played" }.value)
        assertEquals("1 (33.3%)", state.overview.single { it.id == "full-combos" }.value)
        assertEquals("0", state.overview.single { it.id == "gold-stars" }.value)
        assertEquals("90%", state.overview.single { it.id == "avg-accuracy" }.value)
        val chart = state.instruments.single()
        assertEquals("4", chart.stats.single { it.id == "avg-stars" }.value)
        assertEquals("#6", chart.stats.single { it.id == "best-rank" }.value)
        assertEquals("3", chart.stats.single { it.id == "over-threshold" }.value)
        assertEquals(mapOf(1 to 1, 2 to 1, alphaBucket to 1), chart.percentiles.associate { it.bucket.topPercent to it.bucket.count })
        assertEquals("Top 30%", chart.trailing.single { it.id == "percentile" }.value)
        assertEquals("Top ${if (alphaBucket == 10) 4 else 3}%", chart.trailing.single { it.id == "songs-played-percentile" }.value)
        assertEquals(listOf("s-delta", "s-gamma", "s-alpha"), state.topSongs.single().top.map { it.songId })
        val alpha = state.topSongs.single().top.last()
        assertEquals(alphaRank, alpha.rank)
        assertEquals(alphaPopulation, alpha.totalEntries)
    }
}
