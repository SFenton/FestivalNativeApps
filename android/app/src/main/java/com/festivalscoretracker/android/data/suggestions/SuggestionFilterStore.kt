package com.festivalscoretracker.android.data.suggestions

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.stringPreferencesKey
import com.festivalscoretracker.android.core.suggestions.SuggestionFilterSettings
import java.io.IOException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map

// region Filter store

/**
 * Persists the Suggestions filter under its own key in the shared settings
 * DataStore (Apple `@AppStorage("fst.suggestions.filter")`). An untouched filter
 * removes the key; corrupt or oversized values read as defaults.
 *
 * @param store Shared preferences store.
 */
class SuggestionFilterStore(private val store: DataStore<Preferences>) {
    /** Saved filter; defaults when absent, unreadable or corrupt. */
    val filter: Flow<SuggestionFilterSettings> = store.data
        .catch { error -> if (error is IOException) emit(emptyPreferences()) else throw error }
        .map { SuggestionFilterSettings.decodeSaved(it[KEY]) }
        .distinctUntilChanged()

    /**
     * Save a filter (removing the key when it is the default).
     *
     * @param filter New filter.
     */
    suspend fun save(filter: SuggestionFilterSettings) {
        val encoded = filter.encoded()
        store.edit { prefs -> if (encoded.isEmpty()) prefs.remove(KEY) else prefs[KEY] = encoded }
    }

    private companion object {
        val KEY = stringPreferencesKey(SuggestionFilterSettings.STORAGE_KEY)
    }
}

// endregion
