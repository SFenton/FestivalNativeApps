import Foundation

// MARK: - ScoreRowSeasonPolicy

/// When a score row on the song page shows the season the score was achieved (issue #32),
/// ported from the web's width rules:
///
/// - Score History list rows: viewport at least `MEDIUM_BREAKPOINT` (520 px,
///   `QUERY_SHOW_SEASON` in `packages/theme/src/breakpoints.ts`, used by
///   `pages/songinfo/components/chart/ScoreHistoryChart.tsx` `renderListItem`);
/// - the selected bar's detail row: always, when the score has a season
///   (`renderDetailCard` passes `showSeason={point.season != null}`);
/// - top-score rows in an instrument card: card width at least 520 px
///   (`resolveTopScoresColumns` in `pages/songinfo/topScoresLayout.ts`).
///
/// CSS pixels on the web equal points on iOS, so the breakpoint is compared in points.
public enum ScoreRowSeasonPolicy {
    /// Web `MEDIUM_BREAKPOINT` / `SEASON_BREAKPOINT` (520).
    public static let breakpoint: Double = 520

    /// The song-page row kinds that can carry a season pill.
    public enum Surface: Sendable, Equatable {
        /// A Score History list row; measured against the page (viewport) width.
        case historyList
        /// The row shown under the Score History chart for a tapped bar.
        case historyDetail
        /// A top-score row in an instrument card; measured against the card width.
        case topScores
    }

    /// Whether a row of `surface` shows a season pill at `width`.
    ///
    /// - Parameters:
    ///   - surface: The row kind.
    ///   - width: The page width for ``Surface/historyList``, the card width for
    ///     ``Surface/topScores``; ignored for ``Surface/historyDetail``. Zero or
    ///     unmeasured widths hide the season (web `resolveTopScoresColumns(0)`).
    ///   - season: The score's season, if the service reported one.
    /// - Returns: True only when the width rule allows it and the season is a positive number.
    public static func showsSeason(_ surface: Surface, width: Double, season: Int?) -> Bool {
        guard let season, season > 0 else { return false }
        switch surface {
        case .historyDetail: return true
        case .historyList, .topScores: return width.isFinite && width >= breakpoint
        }
    }

    /// Whether the column is on at `width`, independent of any one row's season, so a
    /// row without a season can still reserve the slot and keep scores aligned (web
    /// renders a hidden placeholder pill).
    ///
    /// - Parameters:
    ///   - surface: The row kind.
    ///   - width: As in ``showsSeason(_:width:season:)``.
    /// - Returns: True when rows of this kind show the season column at this width.
    public static func showsColumn(_ surface: Surface, width: Double) -> Bool {
        switch surface {
        case .historyDetail: return true
        case .historyList, .topScores: return width.isFinite && width >= breakpoint
        }
    }
}
