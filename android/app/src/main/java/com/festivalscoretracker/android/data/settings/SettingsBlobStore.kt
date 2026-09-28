package com.festivalscoretracker.android.data.settings

import com.festivalscoretracker.android.core.settings.BlobStore
import com.festivalscoretracker.android.data.SettingsRepository

// region DataStore blob

/**
 * A [BlobStore] over one registered DataStore string key (first-run and
 * notification seen-state share the settings file, so Reset's registry sees them).
 *
 * @property repository Settings store.
 * @property key Registered key name.
 */
class SettingsBlobStore(private val repository: SettingsRepository, private val key: String) : BlobStore {
    override suspend fun read(): String? = repository.readBlob(key)

    override suspend fun write(value: String?) = repository.writeBlob(key, value)
}

// endregion
