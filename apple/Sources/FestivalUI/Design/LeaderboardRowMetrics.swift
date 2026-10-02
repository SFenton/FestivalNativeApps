import SwiftUI

// MARK: - Row metrics

/// Shared sizes for every leaderboard row, so the pages draw one row height.
///
/// The web draws all leaderboard rows at `Layout.entryRowHeight` (48 px,
/// `packages/theme/src/spacing.ts`): Leaderboards cards, Full and Band Rankings, the
/// song leaderboards, Song Detail previews, the selected player's row and the pinned
/// footer rows. Issue #90: the rankings rows used 44 pt while the song rows used
/// 48 pt, so row heights changed between pages.
enum LeaderboardRowMetrics {
    /// Minimum height of a leaderboard row, its loading skeleton and its spotlight
    /// placeholder (web `Layout.entryRowHeight`).
    ///
    /// A minimum rather than a fixed height: rows still grow with Dynamic Type and
    /// stacked accessibility layouts (HIG Layout: "rows/containers may grow to avoid
    /// clipping/overlap and allow multiple lines"). It stays above the 44×44 pt iOS
    /// minimum control size (HIG Accessibility).
    static let minHeight: CGFloat = 48
}
