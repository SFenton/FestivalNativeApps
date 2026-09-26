import Foundation
import Testing
@testable import FestivalCore

private let shopPublication = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
"readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
""".utf8)

private let unpinnedShopPublication = Data("""
{"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
"readyForPinning":false,"pinningEnabled":false,"unreadySurfaces":[]}
""".utf8)

private let shopJSON = Data("""
{"count":2,"lastUpdated":"2026-09-25T00:00:00Z","newSongs":["fixture-pulse"],
"songs":[
  {"songId":"fixture-pulse","title":"Pulse","artist":"Synthetic Quartet",
   "year":2026,"albumArt":"/__fixture__/art/pulse.png",
   "shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/fixture-pulse",
   "leavingTomorrow":false,"isNew":true},
  {"songId":"fixture-orbit","title":"Orbit","artist":"Synthetic Quartet",
   "albumArt":"/__fixture__/art/orbit.png",
   "shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/fixture-orbit",
   "leavingTomorrow":true,"isNew":false}
]}
""".utf8)

@Test func shopCatalogValidatesOfficialLinksAndStableRows() throws {
    let response = try JSONDecoder().decode(ShopResponse.self, from: shopJSON)
    try response.validate()
    #expect(response.count == 2)
    #expect(response.sortedSongs().map(\.songId) == ["fixture-orbit", "fixture-pulse"])
    #expect(response.songs[0].isNew && response.songs[1].leavingTomorrow)
    let original = String(decoding: shopJSON, as: UTF8.self)
    for (old, changed) in [
        ("\"count\":2", "\"count\":3"),
        ("\"fixture-orbit\",\"title\"", "\"fixture-pulse\",\"title\""),
        ("https://www.fortnite.com/item-shop/jam-tracks/fixture-orbit",
         "http://www.fortnite.com/item-shop/jam-tracks/fixture-orbit"),
        ("https://www.fortnite.com/item-shop/jam-tracks/fixture-orbit",
         "https://www.fortnite.com.evil.example/item-shop/jam-tracks/fixture-orbit"),
        ("https://www.fortnite.com/item-shop/jam-tracks/fixture-orbit",
         "https://www.fortnite.com/other/fixture-orbit"),
        ("https://www.fortnite.com/item-shop/jam-tracks/fixture-orbit",
         "https://user@www.fortnite.com/item-shop/jam-tracks/fixture-orbit"),
        ("https://www.fortnite.com/item-shop/jam-tracks/fixture-orbit",
         "https://www.fortnite.com/item-shop/jam-tracks/fixture-orbit?redirect=x"),
    ] {
        let altered = Data(original.replacingOccurrences(of: old, with: changed).utf8)
        let invalid = try JSONDecoder().decode(ShopResponse.self, from: altered)
        #expect(throws: FestivalAPIError.invalidShop) { try invalid.validate() }
    }
    #expect(FestivalAPIError.invalidShop.errorDescription?.contains("Item Shop") == true)
}

@Test func shopHighlightPolicyKeepsSourcePrecedenceAndSavedSettings() throws {
    let offers = try JSONDecoder().decode(ShopResponse.self, from: shopJSON).songs
    #expect(ShopPresentationPolicy.highlight(
        for: offers[0], hidden: false, highlightingDisabled: false
    ) == .new)
    #expect(ShopPresentationPolicy.highlight(
        for: offers[1], hidden: false, highlightingDisabled: false
    ) == .leavingTomorrow)
    #expect(ShopPresentationPolicy.highlight(
        for: nil, hidden: false, highlightingDisabled: false
    ) == nil)
    #expect(ShopPresentationPolicy.highlight(
        for: offers[0], hidden: true, highlightingDisabled: false
    ) == nil)
    #expect(ShopPresentationPolicy.highlight(
        for: offers[1], hidden: false, highlightingDisabled: true
    ) == nil)
    #expect(ShopHighlight.new.label == "New")
    #expect(ShopHighlight.leavingTomorrow.label == "Leaving Tomorrow")
    let both = try JSONDecoder().decode(ShopResponse.self, from: Data(
        String(decoding: shopJSON, as: UTF8.self)
            .replacingOccurrences(
                of: "\"leavingTomorrow\":true,\"isNew\":false",
                with: "\"leavingTomorrow\":true,\"isNew\":true"
            ).utf8
    ))
    #expect(ShopPresentationPolicy.highlight(
        for: both.songs[1], hidden: false, highlightingDisabled: false
    ) == .leavingTomorrow)
}

@Test func shopCatalogPinsPublicationAndRevalidatesETag() async throws {
    let transport = FixtureTransport([
        HTTPResult(status: 200, data: shopPublication),
        HTTPResult(status: 200, data: shopJSON, headers: [
            "X-FST-Publication-Id": "7", "ETag": "\"shop-revision\"",
        ]),
        HTTPResult(status: 304, data: Data(), headers: ["X-FST-Publication-Id": "7"]),
    ])
    let client = try FestivalAPI(transport: transport)
    let first = try await client.shop()
    let second = try await client.shop()
    #expect(first.sortedSongs.count == 2 && second.sortedSongs.count == 2)
    #expect(first.publicationId == 7 && !second.isStale)
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests[1].url?.path == "/api/shop")
    #expect(requests[1].value(forHTTPHeaderField: "X-FST-Publication-Id") == "7")
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == "\"shop-revision\"")
    #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-API-Key") == nil })
}

@Test func shopCatalogUnpinnedWarmOfflineExpiresOnColdLaunch() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedShopPublication)),
        .success(HTTPResult(status: 200, data: shopJSON)),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let warm = try FestivalAPI(transport: transport)
    let live = try await warm.shop()
    let offline = try await warm.shop()
    #expect(!live.isStale && live.publicationId == nil)
    #expect(offline.isStale && offline.publicationId == nil)
    #expect(offline.observedPublicationId == 7 && offline.shop.count == 2)
    let cold = try FestivalAPI(transport: FixtureTransport(results: [
        .failure(URLError(.notConnectedToInternet)),
    ]))
    await #expect(throws: URLError.self) { try await cold.shop() }
}

@Test func shopCatalogInvalidBytesNeverBecomeOfflineSuccess() async throws {
    let unsafe = Data(String(decoding: shopJSON, as: UTF8.self)
        .replacingOccurrences(
            of: "https://www.fortnite.com/item-shop/jam-tracks/fixture-orbit",
            with: "https://other.example/fixture-orbit"
        ).utf8)
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: unpinnedShopPublication)),
        .success(HTTPResult(status: 200, data: unsafe)),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidShop) { try await client.shop() }
    await #expect(throws: URLError.self) { try await client.shop() }
}

@Test func shopCatalogOversizeCannotEnterPinnedMemory() async throws {
    let transport = FixtureTransport(results: [
        .success(HTTPResult(status: 200, data: shopPublication)),
        .success(HTTPResult(
            status: 200, data: Data(repeating: 0, count: 4_000_001),
            headers: ["X-FST-Publication-Id": "7", "ETag": "\"oversized\""]
        )),
        .failure(URLError(.notConnectedToInternet)),
    ])
    let client = try FestivalAPI(transport: transport)
    await #expect(throws: FestivalAPIError.invalidShop) { try await client.shop() }
    await #expect(throws: URLError.self) { try await client.shop() }
    let requests = await transport.recorded()
    #expect(requests.count == 3)
    #expect(requests[2].value(forHTTPHeaderField: "If-None-Match") == nil)
}
