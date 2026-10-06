package com.festivalscoretracker.android.core.nav

import com.festivalscoretracker.android.core.model.Instrument
import com.festivalscoretracker.android.core.model.SelectedPlayer
import com.festivalscoretracker.android.core.rivals.RivalRoutes
import com.festivalscoretracker.android.core.search.SearchScope

// region Debug launch

/**
 * Parsed debug launch extras so `tools/android/fst_android.py` can open any page
 * directly, mirroring Apple's `DebugLaunchRoute` (`FST_DEBUG_*`). Only debug
 * builds (and the non-distributed `benchmark` build) honour it (`MainActivity` checks `BuildConfig.DEBUG_LAUNCH`).
 *
 * Route syntax (`FST_DEBUG_ROUTE`): `song:<songId-or-title>`,
 * `songLeaderboard:<songId>:<Instrument wire ID>[:<page>[:reveal]]`,
 * `playerHistory:<songId>:<Instrument wire ID>`, `player:<accountId>`,
 * `playerBands:<accountId>`, `leaderboards`, `fullRankings:<Instrument wire ID>[:<page>]`,
 * `bandRankings:<bandType>[:<page>]`, `shop`, `rivals`, `statistics`, `suggestions`,
 * `compete`, `bands`, `band:<bandId>`, `songBandLeaderboard:<songId>[:<bandType>[:<page>[:reveal]]]`, `licenses`, `allRivals:<scope>`,
 * `rivalDetail:<rivalId>[:<scope>]`, `rivalry:<rivalId>:<mode>[:<scope>]` (scope = `RivalScope.routeToken`).
 * A trailing `reveal` sets the board route's `navToPlayer`/`navToBand` (issue #307).
 *
 * @property section `FST_DEBUG_TAB`.
 * @property route Parsed `FST_DEBUG_ROUTE`, excluding song lookups.
 * @property songQuery `song:` argument, resolved by ID or title once the catalogue loads.
 * @property songInstrument `FST_DEBUG_INSTRUMENT=<wireId>`: the `song:` route's `?instrument=` focus.
 * @property opensDrawer `FST_DEBUG_DRAWER=1`.
 * @property opensProfileSheet `FST_DEBUG_SHEET=profile`.
 * @property profile `FST_DEBUG_PROFILE=<accountId>:<displayName>`, in memory only.
 * @property anonymous `FST_DEBUG_ANONYMOUS=1` ignores the stored profile for this launch.
 * @property forceFreeze `FST_DEBUG_FORCE_FREEZE=1` synthesizes one scrape freeze per API path.
 * @property stillBackground `FST_DEBUG_STILL_BACKGROUND=1` stops background motion for screenshots.
 * @property origin `FST_ORIGIN`, a loopback fixture origin.
 * @property searchQuery `FST_DEBUG_SEARCH=<text>` opens global search with that text.
 * @property searchScope `FST_DEBUG_SEARCH_SCOPE=songs|players|bands` selects a scope chip.
 * @property suggestionsSeed `FST_DEBUG_SUGGESTIONS_SEED`: pins the Suggestions mix seed (0–4294967295) for screenshots.
 * @property opensNotifications `FST_DEBUG_SHEET=notifications` opens the notifications sheet.
 * @property firstRun `FST_DEBUG_FIRST_RUN=off|on|force` (debug default off so automation is never blocked).
 * @property whatsNew `FST_DEBUG_WHATS_NEW=off|on|fresh|force` (debug default off, like [firstRun]).
 * @property distribution `FST_DEBUG_DISTRIBUTION=store|tester`: which What's New notes to show (default: by installer).
 */
data class DebugLaunch(
    val section: FestivalSection? = null,
    val route: AppRoute? = null,
    val songQuery: String? = null,
    val songInstrument: String? = null,
    val opensDrawer: Boolean = false,
    val opensProfileSheet: Boolean = false,
    val profile: SelectedPlayer? = null,
    val anonymous: Boolean = false,
    val forceFreeze: Boolean = false,
    val stillBackground: Boolean = false,
    val origin: String? = null,
    val searchQuery: String? = null,
    val searchScope: SearchScope? = null,
    val suggestionsSeed: Long? = null,
    val opensNotifications: Boolean = false,
    val firstRun: String? = null,
    val whatsNew: String? = null,
    val distribution: String? = null,
) {
    companion object {
        /** An empty launch (release builds, or no extras). */
        val NONE = DebugLaunch()

        /**
         * Parse launch extras.
         *
         * @param extras String extras by name.
         * @return Parsed launch; malformed values are ignored.
         */
        fun parse(extras: Map<String, String>): DebugLaunch {
            val profile = extras["FST_DEBUG_PROFILE"]?.split(":", limit = 2)
                ?.takeIf { it.size == 2 }
                ?.let { SelectedPlayer.validated(it[0], it[1]) }
            val rawRoute = extras["FST_DEBUG_ROUTE"]
            val parts = rawRoute?.split(":", limit = 2)
            val songQuery = if (parts?.firstOrNull() == "song") parts.getOrNull(1)?.takeIf { it.isNotBlank() } else null
            return DebugLaunch(
                section = FestivalSection.fromName(extras["FST_DEBUG_TAB"]),
                route = rawRoute?.let(::parseRoute),
                songQuery = songQuery,
                songInstrument = extras["FST_DEBUG_INSTRUMENT"]?.takeIf { it.isNotBlank() },
                opensDrawer = extras["FST_DEBUG_DRAWER"] == "1",
                opensProfileSheet = extras["FST_DEBUG_SHEET"] == "profile",
                profile = profile,
                anonymous = extras["FST_DEBUG_ANONYMOUS"] == "1",
                forceFreeze = extras["FST_DEBUG_FORCE_FREEZE"] == "1",
                stillBackground = extras["FST_DEBUG_STILL_BACKGROUND"] == "1",
                origin = extras["FST_ORIGIN"]?.takeIf { it.isNotBlank() },
                searchQuery = extras["FST_DEBUG_SEARCH"],
                searchScope = extras["FST_DEBUG_SEARCH_SCOPE"]?.let(SearchScope::parse)?.takeIf { it != SearchScope.All },
                suggestionsSeed = extras["FST_DEBUG_SUGGESTIONS_SEED"]?.toLongOrNull()?.takeIf { it in 0..0xFFFF_FFFFL },
                opensNotifications = extras["FST_DEBUG_SHEET"] == "notifications",
                firstRun = extras["FST_DEBUG_FIRST_RUN"],
                whatsNew = extras["FST_DEBUG_WHATS_NEW"],
                distribution = extras["FST_DEBUG_DISTRIBUTION"],
            )
        }

        /**
         * Parse one route token.
         *
         * @param raw `name[:argument]`.
         * @return A typed route, or null for song lookups and unknown/malformed input.
         */
        fun parseRoute(raw: String): AppRoute? {
            val parts = raw.split(":", limit = 2)
            val arg = parts.getOrNull(1)?.takeIf { it.isNotBlank() }
            return when (parts[0]) {
                "songLeaderboard" -> arg?.split(":")?.let { pieces ->
                    val instrument = Instrument.fromWireId(pieces.getOrNull(1)) ?: return null
                    SongLeaderboardRoute(
                        pieces[0],
                        instrument.wireId,
                        pieces.getOrNull(2)?.toIntOrNull()?.coerceAtLeast(1) ?: 1,
                        navToPlayer = pieces.getOrNull(3) == "reveal",
                    )
                }
                "playerHistory" -> arg?.split(":")?.let { pieces ->
                    val instrument = Instrument.fromWireId(pieces.getOrNull(1)) ?: return null
                    PlayerHistoryRoute(pieces[0], instrument.wireId)
                }
                "player" -> arg?.let { PlayerRoute(it) }
                "playerBands" -> arg?.let { PlayerBandsRoute(it) }
                "leaderboards" -> LeaderboardsRoute
                "fullRankings" -> arg?.split(":").let { pieces ->
                    FullRankingsRoute((Instrument.fromWireId(pieces?.getOrNull(0)) ?: Instrument.Lead).wireId, page = pieces?.getOrNull(1)?.toIntOrNull()?.coerceAtLeast(1) ?: 1)
                }
                "bandRankings" -> arg?.split(":").let { pieces ->
                    BandRankingsRoute(pieces?.getOrNull(0) ?: "Band_Duets", pieces?.getOrNull(1)?.toIntOrNull()?.coerceAtLeast(1) ?: 1)
                }
                "shop" -> ShopRoute
                "rivals" -> RivalsRoute
                "statistics" -> StatisticsRoute
                "suggestions" -> SuggestionsRoute
                "compete" -> CompeteRoute
                "bands" -> BandsRoute
                // `band:<bandId>[:<bandType>:<teamKey>]`; the team key itself contains `:`.
                "band" -> arg?.split(":", limit = 3)?.let { BandRoute(it[0], bandType = it.getOrNull(1), teamKey = it.getOrNull(2)) }
                "songBandLeaderboard" -> arg?.split(":")?.let { pieces ->
                    SongBandLeaderboardRoute(
                        pieces[0],
                        pieces.getOrNull(1)?.takeIf { it.isNotBlank() } ?: "Band_Duets",
                        pieces.getOrNull(2)?.toIntOrNull()?.coerceAtLeast(1) ?: 1,
                        navToBand = pieces.getOrNull(3) == "reveal",
                    )
                }
                "licenses" -> LicensesRoute
                "allRivals", "rivalDetail", "rivalry" -> RivalRoutes.parseDebug(parts[0], arg)
                else -> null
            }
        }
    }
}

// endregion
