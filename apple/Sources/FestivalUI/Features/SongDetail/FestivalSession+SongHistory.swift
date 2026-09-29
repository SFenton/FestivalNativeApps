import Foundation
import FestivalCore

// MARK: - Song score history (every instrument)

extension FestivalSession {
    /// Load a player's tracked score history for one song on every instrument (the
    /// song page's Score History section, web `playerHistoryQueryOptions`).
    ///
    /// - Parameters:
    ///   - accountId: Player whose history to read (the selected player).
    ///   - songId: Catalog song identifier.
    /// - Returns: Validated rows (possibly empty), sync/registration state and freshness.
    /// - Throws: Client configuration, transport, decoding or publication errors.
    func songHistory(accountId: String, songId: String) async throws -> PlayerHistoryPayload {
        let payload = try await client().songHistory(accountId: accountId, songId: songId)
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }
}
