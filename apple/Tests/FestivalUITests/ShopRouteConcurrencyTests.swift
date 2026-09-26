import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// Keep an obsolete Songs Shop response pending while Detail requests the new one.
private actor HeldShopTransport: HTTPTransport {
    private var reads = 0
    private var suspended: CheckedContinuation<HTTPResult, Error>?
    private var waiting: CheckedContinuation<Void, Never>?

    /// Return publication and the current Shop, withholding the first Shop reply.
    ///
    /// - Parameter request: Public GET whose order is controlled by this fixture.
    /// - Returns: Synthetic publication or Shop response.
    /// - Throws: Unknown or deliberately unavailable leaderboard routes.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        switch request.url?.path {
        case "/api/publication":
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        case "/api/shop":
            reads += 1
            if reads == 1 {
                return try await withCheckedThrowingContinuation { continuation in
                    suspended = continuation
                    waiting?.resume()
                    waiting = nil
                }
            }
            if reads == 3 {
                return HTTPResult(
                    status: 304, data: Data(),
                    headers: ["X-FST-Publication-Id": "7"]
                )
            }
            return HTTPResult(
                status: 200, data: Self.shopJSON(isNew: true),
                headers: ["X-FST-Publication-Id": "7", "ETag": "\"new\""]
            )
        default:
            return HTTPResult(status: 503, data: Data())
        }
    }

    /// Wait until the old Shop read is actually suspended.
    func waitForFirstShopRead() async {
        if suspended != nil { return }
        await withCheckedContinuation { continuation in waiting = continuation }
    }

    /// Complete the canceled read with stale data despite ignored transport cancellation.
    func releaseOldShopRead() {
        suspended?.resume(returning: HTTPResult(
            status: 200, data: Self.shopJSON(isNew: false),
            headers: ["X-FST-Publication-Id": "7", "ETag": "\"old\""]
        ))
        suspended = nil
    }

    /// Count real requested Shop resources rather than UI appearances.
    ///
    /// - Returns: Number of public Shop requests sent.
    func shopReadCount() -> Int { reads }

    /// Produce one original, official-link-shaped fixture offer.
    ///
    /// - Parameter isNew: Whether this fixture response reflects the current Shop.
    /// - Returns: Validated wire JSON without copied production content.
    private static func shopJSON(isNew: Bool) -> Data {
        Data("""
        {"count":1,"songs":[{"songId":"fixture-pulse","title":"Fixture Pulse",
         "artist":"Fixture","shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/fixture-pulse",
         "leavingTomorrow":false,"isNew":\(isNew)}]}
        """.utf8)
    }
}

/// A canceled Songs fetch cannot hide a valid Detail Shop action or poison its ETag.
@MainActor
@Test func detailShopLoadsAfterCancelledSongsRequestWithoutStalePromotion() async throws {
    let transport = HeldShopTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let oldSongsRead = Task { try await session.shop() }
    await transport.waitForFirstShopRead()
    oldSongsRead.cancel()

    let song = try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-pulse","title":"Fixture Pulse","artist":"Fixture",
     "difficulty":{"guitar":2}}
    """.utf8))
    let host = NSHostingView(rootView: NavigationStack {
        SongDetailScreen(song: song, session: session)
    })
    host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
    for _ in 0..<40 {
        host.layoutSubtreeIfNeeded()
        if session.currentShop?.shop.songs.first?.isNew == true { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(await transport.shopReadCount() == 2)
    #expect(session.shopOffersById["fixture-pulse"]?.isNew == true)

    await transport.releaseOldShopRead()
    await #expect(throws: CancellationError.self) { try await oldSongsRead.value }
    #expect(session.shopOffersById["fixture-pulse"]?.isNew == true)
    let next = try await session.shop()
    #expect(next.shop.songs.first?.isNew == true)
    #expect(await transport.shopReadCount() == 3)
}
