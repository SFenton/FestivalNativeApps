import Foundation
import Testing
@testable import FestivalCore

/// Item Shop availability (web `shopAvailability`): independent Available / Not
/// Available categories, both off hides everything, one off needs a validated feed.
@Test func shopAvailabilityFiltersMatchSourceAndRejectAbsentFeed() throws {
    let songs = try JSONDecoder().decode(SongsResponse.self, from: Data("""
    {"count":3,"songs":[
      {"songId":"new","title":"New","artist":"Fixture"},
      {"songId":"leaving","title":"Leaving","artist":"Fixture"},
      {"songId":"outside","title":"Outside","artist":"Fixture"}
    ]}
    """.utf8))
    try songs.validate()
    let shop = try JSONDecoder().decode(ShopResponse.self, from: Data("""
    {"count":2,"songs":[
      {"songId":"new","title":"New","artist":"Fixture",
       "shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/new",
       "leavingTomorrow":false,"isNew":true},
      {"songId":"leaving","title":"Leaving","artist":"Fixture",
       "shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/leaving",
       "leavingTomorrow":true,"isNew":false}
    ]}
    """.utf8))
    try shop.validate()
    let offers = Dictionary(uniqueKeysWithValues: shop.songs.map { ($0.songId, $0) })
    let available = SongShopFilter.availableOnly
    let unavailable = SongShopFilter(available: false, unavailable: true)
    let none = SongShopFilter(available: false, unavailable: false)

    #expect(!SongShopFilter().isActive && !SongShopFilter().needsShopFeed)
    #expect(try SongShopFilter().filtered(songs.songs, offersById: nil) == songs.songs)
    #expect(none.isActive && !none.needsShopFeed)
    #expect(try none.filtered(songs.songs, offersById: nil).isEmpty)
    #expect(throws: FestivalAPIError.invalidShop) {
        try available.filtered(songs.songs, offersById: nil)
    }
    #expect(throws: FestivalAPIError.invalidShop) {
        try unavailable.filtered(songs.songs, offersById: nil)
    }
    #expect(try available.filtered(songs.songs, offersById: offers).map(\.songId)
            == ["new", "leaving"])
    #expect(try unavailable.filtered(songs.songs, offersById: offers).map(\.songId)
            == ["outside"])
    #expect(try available.filtered(songs.songs, offersById: [:]).isEmpty)
    #expect(try unavailable.filtered(songs.songs, offersById: [:]) == songs.songs)
    #expect(songs.songs.map(\.songId) == ["new", "leaving", "outside"])
}

/// Shop membership, sorting and badges must not cross observed publications.
@Test func shopPublicationMatchPreservesValidatedEmptyWithoutMixingGenerations() {
    #expect(SongShopPublicationPolicy.matches(catalogue: 7, shop: 7, current: 7))
    #expect(SongShopPublicationPolicy.matches(catalogue: 8, shop: 8, current: 8))
    #expect(!SongShopPublicationPolicy.matches(catalogue: 7, shop: nil, current: 7))
    #expect(!SongShopPublicationPolicy.matches(catalogue: 7, shop: 7, current: nil))
    #expect(!SongShopPublicationPolicy.matches(catalogue: 7, shop: 8, current: 8))
    #expect(!SongShopPublicationPolicy.matches(catalogue: 8, shop: 7, current: 8))
    #expect(!SongShopPublicationPolicy.matches(catalogue: 7, shop: 7, current: 8))
}

/// The same observed-generation rule must reject a newer player score index on older Songs.
@Test func relatedPublicationMatchRejectsMissingAndMixedScoreObservations() {
    #expect(SongRelatedPublicationPolicy.matches(
        catalogue: 7, related: 7, current: 7
    ))
    #expect(SongRelatedPublicationPolicy.matches(
        catalogue: 8, related: 8, current: 8
    ))
    #expect(!SongRelatedPublicationPolicy.matches(
        catalogue: 7, related: 8, current: 8
    ))
    #expect(!SongRelatedPublicationPolicy.matches(
        catalogue: 8, related: 7, current: 8
    ))
    #expect(!SongRelatedPublicationPolicy.matches(
        catalogue: 7, related: 7, current: 8
    ))
    #expect(!SongRelatedPublicationPolicy.matches(
        catalogue: 7, related: nil, current: 7
    ))
    #expect(!SongRelatedPublicationPolicy.matches(
        catalogue: 7, related: 7, current: nil
    ))
}
