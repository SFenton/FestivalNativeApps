package com.festivalscoretracker.android.core.settings

// region Registry

/** What Settings → Reset does to a persisted key (web `resetSettings` restores app settings only). */
enum class ResetPolicy {
    /** A Settings-page preference: Reset removes it so its default applies. */
    AppSetting,

    /** Profile, navigation, per-feature state or seen-state: Reset keeps it. */
    Kept,
}

/**
 * One persisted DataStore key.
 *
 * @property key Preferences key name.
 * @property policy Reset behaviour.
 * @property owner Owning feature (for reviewers).
 */
data class RegisteredSetting(val key: String, val policy: ResetPolicy, val owner: String)

/**
 * Every key the app persists, so Reset covers each feature's state and a test
 * can prove nothing is written unregistered. **Adding a persisted key? Register
 * it here** with its reset policy; `SettingsRegistryTest` fails otherwise.
 * Key names mirror Apple's `fst.settings.*` / `fst.accessibility.*` where one exists.
 */
object SettingsRegistry {
    const val ACCOUNT_ID = "fst.profile.accountId"
    const val DISPLAY_NAME = "fst.profile.displayName"
    const val SONG_SORT = "fst.songs.sort"
    const val SONG_SORT_ASCENDING = "fst.songs.sortAscending"
    const val VISIBLE_INSTRUMENTS = "fst.settings.visibleInstruments"
    const val INCREASE_CONTRAST = "fst.accessibility.moreContrast"
    const val REDUCE_MOTION = "fst.accessibility.reduceMotion"
    const val REDUCE_TRANSPARENCY = "fst.accessibility.lessTransparency"
    const val DISABLE_ANIMATED_ARTWORK = "fst.accessibility.disableAnimatedArtwork"
    const val SHOW_INSTRUMENT_ICONS = "fst.settings.showInstrumentIcons"
    const val ENABLE_VISUAL_ORDER = "fst.settings.enableVisualOrder"
    const val SONG_ROW_VISUAL_ORDER = "fst.settings.songRowVisualOrder"
    const val PATH_COLUMN_ORDER = "fst.settings.pathColumnOrder"
    const val PATH_DEFAULT_VIEW = "fst.settings.pathDefaultView"
    const val PATH_WARNING_DISMISSED = "fst.settings.pathUnavailableWarningDismissed"
    const val FILTER_INVALID_SCORES = "fst.settings.filterInvalidScores"
    const val LEEWAY = "fst.settings.leeway"
    const val EXPERIMENTAL_RANKS = "fst.settings.experimentalRanks"
    const val HIDE_SHOP = "fst.settings.hideShop"
    const val DISABLE_SHOP_HIGHLIGHTING = "fst.settings.disableShopHighlighting"
    const val VISIBLE_METADATA = "fst.settings.visibleMetadata"
    const val FIRST_RUN_SEEN = "fst.firstRun.seen.v1"
    const val NOTIFICATIONS_SEEN = "fst.notifications.seen.v1"
    const val CHANGELOG_SEEN = "fst.changelog.seen.v1"
    const val SUGGESTIONS_FILTER = "fst.suggestions.filter"
    const val SONG_FILTERS = "fst.songs.filters"
    const val SONG_PLAYER_SCORE_FILTERS = "fst.songs.playerScoreFilters"
    const val SONG_METADATA_ORDER = "fst.songs.metadataOrder"
    const val SHOP_VIEW_MODE = "fst.shop.viewMode"
    const val SHOP_SORT = "fst.shop.sort"
    const val SHOP_SORT_ASCENDING = "fst.shop.sortAscending"

    /** Every registered key. */
    val entries: List<RegisteredSetting> = listOf(
        RegisteredSetting(ACCOUNT_ID, ResetPolicy.Kept, "profile"),
        RegisteredSetting(DISPLAY_NAME, ResetPolicy.Kept, "profile"),
        RegisteredSetting(SONG_SORT, ResetPolicy.Kept, "songs"),
        RegisteredSetting(SONG_SORT_ASCENDING, ResetPolicy.Kept, "songs"),
        RegisteredSetting(VISIBLE_INSTRUMENTS, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(INCREASE_CONTRAST, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(REDUCE_MOTION, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(REDUCE_TRANSPARENCY, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(DISABLE_ANIMATED_ARTWORK, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(SHOW_INSTRUMENT_ICONS, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(ENABLE_VISUAL_ORDER, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(SONG_ROW_VISUAL_ORDER, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(PATH_COLUMN_ORDER, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(PATH_DEFAULT_VIEW, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(PATH_WARNING_DISMISSED, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(FILTER_INVALID_SCORES, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(LEEWAY, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(EXPERIMENTAL_RANKS, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(HIDE_SHOP, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(DISABLE_SHOP_HIGHLIGHTING, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(VISIBLE_METADATA, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(FIRST_RUN_SEEN, ResetPolicy.Kept, "first-run"),
        RegisteredSetting(NOTIFICATIONS_SEEN, ResetPolicy.Kept, "notifications"),
        RegisteredSetting(CHANGELOG_SEEN, ResetPolicy.Kept, "whats-new"),
        RegisteredSetting(SUGGESTIONS_FILTER, ResetPolicy.AppSetting, "suggestions"),
        RegisteredSetting(SONG_FILTERS, ResetPolicy.Kept, "songs"),
        RegisteredSetting(SONG_PLAYER_SCORE_FILTERS, ResetPolicy.Kept, "songs"),
        RegisteredSetting(SONG_METADATA_ORDER, ResetPolicy.Kept, "songs"),
        RegisteredSetting(SHOP_VIEW_MODE, ResetPolicy.Kept, "shop"),
        RegisteredSetting(SHOP_SORT, ResetPolicy.Kept, "shop"),
        RegisteredSetting(SHOP_SORT_ASCENDING, ResetPolicy.Kept, "shop"),
    )

    /** Keys Reset removes. */
    val appSettingKeys: List<String> get() = entries.filter { it.policy == ResetPolicy.AppSetting }.map { it.key }

    /**
     * Keys older builds wrote that no longer exist (Tap Diagnostics / Tap Telemetry, #374).
     * `RetiredSettingsMigration` deletes them when the store first opens.
     */
    val retiredKeys: List<String> = listOf("fst.settings.tapDiagnostics", "fst.settings.tapTelemetry")

    /**
     * Whether a key is registered.
     *
     * @param key Preferences key name.
     * @return True when registered.
     */
    fun isRegistered(key: String): Boolean = entries.any { it.key == key }
}

// endregion
