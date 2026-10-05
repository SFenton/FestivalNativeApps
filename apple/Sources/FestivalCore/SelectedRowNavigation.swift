import Foundation

// MARK: - Selected-row navigation

/// What tapping the selected profile's own row does, shared by the solo and band song
/// leaderboards so a player and a band follow one rule (issue #307):
///
/// - the row shown *separately* from the visible rows (Song Detail's row appended after
///   a top-ten preview, or a full board's pinned footer while the row is on another
///   page) jumps to its position in the full board;
/// - a selected row that is already visible opens the profile: Statistics for the
///   selected player, the Band page for a band.
///
/// Rows of other players and bands always open that player's profile or band page.
public enum SelectedRowAction: Equatable, Sendable {
    /// Show the full board's page that contains the row, with the row brought into view.
    case jump(page: Int)
    /// Open the selected profile (Statistics, or the Band page).
    case openProfile

    /// The action for a full board's pinned footer row.
    ///
    /// - Parameters:
    ///   - rank: The selected row's 1-based rank on this board.
    ///   - isVisible: Whether the row is on the page being shown (or loaded).
    ///   - pageSize: Rows per page.
    /// - Returns: ``openProfile`` when the row is visible or has no usable rank,
    ///   otherwise ``jump(page:)`` to the page that contains it.
    public static func footer(rank: Int, isVisible: Bool, pageSize: Int) -> SelectedRowAction {
        guard !isVisible, rank > 0 else { return .openProfile }
        return .jump(page: LeaderboardPaging.page(forRank: rank, pageSize: pageSize))
    }

    /// The action for a Song Detail preview's selected row.
    ///
    /// - Parameters:
    ///   - rank: The selected row's 1-based rank on the full board.
    ///   - isAppended: The row is appended after the top rows (they do not include it).
    ///   - pageSize: Rows per page of the full board.
    /// - Returns: ``jump(page:)`` for an appended row with a usable rank, else
    ///   ``openProfile``.
    public static func preview(rank: Int, isAppended: Bool, pageSize: Int) -> SelectedRowAction {
        footer(rank: rank, isVisible: !isAppended, pageSize: pageSize)
    }
}

// MARK: - Band row focus

/// Identifies one band's row on a song band leaderboard, so the board opened from
/// Song Detail's selected-band row can highlight that row and bring it into view
/// (web `isSameSongBandEntry`: equal non-empty `bandId`, or equal size and roster key).
public struct SongBandRowFocus: Hashable, Sendable {
    public let bandId: String
    public let bandType: String
    public let teamKey: String

    /// Create a focus target.
    ///
    /// - Parameters:
    ///   - bandId: Band's one-way identifier (may be empty).
    ///   - bandType: Wire band-size key (`Band_Duets`, …).
    ///   - teamKey: Band's roster key.
    public init(bandId: String, bandType: String, teamKey: String) {
        self.bandId = bandId
        self.bandType = bandType
        self.teamKey = teamKey
    }

    /// Focus on the band of a leaderboard row.
    ///
    /// - Parameter entry: Row to focus.
    public init(_ entry: SongBandLeaderboardEntry) {
        self.init(bandId: entry.bandId, bandType: entry.bandType, teamKey: entry.teamKey)
    }

    /// Whether a leaderboard row is this band.
    ///
    /// - Parameter entry: A board row.
    /// - Returns: True for an equal non-empty `bandId`, or the same size and roster key.
    public func matches(_ entry: SongBandLeaderboardEntry) -> Bool {
        (!bandId.isEmpty && bandId == entry.bandId)
            || (bandType == entry.bandType && !teamKey.isEmpty && teamKey == entry.teamKey)
    }
}
