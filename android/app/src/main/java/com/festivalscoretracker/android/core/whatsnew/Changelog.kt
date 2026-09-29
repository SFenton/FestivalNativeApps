package com.festivalscoretracker.android.core.whatsnew

// region Model

/**
 * One titled group of changelog bullets (web `ChangelogSection`, `FortniteFestivalWeb/src/changelog.ts`).
 *
 * @property title Heading exactly as the web data spells it (upper case; the web upper-cases in CSS).
 * @property items Bullet sentences, in web order.
 */
data class ChangelogSection(val title: String, val items: List<String>) {
    /** Native Title Case heading ("SONG DETAILS" → "Song Details"). */
    val displayTitle: String get() = Changelog.titleCase(title)
}

/**
 * One release's worth of changelog sections (web `ChangelogEntry`).
 *
 * @property sections Sections in web order.
 */
data class ChangelogEntry(val sections: List<ChangelogSection>)

// endregion

// region Catalog

/**
 * The "What's New" changelog, ported verbatim from the web so its content hash matches the
 * web's `changelogHash()` (`FortniteFestivalWeb/src/changelogHash.ts`); Apple `Changelog`,
 * Windows `Changelog`.
 *
 * The web shows the card whenever the stored hash differs from the current one; natives use
 * the same rule ([ChangelogSeenStore]). Keep [entries] byte-identical to the web data and
 * update [WEB_HASH] in the same commit; `ChangelogTest` fails if the two drift.
 */
object Changelog {
    /** Web release the entries were copied from (`package.json` version at capture time). */
    const val WEB_VERSION = "0.1.133"

    /** The web's precomputed `CURRENT_CHANGELOG_HASH` for [entries]. */
    const val WEB_HASH = "-6p8bh3"

    /** Changelog entries exactly as the web ships them. */
    val entries: List<ChangelogEntry> = listOf(
        ChangelogEntry(
            listOf(
                ChangelogSection(
                    "ITEM SHOP",
                    listOf(
                        "Newly released songs in the Item Shop have a gold pulse on Songs Page and Song Details.",
                        "Songs in the Item Shop that aren't leaving tomorrow now have a green pulse, to match " +
                            "the gold/green/red styles of the instrument chips on Songs Page.",
                    ),
                ),
                ChangelogSection(
                    "MOBILE",
                    listOf(
                        "FAB buttons and other dock buttons now animate in for a more visually pleasing experience.",
                        "Fixed a bug in search modal where dismissing the keyboard after results show did not " +
                            "expand results view appropriately.",
                    ),
                ),
                ChangelogSection(
                    "SONG DETAILS",
                    listOf("Fixed a bug where leaderboard ranks did not reflect the actual Epic leaderboard value in some cases."),
                ),
                ChangelogSection(
                    "NOTIFICATIONS",
                    listOf(
                        "Fixed a bug where notification alerts would reset when you re-open the web browser.",
                        "Added support for switching profiles/bands and returning to a different profile/band " +
                            "and seeing the appropriate amount of unread notifications, instead of all of them.",
                    ),
                ),
                ChangelogSection(
                    "RIVALS",
                    listOf(
                        "Improved performance when viewing a Rival for the first time.",
                        "Improved availability of Rivals during scrape.",
                    ),
                ),
                ChangelogSection(
                    "LEADERBOARDS",
                    listOf(
                        "Changed to instrument icons on combo leaderboards instead of \"Lead + ...\" text.",
                        "Updated FAB dock on mobile to match other pages.",
                    ),
                ),
            ),
        ),
    )

    /** Content hash of the current entries; drives "show once per changelog". */
    val currentHash: String by lazy { hash(entries) }

    // region Display

    /**
     * Entries as natives display them: the deprecated Manual feature is never advertised, so a
     * section titled Manual or a bullet naming it is dropped, and empty sections removed.
     *
     * @param source Web-identical entries.
     * @return Entries safe to render natively.
     */
    fun displayEntries(source: List<ChangelogEntry> = entries): List<ChangelogEntry> = source.mapNotNull { entry ->
        val sections = entry.sections.mapNotNull { section ->
            if (mentionsManual(section.title)) return@mapNotNull null
            section.items.filterNot(::mentionsManual).takeIf { it.isNotEmpty() }?.let { ChangelogSection(section.title, it) }
        }
        sections.takeIf { it.isNotEmpty() }?.let(::ChangelogEntry)
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

    // region Hash (web-compatible)

    /**
     * The web's `calculateChangelogHash`: a 32-bit `((h << 5) - h) + code` over the UTF-16 code
     * units of `JSON.stringify(entries)`, printed in base 36 with a sign.
     *
     * @param source Entries to hash.
     * @return Hash identical to the web's for identical data.
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
