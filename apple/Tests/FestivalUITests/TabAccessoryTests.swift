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

    /// During a push both pages have controls registered; each page shows only its own.
    @Test func itemsAreScopedToTheirPage() {
        let registry = TabAccessoryRegistry()
        let songsPage = UUID()
        let detailPage = UUID()
        let sort = UUID()
        let links = UUID()
        registry.upsert(id: sort, order: DockOrder.sort, scope: songsPage, content: AnyView(EmptyView()))
        registry.upsert(id: links, order: DockOrder.quickLinks, scope: detailPage, content: AnyView(EmptyView()))
        #expect(registry.items(in: songsPage).map(\.id) == [sort])
        #expect(registry.items(in: detailPage).map(\.id) == [links])
    }

    /// The incoming page of a push or pop is the front one as soon as it appears; the
    /// outgoing page gets the controls back if it is still on screen afterwards (a
    /// cancelled interactive pop).
    @Test func frontPageIsTheLatestStillOnScreen() {
        let registry = TabAccessoryRegistry()
        let songs = UUID()
        let detail = UUID()
        registry.pageAppeared(songs)
        #expect(registry.isFront(songs))
        registry.pageAppeared(detail)   // push starts
        #expect(registry.isFront(detail) && !registry.isFront(songs))
        registry.pageDisappeared(songs) // push ends
        #expect(registry.isFront(detail))
        registry.pageAppeared(songs)    // interactive pop starts
        #expect(registry.isFront(songs))
        registry.pageDisappeared(songs) // pop cancelled
        #expect(registry.isFront(detail))
        registry.pageAppeared(detail)   // re-appearing never duplicates
        #expect(registry.pageScopes == [detail])
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

/// The Songs scrolled state holds between its thresholds, so an inset change caused by
/// moving the tools into the bar cannot flip it back and forth.
@Test func songsScrollStateHasHysteresis() {
    #expect(!SongsScrollState.scrolled(offset: 20, wasScrolled: false))
    #expect(SongsScrollState.scrolled(offset: 41, wasScrolled: false))
    #expect(SongsScrollState.scrolled(offset: 20, wasScrolled: true))
    #expect(!SongsScrollState.scrolled(offset: 3, wasScrolled: true))
}
