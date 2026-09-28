import Foundation

// MARK: - Player score history reads

extension FestivalAPI {
    /// Request one player's tracked score-change history for a song and instrument.
    ///
    /// `GET /api/player/{accountId}/history?songId=&instrument=` is a pure, keyless
    /// read of a precomputed published cache (`FSTService/Api/PlayerEndpoints.cs:733`):
    /// it looks up `registeredAccountIds` and a cached JSON blob, and never writes.
    /// An unregistered account returns HTTP 404; a registered account whose history
    /// has not been precomputed yet returns HTTP 202 with `status: "syncing"`.
    ///
    /// - Parameters:
    ///   - accountId: Validated public player key.
    ///   - songId: Catalog identifier to scope the history to.
    ///   - instrument: Solo chart to scope the history to.
    /// - Returns: Validated rows (possibly empty), sync state and offline freshness.
    /// - Throws: Invalid parameters, transport failures or malformed wire responses;
    ///   never for an unregistered account or a not-yet-published history (see `state`).
    public func playerHistory(
        accountId: String, songId: String, instrument: Instrument
    ) async throws -> PlayerHistoryPayload {
        let resource = PublicEndpoint.playerHistory(
            accountId: accountId, songId: songId, instrument: instrument.rawValue
        )
        do {
            let payload = try await read(resource)
            let response = try JSONDecoder().decode(PlayerHistoryResponse.self, from: payload.data)
            try response.validate(accountId: accountId)
            let state: PlayerHistoryState = payload.httpStatus == 202 ? .syncing : .available
            return PlayerHistoryPayload(
                response: response, state: state,
                publicationId: payload.publicationId,
                observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
            )
        } catch FestivalAPIError.httpStatus(404) {
            let current = try await publication()
            return PlayerHistoryPayload(
                response: PlayerHistoryResponse(
                    accountId: accountId, count: 0, history: [],
                    status: nil, notYetPublished: nil
                ),
                state: .unregistered, publicationId: nil,
                observedPublicationId: current.publicationId, isStale: false
            )
        }
    }
}
