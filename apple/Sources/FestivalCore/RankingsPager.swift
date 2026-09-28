import Foundation

// MARK: - Pager state

/// One step a rankings pager can take, in the order the floating pager shows them
/// (`« ‹ 1 / 34,757 › »` on the web's `FullRankingsPage.tsx` pagination pill).
public enum RankingsPagerAction: String, CaseIterable, Sendable {
    case first
    case previous
    case next
    case last
}

/// Pure paging state behind every paginated rankings board's pager, so the
/// enabled/disabled rules, the visible `page / total` label and the spoken value are
/// testable without a view.
public struct RankingsPagerState: Equatable, Sendable {
    /// Current 1-based page, clamped into `1...totalPages`.
    public let page: Int
    /// Page count, always at least one (an empty board still has one page).
    public let totalPages: Int

    /// Create a clamped pager state.
    ///
    /// - Parameters:
    ///   - page: Requested 1-based page.
    ///   - totalPages: Page count reported by the board; values below one become one.
    public init(page: Int, totalPages: Int) {
        let total = max(1, totalPages)
        self.totalPages = total
        self.page = min(max(1, page), total)
    }

    /// Whether First/Previous can move.
    public var canGoBack: Bool { page > 1 }

    /// Whether Next/Last can move.
    public var canGoForward: Bool { page < totalPages }

    /// The page an action would load, or nil when that action is disabled here.
    ///
    /// - Parameter action: Pager step.
    /// - Returns: Destination page, or nil at the corresponding edge.
    public func destination(for action: RankingsPagerAction) -> Int? {
        switch action {
        case .first: canGoBack ? 1 : nil
        case .previous: canGoBack ? page - 1 : nil
        case .next: canGoForward ? page + 1 : nil
        case .last: canGoForward ? totalPages : nil
        }
    }

    /// Visible compact label, e.g. "1 / 34,757" (grouped with the current locale).
    public var label: String {
        "\(RankingsCountText.grouped(page)) / \(RankingsCountText.grouped(totalPages))"
    }

    /// Spoken value, e.g. "1 of 34,757", read after the element's "Page" label.
    public var accessibilityValue: String {
        "\(RankingsCountText.grouped(page)) of \(RankingsCountText.grouped(totalPages))"
    }
}

// MARK: - Count labels

/// Count-bearing labels on the rankings pages, mirroring the web client's
/// `rankings.viewAllRankingsWithCount`, `viewAllBandRankingsWithCount`,
/// `totalRanked` and `totalRankedBands` strings (`FortniteFestivalWeb/src/i18n/en.json`).
public enum RankingsCountText {
    /// Group an integer with the current locale's separators ("868,901").
    ///
    /// - Parameter value: Count to format.
    /// - Returns: The grouped decimal string.
    public static func grouped(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    /// Instrument card footer: "View all rankings (868,901)", or the bare label when
    /// the board reports no ranked accounts (web `RankingCard.tsx` `viewAllLabel`).
    ///
    /// - Parameter totalAccounts: `totalAccounts` from the top-ten response.
    /// - Returns: The footer button title.
    public static func viewAllRankings(totalAccounts: Int) -> String {
        totalAccounts > 0 ? "View all rankings (\(grouped(totalAccounts)))" : "View all rankings"
    }

    /// Band card footer: "View all band rankings (72,450)", or the bare label.
    ///
    /// - Parameter totalTeams: `totalTeams` from the top-ten response.
    /// - Returns: The footer button title.
    public static func viewAllBandRankings(totalTeams: Int) -> String {
        totalTeams > 0 ? "View all band rankings (\(grouped(totalTeams)))" : "View all band rankings"
    }

    /// Full-board subtitle, e.g. "868,901 ranked players" (singular for one).
    ///
    /// - Parameter totalAccounts: Ranked account count.
    /// - Returns: The subtitle text.
    public static func rankedPlayers(_ totalAccounts: Int) -> String {
        "\(grouped(totalAccounts)) ranked \(totalAccounts == 1 ? "player" : "players")"
    }

    /// Band-board subtitle, e.g. "72,450 ranked bands" (singular for one).
    ///
    /// - Parameter totalTeams: Ranked team count.
    /// - Returns: The subtitle text.
    public static func rankedBands(_ totalTeams: Int) -> String {
        "\(grouped(totalTeams)) ranked \(totalTeams == 1 ? "band" : "bands")"
    }

    /// Spoken songs column, e.g. "728 of 729 songs" for the visible "728 / 729".
    ///
    /// - Parameters:
    ///   - label: Visible `X / Y` songs label from `songsLabel(for:)`.
    ///   - fullCombos: True under FC Rate, where `X` counts full combos instead.
    /// - Returns: A VoiceOver-friendly phrase, or the input when it isn't `X / Y`.
    public static func spokenSongs(_ label: String, fullCombos: Bool = false) -> String {
        let parts = label.components(separatedBy: " / ")
        guard parts.count == 2 else { return label }
        return fullCombos
            ? "\(parts[0]) full combos of \(parts[1]) songs"
            : "\(parts[0]) of \(parts[1]) songs"
    }
}
