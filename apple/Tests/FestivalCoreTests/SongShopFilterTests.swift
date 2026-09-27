import Foundation
import Testing
@testable import FestivalCore

/// Shop membership and Leaving Tomorrow must be distinct, validated conditions.
@Test func shopSongFiltersMatchSourceAndRejectAbsentFeed() throws {
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
    let inShop = SongShopFilter(inShop: true)
    let leaving = SongShopFilter(leavingTomorrow: true)

    #expect(!SongShopFilter().isActive)
    #expect(try SongShopFilter().filtered(songs.songs, offersById: nil) == songs.songs)
    #expect(throws: FestivalAPIError.invalidShop) {
        try inShop.filtered(songs.songs, offersById: nil)
    }
    #expect(throws: FestivalAPIError.invalidShop) {
        try leaving.filtered(songs.songs, offersById: nil)
    }
    #expect(try inShop.filtered(songs.songs, offersById: offers).map(\.songId)
            == ["new", "leaving"])
    #expect(try leaving.filtered(songs.songs, offersById: offers).map(\.songId)
            == ["leaving"])
    #expect(try SongShopFilter(inShop: true, leavingTomorrow: true)
        .filtered(songs.songs, offersById: offers).map(\.songId) == ["leaving"])
    #expect(try inShop.filtered(songs.songs, offersById: [:]).isEmpty)
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
