#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Accessibility tree walker

/// One node of a hosted AppKit accessibility tree, in walk order.
struct MacAXNode: CustomStringConvertible {
    let depth: Int
    let role: String
    let subrole: String
    let label: String
    let title: String
    let value: String
    let identifier: String
    let selected: Bool
    let help: String
    /// `isAccessibilityElement`: false for containers and for elements assistive
    /// technologies skip (SwiftUI's `accessibilityHidden`).
    let isElement: Bool

    /// The name VoiceOver speaks first: label, else title, else value.
    var spokenName: String { [label, title, value].first { !$0.isEmpty } ?? "" }

    var description: String {
        "\(String(repeating: " ", count: depth))\(role)\(subrole.isEmpty ? "" : "/\(subrole)")"
            + " '\(spokenName)'" + (!value.isEmpty && value != spokenName ? " = '\(value)'" : "")
            + (identifier.isEmpty ? "" : " #\(identifier)") + (selected ? " [selected]" : "")
            + (isElement ? "" : " (not element)")
    }
}

/// Walk the accessibility tree of a hosted view (accessibility children and AppKit
/// subviews), recording role, names, identifier and selection for each element.
@MainActor
func macAccessibilityTree(_ root: NSView) -> [MacAXNode] {
    var nodes: [MacAXNode] = []
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func string(_ object: NSObject, _ key: String) -> String {
        switch read(object, key) {
        case let text as String: text
        case let attributed as NSAttributedString: attributed.string
        case let number as NSNumber: number.stringValue
        default: ""
        }
    }
    func walk(_ node: Any, depth: Int) {
        guard depth < 90, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return }
        let isElement = (read(object, "isAccessibilityElement") as? Bool) ?? false
        let role = string(object, "accessibilityRole")
        if isElement || !role.isEmpty {
            nodes.append(MacAXNode(
                depth: depth, role: role, subrole: string(object, "accessibilitySubrole"),
                label: string(object, "accessibilityLabel"), title: string(object, "accessibilityTitle"),
                value: string(object, "accessibilityValue"), identifier: string(object, "accessibilityIdentifier"),
                selected: (read(object, "isAccessibilitySelected") as? Bool) ?? false,
                help: string(object, "accessibilityHelp"), isElement: isElement
            ))
        }
        for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, depth: depth + 1)
        }
        if let view = object as? NSView {
            for subview in view.subviews { walk(subview, depth: depth + 1) }
        }
    }
    walk(root, depth: 0)
    return nodes
}

/// Write a tree dump next to other private captures when `FST_MAC_AX_OUT` names a directory.
func macAccessibilityDump(_ nodes: [MacAXNode], name: String) {
    guard let dir = ProcessInfo.processInfo.environment["FST_MAC_AX_OUT"] else { return }
    let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).txt")
    try? nodes.map(\.description).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
}

// MARK: - Findings

/// Elements an assistive technology can act on or that convey content: each needs a name.
private let macNamedRoles: Set<String> = [
    "AXButton", "AXImage", "AXCheckBox", "AXPopUpButton", "AXRadioButton", "AXSlider",
    "AXTextField", "AXSearchField", "AXLink", "AXMenuButton", "AXDisclosureTriangle", "AXIncrementor",
]

/// Accessibility-tree problems VoiceOver would hit: an unnamed control or image, and a
/// decorative image that repeats the name of the element right after it (read twice).
func macAccessibilityFindings(_ nodes: [MacAXNode]) -> [String] {
    var findings: [String] = []
    // System scroller parts are named by their role description.
    let scrollerParts: Set<String> = ["AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage"]
    let elements = nodes.filter { $0.isElement && !scrollerParts.contains($0.subrole) }
    for (index, node) in elements.enumerated() {
        if macNamedRoles.contains(node.role), node.spokenName.trimmingCharacters(in: .whitespaces).isEmpty {
            findings.append("unnamed \(node.role) #\(node.identifier)")
        }
        // Swift Charts names an unlabelled mark by its plotted range ("0 to 1").
        if node.spokenName.range(of: #"^\d+(\.\d+)? to \d+(\.\d+)?$"#, options: .regularExpression) != nil {
            findings.append("chart mark named by its plotted range '\(node.spokenName)' #\(node.identifier)")
        }
        if node.role == "AXImage", index + 1 < elements.count,
           !node.spokenName.isEmpty, elements[index + 1].spokenName == node.spokenName {
            findings.append("image repeats '\(node.spokenName)' (\(elements[index + 1].role))")
        }
    }
    return findings
}

// MARK: - Fixtures

/// Readiness budget for a whole Mac window over the loopback service.
private let macTreeBudget: Duration = .seconds(120)

/// A session over the loopback fixture service (`tools/mock_service.py`), optionally with
/// `fixture-player-1` selected.
@MainActor
private func macTreeSession(player: Bool) async throws -> FestivalSession {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    let defaults = try #require(UserDefaults(suiteName: "fst.tests.mac-ax.\(UUID().uuidString)"))
    defaults.set(true, forKey: "fst.accessibility.reduceMotion")
    if player {
        defaults.set(
            Data(#"{"accountId":"fixture-player-1","displayName":"Fixture Player 1"}"#.utf8),
            forKey: SelectedPlayerIdentity.storageKey
        )
    }
    return FestivalSession(factory: { client }, selectionStorage: defaults)
}

/// The whole Mac window content at its default size.
@MainActor
private func hostMacRootTree(_ session: FestivalSession, initial: MacDestination)
    -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow, MacAppModel) {
    let size = MacWindowMetrics.defaultSize
    let model = MacAppModel(session: session, storage: nil, initial: initial)
    let host = nativeHostedView(
        MacRootView(model: model)
            .frame(width: size.width, height: size.height),
        size: size
    )
    return (host, nativeHostedWindow(host, size: size), model)
}

/// The sidebar's outline view.
@MainActor
private func macSidebarOutline(_ view: NSView) -> NSOutlineView? {
    if let outline = view as? NSOutlineView { return outline }
    for subview in view.subviews {
        if let outline = macSidebarOutline(subview) { return outline }
    }
    return nil
}

/// Rows of an outline reporting the accessibility selected state (legacy attribute API:
/// `NSOutlineRow` is not an `NSAccessibilityElement`).
@MainActor
private func macSelectedRows(_ outline: NSOutlineView) -> [Int] {
    let rows = (outline.accessibilityAttributeValue(.rows) as? [AnyObject]) ?? []
    return rows.enumerated().compactMap { index, row in
        (row.accessibilityAttributeValue(.selected) as? Bool) == true ? index : nil
    }
}

/// Whole-window trees are heavy (a full `MacRootView` over the loopback service each):
/// run them one at a time, with a generous readiness budget, so the parallel hosted
/// suite does not starve their loads.
@MainActor
@Suite(.serialized)
struct MacAccessibilityTreeTests {
    // MARK: - Sidebar

    /// The sidebar is an outline whose rows are named for their destination, exactly one row
    /// is selected for assistive technologies, and the selection follows the destination
    /// (HIG Split views: "Persistently highlight the current selection in each pane").
    @Test func macTreeSidebarSelectionFollowsDestination() async throws {
        let (host, window, model) = hostMacRootTree(try await macTreeSession(player: true), initial: .leaderboards)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Leaderboards", "Fixture Player 1"], timeout: macTreeBudget)
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "sidebar")
        let outline = try #require(nodes.first { $0.role == "AXOutline" })
        #expect(outline.spokenName == "Sidebar")
        for destination in model.navigation.visible {
            #expect(nodes.contains { $0.identifier == "fst.nav.\(destination.rawValue)" && $0.spokenName == destination.title },
                    "sidebar row \(destination.title)")
        }
        let table = try #require(macSidebarOutline(host))
        for destination in [MacDestination.leaderboards, .shop, .statistics] {
            model.navigation.select(destination)
            try await nativeHostedSettle(host, timeout: macTreeBudget, until: {
                macSelectedRows(table) == [model.navigation.visible.firstIndex(of: destination) ?? -1]
            })
            #expect(macSelectedRows(table) == [model.navigation.visible.firstIndex(of: destination) ?? -1],
                    "\(destination.title) is the one selected row")
        }
    }

    /// The sidebar footer's player and Deselect buttons say what they act on.
    @Test func macTreeSidebarFooterNamesItsActions() async throws {
        let (host, window, _) = hostMacRootTree(try await macTreeSession(player: true), initial: .songs)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Fixture Player 1"], timeout: macTreeBudget)
        let nodes = macAccessibilityTree(host)
        #expect(nodes.contains {
            $0.identifier == "fst.profile.sidebar.name" && $0.spokenName == "Profile: Fixture Player 1. Show Statistics"
        })
        #expect(nodes.contains { $0.identifier == "fst.profile.sidebar.deselect" && $0.spokenName == "Deselect Profile" })
    }

    // MARK: - Toolbar

    /// Toolbar items bridged into a titled window (`sceneBridgingOptions`) carry labels and
    /// tooltips; the Songs filter field is identified as filtering, the global search is not
    /// a second item named "Search" (HIG Search fields: inline field "filters one view rather
    /// than searches globally"; HIG Toolbars: label every item).
    @Test func macTreeToolbarItemsAreLabelled() async throws {
        for player in [false, true] {
            let size = MacWindowMetrics.defaultSize
            let model = MacAppModel(session: try await macTreeSession(player: player), storage: nil, initial: .songs)
            let controller = NSHostingController(rootView: MacRootView(model: model)
                .frame(width: size.width, height: size.height))
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.setFrame(NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), display: false)
            window.orderOut(nil)
            defer { window.close() }
            var budget = NativeHostedPollBudget(.seconds(20))
            while (window.toolbar?.items.count ?? 0) < (player ? 6 : 5), !budget.isExhausted {
                try await budget.sleep(for: .milliseconds(100))
            }
            let items = try #require(window.toolbar?.items)
            let labels = items.map(\.label)
            if let dir = ProcessInfo.processInfo.environment["FST_MAC_AX_OUT"] {
                let text = items.map { "\($0.label) | \($0.toolTip ?? "") | \($0.itemIdentifier.rawValue)" }
                try? text.joined(separator: "\n").write(
                    toFile: dir + "/toolbar-\(player ? "player" : "anonymous").txt", atomically: true, encoding: .utf8
                )
            }
            #expect(labels.allSatisfy { !$0.isEmpty }, "every toolbar item has a label: \(labels)")
            #expect(Set(labels).count == labels.count, "no two toolbar items share a label: \(labels)")
            for expected in ["Sort", "Filter", "Search Festival"] {
                #expect(labels.contains(expected), "\(expected) in \(labels)")
            }
            #expect(labels.contains(player ? "Profile: Fixture Player 1" : "Choose Profile"), "profile item in \(labels)")
            if player { #expect(labels.contains("Notifications"), "bell in \(labels)") }
            let filter = items.compactMap { $0 as? NSSearchToolbarItem }.first
            #expect(filter?.searchField.placeholderString == "Filter Songs")
            for item in items where !(item is NSSearchToolbarItem) {
                #expect(!(item.toolTip ?? "").isEmpty, "\(item.label) has a tooltip")
            }
        }
    }

    /// With a split open, the window toolbar carries the trailing pane's Close button and
    /// the leading page's Back, named and tooltipped with their shortcuts, and no two
    /// items share a label.
    @Test func macTreeSplitToolbarNamesClose() async throws {
        let size = MacWindowMetrics.defaultSize
        let model = MacAppModel(session: try await macTreeSession(player: true), storage: nil, initial: .rivals)
        // All Rivals (pushed, so it has Back) beside a rival (a profile covers the list
        // since #352, so a board › player path no longer splits).
        model.navigation.paths[.rivals] = [
            .allRivals(scope: .song(instruments: ["Solo_Guitar"])),
            .rivalDetail(rivalId: "f1c749eb07c32578cfa3e59ec38c03a8", name: "uwphe", scope: nil),
        ]
        let controller = NSHostingController(rootView: MacRootView(model: model).frame(width: size.width, height: size.height))
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), display: false)
        window.orderOut(nil)
        defer { window.close() }
        var budget = NativeHostedPollBudget(.seconds(20))
        while !(window.toolbar?.items.contains { $0.label == "Close" } ?? false), !budget.isExhausted {
            try await budget.sleep(for: .milliseconds(100))
        }
        let items = try #require(window.toolbar?.items)
        let labels = items.map(\.label)
        let close = try #require(items.first { $0.label == "Close" }, "Close in \(labels)")
        #expect(close.toolTip == "Close (Esc)")
        // The leading page's Back closes the open item first (issue #347; the rule is
        // `OnDemandSplitPolicy.pathAfterListBack`).
        let back = try #require(items.first { $0.label == "Back" }, "Back in \(labels)")
        #expect(back.toolTip == "Back (⌘[)")
        #expect(Set(labels).count == labels.count, "no two toolbar items share a label: \(labels)")
    }

    /// A profile covering the list page (issue #352) has one Back and no Close in the
    /// window toolbar, and the hidden overview's own tools (Rank By) stay out of it.
    @Test func macTreeCoveringProfileToolbarHasOnlyBack() async throws {
        let size = MacWindowMetrics.defaultSize
        let model = MacAppModel(session: try await macTreeSession(player: true), storage: nil, initial: .leaderboards)
        model.navigation.paths[.leaderboards] = [.player(accountId: "fixture-player-2", displayName: "Fixture Player 2")]
        let controller = NSHostingController(rootView: MacRootView(model: model).frame(width: size.width, height: size.height))
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), display: false)
        window.orderOut(nil)
        defer { window.close() }
        var budget = NativeHostedPollBudget(.seconds(20))
        while !(window.toolbar?.items.contains { $0.label == "Back" } ?? false), !budget.isExhausted {
            try await budget.sleep(for: .milliseconds(100))
        }
        // Let the hidden overview finish loading, so a leaked tool would have arrived.
        try await budget.sleep(for: .seconds(1))
        let items = try #require(window.toolbar?.items)
        let labels = items.map(\.label)
        #expect(labels.filter { $0 == "Back" }.count == 1, "one Back: \(labels)")
        #expect(!labels.contains("Close"), "a profile is a full page, not a pane item: \(labels)")
        let metrics = Set(RankingMetric.allCases.map(\.label) + ["Rank By"])
        #expect(!labels.contains { metrics.contains($0) }, "no hidden Rank By: \(labels)")
    }

    /// Score history in the trailing pane (issue #324): its Sort page action reaches the
    /// window toolbar beside Close, named and tooltipped, and no two items share a label.
    @Test func macTreeScoreHistoryToolbarOffersSort() async throws {
        let size = MacWindowMetrics.defaultSize
        let session = try await macTreeSession(player: true)
        let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
        let model = MacAppModel(session: session, storage: nil, initial: .songs)
        model.navigation.paths[.songs] = [.songDetail(song), .playerHistory(song, .lead)]
        let controller = NSHostingController(rootView: MacRootView(model: model).frame(width: size.width, height: size.height))
        controller.sceneBridgingOptions = [.toolbars, .title]
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setFrame(NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), display: false)
        window.orderOut(nil)
        defer { window.close() }
        var budget = NativeHostedPollBudget(.seconds(20))
        while !(window.toolbar?.items.contains { $0.label == "Sort" } ?? false), !budget.isExhausted {
            try await budget.sleep(for: .milliseconds(100))
        }
        let items = try #require(window.toolbar?.items)
        let labels = items.map(\.label)
        let sort = try #require(items.first { $0.label == "Sort" }, "Sort in \(labels)")
        #expect(sort.toolTip == "Sort Scores")
        #expect(labels.contains("Close"), "Close in \(labels)")
        #expect(Set(labels).count == labels.count, "no two toolbar items share a label: \(labels)")
    }

    // MARK: - Pages

    /// Every Mac destination (fixture data): no unnamed control or image, no decorative
    /// image that repeats the next element's name, and content pages expose headings for the
    /// VoiceOver rotor (HIG VoiceOver: "Use titles and headings to convey hierarchy";
    /// "Exclude purely decorative images").
    @Test(arguments: [
        (MacDestination.songs, "Fixture Pulse"), (.leaderboards, "Lead"), (.statistics, "Fixture Player 1"),
        (.suggestions, "Suggestions"), (.rivals, "Rivals"), (.compete, "Compete"), (.shop, "Item Shop"),
    ])
    func macTreePagesNameEveryElement(destination: MacDestination, readyText: String) async throws {
        let (host, window, _) = hostMacRootTree(try await macTreeSession(player: true), initial: destination)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: [readyText], excluding: ["Loading"], timeout: macTreeBudget)
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "page-\(destination.rawValue)")
        #expect(macAccessibilityFindings(nodes) == [], "\(destination.title)")
        // The fixture catalogue fits one Songs section, so its list shows no section
        // heading; Songs no longer shows Song Detail beside it (operator 2026-10-04).
        if destination != .shop && destination != .songs {
            #expect(nodes.contains { $0.role == "AXHeading" && !$0.spokenName.isEmpty }, "\(destination.title) has headings")
        }
    }

    /// Song Detail beside its full leaderboard: the song page (leading half) reads before
    /// the trailing pane, and the song title is a heading.
    @Test func macTreeSongDetailSplitOrder() async throws {
        let session = try await macTreeSession(player: false)
        let song = try #require(try await session.catalog().catalog.songs.first)
        let (host, window, model) = hostMacRootTree(session, initial: .songs)
        defer { window.orderOut(nil) }
        model.navigation.paths[.songs] = [.songDetail(song), .songLeaderboard(song, .lead, 1)]
        let image = try await nativeHostedSettle(host, timeout: macTreeBudget, until: {
            let ids = nativeHostedAccessibility(host).identifiers
            return ids.contains("fst.song-detail.intensity") && ids.contains("fst.split.trailing")
        })
        _ = try nativeHostedPNG(image, filename: "mac-song-detail-split.png", environment: "FST_SHELL_RENDER_OUT")
        let nodes = macAccessibilityTree(host).filter(\.isElement)
        macAccessibilityDump(nodes, name: "song-detail-split")
        let detail = try #require(nodes.firstIndex { $0.identifier == "fst.song-detail.intensity" })
        let sidebar = try #require(nodes.firstIndex { $0.identifier == "fst.nav.songs" })
        #expect(sidebar < detail, "sidebar before the song page")
        let title = try #require(nodes.first { $0.identifier == "fst.song-detail.hero-title" })
        #expect(title.role == "AXHeading", "the song title is a heading: \(title)")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// Each list page beside its open item in the fixed-divider Mac split (Lane SPLIT,
    /// 2026-10-05): the sidebar reads first, the list before the trailing pane, the opened
    /// row is the one selected element (HIG Split views: "Persistently highlight the current
    /// selection"), the divider stays out of the tree, and nothing is unnamed. (Close
    /// sits in the window toolbar: `macTreeToolbarItemsAreLabelled`.)
    @Test(arguments: [
        // View All Rankings opens Full Rankings beside the overview (issue #352).
        ("full-rankings", MacDestination.leaderboards,
         [AppRoute.fullRankings(instrument: .lead, rankBy: "totalscore")], "fst.leaderboards.card.Solo_Guitar.view-all"),
        ("rivals", .rivals,
         [.rivalDetail(rivalId: "f1c749eb07c32578cfa3e59ec38c03a8", name: "uwphe", scope: nil)], "fst.rivals.row."),
    ])
    func macTreeSplitPagesReadLeadingThenTrailing(
        name: String, destination: MacDestination, path: [AppRoute], rowPrefix: String
    ) async throws {
        let (host, window, model) = hostMacRootTree(try await macTreeSession(player: true), initial: destination)
        defer { window.orderOut(nil) }
        model.navigation.paths[destination] = path
        _ = try await nativeHostedSettle(host, timeout: macTreeBudget, until: {
            let ids = nativeHostedAccessibility(host).identifiers
            return ids.contains("fst.split.trailing") && ids.contains { $0.hasPrefix(rowPrefix) }
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "split-\(name)")
        let elements = nodes.filter(\.isElement)
        let sidebar = try #require(elements.firstIndex { $0.identifier == "fst.nav.\(destination.rawValue)" })
        let row = try #require(elements.firstIndex { $0.identifier.hasPrefix(rowPrefix) })
        let trailing = try #require(nodes.firstIndex { $0.identifier == "fst.split.trailing" })
        let firstRowInTree = try #require(nodes.firstIndex { $0.identifier.hasPrefix(rowPrefix) })
        #expect(sidebar < row, "\(name): sidebar before the list")
        #expect(firstRowInTree < trailing, "\(name): the list reads before the trailing pane")
        #expect(!elements.contains { $0.identifier == "fst.split.divider" }, "\(name): the divider is decorative")
        if case .fullRankings = path.last {
            let selected = elements.filter { $0.identifier == rowPrefix && $0.selected }
            #expect(!selected.isEmpty, "\(name): View All Rankings reads selected while its board is open")
        }
        if case .player(let accountId, _) = path.last {
            // Leaderboards lists the same player on every instrument card: each of those
            // rows opens the same item, so each reads selected; no other row does.
            let selected = elements.filter { $0.identifier.hasPrefix(rowPrefix) && $0.selected }
            #expect(!selected.isEmpty && selected.allSatisfy { $0.identifier == "\(rowPrefix)\(accountId)" },
                    "\(name): only the opened item's rows are selected: \(selected)")
        }
        #expect(macAccessibilityFindings(elements) == [], "\(name)")
    }

    /// Profiles are full pages (issue #352): opened from Leaderboards, or pushed inside
    /// Full Rankings in the trailing pane, the profile covers the list page, which leaves
    /// the tree while hidden; the profile's Back (not Close) leads back to it.
    @Test(arguments: [
        ("leaderboards-player", [AppRoute.player(accountId: "fixture-player-2", displayName: "Fixture Player 2")]),
        ("full-rankings-player", [AppRoute.fullRankings(instrument: .lead, rankBy: "totalscore"),
                                  .player(accountId: "fixture-player-2", displayName: "Fixture Player 2")]),
    ])
    func macTreeProfileCoversTheListPage(name: String, path: [AppRoute]) async throws {
        let (host, window, model) = hostMacRootTree(try await macTreeSession(player: true), initial: .leaderboards)
        defer { window.orderOut(nil) }
        model.navigation.paths[.leaderboards] = path
        let states = ["fst.player.loading", "fst.player.syncing", "fst.player.error", "fst.player.available"]
        _ = try await nativeHostedSettle(host, timeout: macTreeBudget, until: {
            let ids = nativeHostedAccessibility(host).identifiers
            return ids.contains("fst.split.trailing") && ids.contains { states.contains($0) }
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "covered-\(name)")
        let ids = nodes.filter(\.isElement).map(\.identifier)
        #expect(!ids.contains { $0.hasPrefix("fst.leaderboards.card") }, "\(name): the covered overview is hidden")
        #expect(!ids.contains { $0.hasPrefix("fst.rankings.row.") }, "\(name): no hidden ranking rows read")
        #expect(!ids.contains("fst.split.close"), "\(name): a profile has Back, not Close")
        #expect(model.navigation.paths[.leaderboards] == path, "\(name): nothing rewrote the path")
    }

    /// Song Detail beside its score history: the sortable history page (issue #324)
    /// carries the registered `fst.history` page root (as on Android/Windows, issue #302)
    /// and its rows.
    @Test func macTreeScoreHistoryPageKeepsChildIdentifiers() async throws {
        let session = try await macTreeSession(player: true)
        let songs = try await session.catalog().catalog.songs
        let song = try #require(songs.first { $0.songId == "fixture-pulse" })
        let (host, window, model) = hostMacRootTree(session, initial: .songs)
        defer { window.orderOut(nil) }
        model.navigation.paths[.songs] = [.songDetail(song), .playerHistory(song, .lead)]
        _ = try await nativeHostedSettle(host, timeout: macTreeBudget, until: {
            let ids = nativeHostedAccessibility(host).identifiers
            return ids.contains("fst.split.trailing") && ids.contains("fst.history.row.0")
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "song-detail-score-history-split")
        let ids = Set(nodes.map(\.identifier))
        #expect(ids.contains("fst.history"), "the history page root is identified")
        #expect(ids.contains("fst.history.row.0"), "the history rows keep their identifiers")
        #expect(macAccessibilityFindings(nodes.filter(\.isElement)) == [])
        #expect(!ids.contains("fst.score-history.page"), "the unregistered identifier is gone")
    }
}
#endif
