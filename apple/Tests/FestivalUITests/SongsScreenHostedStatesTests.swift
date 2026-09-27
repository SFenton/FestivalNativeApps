#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Distinguish real validated Shop membership from a saved, paused sort.
private struct HostedSongsScenario {
    let name: String
    let shop: HostedShopScenario
    let mode: SongSortMode
    let hideShop: Bool
    let search: String
    let filter: Instrument?
    let stale: Bool
    let size: CGSize
    var shopFilter = SongShopFilter()
    var selectPlayer = false
    var restorePlayerLoading = false
}

/// Decode one coherent selected player without adding account fixture bytes to the app.
///
/// - Returns: The original checked-in compact player envelope.
/// - Throws: A missing or malformed synthetic profile fixture.
private func hostedFilterPlayer() throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent(
        "contracts/fixtures/player-demo.json"
    ))
    guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let profiles = envelope["profiles"] as? [String: Any],
          let player = profiles["fixture-player-2"] as? [String: Any] else {
        throw FestivalAPIError.invalidPlayerProfile
    }
    return try JSONSerialization.data(withJSONObject: player)
}

/// Render a publication-backed Songs list without mounting the active network tasks.
///
/// - Parameters:
///   - scenario: Saved sort, effective Shop, search, chart and freshness state.
///   - fixtures: Original committed Shop and catalogue wire bytes.
/// - Returns: Native pixels and rendered red/gold Shop status.
/// - Throws: A failed explicit Shop outcome, invalid catalogue or missing List.
@MainActor
private func hostedSongsState(
    _ scenario: HostedSongsScenario, fixtures: (offers: Data, catalogue: Data)
) async throws -> (data: Data, fills: (gold: Int, green: Int, red: Int)) {
    let suiteName = "fst-songs-host-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.accessibility.lessTransparency")
    storage.set(scenario.mode.rawValue, forKey: "fst.songs.sortMode")
    storage.set(true, forKey: "fst.songs.sortAscending")
    storage.set(scenario.hideShop, forKey: "fst.settings.hideShop")
    storage.set(scenario.shopFilter.inShop, forKey: "fst.songs.filterInShop")
    storage.set(
        scenario.shopFilter.leavingTomorrow,
        forKey: "fst.songs.filterLeavingTomorrow"
    )
    if scenario.restorePlayerLoading {
        let selection = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
        {"accountId":"fixture-player-2","displayName":"Fixture Player 2"}
        """.utf8))
        let identity = try SelectedPlayerIdentity(searchResult: selection)
        storage.set(
            try JSONEncoder().encode(identity),
            forKey: SelectedPlayerIdentity.storageKey
        )
    }

    let transport = HostedShopTransport(
        scenario: scenario.shop, offers: fixtures.offers, catalogue: fixtures.catalogue,
        player: scenario.selectPlayer ? try hostedFilterPlayer() : nil
    )
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(
        factory: { client },
        selectionStorage: scenario.restorePlayerLoading ? storage : nil
    )
    if scenario.shop == .unavailable {
        await #expect(throws: FestivalAPIError.unavailable(retryAfter: nil)) {
            try await session.shop()
        }
        #expect(session.currentShop == nil && session.shopError != nil)
    } else {
        let feed = try await session.shop()
        #expect(feed.shop.count == (scenario.shop == .empty ? 0 : 2))
    }
    let loaded = try await session.catalog()
    #expect(loaded.catalog.count == 2)
    if scenario.selectPlayer {
        let selection = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
        {"accountId":"fixture-player-2","displayName":"Fixture Player 2"}
        """.utf8))
        try session.selectPlayer(selection, from: try await session.viewPlayer(selection))
        #expect(session.playerLoadState == .available)
    }
    if scenario.restorePlayerLoading {
        #expect(session.selectedPlayer?.accountId == "fixture-player-2")
        #expect(session.playerLoadState == .loading)
    }
    let payload = scenario.stale
        ? CatalogPayload(
            catalog: loaded.catalog, publicationId: nil,
            observedPublicationId: loaded.observedPublicationId, isStale: true
        ) : loaded
    let host = nativeHostedView(
        NavigationStack {
            SongsScreen(
                session: session, initialState: .loaded(payload),
                searchText: .constant(scenario.search),
                settledSearch: .constant(scenario.search),
                selectedInstrument: .constant(scenario.filter),
                isVisible: false, openShop: {}
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
        .tint(BrandTokens.accentBlue),
        size: scenario.size
    )
    let window = nativeHostedWindow(host, size: scenario.size)
    #expect(!window.isVisible)
    let image = try nativeHostedImage(host)
    let scale = CGFloat(image.width) / scenario.size.width
    #expect((1...3).contains(scale))
    #expect(abs(CGFloat(image.height) / scenario.size.height - scale) < 0.02)
    #expect(nativeHostedControlPixels(image).bright > 20)
    if scenario.restorePlayerLoading {
        let rowEdges = try #require(image.cropping(to: CGRect(
            x: 0, y: CGFloat(image.height) * 0.14,
            width: CGFloat(image.width) * 0.06,
            height: CGFloat(image.height) * 0.32
        ).integral))
        let accents = nativeHostedStatusPixels(rowEdges)
        #expect(accents.red > 10 && accents.gold == 0)
    }
    let paths = await transport.recordedPaths()
    #expect(paths.contains("/api/songs"))
    #expect(paths.allSatisfy {
        $0 == "/api/shop" || $0 == "/api/songs"
            || (scenario.selectPlayer && $0 == "/api/player/fixture-player-2")
    })
    let screenshot = try nativeHostedPNG(
        image, filename: "songs-host-\(scenario.name).png",
        environment: "FST_SONGS_RENDER_OUT"
    )
    withExtendedLifetime(window) {}
    return (screenshot, nativeHostedStatusPixels(image))
}

/// Shop grouping, paused preferences, true empty/error, search and offline differ.
@MainActor
@Test func songsListPaintsShopAndSearchDependentStates() async throws {
    let fixtures = try shopFixtureBytes()
    let wide = CGSize(width: 820, height: 1180)
    let cases: [HostedSongsScenario] = [
        HostedSongsScenario(
            name: "grouped-shop", shop: .populated, mode: .shop, hideShop: false,
            search: "", filter: nil, stale: false, size: wide
        ),
        HostedSongsScenario(
            name: "shop-hidden", shop: .populated, mode: .shop, hideShop: true,
            search: "", filter: nil, stale: false, size: wide
        ),
        HostedSongsScenario(
            name: "shop-unavailable", shop: .unavailable, mode: .shop, hideShop: false,
            search: "", filter: nil, stale: false, size: wide
        ),
        HostedSongsScenario(
            name: "shop-empty", shop: .empty, mode: .shop, hideShop: false,
            search: "", filter: nil, stale: false, size: wide
        ),
        HostedSongsScenario(
            name: "no-results", shop: .populated, mode: .title, hideShop: false,
            search: "no-such-track", filter: nil, stale: false, size: wide
        ),
        HostedSongsScenario(
            name: "bass-chart", shop: .populated, mode: .title, hideShop: false,
            search: "", filter: .bass, stale: false, size: wide
        ),
        HostedSongsScenario(
            name: "last-seen-unverified", shop: .populated, mode: .title, hideShop: false,
            search: "", filter: nil, stale: true, size: wide
        ),
        HostedSongsScenario(
            name: "compact-grouped", shop: .populated, mode: .shop, hideShop: false,
            search: "", filter: nil, stale: false, size: CGSize(width: 390, height: 844)
        ),
        HostedSongsScenario(
            name: "filter-selected-default", shop: .populated, mode: .title,
            hideShop: false, search: "", filter: nil, stale: false,
            size: CGSize(width: 390, height: 844), selectPlayer: true
        ),
        HostedSongsScenario(
            name: "filter-leaving", shop: .populated, mode: .title,
            hideShop: false, search: "", filter: nil, stale: false,
            size: CGSize(width: 390, height: 844),
            shopFilter: SongShopFilter(leavingTomorrow: true), selectPlayer: true
        ),
        HostedSongsScenario(
            name: "filter-restored-loading", shop: .populated, mode: .title,
            hideShop: false, search: "", filter: nil, stale: false,
            size: CGSize(width: 390, height: 844),
            shopFilter: SongShopFilter(leavingTomorrow: true),
            restorePlayerLoading: true
        ),
        HostedSongsScenario(
            name: "filter-anonymous-paused", shop: .populated, mode: .title,
            hideShop: false, search: "", filter: nil, stale: false,
            size: CGSize(width: 390, height: 844),
            shopFilter: SongShopFilter(inShop: true)
        ),
        HostedSongsScenario(
            name: "filter-hidden-paused", shop: .populated, mode: .title,
            hideShop: true, search: "", filter: nil, stale: false,
            size: CGSize(width: 390, height: 844),
            shopFilter: SongShopFilter(inShop: true), selectPlayer: true
        ),
        HostedSongsScenario(
            name: "filter-unavailable-paused", shop: .unavailable, mode: .title,
            hideShop: false, search: "", filter: nil, stale: false,
            size: CGSize(width: 390, height: 844),
            shopFilter: SongShopFilter(inShop: true), selectPlayer: true
        ),
        HostedSongsScenario(
            name: "filter-empty", shop: .empty, mode: .title,
            hideShop: false, search: "", filter: nil, stale: false,
            size: CGSize(width: 390, height: 844),
            shopFilter: SongShopFilter(inShop: true), selectPlayer: true
        ),
    ]
    var images: [String: Data] = [:]
    var fills: [String: (gold: Int, green: Int, red: Int)] = [:]
    for scenario in cases {
        let rendered = try await hostedSongsState(scenario, fixtures: fixtures)
        images[scenario.name] = rendered.data
        fills[scenario.name] = rendered.fills
    }
    #expect((fills["grouped-shop"]?.red ?? 0) > 10)
    #expect((fills["grouped-shop"]?.gold ?? 0) > 10)
    #expect(fills["shop-hidden"]?.red == 0)
    #expect(fills["shop-unavailable"]?.red == 0)
    #expect(fills["shop-empty"]?.red == 0)
    #expect(images["grouped-shop"] != images["shop-hidden"])
    #expect(images["shop-empty"] != images["shop-unavailable"])
    #expect(images["grouped-shop"] != images["no-results"])
    #expect(images["grouped-shop"] != images["bass-chart"])
    #expect(images["grouped-shop"] != images["last-seen-unverified"])
    #expect(images["filter-leaving"] != images["filter-selected-default"])
    #expect(images["filter-restored-loading"] != images["filter-anonymous-paused"])
    #expect(images["filter-anonymous-paused"] != images["filter-leaving"])
    #expect(images["filter-hidden-paused"] != images["filter-selected-default"])
    #expect(images["filter-empty"] != images["filter-unavailable-paused"])
}

/// A new Shop generation must not filter, sort or badge retained older Songs.
@MainActor
@Test func songsPauseShopDerivedRowsAcrossFailedPublicationRollover() async throws {
    let fixtures = try shopFixtureBytes()
    guard var oneOffer = try JSONSerialization.jsonObject(with: fixtures.offers)
            as? [String: Any],
          let entries = oneOffer["songs"] as? [[String: Any]],
          let pulse = entries.first,
          pulse["songId"] as? String == "fixture-pulse" else {
        throw FestivalAPIError.invalidShop
    }
    oneOffer["songs"] = [pulse]
    oneOffer["count"] = 1
    let transport = HostedShopTransport(
        scenario: .populated, offers: fixtures.offers, catalogue: fixtures.catalogue,
        player: try hostedFilterPlayer(),
        rolloverOffers: try JSONSerialization.data(withJSONObject: oneOffer),
        failSongsAfterRollover: true
    )
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let oldSongs = try await session.catalog()
    #expect(oldSongs.catalog.songs.count == 2)
    #expect(try await session.shop().shop.count == 2)
    let selection = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-2","displayName":"Fixture Player 2"}
    """.utf8))
    try session.selectPlayer(selection, from: try await session.viewPlayer(selection))

    await transport.advancePublication()
    #expect(try await session.refreshPublication().publicationId == 8)
    #expect(session.currentShop == nil && session.playerLoadState == .loading)
    let newShop = try await session.shop()
    #expect(newShop.shop.count == 1 && newShop.observedPublicationId == 8)
    await session.refreshSelectedPlayer()
    #expect(session.playerLoadState == .available)
    await #expect(throws: FestivalAPIError.unavailable(retryAfter: nil)) {
        try await session.catalog()
    }
    #expect(oldSongs.observedPublicationId == 7 && session.publicationId == 8)
    #expect(!SongShopPublicationPolicy.matches(
        catalogue: oldSongs.observedPublicationId,
        shop: newShop.observedPublicationId,
        current: session.publicationId
    ))
    let paths = await transport.recordedGenerationPaths()
    #expect(paths.contains("8:/api/shop"))
    #expect(paths.contains("8:/api/player/fixture-player-2"))
    #expect(paths.contains("8:/api/songs"))

    let suiteName = "fst-songs-rollover-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.songs.filterInShop")
    storage.set(SongSortMode.shop.rawValue, forKey: "fst.songs.sortMode")
    let size = CGSize(width: 820, height: 1180)
    let host = nativeHostedView(
        NavigationStack {
            SongsScreen(
                session: session, initialState: .loaded(oldSongs),
                initialRefreshError: "Fixture catalogue refresh returned HTTP 503",
                isVisible: false, openShop: {}
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
        .tint(BrandTokens.accentBlue),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    #expect(!window.isVisible)
    let image = try nativeHostedImage(host)
    #expect(nativeHostedControlPixels(image).bright > 20)
    // Ignore scored red chips; only Shop accents color the left Song-card edges.
    let rowEdges = try #require(image.cropping(to: CGRect(
        x: 0, y: CGFloat(image.height) * 0.24,
        width: CGFloat(image.width) * 0.06,
        height: CGFloat(image.height) * 0.18
    ).integral))
    let edgeColors = nativeHostedStatusPixels(rowEdges)
    #expect(edgeColors.gold == 0 && edgeColors.red == 0)
    let capture = try nativeHostedPNG(
        image, filename: "songs-host-rollover-shop-join-paused.png",
        environment: "FST_SONGS_RENDER_OUT"
    )
    #expect(!capture.isEmpty)
    withExtendedLifetime(window) {}
}

/// Paint a real selected account's score freshness without issuing page-owned GETs.
///
/// - Parameters:
///   - session: Stored identity with loading, syncing, denied or available scores.
///   - catalog: Response-validated synthetic song list under publication seven.
///   - storage: Isolated Settings flags shared with the offscreen view.
///   - name: Deterministic private visual-state identifier.
/// - Returns: Native pixels and a measured readable warning/status accent.
/// - Throws: Missing AppKit List rows or evidence bytes.
@MainActor
private func selectedProfileSongs(
    session: FestivalSession, catalog: CatalogPayload,
    storage: UserDefaults, name: String
) throws -> (data: Data, fills: (gold: Int, green: Int, red: Int)) {
    let size = CGSize(width: 820, height: 1180)
    let host = nativeHostedView(
        NavigationStack {
            SongsScreen(
                session: session, initialState: .loaded(catalog), isVisible: false
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
        .tint(BrandTokens.accentBlue),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    #expect(!window.isVisible)
    let image = try nativeHostedImage(host)
    #expect(nativeHostedControlPixels(image).bright > 20)
    let bytes = try nativeHostedPNG(
        image, filename: "songs-profile-\(name).png",
        environment: "FST_SONGS_RENDER_OUT"
    )
    withExtendedLifetime(window) {}
    return (bytes, nativeHostedStatusPixels(image))
}

/// Identity-only restore, 202, 403 and recovery must never reuse stale score cards.
@MainActor
@Test func songsListPaintsSelectedProfileLoadingSyncFailureAndRecovery() async throws {
    let suiteName = "fst-songs-profile-host-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.settings.hideShop")
    storage.set(true, forKey: "fst.accessibility.lessTransparency")
    let searchResult = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"fixture-player-1","displayName":"Fixture Player 1"}
    """.utf8))
    let identity = try SelectedPlayerIdentity(searchResult: searchResult)
    storage.set(try JSONEncoder().encode(identity), forKey: SelectedPlayerIdentity.storageKey)
    let transport = ProfileSelectionTransport()
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    #expect(session.selectedPlayer?.accountId == searchResult.accountId)
    #expect(session.playerLoadState == .loading && session.selectedPlayerScores.isEmpty)

    let songs = try JSONDecoder().decode(
        SongsResponse.self, from: shopFixtureBytes().catalogue
    )
    try songs.validate()
    let catalog = CatalogPayload(
        catalog: songs, publicationId: 7, observedPublicationId: 7, isStale: false
    )
    let loading = try selectedProfileSongs(
        session: session, catalog: catalog, storage: storage, name: "loading"
    )
    await transport.syncNextProfile()
    await session.refreshSelectedPlayer()
    #expect(session.playerLoadState == .syncing && session.selectedPlayerScores.isEmpty)
    let syncing = try selectedProfileSongs(
        session: session, catalog: catalog, storage: storage, name: "syncing"
    )
    await transport.setDenied(true)
    await session.refreshSelectedPlayer()
    guard case .failed = session.playerLoadState else {
        Issue.record("Denied profile must not become an anonymous success")
        return
    }
    #expect(session.selectedPlayerScores.isEmpty)
    let denied = try selectedProfileSongs(
        session: session, catalog: catalog, storage: storage, name: "denied"
    )
    await transport.setDenied(false)
    await session.refreshSelectedPlayer()
    #expect(session.playerLoadState == .available)
    #expect(session.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_900)
    let recovered = try selectedProfileSongs(
        session: session, catalog: catalog, storage: storage, name: "available"
    )
    #expect(loading.data != syncing.data && syncing.data != denied.data)
    #expect(denied.data != recovered.data)
    #expect(denied.fills.gold > 10 && recovered.fills.green > 10)

    storage.set(Data("""
    {"accountId":"../other","displayName":"Unsafe"}
    """.utf8), forKey: SelectedPlayerIdentity.storageKey)
    let invalid = FestivalSession(
        factory: { throw FestivalAPIError.invalidResource }, selectionStorage: storage
    )
    #expect(invalid.selectedPlayer == nil)
    #expect(invalid.playerError == FestivalAPIError.invalidSelectedProfile.localizedDescription)
    let rejected = try selectedProfileSongs(
        session: invalid, catalog: catalog, storage: storage, name: "identity-rejected"
    )
    #expect(rejected.fills.gold > 10)
    #expect(rejected.data != loading.data)
}
#endif
