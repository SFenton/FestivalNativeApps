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
}
