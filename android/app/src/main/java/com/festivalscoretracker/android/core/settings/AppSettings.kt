package com.festivalscoretracker.android.core.settings

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.songs.SongSortMode

// region Settings model

/**
 * Persisted preferences that survive cold starts.
 *
 * In-app accessibility overrides are additive: they can only make the app more
 * accessible than the OS setting, never less.
 *
 * @property selectedPlayer Selected player, or null when browsing anonymously.
 * @property visibleInstruments Charts shown on Song Detail and in filters.
 * @property songSort Songs sort field.
 * @property songSortAscending Songs sort direction.
 * @property increaseContrast Opaque surfaces and stronger borders.
 * @property reduceMotion Static background and no decorative motion.
 */
data class AppSettings(
    val selectedPlayer: SelectedPlayer? = null,
    val visibleInstruments: Set<Instrument> = Instrument.entries.toSet(),
    val songSort: SongSortMode = SongSortMode.Title,
    val songSortAscending: Boolean = true,
    val increaseContrast: Boolean = false,
    val reduceMotion: Boolean = false,
)

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
     * means "all visible"; an explicitly empty value stays empty.
     *
     * @param raw Stored string or null.
     * @return Visible charts.
     */
    fun decodeInstruments(raw: String?): Set<Instrument> {
        if (raw == null) return Instrument.entries.toSet()
        return raw.split(",").mapNotNull { Instrument.fromWireId(it.trim()) }.toSet()
    }
}

// endregion
