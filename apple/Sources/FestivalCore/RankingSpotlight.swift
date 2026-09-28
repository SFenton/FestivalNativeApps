import Foundation

// MARK: - Ranking spotlight

/// What is known about the selected player's own row on a rankings board,
/// independent of whether it is currently visible.
///
/// Mirrors the three states the web client's `RankingCard` distinguishes for
/// `playerRanking` (`FortniteFestivalWeb/src/pages/leaderboards/components/RankingCard.tsx:74-102`):
/// not loaded yet, loaded with no rank on this board, or loaded with a row.
public enum RankingSpotlightSource: Sendable, Equatable {
    /// The per-account ranking read has not completed (in flight or not started).
    case notLoaded
    /// The account has no rank on this board (`PlayerInstrumentRankingState.unranked`).
    case unranked
    /// The account's own row, ready to display.
    case available(AccountRankingEntry)
}

/// How the selected player's own row should be presented on a loaded rankings board.
public enum RankingSpotlightPlacement: Sendable, Equatable {
    /// No player is selected; nothing to spotlight.
    case none
    /// The selected player's row is already among the visible entries — highlight
    /// it in place rather than duplicating it below.
    case inline
    /// The selected player is not visible and their own rank is still loading.
    case pending
    /// The selected player is not visible and has no rank on this board.
    case unranked
    /// The selected player is not visible; show this row as a separate spotlight.
    case footer(AccountRankingEntry)
}

/// Pure decision logic for the selected-player spotlight shown on the Leaderboards
/// overview cards and the Full Rankings board, mirroring the web client's
/// `RankingCard` (`spotlightFooterRows` filters out any ranking whose account is
/// already in `topAccountIds`) without any view or networking concerns.
public enum RankingSpotlight {
    /// Decide how to present the selected player relative to one loaded board.
    ///
    /// - Parameters:
    ///   - selectedAccountId: Currently selected player's account id, or nil/empty
    ///     when no player is selected.
    ///   - visibleEntries: Rows already rendered for this board (a top-ten card's
    ///     entries, or the current page of a paginated board).
    ///   - source: What is known about the selected player's own row.
    /// - Returns: Where, if anywhere, to show the selected player's row.
    public static func placement(
        selectedAccountId: String?,
        visibleEntries: [AccountRankingEntry],
        source: RankingSpotlightSource
    ) -> RankingSpotlightPlacement {
        guard let selectedAccountId,
              !selectedAccountId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .none
        }
        let isVisible = visibleEntries.contains {
            $0.accountId.caseInsensitiveCompare(selectedAccountId) == .orderedSame
        }
        if isVisible { return .inline }
        switch source {
        case .notLoaded:
            return .pending
        case .unranked:
            return .unranked
        case let .available(entry):
            // Defensive: a mismatched account (stale fetch racing a new selection)
            // never surfaces as someone else's row.
            guard entry.accountId.caseInsensitiveCompare(selectedAccountId) == .orderedSame else {
                return .pending
            }
            return .footer(entry)
        }
    }
}
