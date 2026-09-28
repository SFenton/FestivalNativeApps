package com.festivalscoretracker.android.core.nav

import kotlinx.serialization.Serializable

// region Routes

/**
 * Every navigable destination, mirroring Apple's `AppRoute` and the web
 * `routes.ts` table (all routes except the deprecated Manual).
 *
 * Tab roots are `*Tab` objects; pushable destinations carry typed arguments.
 * Songs are addressed by ID and resolved against the current catalogue, so a
 * publication change never leaves a route pointing at a stale `Song` value.
 * Instruments travel as service wire IDs (`Solo_Guitar`).
 */
sealed interface AppRoute

// Tab roots

/** `/songs` tab root. */
@Serializable data object SongsTab : AppRoute

/** `/suggestions` tab root (player selected). */
@Serializable data object SuggestionsTab : AppRoute

/** `/leaderboards` tab root. */
@Serializable data object LeaderboardsTab : AppRoute

/** `/compete` tab root (player selected, compact width). */
@Serializable data object CompeteTab : AppRoute

/** `/rivals` tab root (player selected, regular width). */
@Serializable data object RivalsTab : AppRoute

/** `/statistics` tab root (player selected). */
@Serializable data object StatisticsTab : AppRoute

/** `/settings` tab root. */
@Serializable data object SettingsTab : AppRoute

// Songs

/** `/songs/:songId`. */
@Serializable data class SongDetailRoute(val songId: String) : AppRoute

/** `/songs/:songId/:instrument` with a one-based page. */
@Serializable data class SongLeaderboardRoute(val songId: String, val instrument: String, val page: Int = 1) : AppRoute

/** `/songs/:songId/bands/:bandType`. */
@Serializable data class SongBandLeaderboardRoute(val songId: String, val bandType: String) : AppRoute

/** `/songs/:songId/:instrument/history`. */
@Serializable data class PlayerHistoryRoute(val songId: String, val instrument: String) : AppRoute

// Players and bands

/** `/player/:accountId`. */
@Serializable data class PlayerRoute(val accountId: String, val displayName: String? = null) : AppRoute

/** `/bands/player/:accountId`. */
@Serializable data class PlayerBandsRoute(val accountId: String, val displayName: String? = null) : AppRoute

/** `/bands`. */
@Serializable data object BandsRoute : AppRoute

/**
 * `/bands/:bandId`; `bandType`/`teamKey` come from the originating row because
 * the band-detail GET is side-effecting and blocked (service-safety.md).
 */
@Serializable
data class BandRoute(
    val bandId: String,
    val name: String? = null,
    val bandType: String? = null,
    val teamKey: String? = null,
) : AppRoute

// Competitive

/** `/leaderboards` pushed rather than shown as a tab (e.g. from Compete). */
@Serializable data object LeaderboardsRoute : AppRoute

/** `/leaderboards/all?instrument=&rankBy=` with a one-based page (rewritten in the back-stack entry as the user pages). */
@Serializable data class FullRankingsRoute(val instrument: String, val rankBy: String = "totalscore", val page: Int = 1) : AppRoute

/** `/leaderboards/bands/:bandType` with a one-based page (rewritten in the back-stack entry as the user pages). */
@Serializable data class BandRankingsRoute(val bandType: String, val page: Int = 1) : AppRoute

/** `/rivals` pushed from the drawer or Compete. */
@Serializable data object RivalsRoute : AppRoute

/** `/rivals/all`; [scope] is a typed `RivalScope.routeToken` (`core/rivals/RivalScope.kt`). */
@Serializable data class AllRivalsRoute(val scope: String) : AppRoute

/**
 * `/rivals/:rivalId`; [scope] is a `RivalScope.routeToken`. [allowLiveFallback] is set only
 * when opened from Find Rival (web `RivalsPage.tsx:263`).
 */
@Serializable
data class RivalDetailRoute(
    val rivalId: String,
    val name: String? = null,
    val scope: String? = null,
    val allowLiveFallback: Boolean = false,
) : AppRoute

/** `/rivals/:rivalId/rivalry?mode=`; scope and live fallback are forwarded from Rival Detail. */
@Serializable
data class RivalryRoute(
    val rivalId: String,
    val mode: String,
    val name: String? = null,
    val scope: String? = null,
    val allowLiveFallback: Boolean = false,
) : AppRoute

// Profile hubs pushed outside their tab

/** `/statistics` pushed. */
@Serializable data object StatisticsRoute : AppRoute

/** `/suggestions` pushed. */
@Serializable data object SuggestionsRoute : AppRoute

/** `/compete` pushed. */
@Serializable data object CompeteRoute : AppRoute

// Misc

/** `/shop`. */
@Serializable data object ShopRoute : AppRoute

/** `/settings/licenses`. */
@Serializable data object LicensesRoute : AppRoute

// endregion
