import Foundation
import Testing
@testable import FestivalCore

private func offer(
    _ id: String, title: String, artist: String = "Synthetic Quartet", year: Int? = nil
) -> ShopSong {
    ShopSong(
        songId: id, title: title, artist: artist, year: year, albumArt: nil,
        shopUrl: URL(string: "https://www.fortnite.com/item-shop/jam-tracks/\(id)")!,
        leavingTomorrow: false, isNew: false
    )
}

/// Title order: Bravo, Charlie, Delta, Echo (feed order differs on purpose).
private let offers = [
    offer("d", title: "Delta", artist: "Ayla", year: 1999),
    offer("b", title: "Bravo", artist: "Cole", year: 2010),
    offer("e", title: "Echo", artist: "Bex", year: nil),
    offer("c", title: "Charlie", artist: "Bex", year: 1985),
]

private let durations = ["b": 200, "c": 320, "d": 95]

private func ids(_ mode: SongSortMode, ascending: Bool = true, durations: [String: Int]? = durations) -> [String] {
    ShopOfferSort.sorted(offers, by: ShopSortChoice(mode: mode, ascending: ascending), durations: durations)
        .offers.map(\.songId)
}

@Test func shopSortOffersTheFourCatalogueModesInSongsOrder() {
    #expect(ShopSortChoice.modes == [.title, .artist, .year, .duration])
    #expect(ShopSortChoice.modes.map(\.label) == ["Title", "Artist", "Year", "Duration"])
    #expect(ShopSortChoice.modeKey == "fst.shop.sortMode")
    #expect(ShopSortChoice.ascendingKey == "fst.shop.sortAscending")
}

@Test func shopSortDefaultIsTitleAscendingAndNormalizesOtherModes() {
    #expect(ShopSortChoice() == ShopSortChoice(mode: .title, ascending: true))
    #expect(ShopSortChoice().isDefault)
    #expect(!ShopSortChoice(mode: .title, ascending: false).isDefault)
    #expect(!ShopSortChoice(mode: .year).isDefault)
    for foreign in [SongSortMode.shop, .score, .percentile, .stars] {
        #expect(ShopSortChoice(mode: foreign, ascending: false).mode == .title)
    }
}

@Test func shopSortAccessibilityValueUsesSongsVocabulary() {
    #expect(ShopSortChoice().accessibilityValue() == "Title, ascending")
    #expect(ShopSortChoice(mode: .artist, ascending: false).accessibilityValue() == "Artist, descending")
    #expect(
        ShopSortChoice(mode: .duration).accessibilityValue(paused: true)
            == "Duration, ascending, paused; showing Title order"
    )
}

@Test func shopSortOrdersEveryModeAndDirection() {
    #expect(ids(.title) == ["b", "c", "d", "e"])
    #expect(ids(.title, ascending: false) == ["e", "d", "c", "b"])
    // Artist ties (Bex) break by title in the sort direction.
    #expect(ids(.artist) == ["d", "c", "e", "b"])
    #expect(ids(.artist, ascending: false) == ["b", "e", "c", "d"])
    // A missing year sorts as 0.
    #expect(ids(.year) == ["e", "c", "d", "b"])
    #expect(ids(.year, ascending: false) == ["b", "d", "c", "e"])
    // An offer without a catalogue length sorts as 0.
    #expect(ids(.duration) == ["e", "d", "b", "c"])
    #expect(ids(.duration, ascending: false) == ["c", "b", "d", "e"])
}

@Test func shopSortMatchesTheSongsComparator() throws {
    for mode in ShopSortChoice.modes {
        for ascending in [true, false] {
            let songs = offers.map { Song(shopOffer: $0, durationSeconds: durations[$0.songId]) }
            let songsOrder = try SongCatalogSort.sorted(songs, mode: mode, ascending: ascending)
            #expect(ids(mode, ascending: ascending) == songsOrder.map(\.songId))
        }
    }
}

@Test func shopSortBreaksFullTiesBySongId() {
    let twins = [offer("z", title: "Same"), offer("a", title: "Same")]
    let up = ShopOfferSort.sorted(twins, by: ShopSortChoice(mode: .year), durations: [:])
    let down = ShopOfferSort.sorted(twins, by: ShopSortChoice(mode: .year, ascending: false), durations: [:])
    #expect(up.offers.map(\.songId) == ["a", "z"])
    #expect(down.offers.map(\.songId) == ["z", "a"])
}

@Test func shopDurationSortPausesToTitleOrderWithoutLengths() {
    let up = ShopOfferSort.sorted(offers, by: ShopSortChoice(mode: .duration), durations: nil)
    #expect(up.paused)
    #expect(up.offers.map(\.songId) == ["b", "c", "d", "e"])
    let down = ShopOfferSort.sorted(
        offers, by: ShopSortChoice(mode: .duration, ascending: false), durations: nil
    )
    #expect(down.paused)
    #expect(down.offers.map(\.songId) == ["e", "d", "c", "b"])
    // Only Duration needs the catalogue.
    for mode in [SongSortMode.title, .artist, .year] {
        #expect(!ShopOfferSort.sorted(offers, by: ShopSortChoice(mode: mode), durations: nil).paused)
    }
    #expect(!ShopOfferSort.sorted(offers, by: ShopSortChoice(mode: .duration), durations: [:]).paused)
}

@Test func shopSortKeepsEveryOfferOnce() {
    for mode in ShopSortChoice.modes {
        let sorted = ShopOfferSort.sorted(offers, by: ShopSortChoice(mode: mode), durations: durations)
        #expect(Set(sorted.offers.map(\.songId)) == Set(offers.map(\.songId)))
        #expect(sorted.offers.count == offers.count)
    }
    #expect(ShopOfferSort.sorted([], by: ShopSortChoice(mode: .duration), durations: nil).offers.isEmpty)
}

@Test func shopDurationsRequireTheShopsPublication() {
    let catalogue = [
        "b": Song(shopOffer: offers[1], durationSeconds: 200),
        "e": Song(shopOffer: offers[2], durationSeconds: nil),
    ]
    #expect(
        ShopOfferSort.durations(
            catalogue: catalogue, catalogueObservation: 7, shopObservation: 7, currentObservation: 7
        ) == ["b": 200]
    )
    // Different publications, an unobserved Shop, a newer session or a failed catalogue
    // read never lend lengths.
    #expect(ShopOfferSort.durations(
        catalogue: catalogue, catalogueObservation: 6, shopObservation: 7, currentObservation: 7
    ) == nil)
    #expect(ShopOfferSort.durations(
        catalogue: catalogue, catalogueObservation: 7, shopObservation: nil, currentObservation: 7
    ) == nil)
    #expect(ShopOfferSort.durations(
        catalogue: catalogue, catalogueObservation: 7, shopObservation: 7, currentObservation: 8
    ) == nil)
    #expect(ShopOfferSort.durations(
        catalogue: nil, catalogueObservation: 7, shopObservation: 7, currentObservation: 7
    ) == nil)
    #expect(ShopOfferSort.durations(
        catalogue: catalogue, catalogueObservation: nil, shopObservation: 7, currentObservation: 7
    ) == nil)
}
