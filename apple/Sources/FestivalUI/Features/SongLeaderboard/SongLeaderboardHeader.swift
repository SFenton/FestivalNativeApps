import SwiftUI
import FestivalCore
import FestivalDesign

// MARK: - Song leaderboard board line

/// The board line under a song leaderboard header's artist: the board's name (an
/// instrument or a band size), with the entry total when the service asks for totals.
/// The header itself is the shared ``SongHeaderRow`` and the bar title
/// ``SongBarTitleToolbarItem`` (patterns `song-header`, `song-leaderboard-header`).
enum SongLeaderboardBoardLine {
    /// Compose the board line.
    ///
    /// Web `SongInfoHeader` `subtitle2`: the band page reads
    /// `songBandLeaderboard.subtitle` ("{type} • {count} entries") only when
    /// `showLeaderboardEntryTotals` is true; natives use the solo board's " · ".
    ///
    /// - Parameters:
    ///   - name: Board name, e.g. "Lead" or "Duos".
    ///   - totalEntries: Ranked entries on the board; nil while this board's first
    ///     response is still loading (a band size just picked).
    ///   - showsTotals: The response's `showLeaderboardEntryTotals`.
    /// - Returns: "Duos · 1,234 entries" with totals, otherwise "Duos".
    static func text(name: String, totalEntries: Int?, showsTotals: Bool?) -> String {
        guard showsTotals == true, let totalEntries else { return name }
        return "\(name) · \(totalEntries.formatted()) entries"
    }

    // MARK: Split pane beside Song Detail

    /// Whether a song board shows the song header (art, title, artist, board line).
    ///
    /// Owner-approved split-pane variant (issue #342): a board opened in a split's
    /// trailing pane beside Song Detail is part of that song's page, so it drops the
    /// song header and is titled by its board instead (``InstrumentPageTitle``). Pushed
    /// boards, and boards pushed deeper inside the trailing pane, keep the header.
    ///
    /// - Parameter besideList: The list page beside the board
    ///   (`EnvironmentValues.splitDetailBesideList`), nil outside a split's detail root.
    /// - Returns: False only beside Song Detail.
    static func showsSongHeader(besideList: OnDemandSplitPolicy.ListPage?) -> Bool {
        besideList != .songDetail
    }

    /// The entry total under a board title beside Song Detail, on the same terms as the
    /// board line (``text(name:totalEntries:showsTotals:)``).
    ///
    /// - Parameters:
    ///   - totalEntries: Ranked entries on the board; nil while it loads.
    ///   - showsTotals: The response's `showLeaderboardEntryTotals`.
    /// - Returns: "1,234 entries" with totals, otherwise nil.
    static func totalText(totalEntries: Int?, showsTotals: Bool?) -> String? {
        guard showsTotals == true, let totalEntries else { return nil }
        return "\(totalEntries.formatted()) entries"
    }
}
