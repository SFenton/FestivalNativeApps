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
    /// `/songs/:songId/:instrument` (1-based page). `focusSelected` is the web's
    /// `navToPlayer`: bring the selected player's row on that page into view (issue #307).
    case songLeaderboard(Song, Instrument, Int, focusSelected: Bool = false)
    /// `/songs/:songId/bands/:bandType` (1-based page). `focus` is the band row to
    /// highlight and bring into view, like `navToPlayer` for a band (issue #307).
    case songBandLeaderboard(Song, bandType: String, page: Int = 1, focus: SongBandRowFocus? = nil)
    /// `/songs/:songId/:instrument/history`
    case playerHistory(Song, Instrument)

    // MARK: Players and bands
    /// `/player/:accountId`
    case player(accountId: String, displayName: String?)
    /// `/bands/player/:accountId?group=`: `group` is the band size the list opens on
    /// (the profile's per-group View All, issue #312).
    case playerBands(accountId: String, displayName: String?, group: PlayerBandGroup = .all)
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
    /// `/rivals/all?category=&mode=&rankBy=`. `scope` carries the same
    /// information the web's independent query parameters do, typed and
    /// `Hashable` rather than encoded into one string (see `RivalScope`).
    case allRivals(scope: RivalScope)
    /// `/rivals/:rivalId`. `scope` is the combo/leaderboard/instrument context that
    /// produced the tapped row, or `nil` when reached without one (deep link,
    /// restored state); the destination screen then merges every Settings-visible
    /// instrument instead of failing.
    case rivalDetail(rivalId: String, name: String?, scope: RivalScope?)
    /// `/rivals/:rivalId/rivalry?mode=`. `scope` is forwarded unchanged from the
    /// `.rivalDetail` push that reached it.
    case rivalry(rivalId: String, mode: String, name: String?, scope: RivalScope?)

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
