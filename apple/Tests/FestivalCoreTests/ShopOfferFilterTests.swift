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

@Test func freshShopFilterStartsAllOnAndKeepsEveryOfferInOrder() {
    let filter = ShopOfferFilter()
    #expect(filter == ShopOfferFilter(new: true, available: true, leavingTomorrow: true))
    #expect(!filter.isActive)
    #expect(filter.selected == [.new, .available, .leavingTomorrow])
    #expect(filter.hidden.isEmpty)
    #expect(filter.filtered(offers).map(\.songId) == offers.map(\.songId))
    #expect(offers.allSatisfy(filter.matches))
}

@Test func eachSwitchedOffGroupHidesOnlyThatGroup() {
    #expect(ShopOfferFilter(new: false).filtered(offers).map(\.songId) == ["bravo", "charlie", "delta", "echo"])
    #expect(ShopOfferFilter(available: false).filtered(offers).map(\.songId) == ["alpha", "charlie", "delta"])
    #expect(
        ShopOfferFilter(leavingTomorrow: false).filtered(offers).map(\.songId)
            == ["alpha", "bravo", "delta", "echo"]
    )
    for group in ShopAvailability.allCases {
        let filter = ShopOfferFilter().setting(group, included: false)
        #expect(filter.isActive)
        #expect(filter.hidden == [group])
    }
}

@Test func offerInTwoGroupsHidesOnlyWhenBothAreOff() {
    let both = offers[3]
    #expect(ShopOfferFilter(new: false).matches(both))
    #expect(ShopOfferFilter(leavingTomorrow: false).matches(both))
    #expect(!ShopOfferFilter(new: false, leavingTomorrow: false).matches(both))
    #expect(
        ShopOfferFilter(new: false, leavingTomorrow: false).filtered(offers).map(\.songId)
            == ["bravo", "echo"]
    )
}

@Test func everySwitchOffShowsNothing() {
    let none = ShopOfferFilter(new: false, available: false, leavingTomorrow: false)
    #expect(none.isActive)
    #expect(none.selected.isEmpty)
    #expect(none.filtered(offers).isEmpty)
}

@Test func shopFilterSettingTogglesOneGroupAndResetTurnsAllOn() {
    var filter = ShopOfferFilter()
    for group in ShopAvailability.allCases {
        filter = filter.setting(group, included: false)
        #expect(!filter.includes(group))
    }
    #expect(filter == ShopOfferFilter(new: false, available: false, leavingTomorrow: false))
    filter = filter.setting(.available, included: true)
    #expect(filter == ShopOfferFilter(new: false, leavingTomorrow: false))
    #expect(filter.matches(offers[1]))
    #expect(!filter.matches(offers[3]))
    #expect(ShopOfferFilter().filtered([]).isEmpty)
    #expect(ShopOfferFilter(available: false).filtered([offers[1], offers[4]]).isEmpty)
}

// MARK: - Saved preference

@Test func shopFilterRoundTripsHiddenGroups() {
    #expect(ShopOfferFilter().encoded() == "")
    #expect(ShopOfferFilter(leavingTomorrow: false).encoded() == "leavingTomorrow")
    let allOff = ShopOfferFilter(new: false, available: false, leavingTomorrow: false)
    #expect(allOff.encoded() == "new,available,leavingTomorrow")
    for new in [false, true] {
        for available in [false, true] {
            for leaving in [false, true] {
                let filter = ShopOfferFilter(new: new, available: available, leavingTomorrow: leaving)
                #expect(ShopOfferFilter.decodeSaved(filter.encoded()) == filter)
                // Once saved, the older switches are ignored.
                if filter.isActive {
                    #expect(
                        ShopOfferFilter.decodeSaved(
                            filter.encoded(), legacyNew: true, legacyAvailable: true,
                            legacyLeavingTomorrow: true
                        ) == filter
                    )
                }
            }
        }
    }
}

@Test func olderShowOnlySwitchesMigrateWithoutChangingVisibleOffers() {
    // Every older combination lists the same offers after migration.
    for new in [false, true] {
        for available in [false, true] {
            for leaving in [false, true] {
                let migrated = ShopOfferFilter.decodeSaved(
                    "", legacyNew: new, legacyAvailable: available, legacyLeavingTomorrow: leaving
                )
                let selected = [new ? ShopAvailability.new : nil, available ? .available : nil,
                                leaving ? .leavingTomorrow : nil].compactMap { $0 }
                let olderVisible = offers.filter {
                    selected.isEmpty || !ShopAvailability.groups(of: $0).isDisjoint(with: selected)
                }
                #expect(migrated.filtered(offers).map(\.songId) == olderVisible.map(\.songId))
            }
        }
    }
    #expect(ShopOfferFilter.decodeSaved("") == ShopOfferFilter())
    #expect(
        ShopOfferFilter.decodeSaved("", legacyNew: true)
            == ShopOfferFilter(new: true, available: false, leavingTomorrow: false)
    )
}

@Test func unreadableSavedShopFilterFallsBackToShowingEverything() {
    #expect(ShopOfferFilter.decodeSaved("bogus") == ShopOfferFilter())
    #expect(ShopOfferFilter.decodeSaved("new,bogus") == ShopOfferFilter())
    #expect(ShopOfferFilter.decodeSaved(String(repeating: "new,", count: 64)) == ShopOfferFilter())
    #expect(ShopOfferFilter.decodeSaved("new,new") == ShopOfferFilter(new: false))
}
