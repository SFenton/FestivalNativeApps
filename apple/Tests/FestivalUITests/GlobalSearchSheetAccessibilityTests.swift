#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Search sheet title (issue #100, backfilled by #450)

/// The Mac's global search is a window sheet (`GlobalSearchSheet`, `FestivalModal("Search")`)
/// rather than the iOS Search tab whose title #100 restored, so its counterpart evidence is
/// here: presented with `.sheet` as `MacRootView` presents it (in SwiftUI's own sheet
/// window), the sheet must
/// - read its "Search" title first, then its named field, the scope bar's four scopes, the
///   hint and Close, top to bottom, with Close a full target;
/// - give keyboard focus to its field on open (⌘K / ⌘F then typing);
/// - name every control (no `macAccessibilityFindings`).
///
/// The iOS forms (Search tab, iPhone Duo, iPad sidebar page) are covered at AX5 by the
/// `GlobalSearchAccessibilityJourneyTests` journey; macOS has no Dynamic Type.
///
/// HIG VoiceOver: "Give each page or screen a unique, succinct title describing its content
/// and purpose; assistive technology announces it first"; HIG Accessibility: macOS controls
/// default to 28×28 pt, minimum 20×20 pt.
@MainActor
@Suite(.serialized)
struct GlobalSearchSheetAccessibilityTests {
    /// Fails every request: an empty query never reads the service.
    private struct OfflineTransport: HTTPTransport {
        func send(_ request: URLRequest) async throws -> HTTPResult {
            throw URLError(.notConnectedToInternet)
        }
    }

    /// The sheet's default size (`WideColumns.macSheetSize`, one column).
    private static let size = CGSize(width: 620, height: 680)

    /// The All scope's hint (`GlobalSearch.enterQueryHint`).
    private static let hint = "Enter at least two characters to search for songs, players, or bands."

    /// The presented sheet: its own window (SwiftUI's sheet presentation window, which
    /// attaches to the parent only when that is on screen) and the parent's window.
    struct Presented {
        let sheet: NSWindow
        let parent: NSWindow

        func close() {
            sheet.orderOut(nil)
            parent.orderOut(nil)
        }
    }

    /// Present the sheet from a hosted window as `MacRootView` does (`.sheet`,
    /// `macSheetFrame`, `festivalSheet`) and wait for its field and hint.
    private static func presentSheet() async throws -> Presented {
        let earlier = Set(NSApplication.shared.windows.map(ObjectIdentifier.init))
        let client = try FestivalAPI(transport: OfflineTransport())
        let session = FestivalSession(factory: { client })
        let parentSize = CGSize(width: 1000, height: 800)
        let host = nativeHostedView(
            Color.clear
                .frame(width: parentSize.width, height: parentSize.height)
                .sheet(isPresented: .constant(true)) {
                    GlobalSearchSheet(session: session) { _ in }
                        .macSheetFrame(width: size.width, height: size.height, minWidth: 560, minHeight: 520)
                        .festivalSheet()
                },
            size: parentSize
        )
        let parent = nativeHostedWindow(host, size: parentSize)
        var sheet: NSWindow?
        var budget = NativeHostedPollBudget(.seconds(20))
        while !budget.isExhausted {
            host.layoutSubtreeIfNeeded()
            sheet = parent.attachedSheet ?? NSApplication.shared.windows.first { candidate in
                candidate !== parent && !earlier.contains(ObjectIdentifier(candidate))
                    && candidate.contentView.map { nativeHostedAccessibility($0).contains(hint) } == true
            }
            if sheet != nil { break }
            try await budget.sleep(for: .milliseconds(100))
        }
        let presented = try #require(sheet, "the Search sheet opened")
        return Presented(sheet: presented, parent: parent)
    }

    // MARK: - Title, Close and reading order

    /// Containers and the scroll bar, which a screen reader passes through.
    private static let structural: Set<String> = ["AXGroup", "AXScrollArea", "AXScrollBar"]

    /// The sheet reads its "Search" title first, then the named field, the four scopes (All
    /// selected), the hint and Close last; every control is named.
    @Test func sheetReadsSearchTitleFirstThenFieldScopesHintAndClose() async throws {
        let presented = try await Self.presentSheet()
        defer { presented.close() }
        let window = presented.sheet
        let root = try #require(window.contentView?.superview ?? window.contentView)
        let nodes = macAccessibilityTree(root, navigationOrder: true)
        macAccessibilityDump(nodes, name: "global-search-sheet")
        let order = nodes.filter { $0.isElement && !Self.structural.contains($0.role) && !$0.spokenName.isEmpty }
        let read = order.map { "\($0.role) '\($0.spokenName)'" }
        let expected: [(role: String, name: String, identifier: String)] = [
            ("AXStaticText", "Search", ""),
            ("AXTextField", "Search songs, players and bands", "fst.global-search.field"),
            ("AXRadioGroup", "Search Scope", "fst.global-search.scope"),
            ("AXRadioButton", "All", ""), ("AXRadioButton", "Songs", ""),
            ("AXRadioButton", "Players", ""), ("AXRadioButton", "Bands", ""),
            ("AXStaticText", Self.hint, "fst.global-search.hint"),
            ("AXButton", "Close", "fst.global-search.close"),
        ]
        #expect(order.count == expected.count, "only the title, field, scopes, hint and Close are read: \(read)")
        for (index, item) in expected.enumerated() where index < order.count {
            let node = order[index]
            #expect(node.role == item.role && node.spokenName == item.name, "#\(index) reads \(item.role) '\(item.name)': \(read)")
            if !item.identifier.isEmpty { #expect(node.identifier == item.identifier, "#\(index): \(node)") }
        }
        let scopes = order.filter { $0.role == "AXRadioButton" }
        #expect(scopes.map(\.value) == ["1", "0", "0", "0"], "All is the selected scope: \(scopes)")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// Title, field, scope bar, hint and Close sit top to bottom, so the spoken order is the
    /// visual order, and Close meets the Mac's minimum target (HIG Accessibility: macOS
    /// default 28×28 pt, minimum 20×20 pt).
    @Test func readingOrderMatchesTheVisualOrderAndCloseIsATarget() async throws {
        let presented = try await Self.presentSheet()
        defer { presented.close() }
        let window = presented.sheet
        let host = try #require(window.contentView?.superview ?? window.contentView)
        let titleElement = try #require(nativeHostedAccessibilityElement(in: host) { object in
            nativeHostedAccessibilityString(object, "accessibilityRole") == "AXStaticText"
                && ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].contains {
                    nativeHostedAccessibilityString(object, $0) == "Search"
                }
        }, "the Search title")
        let title = try #require(nativeHostedAccessibilityFrame(of: titleElement, in: host), "title frame")
        var frames = [("title", title)]
        for name in ["field", "scope", "hint", "close"] {
            let frame = try #require(nativeHostedAccessibilityFrame("fst.global-search.\(name)", in: host), "\(name) frame")
            frames.append((name, frame))
        }
        for index in frames.indices.dropFirst() {
            let (name, frame) = frames[index], (above, previous) = frames[index - 1]
            #expect(frame.minY >= previous.maxY - 0.5, "\(name) is below \(above): \(frames)")
        }
        let close = frames[frames.count - 1].1
        #expect(close.width >= 20 && close.height >= 20, "Close is at least 20×20 pt: \(close)")
        #expect(!title.isEmpty && title.width >= 30, "the title is drawn whole: \(title)")
    }

    // MARK: - Keyboard

    /// Opening the sheet puts keyboard focus in its field, so ⌘K / ⌘F then typing searches.
    @Test func fieldHasKeyboardFocusOnOpen() async throws {
        let presented = try await Self.presentSheet()
        defer { presented.close() }
        let window = presented.sheet
        window.makeKey()
        var budget = NativeHostedPollBudget(.seconds(10))
        while !(window.firstResponder is NSTextView), !budget.isExhausted {
            try await budget.sleep(for: .milliseconds(100))
        }
        let editor = try #require(window.firstResponder as? NSTextView,
                                  "first responder: \(String(describing: window.firstResponder))")
        #expect(editor.isFieldEditor, "the field's editor has focus")
    }
}
#endif
