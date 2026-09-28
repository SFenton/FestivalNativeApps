import Foundation
import FestivalCore
import Observation
import CoreGraphics
import OSLog

/// NSCache evicts decoded pixels automatically when the process is under pressure.
private final class DecodedArtwork: NSObject {
    let image: CGImage

    /// Hold one immutable ImageIO result within the UI actor.
    ///
    /// - Parameter image: Decoded image shared between tile and backdrop renderers.
    init(image: CGImage) {
        self.image = image
    }
}

/// No selected result can silently fall back to an anonymous score card.
enum SelectedPlayerLoadState: Equatable {
    case none
    case loading
    case available
    case syncing
    case failed(String)
}

/// One native app session owns its publication and artwork caches across tabs.
@MainActor
@Observable
final class FestivalSession {
    @ObservationIgnored
    private static let log = Logger(
        subsystem: "com.sfenton.festivalscoretracker", category: "profile-selection"
    )
    @ObservationIgnored
    private let factory: @Sendable () throws -> FestivalAPI
    @ObservationIgnored
    private let selectionStorage: UserDefaults?
    @ObservationIgnored
    private var sharedClient: FestivalAPI?
    @ObservationIgnored
    let artwork: ArtworkCache
    @ObservationIgnored
    private let thumbnails = NSCache<NSString, DecodedArtwork>()
    @ObservationIgnored
    private var sourceArtworkPaths: [String] = []
    @ObservationIgnored
    private var profileRequestRevision = 0
    private(set) var publicationId: Int?
    private(set) var publicationRevision = 0
    private(set) var artworkPaths: [String] = []
    private(set) var currentShop: ShopPayload?
    private(set) var shopOffersById: [String: ShopSong] = [:]
    private(set) var shopError: String?
    private(set) var selectedPlayer: SelectedPlayerIdentity?
    private(set) var selectedPlayerScores: [String: [Instrument: PlayerScore]] = [:]
    private(set) var selectedPlayerScoreObservation: Int?
    private(set) var playerLoadState: SelectedPlayerLoadState = .none
    private(set) var playerError: String?
    private(set) var selectionRevision = 0

    /// Create a session without starting network work during view construction.
    ///
    /// - Parameters:
    ///   - factory: Provider for a production or fixture-backed client.
    ///   - artwork: In-process artwork store, injectable for hosted tests.
    ///   - selectionStorage: App-only identity store; nil in hosted tests.
    init(
        factory: @escaping @Sendable () throws -> FestivalAPI,
        artwork: ArtworkCache = ArtworkCache(),
        selectionStorage: UserDefaults? = nil
    ) {
        self.factory = factory
        self.artwork = artwork
        self.selectionStorage = selectionStorage
        thumbnails.totalCostLimit = 24_000_000
        if let stored = selectionStorage?.data(forKey: SelectedPlayerIdentity.storageKey) {
            do {
                let identity = try JSONDecoder().decode(
                    SelectedPlayerIdentity.self, from: stored
                )
                try identity.validate()
                selectedPlayer = identity
                playerLoadState = .loading
            } catch {
                selectionStorage?.removeObject(forKey: SelectedPlayerIdentity.storageKey)
                playerError = FestivalAPIError.invalidSelectedProfile.localizedDescription
                Self.log.error("Invalid stored profile identity was discarded")
            }
        }
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
        try await observe(publicationId: payload.observedPublicationId)
        let candidates = payload.catalog.songs.compactMap(\.albumArt).filter { !$0.isEmpty }
        if candidates != sourceArtworkPaths {
            sourceArtworkPaths = candidates
            artworkPaths = Array(candidates.shuffled().prefix(100))
        }
        return payload
    }

    /// Read the independent, publication-aware public Item Shop feed.
    ///
    /// - Returns: Validated current or explicitly stale Shop rows.
    /// - Throws: Configuration, network, publication or invalid-shop errors.
    func shop() async throws -> ShopPayload {
        do {
            let result = try await client().shop()
            try Task.checkCancellation()
            try await observe(publicationId: result.observedPublicationId)
            try Task.checkCancellation()
            currentShop = result
            shopOffersById = Dictionary(
                result.shop.songs.map { ($0.songId, $0) },
                uniquingKeysWith: { original, _ in original }
            )
            shopError = nil
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw error
        } catch {
            guard !Task.isCancelled else { throw CancellationError() }
            shopError = error.localizedDescription
            throw error
        }
    }

    /// View a search result without selecting or persisting its identity.
    ///
    /// - Parameter result: Validated keyless player-search result.
    /// - Returns: Available or syncing scores with response provenance.
    /// - Throws: Service, publication, cancellation or invalid-search errors.
    func viewPlayer(_ result: PlayerSearchResult) async throws -> PlayerProfilePayload {
        try result.validate()
        return try await profile(accountId: result.accountId)
    }

    /// Promote an explicitly viewed, response-proven player and its score index.
    ///
    /// - Parameters:
    ///   - result: Player selected by a separate user action.
    ///   - payload: Current matching, validated public profile read.
    /// - Throws: Invalid identity or a missing/changed response publication.
    func selectPlayer(
        _ result: PlayerSearchResult, from payload: PlayerProfilePayload
    ) throws {
        let identity = try SelectedPlayerIdentity(searchResult: result)
        guard payload.state == .available, let active = publicationId,
              payload.publicationId == active,
              payload.observedPublicationId == active else {
            throw FestivalAPIError.invalidPublication
        }
        let scores = try payload.profile.scoreIndex(requestedAccountId: identity.accountId)
        let stored = try JSONEncoder().encode(identity)
        selectionStorage?.set(stored, forKey: SelectedPlayerIdentity.storageKey)
        profileRequestRevision += 1
        selectedPlayer = identity
        selectedPlayerScores = scores
        selectedPlayerScoreObservation = payload.observedPublicationId
        playerLoadState = .available
        playerError = nil
        selectionRevision += 1
    }

    /// Remove identity and process-only scores while keeping app Settings intact.
    func deselectPlayer() {
        selectionStorage?.removeObject(forKey: SelectedPlayerIdentity.storageKey)
        selectionStorage?.removeObject(forKey: SongPlayerScoreFilter.storageKey)
        profileRequestRevision += 1
        selectedPlayer = nil
        selectedPlayerScores.removeAll()
        selectedPlayerScoreObservation = nil
        playerLoadState = .none
        playerError = nil
        selectionRevision += 1
    }

    /// Reload only the selected account, refusing stale completion after a switch.
    func refreshSelectedPlayer() async {
        guard let identity = selectedPlayer else { return }
        profileRequestRevision += 1
        let requestRevision = profileRequestRevision
        playerLoadState = .loading
        selectedPlayerScores.removeAll()
        selectedPlayerScoreObservation = nil
        playerError = nil
        do {
            let payload = try await profile(accountId: identity.accountId)
            try Task.checkCancellation()
            guard profileRequestRevision == requestRevision,
                  selectedPlayer == identity else {
                throw CancellationError()
            }
            if payload.state == .syncing {
                playerLoadState = .syncing
            } else {
                guard payload.publicationId == publicationId else {
                    throw FestivalAPIError.invalidPublication
                }
                selectedPlayerScores = try payload.profile.scoreIndex(
                    requestedAccountId: identity.accountId
                )
                selectedPlayerScoreObservation = payload.observedPublicationId
                playerLoadState = .available
            }
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled, profileRequestRevision == requestRevision,
                  selectedPlayer == identity else { return }
            selectedPlayerScores.removeAll()
            selectedPlayerScoreObservation = nil
            playerLoadState = .failed(error.localizedDescription)
            playerError = error.localizedDescription
        }
    }

    /// Apply selected scores only to Songs from the same current observation.
    ///
    /// - Parameter catalogueObservation: Generation observed for the displayed Songs rows.
    /// - Returns: True only for selected, available, generation-matched score data.
    func hasCurrentPlayerScores(forCatalogue catalogueObservation: Int?) -> Bool {
        guard selectedPlayer != nil, playerLoadState == .available,
              let catalogueObservation else { return false }
        return SongRelatedPublicationPolicy.matches(
            catalogue: catalogueObservation, related: selectedPlayerScoreObservation,
            current: publicationId
        )
    }

    /// Read one profile under the same observed publication as other visible pages.
    ///
    /// - Parameter accountId: Validated public player key.
    /// - Returns: Typed score data with response provenance.
    /// - Throws: Network, status, cancellation or generation errors.
    private func profile(accountId: String) async throws -> PlayerProfilePayload {
        let result = try await client().playerProfile(accountId: accountId)
        try Task.checkCancellation()
        try await observe(publicationId: result.observedPublicationId)
        try Task.checkCancellation()
        return result
    }

    /// Reuse bounded, decoded art instead of decoding the same cover while scrolling.
    ///
    /// - Parameters:
    ///   - raw: Public artwork path from a validated song.
    ///   - maxPixels: Bounded displayed edge, at most 2,048 pixels.
    /// - Returns: ImageIO result and whether this process already held its image bytes.
    /// - Throws: Invalid artwork, configuration, transport or cancellation errors.
    func preparedArtwork(
        raw: String, maxPixels: Int
    ) async throws -> (image: CGImage, fromMemory: Bool) {
        guard (1...2048).contains(maxPixels) else {
            throw FestivalAPIError.invalidArtwork
        }
        let startedAt = publicationRevision
        let key = NSString(string: "\(raw)|\(maxPixels)")
        if let cached = thumbnails.object(forKey: key) {
            return (cached.image, true)
        }
        let client = try client()
        guard let url = try await client.artworkURL(raw) else {
            throw FestivalAPIError.invalidArtwork
        }
        let payload = try await artwork.load(url)
        let prepared = try await ArtworkDecoding.prepare(
            payload.data, maxPixels: maxPixels
        )
        try Task.checkCancellation()
        guard publicationRevision == startedAt else { throw CancellationError() }
        thumbnails.setObject(
            DecodedArtwork(image: prepared.image), forKey: key,
            cost: prepared.image.width * prepared.image.height * 4
        )
        return (prepared.image, payload.fromMemory)
    }

    /// Load a chart under the same observable publication as the catalogue.
    ///
    /// - Parameters:
    ///   - songId: Catalog identifier for the requested song.
    ///   - instrument: Solo instrument chart.
    ///   - page: One-based page number.
    ///   - top: Ten preview rows or the full 25-row page.
    ///   - leeway: Present only when invalid-score filtering is enabled.
    /// - Returns: Validated score page and publication provenance.
    /// - Throws: Client configuration, transport, decoding or validation failures.
    func leaderboard(
        songId: String, instrument: Instrument, page: Int,
        top: Int = 25, leeway: Double?
    ) async throws -> LeaderboardPayload {
        let payload = try await client().leaderboard(
            songId: songId, instrument: instrument, page: page,
            top: top, leeway: leeway
        )
        try await observe(publicationId: payload.observedPublicationId)
        return payload
    }

    /// Load structured path text and propagate its observed publication to navigation.
    ///
    /// - Parameters:
    ///   - song: Catalog record containing the optional path generation.
    ///   - instrument: Path-capable solo chart.
    ///   - difficulty: Selected CHOpt path difficulty.
    /// - Returns: Validated text path and explicit freshness.
    /// - Throws: Service, decoding, publication or transport errors.
    func pathData(
        song: Song, instrument: Instrument, difficulty: PathDifficulty
    ) async throws -> SongPathDataPayload {
        let result = try await client().pathData(
            songId: song.songId, instrument: instrument, difficulty: difficulty,
            generationId: song.pathArtifactGenerationId
        )
        try await observe(publicationId: result.observedPublicationId)
        return result
    }

    /// Load a bounded, decoded path image under the same publication as Songs.
    ///
    /// - Parameters:
    ///   - song: Catalog record containing the optional path generation.
    ///   - instrument: Path-capable solo chart.
    ///   - difficulty: Selected CHOpt path difficulty.
    /// - Returns: Immutable image and explicit freshness.
    /// - Throws: Service, image, publication or transport errors.
    func pathImage(
        song: Song, instrument: Instrument, difficulty: PathDifficulty
    ) async throws -> SongPathImagePayload {
        let result = try await client().pathImage(
            songId: song.songId, instrument: instrument, difficulty: difficulty,
            generationId: song.pathArtifactGenerationId
        )
        try await observe(publicationId: result.observedPublicationId)
        return result
    }

    /// Force-check the live service generation and notify views when it changes.
    ///
    /// - Returns: The currently published, validated service generation.
    /// - Throws: Service, transport or publication-consistency failures.
    func refreshPublication() async throws -> Publication {
        let result = try await client().publication(force: true)
        try await observe(publicationId: result.publicationId)
        return result
    }

    /// A new generation invalidates retained routes and visible loaded data.
    ///
    /// Internal rather than private so same-module `FestivalSession+<Feature>.swift`
    /// extensions (see PROGRESS.md's lane file ownership) can feed their own reads
    /// through the same publication-consistency tracking as the methods below.
    ///
    /// - Parameter publicationId: Validated service generation, even for unpinned bytes.
    /// - Throws: `FestivalAPIError.invalidPublication` if an older async result arrives late.
    func observe(publicationId: Int) async throws {
        if let previous = self.publicationId {
            guard publicationId >= previous else {
                throw FestivalAPIError.invalidPublication
            }
            if previous != publicationId {
                self.publicationId = publicationId
                publicationRevision += 1
                profileRequestRevision += 1
                selectedPlayerScores.removeAll()
                selectedPlayerScoreObservation = nil
                playerLoadState = selectedPlayer == nil ? .none : .loading
                playerError = nil
                currentShop = nil
                shopOffersById.removeAll()
                shopError = nil
                sourceArtworkPaths.removeAll()
                artworkPaths.removeAll()
                thumbnails.removeAllObjects()
                await artwork.clearForPublicationChange()
                return
            }
        }
        self.publicationId = publicationId
    }
}
