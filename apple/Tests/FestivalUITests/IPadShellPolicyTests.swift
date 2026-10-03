import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Shell choice

/// iPad uses the sidebar only at regular width; a compact window (Slide Over, narrow
/// Split View or window) falls back to the phone tabs. Phones never use the sidebar.
@Test func sidebarShellFollowsSizeClass() {
    #expect(ShellPresentation.usesSidebarShell(supportsSidebar: true, widthClass: .regular))
    #expect(!ShellPresentation.usesSidebarShell(supportsSidebar: true, widthClass: .compact))
    #expect(!ShellPresentation.usesSidebarShell(supportsSidebar: false, widthClass: .regular))
    #expect(!ShellPresentation.usesSidebarShell(supportsSidebar: false, widthClass: .compact))
}

/// A compact iPad window uses the phone section set (Compete, room for Search), a regular
/// one the sidebar.
@Test func compactIPadUsesPhoneSections() {
    let compact = ShellPresentation.resolve(layout: .standardPhone, usesSidebarShell: false)
    #expect(compact.usesDrawer)
    #expect(compact.sections(profile: .player) == [.songs, .suggestions, .compete, .settings])
    let regular = ShellPresentation.resolve(layout: .standardPhone, usesSidebarShell: true)
    #expect(regular.sections(profile: .player, hideShop: false)
        == [.songs, .suggestions, .statistics, .rivals, .leaderboards, .shop, .settings])
}

// MARK: - Sidebar menu

/// The sidebar mirrors the web sidebar order, Item Shop included, Settings in the footer.
@Test func sidebarMenuMatchesWebSidebar() {
    #expect(SidebarMenu.browse(profile: .none, hideShop: false) == [.songs, .leaderboards, .shop])
    #expect(SidebarMenu.browse(profile: .none, hideShop: true) == [.songs, .leaderboards])
    #expect(SidebarMenu.browse(profile: .player, hideShop: false)
        == [.songs, .suggestions, .statistics, .rivals, .leaderboards, .shop])
    #expect(SidebarMenu.browse(profile: .band, hideShop: false)
        == [.songs, .suggestions, .statistics, .leaderboards, .shop])
    #expect(SidebarMenu.footer == [.settings])
    #expect(FestivalSection.shop.title == "Item Shop")
}

/// ⌘1…⌘9 select destinations in sidebar order; past the end does nothing.
@Test func digitShortcutsFollowSidebarOrder() {
    let visible = SidebarMenu.sections(profile: .none, hideShop: false)
    #expect(SidebarMenu.destination(forDigit: 1, in: visible) == .songs)
    #expect(SidebarMenu.destination(forDigit: 3, in: visible) == .shop)
    #expect(SidebarMenu.destination(forDigit: 4, in: visible) == .settings)
    #expect(SidebarMenu.destination(forDigit: 5, in: visible) == nil)
    #expect(SidebarMenu.destination(forDigit: 0, in: visible) == nil)
}

// MARK: - Width transitions

/// Narrowing a window while Item Shop is selected keeps the Shop on screen, pushed on
/// Songs like the phone drawer; widening again keeps that path.
@Test func narrowingFromItemShopCarriesThePage() {
    let compact = FestivalTabPolicy.sections(profile: .none, regularWidth: false)
    let adapted = FestivalTabPolicy.adapt(selected: .shop, paths: [.songs: []], to: compact)
    #expect(adapted.selected == .songs)
    #expect(adapted.paths[.songs] == [.shop])
    #expect(FestivalTabPolicy.resolve(.shop, in: compact) == .songs)
    let regular = SidebarMenu.sections(profile: .none, hideShop: false)
    let widened = FestivalTabPolicy.adapt(selected: .songs, paths: adapted.paths, to: regular)
    #expect(widened.selected == .songs)
    #expect(widened.paths[.songs] == [.shop])
}

/// Widening a Duo-style Compete slot into the sidebar lands on Leaderboards with its path.
@Test func wideningFromCompeteLandsOnLeaderboards() {
    let regular = SidebarMenu.sections(profile: .player, hideShop: false)
    let adapted = FestivalTabPolicy.adapt(
        selected: .compete, paths: [.compete: [.fullRankings(instrument: .lead, rankBy: "totalscore")]], to: regular
    )
    #expect(adapted.selected == .leaderboards)
    #expect(adapted.paths[.leaderboards] == [.fullRankings(instrument: .lead, rankBy: "totalscore")])
}

// MARK: - Refresh registry

/// ⌘R runs the most recently registered page still on screen.
@MainActor
@Test func refreshRegistryRunsFrontmostPage() async {
    let registry = RefreshCommandRegistry()
    #expect(!registry.canRefresh)
    var ran: [String] = []
    let list = UUID()
    let detail = UUID()
    registry.register(list) { ran.append("list") }
    registry.register(detail) { ran.append("detail") }
    await registry.refresh()
    #expect(ran == ["detail"])
    registry.unregister(detail)
    await registry.refresh()
    #expect(ran == ["detail", "list"])
    // Re-registering moves a page to the front.
    registry.register(detail) { ran.append("detail") }
    registry.register(list) { ran.append("list") }
    await registry.refresh()
    #expect(ran.last == "list")
    registry.unregister(list)
    registry.unregister(detail)
    #expect(!registry.canRefresh)
}

// MARK: - Column layouts

/// iPad sidebar-shell columns get a width class from their own width (two-column
/// dashboards only from 600 pt) and never split again; so do iPhone Duo split
/// columns (`/duo` J3). Without a column width the layout is unchanged.
@Test func sidebarColumnsReclassifyWidth() {
    let iPad = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 1194, height: 834), widthClass: .regular, usesSidebarShell: true
    ))
    #expect(iPad.widthClass == .regular)
    #expect(iPad.column(width: 504).widthClass == .compact)
    #expect(iPad.column(width: 600).widthClass == .regular)
    #expect(iPad.column(width: 874).contentArrangement == .stack)
    #expect(iPad.column(width: 874).sectionChrome == .sidebar)
    #expect(ListDetailStack<EmptyView>.columnLayout(iPad, width: 320).widthClass == .compact)
    #expect(ListDetailStack<EmptyView>.columnLayout(iPad, width: nil) == iPad)
    let duo = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    #expect(ListDetailStack<EmptyView>.columnLayout(duo, width: nil) == duo)
    let duoColumn = ListDetailStack<EmptyView>.columnLayout(duo, width: 300)
    #expect(duoColumn.widthClass == .compact)
    #expect(duoColumn.contentArrangement == .stack)
    #expect(duoColumn.sectionChrome == .verticalBar(.trailing))
    // Sheets opened from a column still size from the window (form sheet).
    #expect(duoColumn.windowWidthClass == .regular)
    #expect(iPad.column(width: 320).windowWidthClass == .regular)
    #expect(duo.windowWidthClass == .regular)
}

/// `/duo` J3: the Duo inner display's detail column is about 350 pt in portrait and
/// under 600 pt in landscape (flat or book), so detail pages get compact layouts;
/// folded Duo and iPhone have no split width.
@Test func duoSplitDetailColumnIsCompact() {
    let portrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, heightClass: .regular,
        hinge: .fullyOpen
    ))
    let portraitWidth = ListDetailPolicy.detailColumnWidth(layout: portrait, containerWidth: nil)
    #expect(portraitWidth == 349)
    #expect(portrait.column(width: portraitWidth ?? 0).widthClass == .compact)

    let landscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular, heightClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 70),
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    let landscapeWidth = ListDetailPolicy.detailColumnWidth(layout: landscape, containerWidth: nil)
    #expect(landscapeWidth == 561)
    #expect(landscape.column(width: landscapeWidth ?? 0).widthClass == .compact)

    // Book pose: the system equalises the columns at the vertical fold.
    let book = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular, heightClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 70),
        verticalBarEdge: .trailing, hinge: .partiallyOpen,
        divisions: [CGRect(x: 463, y: 0, width: 24, height: 669)]
    ))
    #expect(ListDetailPolicy.detailColumnWidth(layout: book, containerWidth: nil) == 394)

    let folded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact, verticalBarEdge: .trailing, hinge: .closed
    ))
    #expect(ListDetailPolicy.detailColumnWidth(layout: folded, containerWidth: nil) == nil)
    #expect(ListDetailPolicy.detailColumnWidth(layout: .standardPhone, containerWidth: nil) == nil)

    let iPad = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 1194, height: 834), widthClass: .regular, usesSidebarShell: true
    ))
    #expect(ListDetailPolicy.detailColumnWidth(layout: iPad, containerWidth: 874) == 554)
    #expect(ListDetailPolicy.detailColumnWidth(layout: iPad, containerWidth: nil) == nil)
}


// MARK: - Menu bar

/// The Go menu lists a fixed set per shell (disabled, never hidden, when not visible)
/// and numbers ⌘1…⌘9 by visible order, like the sidebar's.
@Test func goMenuListsFixedDestinationsAndNumbersVisibleOnes() {
    let anonymous = SidebarMenu.sections(profile: .none, hideShop: true)
    let sidebar = FestivalShellCommands.destinations(sidebar: true, visible: anonymous)
    #expect(sidebar == [.songs, .suggestions, .statistics, .rivals, .leaderboards, .shop, .settings])
    let tabs = FestivalShellCommands.destinations(sidebar: false, visible: [.songs, .leaderboards, .settings])
    #expect(tabs == [.songs, .suggestions, .compete, .leaderboards, .statistics, .settings])
    let commands = FestivalShellCommands(
        destinations: sidebar, visible: anonymous, selected: .songs, canGoBack: false,
        sheetOpen: false, hasPlayer: false, select: { _ in }, goBack: {}, search: {}, refresh: {},
        chooseProfile: {}, deselectProfile: {}, notifications: {}, whatsNew: {}, licenses: {}
    )
    #expect(commands.digit(for: .songs) == 1)
    #expect(commands.digit(for: .leaderboards) == 2)
    #expect(commands.digit(for: .settings) == 3)
    #expect(commands.digit(for: .shop) == nil, "Hide Item Shop: listed, disabled, no shortcut")
    #expect(commands.digit(for: .rivals) == nil)
}
