package com.festivalscoretracker.android.core.whatsnew

import java.io.InputStream
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull

// region Model

/**
 * One titled group of changelog bullets: a released app version and its notes.
 *
 * @property title Heading, e.g. "Version 2610.01.01".
 * @property items Bullet sentences, in release-note order.
 */
data class ChangelogSection(val title: String, val items: List<String>) {
    /** Native Title Case heading ("SONG DETAILS" → "Song Details"). */
    val displayTitle: String get() = Changelog.titleCase(title)
}

/**
 * One page-category group of notes, as `versioning.py groups_json` writes it (category prefix already
 * stripped, groups already in the web changelog's page order).
 *
 * @property category Page category ("Songs", "Item Shop", …), or null for uncategorized notes.
 * @property items Bullet sentences, word for word.
 */
data class ChangelogGroup(val category: String?, val items: List<String>) {
    /** Heading shown above the bullets: the category, or "Other" for uncategorized notes. */
    val displayTitle: String get() = category ?: OTHER

    companion object {
        /** Heading of uncategorized notes (TestFlight "What to Test" wording). */
        const val OTHER = "Other"
    }
}

/**
 * The tester notes of the unreleased built version (`testflight` block): every note since the store's
 * latest release, grouped like TestFlight "What to Test".
 *
 * @property release Newest released version the list compares with; null before the first release.
 * @property groups Category groups in display order.
 */
data class TesterNotes(val release: String?, val groups: List<ChangelogGroup>) {
    /** Block heading, matching TestFlight's "Changes since release X" / "Changes so far". */
    val title: String get() = release?.let { "Changes Since Release $it" } ?: "Changes So Far"
}

/**
 * One app version's worth of changelog sections.
 *
 * @property sections Sections in display order (one "Version X" section; drives the show-once hash).
 * @property version App version (`YYMM.DD.NN`) the notes belong to; null for ad-hoc entries.
 * @property released Whether that version was already released when this build was made (the built
 *   version itself is listed unreleased).
 * @property groups The same notes grouped by page category (`groups`); empty for documents without it.
 * @property tester Tester notes for the unreleased built version (`testflight`), or null.
 */
data class ChangelogEntry(
    val sections: List<ChangelogSection>,
    val version: String? = null,
    val released: Boolean = true,
    val groups: List<ChangelogGroup> = emptyList(),
    val tester: TesterNotes? = null,
)

/**
 * One headed block of the What's New list: a version (or the tester list) and its category groups.
 *
 * @property title Block heading ("Version 2610.02.01", "Changes Since Release 2610.01.03").
 * @property groups Non-empty groups in display order.
 */
data class WhatsNewBlock(val title: String, val groups: List<ChangelogGroup>) {
    /** Whether groups get category headings: only when at least one note has a category (TestFlight rule). */
    val headed: Boolean get() = groups.any { it.category != null }
}

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

    /** Most category groups kept per list (17 categories plus "Other", with headroom). */
    internal const val MAX_GROUPS = 24

    /** Longest category name kept. */
    internal const val MAX_CATEGORY_LENGTH = 32

    /**
     * Most bullets kept in the tester list. It holds every note since the latest release, which can exceed a
     * single version's [MAX_ITEMS]; TestFlight's own 4000-character text fits far fewer.
     */
    internal const val MAX_TESTER_ITEMS = 120

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
     * released, items, groups?, testflight?}]}`).
     *
     * `groups` (`[{category, items}]`) and `testflight.groups` are used as written: `versioning.py` owns the
     * categories, so the app never re-classifies notes. Without `groups`, the flat `items` (or
     * `testflight.vs_release`) become one uncategorized group.
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
            val items = strings(entry["items"]).take(MAX_ITEMS)
            if (version.isEmpty() || items.isEmpty()) return@mapNotNull null
            val groups = decodeGroups(entry["groups"], MAX_ITEMS).ifEmpty { listOf(ChangelogGroup(null, items)) }
            val tester = (entry["testflight"] as? JsonObject)?.let(::decodeTester)
            ChangelogEntry(listOf(ChangelogSection("Version $version", items)), version, released, groups, tester)
        }
    }

    /**
     * Bounded, trimmed, non-empty strings of a JSON array (non-strings are skipped).
     *
     * @param element JSON array, or anything else for none.
     * @return Strings of at most [MAX_ITEM_LENGTH] characters.
     */
    private fun strings(element: JsonElement?): List<String> = (element as? JsonArray).orEmpty()
        .mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content?.trim()?.take(MAX_ITEM_LENGTH) }
        .filter { it.isNotEmpty() }

    /**
     * Decode a `groups` array (`[{category: string | null, items: [string]}]`), keeping its order. Malformed
     * groups are skipped rather than failing the document.
     *
     * @param element JSON array, or anything else for none.
     * @param limit Most bullets kept across all groups.
     * @return Non-empty groups, bounded by [MAX_GROUPS] and [limit].
     */
    internal fun decodeGroups(element: JsonElement?, limit: Int): List<ChangelogGroup> {
        var budget = limit
        return (element as? JsonArray).orEmpty().asSequence()
            .mapNotNull { it as? JsonObject }
            .mapNotNull { group ->
                if (budget <= 0) return@mapNotNull null
                val category = (group["category"] as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()
                    ?.take(MAX_CATEGORY_LENGTH)?.takeIf { it.isNotEmpty() }
                val items = strings(group["items"]).take(budget)
                budget -= items.size
                items.takeIf { it.isNotEmpty() }?.let { ChangelogGroup(category, it) }
            }
            .take(MAX_GROUPS)
            .toList()
    }

    /**
     * Decode the `testflight` block (`{since, new, release, vs_release, groups}`).
     *
     * @param block The block.
     * @return Tester notes, or null when it lists nothing.
     */
    private fun decodeTester(block: JsonObject): TesterNotes? {
        val release = (block["release"] as? JsonPrimitive)?.takeIf { it.isString }?.content?.trim()?.take(32)?.takeIf { it.isNotEmpty() }
        val groups = decodeGroups(block["groups"], MAX_TESTER_ITEMS).ifEmpty {
            strings(block["vs_release"]).take(MAX_TESTER_ITEMS).takeIf { it.isNotEmpty() }?.let { listOf(ChangelogGroup(null, it)) }.orEmpty()
        }
        return groups.takeIf { it.isNotEmpty() }?.let { TesterNotes(release, it) }
    }

    // region Display

    /**
     * The What's New list for an install channel: one block per entry, newest first. Tester installs see the
     * built version's tester list (every note since the latest release, like TestFlight "What to Test") in
     * place of its release block; store installs never do. Manual mentions are dropped (see [displayEntries]).
     *
     * @param source Bundled entries.
     * @param channel How this copy was installed.
     * @return Non-empty blocks.
     */
    fun displayBlocks(source: List<ChangelogEntry> = entries, channel: InstallChannel): List<WhatsNewBlock> =
        source.mapNotNull { entry ->
            val tester = entry.tester?.takeIf { channel == InstallChannel.Tester }
            val title = tester?.title ?: entry.sections.firstOrNull()?.displayTitle ?: return@mapNotNull null
            if (tester == null && entry.sections.all { mentionsManual(it.title) }) return@mapNotNull null
            val groups = (tester?.groups ?: entry.groups.ifEmpty { entry.sections.map { ChangelogGroup(null, it.items) } })
                .mapNotNull { group -> group.items.filterNot(::mentionsManual).takeIf { it.isNotEmpty() }?.let { group.copy(items = it) } }
            groups.takeIf { it.isNotEmpty() }?.let { WhatsNewBlock(title, it) }
        }

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
