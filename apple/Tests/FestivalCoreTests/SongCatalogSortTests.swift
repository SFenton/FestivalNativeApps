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
        let ordered = SongCatalogSort.sorted(songs, mode: mode, ascending: true).map(\.songId)
        let reverse = SongCatalogSort.sorted(songs, mode: mode, ascending: false).map(\.songId)
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
    for mode in SongSortMode.allCases {
        #expect(SongCatalogSort.sorted(songs, mode: mode, ascending: true).map(\.songId)
                == ["m", "a", "z"])
        #expect(SongCatalogSort.sorted(songs, mode: mode, ascending: false).map(\.songId)
                == ["z", "a", "m"])
    }
    #expect(SongSortMode(rawValue: "score") == nil)
    #expect(SongSortMode(rawValue: "shop") == nil)
}
