package com.festivalscoretracker.android.core.settings

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.songs.SongSortMode

// region Settings model

/**
 * Persisted preferences that survive cold starts (web `SettingsContext`
 * `AppSettings` plus native-only fields). Keys and reset policy live in
 * [SettingsRegistry].
 *
 * In-app accessibility overrides are additive: they can only make the app more
 * accessible than the OS setting, never less.
 *
 * @property selectedPlayer Selected player, or null when browsing anonymously (kept by Reset).
 * @property visibleInstruments Charts shown throughout the app; never empty once sanitized.
 * @property songSort Songs sort field (kept by Reset).
 * @property songSortAscending Songs sort direction (kept by Reset).
 * @property increaseContrast Opaque surfaces and stronger borders.
 * @property reduceMotion Static background and no decorative motion.
 * @property reduceTransparency Opaque cards, no decorative imagery.
 * @property disableAnimatedArtwork Hold the artwork backdrop still.
 * @property showInstrumentIcons Per-chart status icons on unfiltered Songs rows (web `!songsHideInstrumentIcons`).
 * @property enableVisualOrder Song-row metadata order independent of sort priority.
 * @property songRowVisualOrder Song-row metadata display order (every field once).
 * @property pathColumnOrder CHOpt text-path column order (every column once).
 * @property pathDefaultView How CHOpt paths open by default.
 * @property pathUnavailableWarningDismissed The Paths unavailable-chart warning was dismissed.
 * @property filterInvalidScores Hide scores above the CHOpt maximum plus [leeway].
 * @property leeway Invalid-score leeway percent, −5…+5 in 0.1 steps.
 * @property experimentalRanks Settings → Enable Experimental Leaderboard Ranks (web `enableExperimentalRanks`, off by default):
 * gates the Adjusted, Weighted, FC Rate and Max Score metrics app-wide (experimental-ranks pattern).
 * @property hideShop Hide the Item Shop (navigation, sorts and highlights; the highlight preference is kept).
 * @property disableShopHighlighting Stop pulsing Shop highlights.
 * @property visibleMetadata Song-row metadata fields shown (all may be off).
 */
data class AppSettings(
    val selectedPlayer: SelectedPlayer? = null,
    val visibleInstruments: Set<Instrument> = Instrument.entries.toSet(),
    val songSort: SongSortMode = SongSortMode.Title,
    val songSortAscending: Boolean = true,
    val increaseContrast: Boolean = false,
    val reduceMotion: Boolean = false,
    val reduceTransparency: Boolean = false,
    val disableAnimatedArtwork: Boolean = false,
    val showInstrumentIcons: Boolean = true,
    val enableVisualOrder: Boolean = false,
    val songRowVisualOrder: List<MetadataField> = MetadataField.entries,
    val pathColumnOrder: List<PathColumnKey> = PathColumnKey.entries,
    val pathDefaultView: PathDisplayMode = PathDisplayMode.Image,
    val pathUnavailableWarningDismissed: Boolean = false,
    val filterInvalidScores: Boolean = false,
    val leeway: Double = ScoreLeeway.DEFAULT,
    val experimentalRanks: Boolean = false,
    val hideShop: Boolean = false,
    val disableShopHighlighting: Boolean = false,
    val visibleMetadata: Set<MetadataField> = MetadataField.entries.toSet(),
) {
    /** Whether Shop songs are highlighted (Shop visible and highlighting on; web `shopHighlightEnabled`). */
    val shopHighlightEnabled: Boolean get() = !hideShop && !disableShopHighlighting

    /** Settings-visible charts in canonical order. */
    val orderedVisibleInstruments: List<Instrument> get() = Instrument.entries.filter { it in visibleInstruments }

    /**
     * Visible metadata in display order: [songRowVisualOrder] when independent
     * ordering is on, else the default order (web sort-priority fallback is the
     * Songs consumer's job).
     */
    val orderedVisibleMetadata: List<MetadataField>
        get() = (if (enableVisualOrder) songRowVisualOrder else MetadataField.entries).filter { it in visibleMetadata }

    /**
     * A copy with every field clamped to a valid state.
     *
     * @return Sanitized settings.
     */
    fun sanitized(): AppSettings = copy(
        visibleInstruments = visibleInstruments.ifEmpty { Instrument.entries.toSet() },
        songRowVisualOrder = SettingsOrder.normalize(songRowVisualOrder, MetadataField.entries),
        pathColumnOrder = SettingsOrder.normalize(pathColumnOrder, PathColumnKey.entries),
        leeway = ScoreLeeway.clamp(leeway),
    )

    /**
     * Show or hide one chart; the last visible chart cannot be hidden (web
     * `disabled={showActiveCount <= 1}`).
     *
     * @param instrument Chart.
     * @param visible Desired visibility.
     * @return Updated settings.
     */
    fun withInstrumentVisible(instrument: Instrument, visible: Boolean): AppSettings = when {
        visible -> copy(visibleInstruments = visibleInstruments + instrument)
        visibleInstruments.size > 1 -> copy(visibleInstruments = visibleInstruments - instrument)
        else -> this
    }

    /**
     * Whether a chart's switch is disabled (it is the only one left on).
     *
     * @param instrument Chart.
     * @return True for the last visible chart.
     */
    fun isLastVisible(instrument: Instrument): Boolean = visibleInstruments == setOf(instrument)

    /**
     * Show or hide one metadata field (all may be off).
     *
     * @param field Field.
     * @param visible Desired visibility.
     * @return Updated settings.
     */
    fun withMetadataVisible(field: MetadataField, visible: Boolean): AppSettings =
        copy(visibleMetadata = if (visible) visibleMetadata + field else visibleMetadata - field)

    /**
     * Restore app settings only (web Reset Settings): every [ResetPolicy.AppSetting]
     * field returns to its default; the profile, Songs sort and other kept state survive.
     *
     * @return Settings with every Settings-page preference at its default.
     */
    fun resetAppSettings(): AppSettings =
        AppSettings(selectedPlayer = selectedPlayer, songSort = songSort, songSortAscending = songSortAscending)
}

/** Stable string codecs for settings values. */
object SettingsCodec {
    /**
     * Encode charts as comma-joined wire IDs in canonical order.
     *
     * @param instruments Visible charts.
     * @return Stored string.
     */
    fun encodeInstruments(instruments: Set<Instrument>): String =
        Instrument.entries.filter { it in instruments }.joinToString(",") { it.wireId }

    /**
     * Decode a stored instrument set, dropping unknown tokens. A missing value
     * means "all visible"; an explicitly empty value stays empty here and
     * [AppSettings.sanitized] restores all charts.
     *
     * @param raw Stored string or null.
     * @return Visible charts.
     */
    fun decodeInstruments(raw: String?): Set<Instrument> {
        if (raw == null) return Instrument.entries.toSet()
        return raw.split(",").mapNotNull { Instrument.fromWireId(it.trim()) }.toSet()
    }

    /**
     * Encode visible metadata as comma-joined web keys in default order.
     *
     * @param fields Visible fields.
     * @return Stored string (empty when all are off).
     */
    fun encodeMetadata(fields: Set<MetadataField>): String =
        MetadataField.entries.filter { it in fields }.joinToString(",") { it.token }

    /**
     * Decode visible metadata; missing means all visible, empty means none.
     *
     * @param raw Stored string or null.
     * @return Visible fields.
     */
    fun decodeMetadata(raw: String?): Set<MetadataField> {
        if (raw == null) return MetadataField.entries.toSet()
        return raw.split(",").mapNotNull { MetadataField.fromToken(it.trim()) }.toSet()
    }
}

// endregion
