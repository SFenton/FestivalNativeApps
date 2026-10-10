import Foundation
import FestivalCore

// MARK: - Rankings reads

extension FestivalSession {
    /// Load a page of the public per-instrument rankings board under the same
    /// observable publication as every other tab.
    ///
    /// - Parameters:
    ///   - instrument: Solo chart being ranked.
    ///   - rankBy: Sort metric.
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page; ten for an overview card or 25 for a full page.
    /// - Returns: Validated rankings rows and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func rankings(
        instrument: Instrument, rankBy: RankingMetric, page: Int, pageSize: Int = 10
    ) async throws -> RankingsPayload {
        let payload = try await client().rankings(
            instrument: instrument, rankBy: rankBy, page: page, pageSize: pageSize
        )
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }

    /// Load a page of one Compete scope's board: an instrument's or a combo's
    /// (`/api/rankings/combo`), under the same observable publication as every other tab.
    ///
    /// - Parameters:
    ///   - scope: The instrument or within-group combo being ranked.
    ///   - rankBy: Sort metric.
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page.
    /// - Returns: Validated rankings rows (combo rows mapped onto the instrument row) and
    ///   publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func rankings(
        scope: RankingScope, rankBy: RankingMetric, page: Int, pageSize: Int = 10
    ) async throws -> RankingsPayload {
        switch scope {
        case let .instrument(instrument):
            return try await rankings(instrument: instrument, rankBy: rankBy, page: page, pageSize: pageSize)
        case let .combo(combo):
            let payload = try await client().comboRankings(
                combo: combo, rankBy: rankBy, page: page, pageSize: pageSize
            )
            try await observe(publicationId: payload.observedPublicationId)
            return payload
        }
    }

    /// Read one account's own row on a scope's board.
    ///
    /// Pure keyless reads (`/api/rankings/{instrument}/{accountId}` or
    /// `/api/rankings/combo/{accountId}`); never the forbidden player-stats GET.
    ///
    /// - Parameters:
    ///   - scope: The instrument or within-group combo.
    ///   - accountId: Validated public account key.
    ///   - rankBy: The board's metric (a combo row carries only this metric's rank).
    /// - Returns: The account's row, or an explicit unranked state.
    /// - Throws: Client configuration, transport, decoding or publication errors.
    func playerRanking(
        scope: RankingScope, accountId: String, rankBy: RankingMetric
    ) async throws -> PlayerInstrumentRankingPayload {
        switch scope {
        case let .instrument(instrument):
            return try await playerInstrumentRanking(instrument: instrument, accountId: accountId)
        case let .combo(combo):
            let payload = try await client().playerComboRanking(
                combo: combo, accountId: accountId, rankBy: rankBy
            )
            try await observe(publicationId: payload.observedPublicationId)
            return payload
        }
    }

    /// Load a page of the public per-band-size rankings board under the same
    /// observable publication as every other tab.
    ///
    /// - Parameters:
    ///   - bandType: Band size being ranked.
    ///   - rankBy: Sort metric (bands have no Max Score board).
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page; ten for an overview card or 25 for a full page.
    /// - Returns: Validated band rankings rows and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func bandRankings(
        bandType: BandType, rankBy: BandRankingMetric, page: Int, pageSize: Int = 10
    ) async throws -> BandRankingsPayload {
        let payload = try await client().bandRankings(
            bandType: bandType, rankBy: rankBy, page: page, pageSize: pageSize
        )
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }
}
