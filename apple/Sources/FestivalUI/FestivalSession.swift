import Foundation
import FestivalCore
import Observation

/// One native app session owns its publication and artwork caches across tabs.
@MainActor
@Observable
final class FestivalSession {
    @ObservationIgnored
    private let factory: @Sendable () throws -> FestivalAPI
    @ObservationIgnored
    private var sharedClient: FestivalAPI?
    @ObservationIgnored
    let artwork: ArtworkCache
    private(set) var publicationId: Int?
    private(set) var publicationRevision = 0

    /// Create a session without starting network work during view construction.
    ///
    /// - Parameters:
    ///   - factory: Provider for a production or fixture-backed client.
    ///   - artwork: In-process artwork store, injectable for hosted tests.
    init(
        factory: @escaping @Sendable () throws -> FestivalAPI,
        artwork: ArtworkCache = ArtworkCache()
    ) {
        self.factory = factory
        self.artwork = artwork
    }

    /// Reuse the same client while the process remains alive.
    ///
    /// - Returns: One publication-aware API actor shared by all visited pages.
    /// - Throws: Configuration errors from the client factory.
    func client() throws -> FestivalAPI {
        if let sharedClient { return sharedClient }
        let created = try factory()
        sharedClient = created
        return created
    }

    /// Load songs and publish their verified generation to the navigation shell.
    ///
    /// - Returns: Catalog data with explicit freshness and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func catalog() async throws -> CatalogPayload {
        let payload = try await client().catalog()
        try observe(publicationId: payload.observedPublicationId)
        return payload
    }

    /// Load a chart under the same observable publication as the catalogue.
    ///
    /// - Parameters:
    ///   - songId: Catalog identifier for the requested song.
    ///   - instrument: Solo instrument chart.
    ///   - page: One-based page number.
    ///   - leeway: Present only when invalid-score filtering is enabled.
    /// - Returns: Validated score page and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func leaderboard(
        songId: String, instrument: Instrument, page: Int, leeway: Double?
    ) async throws -> LeaderboardPayload {
        let payload = try await client().leaderboard(
            songId: songId, instrument: instrument, page: page, leeway: leeway
        )
        try observe(publicationId: payload.observedPublicationId)
        return payload
    }

    /// Force-check the live service generation and notify views when it changes.
    ///
    /// - Returns: The currently published, validated service generation.
    /// - Throws: Service, transport or publication-consistency failures.
    func refreshPublication() async throws -> Publication {
        let result = try await client().publication(force: true)
        try observe(publicationId: result.publicationId)
        return result
    }

    /// A new generation invalidates retained routes and visible loaded data.
    ///
    /// - Parameter publicationId: Validated service generation, even for unpinned bytes.
    /// - Throws: `FestivalAPIError.invalidPublication` if an older async result arrives late.
    private func observe(publicationId: Int) throws {
        if let previous = self.publicationId {
            guard publicationId >= previous else {
                throw FestivalAPIError.invalidPublication
            }
            if previous != publicationId {
                publicationRevision += 1
            }
        }
        self.publicationId = publicationId
    }
}
