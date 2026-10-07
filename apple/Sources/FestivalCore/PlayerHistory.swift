import Foundation

// MARK: - Score history wire model

/// One tracked score change, mirroring the web's `ServerScoreHistoryEntry`
/// (`FortniteFestivalWeb/src/pages/leaderboard/player/PlayerHistoryPage.tsx`).
public struct ScoreHistoryEntry: Decodable, Sendable, Equatable {
    public let songId: String
    public let instrument: String
    public let oldScore: Int?
    public let newScore: Int
    public let oldRank: Int?
    public let newRank: Int
    public let accuracy: Double?
    public let isFullCombo: Bool?
    public let stars: Int?
    public let percentile: Double?
    public let season: Int?
    public let scoreAchievedAt: String?
    public let seasonRank: Int?
    public let allTimeRank: Int?
    public let difficulty: Double?
    public let changedAt: String

    /// Date used for sort/display; prefers the achieved timestamp like the web client.
    ///
    /// Service timestamps may or may not carry fractional seconds, so both are tried.
    public var displayDate: Date? {
        ISO8601Parsing.date(scoreAchievedAt ?? changedAt)
    }
}

/// `GET /api/player/{accountId}/history` response envelope.
public struct PlayerHistoryResponse: Decodable, Sendable, Equatable {
    public let accountId: String
    public let count: Int
    public let history: [ScoreHistoryEntry]
    public let status: String?
    public let notYetPublished: Bool?

    /// Reject a response for a different account or an internally inconsistent count.
    ///
    /// - Parameter accountId: Requested player.
    /// - Throws: `FestivalAPIError.invalidPlayerProfile` on a mismatched or corrupt payload.
    public func validate(accountId: String) throws {
        guard self.accountId == accountId, count == history.count, count >= 0 else {
            throw FestivalAPIError.invalidPlayerProfile
        }
    }
}

/// Availability of one player's score history for a song/instrument.
public enum PlayerHistoryState: Sendable, Equatable {
    /// Rows are ready, tagged with offline freshness.
    case available
    /// Registered but not yet computed by the service (HTTP 202).
    case syncing
    /// The account is not a registered/tracked user (HTTP 404).
    case unregistered
}

/// One page's response, freshness and availability, independent of URL state.
public struct PlayerHistoryPayload: Sendable {
    public let response: PlayerHistoryResponse
    public let state: PlayerHistoryState
    public let publicationId: Int?
    public let observedPublicationId: Int
    public let isStale: Bool

    /// Entries for exactly the requested song and instrument.
    ///
    /// - Parameters:
    ///   - songId: Requested catalog song.
    ///   - instrument: Requested solo chart.
    /// - Returns: Server-filtered rows, defensively re-filtered client-side.
    public func entries(songId: String, instrument: Instrument) -> [ScoreHistoryEntry] {
        response.history.filter {
            $0.songId == songId && $0.instrument == instrument.rawValue
        }
    }
}

// MARK: - Sort

/// Sort keys offered by the source `PlayerScoreSortModal`
/// (`FortniteFestivalWeb/src/pages/leaderboard/player/modals/PlayerScoreSortModal.tsx`).
public enum PlayerScoreSortMode: String, CaseIterable, Sendable, Identifiable {
    case date
    case score
    case accuracy
    case season

    public var id: String { rawValue }

    /// Present the same sort names as the web client.
    public var label: String {
        switch self {
        case .date: "Date"
        case .score: "Score"
        case .accuracy: "Accuracy"
        case .season: "Season"
        }
    }
}

/// Pure sort logic extracted for testability, matching `useSortedScoreHistory.ts`.
public enum PlayerScoreHistorySort {
    /// The web's default mode (`PlayerHistoryPage` `sortMode` initial state).
    public static let defaultMode: PlayerScoreSortMode = .score
    /// The web's default direction: descending, best or newest first.
    public static let defaultAscending = false

    /// Whether a sort differs from the default (the web's `active` sort pill, the
    /// native gold Sort tint).
    ///
    /// - Parameters:
    ///   - mode: Applied sort key.
    ///   - ascending: Applied direction.
    /// - Returns: True unless the sort is Score, descending.
    public static func isCustomized(mode: PlayerScoreSortMode, ascending: Bool) -> Bool {
        mode != defaultMode || ascending != defaultAscending
    }

    /// The Sort button's spoken value, e.g. "Score, descending".
    ///
    /// - Parameters:
    ///   - mode: Applied sort key.
    ///   - ascending: Applied direction.
    /// - Returns: The mode label and direction.
    public static func spokenValue(mode: PlayerScoreSortMode, ascending: Bool) -> String {
        "\(mode.label), \(ascending ? "ascending" : "descending")"
    }

    /// Order history rows by the chosen mode and direction.
    ///
    /// - Parameters:
    ///   - entries: Rows already filtered to one song/instrument.
    ///   - mode: Selected sort key.
    ///   - ascending: Sort direction.
    /// - Returns: A new array; ties break by score then date, as the web does for accuracy.
    public static func sorted(
        _ entries: [ScoreHistoryEntry], mode: PlayerScoreSortMode, ascending: Bool
    ) -> [ScoreHistoryEntry] {
        let direction = ascending ? 1 : -1
        return entries.sorted { a, b in
            let comparison: Int
            switch mode {
            case .date:
                let da = a.scoreAchievedAt ?? a.changedAt
                let db = b.scoreAchievedAt ?? b.changedAt
                comparison = da == db ? 0 : (da < db ? -1 : 1)
            case .score:
                comparison = a.newScore == b.newScore ? 0 : (a.newScore < b.newScore ? -1 : 1)
            case .accuracy:
                let aa = a.accuracy ?? 0
                let ab = b.accuracy ?? 0
                if aa != ab {
                    comparison = aa < ab ? -1 : 1
                } else {
                    let fcA = (a.isFullCombo ?? false) ? 1 : 0
                    let fcB = (b.isFullCombo ?? false) ? 1 : 0
                    if fcA != fcB {
                        comparison = fcA < fcB ? -1 : 1
                    } else if a.newScore != b.newScore {
                        comparison = a.newScore < b.newScore ? -1 : 1
                    } else {
                        let da = a.scoreAchievedAt ?? a.changedAt
                        let db = b.scoreAchievedAt ?? b.changedAt
                        comparison = da == db ? 0 : (da < db ? -1 : 1)
                    }
                }
            case .season:
                let sa = a.season ?? 0
                let sb = b.season ?? 0
                comparison = sa == sb ? 0 : (sa < sb ? -1 : 1)
            }
            return direction * comparison < 0
        }
    }

    /// The player's single highest score in the visible (already sorted) rows.
    ///
    /// - Parameter sorted: Rows in their currently displayed order.
    /// - Returns: Index of the best `newScore`, or nil for an empty list.
    public static func highScoreIndex(in sorted: [ScoreHistoryEntry]) -> Int? {
        guard !sorted.isEmpty else { return nil }
        var best = 0
        for index in 1..<sorted.count where sorted[index].newScore > sorted[best].newScore {
            best = index
        }
        return best
    }
}
