#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Notifications pinned titles, accessibility (issue #459, for #301)

/// VoiceOver over the Notifications sheet's pinned "New" / "Older" titles and the rows
/// that fade out under them (issue #301, pattern `scroll-edge` R5 and R7): at rest, while
/// scrolled under each pinned title, during the push and with the hard edge (in-app Less
/// Transparency). The titles are headings read before the rows beneath them; rows are
/// named, enabled buttons with their identifiers and at least 44 pt tall; a row partly
/// under a title stays one; a row wholly in the cut is no VoiceOver stop.
///
/// The fixture lists 8 unread ("New") and 24 seen ("Older") 93 pt rows (85 pt buttons
/// inside 4 pt insets) under a 28 pt title band, in a 420 × 640 pt sheet; offsets below
/// are measured from the List's top in those units.
@MainActor
struct NotificationsPinnedHeaderAccessibilityTests {
    /// A hosted Notifications sheet and its List.
    @MainActor
    struct Hosted {
        let host: NSView
        let window: NSWindow
        let scroll: NSScrollView
        let table: NSTableView
        let accountId: String
        let suite: String
        /// Settles the hosting view until the given texts are drawn.
        let settle: @MainActor ([String]) async throws -> Void

        /// Scroll the List so `offset` points of content lie above its top, then settle
        /// until `title` is drawn.
        func scroll(to offset: CGFloat, showing title: String) async throws {
            let clip = scroll.contentView
            clip.scroll(to: NSPoint(x: 0, y: offset - scroll.contentInsets.top))
            scroll.reflectScrolledClipView(clip)
            try await settle([title])
        }

        /// The List's frame in screen coordinates (y up), as accessibility frames are.
        var listScreenFrame: CGRect {
            window.convertToScreen(scroll.convert(scroll.bounds, to: nil))
        }

        func close() {
            window.orderOut(nil)
            forgetScrollingAccount(accountId)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    /// The fixture's notifications by section.
    static let newCount = 8
    static let olderCount = 24
    /// HIG Accessibility: a 44 × 44 pt minimum target (iOS); Mac rows share the layout.
    static let minimumTarget: CGFloat = 44
    /// Identifier prefix of the rows.
    static let rowPrefix = "fst.notifications.row."

    /// Host the sheet over the scrolling fixture.
    ///
    /// - Parameter lessTransparency: Turn the in-app Less Transparency on (scroll-edge R7:
    ///   the fade becomes a hard edge).
    /// - Returns: The hosted sheet.
    func host(lessTransparency: Bool = false) async throws -> Hosted {
        let (session, accountId) = await scrollingNotificationsSession(
            newCount: Self.newCount, olderCount: Self.olderCount
        )
        let suite = "fst.tests.notifications-a11y.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.set(lessTransparency, forKey: "fst.accessibility.lessTransparency")
        let size = CGSize(width: 420, height: 640)
        let host = nativeHostedView(
            NotificationsSheet(session: session)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .background(BrandTokens.appBackground)
                .defaultAppStorage(defaults),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        _ = try await nativeHostedSettle(host, untilText: ["New"])
        let scroll = try #require(listScrollView(in: host))
        let table = try #require(scroll.documentView as? NSTableView)
        return Hosted(
            host: host, window: window, scroll: scroll, table: table, accountId: accountId, suite: suite,
            settle: { _ = try await nativeHostedSettle(host, untilText: $0) }
        )
    }

    // MARK: - Reading order

    /// The sheet's on-screen elements in VoiceOver's reading order, as the Songs section
    /// bar tests read it (`SongsSectionBarAccessibilityTests.readingOrder`): what sits
    /// outside the List's rows in tree order (a pinned title floats above the table),
    /// then the rows on screen by row index (an outline reads its rows in index order;
    /// AppKit reorders recycled row views). Off-screen elements and duplicates (the
    /// floating title is also its own row view at rest) are dropped.
    func readingOrder(_ hosted: Hosted) -> [MacAXNode] {
        let list = hosted.listScreenFrame
        func onScreen(_ node: MacAXNode) -> Bool {
            node.isElement && node.frame.width > 0 && node.frame.height > 0 && node.frame.intersects(list)
        }
        let tree = macAccessibilityTree(hosted.host, navigationOrder: true)
        var outside: [MacAXNode] = []
        var outlineDepth: Int?
        for node in tree {
            if let depth = outlineDepth, node.depth > depth { continue }
            outlineDepth = nil
            if node.role == "AXOutline" {
                outlineDepth = node.depth
                continue
            }
            if onScreen(node), node.role != "AXScrollBar", node.role != "AXValueIndicator",
               node.subrole.isEmpty || !node.subrole.hasSuffix("Arrow") && !node.subrole.hasSuffix("Page") {
                outside.append(node)
            }
        }
        let visible = hosted.table.rows(in: hosted.table.visibleRect)
        let rows = (visible.lowerBound..<visible.upperBound).flatMap { index in
            hosted.table.rowView(atRow: index, makeIfNecessary: false).map {
                macAccessibilityTree($0, navigationOrder: true).filter(onScreen)
            } ?? []
        }
        var seen: Set<String> = []
        return (outside + rows).filter { node in
            seen.insert("\(node.role)|\(node.spokenName)|\(node.identifier)|\(node.frame)").inserted
        }
    }

    /// The row's index in the fixture (`<account>-<index>`), or nil for anything else.
    static func rowIndex(_ node: MacAXNode) -> Int? {
        guard node.identifier.hasPrefix(rowPrefix) else { return nil }
        return node.identifier.split(separator: "-").last.flatMap { Int($0) }
    }

    /// The title a row is read under.
    static func section(ofRow index: Int) -> String { index < newCount ? "New" : "Older" }

    /// The rows' and titles' rules for one state.
    ///
    /// - Titles are headings named "New" / "Older"; the pinned one is read first.
    /// - Every row is read after its own section's title, in fixture order, and is a
    ///   named, enabled button with its identifier, at least 44 pt tall.
    /// - R7: no element is a row wholly hidden under the pinned title band (its bottom
    ///   at or above the band's bottom edge); a row with any part below the edge stays.
    ///
    /// - Parameters:
    ///   - order: The reading order.
    ///   - hosted: The sheet.
    ///   - pinned: The title expected first.
    ///   - state: Names the state in failures.
    /// - Returns: The rows read, by fixture index.
    @discardableResult
    func expectRules(_ order: [MacAXNode], in hosted: Hosted, pinned: String, state: String) -> [Int] {
        #expect(macAccessibilityFindings(order).isEmpty, "\(state): \(macAccessibilityFindings(order))")
        let headings = order.filter { $0.role == "AXHeading" }
        #expect(headings.first?.spokenName == pinned, "\(state): \(order)")
        #expect(order.first { $0.role == "AXHeading" || Self.rowIndex($0) != nil }?.role == "AXHeading",
                "\(state): a row is read before the pinned title: \(order)")
        #expect(Set(headings.map(\.spokenName)).isSubset(of: ["New", "Older"]), "\(state): \(headings)")
        #expect(headings.count == Set(headings.map(\.spokenName)).count, "\(state): a title read twice: \(headings)")

        // The pinned band is the title's whole table row; screen coordinates are y up, so
        // its bottom edge (where the row cut is) lies one header row below the List's top.
        let edge = hosted.listScreenFrame.maxY - hosted.table.rect(ofRow: 0).height
        var current: String?
        var rows: [Int] = []
        for node in order {
            if node.role == "AXHeading" {
                current = node.spokenName
                continue
            }
            guard let index = Self.rowIndex(node) else { continue }
            rows.append(index)
            #expect(current == Self.section(ofRow: index), "\(state): row \(index) is read under \(current ?? "nothing")")
            #expect(node.role == "AXButton" && node.isEnabled, "\(state): \(node)")
            #expect(node.label.contains("Fixture Anthem") && node.label.contains("Rank Up"), "\(state): \(node)")
            #expect(node.frame.height >= Self.minimumTarget, "\(state): row \(index) target \(node.frame)")
            // A row's bottom is its minY.
            #expect(node.frame.minY < edge - 0.5,
                    "\(state): row \(index) is wholly under the pinned title (\(node.frame), edge \(edge)) yet read")
        }
        #expect(rows == rows.sorted(), "\(state): rows out of order \(rows)")
        return rows
    }

    // MARK: - Tests

    /// At rest: "New", its eight rows, then "Older" and its rows, every row a named,
    /// enabled 44 pt button.
    @Test func restingSheetReadsEachTitleThenItsRows() async throws {
        let hosted = try await host()
        defer { hosted.close() }
        let order = readingOrder(hosted)
        macAccessibilityDump(order, name: "notifications-pinned-rest")
        let rows = expectRules(order, in: hosted, pinned: "New", state: "rest")
        #expect(rows.first == 0, "rest: \(order)")
        #expect(rows.count >= 5, "rest: \(order)")
    }

    /// Scrolled under each pinned title, with the fade and with the hard edge (R7): the
    /// pinned title is read first; a row wholly in the cut is no stop, and the row
    /// partly under the title is read next, still a named button.
    @Test(arguments: [false, true])
    func scrolledRowsWhollyUnderAPinnedTitleAreNoStop(lessTransparency: Bool) async throws {
        let hosted = try await host(lessTransparency: lessTransparency)
        defer { hosted.close() }
        // Row n's button spans 32 + 93n … 117 + 93n; the pinned band covers offset … offset + 28.
        // 100: "New" row 0 (… 117) lies wholly in the band, row 1 (125 …) partly under it.
        // 870: "Older" row 8 (804 … 889) lies wholly in the band, row 9 (897 …) partly.
        for (offset, pinned, hidden, partial) in [(100.0, "New", 0, 1), (870.0, "Older", 8, 9)] {
            let state = "\(pinned) pinned at \(offset)\(lessTransparency ? ", Less Transparency" : "")"
            try await hosted.scroll(to: offset, showing: pinned)
            let order = readingOrder(hosted)
            macAccessibilityDump(order, name: "notifications-pinned-\(pinned.lowercased())-\(lessTransparency)")
            let rows = expectRules(order, in: hosted, pinned: pinned, state: state)
            #expect(!rows.contains(hidden), "\(state): row \(hidden) is read: \(order)")
            #expect(rows.first == partial, "\(state): \(rows)")
        }
    }

    /// While "Older" pushes "New" out, "New" is still read first, its last rows (wholly
    /// under the band excepted) follow it, then "Older" and its rows.
    @Test func pushReadsTheOutgoingTitleThenTheIncomingOne() async throws {
        let hosted = try await host()
        defer { hosted.close() }
        // "Older" is laid out at 772 … 800: at 760 it pushes "New" 12 pt up.
        try await hosted.scroll(to: 760, showing: "Older")
        let order = readingOrder(hosted)
        macAccessibilityDump(order, name: "notifications-pinned-push")
        let rows = expectRules(order, in: hosted, pinned: "New", state: "push")
        #expect(order.filter { $0.role == "AXHeading" }.map(\.spokenName) == ["New", "Older"], "push: \(order)")
        #expect(rows.contains(Self.newCount), "push: the first Older row is not read: \(rows)")
    }
}
#endif
