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
                 "title":"Generation \(id)","artist":"Fixture"}]}
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

/// An explicit Settings refresh invalidates the old page and updates observation.
@MainActor
@Test func sessionPublishesRolloverAndNeverReturnsOldSongs() async throws {
    let transport = PublicationTransitionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let first = try await session.catalog()
    #expect(first.catalog.songs.first?.title == "Generation 7")
    #expect(session.publicationId == 7)
    #expect(session.publicationRevision == 0)

    _ = try await session.refreshPublication()
    #expect(session.publicationId == 8)
    #expect(session.publicationRevision == 1)
    let current = try await session.catalog()
    #expect(current.catalog.songs.first?.title == "Generation 8")
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
