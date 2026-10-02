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
        "detectedAt":"2024-01-04T00:00:00Z","expiresAt":"2024-02-04T00:00:00Z"},
       {"eventId":3,"notificationGuid":"guid-3","accountId":"fixture-1",
        "eventKind":"player_first_score","songId":"fixture-song","instrument":"Solo_Drums",
        "detectedAt":"2024-01-03T00:00:00Z","expiresAt":"2024-02-03T00:00:00Z",
        "payload":{"coalescedInstruments":["Solo_Drums","Solo_Vocals"],"coalescedEvents":[
          {"eventKind":"player_first_score","instrument":"Solo_Drums","newNumeric":250000},
          {"eventKind":"player_stars_improved","instrument":"Solo_Vocals","oldNumeric":4,"newNumeric":5}]}}
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

/// Build a selected-profile session whose notification feed is already loaded.
///
/// The sheet's own `.task` refresh then revalidates without leaving the loaded
/// rows, so readiness never depends on when SwiftUI starts that task in an
/// offscreen host under a loaded parallel CI run (it once stayed on the spinner
/// for the whole settle timeout).
///
/// - Parameter transport: Fixture transport serving the feed.
/// - Returns: Session whose `notificationsCenter` is `.loaded`.
@MainActor
private func preloadedNotificationsSession(
    transport: HostedHistoryTransport
) async -> FestivalSession {
    let session = hostedHistorySession(transport: transport)
    await session.notificationsCenter.refresh(session: session)
    #expect(session.notificationsCenter.state == .loaded)
    return session
}

private let fixtureSong = Song(
    songId: "fixture-song", title: "Fixture Anthem", artist: "The Fixtures", album: nil,
    year: 2024, durationSeconds: 180, albumArt: nil, difficulty: nil,
    pathArtifactGenerationId: nil, sig: nil, maxScores: nil
)

// MARK: - Player History

/// Score history is a section of the song page: the selector, the chart and the best
/// scores (highest first, the best marked), expanding to every score in place.
@MainActor
@Test func songScoreHistorySectionRendersChartAndBestScores() async throws {
    let transport = HostedHistoryTransport()
    let session = hostedHistorySession(transport: transport)
    let payload = try await session.songHistory(accountId: "fixture-1", songId: "fixture-song")
    let entries = payload.response.history
    #expect(entries.count == 3)
    let size = CGSize(width: 420, height: 900)
    let host = nativeHostedView(
        ScrollView {
            SongScoreHistorySection(
                entries: entries, pool: [.lead, .bass], keyboardIcon: false,
                instrument: .constant(nil), expanded: .constant(false)
            )
            .padding(16)
        }
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Score History", "score 850,000"])
    _ = try nativeHostedPNG(image, filename: "song-score-history.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Score History", "score 850,000"])
}

/// Issue #32: Score History list rows show the season only when the page is at least
/// 520 pt wide (web `QUERY_SHOW_SEASON`); a portrait-phone page hides it.
@MainActor
@Test(arguments: [(393.0, false), (600.0, true)])
func songScoreHistoryRowsShowTheSeasonOnlyOnWidePages(width: Double, shows: Bool) async throws {
    let transport = HostedHistoryTransport()
    let session = hostedHistorySession(transport: transport)
    let entries = try await session.songHistory(accountId: "fixture-1", songId: "fixture-song").response.history
    let size = CGSize(width: width, height: 900)
    let host = nativeHostedView(
        ScrollView {
            SongScoreHistorySection(
                entries: entries, pool: [.lead], keyboardIcon: false,
                instrument: .constant(nil), expanded: .constant(false),
                viewportWidth: size.width, currentSeason: 40
            )
            .padding(16)
        }
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["score 850,000", "score 700,000"])
    _ = try nativeHostedPNG(
        image, filename: "song-score-history-season-\(Int(width)).png", environment: "FST_HISTORY_RENDER_OUT"
    )
    let seasons = ["current season 40, score 850,000", "season 39, score 700,000"]
    if shows {
        assertRendersContent(host, image: image, containing: seasons)
    } else {
        assertRendersContent(host, image: image, containing: ["score 850,000"], notContaining: ["season 39", "season 40"])
    }
}

/// Issue #32: a top-score row draws the season pill only when its card turns the
/// column on, and an entry without a season keeps the slot without speaking it.
@MainActor
@Test func songLeaderboardEntryRowSeasonColumnFollowsTheCard() async throws {
    func entry(_ id: String, season: Int?) -> LeaderboardEntry {
        LeaderboardEntry(
            accountId: id, displayName: "Fixture \(id)", score: 99_800, rank: 2, localRank: nil,
            accuracy: 980_000, isFullCombo: false, stars: 5, season: season, difficulty: 3
        )
    }
    let size = CGSize(width: 600, height: 200)
    let host = nativeHostedView(
        VStack(spacing: 8) {
            SongLeaderboardEntryRow(entry: entry("a", season: 9), seasonColumn: true, currentSeason: 9)
            SongLeaderboardEntryRow(entry: entry("b", season: 8), seasonColumn: true, currentSeason: 9)
            SongLeaderboardEntryRow(entry: entry("c", season: nil), seasonColumn: true)
            SongLeaderboardEntryRow(entry: entry("d", season: 7))
        }
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Current season 9", "Season 8", "Fixture d"])
    assertRendersContent(
        host, image: image, containing: ["Current season 9", "Season 8"], notContaining: ["Season 7"]
    )
}

// MARK: - Notifications

@MainActor
@Test func notificationsSheetRendersRowsWithUnreadSection() async throws {
    let transport = HostedHistoryTransport()
    let session = await preloadedNotificationsSession(transport: transport)
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
        host, untilText: ["You climbed from #42 to #10 on Lead", "Full Combo on Bass", "Drums: First Play"]
    )
    _ = try nativeHostedPNG(image, filename: "notifications.png", environment: "FST_HISTORY_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["You climbed from #42 to #10 on Lead", "Full Combo on Bass", "Drums: First Play"]
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
    let session = await preloadedNotificationsSession(transport: transport)
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
    let session = await preloadedNotificationsSession(transport: transport)
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
