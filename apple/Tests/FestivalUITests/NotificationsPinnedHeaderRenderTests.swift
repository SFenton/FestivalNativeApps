#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// Keyless fixture transport for one scrolling Notifications feed: publication, the
/// catalogue song its rows name and the account's notifications. Rejects the privileged
/// key, selected-profile headers, writes and any other route.
private actor ScrollingNotificationsTransport: HTTPTransport {
    private let generation = 7
    let accountId: String
    let notificationsBody: Data

    init(accountId: String, notificationsBody: Data) {
        self.accountId = accountId
        self.notificationsBody = notificationsBody
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        let pinned = ["X-FST-Publication-Id": String(generation)]
        switch url.path {
        case "/api/publication":
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":\(generation),"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        case "/api/songs":
            guard request.value(forHTTPHeaderField: "X-FST-Publication-Id") == String(generation) else {
                throw FestivalAPIError.invalidPublication
            }
            return HTTPResult(status: 200, data: Data("""
            {"count":1,"currentSeason":40,"songs":[
              {"songId":"fixture-song","title":"Fixture Anthem","artist":"The Fixtures",
               "album":null,"year":2024,"durationSeconds":180,"albumArt":null,
               "difficulty":null,"pathArtifactGenerationId":null}
            ]}
            """.utf8), headers: pinned)
        case "/api/player/\(accountId)/notifications":
            guard request.value(forHTTPHeaderField: "X-FST-Publication-Id") == String(generation) else {
                throw FestivalAPIError.invalidPublication
            }
            return HTTPResult(status: 200, data: notificationsBody, headers: pinned)
        default:
            throw FestivalAPIError.httpStatus(404)
        }
    }
}

/// A loaded Notifications feed long enough to scroll: `newCount` unread rows ("New")
/// followed by `olderCount` rows already marked seen ("Older").
///
/// The account is unique per call: the seen store lives in the process's standard
/// defaults, keeps 200 IDs per account and is filled by every sheet that disappears.
/// Call ``forgetScrollingAccount(_:)`` when done.
@MainActor
private func scrollingNotificationsSession(
    newCount: Int, olderCount: Int
) async -> (session: FestivalSession, accountId: String) {
    let accountId = "scroll\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
    let instruments = ["Solo_Guitar", "Solo_Bass", "Solo_Drums", "Solo_Vocals"]
    let items = (0..<(newCount + olderCount)).map { index in
        """
        {"eventId":\(index + 1),"notificationGuid":"\(accountId)-\(index)","accountId":"\(accountId)",
         "eventKind":"player_song_rank_improved","songId":"fixture-song",
         "instrument":"\(instruments[index % instruments.count])","oldRank":\(500 + index),"newRank":\(index + 1),
         "detectedAt":"2024-01-05T00:00:00Z","expiresAt":"2024-02-05T00:00:00Z"}
        """
    }
    let transport = ScrollingNotificationsTransport(accountId: accountId, notificationsBody: Data("""
    {"generatedAt":"2024-01-05T00:00:00Z","expiresAfterHours":72,"sourceRunId":1,
     "sourceCompletedAt":"2024-01-05T00:00:00Z","notificationsGenerated":true,"items":[
    \(items.joined(separator: ",\n"))
    ]}
    """.utf8))
    NotificationSeenStore.markSeen(
        (newCount..<(newCount + olderCount)).map { "\(accountId)-\($0)" }, accountId: accountId
    )
    let client = try! FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: transport)
    let defaults = UserDefaults(suiteName: "fst.tests.notifications-scroll.\(accountId)")!
    defaults.set(
        Data(#"{"accountId":"\#(accountId)","displayName":"Fixture Player"}"#.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    let session = FestivalSession(factory: { client }, selectionStorage: defaults)
    await session.notificationsCenter.refresh(session: session)
    #expect(session.notificationsCenter.state == .loaded)
    #expect(session.notificationsCenter.unreadCount == newCount)
    return (session, accountId)
}

/// Drop a scrolling fixture account's seen IDs and selection suite.
@MainActor
private func forgetScrollingAccount(_ accountId: String) {
    let key = "fst.notifications.seen"
    if var store = UserDefaults.standard.dictionary(forKey: key) {
        store[accountId] = nil
        UserDefaults.standard.set(store, forKey: key)
    }
    UserDefaults.standard.removePersistentDomain(forName: "fst.tests.notifications-scroll.\(accountId)")
}

// MARK: - Geometry helpers

/// The List's own scroll view: the deepest scroll view whose document is a table.
@MainActor
private func listScrollView(in view: NSView) -> NSScrollView? {
    for subview in view.subviews {
        if let found = listScrollView(in: subview) { return found }
    }
    if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
    return nil
}

// MARK: - Pinned header (issue #301)

/// Issue #301: scrolled Notifications rows have gone by the time they reach the pinned
/// section header. The band beside the pinned "New"/"Older" title (right of the title,
/// down the header's height) shows no row text, while rows further down still draw.
@MainActor
@Test(arguments: [(160.0, "New"), (900.0, "Older")])
func notificationsRowsDoNotDrawUnderThePinnedSectionHeader(offset: Double, pinned: String) async throws {
    let (session, accountId) = await scrollingNotificationsSession(newCount: 8, olderCount: 24)
    defer { forgetScrollingAccount(accountId) }
    let size = CGSize(width: 420, height: 640)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: ["New"])
    let scroll = try #require(listScrollView(in: host))

    let clip = scroll.contentView
    clip.scroll(to: NSPoint(x: 0, y: CGFloat(offset) - scroll.contentInsets.top))
    scroll.reflectScrolledClipView(clip)
    let image = try await nativeHostedSettle(host, untilText: [pinned])
    _ = try nativeHostedPNG(
        image, filename: "notifications-pinned-\(pinned.lowercased()).png", environment: "FST_HISTORY_RENDER_OUT"
    )

    let scrollFrame = scroll.convert(scroll.bounds, to: host)
    let pinTop = (host.isFlipped ? scrollFrame.minY : host.bounds.height - scrollFrame.maxY)
        + scroll.contentInsets.top
    // The pinned band is the header's whole table row; its title occupies the leading
    // ~70 pt, while rows' text runs across the rest of the band.
    let table = try #require(scroll.documentView as? NSTableView)
    let headerRow = table.rect(ofRow: 0).height
    #expect(headerRow > 20)
    let band = CGRect(x: 90, y: pinTop + 1, width: size.width - 110, height: headerRow - 2)
    let below = CGRect(x: 90, y: pinTop + 80, width: size.width - 110, height: 200)
    #expect(nativeHostedBrightSamples(in: band, of: image, hostSize: size) == 0)
    #expect(nativeHostedBrightSamples(in: below, of: image, hostSize: size) > 0)
}

/// Issue #322: row separators fade with their rows. Swept through the "New" section and
/// past the push of "Older", no separator line (dim ink, unlike the bright text above)
/// is drawn in the pinned header's band beside its title, while separators further
/// down the list still draw.
@MainActor
@Test func notificationsRowSeparatorsDoNotDrawUnderThePinnedSectionHeader() async throws {
    let (session, accountId) = await scrollingNotificationsSession(newCount: 8, olderCount: 24)
    defer { forgetScrollingAccount(accountId) }
    let size = CGSize(width: 420, height: 640)
    let host = nativeHostedView(
        NotificationsSheet(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: ["New"])
    let scroll = try #require(listScrollView(in: host))
    let table = try #require(scroll.documentView as? NSTableView)
    let headerRow = table.rect(ofRow: 0).height
    #expect(headerRow > 20)

    // App background mean ≈ 27; a separator ≈ 49 (system separator color over it).
    let separatorInk = 40
    let offsets = Array(stride(from: 100.0, through: 700.0, by: 9.0)) + Array(stride(from: 880.0, through: 1_200.0, by: 9.0))
    var leaks: [Double] = []
    var separatorsBelow = 0
    for offset in offsets {
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: CGFloat(offset) - scroll.contentInsets.top))
        scroll.reflectScrolledClipView(clip)
        let image = try await nativeHostedSettle(host, untilText: [offset < 800 ? "New" : "Older"])
        let scrollFrame = scroll.convert(scroll.bounds, to: host)
        let pinTop = (host.isFlipped ? scrollFrame.minY : host.bounds.height - scrollFrame.maxY)
            + scroll.contentInsets.top
        // Right of the title, above the header's own bottom hairline.
        let band = CGRect(x: 90, y: pinTop + 1, width: size.width - 110, height: headerRow - 5)
        if nativeHostedBrightSamples(in: band, of: image, hostSize: size, threshold: separatorInk) > 0 {
            leaks.append(offset)
            _ = try nativeHostedPNG(
                image, filename: "notifications-separator-leak-\(Int(offset)).png", environment: "FST_HISTORY_RENDER_OUT"
            )
        }
        // A thin strip between the rows' text and their trailing chevrons: only separators draw there.
        let strip = CGRect(x: 340, y: pinTop + 100, width: 28, height: 300)
        separatorsBelow += nativeHostedBrightSamples(in: strip, of: image, hostSize: size, threshold: separatorInk)
    }
    #expect(leaks.isEmpty, "separator drawn under the pinned header at offsets \(leaks)")
    #expect(separatorsBelow > 0)
}
#endif
