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

// MARK: - Pane layouts

/// On-demand split panes get a width class from their own width (two-column
/// dashboards only from 600 pt) and never split again; without a width the layout is
/// unchanged. Sheets opened from a pane still size from the window.
@Test func splitPanesReclassifyWidth() {
    let iPad = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 1194, height: 834), widthClass: .regular, usesSidebarShell: true
    ))
    #expect(iPad.widthClass == .regular)
    #expect(iPad.column(width: 504).widthClass == .compact)
    #expect(iPad.column(width: 600).widthClass == .regular)
    #expect(iPad.column(width: 874).contentArrangement == .stack)
    #expect(iPad.column(width: 874).sectionChrome == .sidebar)
    let duo = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    let pane = duo.column(width: 475)
    #expect(pane.widthClass == .compact)
    #expect(pane.sectionChrome == .verticalBar(.trailing))
    #expect(pane.windowWidthClass == .regular)
    // The hinge survives re-classification, so a pane's pages could still see it.
    #expect(pane.splitHinge == duo.splitHinge)
    #expect(iPad.column(width: 320).windowWidthClass == .regular)
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
