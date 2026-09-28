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
    /// `/bands/:bandId`
    case band(bandId: String, name: String?)

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
