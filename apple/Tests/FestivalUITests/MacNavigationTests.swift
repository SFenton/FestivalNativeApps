import CoreGraphics
import Foundation
import Testing
@testable import FestivalUI

// MARK: - Sidebar policy

/// Anonymous: Songs, Leaderboards, Item Shop (web pinned sidebar without a player).
@Test func macSidebarAnonymousDestinations() {
    #expect(MacSidebarPolicy.destinations(hasPlayer: false, hideShop: false) == [.songs, .leaderboards, .shop])
}

/// With a player: the web order Songs, Suggestions, Statistics, Rivals, Compete,
/// Leaderboards, Item Shop; Settings › Hide Item Shop removes the Shop row.
@Test func macSidebarPlayerDestinationsAndHiddenShop() {
    #expect(MacSidebarPolicy.destinations(hasPlayer: true, hideShop: false)
        == [.songs, .suggestions, .statistics, .rivals, .compete, .leaderboards, .shop])
    #expect(!MacSidebarPolicy.destinations(hasPlayer: true, hideShop: true).contains(.shop))
}

/// Titles are Title Case and every row has a symbol and a stable identifier.
@Test func macDestinationLabels() {
    #expect(MacDestination.shop.title == "Item Shop")
    #expect(MacDestination.leaderboards.title == "Leaderboards")
    for destination in MacDestination.allCases {
        #expect(!destination.symbol.isEmpty)
        #expect(destination.accessibilityIdentifier == "fst.nav.\(destination.rawValue)")
        #expect(destination.requiresPlayer == (destination.section.map {
            [.suggestions, .statistics, .rivals, .compete].contains($0)
        } ?? false))
    }
}

/// A hidden selection falls back: Rivals/Compete to Leaderboards (same web slot), the
/// rest to the first row.
@Test func macSidebarResolveFallbacks() {
    let anonymous = MacSidebarPolicy.destinations(hasPlayer: false, hideShop: false)
    #expect(MacSidebarPolicy.resolve(.rivals, in: anonymous) == .leaderboards)
    #expect(MacSidebarPolicy.resolve(.compete, in: anonymous) == .leaderboards)
    #expect(MacSidebarPolicy.resolve(.statistics, in: anonymous) == .songs)
    #expect(MacSidebarPolicy.resolve(.shop, in: [.songs, .leaderboards]) == .songs)
    #expect(MacSidebarPolicy.resolve(.leaderboards, in: anonymous) == .leaderboards)
    #expect(MacSidebarPolicy.resolve(.songs, in: []) == .songs)
}

/// ⌘n selects the n-th visible row; out-of-range numbers do nothing.
@Test func macSidebarShortcutNumbers() {
    let visible = MacSidebarPolicy.destinations(hasPlayer: false, hideShop: false)
    #expect(MacSidebarPolicy.destination(forShortcut: 1, in: visible) == .songs)
    #expect(MacSidebarPolicy.destination(forShortcut: 3, in: visible) == .shop)
    #expect(MacSidebarPolicy.destination(forShortcut: 4, in: visible) == nil)
    #expect(MacSidebarPolicy.destination(forShortcut: 0, in: visible) == nil)
}

/// Shared sections and root routes map onto sidebar rows; Settings is its own window.
@Test func macSidebarSectionAndRouteMapping() {
    #expect(MacSidebarPolicy.destination(for: FestivalSection.settings) == nil)
    for section in FestivalSection.allCases where section != .settings && section != .shop {
        #expect(MacSidebarPolicy.destination(for: section)?.section == section)
    }
    // The shared sidebar-only Item Shop section (iPad) selects the Mac Item Shop row.
    #expect(MacSidebarPolicy.destination(for: FestivalSection.shop) == .shop)
    #expect(MacSidebarPolicy.destination(for: AppRoute.shop) == .shop)
    #expect(MacSidebarPolicy.destination(for: AppRoute.statistics) == .statistics)
    #expect(MacSidebarPolicy.destination(for: AppRoute.licenses) == nil)
    #expect(MacSidebarPolicy.destination(for: AppRoute.bands) == nil)
}

// MARK: - Back

private let rival = AppRoute.rivalDetail(rivalId: "r1", name: "R", scope: nil)
private let rankings = AppRoute.fullRankings(instrument: .lead, rankBy: "totalscore")
private let player = AppRoute.player(accountId: "p1", displayName: "P")

/// One column: Back pops one route; nothing to pop is unavailable.
@Test func macBackInOneColumn() {
    #expect(MacSidebarPolicy.backPath([], section: .songs, split: false) == nil)
    #expect(MacSidebarPolicy.backPath([rival, player], section: .rivals, split: false) == [rival])
    #expect(MacSidebarPolicy.backPath([.licenses], section: nil, split: true) == [])
}

/// Two columns: the detail root of a root list is never popped (it would only be
/// auto-selected again); pushes inside the detail pop first; a pushed list page pops
/// with its selection.
@Test func macBackInTwoColumns() {
    #expect(MacSidebarPolicy.backPath([rival], section: .rivals, split: true) == nil)
    #expect(MacSidebarPolicy.backPath([rival, player], section: .rivals, split: true) == [rival])
    #expect(MacSidebarPolicy.backPath([rankings, player], section: .leaderboards, split: true) == [])
    #expect(MacSidebarPolicy.backPath([rankings], section: .leaderboards, split: true) == [])
}

// MARK: - Layout policy

/// Two columns from 820 pt with a list page; regular width from 720 pt per column.
@Test func macLayoutWidths() {
    #expect(!MacLayoutPolicy.showsSplit(width: 819, hasListPage: true, emptyListCollapsed: false))
    #expect(MacLayoutPolicy.showsSplit(width: 820, hasListPage: true, emptyListCollapsed: false))
    #expect(!MacLayoutPolicy.showsSplit(width: 1400, hasListPage: false, emptyListCollapsed: false))
    #expect(!MacLayoutPolicy.showsSplit(width: 1400, hasListPage: true, emptyListCollapsed: true))
    #expect(MacLayoutPolicy.widthClass(forWidth: 719) == .compact)
    #expect(MacLayoutPolicy.widthClass(forWidth: 720) == .regular)
    #expect(MacLayoutPolicy.listColumn.min + MacLayoutPolicy.detailMinimumWidth
        <= MacLayoutPolicy.splitMinimumWidth)
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 820) == 340)
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 1060) == 1060 * 0.38)
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 3000) == 560)
}

/// A dragged divider width is remembered but clamped: never narrower than the list
/// minimum, never wider than the drag maximum or than leaves the detail its minimum.
@Test func macDraggedListWidthIsClampedSoTheDividerStaysVisible() {
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 1060, preferred: nil) == 1060 * 0.38)
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 1060, preferred: 0) == 1060 * 0.38)
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 1060, preferred: 450) == 450)
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 1060, preferred: 100) == 340)
    // 1060 − 480 − 1 leaves the detail its minimum.
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 1060, preferred: 900) == 579)
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 3000, preferred: 900) == 680)
    // At the narrowest split the list never drops below its minimum.
    #expect(MacLayoutPolicy.listWidth(forContentWidth: 820, preferred: 600) == 340)
    #expect(MacLayoutPolicy.pageMaxWidth(for: nil) == 1400)
    #expect(MacLayoutPolicy.pageMaxWidth(for: nil, isShopRoot: true) == 2170)
    #expect(MacLayoutPolicy.pageMaxWidth(for: .shop) == 2170)
    #expect(MacLayoutPolicy.pageMaxWidth(for: .licenses) == 1400)
}

// MARK: - Navigation model

/// Selection persists to storage and restores; a launch override wins without writing.
@MainActor
@Test func macNavigationRestoresSelection() throws {
    let suite = "fst.tests.mac.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let visible = MacSidebarPolicy.destinations(hasPlayer: true, hideShop: false)
    let first = MacNavigationModel(storage: defaults, visible: visible)
    #expect(first.selected == .songs)
    first.select(.rivals)
    #expect(defaults.string(forKey: MacNavigationModel.selectionKey) == "rivals")
    #expect(MacNavigationModel(storage: defaults, visible: visible).selected == .rivals)
    // Restored while the player is gone: Leaderboards (the Rivals slot).
    let anonymous = MacSidebarPolicy.destinations(hasPlayer: false, hideShop: false)
    #expect(MacNavigationModel(storage: defaults, visible: anonymous).selected == .leaderboards)
    #expect(MacNavigationModel(storage: defaults, initial: .shop, visible: visible).selected == .shop)
}

/// Re-selecting returns to the root, leaving Statistics clears it, other paths stay.
@MainActor
@Test func macNavigationSelectSemantics() {
    let visible = MacSidebarPolicy.destinations(hasPlayer: true, hideShop: false)
    let model = MacNavigationModel(storage: nil, visible: visible)
    model.push(.licenses)
    #expect(model.canGoBack)
    model.select(.statistics)
    model.push(player)
    model.select(.songs)
    #expect(model.paths[.statistics] == [])
    #expect(model.paths[.songs] == [.licenses])
    model.select(.songs)
    #expect(model.currentPath.isEmpty)
    #expect(!model.canGoBack)
    model.selectShortcut(4)
    #expect(model.selected == .rivals)
    model.selectShortcut(42)
    #expect(model.selected == .rivals)
}

/// Back respects the reported two-column state.
@MainActor
@Test func macNavigationBackUsesSplitState() {
    let model = MacNavigationModel(storage: nil, initial: .rivals, visible: MacDestination.allCases)
    model.paths[.rivals] = [rival]
    #expect(model.canGoBack)
    model.splitDestinations.insert(.rivals)
    #expect(!model.canGoBack)
    model.push(player)
    model.goBack()
    #expect(model.currentPath == [rival])
    model.refresh()
    #expect(model.refreshGeneration == 1)
}

/// Deselecting the player moves off player-only rows; hiding the Shop trims paths.
@MainActor
@Test func macNavigationAdaptsToVisibility() {
    let model = MacNavigationModel(storage: nil, initial: .statistics, visible: MacDestination.allCases)
    model.push(player)
    model.paths[.songs] = [.shop, .licenses]
    model.update(visible: [.songs, .leaderboards])
    #expect(model.selected == .songs)
    #expect(model.paths[.statistics] == [])
    #expect(model.paths[.songs] == [])
    model.select(.shop)
    #expect(model.selected == .songs)
}

// MARK: - Debug hooks

#if os(macOS)
/// `FST_DEBUG_WINDOW_SIZE` parsing and the top-anchored resize frame.
@Test func macDebugHooksSizeParsing() {
    #expect(MacDebugHooks.parseSize("1280x800") == CGSize(width: 1280, height: 800))
    #expect(MacDebugHooks.parseSize("1280X800") == CGSize(width: 1280, height: 800))
    #expect(MacDebugHooks.parseSize("1280") == nil)
    #expect(MacDebugHooks.parseSize("0x800") == nil)
    let frame = MacDebugHooks.topAnchoredFrame(
        CGRect(x: 10, y: 100, width: 400, height: 300), newFrameSize: CGSize(width: 800, height: 600)
    )
    #expect(frame == CGRect(x: 10, y: -200, width: 800, height: 600))
}
#endif

#if os(macOS)
/// `tools/mac_app.py command` text parses into shell commands; junk is rejected.
@Test func macDebugCommandParsing() {
    #expect(MacDebugCommand("select:3") == .select(nil, number: 3))
    #expect(MacDebugCommand("select:shop") == .select(.shop, number: nil))
    #expect(MacDebugCommand("route:player:abc") == .route("player:abc"))
    #expect(MacDebugCommand("back") == .back)
    #expect(MacDebugCommand("whatsnew") == .whatsNew)
    #expect(MacDebugCommand("sort") == .sort)
    #expect(MacDebugCommand("select:nowhere") == nil)
    #expect(MacDebugCommand("back:1") == nil)
    #expect(MacDebugCommand("settings") == .settings)
    #expect(MacDebugCommand("settings:paths") == .settingsPane(.paths))
    #expect(MacDebugCommand("settings:nowhere") == nil)
    #expect(MacDebugCommand("menus") == .menus)
    #expect(MacDebugCommand("song:history") == .song("history"))
    #expect(MacDebugCommand("song:nowhere") == nil)
    #expect(MacDebugCommand("explode") == nil)
}
#endif
