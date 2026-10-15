#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Page tools in the menu bar (issue #633, page-tools-and-nav-chrome R28)
//
// HIG Toolbars › macOS: "Every toolbar item must also be a menu-bar command" (must).
// `MacCommands` (macOS) and `FestivalCommands` (the iPadOS menu bar) both lay out the
// shared `PageToolViewMenuItems` / `PageToolProfileMenuItems` over the front page's
// focused values. A menu bar is not hostable, so these tests host the real pages beside
// `PageToolMenuBarMirror`, which reads the same `@FocusedValue` keys the menu bars read
// and lays the shared items out as controls. They pin, per page, each command's
// accessible name and role, its enabled state, its checkmark, and that pressing it
// (AXPress) acts on the page in focus. `menuBarsLayOutTheSharedPageToolItems` pins that
// both menu bars keep using those items; the iPad shell is driven by the iPadOS journey
// `IPadMenuBarJourneyTests` (the same mirror in the real app, `FST_DEBUG_MENU_BAR=1`).

private let menuProbeID = PageToolMenuBarMirror.identifier
private let probeWidth: CGFloat = 260

/// The names the menu bar lists, in menu order, with every page tool unavailable.
private let menuNames = [
    "Sort…", "Filter…", "Rank By", "Instrument", "Band Size", "as List", "as Grid",
] + BandType.allCases.map(\.label) + ["Select This Profile", "View Rival's Profile", "Find Rival…"]

/// A hosted page beside the menu-bar probe.
@MainActor
private struct MenuBarHost {
    let host: NSHostingView<NativeHostedRoot<AnyView>>
    let window: NSWindow

    /// Host `page` (in a navigation stack, as the shell shows it) beside the probe.
    ///
    /// - Parameters:
    ///   - page: The page, or nil for a window with no page tools in front.
    ///   - pageWidth: The page column's width.
    ///   - storage: App storage (Item Shop's List/Grid choice).
    ///   - pushRoute: Captures pushes (View Rival's Profile).
    ///   - blocked: Whether a sheet covers the window.
    init(
        _ page: AnyView?, pageWidth: CGFloat = 820, storage: UserDefaults? = nil,
        pushRoute: PushRouteAction? = nil, blocked: Bool = false
    ) {
        let size = CGSize(width: pageWidth + probeWidth, height: 1100)
        let storage = storage ?? UserDefaults(suiteName: "fst.tests.menu-bar.\(UUID().uuidString)")!
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        host = nativeHostedView(
            AnyView(
                HStack(alignment: .top, spacing: 0) {
                    if let page {
                        NavigationStack { page }
                            .frame(width: pageWidth, height: size.height)
                            .environment(\.pushRoute, pushRoute)
                    }
                    PageToolMenuBarMirror(blocked: blocked, experimentalRanks: false).frame(width: probeWidth)
                }
                .defaultAppStorage(storage)
                .environment(\.horizontalSizeClass, .regular)
                .preferredColorScheme(.dark)
            ),
            size: size
        )
        window = nativeHostedWindow(host, size: size)
    }

    /// The probe's menu items in reading order.
    var items: [MacAXNode] {
        let nodes = macAccessibilityTree(host)
        guard let start = nodes.firstIndex(where: { $0.identifier == menuProbeID }) else { return [] }
        let depth = nodes[start].depth
        return Array(nodes[(start + 1)...].prefix { $0.depth > depth }.filter { $0.isElement && !$0.spokenName.isEmpty })
    }

    /// The probe item named `name`.
    func item(_ name: String) -> MacAXNode? { items.first { $0.spokenName == name } }

    /// Wait until `ready` holds for the probe's items.
    func settle(_ ready: @escaping @MainActor (MenuBarHost) -> Bool, timeout: Duration = .seconds(60)) async throws {
        _ = try await nativeHostedSettle(host, timeout: timeout) { ready(self) }
    }

    /// Press the probe item named `name` (VoiceOver / Full Keyboard Access activation).
    func press(_ name: String) throws {
        let probe = try #require(nativeHostedAccessibilityElement(menuProbeID, in: host))
        let element = try #require(Self.find(name, under: probe), "no menu item \(name)")
        _ = element.perform(NSSelectorFromString("accessibilityPerformPress"))
    }

    private static func find(_ name: String, under root: NSObject) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func walk(_ node: Any, depth: Int) -> NSObject? {
            guard depth < 40, let object = node as? NSObject, seen.insert(ObjectIdentifier(object)).inserted
            else { return nil }
            if nativeHostedAccessibilityString(object, "accessibilityLabel") == name
                || nativeHostedAccessibilityString(object, "accessibilityTitle") == name { return object }
            let children = object.responds(to: NSSelectorFromString("accessibilityChildren"))
                ? (object.value(forKey: "accessibilityChildren") as? [Any]) ?? [] : []
            for child in children { if let found = walk(child, depth: depth + 1) { return found } }
            return nil
        }
        return walk(root, depth: 0)
    }

    /// Whether the item named `name` is enabled.
    func isEnabled(_ name: String) -> Bool { item(name)?.isEnabled == true }

    /// Whether the toggle named `name` carries its checkmark.
    func isChecked(_ name: String) -> Bool { item(name)?.value == "1" }
}

/// A session over the shared loopback fixture service, optionally with a selected player.
@MainActor
private func menuBarSession(selected accountId: String? = nil) async throws -> FestivalSession {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    let storage = try #require(UserDefaults(suiteName: "fst.tests.menu-bar.session.\(UUID().uuidString)"))
    if let accountId {
        let identity = ["accountId": accountId, "displayName": "Fixture Menu Player"]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        storage.set(true, forKey: "fst.settings.showLead")
    }
    return FestivalSession(factory: { client }, selectionStorage: storage)
}

// MARK: - Names, roles and disabled states

/// With no page tools in front, the menu bar still lists every page tool in toolbar
/// order with its role, each disabled (HIG The menu bar: "Disable, don't hide,
/// unavailable items"; Menus: a submenu "remains available even when its items are
/// unavailable"), and the identity item takes its Select title.
@MainActor
@Test func pageToolMenuItemsAreNamedListedInOrderAndDisabledWithoutAPage() async throws {
    let menu = MenuBarHost(nil)
    defer { menu.window.orderOut(nil) }
    try await menu.settle { $0.items.count >= menuNames.count }
    let items = menu.items
    #expect(items.map(\.spokenName) == menuNames, "\(items)")
    for item in items {
        switch item.spokenName {
        case "Rank By", "Instrument", "Band Size":
            #expect(["AXMenuButton", "AXPopUpButton"].contains(item.role), "a submenu: \(item)")
            #expect(item.isEnabled, "the submenu stays available: \(item)")
        case "as List", "as Grid":
            #expect(item.role == "AXCheckBox", "a checkmarked choice: \(item)")
            #expect(!item.isEnabled && item.value == "0", "\(item)")
        case _ where BandType.allCases.map(\.label).contains(item.spokenName):
            #expect(item.role == "AXCheckBox", "a checkmarked band size: \(item)")
            #expect(!item.isEnabled && item.value == "0", "\(item)")
        default:
            #expect(item.role == "AXButton", "\(item)")
            #expect(!item.isEnabled, "nothing in front offers \(item.spokenName)")
        }
    }
    #expect(macAccessibilityFindings(items).isEmpty, "\(macAccessibilityFindings(items))")
}

/// A sheet over the window disables the commands that present or navigate, even while
/// the page beneath still offers them.
@MainActor
@Test func pageToolMenuItemsAreDisabledUnderASheet() async throws {
    let page = AnyView(Color.clear
        .macPageCommands(MacPageCommands(
            filter: {}, findRival: {}, layout: MacLayoutChoice(isGrid: true) { _ in }
        ))
        .macProfilePageCommands(MacProfilePageCommands(
            identity: .switchTo, performIdentity: {}, viewRivalProfile: {}
        )))
    let open = MenuBarHost(page, pageWidth: 40)
    defer { open.window.orderOut(nil) }
    try await open.settle { $0.isEnabled("Filter…") && $0.isEnabled("Switch to This Profile") }
    for name in ["Filter…", "as List", "as Grid", "Switch to This Profile", "View Rival's Profile", "Find Rival…"] {
        #expect(open.isEnabled(name), "\(name) acts on the page in front")
    }
    #expect(!open.isEnabled("Sort…"), "the page offers no Sort")
    #expect(open.isChecked("as Grid") && !open.isChecked("as List"))

    let covered = MenuBarHost(page, pageWidth: 40, blocked: true)
    defer { covered.window.orderOut(nil) }
    try await covered.settle { $0.item("Switch to This Profile") != nil }
    for name in ["Filter…", "as List", "as Grid", "Switch to This Profile", "View Rival's Profile", "Find Rival…"] {
        #expect(!covered.isEnabled(name), "\(name) must not stack on a sheet")
    }
}

/// Both menu bars lay out the shared items over the front page's values, so the items
/// the mirror proves here are the ones each menu bar lists: macOS `MacCommands` and the
/// iPadOS `FestivalCommands` (a `Commands` body cannot be hosted).
@Test func menuBarsLayOutTheSharedPageToolItems() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/FestivalUI")
    for file in ["Mac/MacCommands.swift", "App/Shell/FestivalCommands.swift"] {
        let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
        #expect(text.contains("PageToolViewMenuItems(state: pageTools)"), "\(file) lists the View page tools")
        #expect(text.contains("PageToolProfileMenuItems(state: pageTools)"), "\(file) lists the Profile page tools")
        for key in ["macPageCommands", "macRankBy", "macInstrument", "macBandSize", "macProfilePageCommands"] {
            #expect(text.contains("@FocusedValue(\\.\(key))"), "\(file) reads \(key) like the mirror")
        }
        let state = try #require(text.range(of: "PageToolMenuState(")).upperBound
        let call = text[state...].prefix(240)
        #expect(call.contains("page: pageCommands, rankBy: rankBy, instrument: instrument, bandSize: bandSize"), "\(file): \(call)")
        #expect(call.contains("profile: profilePageCommands"), "\(file): \(call)")
    }
}

// MARK: - Invocation against the page in front

/// Item Shop: View › as List / as Grid checks the layout in effect and switches the
/// page's layout; Sort… and Filter… are offered.
@MainActor
@Test func shopLayoutMenuItemsFollowAndSwitchThePage() async throws {
    let bytes = try shopFixtureBytes()
    let transport = HostedShopTransport(scenario: .populated, offers: bytes.offers, catalogue: bytes.catalogue)
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let storage = try #require(UserDefaults(suiteName: "fst.tests.menu-bar.shop.\(UUID().uuidString)"))
    let menu = MenuBarHost(AnyView(ShopScreen(session: session, isVisible: true)), storage: storage)
    defer { menu.window.orderOut(nil) }
    try await menu.settle { $0.isEnabled("as List") && $0.isChecked("as Grid") }
    #expect(menu.isEnabled("as Grid") && !menu.isChecked("as List"))
    #expect(menu.isEnabled("Sort…") && menu.isEnabled("Filter…"))
    #expect(!menu.isEnabled("Select This Profile") && !menu.isEnabled("Find Rival…"))

    try menu.press("as List")
    try await menu.settle { $0.isChecked("as List") && !$0.isChecked("as Grid") }
    #expect(storage.string(forKey: "fst.shop.viewMode") == ShopViewMode.list.rawValue, "the page shows its list")
    try menu.press("as Grid")
    try await menu.settle { $0.isChecked("as Grid") }
    #expect(storage.string(forKey: "fst.shop.viewMode") == ShopViewMode.grid.rawValue)
}

/// Suggestions: View › Filter… is offered once the selected player's scores are
/// available, and opens the page's Filter sheet; nothing else in View applies.
@MainActor
@Test func suggestionsFilterMenuItemOpensThePageFilter() async throws {
    let session = try await menuBarSession(selected: "fixture-player-1")
    let menu = MenuBarHost(
        AnyView(SuggestionsScreen(session: session, visibleInstruments: Set(Instrument.allCases))), pageWidth: 402
    )
    defer { menu.window.orderOut(nil) }
    try await menu.settle { $0.isEnabled("Filter…") }
    #expect(!menu.isEnabled("Sort…") && !menu.isEnabled("as List"))
    let earlier = Set(NSApp.windows.map(ObjectIdentifier.init))
    // SwiftUI presents the sheet in its own window, attached only to an on-screen parent
    // (a hosted window never is), so look for the new window holding the filter form.
    let filterSheet = {
        menu.window.attachedSheet ?? NSApp.windows.first { candidate in
            candidate !== menu.window && !earlier.contains(ObjectIdentifier(candidate))
                && candidate.contentView.map {
                    nativeHostedAccessibilityElement("fst.suggestions.filter.reset", in: $0) != nil
                } == true
        }
    }
    #expect(filterSheet() == nil)
    try menu.press("Filter…")
    _ = try await nativeHostedSettle(menu.host) { filterSheet() != nil }
    let sheet = try #require(filterSheet(), "Filter… presents the Suggestions filter")
    sheet.orderOut(nil)
}

/// Band boards: View › Band Size checks the board's size and switches it.
@MainActor
@Test func bandSizeMenuItemsFollowAndSwitchTheBoard() async throws {
    let session = try await menuBarSession()
    let menu = MenuBarHost(AnyView(BandRankingsScreen(session: session, bandType: "Band_Duets")), pageWidth: 402)
    defer { menu.window.orderOut(nil) }
    try await menu.settle { $0.isChecked(BandType.duets.label) }
    for size in BandType.allCases {
        #expect(menu.isEnabled(size.label), "\(size.label) is offered on the board")
    }
    try menu.press(BandType.trios.label)
    try await menu.settle { $0.isChecked(BandType.trios.label) && !$0.isChecked(BandType.duets.label) }
    let pageMenu = { macAccessibilityTree(menu.host).first { $0.identifier == "fst.band-rankings.band-type-menu" } }
    _ = try await nativeHostedSettle(menu.host) { pageMenu()?.value == BandType.trios.label }
    #expect(pageMenu()?.value == BandType.trios.label, "the board's own Band size reads Trios: \(String(describing: pageMenu()))")
}

/// Player page: Profile › Select This Profile is offered once the read proves it and
/// selects the shown player.
@MainActor
@Test func selectThisProfileMenuItemSelectsTheShownPlayer() async throws {
    let session = try await menuBarSession()
    let menu = MenuBarHost(AnyView(
        PlayerProfileContent(session: session, accountId: "fixture-player-1", routeDisplayName: nil)
    ), pageWidth: 402)
    defer { menu.window.orderOut(nil) }
    try await menu.settle { $0.isEnabled("Select This Profile") }
    #expect(!menu.isEnabled("View Rival's Profile"))
    #expect(session.selectedPlayer == nil)
    try menu.press("Select This Profile")
    _ = try await nativeHostedSettle(menu.host) { session.selectedPlayer?.accountId == "fixture-player-1" }
    #expect(session.selectedPlayer?.accountId == "fixture-player-1")
    try await menu.settle { !$0.isEnabled("Select This Profile") }
    #expect(menu.item("Switch to This Profile") == nil, "nothing to select on your own page")
}

/// Rivalry and Rival Detail: Profile › View Rival's Profile opens the rival's player page.
@MainActor
@Test(arguments: [false, true])
func viewRivalsProfileMenuItemOpensTheRival(detail: Bool) async throws {
    let session = try await menuBarSession(selected: "fixture-riv")
    let rivalId = "f1c749eb07c32578cfa3e59ec38c03a8"
    let page = detail
        ? AnyView(RivalDetailScreen(
            session: session, rivalId: rivalId, name: "Fixture Rival Golf", scope: .song(instruments: ["Solo_Guitar"])
        ))
        : AnyView(RivalryScreen(
            session: session, rivalId: rivalId, mode: "closest_battles",
            name: "Fixture Rival Golf", scope: .song(instruments: ["Solo_Guitar"])
        ))
    var pushed: [AppRoute] = []
    let menu = MenuBarHost(page, pageWidth: 402, pushRoute: PushRouteAction { pushed.append($0) })
    defer { menu.window.orderOut(nil) }
    try await menu.settle { $0.isEnabled("View Rival's Profile") }
    #expect(!menu.isEnabled("Select This Profile"))
    try menu.press("View Rival's Profile")
    _ = try await nativeHostedSettle(menu.host) { !pushed.isEmpty }
    #expect(pushed == [.player(accountId: rivalId, displayName: "Fixture Rival Golf")])
}
#endif
