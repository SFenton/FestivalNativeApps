import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

/// Songs covering every General classification, including missing metadata.
private func generalSongs() throws -> [Song] {
    let response = try JSONDecoder().decode(SongsResponse.self, from: Data("""
    {"count":5,"songs":[
      {"songId":"seventies","title":"A","artist":"F","year":1975,"durationSeconds":59,
       "doubleBassSupported":true},
      {"songId":"nineties","title":"B","artist":"F","year":1999,"durationSeconds":240,
       "doubleBassSupported":false},
      {"songId":"long","title":"C","artist":"F","year":2020,"durationSeconds":605,
       "doubleBassSupported":false},
      {"songId":"unknown","title":"D","artist":"F","doubleBassSupported":null},
      {"songId":"absent","title":"E","artist":"F","year":0,"durationSeconds":0}
    ]}
    """.utf8))
    try response.validate()
    return response.songs
}

private func ids(_ songs: [Song]) -> [String] { songs.map(\.songId) }

// MARK: - Buckets and labels

@Test func generalBucketsAndLabelsMatchWebFilterModal() throws {
    let songs = try generalSongs()
    #expect(SongGeneralFilter.decade(forYear: 1999) == 1990)
    #expect(SongGeneralFilter.decade(forYear: 2020) == 2020)
    #expect(SongGeneralFilter.decade(forYear: 0) == nil)
    #expect(SongGeneralFilter.decade(forYear: nil) == nil)
    #expect(SongGeneralFilter.durationBucket(forSeconds: 59) == 0)
    #expect(SongGeneralFilter.durationBucket(forSeconds: 240) == 4)
    #expect(SongGeneralFilter.durationBucket(forSeconds: 6_000) == 10)
    #expect(SongGeneralFilter.durationBucket(forSeconds: 0) == nil)
    #expect(SongGeneralFilter.decades(in: songs) == [1970, 1990, 2020])
    #expect(SongGeneralFilter.durationBuckets(in: songs) == Array(0...10))
    #expect(SongGeneralFilter.durationBuckets(in: Array(songs.prefix(2))) == Array(0..<10))
    #expect(SongGeneralFilter.decadeLabel(1990) == "1990s")
    #expect(SongGeneralFilter.durationLabel(0) == "Under 1 Minute")
    #expect(SongGeneralFilter.durationLabel(3) == "3-4 Minutes")
    #expect(SongGeneralFilter.durationLabel(9) == "9-10 Minutes")
    #expect(SongGeneralFilter.durationLabel(10) == "10+ Minutes")
    #expect(songs[0].doubleBassSupported == true && songs[3].doubleBassSupported == nil)
    #expect(songs[4].doubleBassSupported == nil)
}

// MARK: - Filtering

@Test func defaultGeneralFilterKeepsEverySongIncludingUnknownMetadata() throws {
    let songs = try generalSongs()
    let filter = SongGeneralFilter()
    #expect(!filter.isActive(shopVisible: true) && !filter.isCustomized)
    #expect(filter.filteredMetadata(songs) == songs)
}

@Test func yearAndDurationExcludeChosenBucketsAndUnknownValuesOnlyWhileRestricting() throws {
    let songs = try generalSongs()
    let year = SongGeneralFilter(excludedDecades: [1990])
    #expect(year.isActive(shopVisible: false))
    #expect(ids(year.filteredMetadata(songs)) == ["seventies", "long"])
    let duration = SongGeneralFilter(excludedDurations: [10])
    #expect(ids(duration.filteredMetadata(songs)) == ["seventies", "nineties"])
    let everyDecade = SongGeneralFilter(excludedDecades: Set(SongGeneralFilter.decades(in: songs)))
    #expect(everyDecade.filteredMetadata(songs).isEmpty)
}

@Test func doubleBassMatchesExplicitValuesAndExcludesNullWhenEitherIsOff() throws {
    let songs = try generalSongs()
    let supported = SongGeneralFilter(doubleBassUnsupported: false)
    #expect(ids(supported.filteredMetadata(songs)) == ["seventies"])
    let unsupported = SongGeneralFilter(doubleBassSupported: false)
    #expect(ids(unsupported.filteredMetadata(songs)) == ["nineties", "long"])
    let neither = SongGeneralFilter(doubleBassSupported: false, doubleBassUnsupported: false)
    #expect(neither.filteredMetadata(songs).isEmpty)
    #expect(neither.isActive(shopVisible: false))
}

@Test func shopChoiceCountsAsActiveOnlyWhileShopIsVisible() {
    let filter = SongGeneralFilter(shop: .availableOnly)
    #expect(filter.isActive(shopVisible: true))
    #expect(!filter.isActive(shopVisible: false))
    #expect(filter.isCustomized && !filter.restrictsMetadata)
}

// MARK: - Saved preferences

@Test func generalFilterRoundTripsDeterministicallyAndDefaultsSaveNoBytes() throws {
    #expect(try SongGeneralFilter().encoded().isEmpty)
    let filter = SongGeneralFilter(
        excludedDecades: [2020, 1970], excludedDurations: [10, 0],
        shop: SongShopFilter(available: false, unavailable: true),
        doubleBassSupported: false
    )
    let data = try filter.encoded()
    #expect(String(decoding: data, as: UTF8.self) == #"{"doubleBassSupported":false,"#
        + #""doubleBassUnsupported":true,"excludedDecades":[1970,2020],"#
        + #""excludedDurations":[0,10],"shopAvailable":false,"shopUnavailable":true}"#)
    #expect(try SongGeneralFilter.decodeSaved(data) == filter)
    // Saved choices win over the legacy toggles.
    #expect(try SongGeneralFilter.decodeSaved(data, legacyInShop: true) == filter)
}

@Test func legacyShopTogglesMigrateToAvailableOnly() throws {
    #expect(try SongGeneralFilter.decodeSaved(Data()) == SongGeneralFilter())
    #expect(try SongGeneralFilter.decodeSaved(Data(), legacyInShop: true)
        == SongGeneralFilter(shop: .availableOnly))
    #expect(try SongGeneralFilter.decodeSaved(Data(), legacyLeavingTomorrow: true)
        == SongGeneralFilter(shop: .availableOnly))
}

@Test func corruptOrOutOfRangeGeneralFiltersRequireExplicitReset() throws {
    for json in [
        "{", "[]", #"{"excludedDecades":[1995]}"#, #"{"excludedDecades":[1990,1990]}"#,
        #"{"excludedDecades":[-10]}"#, #"{"excludedDurations":[11]}"#,
        #"{"excludedDurations":[1,1]}"#, #"{"shopAvailable":"yes"}"#,
        #"{"excludedDecades":["#
            + (0..<65).map { String($0 * 10) }.joined(separator: ",") + "]}",
    ] {
        #expect(throws: FestivalAPIError.invalidSongFilter) {
            try SongGeneralFilter.decodeSaved(Data(json.utf8))
        }
    }
    #expect(throws: FestivalAPIError.invalidSongFilter) {
        try SongGeneralFilter.decodeSaved(Data(repeating: 0x20, count: 4_097))
    }
    // Older or newer saved forms without some keys use defaults for them.
    #expect(try SongGeneralFilter.decodeSaved(Data(#"{"excludedDurations":[3]}"#.utf8))
        == SongGeneralFilter(excludedDurations: [3]))
}
