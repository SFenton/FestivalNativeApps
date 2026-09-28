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
    const val TAP_DIAGNOSTICS = "fst.settings.tapDiagnostics"
    const val TAP_TELEMETRY = "fst.settings.tapTelemetry"
    const val VISIBLE_METADATA = "fst.settings.visibleMetadata"
    const val FIRST_RUN_SEEN = "fst.firstRun.seen.v1"
    const val NOTIFICATIONS_SEEN = "fst.notifications.seen.v1"

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
        RegisteredSetting(TAP_DIAGNOSTICS, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(TAP_TELEMETRY, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(VISIBLE_METADATA, ResetPolicy.AppSetting, "settings"),
        RegisteredSetting(FIRST_RUN_SEEN, ResetPolicy.Kept, "first-run"),
        RegisteredSetting(NOTIFICATIONS_SEEN, ResetPolicy.Kept, "notifications"),
    )

    /** Keys Reset removes. */
    val appSettingKeys: List<String> get() = entries.filter { it.policy == ResetPolicy.AppSetting }.map { it.key }

    /**
     * Whether a key is registered.
     *
     * @param key Preferences key name.
     * @return True when registered.
     */
    fun isRegistered(key: String): Boolean = entries.any { it.key == key }
}

// endregion
