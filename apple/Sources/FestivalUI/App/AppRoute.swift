import Foundation
import FestivalCore

// MARK: - Routes

/// Every pushable destination in the app, mirroring the web app's `Routes` table
/// (`FortniteFestivalWeb/src/routes.ts`).
///
/// Each tab owns a `NavigationStack(path: [AppRoute])`; screens navigate with
/// `NavigationLink(value: AppRoute.…)` and never construct other screens directly.
/// `AppRouteDestination` maps each case to its feature screen.
///
/// Ownership: adding a case is an orchestrator (foundation) change. Feature lanes
/// fill in the screen behind an existing case inside their own `Features/<Feature>/` folder.
enum AppRoute: Hashable {
    // MARK: Songs
    /// `/songs/:songId`
    case songDetail(Song)
    /// `/songs/:songId/:instrument` (1-based page)
    case songLeaderboard(Song, Instrument, Int)
    /// `/songs/:songId/bands/:bandType`
    case songBandLeaderboard(Song, bandType: String)
    /// `/songs/:songId/:instrument/history`
    case playerHistory(Song, Instrument)

    // MARK: Players and bands
    /// `/player/:accountId`
    case player(accountId: String, displayName: String?)
    /// `/bands/player/:accountId`
    case playerBands(accountId: String, displayName: String?)
    /// `/bands`
    case bands
    /// `/bands/:bandId`.
    ///
    /// `bandType`/`teamKey` are additive: a rankings, player-bands or
    /// song-band-leaderboard row already knows both and passes them along so Band
    /// Detail can call the safe `GET /api/rankings/bands/{bandType}?teamKey=` board.
    /// A bare `bandId` (its one-way hash) cannot be resolved to either without the
    /// side-effecting `/api/bands/{bandId}` endpoint — see `Bands.swift`'s
    /// `BandDetail` documentation — so a link carrying only `bandId` (e.g. a debug
    /// deep link) shows an explicit "open from a band list" state instead.
    case band(bandId: String, name: String?, bandType: String? = nil, teamKey: String? = nil)

    // MARK: Competitive
    /// `/leaderboards` when pushed rather than shown as a tab (e.g. from Compete).
    case leaderboards
    /// `/leaderboards/all?instrument=&rankBy=`
    case fullRankings(instrument: Instrument, rankBy: String)
    /// `/leaderboards/bands/:bandType`
    case bandRankings(bandType: String)
    /// `/rivals`
    case rivals
    /// `/rivals/all?category=`
    case allRivals(category: String)
    /// `/rivals/:rivalId`
    case rivalDetail(rivalId: String, name: String?)
    /// `/rivals/:rivalId/rivalry?mode=`
    case rivalry(rivalId: String, mode: String, name: String?)

    // MARK: Profile hubs (tabs on phone, pushable elsewhere)
    /// `/statistics`
    case statistics
    /// `/suggestions`
    case suggestions
    /// `/compete`
    case compete

    // MARK: Misc
    /// `/shop`
    case shop
    /// `/settings/licenses`
    case licenses
}
