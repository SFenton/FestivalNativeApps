package com.festivalscoretracker.android

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.preferencesDataStore
import com.festivalscoretracker.android.core.firstrun.FirstRunMode
import com.festivalscoretracker.android.core.firstrun.FirstRunSeenStore
import com.festivalscoretracker.android.core.nav.DebugLaunch
import com.festivalscoretracker.android.core.notifications.NotificationSeenStore
import com.festivalscoretracker.android.core.settings.SettingsRegistry
import com.festivalscoretracker.android.data.settings.SettingsBlobStore
import com.festivalscoretracker.android.presentation.firstrun.FirstRunCenter
import com.festivalscoretracker.android.core.service.ServiceRetryBackoff
import com.festivalscoretracker.android.data.FestivalApi
import com.festivalscoretracker.android.data.ForcedFreezeTransport
import com.festivalscoretracker.android.data.HttpTransport
import com.festivalscoretracker.android.data.OkHttpTransport
import com.festivalscoretracker.android.data.RetiredSettingsMigration
import com.festivalscoretracker.android.data.SettingsRepository
import com.festivalscoretracker.android.data.shop.shop
import com.festivalscoretracker.android.data.songs.SongsPreferences
import com.festivalscoretracker.android.presentation.shop.ShopStore
import com.festivalscoretracker.android.data.profile.playerProfile
import com.festivalscoretracker.android.data.rankings.LeaderboardPreferences
import com.festivalscoretracker.android.data.rivals.RivalsRepository
import com.festivalscoretracker.android.data.suggestions.SuggestionFilterStore
import com.festivalscoretracker.android.presentation.BackgroundController
import com.festivalscoretracker.android.presentation.profile.SelectedProfileStore
import com.festivalscoretracker.android.core.whatsnew.ChangelogSeenStore
import com.festivalscoretracker.android.core.whatsnew.InstallChannel
import com.festivalscoretracker.android.core.whatsnew.WhatsNewMode
import com.festivalscoretracker.android.presentation.whatsnew.WhatsNewController
import com.festivalscoretracker.android.presentation.whatsnew.installerPackage
import okhttp3.OkHttpClient

// region Container

/** Process-wide preferences store for [SettingsRepository]; opening it drops retired keys. */
private val Context.settingsDataStore: DataStore<Preferences> by preferencesDataStore(
    name = "fst_settings",
    produceMigrations = { listOf(RetiredSettingsMigration) },
)

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

    /** App-wide first-run arbiter (seen-state in the settings DataStore). */
    val firstRun = FirstRunCenter(
        FirstRunSeenStore(SettingsBlobStore(settings, SettingsRegistry.FIRST_RUN_SEEN)),
        FirstRunMode.parse(launch.firstRun, BuildConfig.DEBUG_LAUNCH),
    )

    /** "What's New" launch gate + Settings replay (dismissal in the settings DataStore). */
    val whatsNew = WhatsNewController(
        ChangelogSeenStore(SettingsBlobStore(settings, SettingsRegistry.CHANGELOG_SEEN)),
        firstRun,
        WhatsNewMode.parse(launch.whatsNew, BuildConfig.DEBUG_LAUNCH),
        BuildConfig.VERSION_NAME,
        InstallChannel.resolve(launch.distribution, BuildConfig.DEBUG_LAUNCH) { installerPackage(context) },
    )

    /** Per-account notification seen-state. */
    val notificationSeen = NotificationSeenStore(SettingsBlobStore(settings, SettingsRegistry.NOTIFICATIONS_SEEN))

    /** Selected player's process-only scores (Songs, Statistics and the player page read this). */
    val selectedProfile = SelectedProfileStore(read = { api.playerProfile(it) }, publications = api.publicationChanges, backoff = backoff)

    /** Shared Item Shop feed (Shop page, Songs and Song Detail). */
    val shop = ShopStore(load = { api.shop() }, publications = api.publicationChanges, backoff = backoff)

    /** Saved Songs filters and Shop layout. */
    val songsPreferences = SongsPreferences(settings)
}

// endregion
