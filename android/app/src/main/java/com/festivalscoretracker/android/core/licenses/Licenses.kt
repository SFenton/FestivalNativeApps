package com.festivalscoretracker.android.core.licenses

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// region Manifest

/**
 * One runtime dependency from `tools/android/licenses.py` (the release runtime classpath).
 *
 * @property group Maven group.
 * @property artifact Maven artifact.
 * @property version Resolved version.
 * @property name POM project name.
 * @property licenses SPDX IDs.
 * @property url HTTPS project URL, if any.
 */
@Serializable
data class LicensedPackage(
    val group: String,
    val artifact: String,
    val version: String,
    val name: String,
    val licenses: List<String>,
    val url: String? = null,
) {
    /** Stable ID / test-tag suffix. */
    val id: String get() = "$group:$artifact"

    /** Row subtitle: coordinates, version and license. */
    val subtitle: String get() = "Maven · $group:$artifact $version"
}

/**
 * The generated `assets/licenses.json`.
 *
 * @property version Manifest schema version.
 * @property source Gradle configuration the graph came from.
 * @property packages Dependencies.
 * @property texts SPDX ID → full license text.
 */
@Serializable
data class LicenseManifest(
    val version: Int = 1,
    val source: String = "",
    val packages: List<LicensedPackage> = emptyList(),
    val texts: Map<String, String> = emptyMap(),
) {
    /**
     * Full text for a package (every license it declares, separated by a rule).
     *
     * @param item Package.
     * @return License text.
     */
    fun text(item: LicensedPackage): String = item.licenses.mapNotNull(texts::get).joinToString("\n\n———\n\n")

    companion object {
        private val JSON = Json { ignoreUnknownKeys = true }

        /**
         * Parse and validate: rows whose license has no text or whose URL is
         * not HTTPS are repaired or dropped; malformed JSON is an empty manifest.
         * Rows sort by name, case-insensitively.
         *
         * @param raw Asset text.
         * @return Manifest.
         */
        fun parse(raw: String?): LicenseManifest {
            val manifest = raw?.let { runCatching { JSON.decodeFromString(serializer(), it) }.getOrNull() } ?: return LicenseManifest()
            val packages = manifest.packages
                .filter { item -> item.licenses.isNotEmpty() && item.licenses.all { it in manifest.texts } }
                .map { item -> if (item.url?.startsWith("https://") == true) item else item.copy(url = null) }
                .distinctBy { it.id }
                .sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.name })
            return manifest.copy(packages = packages)
        }
    }
}

// endregion
