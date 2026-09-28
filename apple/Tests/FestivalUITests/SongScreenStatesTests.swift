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

enum ScoreAccuracyScenario: CaseIterable, Sendable {
    case missing, unknownFullCombo, nonFullComboLow, fullCombo, fullComboWithoutAccuracy
}

/// Each offline banner exposes the response's actual provenance, not just recency.
@Test func offlineLabelsDistinguishUnverifiedFromPublicationBoundData() {
    #expect(OfflineDisclosure.label(.songs, publicationId: nil)
            == "Offline - last seen songs (publication unverified)")
    #expect(OfflineDisclosure.label(.scores, publicationId: nil)
            == "Offline - last seen scores (publication unverified)")
    #expect(OfflineDisclosure.label(.paths, publicationId: nil)
            == "Offline - last seen paths (publication unverified)")
    #expect(OfflineDisclosure.label(.shop, publicationId: nil)
            == "Offline - last seen shop (publication unverified)")
    #expect(OfflineDisclosure.label(.songs, publicationId: 7)
            == "Offline - showing cached songs")
    #expect(OfflineDisclosure.label(.scores, publicationId: 7)
            == "Offline - showing cached scores")
    #expect(OfflineDisclosure.label(.paths, publicationId: 7)
            == "Offline - showing cached paths")
    #expect(OfflineDisclosure.label(.shop, publicationId: 7)
            == "Offline - showing cached shop")
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

/// Build one synthetic score state without exposing live player identity or network.
///
/// - Parameters:
///   - accuracy: Expanded service percentage, or nil when it was not reported.
///   - fullCombo: Explicit flag, or nil when its status is unknown.
/// - Returns: A validated, offline-only preview payload.
/// - Throws: Invalid test JSON or leaderboard shape.
private func fixtureAccuracyScore(
    accuracy: Int?, fullCombo: Bool?
) throws -> LeaderboardPayload {
    let accuracyField = accuracy.map { ",\"accuracy\":\($0)" } ?? ""
    let comboField = fullCombo.map { ",\"isFullCombo\":\($0 ? "true" : "false")" } ?? ""
    let data = Data("""
    {"songId":"fixture-1","instrument":"Solo_Guitar","count":1,
     "localEntries":1,"totalEntries":1,"entries":[{
       "accountId":"fixture-player-1","displayName":"Fixture Player",
       "score":99900,"rank":1\(accuracyField)\(comboField)}]}
    """.utf8)
    let result = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
    try result.validate(songId: "fixture-1", instrument: .lead)
    return LeaderboardPayload(
        page: 1, leaderboard: result, publicationId: 7,
        observedPublicationId: 7, isStale: false
    )
}

/// Any unexpected request fails, preventing test screenshots from using the network.
@MainActor
private func offlineSession() -> FestivalSession {
    FestivalSession(factory: { throw FestivalAPIError.invalidResource })
}

/// Force `festivalGlass` surfaces onto their deterministic, opaque fallback.
///
/// Real Liquid Glass (`glassEffect`, iOS/macOS 26+) is a live compositor effect
/// that does not reliably reproduce through `NSHostingView.cacheDisplay`, so
/// pixel-diffed hosted tests opt into the same "Increase Contrast" fallback a
/// person can already choose in Settings.
///
/// - Returns: A throwaway `UserDefaults` suite with `moreContrast` enabled.
@MainActor
private func deterministicGlassDefaults() -> UserDefaults {
    let suiteName = "fst-glass-fallback-\(UUID().uuidString)"
    let storage = UserDefaults(suiteName: suiteName)!
    storage.set(true, forKey: "fst.accessibility.moreContrast")
    return storage
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
    let unverifiedOffline = CatalogPayload(
        catalog: catalog.catalog, publicationId: nil,
        observedPublicationId: 7, isStale: true
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
    // Online-only (2026-09-27): Songs no longer renders a distinct warm-cache
    // disclosure for `isStale`, so an unverified-live payload and its stale
    // counterpart now paint identically.
    #expect(try snapshot(unverifiedOffline) == snapshot(unpinned))
}

/// Offline scores have a different visible warning when bytes were never pinned.
@MainActor
@Test func unpinnedScoresHaveAVisibleProvenanceWarning() throws {
    let pinned = try fixtureLeaderboard(visible: 1)
    let unpinned = LeaderboardPayload(
        page: pinned.page, leaderboard: pinned.leaderboard,
        publicationId: nil, observedPublicationId: 7, isStale: false
    )
    let unverifiedOffline = LeaderboardPayload(
        page: pinned.page, leaderboard: pinned.leaderboard,
        publicationId: nil, observedPublicationId: 7, isStale: true
    )
    let verifiedOffline = LeaderboardPayload(
        page: pinned.page, leaderboard: pinned.leaderboard,
        publicationId: 7, observedPublicationId: 7, isStale: true
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
    #expect(try snapshot(unverifiedOffline) != snapshot(unpinned))
    #expect(try snapshot(unverifiedOffline) != snapshot(verifiedOffline))
}

/// Draw the real row body: high contrast and an instrument must change pixels.
@MainActor
@Test func songRowShowsMeterAndContrastOnDemand() throws {
    let song = try fixtureSong()
    let session = offlineSession()
    // Real AppKit hosting (not a bare ImageRenderer) is required once the row
    // paints on a Liquid Glass/material surface; see NativeHostedSnapshot.swift.
    func snapshot(instrument: Instrument?, highContrast: Bool) throws -> Data {
        let host = nativeHostedView(
            SongRowView(
                song: song, instrument: instrument, session: session, highContrast: highContrast
            )
            .frame(width: 420, height: 100)
            // Force the deterministic glass fallback: real Liquid Glass compositing
            // does not reliably reproduce on an offscreen `cacheDisplay` bitmap.
            .defaultAppStorage(deterministicGlassDefaults()),
            size: CGSize(width: 420, height: 100)
        )
        let image = try nativeHostedImage(host)
        return try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
    }
    let originalBytes = try snapshot(instrument: nil, highContrast: false)
    let meteredBytes = try snapshot(instrument: .lead, highContrast: false)
    let outlinedBytes = try snapshot(instrument: nil, highContrast: true)
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

/// The same preview control paints loading, scores, empty, stale and retry states.
@MainActor
@Test func songDetailPreviewRendersAllLocalStates() throws {
    let song = try fixtureSong()
    let session = offlineSession()
    func snapshot(_ state: SongScorePreview.LoadState) throws -> Data {
        let host = nativeHostedView(
            NavigationStack {
                SongScorePreview(
                    song: song, instrument: .lead, session: session, initialState: state
                )
                .frame(width: 420, height: 510, alignment: .top)
            }
            .defaultAppStorage(deterministicGlassDefaults()),
            size: CGSize(width: 420, height: 510)
        )
        let image = try nativeHostedImage(host)
        return try #require(
            NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        )
    }
    let loading = try snapshot(.loading)
    let populated = try snapshot(.loaded(fixtureLeaderboard(visible: 10)))
    let empty = try snapshot(.loaded(fixtureLeaderboard(visible: 0)))
    let stale = try snapshot(.loaded(fixtureLeaderboard(visible: 10, stale: true)))
    let failed = try snapshot(.failed("Fixture unavailable"))
    #expect(loading != populated)
    #expect(populated != empty)
    // Online-only (2026-09-27): the preview no longer renders a distinct
    // warm-cache disclosure for `isStale`, so it paints identically to a
    // verified response with the same rows.
    #expect(populated == stale)
    #expect(failed != loading)
}

/// Unknown FC is graded, explicit FC has gold, and missing data paints neither.
@MainActor
@Test(arguments: ScoreAccuracyScenario.allCases)
func scoreAccuracyBadgeRendersSourceStates(_ scenario: ScoreAccuracyScenario) throws {
    let (accuracy, fullCombo): (Int?, Bool?) = switch scenario {
    case .missing: (nil, nil)
    case .unknownFullCombo: (980_000, nil)
    case .nonFullComboLow: (0, false)
    case .fullCombo: (980_000, true)
    case .fullComboWithoutAccuracy: (nil, true)
    }
    let payload = try fixtureAccuracyScore(accuracy: accuracy, fullCombo: fullCombo)
    let song = try fixtureSong()
    let host = nativeHostedView(
        NavigationStack {
            SongScorePreview(
                song: song, instrument: .lead,
                session: offlineSession(), initialState: .loaded(payload)
            )
            .frame(width: 420, height: 280, alignment: .top)
        }
        .defaultAppStorage(deterministicGlassDefaults()),
        size: CGSize(width: 420, height: 280)
    )
    let image = try nativeHostedImage(host)
    let bitmap = NSBitmapImageRep(cgImage: image)
    var gold = 0
    var green = 0
    var red = 0
    var sampled = 0
    for y in 0..<image.height {
        for x in 0..<image.width {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            sampled += 1
            let r = color.redComponent
            let g = color.greenComponent
            let b = color.blueComponent
            if r > 0.86 && g > 0.66 && b < 0.27 { gold += 1 }
            if g > 0.18 && g > r + 0.09 && g > b + 0.015 { green += 1 }
            if r > 0.17 && r > g + 0.08 && r > b + 0.05 { red += 1 }
        }
    }
    #expect(sampled == image.width * image.height)
    switch scenario {
    case .missing:
        #expect(gold == 0)
        #expect(green == 0)
        #expect(red == 0)
    case .unknownFullCombo:
        #expect(gold == 0)
        #expect(green > 80)
    case .nonFullComboLow:
        #expect(gold == 0)
        #expect(red > 80)
    case .fullCombo, .fullComboWithoutAccuracy:
        #expect(gold > 40)
        #expect(green == 0)
    }
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
            initialPage: 1, path: .constant([.songDetail(song), .songLeaderboard(song, .lead, 1)]),
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
    func snapshot(_ path: [AppRoute]) async throws -> Data {
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
    let detailPNG = try await snapshot([.songDetail(song)])
    let scoresPNG = try await snapshot([.songDetail(song), .songLeaderboard(song, .lead, 1)])
    #expect(detailPNG != scoresPNG)
}
