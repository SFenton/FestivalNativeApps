#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Songs section bar accessibility (issues #8, #390)

/// What assistive technologies get from the Songs floating section bar and the in-list
/// section titles in each scroll state (section-headers R1, R4, R6).
///
/// Issue #8 moved the scroll-driven state these views show into ``SongsScrollChrome``,
/// which they observe themselves. These tests drive that state directly and walk the
/// hosted AppKit accessibility tree (``macAccessibilityTree(_:)``), so they pin what
/// VoiceOver reads for the same SwiftUI views iPhone, iPad, iPhone Duo and macOS 26 draw:
/// - at the top the bar exposes nothing, and its tap-blocking area is not an element;
/// - scrolled, it exposes one heading named with the section's spoken label and no
///   control;
/// - while one title pushes another out, the outgoing and incoming visual copies stay
///   hidden, so it is still one heading;
/// - an in-list title blanked under the bar keeps its heading and spoken label;
/// - a long section name wraps instead of truncating, and the bar's measured height (the
///   row fade's edge) follows it.
@MainActor
struct SongsSectionBarAccessibilityTests {
    /// Star-sort sections: their visible labels ("5★") differ from what VoiceOver says.
    private let sections = [
        SongsSectionBar.Entry(key: "4", label: "4★", spokenLabel: "4 stars"),
        SongsSectionBar.Entry(key: "5", label: "5★", spokenLabel: "5 stars"),
        SongsSectionBar.Entry(key: "6", label: "6★", spokenLabel: "Gold stars"),
    ]

    /// Host a view at the top of a fixed-size, never-shown window and let it settle.
    ///
    /// - Parameters:
    ///   - content: The view under test.
    ///   - width: Window width in points.
    /// - Returns: The host, its window (retain it while reading the tree) and a settle
    ///   step for later state changes.
    private func host(
        _ content: some View, width: CGFloat = 390
    ) async throws -> (NSView, NSWindow, @MainActor () async throws -> Void) {
        let size = CGSize(width: width, height: 240)
        let host = nativeHostedView(
            content.frame(width: width, height: size.height, alignment: .top), size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let settle: @MainActor () async throws -> Void = {
            _ = try await nativeHostedSettle(host, timeout: .seconds(10))
        }
        try await settle()
        return (host, window, settle)
    }

    /// Accessibility elements (what VoiceOver stops on) in tree order, without the
    /// hosting view's own root group.
    private func elements(_ view: NSView) -> [MacAXNode] {
        exposed(macAccessibilityTree(view))
    }

    /// The elements among `nodes`, without the hosting view's own root group.
    private func exposed(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.isElement && $0.subrole != "AXHostingView" }
    }

    /// A chrome whose List has scrolled with `passed` sections at the bar.
    private func scrolledChrome(passed: [String]) -> SongsScrollChrome {
        let chrome = SongsScrollChrome()
        chrome.setScrolled(true)
        for key in passed { chrome.setHeader(key, passed: true) }
        return chrome
    }

    // MARK: Scroll states

    /// At the top of the list the bar is empty: no element, and the clear area that keeps
    /// taps off rows under the bar is not an unnamed element either.
    @Test func atTheTopTheBarExposesNothing() async throws {
        let chrome = SongsScrollChrome()
        let (view, window, _) = try await host(SongsSectionBar(chrome: chrome, sections: sections))
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(view)
        macAccessibilityDump(nodes, name: "songs-section-bar-top")
        #expect(exposed(nodes).isEmpty, "\(nodes)")
        #expect(macAccessibilityFindings(nodes).isEmpty)
    }

    /// Scrolled, the bar names the current section once: a heading with the spoken label
    /// (not the "5★" glyphs), its test ID, and nothing to activate.
    @Test func scrolledTheBarIsOneHeadingWithTheSpokenLabel() async throws {
        let chrome = scrolledChrome(passed: ["4", "5"])
        let (view, window, _) = try await host(SongsSectionBar(chrome: chrome, sections: sections))
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(view)
        macAccessibilityDump(nodes, name: "songs-section-bar-scrolled")
        let exposed = exposed(nodes)
        #expect(exposed.count == 1, "\(exposed)")
        let title = try #require(exposed.first)
        #expect(title.role == "AXHeading", "\(title)")
        #expect(title.spokenName == "5 stars")
        #expect(title.identifier == "fst.songs.section-bar")
        #expect(!nodes.contains { $0.role == "AXButton" }, "the bar has no control: \(nodes)")
        #expect(macAccessibilityFindings(nodes).isEmpty)
    }

    /// While the next title pushes the current one out, and the current one is still
    /// pushing the previous one out, the bar draws three copies. Only the current title is
    /// an element; the others are visual copies of titles VoiceOver reads in the list.
    @Test func pushedAndIncomingCopiesStayHidden() async throws {
        let chrome = scrolledChrome(passed: ["4", "5"])
        let barHeight: CGFloat = 26
        chrome.setBarMetrics(top: 0, height: barHeight)
        // "5 stars" is 10 pt below the bar's top (still pushing "4 stars" out) and
        // "Gold stars" 20 pt below it (already pushing "5 stars" up).
        chrome.setTitleTop("5", top: 10)
        chrome.setTitleTop("6", top: 20)
        let layout = SongsScrollChrome.sectionBarLayout(
            currentTop: 10, currentPassed: true, nextTop: 20,
            landingOffset: SongsScrollChrome.landingOffset, barHeight: barHeight
        )
        let previous = SongsScrollChrome.previousTitleY(
            currentTop: 10, landingOffset: SongsScrollChrome.landingOffset, barHeight: barHeight
        )
        #expect(layout.currentY != nil && layout.nextY != nil && previous != nil,
                "the state draws all three copies")
        let (view, window, _) = try await host(SongsSectionBar(chrome: chrome, sections: sections))
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(view)
        macAccessibilityDump(nodes, name: "songs-section-bar-push")
        let exposed = exposed(nodes)
        #expect(exposed.map(\.spokenName) == ["5 stars"], "\(nodes)")
        #expect(exposed.first?.role == "AXHeading")
        #expect(!nodes.contains { ["4★", "4 stars", "6★", "Gold stars"].contains($0.spokenName) },
                "a moving copy reached assistive technologies: \(nodes)")
    }

    /// Back at the top after scrolling, the bar's title leaves the tree with it.
    @Test func returningToTheTopRemovesTheHeading() async throws {
        let chrome = scrolledChrome(passed: ["4"])
        let (view, window, settle) = try await host(SongsSectionBar(chrome: chrome, sections: sections))
        defer { window.orderOut(nil) }
        #expect(elements(view).map(\.spokenName) == ["4 stars"])
        chrome.setScrolled(false)
        try await settle()
        #expect(elements(view).isEmpty, "\(macAccessibilityTree(view))")
    }

    // MARK: In-list titles

    /// A title that has reached the bar is blanked (the bar draws it), but it keeps its
    /// row, its heading and its spoken label: VoiceOver and the headings rotor still find
    /// every section in the list.
    @Test func blankedInListTitleKeepsItsHeading() async throws {
        let chrome = SongsScrollChrome()
        chrome.setScrolled(true)
        let title = SongsInlineSectionTitle(
            key: "6", label: "6★", spokenLabel: "Gold stars",
            accessibilityID: "fst.songs.section.2", chrome: chrome
        )
        let (view, window, _) = try await host(title)
        defer { window.orderOut(nil) }
        // Hosted at the window's top, the title sits on the landing line: passed.
        #expect(chrome.passedHeaders.contains("6"), "the title did not reach the bar")
        let exposed = elements(view)
        #expect(exposed.count == 1, "\(exposed)")
        let heading = try #require(exposed.first)
        #expect(heading.role == "AXHeading")
        #expect(heading.spokenName == "Gold stars")
        #expect(heading.identifier == "fst.songs.section.2")
    }

    // MARK: Composed bar and list

    /// The Songs list as `SongsScreen` composes it on iOS 26 and macOS 26: flat List rows
    /// (each section's in-list title, then its songs) with the section bar overlaid at the
    /// List's top by the screen's own ``SongsSectionBarOverlay``.
    private struct ComposedList: View {
        let chrome: SongsScrollChrome
        let sections: [SongsSectionBar.Entry]
        let rowsPerSection: Int

        var body: some View {
            List {
                ForEach(Array(sections.enumerated()), id: \.element.key) { index, entry in
                    SongsInlineSectionTitle(
                        key: entry.key, label: entry.label, spokenLabel: entry.spokenLabel,
                        accessibilityID: "fst.songs.section.\(index)", chrome: chrome
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    ForEach((0..<rowsPerSection).map { "\(entry.key)-\($0)" }, id: \.self) { row in
                        Text("Song \(row)")
                            .accessibilityIdentifier("fst.songs.row.\(row)")
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("fst.songs.list")
            .modifier(SongsSectionBarOverlay(chrome: chrome, sections: sections))
        }
    }

    /// Hosts ``ComposedList`` scrolled to its top, with ``SongsScrollChrome`` reporting a
    /// scroll as the screen's `ScrolledAwayTracker` does.
    private func hostComposed(
        _ chrome: SongsScrollChrome
    ) async throws -> (NSView, NSWindow, NSTableView, @MainActor () async throws -> Void) {
        let size = CGSize(width: 390, height: 320)
        let host = nativeHostedView(
            ComposedList(chrome: chrome, sections: sections, rowsPerSection: 12)
                .frame(width: size.width, height: size.height), size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let settle: @MainActor () async throws -> Void = {
            _ = try await nativeHostedSettle(host, timeout: .seconds(10))
        }
        try await settle()
        let table = try #require(chrome.listNudger.scrollView?.documentView as? NSTableView)
        chrome.setScrolled(true)
        return (host, window, table, settle)
    }

    /// Drags the List up in small steps, as a finger or trackpad would (a far jump skips
    /// the geometry a title reports on its way past the bar), until `reached` holds.
    private func scroll(
        _ chrome: SongsScrollChrome, settle: @MainActor () async throws -> Void,
        until reached: () -> Bool
    ) async throws {
        for _ in 0..<200 where !reached() {
            #expect(chrome.listNudger.moveContent(by: -4), "the List ran out of rows")
            try await settle()
        }
        #expect(reached(), "the scroll state was never reached")
    }

    /// The composed screen's elements in VoiceOver's reading order: what sits outside the
    /// List in tree order (SwiftUI places the overlaid bar first), then the List's rows by
    /// row index. AppKit reorders recycled row views, so their subview order is not the
    /// reading order; an outline reads its rows in index order.
    private func readingOrder(_ host: NSView, table: NSTableView) -> [MacAXNode] {
        let tree = macAccessibilityTree(host, navigationOrder: true)
        let listStart = tree.firstIndex { $0.role == "AXScrollArea" } ?? tree.endIndex
        let outside = exposed(Array(tree[..<listStart]))
        let visible = table.rows(in: table.visibleRect)
        let rows = (visible.lowerBound..<visible.upperBound).flatMap { index in
            table.rowView(atRow: index, makeIfNecessary: false).map {
                exposed(macAccessibilityTree($0, navigationOrder: true))
            } ?? []
        }
        return outside + rows
    }

    /// The section key a song row or in-list title belongs to (`nil` for the bar).
    private func sectionKey(_ node: MacAXNode) -> String? {
        if node.identifier.hasPrefix("fst.songs.row.") {
            return node.identifier.dropFirst("fst.songs.row.".count)
                .split(separator: "-").first.map(String.init)
        }
        if node.identifier.hasPrefix("fst.songs.section."),
           let index = Int(node.identifier.dropFirst("fst.songs.section.".count)) {
            return sections[index].key
        }
        return nil
    }

    /// Reading-order rules for one scroll state: the bar's heading is read first and
    /// once, the List's headings follow in section order, and every song is read after
    /// its own section's heading (or, for the section the bar names, after the bar).
    private func expectReadingOrder(
        _ order: [MacAXNode], headings expected: [String], state: String
    ) {
        let headings = order.filter { $0.role == "AXHeading" }
        #expect(headings.map(\.spokenName) == expected, "\(state): \(order)")
        #expect(headings.first?.identifier == "fst.songs.section-bar", "\(state): the bar is not read first")
        #expect(order.filter { $0.identifier == "fst.songs.section-bar" }.count == 1, "\(state): \(order)")
        let barKey = sections.first { $0.spokenLabel == headings.first?.spokenName }?.key
        var current: String?
        for node in order {
            if node.identifier == "fst.songs.section-bar" {
                current = barKey
            } else if node.role == "AXHeading" {
                current = sectionKey(node)
            } else if node.identifier.hasPrefix("fst.songs.row.") {
                #expect(sectionKey(node) == current, "\(state): \(node) is read under \(current ?? "nothing")")
            }
        }
        #expect(!order.contains { ["4★", "5★", "6★"].contains($0.spokenName) },
                "\(state): a visible star glyph label reached VoiceOver: \(order)")
    }

    /// Scrolled inside a section, VoiceOver reads the bar's heading, then the List's rows
    /// below it in order: that section's songs, then the next section's heading and songs.
    @Test func composedScrolledReadsTheBarThenTheListInOrder() async throws {
        let chrome = SongsScrollChrome()
        let (host, window, table, settle) = try await hostComposed(chrome)
        defer { window.orderOut(nil) }
        // The first title has gone under the bar; the second is still well below it.
        try await scroll(chrome, settle: settle) {
            chrome.passedHeaders == ["4"] && chrome.titleTops.isEmpty
                && !readingOrder(host, table: table).contains { $0.identifier == "fst.songs.section.0" }
        }
        let order = readingOrder(host, table: table)
        macAccessibilityDump(order, name: "songs-section-bar-composed-scrolled")
        expectReadingOrder(order, headings: ["4 stars", "5 stars"], state: "scrolled")
    }

    /// While "5 stars" pushes "4 stars" out, the bar draws both, but VoiceOver still
    /// reads one bar heading ("4 stars", still current) and then the List, where the
    /// incoming "5 stars" title stays a heading at its place in the reading order.
    @Test func composedPushKeepsOneBarHeadingAndListOrder() async throws {
        let chrome = SongsScrollChrome()
        let (host, window, table, settle) = try await hostComposed(chrome)
        defer { window.orderOut(nil) }
        try await scroll(chrome, settle: settle) {
            chrome.titleTops["5"].map { $0 > 2 } == true && !chrome.passedHeaders.contains("5")
        }
        let order = readingOrder(host, table: table)
        macAccessibilityDump(order, name: "songs-section-bar-composed-push")
        expectReadingOrder(order, headings: ["4 stars", "5 stars"], state: "push")
        let incoming = try #require(order.first { $0.identifier == "fst.songs.section.1" })
        #expect(incoming.role == "AXHeading" && incoming.spokenName == "5 stars")
    }

    /// Once "5 stars" lands, the bar names it and reads first. The landed in-list title,
    /// blanked under the bar, keeps its place in the List's order (headings rotor), and
    /// the next section's heading follows its songs.
    @Test func composedLandedTitleReadsTheBarThenItsBlankedTitle() async throws {
        let chrome = SongsScrollChrome()
        let (host, window, table, settle) = try await hostComposed(chrome)
        defer { window.orderOut(nil) }
        try await scroll(chrome, settle: settle) {
            chrome.passedHeaders.contains("5")
                && readingOrder(host, table: table).contains { $0.identifier == "fst.songs.section.2" }
        }
        let order = readingOrder(host, table: table)
        macAccessibilityDump(order, name: "songs-section-bar-composed-landed")
        let landed = order.contains { $0.identifier == "fst.songs.section.1" }
        expectReadingOrder(
            order, headings: landed ? ["5 stars", "5 stars", "Gold stars"] : ["5 stars", "Gold stars"],
            state: "landed"
        )
        #expect(macAccessibilityFindings(macAccessibilityTree(host)).isEmpty)
    }

    // MARK: Text size

    /// A long section name wraps instead of truncating, and the bar reports its taller
    /// height, which moves the row fade's edge and the push band with it (R3, R4).
    @Test func longSectionNameWrapsAndTheBarGrows() async throws {
        func barHeight(_ label: String) async throws -> CGFloat {
            let chrome = SongsScrollChrome()
            chrome.setScrolled(true)
            chrome.setHeader("x", passed: true)
            let bar = SongsSectionBar(chrome: chrome, sections: [
                SongsSectionBar.Entry(key: "x", label: label, spokenLabel: label),
            ])
            let (view, window, _) = try await host(bar, width: 120)
            defer { window.orderOut(nil) }
            #expect(elements(view).map(\.spokenName) == [label])
            return chrome.barHeight.value
        }
        let short = try await barHeight("A")
        let long = try await barHeight("Leaving the Item Shop Tomorrow")
        #expect(short > 0, "the bar never measured its title")
        #expect(long > short * 1.8, "a long name wrapped to several lines: \(long) vs \(short)")
    }
}
#endif
