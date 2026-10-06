import Foundation

// MARK: - Rankings reads

extension FestivalAPI {
    /// Request one page of the public per-instrument rankings board.
    ///
    /// `GET /api/rankings/{instrument}?rankBy=&page=&pageSize=` is a pure, keyless
    /// read (`FSTService/Api/RankingsEndpoints.cs:187`); it never registers activity.
    ///
    /// - Parameters:
    ///   - instrument: Solo chart being ranked.
    ///   - rankBy: Sort metric.
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page; ten for an overview card or 25 for a full page.
    /// - Returns: Validated rankings rows and explicit offline freshness.
    /// - Throws: Invalid parameters, service failures or malformed wire responses.
    public func rankings(
        instrument: Instrument, rankBy: RankingMetric, page: Int, pageSize: Int = 10
    ) async throws -> RankingsPayload {
        guard page > 0, (1...200).contains(pageSize) else {
            throw FestivalAPIError.invalidResource
        }
        let resource = PublicEndpoint.rankings(
            instrument: instrument.rawValue, rankBy: rankBy.rawValue,
            page: page, pageSize: pageSize
        )
        let payload = try await read(resource)
        let response = try JSONDecoder().decode(RankingsResponse.self, from: payload.data)
        try response.validate(instrument: instrument)
        try await rememberUnverified(payload, for: resource)
        return RankingsPayload(
            page: page, rankings: response,
            publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }

    /// Request one page of the public per-band-size rankings board.
    ///
    /// `GET /api/rankings/bands/{bandType}?rankBy=&page=&pageSize=` is a pure,
    /// keyless read (`FSTService/Api/RankingsEndpoints.cs:680`).
    ///
    /// - Parameters:
    ///   - bandType: Band size being ranked.
    ///   - rankBy: Sort metric (bands have no Max Score board).
    ///   - page: One-based page number.
    ///   - pageSize: Rows per page; ten for an overview card or 25 for a full page.
    /// - Returns: Validated band rankings rows and explicit offline freshness.
    /// - Throws: Invalid parameters, service failures or malformed wire responses.
    public func bandRankings(
        bandType: BandType, rankBy: BandRankingMetric, page: Int, pageSize: Int = 10
    ) async throws -> BandRankingsPayload {
        guard page > 0, (1...200).contains(pageSize) else {
            throw FestivalAPIError.invalidResource
        }
        let resource = PublicEndpoint.bandRankings(
            bandType: bandType.rawValue, rankBy: rankBy.rawValue,
            page: page, pageSize: pageSize
        )
        let payload = try await read(resource)
        let response = try JSONDecoder().decode(BandRankingsResponse.self, from: payload.data)
        try response.validate(bandType: bandType)
        try await rememberUnverified(payload, for: resource)
        return BandRankingsPayload(
            page: page, rankings: response,
            publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }
}
