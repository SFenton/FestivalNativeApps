package com.festivalscoretracker.android.core.profile

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.rankings.RankingMetric
import com.festivalscoretracker.android.core.songs.SongFilter
import com.festivalscoretracker.android.core.songs.SongPlayerScoreFilter
import com.festivalscoretracker.android.core.songs.SongScoreFilterKind
import com.festivalscoretracker.android.core.songs.SongShopFilter
import com.festivalscoretracker.android.core.songs.SongSortMode

// region Songs presets

/**
 * The saved Songs state a preset rewrites (web `SongSettings` subset Android can express).
 *
 * @property filter Public chart/difficulty filter.
 * @property shopFilter Public Shop filter.
 * @property playerFilter Selected-player score/FC checks.
 * @property sort Sort mode.
 * @property ascending Sort direction.
 */
data class SongsFilterState(
    val filter: SongFilter = SongFilter(),
    val shopFilter: SongShopFilter = SongShopFilter(),
    val playerFilter: SongPlayerScoreFilter = SongPlayerScoreFilter(),
    val sort: SongSortMode = SongSortMode.Title,
    val ascending: Boolean = true,
)

/**
 * A stat tile's Songs filter (web `playerFilterHelpers.ts` and the `*Updater`s in
 * `OverallSummarySection.tsx`/`InstrumentStatsSection.tsx`). Only the presets whose
 * filters the Android Songs page supports exist; star, percentile and CHOpt-threshold
 * presets need Songs filters that are not ported yet, so those tiles stay flat.
 */
sealed interface SongsPreset {
    /**
     * Rewrite the saved Songs state.
     *
     * @param current Saved state.
     * @return New state to persist before showing Songs.
     */
    fun apply(current: SongsFilterState): SongsFilterState

    /**
     * Overview "Songs Played"/"Full Combos": every filter reset, Title ascending, and the
     * check set on every Settings-visible chart (web `songsPlayedUpdater`/`fullCombosUpdater`).
     *
     * @property kind [SongScoreFilterKind.HasScores] or [SongScoreFilterKind.HasFCs].
     * @property visible Settings-visible charts.
     */
    data class Overall(val kind: SongScoreFilterKind, val visible: Set<Instrument>) : SongsPreset {
        override fun apply(current: SongsFilterState): SongsFilterState =
            SongsFilterState(playerFilter = SongPlayerScoreFilter().withAll(kind, visible, true))
    }

    /**
     * An instrument's "Songs Played"/"FCs": that chart only, its checks and difficulty
     * cleared, then one check set, sorted by Score ascending; other charts' checks and the
     * Shop filter are kept (web `cleanFilters` + `instSongsPlayedUpdater`/`instFCsUpdater`).
     *
     * @property kind [SongScoreFilterKind.HasScores] or [SongScoreFilterKind.HasFCs].
     * @property instrument Chart.
     */
    data class ForInstrument(val kind: SongScoreFilterKind, val instrument: Instrument) : SongsPreset {
        override fun apply(current: SongsFilterState): SongsFilterState {
            val cleared = SongScoreFilterKind.entries.fold(current.playerFilter) { filter, check -> filter.with(check, instrument, false) }
            return current.copy(
                filter = SongFilter(instrument = instrument),
                playerFilter = cleared.with(kind, instrument, true),
                sort = SongSortMode.Score,
                ascending = true,
            )
        }
    }
}

// endregion

// region Tile actions

/** What tapping a stat tile or a top-song row does (web `StatBox.onClick`). */
sealed interface PlayerTileAction {
    /**
     * Whether the action is meaningless without selecting the viewed player. Every action
     * selects a viewed player first when it can (web `withProfileSwitch`); only a Songs
     * filter is withheld when selection is paused (unverified or changed publication).
     */
    val requiresSelection: Boolean get() = false

    /**
     * Save a Songs filter, then show the Songs tab.
     *
     * @property preset Filter.
     */
    data class FilterSongs(val preset: SongsPreset) : PlayerTileAction {
        override val requiresSelection: Boolean get() = true
    }

    /**
     * Open Song Detail (Best Rank tiles, top-song rows).
     *
     * @property songId Song.
     * @property instrument Chart the web focuses (`?instrument=`).
     */
    data class OpenSong(val songId: String, val instrument: Instrument) : PlayerTileAction

    /**
     * Open an instrument's full rankings (the Total Score rank tile).
     *
     * @property instrument Chart.
     * @property metric Rank By.
     */
    data class OpenRankings(val instrument: Instrument, val metric: RankingMetric = RankingMetric.TotalScore) : PlayerTileAction
}

// endregion
