import Foundation

// MARK: - PlayerRankHistorySnapshot

/// One daily snapshot of an account's per-instrument global ranking, matching the
/// service's `RankHistoryDto` (`FSTService/Persistence/DataTransferObjects.cs`).
///
/// Read from `GET /api/rankings/{instrument}/{accountId}/history`, a pure `SELECT`
/// over `rank_history` joined to its snapshot stats
/// (`InstrumentDatabase.GetRankHistory`, `FSTService/Persistence/InstrumentDatabase.cs`),
/// never the forbidden player-stats GET.
public struct PlayerRankHistorySnapshot: Decodable, Sendable, Equatable, Identifiable {
    /// UTC calendar day, `yyyy-MM-dd`.
    public let snapshotDate: String
    public let snapshotTakenAt: String?
    public let adjustedSkillRank: Int
    public let weightedRank: Int
    public let fcRateRank: Int
    public let totalScoreRank: Int
    public let maxScorePercentRank: Int
    public let totalScore: Int?
    public let songsPlayed: Int?
    public let fullComboCount: Int?
    public let totalChartedSongs: Int?
    public let rankedAccountCount: Int?

    public var id: String { snapshotDate }

    /// The snapshot's calendar day as local midnight, or nil for a malformed wire date.
    ///
    /// The wire day is a UTC calendar date (`ToString("yyyy-MM-dd")`); it is a *label*,
    /// not an instant, so it is anchored in the current time zone. Anchoring at UTC
    /// midnight made charts west of UTC show every snapshot one day early.
    public var date: Date? {
        let parts = snapshotDate.split(separator: "-")
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }
}

// MARK: - PlayerRankHistory

/// Response for `/api/rankings/{instrument}/{accountId}/history`.
public struct PlayerRankHistory: Decodable, Sendable, Equatable {
    public let instrument: String
    public let accountId: String
    public let history: [PlayerRankHistorySnapshot]

    /// Reject a response for another instrument or account, or with bad rows.
    ///
    /// - Parameters:
    ///   - instrument: Requested solo chart.
    ///   - accountId: Requested account (compared case-insensitively).
    /// - Throws: `FestivalAPIError.invalidLeaderboard` on any mismatch.
    public func validate(instrument: Instrument, accountId: String) throws {
        guard self.instrument == instrument.rawValue,
              self.accountId.caseInsensitiveCompare(accountId) == .orderedSame,
              history.allSatisfy({ $0.date != nil && $0.totalScoreRank >= 0 }),
              Set(history.map(\.snapshotDate)).count == history.count else {
            throw FestivalAPIError.invalidLeaderboard
        }
    }

    /// Snapshots with a real Total Score rank, oldest first, for charting.
    public var rankedChronological: [PlayerRankHistorySnapshot] {
        history.filter { $0.totalScoreRank > 0 }.sorted { $0.snapshotDate < $1.snapshotDate }
    }
}

extension FestivalAPI {
    /// Read one account's daily global-rank history on one instrument.
    ///
    /// `GET /api/rankings/{instrument}/{accountId}/history?days=` only `SELECT`s
    /// (`RankingsEndpoints.cs` → `InstrumentDatabase.GetRankHistory`); no stats,
    /// tier or registration side effects. An account with no snapshots gets an empty
    /// `history`, not a 404.
    ///
    /// - Parameters:
    ///   - instrument: Solo chart to read.
    ///   - accountId: Validated public account key.
    ///   - days: Lookback window, 1 to 365 (the web uses 30).
    /// - Returns: Validated history for exactly this instrument and account.
    /// - Throws: Invalid parameters, transport, status or wire-shape errors.
    public func playerRankHistory(
        instrument: Instrument, accountId: String, days: Int = 30
    ) async throws -> PlayerRankHistory {
        let resource = PublicEndpoint.playerRankHistory(
            instrument: instrument.rawValue, accountId: accountId, days: days
        )
        do {
            let payload = try await read(resource)
            let history = try JSONDecoder().decode(PlayerRankHistory.self, from: payload.data)
            try history.validate(instrument: instrument, accountId: accountId)
            return history
        } catch is DecodingError {
            throw FestivalAPIError.invalidLeaderboard
        }
    }
}
