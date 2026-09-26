import Foundation
import Testing
@testable import FestivalCore

/// Four original song fields, including missing year and duration wire values.
private func sortingSongs() throws -> [Song] {
    let bytes = Data("""
    {"count":4,"songs":[
      {"songId":"alpha","title":"Alpha","artist":"Delta","year":2021,"durationSeconds":200},
      {"songId":"beta","title":"Beta","artist":"Charlie","year":2022,"durationSeconds":100},
      {"songId":"gamma","title":"Gamma","artist":"Bravo"},
      {"songId":"delta","title":"Delta","artist":"Alpha","year":2020,"durationSeconds":150}
    ]}
    """.utf8)
    let catalogue = try JSONDecoder().decode(SongsResponse.self, from: bytes)
    try catalogue.validate()
    return catalogue.songs
}

/// Sorting must affect live catalogue rows, not only the sheet's selected state.
@Test func anonymousSongsSortOrdersAllModesAndDirections() throws {
    let songs = try sortingSongs()
    let expectations: [(SongSortMode, [String])] = [
        (.title, ["alpha", "beta", "delta", "gamma"]),
        (.artist, ["delta", "gamma", "beta", "alpha"]),
        (.year, ["gamma", "delta", "alpha", "beta"]),
        (.duration, ["gamma", "beta", "delta", "alpha"]),
    ]
    for (mode, ascending) in expectations {
        let ordered = try SongCatalogSort.sorted(
            songs, mode: mode, ascending: true
        ).map(\.songId)
        let reverse = try SongCatalogSort.sorted(
            songs, mode: mode, ascending: false
        ).map(\.songId)
        #expect(ordered == ascending)
        #expect(reverse == Array(ascending.reversed()))
        #expect(!mode.label.isEmpty)
    }
    #expect(songs.map(\.songId) == ["alpha", "beta", "gamma", "delta"])
}

/// Equal visible fields use the title and then stable song ID, not random array order.
@Test func anonymousSongsSortKeepsDeterministicTies() throws {
    let bytes = Data("""
    {"count":3,"songs":[
      {"songId":"z","title":"Same","artist":"Fixture","year":2025,"durationSeconds":120},
      {"songId":"a","title":"Same","artist":"Fixture","year":2025,"durationSeconds":120},
      {"songId":"m","title":"Other","artist":"Fixture","year":2025,"durationSeconds":120}
    ]}
    """.utf8)
    let songs = try JSONDecoder().decode(SongsResponse.self, from: bytes).songs
    for mode in SongSortMode.allCases where mode != .shop {
        #expect(try SongCatalogSort.sorted(songs, mode: mode, ascending: true).map(\.songId)
                == ["m", "a", "z"])
        #expect(try SongCatalogSort.sorted(songs, mode: mode, ascending: false).map(\.songId)
                == ["z", "a", "m"])
    }
    #expect(SongSortMode(rawValue: "score") == nil)
    #expect(SongSortMode(rawValue: "shop") == .shop)
}

/// A known empty Shop is sortable; an absent or failed feed is not empty membership.
@Test func anonymousShopSortRequiresValidatedMembershipAndReversesAllTies() throws {
    let songs = try sortingSongs()
    #expect(throws: FestivalAPIError.invalidShop) {
        try SongCatalogSort.sorted(songs, mode: .shop, ascending: true)
    }
    let membership: Set<String> = ["beta", "delta"]
    let ordered = try SongCatalogSort.sorted(
        songs, mode: .shop, ascending: true, shopSongIds: membership
    ).map(\.songId)
    let reverse = try SongCatalogSort.sorted(
        songs, mode: .shop, ascending: false, shopSongIds: membership
    ).map(\.songId)
    #expect(ordered == ["beta", "delta", "alpha", "gamma"])
    #expect(reverse == Array(ordered.reversed()))
    #expect(try SongCatalogSort.sorted(
        songs, mode: .shop, ascending: true, shopSongIds: []
    ).map(\.songId) == ["alpha", "beta", "delta", "gamma"])

    let ties = try JSONDecoder().decode(SongsResponse.self, from: Data("""
    {"count":3,"songs":[
      {"songId":"x","title":"Same","artist":"Beta","year":2025},
      {"songId":"y","title":"Same","artist":"Alpha","year":2024},
      {"songId":"z","title":"Same","artist":"Alpha","year":2023}
    ]}
    """.utf8)).songs
    #expect(try SongCatalogSort.sorted(
        ties, mode: .shop, ascending: true, shopSongIds: []
    ).map(\.songId) == ["z", "y", "x"])
    #expect(try SongCatalogSort.sorted(
        ties, mode: .shop, ascending: false, shopSongIds: []
    ).map(\.songId) == ["x", "y", "z"])
}

/// Shop headings follow first-seen status buckets and vanish for one bucket.
@Test func anonymousShopSortGroupsLeavingAndMembershipLikeSourceQuickLinks() throws {
    let songs = try sortingSongs()
    let response = try JSONDecoder().decode(ShopResponse.self, from: Data("""
    {"count":3,"songs":[
      {"songId":"alpha","title":"Alpha","artist":"Fixture","shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/alpha","leavingTomorrow":false,"isNew":false},
      {"songId":"beta","title":"Beta","artist":"Fixture","shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/beta","leavingTomorrow":true,"isNew":false},
      {"songId":"delta","title":"Delta","artist":"Fixture","shopUrl":"https://www.fortnite.com/item-shop/jam-tracks/delta","leavingTomorrow":false,"isNew":true}
    ]}
    """.utf8))
    try response.validate()
    let offers = Dictionary(uniqueKeysWithValues: response.songs.map { ($0.songId, $0) })
    let membership = Set(offers.keys)

    let ascending = try SongCatalogSort.sorted(
        songs, mode: .shop, ascending: true, shopSongIds: membership
    )
    let ascendingSections = SongCatalogSort.shopSections(ascending, offersById: offers)
    #expect(ascendingSections.map(\.kind) == [.inShop, .leavingTomorrow, .notInShop])
    #expect(ascendingSections.map { $0.songs.map(\.songId) }
            == [["alpha", "delta"], ["beta"], ["gamma"]])

    let descending = try SongCatalogSort.sorted(
        songs, mode: .shop, ascending: false, shopSongIds: membership
    )
    let descendingSections = SongCatalogSort.shopSections(descending, offersById: offers)
    #expect(descendingSections.map(\.kind) == [.notInShop, .inShop, .leavingTomorrow])
    #expect(descendingSections.map { $0.songs.map(\.songId) }
            == [["gamma"], ["delta", "alpha"], ["beta"]])

    let empty = SongCatalogSort.shopSections(ascending, offersById: [:])
    #expect(empty.map(\.kind) == [.notInShop])
    #expect(empty[0].songs.map(\.songId) == ascending.map(\.songId))
    #expect(SongCatalogSort.shopSections([], offersById: offers).isEmpty)
}
