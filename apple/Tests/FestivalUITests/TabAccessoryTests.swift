import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Registry

/// `TabAccessoryRegistry`: the newest visible page's accessory wins; replacing keeps order.
@MainActor
struct TabAccessoryRegistryTests {
    @Test func emptyRegistryHasNoActiveAccessory() {
        #expect(TabAccessoryRegistry().active == nil)
    }

    @Test func newestRegistrationIsActiveAndRemovalRevealsPrevious() {
        let registry = TabAccessoryRegistry()
        let songs = UUID()
        let player = UUID()
        registry.upsert(id: songs, content: AnyView(Text("Search")))
        registry.upsert(id: player, content: AnyView(Text("Select")))
        #expect(registry.active?.id == player)
        // Pop: the player page disappears after Songs re-registered on appear.
        registry.upsert(id: songs, content: AnyView(Text("Search")))
        registry.remove(id: player)
        #expect(registry.active?.id == songs)
        #expect(registry.entries.count == 1)
    }

    @Test func replacingContentKeepsPosition() {
        let registry = TabAccessoryRegistry()
        let songs = UUID()
        let player = UUID()
        registry.upsert(id: songs, content: AnyView(Text("Search")))
        registry.upsert(id: player, content: AnyView(Text("Select")))
        registry.upsert(id: songs, content: AnyView(Text("love")))
        #expect(registry.entries.map(\.id) == [songs, player])
        #expect(registry.active?.id == player)
    }

    @Test func removingUnknownIdIsHarmless() {
        let registry = TabAccessoryRegistry()
        let songs = UUID()
        registry.upsert(id: songs, content: AnyView(EmptyView()))
        registry.remove(id: UUID())
        #expect(registry.active?.id == songs)
    }
}

// MARK: - Profile identity action

/// Titles, symbols and test IDs of `ProfileIdentityAction` stay stable for journeys.
struct ProfileIdentityActionTests {
    @Test func selectAndSwitchKeepTheSelectIdentifier() {
        #expect(ProfileIdentityAction.select.accessibilityIdentifier == "fst.player.select")
        #expect(ProfileIdentityAction.switchTo.accessibilityIdentifier == "fst.player.select")
        #expect(ProfileIdentityAction.deselect.accessibilityIdentifier == "fst.player.deselect")
    }

    @Test func onlyDeselectIsSecondary() {
        #expect(ProfileIdentityAction.select.isProminent)
        #expect(ProfileIdentityAction.switchTo.isProminent)
        #expect(!ProfileIdentityAction.deselect.isProminent)
    }

    @Test func titlesMatchTheFormerHeaderButtons() {
        #expect(ProfileIdentityAction.select.title == "Select Profile")
        #expect(ProfileIdentityAction.switchTo.title == "Switch To This Profile")
        #expect(ProfileIdentityAction.deselect.title == "Deselect Profile")
        #expect(ProfileIdentityAction.deselect.shortTitle == "Deselect")
    }
}
