#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Minimal keyless fixture transport for `PlayerHistoryScreen`/`NotificationsSheet`
/// hosted renders: publication, songs (for title/art resolution) and the two new
/// personal-data endpoints. Rejects the privileged key and selected-profile headers
/// like the service safety rules require of every fixture, matching the pattern in
/// `ShopScreenRenderTests.swift`.
actor HostedHistoryTransport: HTTPTransport {
    private let generation = 7
    var historyStatus = 200
    var notificationsBody = Data("""
    {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":1,
     "sourceCompletedAt":"2024-01-05T00:00:00Z","notificationsGenerated":true,"items":[
       {"eventId":1,"notificationGuid":"guid-1","accountId":"fixture-1",
        "eventKind":"player_song_rank_improved","songId":"fixture-song",
        "instrument":"Solo_Guitar","oldRank":42,"newRank":10,
        "detectedAt":"2024-01-05T00:00:00Z","expiresAt":"2024-02-05T00:00:00Z"},
       {"eventId":2,"notificationGuid":"guid-2","accountId":"fixture-1",
        "eventKind":"player_fc_achieved","songId":"fixture-song",
        "instrument":"Solo_Bass",
        "detectedAt":"2024-01-04T00:00:00Z","expiresAt":"2024-02-04T00:00:00Z"}
    ]}
    """.utf8)

    /// Replace the fixture `/api/player/{id}/notifications` response body.
    ///
    /// - Parameter body: Raw JSON envelope bytes to serve for subsequent requests.
    func setNotificationsBody(_ body: Data) {
        notificationsBody = body
    }

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
        guard request.value(forHTTPHeaderField: "X-FST-Publication-Id")
                == String(generation) else {
            throw FestivalAPIError.invalidPublication
        }
        if url.path == "/api/songs" {
            return HTTPResult(
                status: 200,
                data: Data("""
                {"count":1,"currentSeason":40,"songs":[
                  {"songId":"fixture-song","title":"Fixture Anthem","artist":"The Fixtures",
                   "album":null,"year":2024,"durationSeconds":180,"albumArt":null,
                   "difficulty":null,"pathArtifactGenerationId":null}
                ]}
                """.utf8),
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        if url.path == "/api/player/fixture-1/history" {
            if historyStatus == 202 {
                return HTTPResult(status: 202, data: Data("""
                {"accountId":"fixture-1","status":"syncing","notYetPublished":true,
                 "count":0,"history":[]}
                """.utf8))
            }
            return HTTPResult(
                status: 200,
                data: Data("""
                {"accountId":"fixture-1","count":3,"history":[
                  {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":850000,
                   "newRank":4,"accuracy":991200,"isFullCombo":true,"season":40,
                   "scoreAchievedAt":"2024-01-05T00:00:00Z","changedAt":"2024-01-05T00:00:00Z"},
                  {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":700000,
                   "newRank":9,"accuracy":954500,"isFullCombo":false,"season":39,
                   "scoreAchievedAt":"2024-01-01T00:00:00Z","changedAt":"2024-01-01T00:00:00Z"},
                  {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":600000,
                   "newRank":15,"accuracy":901000,"isFullCombo":false,"season":39,
                   "scoreAchievedAt":"2023-12-20T00:00:00Z","changedAt":"2023-12-20T00:00:00Z"}
                ]}
                """.utf8),
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        if url.path == "/api/player/fixture-1/notifications" {
            return HTTPResult(
                status: 200, data: notificationsBody,
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        }
        throw FestivalAPIError.httpStatus(404)
    }
}

/// Build a session with a stored selected profile against the fixture transport.
@MainActor
private func hostedHistorySession(transport: HostedHistoryTransport) -> FestivalSession {
    let client = try! FestivalAPI(
        baseURL: URL(string: "http://localhost")!, transport: transport
    )
    let suite = "fst.tests.history.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(
        Data("""
        {"accountId":"fixture-1","displayName":"Fixture Player"}
        """.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    return FestivalSession(factory: { client }, selectionStorage: defaults)
}

private let fixtureSong = Song(
    songId: "fixture-song", title: "Fixture Anthem", artist: "The Fixtures", album: nil,
    year: 2024, durationSeconds: 180, albumArt: nil, difficulty: nil,
    pathArtifactGenerationId: nil, sig: nil, maxScores: nil
)

// MARK: - Player History

@MainActor
@Test func playerHistoryScreenRendersScoreRowsAndChart() async throws {
    let transport = HostedHistoryTransport()
    let session = hostedHistorySession(transport: transport)
    let size = CGSize(width: 420, height: 900)
    let host = nativeHostedView(
        PlayerHistoryScreen(session: session, song: fixtureSong, instrument: .lead)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    // Let the `.task` load complete.
    let image = try await nativeHostedSettle(host, untilText: ["Score history chart", "score 850000"])
    _ = try nativeHostedPNG(image, filename: "player-history.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Score history chart", "score 850000"])
}

// MARK: - Notifications

@MainActor
@Test func notificationsSheetRendersRowsWithUnreadSection() async throws {
    let transport = HostedHistoryTransport()
    let session = hostedHistorySession(transport: transport)
    let size = CGSize(width: 420, height: 700)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["You climbed from #42 to #10 on Lead", "Full Combo on Bass"]
    )
    _ = try nativeHostedPNG(image, filename: "notifications.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["You climbed from #42 to #10 on Lead", "Full Combo on Bass"]
    )
}

/// No selected profile shows "Choose a Profile" rather than an empty feed
/// (`notifications` control's `no-profile` state).
@MainActor
@Test func notificationsSheetRendersNoProfileState() async throws {
    let transport = HostedHistoryTransport()
    // A session with no stored selection at all: `selectedPlayer` is nil.
    let client = try! FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    let session = FestivalSession(factory: { client })
    #expect(session.selectedPlayer == nil)
    let size = CGSize(width: 420, height: 500)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Choose a Profile"])
    _ = try nativeHostedPNG(image, filename: "notifications-no-profile.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Choose a Profile"])
}

/// A generated-but-empty feed shows the "will appear here" copy
/// (`notifications` control's `empty-generated` state).
@MainActor
@Test func notificationsSheetRendersEmptyGeneratedState() async throws {
    let transport = HostedHistoryTransport()
    await transport.setNotificationsBody(Data("""
    {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":1,
     "sourceCompletedAt":"2024-01-05T00:00:00Z","notificationsGenerated":true,"items":[]}
    """.utf8))
    let session = hostedHistorySession(transport: transport)
    let size = CGSize(width: 420, height: 500)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["No notifications available", "will appear here when new high scores are set"]
    )
    _ = try nativeHostedPNG(
        image, filename: "notifications-empty-generated.png", environment: "FST_HISTORY_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image,
        containing: ["No notifications available", "will appear here when new high scores are set"]
    )
}

/// A feed that has never been generated shows the "may appear after the next
/// leaderboard update" copy (`notifications` control's `empty-not-generated` state).
@MainActor
@Test func notificationsSheetRendersEmptyNotGeneratedState() async throws {
    let transport = HostedHistoryTransport()
    await transport.setNotificationsBody(Data("""
    {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":null,
     "sourceCompletedAt":null,"notificationsGenerated":false,"items":[]}
    """.utf8))
    let session = hostedHistorySession(transport: transport)
    let size = CGSize(width: 420, height: 500)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["No notifications available", "may appear here after the next leaderboard update"]
    )
    _ = try nativeHostedPNG(
        image, filename: "notifications-empty-not-generated.png", environment: "FST_HISTORY_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image,
        containing: ["No notifications available", "may appear here after the next leaderboard update"]
    )
}
#endif
