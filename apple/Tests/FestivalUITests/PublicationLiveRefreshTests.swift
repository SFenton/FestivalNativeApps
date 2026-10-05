import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Live publication refresh (issue #304)

/// Publication 7, then 8 from the second publication read on.
private actor AdvancingPublicationTransport: HTTPTransport {
    private(set) var publicationReads = 0
    private(set) var requestHeaders: [[String: String]] = []

    func send(_ request: URLRequest) async throws -> HTTPResult {
        requestHeaders.append(request.allHTTPHeaderFields ?? [:])
        switch request.url?.path {
        case "/api/publication":
            publicationReads += 1
            let id = publicationReads == 1 ? 7 : 8
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":\(id),"publishedScrapeId":\(id),
             "readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
            """.utf8))
        case "/api/songs":
            let id = publicationReads <= 1 ? 7 : 8
            return HTTPResult(status: 200, data: Data("""
            {"count":2,"songs":[
             {"songId":"kept","title":"Kept \(id)","artist":"Fixture"},
             {"songId":"only-\(id)","title":"Only \(id)","artist":"Fixture"}]}
            """.utf8))
        default:
            throw FestivalAPIError.invalidResource
        }
    }
}

/// The first socket announces a new publication; later sockets stay open until closed.
private final class ScriptedSocket: PublicationLiveSocket, @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []

    var connected: [URL] { lock.withLock { urls } }

    func connect(to url: URL) -> AsyncThrowingStream<PublicationSocketEvent, any Error> {
        let number = lock.withLock { urls.append(url); return urls.count }
        return AsyncThrowingStream { continuation in
            continuation.yield(.opened)
            continuation.yield(.message(Data(#"{"type":"shop_snapshot","songs":[]}"#.utf8)))
            if number == 1 {
                continuation.yield(.message(Data(#"{"type":"publication_changed","publicationId":8}"#.utf8)))
                continuation.finish()
            }
        }
    }
}

/// Wait (bounded) for a main-actor condition.
@MainActor
private func eventually(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

private func song(_ id: String, title: String) throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"\(id)","title":"\(title)","artist":"Fixture"}
    """.utf8))
}

/// A pushed publication change is observed without user action and without navigation.
@MainActor
@Test func liveSocketObservesNewPublicationWithoutUserAction() async throws {
    let transport = AdvancingPublicationTransport()
    let client = try FestivalAPI(transport: transport)
    let socket = ScriptedSocket()
    let session = FestivalSession(
        factory: { client },
        liveConnection: PublicationLiveConnection(socket: socket, sleep: { _ in throw CancellationError() })
    )
    let window = UUID()
    session.acquireLiveUpdates(window)
    #expect(session.liveConnection?.isRunning == true)

    #expect(await eventually { session.publicationRevision == 1 })
    #expect(session.publicationId == 8)
    #expect(await eventually { socket.connected.count == 2 })
    #expect(socket.connected.map(\.absoluteString) == [
        "wss://festivalscoretracker.com/api/ws?publicationId=7",
        "wss://festivalscoretracker.com/api/ws?publicationId=8",
    ])
    // Keyless and anonymous: no privileged or selected-profile headers on any read.
    for headers in await transport.requestHeaders {
        #expect(headers.keys.allSatisfy {
            !$0.lowercased().contains("api-key") && !$0.lowercased().contains("selected")
        })
    }

    session.releaseLiveUpdates(window)
    #expect(session.liveConnection?.isRunning == false)
}

/// Windows share one socket; it closes only when the last window lets go.
@MainActor
@Test func liveSocketIsSharedAcrossWindows() throws {
    let socket = ScriptedSocket()
    let connection = PublicationLiveConnection(socket: socket, sleep: { _ in throw CancellationError() })
    let session = FestivalSession(factory: { try FestivalAPI(transport: AdvancingPublicationTransport()) },
                                  liveConnection: connection)
    let first = UUID(), second = UUID()
    session.acquireLiveUpdates(first)
    session.acquireLiveUpdates(second)
    session.acquireLiveUpdates(first)
    #expect(connection.isRunning)
    session.releaseLiveUpdates(first)
    #expect(connection.isRunning, "the other window still holds it")
    session.releaseLiveUpdates(second)
    #expect(!connection.isRunning)

    let without = FestivalSession(factory: { try FestivalAPI() })
    without.acquireLiveUpdates(first)
    #expect(without.liveConnection == nil, "hosted tests and fixture launches never open a socket")
}

/// The live socket is on for the public service and off for loopback fixtures by default.
@Test func liveUpdatesDefaultOnOnlyForPublicService() {
    #expect(PublicationLiveConnection.isEnabled(environment: [:]))
    #if DEBUG
    #expect(!PublicationLiveConnection.isEnabled(environment: ["FST_API_BASE_URL": "http://127.0.0.1:8787"]))
    #expect(PublicationLiveConnection.isEnabled(
        environment: ["FST_API_BASE_URL": "http://127.0.0.1:8787", "FST_LIVE_PUBLICATION_UPDATES": "1"]
    ))
    #expect(!PublicationLiveConnection.isEnabled(environment: ["FST_LIVE_PUBLICATION_UPDATES": "0"]))
    #endif
}

/// Songs routes keep their place and re-read their song from the new catalogue.
@MainActor
@Test func songRoutesReResolveAgainstTheNewCatalogue() async throws {
    let session = FestivalSession(factory: { try FestivalAPI(transport: AdvancingPublicationTransport()) })
    let old = try song("kept", title: "Kept 7")
    let route = AppRoute.songLeaderboard(old, .lead, 2)
    #expect(route.song == old)
    #expect(AppRoute.bands.song == nil)

    _ = try await session.catalog()
    _ = try await session.refreshPublication()
    #expect(session.publicationRevision == 1)
    let current = try await session.catalog()

    let kept = RouteSongRefresh.resolve(songId: "kept", in: current, publicationId: session.publicationId)
    guard case let .current(fresh) = kept else {
        Issue.record("expected the song from the new catalogue, got \(kept)")
        return
    }
    #expect(fresh.title == "Kept 8")
    #expect(route.replacingSong(fresh) == .songLeaderboard(fresh, .lead, 2))
    #expect(AppRoute.songDetail(old).replacingSong(fresh) == .songDetail(fresh))
    #expect(AppRoute.playerHistory(old, .bass).replacingSong(fresh) == .playerHistory(fresh, .bass))
    #expect(AppRoute.songBandLeaderboard(old, bandType: "Band_Duets").replacingSong(fresh)
        == .songBandLeaderboard(fresh, bandType: "Band_Duets"))
    #expect(AppRoute.bands.replacingSong(fresh) == .bands)

    #expect(RouteSongRefresh.resolve(songId: "only-7", in: current, publicationId: session.publicationId)
        == .missing, "a song the new publication dropped is reported, never shown stale")
    #expect(RouteSongRefresh.resolve(songId: "kept", in: current, publicationId: 7)
        == .failed(ServiceIssue(FestivalAPIError.invalidPublication)), "generations never mix")
}
