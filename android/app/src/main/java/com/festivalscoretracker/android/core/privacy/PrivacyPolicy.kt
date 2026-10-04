package com.festivalscoretracker.android.core.privacy

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// region Model

/**
 * One block of policy body text.
 *
 * @property kind `paragraph` (uses [text]) or `bullets` (uses [items]).
 * @property text Paragraph text.
 * @property items Bullet items, in order.
 */
@Serializable
data class PrivacyPolicyBlock(
    val kind: String = "",
    val text: String = "",
    val items: List<String> = emptyList(),
) {
    /** Whether this is a bullet list. */
    val isBullets: Boolean get() = kind == BULLETS

    companion object {
        /** Wire `kind` of a paragraph. */
        const val PARAGRAPH = "paragraph"

        /** Wire `kind` of a bullet list. */
        const val BULLETS = "bullets"
    }
}

/**
 * One titled policy section.
 *
 * @property id Stable ID (test-tag suffix).
 * @property title Heading.
 * @property blocks Body.
 */
@Serializable
data class PrivacyPolicySection(
    val id: String = "",
    val title: String = "",
    val blocks: List<PrivacyPolicyBlock> = emptyList(),
)

/**
 * The bundled Privacy Policy: a byte-identical copy of the shared `contracts/privacy-policy.json`, so the
 * wording matches every other client (issue #98).
 *
 * @property schema Contract schema version.
 * @property title Modal title.
 * @property effectiveDate ISO date the policy took effect.
 * @property effectiveDateText Display form of [effectiveDate].
 * @property sections Sections in reading order.
 */
@Serializable
data class PrivacyPolicy(
    val schema: Int = 0,
    val title: String = "",
    val effectiveDate: String = "",
    val effectiveDateText: String = "",
    val sections: List<PrivacyPolicySection> = emptyList(),
) {
    /** Whether the policy decoded with no content to show. */
    val isEmpty: Boolean get() = sections.isEmpty()

    companion object {
        /** Asset path of the bundled copy. */
        const val ASSET = "privacy-policy.json"

        /** Title used when the asset cannot be read (never blank). */
        const val DEFAULT_TITLE = "Privacy Policy"

        /** Supported contract schema. */
        const val SCHEMA = 1

        private val JSON = Json { ignoreUnknownKeys = true }

        /**
         * Parse and validate the bundled policy: unknown block kinds, blank paragraphs, blank bullet items, and
         * sections without a title or any remaining block are dropped. Malformed JSON or an unsupported schema
         * yields an empty policy titled [DEFAULT_TITLE].
         *
         * @param raw Asset text, or `null` when it could not be read.
         * @return Policy.
         */
        fun parse(raw: String?): PrivacyPolicy {
            val decoded = raw?.let { runCatching { JSON.decodeFromString(serializer(), it) }.getOrNull() }
            if (decoded == null || decoded.schema != SCHEMA) return PrivacyPolicy(schema = SCHEMA, title = DEFAULT_TITLE)
            val sections = decoded.sections.mapNotNull { section ->
                val blocks = section.blocks.mapNotNull { block ->
                    when (block.kind) {
                        PrivacyPolicyBlock.PARAGRAPH -> block.takeIf { it.text.isNotBlank() }?.copy(items = emptyList())
                        PrivacyPolicyBlock.BULLETS -> block.items.filter { it.isNotBlank() }.takeIf { it.isNotEmpty() }
                            ?.let { PrivacyPolicyBlock(PrivacyPolicyBlock.BULLETS, items = it) }
                        else -> null
                    }
                }
                section.copy(blocks = blocks).takeIf { section.title.isNotBlank() && blocks.isNotEmpty() }
            }
            return decoded.copy(title = decoded.title.ifBlank { DEFAULT_TITLE }, sections = sections)
        }

        private val URL = Regex("""https://[^\s]+""")

        /**
         * HTTPS links in a line of policy text, so the UI can make them activatable. Trailing sentence
         * punctuation (`.`, `,`, `;`, `:`, `)`) is not part of the link.
         *
         * @param text Paragraph or bullet text.
         * @return Character ranges of each link, in order.
         */
        fun linkRanges(text: String): List<IntRange> = URL.findAll(text).mapNotNull { match ->
            val trimmed = match.value.trimEnd('.', ',', ';', ':', ')')
            (match.range.first until match.range.first + trimmed.length).takeIf { trimmed.length > "https://".length }
        }.toList()
    }
}

// endregion
