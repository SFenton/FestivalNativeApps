#if os(iOS)
import FestivalCore
import UIKit

// MARK: - Leaderboards lane routes

/// The Leaderboards, rankings and song leaderboards lane's screens in the UIKit port (ports `Features/Leaderboards, Features/SongLeaderboard`).
///
/// Owned by the Leaderboards lane: `.leaderboards`, `.fullRankings`, `.fullComboRankings`, `.bandRankings`, `.songLeaderboard`, `.songBandLeaderboard`, `.playerHistory`; root `.leaderboards`. ``UKRouteDestination`` calls these; return nil for a
/// route not ported yet and the placeholder shows.
@MainActor
enum UKLeaderboardsRoutes {
    /// The controller for a pushed route of this lane.
    ///
    /// - Parameters:
    ///   - route: The route to show.
    ///   - context: The pushing screen's context.
    /// - Returns: The ported screen, or nil while it is not ported.
    static func make(_ route: AppRoute, context: UKContext) -> UIViewController? {
        switch route {
        case let .fullRankings(instrument, rankBy, page, focusSelected):
            UKFullRankingsViewController(context: context, instrument: instrument, rankBy: rankBy, page: page, focusSelected: focusSelected)
        case let .fullComboRankings(combo, rankBy, page, focusSelected):
            UKFullRankingsViewController(context: context, combo: combo, rankBy: rankBy, page: page, focusSelected: focusSelected)
        case let .bandRankings(bandType, rankBy, page):
            UKBandRankingsViewController(context: context, bandType: bandType, rankBy: rankBy, page: page)
        case .leaderboards:
            UKLeaderboardsViewController(context: context)
        case let .songLeaderboard(song, instrument, page, focusSelected):
            UKSongLeaderboardViewController(context: context, song: song, instrument: instrument, page: page, focusSelected: focusSelected)
        case let .songBandLeaderboard(song, bandType, page, focus):
            UKSongBandLeaderboardViewController(context: context, song: song, bandType: bandType, page: page, focus: focus)
        case let .playerHistory(song, instrument):
            UKPlayerHistoryViewController(context: context, song: song, instrument: instrument)
        default:
            nil
        }
    }

    /// The root controller of a section this lane owns.
    ///
    /// - Parameters:
    ///   - section: The root section.
    ///   - context: The section's context.
    /// - Returns: The ported root, or nil while it is not ported.
    static func root(for section: FestivalSection, context: UKContext) -> UIViewController? {
        section == .leaderboards ? UKLeaderboardsViewController(context: context) : nil
    }
}
#endif
