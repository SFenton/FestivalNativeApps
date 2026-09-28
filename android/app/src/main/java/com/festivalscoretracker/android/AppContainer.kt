package com.festivalscoretracker.android

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ForcedFreezeTransport
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.data.OkHttpTransport
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.data.profile.playerProfile
import com.festivalscoretracker.android.data.rankings.LeaderboardPreferences
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.data.suggestions.SuggestionFilterStore
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.profile.SelectedProfileStore
import okhttp3.OkHttpClient

// region Container

/** Process-wide preferences store for [SettingsRepository]. */
private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(name = "fst_settings")

/**
 * Manual dependency graph for the single activity (process lifetime).
 *
 * @param context Application context.
 * @param httpClient Shared cache-less OkHttp client (also used for artwork).
 * @param launch Debug launch extras; only debug builds pass anything but [DebugLaunch.NONE].
 * @param transport Transport override for fixture-backed tests.
 * @param settingsStore Preferences override for tests.
 */
class AppContainer(
    context: Context,
    httpClient: OkHttpClient,
    launch: DebugLaunch,
    transport: HttpTransport? = null,
    settingsStore: DataStore<Preferences>? = null,
) {
    /** Keyless public API client. */
    val api: FestivalApi = run {
        val base = transport ?: OkHttpTransport(httpClient)
        val effective = if (launch.forceFreeze) ForcedFreezeTransport(base) else base
        FestivalApi(launch.origin ?: BuildConfig.SERVICE_ORIGIN, effective)
    }

    /** Persisted settings. */
    val settings = SettingsRepository(settingsStore ?: context.applicationContext.settingsDataStore)

    /** Persisted Leaderboards Rank By (same store, its own key). */
    val leaderboardPreferences = LeaderboardPreferences(settingsStore ?: context.applicationContext.settingsDataStore)

    /** Persisted Suggestions filter (its own key in the shared settings store). */
    val suggestionFilters = SuggestionFilterStore(settingsStore ?: context.applicationContext.settingsDataStore)

    /** Debug-pinned Suggestions seed, or null for a random mix. */
    val suggestionsSeed: Long? = launch.suggestionsSeed

    /** Shared automatic-retry backoff. */
    val backoff = ServiceRetryBackoff()

    /** Rivals reads over an in-process cache. */
    val rivals = RivalsRepository(api)

    /** Shared animated backdrop state. */
    val background = BackgroundController(loadCatalog = { api.catalog() }, artworkUrl = api::artworkUrl)

    /** Selected player's process-only scores (Songs, Statistics and the player page read this). */
    val selectedProfile = SelectedProfileStore(read = { api.playerProfile(it) }, publications = api.publicationChanges, backoff = backoff)
}

// endregion
