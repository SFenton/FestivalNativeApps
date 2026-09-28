package com.festivalscoretracker.android.core.suggestions

import com.festivalscoretracker.android.core.model.Instrument
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// region Filter settings

/**
 * Persisted Suggestions filter (web `SuggestionsFilterDraft`, Apple
 * `SuggestionFilterSettings`): per-instrument visibility plus global and
 * per-instrument toggles for each [SuggestionCategoryType].
 *
 * Storage is minimal by construction: only keys switched **off** are recorded, so
 * [isActive] is exactly "anything off" and an untouched filter encodes to `""`.
 * Immutable; every mutation returns a new value (Compose-friendly).
 *
 * @property instrumentOff Wire IDs of hidden instruments.
 * @property globalTypeOff Type keys switched off globally.
 * @property perInstrumentTypeOff `"Solo_X|typeKey"` combinations switched off.
 */
@Serializable
data class SuggestionFilterSettings(
    val instrumentOff: Set<String> = emptySet(),
    val globalTypeOff: Set<String> = emptySet(),
    val perInstrumentTypeOff: Set<String> = emptySet(),
) {
    // region Reads

    /**
     * Whether this instrument's suggestions are shown at all.
     *
     * @param instrument Chart.
     * @return False when hidden by the filter.
     */
    fun isInstrumentEnabled(instrument: Instrument): Boolean = instrument.wireId !in instrumentOff

    /**
     * Whether a type is enabled globally (ignoring per-instrument overrides).
     *
     * @param type Family.
     * @return Global toggle.
     */
    fun isGlobalEnabled(type: SuggestionCategoryType): Boolean = type.key !in globalTypeOff

    /**
     * Whether a type is enabled for an instrument-scoped category, falling back to
     * the global toggle for a mixed-instrument category.
     *
     * @param type Family.
     * @param instrument The category's instrument, or null when mixed.
     * @return Effective toggle.
     */
    fun isTypeEnabled(type: SuggestionCategoryType, instrument: Instrument?): Boolean {
        if (instrument == null) return isGlobalEnabled(type)
        if (perKey(instrument, type) in perInstrumentTypeOff) return false
        return type.key !in globalTypeOff
    }

    /** True once any toggle is off (gold filter button). */
    val isActive: Boolean get() = instrumentOff.isNotEmpty() || globalTypeOff.isNotEmpty() || perInstrumentTypeOff.isNotEmpty()

    /** True when every type is off, so nothing generated could ever show. */
    val allTypesOff: Boolean get() = SuggestionCategoryType.entries.none(::isGlobalEnabled)

    /**
     * Settings-visible charts intersected with this filter's instrument toggles.
     *
     * @param appVisible Charts enabled in Settings.
     * @return Charts that may surface suggestions.
     */
    fun effectiveInstruments(appVisible: Set<Instrument>): Set<Instrument> = appVisible.filterTo(LinkedHashSet(), ::isInstrumentEnabled)

    // endregion

    // region Mutations

    /**
     * Show or hide one instrument's suggestions.
     *
     * @param instrument Chart.
     * @param enabled New value.
     * @return Updated filter.
     */
    fun withInstrument(instrument: Instrument, enabled: Boolean): SuggestionFilterSettings =
        copy(instrumentOff = instrumentOff.toggle(instrument.wireId, enabled))

    /**
     * Toggle a type globally, cascading to every listed instrument's row.
     *
     * @param type Family.
     * @param enabled New value.
     * @param instruments Rows to cascade to (Settings-visible charts).
     * @return Updated filter.
     */
    fun withGlobalType(
        type: SuggestionCategoryType,
        enabled: Boolean,
        instruments: List<Instrument> = Instrument.entries,
    ): SuggestionFilterSettings {
        var per = perInstrumentTypeOff
        for (instrument in instruments) per = per.toggle(perKey(instrument, type), enabled)
        return copy(globalTypeOff = globalTypeOff.toggle(type.key, enabled), perInstrumentTypeOff = per)
    }

    /**
     * Toggle one instrument's row for a type. Turning a row on re-enables the
     * global switch; turning the last listed row off turns it off (web modal rule).
     *
     * @param type Family.
     * @param instrument Row.
     * @param enabled New value.
     * @param allInstruments Rows shown in that section.
     * @return Updated filter.
     */
    fun withPerInstrumentType(
        type: SuggestionCategoryType,
        instrument: Instrument,
        enabled: Boolean,
        allInstruments: List<Instrument> = Instrument.entries,
    ): SuggestionFilterSettings {
        val next = copy(perInstrumentTypeOff = perInstrumentTypeOff.toggle(perKey(instrument, type), enabled))
        return when {
            enabled -> next.copy(globalTypeOff = next.globalTypeOff - type.key)
            allInstruments.none { next.isTypeEnabled(type, it) } -> next.copy(globalTypeOff = next.globalTypeOff + type.key)
            else -> next
        }
    }

    // endregion

    // region Persistence

    /**
     * Encode for storage: `""` when untouched, else sorted-key JSON.
     *
     * @return Stored text.
     */
    fun encoded(): String {
        if (!isActive) return ""
        return JSON.encodeToString(serializer(), copy(
            instrumentOff = instrumentOff.toSortedSet(),
            globalTypeOff = globalTypeOff.toSortedSet(),
            perInstrumentTypeOff = perInstrumentTypeOff.toSortedSet(),
        ))
    }

    // endregion

    companion object {
        /** DataStore key (Apple `SuggestionFilterSettings.storageKey`). */
        const val STORAGE_KEY = "fst.suggestions.filter"

        /** Largest stored value accepted; anything bigger is treated as corrupt. */
        const val MAX_STORED_LENGTH = 16_384

        /** Every instrument and type enabled. */
        val DEFAULTS = SuggestionFilterSettings()

        private val JSON = Json { ignoreUnknownKeys = true }

        private fun perKey(instrument: Instrument, type: SuggestionCategoryType) = "${instrument.wireId}|${type.key}"

        private fun Set<String>.toggle(key: String, enabled: Boolean): Set<String> = if (enabled) this - key else this + key

        /**
         * Decode stored text, falling back to defaults for empty, oversized or corrupt data.
         *
         * @param raw Stored text or null.
         * @return A valid filter.
         */
        fun decodeSaved(raw: String?): SuggestionFilterSettings {
            if (raw.isNullOrEmpty() || raw.length > MAX_STORED_LENGTH) return DEFAULTS
            return runCatching { JSON.decodeFromString(serializer(), raw) }.getOrDefault(DEFAULTS)
        }
    }
}

// endregion

// region Category filtering

/**
 * Applies a filter and the current instrument visibility to generated categories
 * (web `shouldShowCategory` + `filterCategoryForInstruments` +
 * `shouldShowCategoryType` + `filterCategoryForInstrumentTypes` in one pass).
 */
object SuggestionCategoryFilter {
    /**
     * Filter one category: drop it, or trim a mixed category's hidden-instrument rows.
     *
     * @param category Generated category.
     * @param effectiveInstruments Settings-visible charts ∩ the filter's instrument toggles.
     * @param filter Saved filter.
     * @return The category (possibly trimmed), or null when hidden.
     */
    fun visible(
        category: SuggestionCategory,
        effectiveInstruments: Set<Instrument>,
        filter: SuggestionFilterSettings,
    ): SuggestionCategory? {
        if (!filter.isTypeEnabled(category.type, category.instrument)) return null
        category.instrument?.let { return if (it in effectiveInstruments) category else null }
        val kept = category.songs.filter { item ->
            val instrument = item.instrument ?: return@filter true
            instrument in effectiveInstruments && filter.isTypeEnabled(category.type, instrument)
        }
        if (kept.isEmpty()) return null
        return if (kept.size == category.songs.size) category else category.copy(songs = kept)
    }
}

// endregion
