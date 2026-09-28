package com.festivalscoretracker.android.core.search

import com.festivalscoretracker.android.core.model.PlayerSearchResult
import com.festivalscoretracker.android.core.model.ProfileSearchText
import com.festivalscoretracker.android.core.model.Song
import com.festivalscoretracker.android.core.nav.AppRoute
import com.festivalscoretracker.android.core.nav.BandRankingsRoute
import com.festivalscoretracker.android.core.nav.FestivalSection
import com.festivalscoretracker.android.core.nav.PlayerRoute
import com.festivalscoretracker.android.core.nav.SongDetailRoute
import com.festivalscoretracker.android.core.songs.SongSearch

// region Scope

/**
 * Global search scope (web `SearchTarget` order). [All] is the web's no-chip state.
 *
 * @property title Chip label.
 */
enum class SearchScope(val title: String) {
    /** Every live scope (Songs → Players). */
    All("All"),

    /** Songs from the loaded catalogue. */
    Songs("Songs"),

    /** Players from `GET /api/account/search`. */
    Players("Players"),

    /** Bands: shown but blocked (the service's band search GET can write). */
    Bands("Bands");

    /** Lowercase token used in test tags and saved state. */
    val token: String get() = name.lowercase()

    /**
     * Toggle this chip (web `aria-pressed` chips): tapping the selected chip returns to [All].
     *
     * @param current Scope selected now.
     * @return The new scope.
     */
    fun toggledFrom(current: SearchScope): SearchScope = if (current == this) All else this

    companion object {
        /** Chips in display order (no chip for [All]). */
        val chips: List<SearchScope> = listOf(Songs, Players, Bands)

        /**
         * Parse a saved token.
         *
         * @param token Token in any case.
         * @return The scope, or [All] for unknown/missing values.
         */
        fun parse(token: String?): SearchScope = entries.firstOrNull { it.token.equals(token, ignoreCase = true) } ?: All
    }
}

// endregion

// region Results

/** Where opening a result goes. */
sealed interface SearchDestination {
    /**
     * Push on the current section's stack (the user's place is kept for Back).
     *
     * @property route Destination.
     */
    data class Push(val route: AppRoute) : SearchDestination

    /**
     * Switch to a root section (the selected player opens Statistics).
     *
     * @property section Section.
     */
    data class Section(val section: FestivalSection) : SearchDestination
}

/**
 * One song result (catalogue projection; art is decorative).
 *
 * @property songId Song.
 * @property title Title.
 * @property artist Artist.
 * @property albumArt Raw album-art reference.
 */
data class GlobalSongResult(val songId: String, val title: String, val artist: String, val albumArt: String?) {
    /** Destination: Song Detail. */
    val destination: SearchDestination get() = SearchDestination.Push(SongDetailRoute(songId))

    /** Spoken name ("Title by Artist"). */
    val accessibleName: String get() = "$title by $artist"
}

/**
 * One player result.
 *
 * @property accountId Account.
 * @property displayName Display name.
 * @property isSelected Whether this is the selected player (opens Statistics).
 */
data class GlobalPlayerResult(val accountId: String, val displayName: String, val isSelected: Boolean) {
    /** The selected player → Statistics; anyone else → their profile (viewing, not selecting). */
    val destination: SearchDestination
        get() = if (isSelected) {
            SearchDestination.Section(FestivalSection.Statistics)
        } else {
            SearchDestination.Push(PlayerRoute(accountId, displayName))
        }

    /** Secondary line. */
    val subtitle: String get() = if (isSelected) "Selected player · Statistics" else "Player"

    /** Spoken name. */
    val accessibleName: String get() = if (isSelected) "$displayName, selected player, opens Statistics" else displayName
}

/** Pure global-search rules: limits, song matching, routing and announcements (global-search spec). */
object GlobalSearchResults {
    /** Shortest searchable (trimmed) query. */
    const val MIN_QUERY = 2

    /** Songs shown. */
    const val SONG_LIMIT = 20

    /** Players requested and shown. */
    const val PLAYER_LIMIT = 10

    /** Keystroke debounce (web `DEBOUNCE_MS`). */
    const val DEBOUNCE_MS = 250L

    /** Field placeholder; only live scopes are named (web `search.placeholders.songsPlayers`). */
    const val PLACEHOLDER = "Search songs or players"

    /** Field accessible name. */
    const val FIELD_NAME = "Search songs and players"

    /** Short-query hint (web `search.enterQuery`). */
    const val ENTER_QUERY_HINT = "Enter at least two characters to search."

    /** All-scope empty text. */
    const val NO_RESULTS = "No results found."

    /** Songs empty text. */
    const val NO_SONGS = "No songs found."

    /** Players empty text (an empty envelope may be a server timeout, so Retry is offered). */
    const val NO_PLAYERS = "No players found."

    /** Catalogue failure text in the Songs section. */
    const val SONGS_FAILED = "Search failed. Try again."

    /** Players failure fallback title. */
    const val PLAYERS_UNAVAILABLE = "Player search unavailable"

    /** Bands explanation (global-search spec, "Band scope (blocked)"). */
    const val BANDS_UNAVAILABLE =
        "Band search isn't available in the app yet. The service's band search can change stored band data, so the app " +
            "won't call it until a read-only version exists. Browse bands in Leaderboards → Band Rankings, or from a player's Bands."

    /** Band Rankings destination offered by the Bands explanation. */
    val bandRankings: AppRoute = BandRankingsRoute("Band_Duets")

    /**
     * Trimmed query.
     *
     * @param query User text.
     * @return Trimmed text.
     */
    fun normalize(query: String?): String = query.orEmpty().trim()

    /**
     * Whether the trimmed query is long enough to search.
     *
     * @param query User text.
     * @return True at two or more characters.
     */
    fun isSearchable(query: String?): Boolean = normalize(query).length >= MIN_QUERY

    /**
     * Whether the account search can be asked (2–200 characters, no control or bidi characters).
     *
     * @param query User text.
     * @return True when the request is valid.
     */
    fun canSearchPlayers(query: String?): Boolean = ProfileSearchText.isValidQuery(normalize(query))

    /**
     * Local catalogue match in catalogue order (web `songMatchesSearch`).
     *
     * @param songs Catalogue.
     * @param query User text.
     * @param limit Maximum rows.
     * @return Matches; empty for a short query.
     */
    fun matchSongs(songs: List<Song>, query: String?, limit: Int = SONG_LIMIT): List<GlobalSongResult> {
        val text = normalize(query)
        if (text.length < MIN_QUERY) return emptyList()
        return songs.asSequence()
            .filter { SongSearch.matches(it, text) }
            .take(limit)
            .map { GlobalSongResult(it.songId, it.title, it.artist, it.albumArt) }
            .toList()
    }

    /**
     * Project account-search rows, marking the selected player.
     *
     * @param results Validated rows.
     * @param selectedAccountId Selected player, if any.
     * @return At most [PLAYER_LIMIT] rows.
     */
    fun players(results: List<PlayerSearchResult>, selectedAccountId: String?): List<GlobalPlayerResult> =
        results.take(PLAYER_LIMIT).map {
            GlobalPlayerResult(it.accountId, it.displayName, it.accountId.equals(selectedAccountId, ignoreCase = true))
        }

    /**
     * Polite result-count announcement ("3 songs, 10 players").
     *
     * @param songs Song count, or null when the catalogue failed.
     * @param players Player count, or null when the account search failed.
     * @return Announcement text.
     */
    fun announcement(songs: Int?, players: Int?): String {
        if (songs == 0 && players == 0) return NO_RESULTS
        val songText = songs?.let { count(it, "song", "songs") } ?: "song search failed"
        val playerText = players?.let { count(it, "player", "players") } ?: "player search failed"
        return "$songText, $playerText"
    }

    private fun count(value: Int, one: String, many: String): String = "$value ${if (value == 1) one else many}"
}

// endregion

// region Layout

/** How the search surface is presented for the current window. */
enum class SearchPresentation {
    /** Compact (< 600 dp): action → `ExpandedFullScreenSearchBar`. */
    FullScreen,

    /**
     * Medium and wider (≥ 600 dp): action → `ExpandedDockedSearchBar` under the top bar at the end
     * edge. (No persistent search field: operator decision 2026-09-28, it read as a website.)
     */
    Docked,
}

/**
 * Integer rectangle in window pixels (Compose-free so it can be unit-tested).
 *
 * @property left Left edge.
 * @property top Top edge.
 * @property right Right edge (exclusive).
 * @property bottom Bottom edge (exclusive).
 */
data class PxRect(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    /** Width. */
    val width: Int get() = right - left

    /** Height. */
    val height: Int get() = bottom - top
}

/**
 * Where the expanded search surface sits.
 *
 * @property anchor Collapsed bounds the expanded bar grows from (the docked panel's top-left and width).
 * @property maxPanelHeight Maximum docked panel height, or null for Material's default (2/3 of the window).
 */
data class SearchAnchor(val anchor: PxRect, val maxPanelHeight: Int?)

/**
 * Pure window-size rules for global search (`.agents/controls/global-search/android.md`):
 * never device names or product checks.
 */
object GlobalSearchLayout {
    /** Material compact/medium boundary. */
    const val MEDIUM_WIDTH_DP = 600

    /** Widest docked panel. */
    const val MAX_PANEL_WIDTH_DP = 720

    /** Collapsed bar / input field height. */
    const val FIELD_HEIGHT_DP = 56

    /** Gap kept between the panel and a hinge or the window edge. */
    const val EDGE_GAP_DP = 8

    /**
     * Presentation for a window width.
     *
     * @param windowWidthDp Window width in dp.
     * @return Full screen on compact windows, else docked from the action.
     */
    fun presentation(windowWidthDp: Int): SearchPresentation =
        if (windowWidthDp < MEDIUM_WIDTH_DP) SearchPresentation.FullScreen else SearchPresentation.Docked

    /**
     * Anchor for the expanded surface.
     *
     * Full screen grows from the requester (the action icon), at the field's 56 dp height:
     * Material measures the expanded input field at the collapsed height. Docked opens under the top
     * bar, end-aligned to the requester, at most 720 dp wide and never across a separating
     * vertical hinge (clamped to the side that holds the requester). A separating horizontal (tabletop) hinge below the anchor caps the panel
     * height so no results sit under the fold.
     *
     * @param presentation Current presentation.
     * @param requester Bounds of the action or bar that asked (window px).
     * @param windowWidth Window width in px.
     * @param windowHeight Window height in px.
     * @param density Pixels per dp.
     * @param verticalHinge Separating vertical hinge bounds, if any.
     * @param horizontalHinge Separating horizontal hinge bounds, if any.
     * @return Anchor and optional height cap.
     */
    fun anchor(
        presentation: SearchPresentation,
        requester: PxRect,
        windowWidth: Int,
        windowHeight: Int,
        density: Float,
        verticalHinge: PxRect? = null,
        horizontalHinge: PxRect? = null,
    ): SearchAnchor {
        fun px(dp: Int) = (dp * density).toInt()
        val gap = px(EDGE_GAP_DP)
        val fieldHeight = px(FIELD_HEIGHT_DP)
        val anchor = when (presentation) {
            SearchPresentation.FullScreen -> {
                val top = ((requester.top + requester.bottom - fieldHeight) / 2).coerceAtLeast(0)
                PxRect(requester.left, top, requester.right, top + fieldHeight)
            }
            SearchPresentation.Docked -> {
                // The pane holding the requester: the whole window, or one side of a vertical hinge.
                val center = (requester.left + requester.right) / 2
                val (paneLeft, paneRight) = when {
                    verticalHinge == null -> 0 to windowWidth
                    center < verticalHinge.left -> 0 to verticalHinge.left
                    else -> verticalHinge.right to windowWidth
                }
                val maxWidth = (paneRight - paneLeft - 2 * gap).coerceAtLeast(0)
                val width = px(MAX_PANEL_WIDTH_DP).coerceAtMost(maxWidth)
                val right = requester.right.coerceIn(paneLeft + gap + width, paneRight - gap)
                val top = (requester.top + requester.bottom - fieldHeight) / 2
                PxRect(right - width, top.coerceAtLeast(0), right, top.coerceAtLeast(0) + fieldHeight)
            }
        }
        val cap = horizontalHinge
            ?.takeIf { presentation != SearchPresentation.FullScreen && it.top > anchor.bottom }
            ?.let { it.top - anchor.top - gap }
        return SearchAnchor(anchor, cap ?: if (presentation == SearchPresentation.FullScreen) null else windowHeight * 2 / 3)
    }
}

// endregion

// region Keyboard

/** App-level keyboard shortcuts (global-search android.md "Keyboard"). */
enum class ShellShortcut {
    /** Ctrl+K or the Search key: open global search and focus the field. */
    OpenSearch,

    /** Ctrl+F: page-local find where the page has one, otherwise global search. */
    FindInPage,
}

/** Maps raw key events to [ShellShortcut]s (Android key codes, kept as plain ints). */
object ShellShortcuts {
    /** `KeyEvent.KEYCODE_F`. */
    const val KEYCODE_F = 34

    /** `KeyEvent.KEYCODE_K`. */
    const val KEYCODE_K = 39

    /** `KeyEvent.KEYCODE_SEARCH`. */
    const val KEYCODE_SEARCH = 84

    /**
     * Resolve a key-down event.
     *
     * @param keyCode Android key code.
     * @param ctrl Ctrl held.
     * @param alt Alt held.
     * @param shift Shift held.
     * @param meta Meta held.
     * @return The shortcut, or null when the event isn't one.
     */
    fun resolve(keyCode: Int, ctrl: Boolean, alt: Boolean = false, shift: Boolean = false, meta: Boolean = false): ShellShortcut? {
        if (keyCode == KEYCODE_SEARCH && !ctrl && !alt && !meta) return ShellShortcut.OpenSearch
        if (!ctrl || alt || shift || meta) return null
        return when (keyCode) {
            KEYCODE_K -> ShellShortcut.OpenSearch
            KEYCODE_F -> ShellShortcut.FindInPage
            else -> null
        }
    }
}

// endregion
