package com.festivalscoretracker.android.data.rankings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.festivalscoretracker.android.core.rankings.RankingMetric
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

// region Leaderboard preferences

/**
 * The persisted Leaderboards Rank By choice (web `fst:leaderboardSettings`,
 * Apple `fst.leaderboards.rankBy`), stored in the shared settings DataStore under
 * its own key so it survives cold starts without touching `AppSettings`.
 *
 * @param store Shared preferences store.
 */
class LeaderboardPreferences(private val store: DataStore<Preferences>) {
    /** Current metric; unknown or missing values fall back to Total Score. */
    val rankBy: Flow<RankingMetric> = store.data
        .map { RankingMetric.fromWireId(it[KEY_RANK_BY]) ?: RankingMetric.DEFAULT }
        .distinctUntilChanged()

    /**
     * Persist the Rank By choice.
     *
     * @param metric Selected metric.
     */
    suspend fun setRankBy(metric: RankingMetric) {
        store.edit { it[KEY_RANK_BY] = metric.wireId }
    }

    companion object {
        internal val KEY_RANK_BY = stringPreferencesKey("fst.leaderboards.rankBy")
    }
}

// endregion
