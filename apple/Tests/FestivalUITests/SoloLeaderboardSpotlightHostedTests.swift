#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixture transport

/// Keyless fixture transport for `SoloLeaderboardScreen` spotlight hosted renders:
/// publication plus a minimal `/api/player/{accountId}` compact profile envelope,
/// matching the same service-safety rules as `HostedRankingsTransport`.
private actor HostedSoloSpotlightTransport: HTTPTransport {
    private let generation = 13

    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        if url.path == "/api/publication" {
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":\(generation),"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        let prefix = "/api/player/"
        guard url.path.hasPrefix(prefix),
              request.value(forHTTPHeaderField: "X-FST-Publication-Id") == String(generation)
        else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        let accountId = String(url.path.dropFirst(prefix.count))
        guard accountId == "fixture-spotlight-player" else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        return HTTPResult(status: 200, data: Data("""
        {"accountId":"fixture-spotlight-player","displayName":"Spotlight Player",
         "totalScores":1,
         "scores":[{"si":"fixture-pulse","ins":"01","sc":95000,"rk":57,"te":500}]}
        """.utf8), headers: ["X-FST-Publication-Id": String(generation)])
    }
}

/// Decode a minimal charted song without network-dependent artwork.
private func spotlightFixtureSong() throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Fixture Pulse","artist":"Fixture Artist",
     "year":2026,"difficulty":{"guitar":3,"bass":3}}
    """.utf8))
}

/// Build a 25-row Lead chart page, optionally including the spotlighted account.
///
/// - Parameter includeSpotlightAccount: When true, one row is
///   `fixture-spotlight-player` (their row is then visible on this page).
/// - Returns: A validated, freshly-pinned chart page.
private func spotlightFixtureLeaderboard(includeSpotlightAccount: Bool) throws -> LeaderboardPayload {
    let rows: [String] = (1...25).map { rank in
        let accountId = (includeSpotlightAccount && rank == 3)
            ? "fixture-spotlight-player" : "fixture-other-\(rank)"
        return #"{"accountId":"\#(accountId)","displayName":"Row \#(rank)","score":\#(99_000 - rank),"rank":\#(rank)}"#
    }
    let data = Data("""
    {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":25,
     "localEntries":500,"totalEntries":500,"entries":[\(rows.joined(separator: ","))]}
    """.utf8)
    let result = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
    try result.validate(songId: "fixture-pulse", instrument: .lead)
    return LeaderboardPayload(
        page: 1, leaderboard: result, publicationId: 13, observedPublicationId: 13, isStale: false
    )
}

/// Select the fixture spotlight player through the real `viewPlayer`/`selectPlayer`
/// path, so `FestivalSession.selectedPlayerScores` is populated exactly as it would
/// be after the operator picks a profile — never hand-assembled.
///
/// - Returns: A session with the fixture player selected and its score index loaded.
@MainActor
private func spotlightSelectedSession() async throws -> FestivalSession {
    let transport = HostedSoloSpotlightTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-spotlight-player","displayName":"Spotlight Player"}
    """.utf8))
    try session.selectPlayer(result, from: await session.viewPlayer(result))
    #expect(session.playerLoadState == .available)
    return session
}

// MARK: - Hosted renders

/// The selected player's row is highlighted in place and the footer shows their
/// score without a jump control when they are already visible on the page.
@MainActor
@Test func soloLeaderboardHighlightsVisibleSelectedRowWithoutJumpControl() async throws {
    let session = try await spotlightSelectedSession()
    let song = try spotlightFixtureSong()
    let payload = try spotlightFixtureLeaderboard(includeSpotlightAccount: true)
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(
        NavigationStack {
            SoloLeaderboardScreen(
                song: song, instrument: .lead, session: session,
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            )
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Fixture Pulse", "Your rank"])
    _ = try nativeHostedPNG(
        image, filename: "song-leaderboard-spotlight-visible.png",
        environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image, containing: ["Fixture Pulse", "Your rank"], notContaining: ["Jump to"]
    )
}

/// A selected player not visible on the current page gets a footer with a jump
/// control that moves to the page containing their rank.
@MainActor
@Test func soloLeaderboardShowsJumpControlWhenSelectedRowIsOffPage() async throws {
    let session = try await spotlightSelectedSession()
    let song = try spotlightFixtureSong()
    let payload = try spotlightFixtureLeaderboard(includeSpotlightAccount: false)
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(
        NavigationStack {
            SoloLeaderboardScreen(
                song: song, instrument: .lead, session: session,
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            )
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Fixture Pulse", "Jump to"])
    _ = try nativeHostedPNG(
        image, filename: "song-leaderboard-spotlight-jump.png",
        environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Fixture Pulse", "Jump to"])
    // Rank 57 at page size 25 is page 3, matching `LeaderboardPaging.page(forRank:pageSize:)`.
    #expect(LeaderboardPaging.page(forRank: 57, pageSize: 25) == 3)
}

/// No selected player (or one with no score on this song) shows neither row
/// highlight nor footer.
@MainActor
@Test func soloLeaderboardShowsNoSpotlightWithoutASelectedScore() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let song = try spotlightFixtureSong()
    let payload = try spotlightFixtureLeaderboard(includeSpotlightAccount: false)
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(
        NavigationStack {
            SoloLeaderboardScreen(
                song: song, instrument: .lead, session: session,
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            )
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Fixture Pulse", "#1, Row 1"])
    _ = try nativeHostedPNG(
        image, filename: "song-leaderboard-spotlight-none.png",
        environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image,
        containing: ["Fixture Pulse", "#1, Row 1"],
        notContaining: ["Your rank", "Jump to"]
    )
}
#endif
