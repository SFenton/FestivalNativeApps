package com.festivalscoretracker.android.core.settings

// region Blob store

/** One persisted string value (a DataStore key in the app, memory in tests). */
interface BlobStore {
    /**
     * Read the stored value.
     *
     * @return Value, or null when absent.
     */
    suspend fun read(): String?

    /**
     * Replace or remove the stored value.
     *
     * @param value New value, or null to remove it.
     */
    suspend fun write(value: String?)
}

/**
 * In-memory [BlobStore] for tests and previews.
 *
 * @property value Current value.
 */
class MemoryBlobStore(var value: String? = null) : BlobStore {
    override suspend fun read(): String? = value

    override suspend fun write(value: String?) {
        this.value = value
    }
}

// endregion
