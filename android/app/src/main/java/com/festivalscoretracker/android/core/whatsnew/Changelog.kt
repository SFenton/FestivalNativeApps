package com.festivalscoretracker.android.core.whatsnew

import java.io.InputStream
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

// region Model

/**
 * One titled group of changelog bullets: a released app version and its notes.
 *
 * @property title Heading, e.g. "Version 2610.01".
 * @property items Bullet sentences, in release-note order.
 */
data class ChangelogSection(val title: String, val items: List<String>) {
    /** Native Title Case heading ("SONG DETAILS" → "Song Details"). */
    val displayTitle: String get() = Changelog.titleCase(title)
}

/**
 * One app version's worth of changelog sections.
 *
 * @property sections Sections in display order.
 * @property version App version (`YYMM.NN`) the notes belong to; null for ad-hoc entries.
 * @property released Whether that version was already released when this build was made (the built
 *   version itself is listed unreleased).
 */
data class ChangelogEntry(val sections: List<ChangelogSection>, val version: String? = null, val released: Boolean = true)

// endregion

// region Catalog

/**
 * The "What's New" changelog: one section per released app version, newest first (Apple `Changelog`,
 * Windows `Changelog`).
 *
 * Release builds generate the `WhatsNew.json` Java resource (`src/main/resources`) with
 * `tools/release/versioning.py whats-new` from `Release-Note` commit trailers and the store's released
 * versions, so intermediate test builds fold into the next released version. The checked-in file is a
 * development placeholder. The sheet shows whenever the content hash differs from the dismissed one
 * ([ChangelogSeenStore]).
 */
object Changelog {
    /** Classpath location of the generated changelog. */
    const val RESOURCE = "/WhatsNew.json"

    /** Most entries kept from the document (the generator writes at most 10). */
    internal const val MAX_ENTRIES = 20

    /** Most bullets kept per entry. */
    internal const val MAX_ITEMS = 40

    /** Longest bullet kept, in characters. */
    internal const val MAX_ITEM_LENGTH = 600

    /** Entries bundled with the app (empty when the resource is missing or invalid). */
    val entries: List<ChangelogEntry> by lazy { load() }

    /** Content hash of the bundled entries; drives "show once per changelog". */
    val currentHash: String by lazy { hash(entries) }

    /** Hash of an empty changelog; the store never shows the sheet for it. */
    val emptyHash: String by lazy { hash(emptyList()) }

    /**
     * Read the bundled document.
     *
     * @param open Opens the resource (null when absent).
     * @return Decoded entries, or an empty list when absent or invalid.
     */
    fun load(open: () -> InputStream? = { Changelog::class.java.getResourceAsStream(RESOURCE) }): List<ChangelogEntry> =
        runCatching { open()?.use { decode(it.readBytes().decodeToString()) } }.getOrNull().orEmpty()

    /**
     * Decode a `versioning.py whats-new` document (`{schema, platform, version, baseline, entries: [{version,
     * released, items}]}`).
     *
     * @param text JSON document.
     * @return One entry per version with a single "Version <v>" section, bounded in size; versions without
     *   notes are skipped.
     * @throws IllegalArgumentException Malformed document.
     */
    fun decode(text: String): List<ChangelogEntry> {
        val root = Json.parseToJsonElement(text) as? JsonObject ?: throw IllegalArgumentException("not an object")
        val list = root["entries"] as? JsonArray ?: throw IllegalArgumentException("missing entries")
        return list.take(MAX_ENTRIES).mapNotNull { element ->
            val entry = element as? JsonObject ?: throw IllegalArgumentException("entry is not an object")
            val version = (entry["version"] as? JsonPrimitive)?.takeIf { it.isString }?.content?.take(32)
                ?: throw IllegalArgumentException("entry without version")
            val released = (entry["released"] as? JsonPrimitive)?.booleanOrNull ?: true
            val items = (entry["items"] as? JsonArray).orEmpty()
                .mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content?.trim()?.take(MAX_ITEM_LENGTH) }
                .filter { it.isNotEmpty() }
                .take(MAX_ITEMS)
            if (version.isEmpty() || items.isEmpty()) null
            else ChangelogEntry(listOf(ChangelogSection("Version $version", items)), version, released)
        }
    }

    // region Display

    /**
     * Entries as natives display them: the deprecated Manual feature is never advertised, so a
     * section titled Manual or a bullet naming it is dropped, and empty sections removed.
     *
     * @param source Bundled entries.
     * @return Entries safe to render natively.
     */
    fun displayEntries(source: List<ChangelogEntry> = entries): List<ChangelogEntry> = source.mapNotNull { entry ->
        val sections = entry.sections.mapNotNull { section ->
            if (mentionsManual(section.title)) return@mapNotNull null
            section.items.filterNot(::mentionsManual).takeIf { it.isNotEmpty() }?.let { ChangelogSection(section.title, it) }
        }
        sections.takeIf { it.isNotEmpty() }?.let { entry.copy(sections = it) }
    }

    /**
     * Whether text refers to the deprecated in-app Manual.
     *
     * @param text Heading or bullet.
     * @return True when "manual" appears as a whole word, any case.
     */
    internal fun mentionsManual(text: String): Boolean =
        text.lowercase().split(Regex("[^\\p{L}]+")).contains("manual")

    /** Words kept lower case inside a Title Case heading (never the first word). */
    private val minorWords = setOf("a", "an", "and", "as", "at", "by", "for", "in", "of", "on", "or", "the", "to", "vs")

    /**
     * Convert a heading to Title Case.
     *
     * @param text Heading in any case.
     * @return Title Case heading with minor words lower-cased after the first word.
     */
    fun titleCase(text: String): String =
        text.lowercase().split(' ').filter { it.isNotEmpty() }.mapIndexed { index, word ->
            if (index > 0 && word in minorWords) word else word.replaceFirstChar { it.uppercaseChar() }
        }.joinToString(" ")

    // endregion

    // region Hash

    /**
     * Content hash in the web's `calculateChangelogHash` form: a 32-bit `((h << 5) - h) + code` over the
     * UTF-16 code units of `JSON.stringify(entries)`'s section shape, printed in base 36 with a sign. Section
     * titles carry the version, so a newly released version always changes it.
     *
     * @param source Entries to hash.
     * @return Short hash string.
     */
    fun hash(source: List<ChangelogEntry>): String {
        var value = 0
        for (unit in canonicalJson(source)) value = (value shl 5) - value + unit.code
        return Integer.toString(value, 36)
    }

    /**
     * Reproduce `JSON.stringify` for the entry array (no whitespace, key order
     * `sections` → `title`, `items`).
     *
     * @param source Entries to serialize.
     * @return Compact JSON text.
     */
    internal fun canonicalJson(source: List<ChangelogEntry>): String = source.joinToString(",", "[", "]") { entry ->
        entry.sections.joinToString(",", "{\"sections\":[", "]}") { section ->
            "{\"title\":${jsonString(section.title)},\"items\":${section.items.joinToString(",", "[", "]", transform = ::jsonString)}}"
        }
    }

    /**
     * Quote a string the way `JSON.stringify` does (escapes `"`, `\` and control characters;
     * leaves other Unicode as-is).
     *
     * @param text Raw string.
     * @return Quoted JSON string literal.
     */
    internal fun jsonString(text: String): String = buildString {
        append('"')
        for (char in text) {
            when (char) {
                '"' -> append("\\\"")
                '\\' -> append("\\\\")
                '\n' -> append("\\n")
                '\r' -> append("\\r")
                '\t' -> append("\\t")
                '\b' -> append("\\b")
                '\u000C' -> append("\\f")
                else -> if (char.code < 0x20) append("\\u%04x".format(char.code)) else append(char)
            }
        }
        append('"')
    }

    // endregion
}

// endregion
