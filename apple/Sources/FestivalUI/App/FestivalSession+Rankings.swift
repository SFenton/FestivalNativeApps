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
