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

    /// The accessory shows only the front page's tools, in dock order, and nothing once
    /// every page has gone (issue #42).
    @Test func frontItemsFollowTheFrontPage() {
        let registry = TabAccessoryRegistry()
        let songs = UUID()
        let detail = UUID()
        let search = UUID()
        let sort = UUID()
        let filter = UUID()
        let links = UUID()
        #expect(registry.frontItems.isEmpty)
        registry.upsert(id: sort, order: DockOrder.sort, scope: songs, content: AnyView(EmptyView()))
        registry.upsert(id: filter, order: DockOrder.filter, scope: songs, content: AnyView(EmptyView()))
        registry.upsert(
            id: search, order: DockOrder.search, scope: songs, kind: .field,
            content: AnyView(EmptyView())
        )
        registry.upsert(id: links, order: DockOrder.quickLinks, scope: detail, content: AnyView(EmptyView()))
        #expect(registry.frontItems.isEmpty, "No page on screen yet")
        registry.pageAppeared(songs)
        #expect(registry.frontItems.map(\.id) == [search, filter, sort])
        #expect(registry.frontItems.first?.kind == .field)
        registry.pageAppeared(detail)
        #expect(registry.frontItems.map(\.id) == [links])
        registry.pageDisappeared(detail)
        #expect(registry.frontItems.map(\.id) == [search, filter, sort])
        registry.pageDisappeared(songs)
        #expect(registry.frontItems.isEmpty)
    }

    /// Re-registering can change a control's kind.
    @Test func upsertReplacesKind() {
        let registry = TabAccessoryRegistry()
        let id = UUID()
        registry.upsert(id: id, content: AnyView(EmptyView()))
        #expect(registry.entries.first?.kind == .tool)
        registry.upsert(id: id, kind: .field, content: AnyView(EmptyView()))
        #expect(registry.entries.first?.kind == .field)
    }

    @Test func removingUnknownIdIsHarmless() {
        let registry = TabAccessoryRegistry()
        let songs = UUID()
        registry.upsert(id: songs, content: AnyView(EmptyView()))
        registry.remove(id: UUID())
        #expect(registry.active?.id == songs)
    }
}

// MARK: - Presentation and accessory layout (issue #42)

/// Only the horizontal iPhone tab bar hosts page tools; the accessory needs iOS 26.1.
@Test(arguments: [
    (false, false, nil),
    (false, true, nil),
    (true, false, PageToolsPresentation.floating),
    (true, true, .accessory),
] as [(Bool, Bool, PageToolsPresentation?)])
func pageToolsPresentationResolves(
    horizontal: Bool, supported: Bool, expected: PageToolsPresentation?
) {
    #expect(PageToolsPresentation.resolve(
        horizontalTabBar: horizontal, accessorySupported: supported
    ) == expected)
}

// MARK: - Separate tools and the accessory (issue #89)

/// The tab-bar accessory holds only the front page's field (Songs search); Filter, Sort
/// and Quick Links float as separate round buttons in dock order.
@MainActor
@Test func accessoryHoldsOnlyFieldsAndToolsFloat() {
    let registry = TabAccessoryRegistry()
    let songs = UUID()
    let detail = UUID()
    let search = UUID()
    let filter = UUID()
    let sort = UUID()
    let links = UUID()
    let detailLinks = UUID()
    registry.upsert(id: links, order: DockOrder.quickLinks, scope: songs, content: AnyView(EmptyView()))
    registry.upsert(id: sort, order: DockOrder.sort, scope: songs, content: AnyView(EmptyView()))
    registry.upsert(id: filter, order: DockOrder.filter, scope: songs, content: AnyView(EmptyView()))
    registry.upsert(
        id: search, order: DockOrder.search, scope: songs, kind: .field, content: AnyView(EmptyView())
    )
    registry.upsert(
        id: detailLinks, order: DockOrder.quickLinks, scope: detail, content: AnyView(EmptyView())
    )
    registry.pageAppeared(songs)
    #expect(registry.frontFields.map(\.id) == [search])
    #expect(registry.tools(in: songs).map(\.id) == [filter, sort, links])
    registry.pageAppeared(detail)
    #expect(registry.frontFields.isEmpty, "Song Detail has no field: no accessory")
    #expect(registry.tools(in: detail).map(\.id) == [detailLinks])
}

/// While the accessory is inline the tools drop until their resting bottom meets its top,
/// and rise again when it expands.
@Test func accessoryFollowDropsToTheInlineAccessory() {
    var follow = AccessoryFollow()
    #expect(follow.drop(restingBottom: 736) == 0)
    follow.report(top: 736, inline: false)
    #expect(follow.drop(restingBottom: 736) == 0, "Expanded: tools rest on the safe area above it")
    follow.report(top: 798, inline: true)
    #expect(follow.drop(restingBottom: 736) == 62)
    follow.report(top: 736, inline: false)
    #expect(follow.drop(restingBottom: 736) == 0)
}

/// Before the tools are laid out, or if the accessory sits above them, they stay where
/// the safe area puts them.
@Test func accessoryFollowNeverGuessesOrRises() {
    var follow = AccessoryFollow()
    follow.report(top: 798, inline: true)
    #expect(follow.drop(restingBottom: nil) == 0, "Tools not laid out yet")
    follow.report(top: 700, inline: true)
    #expect(follow.drop(restingBottom: 736) == 0, "Never negative")
}

/// Withdrawing the accessory (a page without a field) resets the tools' drop.
@MainActor
@Test func withdrawingTheAccessoryResetsTheDrop() {
    let registry = TabAccessoryRegistry()
    registry.reportAccessory(top: 822, inline: true)
    #expect(registry.accessoryFollow.drop(restingBottom: 760) == 62)
    registry.accessoryWithdrawn()
    #expect(registry.accessoryFollow == AccessoryFollow())
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
