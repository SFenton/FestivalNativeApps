#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Sequenced freeze transport

/// Forwards to the shared loopback fixture service until ``startFreeze()``, then answers
/// every `/api/…` read except `/api/publication` with a score-update 503 that names the
/// publication the fixture service last stamped, like the live service during a scrape
/// (issue #554, pattern `empty-error-states` R9).
private actor SequencedFreezeTransport: HTTPTransport {
    private let wrapped = URLSessionHTTPTransport()
    private var freezing = false
    private var onlySuffix: String?
    private var lastPublication: String?
    private(set) var frozenPaths: [String] = []

    /// Answer every later band, catalogue and board read with a scrape freeze.
    ///
    /// - Parameter suffix: Freeze only paths ending in this suffix; nil freezes them all.
    func startFreeze(onlyPathsEndingIn suffix: String? = nil) {
        freezing = true
        onlySuffix = suffix
    }

    /// Forward the request, or synthesize the freeze once ``startFreeze()`` ran.
    ///
    /// - Parameter request: Outgoing pinned read.
    /// - Returns: The fixture reply, or a 503 with `X-FST-Public-Read-Freeze-Reason: scrape`.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        let path = request.url?.path ?? ""
        if freezing, path.hasPrefix("/api/"), path != "/api/publication",
           onlySuffix.map(path.hasSuffix) ?? true {
            frozenPaths.append(path)
            var headers = ["Retry-After": "30", ServiceFreezeReason.header: "scrape", "Cache-Control": "no-store"]
            if let lastPublication { headers["X-FST-Publication-Id"] = lastPublication }
            return HTTPResult(
                status: 503,
                data: Data(#"{"title":"Published data unavailable","status":503}"#.utf8),
                headers: headers
            )
        }
        let result = try await wrapped.send(request)
        if let publication = result.header("X-FST-Publication-Id") { lastPublication = publication }
        return result
    }
}

// MARK: - Helpers

private let bandSize = CGSize(width: 402, height: 2000)

/// Section and row identifiers in the web's reading order.
private let freezeReadingOrder = [
    "fst.band.summary-section", "fst.band.history-section", "fst.band.best-songs",
    "fst.band.song-row.fixture-pulse", "fst.band.worst-songs", "fst.band.song-row.fixture-ghost-song",
]

@MainActor
private func hostBandDetail(_ session: FestivalSession) -> (NSHostingView<some View>, NSWindow) {
    let host = nativeHostedView(
        NavigationStack {
            BandDetailScreen(
                session: session, bandId: "fixture-band-1", name: "Band 1 Member A + Band 1 Member B",
                bandType: "Band_Duets", teamKey: "fixture-team-1"
            )
        }
        .preferredColorScheme(.dark),
        size: bandSize
    )
    return (host, nativeHostedWindow(host, size: bandSize))
}

// MARK: - Tests

/// #554 (pattern `empty-error-states` R9): a band page that loaded its Best & Worst Songs,
/// summary and Rank History keeps them when the page reappears during a scrape. The next
/// reads all answer a same-publication score-update 503, yet the rendered page still reads
/// the same song rows in web order, each a labelled ≥ 44 pt element, with no "Scores are
/// updating" inline status anywhere.
@MainActor
@Test func bandDetailKeepsBestAndWorstSongsThroughAScrapeFreeze() async throws {
    let transport = SequencedFreezeTransport()
    let client = try FestivalAPI(baseURL: try await RivalsMockService.shared.baseURL(), transport: transport)
    let session = FestivalSession(factory: { client })

    let (before, beforeWindow) = hostBandDetail(session)
    _ = try await nativeHostedSettle(before, untilText: ["Fixture Pulse", "Five Worst Songs"])
    let loaded = nativeHostedAccessibility(before).identifiers
    #expect(loaded.contains("fst.band.song-row.fixture-ghost-song"), "fixture did not load: \(loaded)")
    beforeWindow.orderOut(nil)

    await transport.startFreeze()
    let (during, duringWindow) = hostBandDetail(session)
    defer { duringWindow.orderOut(nil) }
    let image = try await nativeHostedSettle(during) {
        let ids = nativeHostedAccessibility(during).identifiers
        return ids.contains("fst.band.song-row.fixture-ghost-song") || ids.contains("fst.service-status.inline")
    }
    _ = try nativeHostedPNG(image, filename: "band-detail-scrape-freeze.png", environment: "FST_BANDS_RENDER_OUT")

    let frozen = await transport.frozenPaths
    #expect(frozen.contains("/api/rankings/bands/Band_Duets/fixture-team-1/songs"), "songs were not re-read: \(frozen)")
    #expect(frozen.contains("/api/rankings/bands/Band_Duets/fixture-team-1/history"), "history was not re-read: \(frozen)")

    let tree = nativeHostedAccessibility(during)
    #expect(!tree.identifiers.contains("fst.service-status.inline"), "freeze status shown: \(tree.identifiers)")
    #expect(!tree.identifiers.contains("fst.band.best-songs-empty"))
    #expect(!tree.identifiers.contains("fst.band.worst-songs-empty"))
    #expect(!tree.contains("Scores are updating"))

    let positions = freezeReadingOrder.map { tree.identifiers.firstIndex(of: $0) }
    #expect(positions.allSatisfy { $0 != nil }, "missing after freeze: \(tree.identifiers)")
    #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted(), "reading order: \(tree.identifiers)")

    for identifier in ["fst.band.song-row.fixture-pulse", "fst.band.song-row.fixture-ghost-song"] {
        let frame = try #require(nativeHostedAccessibilityFrame(identifier, in: during), "\(identifier) unreachable")
        #expect(frame.height >= 44, "\(identifier) is \(frame.height) pt tall")
    }
    let pulse = try #require(nativeHostedAccessibilityElement("fst.band.song-row.fixture-pulse", in: during))
    #expect(nativeHostedAccessibilityString(pulse, "accessibilityLabel").hasPrefix("Fixture Pulse, Top 10%, rank 1 of 10"))
}

/// #554 (R9 cold case, R1): a band first opened during a scrape, with nothing verified
/// this publication, shows the distinct "Scores are updating" inline status with Retry
/// in Best & Worst Songs, never the in-card "No ranked band songs yet." empty state.
@MainActor
@Test func bandDetailFirstOpenedDuringAScrapeShowsTheFreezeNotNoSongs() async throws {
    let transport = SequencedFreezeTransport()
    await transport.startFreeze(onlyPathsEndingIn: "/songs")
    let client = try FestivalAPI(baseURL: try await RivalsMockService.shared.baseURL(), transport: transport)
    let session = FestivalSession(factory: { client })

    let (host, window) = hostBandDetail(session)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host) {
        nativeHostedAccessibility(host).identifiers.contains("fst.service-status.retry")
    }
    let tree = nativeHostedAccessibility(host)
    let best = try #require(tree.identifiers.firstIndex(of: "fst.band.best-songs"), "\(tree.identifiers)")
    let worst = try #require(tree.identifiers.firstIndex(of: "fst.band.worst-songs"), "\(tree.identifiers)")
    let statuses = tree.identifiers.indices.filter { tree.identifiers[$0] == "fst.service-status.inline" }
    #expect(statuses.contains { $0 > best && $0 < worst }, "Best Songs has no inline status: \(tree.identifiers)")
    #expect(statuses.contains { $0 > worst }, "Worst Songs has no inline status: \(tree.identifiers)")
    #expect(tree.identifiers.contains("fst.service-status.retry"), "no Retry: \(tree.identifiers)")
    #expect(tree.identifiers.contains("fst.band.summary-section"), "summary should load: \(tree.identifiers)")
    #expect(!tree.identifiers.contains("fst.band.song-row.fixture-pulse"))
    #expect(!tree.identifiers.contains("fst.band.best-songs-empty"))
    #expect(!tree.contains("No ranked band songs yet."))
}
#endif
