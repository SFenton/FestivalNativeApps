import Foundation
import Testing
@testable import FestivalCore

private func offer(_ id: String, new: Bool = false, leaving: Bool = false) -> ShopSong {
    ShopSong(
        songId: id, title: id.capitalized, artist: "Synthetic Quartet", year: nil,
        albumArt: nil,
        shopUrl: URL(string: "https://www.fortnite.com/item-shop/jam-tracks/\(id)")!,
        leavingTomorrow: leaving, isNew: new
    )
}

private let offers = [
    offer("alpha", new: true),
    offer("bravo"),
    offer("charlie", leaving: true),
    offer("delta", new: true, leaving: true),
    offer("echo"),
]

@Test func shopAvailabilityGroupsCoverEveryOffer() {
    #expect(ShopAvailability.groups(of: offers[0]) == [.new])
    #expect(ShopAvailability.groups(of: offers[1]) == [.available])
    #expect(ShopAvailability.groups(of: offers[2]) == [.leavingTomorrow])
    #expect(ShopAvailability.groups(of: offers[3]) == [.new, .leavingTomorrow])
    #expect(ShopAvailability.allCases.map(\.label) == ["New", "Available", "Leaving Tomorrow"])
}

@Test func inactiveShopFilterKeepsEveryOfferInOrder() {
    let filter = ShopOfferFilter()
    #expect(!filter.isActive)
    #expect(filter.selected.isEmpty)
    #expect(filter.filtered(offers).map(\.songId) == offers.map(\.songId))
}

@Test func eachShopFilterShowsOnlyItsGroup() {
    #expect(ShopOfferFilter(new: true).filtered(offers).map(\.songId) == ["alpha", "delta"])
    #expect(ShopOfferFilter(available: true).filtered(offers).map(\.songId) == ["bravo", "echo"])
    #expect(
        ShopOfferFilter(leavingTomorrow: true).filtered(offers).map(\.songId)
            == ["charlie", "delta"]
    )
}

@Test func combinedShopFiltersShowAnySelectedGroup() {
    #expect(
        ShopOfferFilter(new: true, leavingTomorrow: true).filtered(offers).map(\.songId)
            == ["alpha", "charlie", "delta"]
    )
    #expect(
        ShopOfferFilter(new: true, available: true).filtered(offers).map(\.songId)
            == ["alpha", "bravo", "delta", "echo"]
    )
    let all = ShopOfferFilter(new: true, available: true, leavingTomorrow: true)
    #expect(all.filtered(offers).map(\.songId) == offers.map(\.songId))
    #expect(all.selected == [.new, .available, .leavingTomorrow])
}

@Test func shopFilterSettingTogglesOneGroupAndResetClearsAll() {
    var filter = ShopOfferFilter()
    for group in ShopAvailability.allCases {
        filter = filter.setting(group, included: true)
        #expect(filter.includes(group))
    }
    #expect(filter == ShopOfferFilter(new: true, available: true, leavingTomorrow: true))
    filter = filter.setting(.available, included: false)
    #expect(filter == ShopOfferFilter(new: true, leavingTomorrow: true))
    #expect(!filter.matches(offers[1]))
    #expect(filter.matches(offers[3]))
    #expect(ShopOfferFilter().filtered([]).isEmpty)
    #expect(ShopOfferFilter(new: true).filtered([offers[1], offers[4]]).isEmpty)
}
