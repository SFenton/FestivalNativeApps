package com.festivalscoretracker.android.presentation.profile

import com.festivalscoretracker.android.core.bands.PlayerBandGroup
import com.festivalscoretracker.android.core.bands.PlayerBandListResponse
import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.PopulationTiers
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.FullRankingsRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.nav.SongsTab
import com.festivalscoretracker.android.core.profile.StatTints
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRanking
import com.festivalscoretracker.android.core.profile.PlayerInstrumentRankingPayload
import com.festivalscoretracker.android.core.profile.PlayerProfilePayload
import com.festivalscoretracker.android.core.profile.PlayerProfileResponse
import com.festivalscoretracker.android.core.profile.PlayerProfileState
import com.festivalscoretracker.android.core.profile.PlayerRankHistory
import com.festivalscoretracker.android.core.profile.PlayerTileAction
import com.festivalscoretracker.android.core.profile.SongsPreset
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.core.settings.AppSettings
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.testing.Fixtures
import com.festivalscoretracker.android.testing.MainDispatcherRule
import com.festivalscoretracker.android.testing.ProfileFixtures
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/** Tile actions (web `withProfileSwitch`) and top songs on the player page model. */
@OptIn(ExperimentalCoroutinesApi::class)
class ProfileActionsTest {
    @get:Rule
    val main = MainDispatcherRule()

    private val storeJob = Job()
    private val settings = MutableStateFlow<AppSettings?>(AppSettings())
    private val publications = MutableStateFlow<Int?>(7)
    private var header: Int? = 7
    private var catalogFailure: Exception? = null
    private var catalogReads = 0
    private var leadMaximum: Int? = null
    private var bandsFailure: Exception? = null
    private var bandsFailingGroup: PlayerBandGroup? = null
    private val bandReads = mutableListOf<String>()
    private val presets = mutableListOf<SongsPreset>()
    private val selected = mutableListOf<SelectedPlayer?>()

    @After
    fun tearDown() = storeJob.cancel()

    private var alphaPopulation: Map<String, PopulationTiers?>? = null

    private var rows = listOf(
        ProfileFixtures.score("s-alpha", "01", fc = true, stars = 6, rank = 1, total = 200),
        ProfileFixtures.score("s-beta", "01", rank = 30, total = 200),
        ProfileFixtures.score("s-gamma", "02", rank = 9, total = 10),
    )

    private val reads = ProfileReads(
        profile = { account ->
            val profile = FestivalApi.JSON.decodeFromString(PlayerProfileResponse.serializer(), ProfileFixtures.profile(account, rows = rows))
            PlayerProfilePayload(profile, PlayerProfileState.Available, header, 7)
        },
        ranking = { _, account ->
            PlayerInstrumentRankingPayload(FestivalApi.JSON.decodeFromString(PlayerInstrumentRanking.serializer(), ProfileFixtures.ranking(account)))
        },
        rankHistory = { instrument, account ->
            FestivalApi.JSON.decodeFromString(PlayerRankHistory.serializer(), ProfileFixtures.rankHistory(account, instrument.wireId))
        },
        catalog = {
            catalogReads++
            catalogFailure?.let { throw it }
            listOf(Song("s-alpha", "Alpha Song", "Alpha Artist", year = 2021, albumArt = "alpha.jpg", maxScores = leadMaximum?.let { mapOf("Solo_Guitar" to it) }, populationTiers = alphaPopulation))
        },
        bands = { account, group ->
            bandReads += "$account:${group.wireId}"
            bandsFailure?.takeIf { group == bandsFailingGroup || bandsFailingGroup == null }?.let { throw it }
            PlayerBandListResponse(accountId = account, totalCount = 0)
        },
    )

    private fun viewModel(scope: CoroutineScope, accountId: String?): PlayerProfileViewModel {
        val store = SelectedProfileStore(reads.profile, publications, ServiceRetryBackoff())
        store.start(CoroutineScope(scope.coroutineContext + storeJob), settings.map { it?.selectedPlayer })
        return PlayerProfileViewModel(
            accountId = accountId,
            routeDisplayName = null,
            reads = reads,
            store = store,
            settings = settings,
            publications = publications,
            backoff = ServiceRetryBackoff(),
            onSelect = { player -> selected += player; settings.value = settings.value?.copy(selectedPlayer = player) },
            onDeselect = { selected += null; settings.value = settings.value?.copy(selectedPlayer = null) },
            saveSongsPreset = { presets += it },
            artworkUrl = { raw -> raw?.let { "https://art/$it" } },
        )
    }

    private val lead = SongsPreset.ForInstrument(SongScoreFilterKind.HasScores, Instrument.Lead)

    @Test
    fun overThresholdTileFollowsFilterInvalidScores() = runTest(main.dispatcher) {
        // Alpha Lead scores 90,000 on an 86,000 CHOpt maximum (+1% leeway = 86,860): over threshold.
        leadMaximum = 86_000
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        fun lead() = vm.state.value.instruments.first { it.instrument == Instrument.Lead }.stats
        assertTrue(lead().none { it.id == "over-threshold" })
        settings.value = settings.value?.copy(filterInvalidScores = true)
        advanceUntilIdle()
        val tile = lead().first { it.id == "over-threshold" }
        assertEquals("Over CHOpt Threshold", tile.label)
        assertEquals("1", tile.value)
        assertEquals(StatTints.RED, tile.tint)
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.OverThreshold(Instrument.Lead)), tile.action)
        // Web PlayerContent: the count reads raw scores, while the other tiles read the effective
        // scores (Alpha has no valid fallback, so its FC drops out). Bass (no maximum) gets no tile.
        assertEquals(listOf("songs-played", "over-threshold"), lead().take(2).map { it.id })
        assertEquals("1", lead().first().value)
        assertTrue(vm.state.value.instruments.first { it.instrument == Instrument.Bass }.stats.none { it.id == "over-threshold" })
        // A leeway wide enough to accept the score drops the tile again.
        settings.value = settings.value?.copy(leeway = 5.0)
        advanceUntilIdle()
        assertTrue(lead().none { it.id == "over-threshold" })
    }

    @Test
    fun overThresholdTileUsesTheUnroundedCeilingNotMinLeeway() = runTest(main.dispatcher) {
        // Web isScoreValid (R8): only score vs CHOpt maximum × (1 + leeway / 100), unrounded.
        leadMaximum = 100_000
        settings.value = settings.value?.copy(filterInvalidScores = true, leeway = 1.0)
        fun lead(vm: PlayerProfileViewModel) = vm.state.value.instruments.first { it.instrument == Instrument.Lead }.stats

        // 101,040 is over the 101,000 ceiling even though its rounded ml (1.0) is within the leeway.
        rows = listOf("""{"si":"s-alpha","ins":"01","sc":101040,"acc":1000,"fc":false,"st":5,"rk":3,"te":200,"ml":1.0}""")
        val over = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertEquals("1", lead(over).first { it.id == "over-threshold" }.value)

        // At or below the ceiling, an ml above the leeway does not count.
        for (score in listOf(101_000, 100_500)) {
            rows = listOf("""{"si":"s-alpha","ins":"01","sc":$score,"acc":1000,"fc":false,"st":5,"rk":3,"te":200,"ml":1.5}""")
            val under = viewModel(this, Fixtures.ACCOUNT_A)
            advanceUntilIdle()
            assertTrue("score $score", lead(under).none { it.id == "over-threshold" })
        }
    }

    @Test
    fun viewedProfileShowsFilteredRanksLikeWebFilterPlayerScores() = runTest(main.dispatcher) {
        // #619: another player is selected, so this is a viewed (non-selected) profile.
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_B, "Other Player"))
        rows = listOf(
            """{"si":"s-alpha","ins":"01","sc":99000,"acc":1000,"fc":true,"st":6,"rk":1,"te":200,"ml":2.0,""" +
                """"vs":[{"sc":80000,"acc":950,"fc":false,"st":5,"ml":0.5,"rt":[{"l":0.0,"r":40},{"l":1.5,"r":35}]}]}""",
            ProfileFixtures.score("s-beta", "01", rank = 30, total = 200),
            """{"si":"s-gamma","ins":"02","sc":70000,"acc":900,"fc":false,"st":5,"rk":9,"te":10,"ml":3.0}""",
        )
        alphaPopulation = mapOf("Solo_Guitar" to PopulationTiers(150, doubleArrayOf(0.5, 1.5), intArrayOf(160, 180)))
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        fun section(chart: Instrument) = vm.state.value.instruments.first { it.instrument == chart }
        fun bestRank() = section(Instrument.Lead).stats.first { it.id == "best-rank" }
        fun leadTop() = vm.state.value.topSongs.first { it.instrument == Instrument.Lead }.top.map { Triple(it.songId, it.rank, it.totalEntries) }
        assertFalse(vm.state.value.isSelected)
        // Off: raw scores.
        assertEquals("#1", bestRank().value)
        assertEquals("#1", vm.state.value.overview.first { it.id == "best-rank" }.value)
        assertEquals(listOf(1, 15), section(Instrument.Lead).percentiles.map { it.bucket.topPercent })
        assertEquals(listOf(Triple("s-alpha", 1, 200), Triple("s-beta", 30, 200)), leadTop())
        assertTrue(section(Instrument.Bass).hasScores)

        // On at 1.0: Alpha shows its valid variant at rank 40 of 160; Gamma has no valid score.
        settings.value = settings.value?.copy(filterInvalidScores = true, leeway = 1.0)
        advanceUntilIdle()
        assertEquals("#30", bestRank().value)
        assertEquals(PlayerTileAction.OpenSong("s-beta", Instrument.Lead), vm.state.value.overview.first { it.id == "best-rank" }.action)
        assertTrue(section(Instrument.Lead).stats.none { it.id == "full-combos" })
        assertEquals(listOf(15, 25), section(Instrument.Lead).percentiles.map { it.bucket.topPercent })
        assertEquals(listOf(Triple("s-beta", 30, 200), Triple("s-alpha", 40, 160)), leadTop())
        assertFalse(section(Instrument.Bass).hasScores)
        assertTrue(vm.state.value.topSongs.first { it.instrument == Instrument.Bass }.isEmpty)

        // A wider leeway re-resolves in place: the variant's next rank tier and population.
        settings.value = settings.value?.copy(leeway = 1.5)
        advanceUntilIdle()
        assertEquals(listOf(Triple("s-beta", 30, 200), Triple("s-alpha", 35, 180)), leadTop())

        // Off again: raw ranks return without another read.
        settings.value = settings.value?.copy(filterInvalidScores = false)
        advanceUntilIdle()
        assertEquals("#1", bestRank().value)
        assertEquals(listOf(Triple("s-alpha", 1, 200), Triple("s-beta", 30, 200)), leadTop())
        assertEquals(1, catalogReads)
    }

    @Test
    fun statisticsAndViewedProfileAgreeOnFilteredRanks() = runTest(main.dispatcher) {
        rows = listOf(
            """{"si":"s-alpha","ins":"01","sc":99000,"acc":1000,"fc":true,"st":6,"rk":1,"te":200,"ml":2.0,""" +
                """"vs":[{"sc":80000,"acc":950,"fc":false,"st":5,"ml":0.5,"rt":[{"l":0.0,"r":40}]}]}""",
        )
        settings.value = AppSettings(filterInvalidScores = true, leeway = 1.0)
        val viewed = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        fun best(vm: PlayerProfileViewModel) = vm.state.value.instruments.first { it.instrument == Instrument.Lead }.stats.first { it.id == "best-rank" }.value
        assertFalse(viewed.state.value.isSelected)
        val viewedBest = best(viewed)
        settings.value = settings.value?.copy(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        val statistics = viewModel(this, null)
        advanceUntilIdle()
        assertTrue(statistics.state.value.isSelected)
        assertEquals("#40", viewedBest)
        assertEquals(viewedBest, best(statistics))
    }

    @Test
    fun tilesCarryTheWebActions() = runTest(main.dispatcher) {
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        val state = vm.state.value
        val visible = Instrument.entries.toSet()
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.Overall(SongScoreFilterKind.HasScores, visible)), state.overview[0].action)
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.Overall(SongScoreFilterKind.HasFCs, visible)), state.overview[1].action)
        assertNull(state.overview[2].action)
        assertNull(state.overview[3].action)
        assertEquals(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead), state.overview[4].action)
        val leadTiles = state.instruments.first { it.instrument == Instrument.Lead }.stats
        assertEquals(PlayerTileAction.FilterSongs(lead), leadTiles[0].action)
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.ForInstrument(SongScoreFilterKind.HasFCs, Instrument.Lead)), leadTiles[1].action)
        // Avg Stars: a 6-star and a 5-star row average 5.5 (web formatClamped2).
        assertEquals(PlayerStatTile("avg-stars", "Avg Stars", "5.5"), leadTiles[5])
        assertEquals(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead), leadTiles[6].action)
        assertEquals("Best Lead Song Rank", leadTiles[6].label)
        // Web star cards: non-zero counts only, gold first.
        assertEquals(listOf("stars-6", "stars-5"), leadTiles.filter { it.id.startsWith("stars-") }.map { it.id })
        assertTrue(leadTiles[2].gold)
        // Web percentile tiles after the rank card sort Songs by Percentile.
        val trailing = state.instruments.first { it.instrument == Instrument.Lead }.trailing
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.Percentile(Instrument.Lead, scoredOnly = false)), trailing[0].action)
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.Percentile(Instrument.Lead, scoredOnly = true)), trailing[1].action)
        assertEquals("Songs Played percentile: ${trailing[1].value}", trailing[1].announcement)
        // Bass has no full combo, so its FC tile is flat (the web omits the card).
        val bassTiles = state.instruments.first { it.instrument == Instrument.Bass }.stats
        assertTrue(bassTiles.none { it.id == "full-combos" })
        val bassStars = bassTiles.first { it.id.startsWith("stars-") }
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.Stars(Instrument.Bass, bassStars.id.removePrefix("stars-").toInt())), bassStars.action)
        // Percentile rows filter Songs to their bucket (6.35).
        val leadRows = state.instruments.first { it.instrument == Instrument.Lead }.percentiles
        assertEquals(PlayerTileAction.FilterSongs(SongsPreset.PercentileBucket(Instrument.Lead, 1)), leadRows.first().action)
        vm.ensureInstrument(Instrument.Lead)
        advanceUntilIdle()
        val rank = vm.ranks.value[Instrument.Lead] as RankLoad.Available
        val total = RankLoad.tiles(rank, experimentalRanks = false).single()
        val open = total.action as PlayerTileAction.OpenRankings
        assertEquals(Instrument.Lead, open.instrument)
        assertEquals(RankingMetric.TotalScore, open.metric)
        assertEquals(RankLoad.TILE_LABEL, total.label)
        assertEquals(1, open.page)
        // Experimental Ranks on (#541): one web rank card per metric, each opening its own board.
        val all = RankLoad.tiles(rank, experimentalRanks = true)
        assertEquals(RankingMetric.entries.map { RankLoad.tileLabel(it) }, all.map { it.label })
        assertEquals(RankingMetric.entries.map { RankLoad.tileId(it) }, all.map { it.id })
        all.zip(RankingMetric.entries).forEach { (tile, metric) ->
            (tile.action as? PlayerTileAction.OpenRankings)?.let { assertEquals(metric, it.metric) } ?: assertEquals("—", tile.value)
        }
    }

    @Test
    fun topSongsUseTheCatalogueAndFallBackWithoutIt() = runTest(main.dispatcher) {
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        val leadTop = vm.state.value.topSongs.first { it.instrument == Instrument.Lead }
        assertEquals(listOf("s-alpha", "s-beta"), leadTop.top.map { it.songId })
        assertEquals("Alpha Song", leadTop.top[0].title)
        assertEquals("https://art/alpha.jpg", leadTop.top[0].artUrl)
        assertEquals("s-beta", leadTop.top[1].title)
        assertTrue(vm.state.value.topSongs.first { it.instrument == Instrument.Drums }.isEmpty)
        assertEquals(Instrument.entries.size, vm.state.value.topSongs.size)
        // Hiding a chart drops its card; the catalogue is read once.
        settings.value = settings.value?.withInstrumentVisible(Instrument.Drums, false)
        advanceUntilIdle()
        assertFalse(vm.state.value.topSongs.any { it.instrument == Instrument.Drums })
        assertEquals(1, catalogReads)
    }

    @Test
    fun catalogueFailureKeepsSongIds() = runTest(main.dispatcher) {
        catalogFailure = IOException("offline")
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertEquals("s-alpha", vm.state.value.topSongs.first { it.instrument == Instrument.Lead }.top[0].title)
    }

    @Test
    fun viewedPlayerIsSelectedBeforeNavigating() = runTest(main.dispatcher) {
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertTrue(vm.state.value.canRun(PlayerTileAction.FilterSongs(lead)))
        val result = vm.run(PlayerTileAction.FilterSongs(lead))
        assertEquals(ProfileActionResult.Navigate(SongsTab), result)
        assertEquals(Fixtures.ACCOUNT_A, selected.single()?.accountId)
        assertEquals(listOf<SongsPreset>(lead), presets)
        advanceUntilIdle()
        // Now selected: later actions navigate without selecting again.
        assertEquals(ProfileActionResult.Navigate(SongDetailRoute("s-alpha", "Solo_Guitar")), vm.run(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead)))
        assertEquals(
            ProfileActionResult.Navigate(FullRankingsRoute("Solo_Bass", "totalscore")),
            vm.run(PlayerTileAction.OpenRankings(Instrument.Bass)),
        )
        assertEquals(1, selected.size)
    }

    @Test
    fun anotherSelectedPlayerNeedsConfirmation() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_B, "Other Player"))
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        assertEquals(PlayerIdentityAction.Switch, vm.state.value.identity)
        assertEquals(ProfileActionResult.ConfirmSwitch, vm.run(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead)))
        assertTrue(selected.isEmpty())
        assertEquals(ProfileActionResult.Navigate(SongDetailRoute("s-alpha", "Solo_Guitar")), vm.run(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead), confirmedSwitch = true))
        assertEquals(Fixtures.ACCOUNT_A, selected.single()?.accountId)
    }

    @Test
    fun pausedSelectionWithholdsOnlySongsFilters() = runTest(main.dispatcher) {
        header = null
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        val state = vm.state.value
        assertEquals(PlayerIdentityAction.Unverified, state.identity)
        assertFalse(state.canRun(PlayerTileAction.FilterSongs(lead)))
        assertTrue(state.canRun(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead)))
        assertEquals(ProfileActionResult.Unavailable, vm.run(PlayerTileAction.FilterSongs(lead)))
        assertEquals(ProfileActionResult.Navigate(SongDetailRoute("s-alpha", "Solo_Guitar")), vm.run(PlayerTileAction.OpenSong("s-alpha", Instrument.Lead)))
        assertTrue(selected.isEmpty())
        assertTrue(presets.isEmpty())
    }

    @Test
    fun failedSelectionDoesNotApplyTheFilter() = runTest(main.dispatcher) {
        val vm = viewModel(this, Fixtures.ACCOUNT_A)
        advanceUntilIdle()
        // The publication advanced after the state was built but before the tap landed.
        publications.value = 8
        assertEquals(PlayerIdentityAction.Select, vm.state.value.identity)
        assertEquals(ProfileActionResult.Unavailable, vm.run(PlayerTileAction.FilterSongs(lead)))
        assertTrue(presets.isEmpty())
        assertTrue(selected.isEmpty())
    }

    @Test
    fun bandsPreviewLoadsOnceRetriesAndResetsPerAccount() = runTest(main.dispatcher) {
        val vm = viewModel(this, null)
        advanceUntilIdle()
        // Statistics with no selection reads nothing.
        vm.ensureBands()
        assertNull(vm.bands.value)
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        advanceUntilIdle()
        // One failing group fails the whole section (no partial Duos/Trios/Quads preview).
        bandsFailure = IOException("offline")
        bandsFailingGroup = PlayerBandGroup.Trios
        vm.ensureBands()
        advanceUntilIdle()
        assertTrue(vm.bands.value is BandsLoad.Failed)
        vm.ensureBands()
        advanceUntilIdle()
        val groups = listOf("duos", "trios", "quads")
        // A failing group cancels the reads still pending; ensureBands never re-reads a failed section.
        assertTrue(bandReads.isNotEmpty() && bandReads.all { it in groups.map { g -> "${Fixtures.ACCOUNT_A}:$g" } })
        val failedReads = bandReads.size
        bandsFailure = null
        vm.retryBands()
        advanceUntilIdle()
        assertEquals(groups.map { "${Fixtures.ACCOUNT_A}:$it" }.toSet(), bandReads.drop(failedReads).toSet())
        val loaded = (vm.bands.value as BandsLoad.Loaded).groups
        assertEquals(listOf(PlayerBandGroup.Duos, PlayerBandGroup.Trios, PlayerBandGroup.Quads), loaded.map { it.group })
        assertTrue(loaded.all { it.page == PlayerBandListResponse(accountId = Fixtures.ACCOUNT_A) })
        // Another selected account resets the preview until its section is shown again.
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_B, "Other"))
        advanceUntilIdle()
        assertNull(vm.bands.value)
        assertEquals(failedReads + 3, bandReads.size)
        assertTrue(bandReads.all { it.startsWith(Fixtures.ACCOUNT_A) })
    }

    @Test
    fun statisticsRunsActionsWithoutSelecting() = runTest(main.dispatcher) {
        settings.value = AppSettings(selectedPlayer = SelectedPlayer(Fixtures.ACCOUNT_A, "Synthetic Player"))
        val vm = viewModel(this, null)
        advanceUntilIdle()
        assertTrue(vm.state.value.isSelected)
        assertEquals(ProfileActionResult.Navigate(SongsTab), vm.run(PlayerTileAction.FilterSongs(lead)))
        assertTrue(selected.isEmpty())
        assertEquals(1, presets.size)
    }
}
