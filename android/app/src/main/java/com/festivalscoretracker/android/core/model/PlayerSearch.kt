package com.festivalscoretracker.android.core.model

import kotlinx.serialization.Serializable

// region Player search

/** One `/api/account/search` result. */
@Serializable
data class PlayerSearchResult(val accountId: String, val displayName: String)

/** `/api/account/search` envelope. */
@Serializable
data class PlayerSearchResponse(val results: List<PlayerSearchResult> = emptyList())

/** Validation shared by account-scoped URLs and search queries. */
object ProfileSearchText {
    private val accountIdPattern = Regex("^[0-9a-fA-F]{32}$")

    /** Minimum trimmed query length the service accepts. */
    const val MIN_QUERY = 2

    /** Maximum query length the service accepts. */
    const val MAX_QUERY = 200

    /**
     * Whether a string is a well-formed Epic account ID (32 hex digits).
     *
     * @param value Candidate ID.
     * @return True for a valid ID.
     */
    fun isValidAccountId(value: String): Boolean = accountIdPattern.matches(value)

    /**
     * Whether a query may be sent: 2–200 characters, already trimmed, with no
     * control or bidirectional-override characters.
     *
     * @param query Candidate search text.
     * @return True when the search GET may be built.
     */
    fun isValidQuery(query: String): Boolean =
        query.length in MIN_QUERY..MAX_QUERY && query == query.trim() && query.none(::isUnsafe)

    private fun isUnsafe(char: Char): Boolean =
        char.isISOControl() || char in '‪'..'‮' || char in '⁦'..'⁩'
}

/**
 * The persisted selected player.
 *
 * @property accountId Validated Epic account ID.
 * @property displayName Name shown in the shell.
 */
@Serializable
data class SelectedPlayer(val accountId: String, val displayName: String) {
    /** One or two uppercase initials for the avatar. */
    val initials: String
        get() {
            val words = displayName.trim().split(Regex("[\\s._-]+")).filter { it.isNotEmpty() }
            val letters = when {
                words.isEmpty() -> "?"
                words.size == 1 -> words[0].take(1)
                else -> words[0].take(1) + words[1].take(1)
            }
            return letters.uppercase()
        }

    companion object {
        /**
         * Build a validated identity.
         *
         * @param accountId Candidate account ID.
         * @param displayName Candidate display name.
         * @return The identity, or null when either field is invalid.
         */
        fun validated(accountId: String, displayName: String): SelectedPlayer? =
            if (ProfileSearchText.isValidAccountId(accountId) && displayName.isNotBlank()) {
                SelectedPlayer(accountId, displayName.trim())
            } else {
                null
            }
    }
}

// endregion
