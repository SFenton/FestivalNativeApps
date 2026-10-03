import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// Answers rival detail with a publish-freeze 503 and `/rivals/all` from a script,
/// recording every request so the tests can check the wire shape (#95).
private actor FrozenRivalDetailTransport: HTTPTransport {
    private let rivalsAll: HTTPResult
    private(set) var requests: [URL] = []

    init(rivalsAll: HTTPResult) { self.rivalsAll = rivalsAll }

    /// Route one keyless public GET.
    ///
    /// - Parameter request: The client's request.
    /// - Returns: Publication, `/rivals/all`, or a 503 for everything else.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url else { return HTTPResult(status: 400, data: Data()) }
        requests.append(url)
        switch url.path {
        case "/api/publication":
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        case "/api/player/player1/rivals/all":
            return rivalsAll
        case let path where path.hasPrefix("/api/player/player1/rivals/"):
            return HTTPResult(
                status: 503, data: Data(),
                headers: ["Retry-After": "30", ServiceFreezeReason.header: "post-process"]
            )
        default:
            return HTTPResult(status: 503, data: Data())
        }
    }
}

/// A session with `player1` selected over the scripted transport.
@MainActor
private func frozenSession(
    _ transport: FrozenRivalDetailTransport
) throws -> (session: FestivalSession, storage: UserDefaults, suite: String) {
    let client = try FestivalAPI(transport: transport)
    let suite = "fst.tests.rival-fallback.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity = ["accountId": "player1", "displayName": "Player"]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    return (FestivalSession(factory: { client }, selectionStorage: storage), storage, suite)
}

/// A `/rivals/all` body whose rival has one Lead and one Pro Lead sample.
private let rivalsAllBody = Data("""
{"accountId":"player1","songs":["s0","s1"],"combos":[{"combo":"03","above":[
 {"accountId":"rival9","displayName":"Rival Nine","direction":"above","sharedSongCount":2,
  "aheadCount":1,"behindCount":1,"rivalScore":1.0,"samples":[
   {"s":0,"i":"Solo_Guitar","ur":10,"rr":4,"us":900,"rs":950},
   {"s":1,"i":"Solo_PeripheralGuitar","ur":3,"rr":8,"us":800,"rs":700}]}],"below":[]}]}
""".utf8)

@MainActor
@Test func frozenRivalDetailFallsBackToRivalsAllWithWebScope() async throws {
    let transport = FrozenRivalDetailTransport(rivalsAll: HTTPResult(status: 200, data: rivalsAllBody))
    let (session, storage, suite) = try frozenSession(transport)
    defer { storage.removePersistentDomain(forName: suite) }

    let detail = try await session.rivalDetail(
        forScope: RivalDetailScopes.hubScope(visible: [.lead, .bass]), rivalId: "rival9",
        visibleInstruments: [.lead, .bass]
    )
    #expect(detail.source == RivalDetailFallback.source)
    #expect(detail.songs.map(\.songId) == ["s0"])
    #expect(detail.songs.first?.rankDelta == -6)
    #expect(detail.rival.displayName == "Rival Nine")

    let detailURL = try #require(await transport.requests.first { $0.path.hasSuffix("/rival9") })
    #expect(detailURL.path == "/api/player/player1/rivals/03/rival9")
    #expect(detailURL.query == "limit=0&sort=closest")
}

@MainActor
@Test func frozenFindRivalDetailAsksForEverySettingsScopeWithLiveFallback() async throws {
    let transport = FrozenRivalDetailTransport(rivalsAll: HTTPResult(status: 200, data: rivalsAllBody))
    let (session, storage, suite) = try frozenSession(transport)
    defer { storage.removePersistentDomain(forName: suite) }

    let detail = try await session.rivalDetail(
        forScope: nil, rivalId: "rival9", visibleInstruments: [.lead, .bass, .proLead, .proBass]
    )
    #expect(Set(detail.songs.map(\.songId)) == ["s0", "s1"])
    let detailURLs = await transport.requests.filter { $0.path.hasSuffix("/rival9") }
    #expect(detailURLs.map(\.path) == [
        "/api/player/player1/rivals/03/rival9", "/api/player/player1/rivals/30/rival9",
    ])
    #expect(detailURLs.allSatisfy { $0.query == "limit=0&sort=closest&allowLiveFallback=true" })
}

@MainActor
@Test func frozenRivalDetailKeepsTheRetryErrorWhenRivalsAllHasNoSamples() async throws {
    let transport = FrozenRivalDetailTransport(rivalsAll: HTTPResult(status: 404, data: Data()))
    let (session, storage, suite) = try frozenSession(transport)
    defer { storage.removePersistentDomain(forName: suite) }

    await #expect {
        _ = try await session.rivalDetail(
            forScope: .song(instruments: ["Solo_Guitar"]), rivalId: "rival9", visibleInstruments: [.lead]
        )
    } throws: { error in
        if case FestivalAPIError.publicReadFrozen(reason: "post-process", retryAfter: "30") = error { return true }
        return false
    }
}
