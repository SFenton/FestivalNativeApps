import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixture transport

/// Keyless fixture whose notifications read can be held open, so a test can observe
/// the center while a revalidation is in flight.
private actor GatedNotificationsTransport: HTTPTransport {
    private let generation = 7
    private var gated = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var notificationRequests = 0
    var notificationsStatus = 200

    /// Hold subsequent notification reads until `open()`.
    func close() { gated = true }

    /// Release every held notification read.
    func open() {
        gated = false
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }

    /// Serve the notification feed with the given HTTP status from now on.
    ///
    /// - Parameter status: HTTP status for later `/notifications` reads.
    func setNotificationsStatus(_ status: Int) { notificationsStatus = status }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        let headers = ["X-FST-Publication-Id": String(generation)]
        switch url.path {
        case "/api/publication":
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":\(generation),"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        case "/api/songs":
            return HTTPResult(status: 200, data: Data("""
            {"count":1,"currentSeason":40,"songs":[
              {"songId":"fixture-song","title":"Fixture Anthem","artist":"The Fixtures",
               "album":null,"year":2024,"durationSeconds":180,"albumArt":null,
               "difficulty":null,"pathArtifactGenerationId":null}
            ]}
            """.utf8), headers: headers)
        case "/api/player/fixture-1/notifications":
            notificationRequests += 1
            if gated {
                await withCheckedContinuation { waiters.append($0) }
            }
            try Task.checkCancellation()
            guard notificationsStatus == 200 else {
                return HTTPResult(status: notificationsStatus, data: Data())
            }
            return HTTPResult(status: 200, data: Data("""
            {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":1,
             "sourceCompletedAt":"2024-01-05T00:00:00Z","notificationsGenerated":true,"items":[
               {"eventId":2,"notificationGuid":"guid-2","accountId":"fixture-1",
                "eventKind":"player_fc_achieved","songId":"fixture-song",
                "instrument":"Solo_Bass",
                "detectedAt":"2024-01-04T00:00:00Z","expiresAt":"2024-02-04T00:00:00Z"}
            ]}
            """.utf8), headers: headers)
        default:
            throw FestivalAPIError.httpStatus(404)
        }
    }
}

/// Selected-profile session over the gated fixture.
@MainActor
private func gatedSession(_ transport: GatedNotificationsTransport) throws -> FestivalSession {
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    let defaults = try #require(UserDefaults(suiteName: "fst.tests.center.\(UUID().uuidString)"))
    defaults.set(
        Data(#"{"accountId":"fixture-1","displayName":"Fixture Player"}"#.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    return FestivalSession(factory: { client }, selectionStorage: defaults)
}

/// Yield until the transport has seen `count` notification reads.
private func waitForNotificationRequests(
    _ transport: GatedNotificationsTransport, count: Int
) async {
    for _ in 0..<2_000 where await transport.notificationRequests < count {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

// MARK: - NotificationsCenter

/// Reopening the sheet revalidates the same account's feed without regressing the
/// loaded rows to a spinner; a cancelled revalidation keeps them too.
@MainActor
@Test func notificationsCenterKeepsLoadedRowsWhileRevalidating() async throws {
    let transport = GatedNotificationsTransport()
    let session = try gatedSession(transport)
    let center = session.notificationsCenter

    await center.refresh(session: session)
    #expect(center.state == .loaded)
    #expect(center.notifications.map(\.id) == ["guid-2"])

    await transport.close()
    let revalidation = Task { await center.refresh(session: session) }
    await waitForNotificationRequests(transport, count: 2)
    #expect(center.state == .loaded)
    #expect(center.notifications.map(\.id) == ["guid-2"])
    await transport.open()
    await revalidation.value
    #expect(center.state == .loaded)

    await transport.close()
    let cancelled = Task { await center.refresh(session: session) }
    await waitForNotificationRequests(transport, count: 3)
    cancelled.cancel()
    await transport.open()
    await cancelled.value
    #expect(center.state == .loaded)
    #expect(center.notifications.map(\.id) == ["guid-2"])
}

/// A first load shows the loading state, a failed revalidation reports the failure,
/// and deselecting the profile clears the rows.
@MainActor
@Test func notificationsCenterLoadsFailsAndClearsOnDeselection() async throws {
    let transport = GatedNotificationsTransport()
    let session = try gatedSession(transport)
    let center = session.notificationsCenter

    await transport.close()
    let first = Task { await center.refresh(session: session) }
    await waitForNotificationRequests(transport, count: 1)
    #expect(center.state == .loading)
    #expect(center.notifications.isEmpty)
    await transport.open()
    await first.value
    #expect(center.state == .loaded)

    await transport.setNotificationsStatus(503)
    await center.refresh(session: session)
    guard case .failed = center.state else {
        Issue.record("Expected a failed revalidation, got \(center.state)")
        return
    }

    session.deselectPlayer()
    await center.refresh(session: session)
    #expect(center.state == .idle)
    #expect(center.notifications.isEmpty)
    #expect(center.unreadCount == 0)
}
