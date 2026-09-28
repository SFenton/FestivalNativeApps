import Foundation

// MARK: - Player notifications

extension FestivalAPI {
    /// Request one player's improvement-notification feed.
    ///
    /// `GET /api/player/{accountId}/notifications?limit=` is a pure, keyless read
    /// (`FSTService/Api/ImprovementNotificationEndpoints.cs:10`): it runs a single
    /// `SELECT` over `player_improvement_events`/`service_notifications`
    /// (`FSTService/Persistence/ImprovementNotificationService.cs:441-553`) and never
    /// writes. Unlike `player`/`playerHistory`, an unregistered or unknown account
    /// simply returns an empty envelope rather than 404.
    ///
    /// - Parameters:
    ///   - accountId: Validated public player key.
    ///   - limit: Rows requested, one to 200; the service defaults to 50.
    /// - Returns: Validated envelope and offline freshness.
    /// - Throws: Invalid parameters, transport failures or malformed wire responses.
    public func playerNotifications(
        accountId: String, limit: Int = 50
    ) async throws -> PlayerNotificationsPayload {
        let resource = PublicEndpoint.playerNotifications(accountId: accountId, limit: limit)
        let payload = try await read(resource)
        let envelope = try JSONDecoder().decode(
            ImprovementNotificationsEnvelope.self, from: payload.data
        )
        return PlayerNotificationsPayload(
            envelope: envelope, publicationId: payload.publicationId,
            observedPublicationId: payload.observedPublicationId, isStale: payload.isStale
        )
    }
}
