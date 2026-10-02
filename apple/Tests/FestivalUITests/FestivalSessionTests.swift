import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// Script publication seven then eight without touching a live service.
private actor PublicationTransitionTransport: HTTPTransport {
    private var publicationReads = 0
    private var songsReads: [Int] = []
    private var scoreQueries: [String] = []
    private let pinned: Bool
    private let advances: Bool

    /// Control whether the fixture supplies bound headers and a new generation.
    ///
    /// - Parameters:
    ///   - pinned: Simulate a publication-bound service response.
    ///   - advances: Move publication seven to eight on the second status read.
    init(pinned: Bool = true, advances: Bool = true) {
        self.pinned = pinned
        self.advances = advances
    }

    /// Return a generation-tagged catalogue after each publication refresh.
    ///
    /// - Parameter request: Publication or public-catalogue fixture request.
    /// - Returns: One valid, pinned fixture response.
    /// - Throws: Invalid requests outside the scripted public endpoints.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        switch request.url?.path {
        case "/api/publication":
            publicationReads += 1
            let id = publicationReads == 1 || !advances ? 7 : 8
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":\(id),"publishedScrapeId":\(id),
             "readyForPinning":\(pinned),"pinningEnabled":\(pinned),"unreadySurfaces":[]}
            """.utf8))
        case "/api/songs":
            let id = publicationReads == 1 || !advances ? 7 : 8
            let requestedId = request.value(forHTTPHeaderField: "X-FST-Publication-Id")
            guard pinned ? requestedId == String(id) : requestedId == nil else {
                throw FestivalAPIError.invalidPublication
            }
            songsReads.append(id)
            return HTTPResult(
                status: 200, data: Data("""
                {"count":1,"songs":[{"songId":"fixture-\(id)",
                 "title":"Generation \(id)","artist":"Fixture",
                 "albumArt":"/__fixture__/art/pulse.png"}]}
                """.utf8),
                headers: pinned ? ["X-FST-Publication-Id": String(id)] : [:]
            )
        case "/api/leaderboard/fixture-8/Solo_Guitar":
            scoreQueries.append(request.url?.query ?? "")
            return HTTPResult(
                status: 200, data: Data("""
                {"songId":"fixture-8","instrument":"Solo_Guitar","count":0,
                 "totalEntries":0,"entries":[]}
                """.utf8),
                headers: ["X-FST-Publication-Id": "8"]
            )
        default:
            throw FestivalAPIError.invalidResource
        }
    }

    /// Return the generations actually requested for the visible catalogue.
    ///
    /// - Returns: Publication IDs pinned to each catalogue response.
    func pinnedCatalogues() -> [Int] { songsReads }

    /// Return the wire queries made after the Settings leeway is enabled.
    ///
    /// - Returns: Recorded solo chart query strings.
    func recordedScoreQueries() -> [String] { scoreQueries }
}

/// Generate 105 unique catalog covers without downloading any image bytes.
actor ArtworkPoolTransport: HTTPTransport {
    private let catalogue: Data

    /// Build deterministic paths to prove the 100-cover process cap.
    init() {
        let songs = (0..<105).map { index in
            """
            {"songId":"fixture-\(index)","title":"Cover \(index)",
             "artist":"Fixture","albumArt":"covers/cover-\(index).png"}
            """
        }.joined(separator: ",")
        catalogue = Data("{\"count\":105,\"songs\":[\(songs)]}".utf8)
    }

    /// Serve a pinned generation and original synthetic catalogue.
    ///
    /// - Parameter request: Publication or Songs endpoint request.
    /// - Returns: Valid public fixture bytes and generation metadata.
    /// - Throws: Unknown paths outside the read-only fixture.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        switch request.url?.path {
        case "/api/publication":
            HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        case "/api/songs":
            HTTPResult(
                status: 200, data: catalogue,
                headers: ["X-FST-Publication-Id": "7"]
            )
        default:
            throw FestivalAPIError.invalidResource
        }
    }
}

/// An explicit Settings refresh invalidates the old page and updates observation.
@MainActor
@Test func sessionPublishesRolloverAndNeverReturnsOldSongs() async throws {
    let transport = PublicationTransitionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let first = try await session.catalog()
    #expect(first.catalog.songs.first?.title == "Generation 7")
    #expect(session.artworkPaths == ["/__fixture__/art/pulse.png"])
    #expect(session.publicationId == 7)
    #expect(session.publicationRevision == 0)

    _ = try await session.refreshPublication()
    #expect(session.publicationId == 8)
    #expect(session.publicationRevision == 1)
    #expect(session.artworkPaths.isEmpty)
    let current = try await session.catalog()
    #expect(current.catalog.songs.first?.title == "Generation 8")
    #expect(session.artworkPaths == ["/__fixture__/art/pulse.png"])
    #expect(session.publicationRevision == 1)
    #expect(await transport.pinnedCatalogues() == [7, 8])

    let scores = try await session.leaderboard(
        songId: "fixture-8", instrument: .lead, page: 1, leeway: 1
    )
    #expect(scores.publicationId == 8)
    #expect(session.publicationRevision == 1)
    #expect(await transport.recordedScoreQueries() == ["top=25&offset=0&leeway=1.0"])
}

/// A headerless catalog has no response provenance, but still observes its bootstrap.
@MainActor
@Test(arguments: [false, true])
func sessionTracksHeaderlessPublicationWithoutInventingProvenance(advances: Bool) async throws {
    let transport = PublicationTransitionTransport(pinned: false, advances: advances)
    let session = FestivalSession(factory: { try FestivalAPI(transport: transport) })
    let initial = try await session.catalog()
    #expect(initial.publicationId == nil)
    #expect(initial.observedPublicationId == 7)
    #expect(session.publicationId == 7)
    #expect(session.publicationRevision == 0)

    let checked = try await session.refreshPublication()
    let expected = advances ? 8 : 7
    #expect(checked.publicationId == expected)
    #expect(session.publicationId == expected)
    #expect(session.publicationRevision == (advances ? 1 : 0))
    let next = try await session.catalog()
    #expect(next.publicationId == nil)
    #expect(next.observedPublicationId == expected)
    #expect(next.catalog.songs.first?.title == "Generation \(expected)")
    #expect(await transport.pinnedCatalogues() == [7, expected])
}

/// Decoded and raw art are process-scoped and reset on a verified rollover.
@MainActor
@Test func sessionReusesDecodedArtAndClearsItOnPublicationChange() async throws {
    let png = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let transport = ArtworkFixtureTransport(data: try Data(contentsOf: png))
    let client = try FestivalAPI(
        baseURL: URL(string: "http://127.0.0.1:8765")!,
        transport: PublicationTransitionTransport()
    )
    let session = FestivalSession(
        factory: { client }, artwork: ArtworkCache(transport: transport)
    )
    _ = try await session.catalog()
    #expect(session.artworkPaths == ["/__fixture__/art/pulse.png"])
    #expect(session.cachedArtwork(raw: "/__fixture__/art/pulse.png", maxPixels: 56) == nil)
    let first = try await session.preparedArtwork(
        raw: "/__fixture__/art/pulse.png", maxPixels: 56
    )
    let cached = try await session.preparedArtwork(
        raw: "/__fixture__/art/pulse.png", maxPixels: 56
    )
    #expect(first.image.width == 56)
    #expect(!first.fromMemory && cached.fromMemory)
    #expect(await transport.requestCount() == 1)
    // A rebuilt row reads the decoded cover synchronously, only at the decoded size.
    let hit = session.cachedArtwork(raw: "/__fixture__/art/pulse.png", maxPixels: 56)
    #expect(hit?.width == 56)
    #expect(session.cachedArtwork(raw: "/__fixture__/art/pulse.png", maxPixels: 132) == nil)
    #expect(session.cachedArtwork(raw: "/__fixture__/art/pulse.png", maxPixels: 0) == nil)
    #expect(await transport.requestCount() == 1)

    _ = try await session.refreshPublication()
    #expect(session.artworkPaths.isEmpty)
    #expect(session.cachedArtwork(raw: "/__fixture__/art/pulse.png", maxPixels: 56) == nil)
    let current = try await session.preparedArtwork(
        raw: "/__fixture__/art/pulse.png", maxPixels: 56
    )
    #expect(!current.fromMemory)
    #expect(await transport.requestCount() == 2)
    await #expect(throws: FestivalAPIError.invalidArtwork) {
        try await session.preparedArtwork(
            raw: "/__fixture__/art/pulse.png", maxPixels: 2049
        )
    }
}

/// The fixture-only publication check must refill art before reporting publication eight.
@MainActor
@Test func settingsPublicationCheckRestoresCurrentArtworkPaths() async throws {
    let transport = PublicationTransitionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    _ = try await session.catalog()
    #expect(session.artworkPaths == ["/__fixture__/art/pulse.png"])
    _ = await SettingsPublicationCheck.run(session: session)
    #expect(session.publicationId == 8)
    #expect(session.artworkPaths == ["/__fixture__/art/pulse.png"])
    #expect(await transport.pinnedCatalogues() == [7, 8])
}

/// A successful publication check cannot claim fresh or verified offline Songs.
@Test func settingsPublicationSummaryKeepsSongFreshnessAndProvenanceSeparate() throws {
    let catalog = SongsResponse(count: 0, currentSeason: nil, songs: [])
    func payload(publicationId: Int?, stale: Bool) -> CatalogPayload {
        CatalogPayload(
            catalog: catalog, publicationId: publicationId,
            observedPublicationId: 7, isStale: stale
        )
    }
    #expect(SettingsServiceSummary.message(for: payload(publicationId: 7, stale: false))
            == "Publication 7")
    #expect(SettingsServiceSummary.message(for: payload(publicationId: nil, stale: false))
            == "Publication 7; songs live (publication unverified)")
    #expect(SettingsServiceSummary.message(for: payload(publicationId: 7, stale: true))
            == "Publication 7; songs offline - showing verified cached data")
    #expect(SettingsServiceSummary.message(for: payload(publicationId: nil, stale: true))
            == "Publication 7; songs offline - last seen (publication unverified)")
}

/// A catalogue update only reshuffles when its art paths actually change.
@MainActor
@Test func carouselPoolCapsAtHundredAndPreservesUnchangedOrder() async throws {
    let client = try FestivalAPI(transport: ArtworkPoolTransport())
    let session = FestivalSession(factory: { client })
    _ = try await session.catalog()
    let first = session.artworkPaths
    #expect(first.count == 100)
    #expect(Set(first).count == 100)
    _ = try await session.catalog()
    #expect(session.artworkPaths == first)
}
