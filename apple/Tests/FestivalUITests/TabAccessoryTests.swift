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

/// Songs: the field spans and a hairline separates it from Filter, Sort and Quick Links.
@Test func accessoryArrangementWithAField() {
    let layout = PageToolsAccessoryArrangement(kinds: [.field, .tool, .tool, .tool])
    #expect(layout.spans(0))
    #expect(!layout.spans(1) && !layout.spans(2) && !layout.spans(3))
    #expect(!layout.showsDivider(before: 0))
    #expect(layout.showsDivider(before: 1))
    #expect(!layout.showsDivider(before: 2) && !layout.showsDivider(before: 3))
}

/// A page's only tool (Quick Links on Song Detail) fills the capsule with its title.
@Test func accessoryArrangementWithALoneTool() {
    let layout = PageToolsAccessoryArrangement(kinds: [.tool])
    #expect(layout.spans(0))
    #expect(!layout.showsDivider(before: 0))
}

/// Several tools without a field stay icon buttons with no divider.
@Test func accessoryArrangementWithToolsOnly() {
    let layout = PageToolsAccessoryArrangement(kinds: [.tool, .tool])
    #expect(!layout.spans(0) && !layout.spans(1))
    #expect(!layout.showsDivider(before: 1))
    #expect(!layout.spans(5) && !layout.showsDivider(before: 5), "Out of range is harmless")
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
