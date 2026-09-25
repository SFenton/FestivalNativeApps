import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

actor ArtworkFixtureTransport: HTTPTransport {
    let data: Data
    private var calls = 0

    /// Supply a PNG fixture without a live CDN request.
    ///
    /// - Parameter data: Original generated artwork bytes.
    init(data: Data) { self.data = data }

    /// Return one observable image response.
    ///
    /// - Parameter request: Local fixture image request.
    /// - Returns: PNG image bytes with the expected MIME type.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        calls += 1
        return HTTPResult(status: 200, data: data, headers: ["Content-Type": "image/png"])
    }

    /// Count actual HTTP sends rather than UI appearances.
    ///
    /// - Returns: Number of transport calls.
    func requestCount() -> Int { calls }
}

enum CatalogScenario: CaseIterable, Sendable, Equatable {
    case loading, populated, offline, empty, failure, refreshFailure
}

enum ScoreScenario: CaseIterable, Sendable {
    case loading, populated, offline, empty, failure
}

/// Decode fixtures using the same strict wire models as the native app.
///
/// - Parameter index: Song fixture to render.
/// - Returns: Valid catalog song without network-dependent artwork.
private func fixtureSong(_ index: Int = 1) throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-\(index)","title":"Fixture \(index)","artist":"Fixture Artist",
     "year":2026,"difficulty":{"guitar":\(index),"bass":3}}
    """.utf8))
}

/// Create loaded/empty/offline states without making a live request.
///
/// - Parameters:
///   - count: Number of fixture songs.
///   - stale: Whether the screen should announce memory-cached offline data.
/// - Returns: A validated catalogue payload.
private func fixtureCatalogue(count: Int, stale: Bool = false) throws -> CatalogPayload {
    let songs = try (1...max(1, count)).prefix(count).map(fixtureSong)
    let catalog = SongsResponse(count: count, currentSeason: 9, songs: songs)
    try catalog.validate()
    return CatalogPayload(
        catalog: catalog, publicationId: 7, observedPublicationId: 7, isStale: stale
    )
}

/// Build a 26-total leaderboard with either visible rows or an empty page.
///
/// - Parameters:
///   - visible: Number of rows on this page.
///   - stale: Whether the page is loaded from warm offline memory.
/// - Returns: Native validated response and freshness.
private func fixtureLeaderboard(visible: Int, stale: Bool = false) throws -> LeaderboardPayload {
    let rows = (1...max(1, visible)).prefix(visible).map { rank in
        #"{"accountId":"fixture-player-"# + String(rank)
            + #"","displayName":"Player ","score":90000,"rank":"#
            + String(rank) + "}"
    }.joined(separator: ",")
    let data = Data("""
    {"songId":"fixture-1","instrument":"Solo_Guitar","count":\(visible),
     "localEntries":26,"totalEntries":26,"entries":[\(rows)]}
    """.utf8)
    let result = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
    try result.validate(songId: "fixture-1", instrument: .lead)
    return LeaderboardPayload(
        page: 1, leaderboard: result, publicationId: 7,
        observedPublicationId: 7, isStale: stale
    )
}

/// Any unexpected request fails, preventing test screenshots from using the network.
@MainActor
private func offlineSession() -> FestivalSession {
    FestivalSession(factory: { throw FestivalAPIError.invalidResource })
}

/// Render a hosted macOS state at a consistent window size.
///
/// - Parameter content: Native view with a fixture-backed state.
/// - Returns: Snapshot image whose size and content can be asserted.
@MainActor
private func render<Content: View>(_ content: Content) throws -> CGImage {
    let renderer = ImageRenderer(content: content.frame(width: 800, height: 600))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    #expect(image.width == 800 && image.height == 600)
    return image
}

/// Individually exercise loading, populated, offline, empty and error catalogue views.
@MainActor
@Test(arguments: CatalogScenario.allCases)
func catalogueVisualStates(_ scenario: CatalogScenario) throws {
    let state: SongsScreen.LoadState
    switch scenario {
    case .loading: state = .loading
    case .populated: state = .loaded(try fixtureCatalogue(count: 2))
    case .offline: state = .loaded(try fixtureCatalogue(count: 2, stale: true))
    case .empty: state = .loaded(try fixtureCatalogue(count: 0))
    case .failure: state = .failed("Synthetic network outage")
    case .refreshFailure: state = .loaded(try fixtureCatalogue(count: 2))
    }
    _ = try render(NavigationStack {
        SongsScreen(
            session: offlineSession(), initialState: state,
            initialRefreshError: scenario == .refreshFailure ? "Update unavailable" : nil
        )
    })
}

/// Compare empty-result snapshots so a warning cannot disappear with the list.
@MainActor
@Test func emptySearchStillShowsFreshnessAndNavigationNotices() throws {
    let catalog = try fixtureCatalogue(count: 2)
    let unpinned = CatalogPayload(
        catalog: catalog.catalog, publicationId: nil,
        observedPublicationId: 7, isStale: false
    )
    func snapshot(
        _ payload: CatalogPayload, refresh: String? = nil, notice: String? = nil
    ) throws -> Data {
        let image = try render(NavigationStack {
            SongsScreen(
                session: offlineSession(), initialState: .loaded(payload),
                initialRefreshError: refresh,
                searchText: .constant("no-match"), settledSearch: .constant("no-match"),
                navigationNotice: .constant(notice)
            )
        })
        return try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
    }
    let baseline = try snapshot(catalog)
    #expect(try snapshot(catalog, refresh: "Update unavailable") != baseline)
    #expect(try snapshot(catalog, notice: "Scores changed; returned to Songs") != baseline)
    #expect(try snapshot(unpinned) != baseline)
}

/// An unpinned score response announces its missing provenance above the rows.
@MainActor
@Test func unpinnedScoresHaveAVisibleProvenanceWarning() throws {
    let pinned = try fixtureLeaderboard(visible: 1)
    let unpinned = LeaderboardPayload(
        page: pinned.page, leaderboard: pinned.leaderboard,
        publicationId: nil, observedPublicationId: 7, isStale: false
    )
    let song = try fixtureSong()
    func snapshot(_ payload: LeaderboardPayload) throws -> Data {
        let image = try render(NavigationStack {
            SoloLeaderboardScreen(
                song: song, instrument: .lead, session: offlineSession(),
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            )
        })
        return try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
    }
    #expect(try snapshot(pinned) != snapshot(unpinned))
}

/// Draw the real row body: high contrast and an instrument must change pixels.
@MainActor
@Test func songRowShowsMeterAndContrastOnDemand() throws {
    let song = try fixtureSong()
    let session = offlineSession()
    let normal = ImageRenderer(content: SongRowView(
        song: song, instrument: nil, session: session, highContrast: false
    ).frame(width: 420, height: 100))
    let selected = ImageRenderer(content: SongRowView(
        song: song, instrument: .lead, session: session, highContrast: false
    ).frame(width: 420, height: 100))
    let contrast = ImageRenderer(content: SongRowView(
        song: song, instrument: nil, session: session, highContrast: true
    ).frame(width: 420, height: 100))
    let original = try #require(normal.cgImage)
    let metered = try #require(selected.cgImage)
    let outlined = try #require(contrast.cgImage)
    let originalBytes = try #require(
        NSBitmapImageRep(cgImage: original).representation(using: .png, properties: [:])
    )
    let meteredBytes = try #require(
        NSBitmapImageRep(cgImage: metered).representation(using: .png, properties: [:])
    )
    let outlinedBytes = try #require(
        NSBitmapImageRep(cgImage: outlined).representation(using: .png, properties: [:])
    )
    #expect(originalBytes != meteredBytes)
    #expect(originalBytes != outlinedBytes)
}

/// Render the app's retained-list warning without AppKit-backed List placeholders.
@MainActor
@Test func refreshFailureBannerHasVisibleText() throws {
    let failed = ImageRenderer(content: RefreshErrorBanner(message: "Update unavailable")
        .frame(width: 320, height: 50))
    let recovered = ImageRenderer(content: RefreshErrorBanner(message: "Try again")
        .frame(width: 320, height: 50))
    let first = try #require(failed.cgImage)
    let second = try #require(recovered.cgImage)
    #expect(
        NSBitmapImageRep(cgImage: first).representation(using: .png, properties: [:])
        != NSBitmapImageRep(cgImage: second).representation(using: .png, properties: [:])
    )
}

/// Detail intensity and leaderboard destinations render without a selected profile.
@MainActor
@Test(arguments: [1, 2])
func detailVisualStates(_ songNumber: Int) throws {
    let song = try fixtureSong(songNumber)
    _ = try render(NavigationStack {
        SongDetailScreen(song: song, session: offlineSession())
    })
}

/// Pagination/footer states remain visible at both score and empty boundaries.
@MainActor
@Test(arguments: ScoreScenario.allCases)
func soloLeaderboardVisualStates(_ scenario: ScoreScenario) throws {
    let state: SoloLeaderboardScreen.LoadState
    switch scenario {
    case .loading: state = .loading
    case .populated: state = .loaded(try fixtureLeaderboard(visible: 25))
    case .offline: state = .loaded(try fixtureLeaderboard(visible: 25, stale: true))
    case .empty: state = .loaded(try fixtureLeaderboard(visible: 0))
    case .failure: state = .failed("Synthetic leaderboard outage")
    }
    let song = try fixtureSong()
    _ = try render(NavigationStack {
        SoloLeaderboardScreen(
            song: song, instrument: .lead, session: offlineSession(),
            initialPage: 1, path: .constant([.detail(song), .leaderboard(song, .lead, 1)]),
            initialState: state
        )
    })
}

/// A scene's client remains identical across navigation within that process.
@MainActor
@Test func sceneReusesOnePublicationClient() throws {
    let expected = try FestivalAPI()
    let session = FestivalSession(factory: { expected })
    #expect(try session.client() === expected)
    #expect(try session.client() === expected)
}

/// A rendered original image differs from an unavailable-art placeholder.
@MainActor
@Test func artworkTilePreparesBoundedVisualContent() async throws {
    let asset = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let data = try Data(contentsOf: asset)
    let session = offlineSession()
    let tile = ArtworkTile(raw: nil, session: session, size: 56)
    let prepared = try await tile.prepare(data, maxPixels: 32)
    #expect(prepared.image.width == 32 && prepared.image.height == 32)
    await #expect(throws: FestivalAPIError.invalidArtwork) {
        try await tile.prepare(Data("invalid".utf8), maxPixels: 32)
    }

    let rendered = ImageRenderer(content: ArtworkTile(
        raw: nil, session: session, size: 56, previewImage: prepared.image
    ))
    let empty = ImageRenderer(content: ArtworkTile(raw: nil, session: session, size: 56))
    let displayed = try #require(rendered.cgImage)
    let fallback = try #require(empty.cgImage)
    let artworkPNG = try #require(NSBitmapImageRep(cgImage: displayed).representation(
        using: .png, properties: [:]
    ))
    let fallbackPNG = try #require(NSBitmapImageRep(cgImage: fallback).representation(
        using: .png, properties: [:]
    ))
    #expect(displayed.width == 56 && displayed.height == 56)
    #expect(artworkPNG != fallbackPNG)

    let emptyString = ImageRenderer(content: ArtworkTile(raw: "", session: session, size: 56))
    let emptyImage = try #require(emptyString.cgImage)
    let emptyPNG = try #require(
        NSBitmapImageRep(cgImage: emptyImage)
            .representation(using: .png, properties: [:])
    )
    #expect(emptyPNG == fallbackPNG)
}

/// A hosted tile downloads once, then reuses process memory on a second visit.
@MainActor
@Test func artworkTileLoadsOnlyOncePerSession() async throws {
    let asset = try #require(Bundle.module.url(forResource: "pulse", withExtension: "png"))
    let transport = ArtworkFixtureTransport(data: try Data(contentsOf: asset))
    let client = try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:8765")!)
    let cache = ArtworkCache(transport: transport)
    let session = FestivalSession(factory: { client }, artwork: cache)
    let tile = ArtworkTile(raw: "/__fixture__/art/pulse.png", session: session, size: 56)
    await tile.load()
    let url = try #require(try await client.artworkURL("/__fixture__/art/pulse.png"))
    #expect((try await cache.load(url)).fromMemory)
    #expect(await transport.requestCount() == 1)
}

/// Distinct typed route paths render different content, not the Songs root.
@MainActor
@Test func nestedSongRoutesRenderDifferentDestinations() async throws {
    let song = try fixtureSong()
    func snapshot(_ path: [SongRoute]) async throws -> Data {
        let host = NSHostingView(rootView: SongNavigationRoot(
            session: offlineSession(), path: .constant(path),
            searchText: .constant(""), settledSearch: .constant("")
        ))
        host.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        host.layoutSubtreeIfNeeded()
        for _ in 0..<10 {
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded()
        }
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
    let detailPNG = try await snapshot([.detail(song)])
    let scoresPNG = try await snapshot([.detail(song), .leaderboard(song, .lead, 1)])
    #expect(detailPNG != scoresPNG)
}
