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
        #expect(registry.frontItems.map(\.id) == [search, sort, filter])
        #expect(registry.frontItems.first?.kind == .field)
        registry.pageAppeared(detail)
        #expect(registry.frontItems.map(\.id) == [links])
        registry.pageDisappeared(detail)
        #expect(registry.frontItems.map(\.id) == [search, sort, filter])
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

// MARK: - One row beside the tab bar (issue #89)

/// The dock shows the front page's search field first, then round Sort, Filter and
/// Quick Links in that order; before iOS 26.1 only the icon tools float.
@MainActor
@Test func dockShowsSearchThenSortFilterQuickLinks() {
    let registry = TabAccessoryRegistry()
    let songs = UUID()
    let detail = UUID()
    let search = UUID()
    let filter = UUID()
    let sort = UUID()
    let links = UUID()
    let detailLinks = UUID()
    registry.upsert(id: links, order: DockOrder.quickLinks, scope: songs, content: AnyView(EmptyView()))
    registry.upsert(id: filter, order: DockOrder.filter, scope: songs, content: AnyView(EmptyView()))
    registry.upsert(id: sort, order: DockOrder.sort, scope: songs, content: AnyView(EmptyView()))
    registry.upsert(
        id: search, order: DockOrder.search, scope: songs, kind: .field, content: AnyView(EmptyView())
    )
    registry.upsert(
        id: detailLinks, order: DockOrder.quickLinks, scope: detail, content: AnyView(EmptyView())
    )
    registry.pageAppeared(songs)
    #expect(registry.frontItems.map(\.id) == [search, sort, filter, links])
    #expect(registry.tools(in: songs).map(\.id) == [sort, filter, links])
    registry.pageAppeared(detail)
    #expect(registry.frontItems.map(\.id) == [detailLinks], "Song Detail: Quick Links only")
}

/// The open Songs search bar hides the dock; identical reports never re-publish.
@MainActor
@Test func registryTracksTabBarAndSuppression() {
    let registry = TabAccessoryRegistry()
    #expect(registry.tabBar == nil && !registry.dockSuppressed)
    let geometry = TabBarGeometry(
        bar: CGRect(x: 0, y: 791, width: 402, height: 83),
        platter: CGRect(x: 43, y: 791, width: 317, height: 62)
    )
    registry.reportTabBar(geometry)
    #expect(registry.tabBar == geometry)
    registry.reportTabBar(nil)
    #expect(registry.tabBar == nil)
    registry.setDockSuppressed(true)
    #expect(registry.dockSuppressed)
    registry.setDockSuppressed(false)
    #expect(!registry.dockSuppressed)
}

/// iPhone 17 Pro, iOS 26.5 (402 × 874 pt): measured tab-bar frames.
private enum Measured {
    static let window = CGRect(x: 0, y: 0, width: 402, height: 874)
    static let bar = CGRect(x: 0, y: 791, width: 402, height: 83)
    static let expanded = TabBarGeometry(bar: bar, platter: CGRect(x: 43, y: 791, width: 317, height: 62))
    static let minimized = TabBarGeometry(bar: bar, platter: CGRect(x: 28, y: 798, width: 48, height: 48))
    /// Right-to-left: the minimized tab sits on the right.
    static let minimizedRTL = TabBarGeometry(bar: bar, platter: CGRect(x: 326, y: 798, width: 48, height: 48))
}

/// A wide platter is the expanded bar; a circle is the minimized one.
@Test func tabBarGeometryClassifiesMinimized() {
    #expect(!Measured.expanded.isMinimized)
    #expect(Measured.minimized.isMinimized)
    #expect(Measured.minimizedRTL.isMinimized)
    #expect(!TabBarGeometry(bar: Measured.bar, platter: .zero).isMinimized)
    #expect(!TabBarGeometry(bar: Measured.bar, platter: CGRect(x: 100, y: 791, width: 200, height: 62)).isMinimized,
            "Two tabs are still wider than tall")
}

/// The platter is the largest visible subview; empty or missing frames are ignored.
@Test func tabBarPlatterIsTheLargestFrame() {
    let platter = CGRect(x: 43, y: 791, width: 317, height: 62)
    #expect(TabBarGeometry.platter(among: [
        CGRect(x: 0, y: 791, width: 1, height: 1), platter, .zero,
        CGRect(x: 60, y: 795, width: 70, height: 54),
    ]) == platter)
    #expect(TabBarGeometry.platter(among: []) == nil)
    #expect(TabBarGeometry.platter(among: [.zero]) == nil)
    let noisy = TabBarGeometry(
        bar: CGRect(x: 0, y: 790.83, width: 402, height: 83.2),
        platter: CGRect(x: 27.9, y: 798.1, width: 48.2, height: 47.9)
    ).rounded()
    #expect(noisy == TabBarGeometry(
        bar: CGRect(x: 0, y: 791, width: 402, height: 83),
        platter: CGRect(x: 28, y: 798, width: 48, height: 48)
    ))
}

/// Expanded: the row spans the width just above the tab bar's glass, ending where the
/// page's bottom inset begins.
@Test func dockSitsAboveTheExpandedTabBar() {
    let layout = PageToolsDockLayout.resolve(
        tabBar: Measured.expanded, container: Measured.window, bottomSafeArea: 34
    )
    #expect(!layout.collapsed)
    #expect(layout.minX == 20 && layout.maxX == 382)
    #expect(layout.midY + PageToolsDockLayout.rowHeight / 2 == 781, "10 pt above the glass")
    #expect(layout.midY - PageToolsDockLayout.rowHeight / 2 == Measured.bar.minY - PageToolsDockLayout.pageInset,
            "The page's bottom inset ends where the row begins")
}

/// Minimized: the row moves into the tab-bar row beside the round tab, mirroring its
/// margin on the far side, in either reading direction.
@Test func dockMovesBesideTheMinimizedTab() {
    let ltr = PageToolsDockLayout.resolve(
        tabBar: Measured.minimized, container: Measured.window, bottomSafeArea: 34
    )
    #expect(ltr.collapsed)
    #expect(ltr.minX == 28 + 48 + 12 && ltr.maxX == 402 - 28)
    #expect(ltr.midY == 822, "Centred on the minimized tab")
    let rtl = PageToolsDockLayout.resolve(
        tabBar: Measured.minimizedRTL, container: Measured.window, bottomSafeArea: 34
    )
    #expect(rtl.collapsed)
    #expect(rtl.minX == 28 && rtl.maxX == 326 - 12)
    #expect(rtl.width == ltr.width)
}

/// Without a tab bar reading the row rests where a standard bar would put it: the
/// expanded position, never over the tabs.
@Test func dockFallsBackToTheExpandedPlace() {
    let layout = PageToolsDockLayout.resolve(tabBar: nil, container: Measured.window, bottomSafeArea: 34)
    #expect(!layout.collapsed)
    let restingBottom: CGFloat = 874 - 34 - 49 - 10
    #expect(layout.midY + PageToolsDockLayout.rowHeight / 2 == restingBottom)
    #expect(layout.minX == 20 && layout.maxX == 382)
    let empty = PageToolsDockLayout.resolve(
        tabBar: TabBarGeometry(bar: Measured.bar, platter: .zero),
        container: Measured.window, bottomSafeArea: 34
    )
    #expect(empty == layout)
}

/// Each round tool and the row keep a 44 pt hit region (HIG Buttons).
@Test func dockControlsKeepTheMinimumHitRegion() {
    #expect(PageToolsDockLayout.rowHeight >= 44)
    #expect(PageToolsDockLayout.spacing >= 8)
}

/// Pages keep room for the row only when they have tools, and not while the Songs
/// search bar replaces it; before 26.1 the floating dock's height applies.
@MainActor
@Test(arguments: [
    (PageToolsPresentation?.none, true, false, CGFloat(0)),
    (.accessory, false, false, 0),
    (.accessory, true, false, PageToolsDockLayout.pageInset),
    (.accessory, true, true, 0),
    (.floating, true, false, 58), // FloatingPageControls.height
    (.floating, false, false, 0),
] as [(PageToolsPresentation?, Bool, Bool, CGFloat)])
func pageInsetFollowsThePresentation(
    presentation: PageToolsPresentation?, hasItems: Bool, suppressed: Bool, expected: CGFloat
) {
    #expect(FloatingPageControls.inset(
        presentation: presentation, hasItems: hasItems, dockSuppressed: suppressed
    ) == expected)
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
