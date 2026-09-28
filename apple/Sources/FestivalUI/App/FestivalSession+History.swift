import Foundation
import FestivalCore

// MARK: - Player score history

extension FestivalSession {
    /// Load the selected/viewed player's tracked score history for one chart.
    ///
    /// - Parameters:
    ///   - accountId: Player whose history to read (usually `selectedPlayer`).
    ///   - songId: Catalog song identifier.
    ///   - instrument: Solo chart.
    /// - Returns: Validated rows (possibly empty), sync/registration state and freshness.
    /// - Throws: Client configuration, transport, decoding or publication errors.
    func playerHistory(
        accountId: String, songId: String, instrument: Instrument
    ) async throws -> PlayerHistoryPayload {
        let payload = try await client().playerHistory(
            accountId: accountId, songId: songId, instrument: instrument
        )
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }
}
