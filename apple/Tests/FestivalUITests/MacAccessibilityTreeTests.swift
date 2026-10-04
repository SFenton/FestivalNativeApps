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
            + " '\(spokenName)'" + (identifier.isEmpty ? "" : " #\(identifier)") + (selected ? " [selected]" : "")
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
            .environment(\.macListCollapseDelay, .seconds(120))
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
                .environment(\.macListCollapseDelay, .seconds(120))
                .frame(width: size.width, height: size.height))
            controller.sceneBridgingOptions = [.toolbars, .title]
            let window = NSWindow(contentViewController: controller)
            window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
            window.setFrame(NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), display: false)
            window.orderOut(nil)
            defer { window.close() }
            let deadline = ContinuousClock.now + nativeHostedReadinessBudget(.seconds(20))
            while (window.toolbar?.items.count ?? 0) < (player ? 6 : 5), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(100))
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
        if destination != .shop {
            #expect(nodes.contains { $0.role == "AXHeading" && !$0.spokenName.isEmpty }, "\(destination.title) has headings")
        }
    }

    /// Songs list | detail: the auto-selected song row reports the selected state and reads
    /// before the detail, whose song title is a heading.
    @Test func macTreeSongsSplitSelectionAndOrder() async throws {
        let (host, window, _) = hostMacRootTree(try await macTreeSession(player: false), initial: .songs)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, timeout: macTreeBudget, until: {
            nativeHostedAccessibility(host).identifiers.contains("fst.song-detail.intensity")
        })
        let nodes = macAccessibilityTree(host).filter(\.isElement)
        macAccessibilityDump(nodes, name: "songs-split")
        let rows = nodes.enumerated().filter { $0.element.identifier.hasPrefix("fst.songs.row.") }
        #expect(rows.filter(\.element.selected).count == 1, "one selected song row: \(rows.map(\.element))")
        let detail = try #require(nodes.firstIndex { $0.identifier == "fst.song-detail.intensity" })
        let sidebar = try #require(nodes.firstIndex { $0.identifier == "fst.nav.songs" })
        #expect(sidebar < (rows.first?.offset ?? .max), "sidebar before list")
        #expect((rows.last?.offset ?? .max) < detail, "list before detail")
        #expect(nodes[detail...].contains { $0.role == "AXHeading" }, "detail headings")
    }
}
#endif
