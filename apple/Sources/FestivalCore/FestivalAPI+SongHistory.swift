import Foundation

// MARK: - Song score history (every instrument)

extension FestivalAPI {
    /// Request one player's tracked score-change history for one song on **every**
    /// instrument, as the web song page does (`playerHistoryQueryOptions(accountId,
    /// songId)` feeds `ScoreHistoryChart`, whose instrument selector switches charts).
    ///
    /// Same pure, keyless read as ``playerHistory(accountId:songId:instrument:)``
    /// (`GET /api/player/{accountId}/history?songId=`, a precomputed published cache
    /// that never writes), just without the instrument scope: 404 is an unregistered
    /// account, 202 is still syncing.
    ///
    /// - Parameters:
    ///   - accountId: Validated public player key.
    ///   - songId: Catalog identifier to scope the history to.
    /// - Returns: Validated rows for every instrument (possibly empty), sync state and
    ///   freshness.
    /// - Throws: Invalid parameters, transport failures or malformed wire responses.
    public func songHistory(accountId: String, songId: String) async throws -> PlayerHistoryPayload {
        let resource = PublicEndpoint.playerHistory(accountId: accountId, songId: songId, instrument: nil)
        do {
            let payload = try await read(resource)
            let response = try JSONDecoder().decode(PlayerHistoryResponse.self, from: payload.data)
            try response.validate(accountId: accountId)
            return PlayerHistoryPayload(
                response: response, state: payload.httpStatus == 202 ? .syncing : .available,
                publicationId: payload.publicationId,
                observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
            )
        } catch FestivalAPIError.httpStatus(404) {
            let current = try await publication()
            return PlayerHistoryPayload(
                response: PlayerHistoryResponse(
                    accountId: accountId, count: 0, history: [], status: nil, notYetPublished: nil
                ),
                state: .unregistered, publicationId: nil,
                observedPublicationId: current.publicationId, isStale: false
            )
        }
    }
}

// MARK: - Song history chart model

/// The web `ScoreHistoryChart` data rules (`pages/songinfo/components/chart/
/// ScoreHistoryChart.tsx`, `useChartData`) for one song's history.
public enum SongScoreHistoryModel {
    /// Instruments with at least one history row, in `pool` order (web
    /// `availableInstruments`).
    ///
    /// - Parameters:
    ///   - entries: Every row for the song.
    ///   - pool: Visible charted instruments in display order.
    /// - Returns: The selector's instruments.
    public static func instruments(with entries: [ScoreHistoryEntry], in pool: [Instrument]) -> [Instrument] {
        let present = Set(entries.map(\.instrument))
        return pool.filter { present.contains($0.rawValue) }
    }

    /// The instrument to show: the requested one when it has history, else Lead when it
    /// has history, else the first with history (web auto-select effect).
    ///
    /// - Parameters:
    ///   - preferred: Requested instrument (deep link or current choice).
    ///   - available: ``instruments(with:in:)``.
    /// - Returns: The instrument to chart, or nil with no history.
    public static func resolvedInstrument(preferred: Instrument?, available: [Instrument]) -> Instrument? {
        if let preferred, available.contains(preferred) { return preferred }
        if available.contains(.lead) { return .lead }
        return available.first
    }

    /// One instrument's rows oldest first (the chart's x order).
    ///
    /// - Parameters:
    ///   - entries: Every row for the song.
    ///   - instrument: Charted instrument.
    /// - Returns: Chronological rows.
    public static func chronological(_ entries: [ScoreHistoryEntry], instrument: Instrument) -> [ScoreHistoryEntry] {
        entries.filter { $0.instrument == instrument.rawValue }
            .sorted { ($0.displayDate ?? .distantPast) < ($1.displayDate ?? .distantPast) }
    }

    /// The list beneath the chart: highest score first (ties by newest), the first
    /// `limit` rows (web top five; nil for every row, "View all scores").
    ///
    /// - Parameters:
    ///   - entries: One instrument's rows.
    ///   - limit: Rows to keep, or nil for all.
    /// - Returns: Rows by score, best first.
    public static func bestFirst(_ entries: [ScoreHistoryEntry], limit: Int?) -> [ScoreHistoryEntry] {
        let sorted = entries.sorted {
            if $0.newScore != $1.newScore { return $0.newScore > $1.newScore }
            return ($0.displayDate ?? .distantPast) > ($1.displayDate ?? .distantPast)
        }
        guard let limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    /// Web list size under the chart.
    public static let listLimit = 5

    /// Bar height on the chart's percent axis: accuracy in percent (0…100).
    ///
    /// - Parameter entry: History row.
    /// - Returns: Percent, or 0 when unknown.
    public static func accuracyPercent(_ entry: ScoreHistoryEntry) -> Double {
        guard let accuracy = entry.accuracy, accuracy.isFinite else { return 0 }
        return min(max(accuracy / 10_000, 0), 100)
    }

    /// Whether a bar is gold (web: accuracy ≥ 100% on a full combo).
    ///
    /// - Parameter entry: History row.
    /// - Returns: True for a gold bar.
    public static func isGold(_ entry: ScoreHistoryEntry) -> Bool {
        entry.isFullCombo == true && accuracyPercent(entry) >= 100
    }
}
