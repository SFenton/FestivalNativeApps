#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// Accessibility tests for the canonical scroll-edge fades (issue #462, backfilling #308).
//
// #308 made one fade per edge kind (`.agents/patterns/scroll-edge.md`): the pinned
// section title fade (`PinnedHeaderEdgeFade`, the Notifications sheet's "New"/"Older"),
// the sheet header fade (`ModalTopEdgeFade`, which yields a hard edge to it) and the
// bottom chrome fade (`BottomChromeFade`, the boards' pager footer). Pixel tests prove
// the ramps; these prove what assistive technologies get from the same regions:
//
// - The fades are decorative (HIG VoiceOver: "Exclude purely decorative images"): they
//   add no element, and the controls and headings they sit beside keep their names,
//   roles and state.
// - Reading order: a pinned title is read before the rows under it (HIG VoiceOver: "Use
//   titles and headings to convey hierarchy"); board rows are read in rank order before
//   the pager floating over them.
// - Target size: rows and pager controls are at least 44×44 pt (HIG Accessibility).
// - Transparency and contrast: system Reduce Transparency and Increase Contrast and the
//   app's Less Transparency and Increase Contrast turn every ramp into a hard edge (R7)
//   without changing the tree; Reduce Motion is on throughout.
// - Text scaling: at the largest accessibility size the pinned title grows (HIG
//   Accessibility: "text enlargement of at least 200 percent"), the rows' fade edge
//   moves down with it and rows still never draw beside it.
//
// The Songs section bar has its own tests (`SongsSectionBarAccessibilityTests` and the
// iPhone CI journey `SongsChromeJourneyTests/testSectionBarHeadingAtLargestText`).

// MARK: - Shared helpers

/// Mean channel value (0–255) above which a sample is row text: light row text measures
/// ~140 or more on the dark page; within 10 pt of a fade's edge the ramp leaves it at most
/// ~25% opaque (~65), well under it.
private let fadedTextThreshold = 100

/// System scroller parts, which AppKit names by their role description.
private let scrollerSubroles: Set<String> = ["AXIncrementArrow", "AXDecrementArrow", "AXIncrementPage", "AXDecrementPage"]

/// Unnamed containers VoiceOver moves through rather than stops on.
private let containerRoles: Set<String> = ["AXGroup", "AXScrollArea", "AXOutline", "AXList", "AXOpaqueProviderGroup"]

/// The elements assistive technologies stop on, in reading order: no unnamed
/// containers, scroll bars or scroller parts.
@MainActor
private func readableElements(_ nodes: [MacAXNode]) -> [MacAXNode] {
    nodes.filter {
        $0.isElement && !scrollerSubroles.contains($0.subrole)
            && !["AXScrollBar", "AXValueIndicator"].contains($0.role)
            && !(containerRoles.contains($0.role) && $0.spokenName.isEmpty)
    }
}

/// Whether a realized accessibility element reports itself enabled.
@MainActor
private func isAccessibilityEnabled(_ element: NSObject) -> Bool {
    guard element.responds(to: NSSelectorFromString("isAccessibilityEnabled")) else { return true }
    return (element.value(forKey: "isAccessibilityEnabled") as? Bool) ?? true
}

/// The deepest scroll view under `view` whose document is a table (a SwiftUI List).
@MainActor
private func listScrollView(in view: NSView) -> NSScrollView? {
    for subview in view.subviews {
        if let found = listScrollView(in: subview) { return found }
    }
    if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
    return nil
}

/// The deepest scroll view under `view` whose content runs past its height (a board).
@MainActor
private func longScrollView(in view: NSView) -> NSScrollView? {
    for subview in view.subviews {
        if let found = longScrollView(in: subview) { return found }
    }
    if let scroll = view as? NSScrollView, let document = scroll.documentView,
       document.frame.height > scroll.contentView.bounds.height + 100 {
        return scroll
    }
    return nil
}

/// Scroll `scroll` so `offset` points of content sit above its top, and let it settle.
@MainActor
@discardableResult
private func scrollHosted(
    _ scroll: NSScrollView, to offset: CGFloat, host: NSHostingView<some View>, untilText texts: [String] = []
) async throws -> CGImage {
    let clip = scroll.contentView
    clip.scroll(to: NSPoint(x: 0, y: offset - scroll.contentInsets.top))
    scroll.reflectScrolledClipView(clip)
    return texts.isEmpty ? try await nativeHostedSettle(host) : try await nativeHostedSettle(host, untilText: texts)
}

/// Where a List's headers pin, in the host's top-left points.
@MainActor
private func pinTop(of scroll: NSScrollView, in host: NSView) -> CGFloat {
    let frame = scroll.convert(scroll.bounds, to: host)
    return (host.isFlipped ? frame.minY : host.bounds.height - frame.maxY) + scroll.contentInsets.top
}

/// Height, in points, of the bright ink inside `rect` of a capture.
///
/// - Parameters:
///   - image: A capture of the whole host.
///   - rect: A region, in the host's top-left points.
///   - hostSize: The host's size in points.
/// - Returns: From the first to the last sampled row holding ink; 0 without ink.
@MainActor
private func inkHeight(in rect: CGRect, of image: CGImage, hostSize: CGSize) -> CGFloat {
    var first: CGFloat?
    var last: CGFloat = 0
    for y in stride(from: rect.minY, to: rect.maxY, by: 0.5) {
        let line = CGRect(x: rect.minX, y: y, width: rect.width, height: 0.5)
        if nativeHostedBrightSamples(in: line, of: image, hostSize: hostSize) > 0 {
            first = first ?? y
            last = y
        }
    }
    guard let first else { return 0 }
    return last - first + 0.5
}

// MARK: - Notifications sheet (pinned title and sheet header fades)

/// The Notifications sheet hosted at a sheet-like size over its page background, in
/// `mode` (the host keeps system transparency so the standard mode shows its ramp).
@MainActor
private func hostNotificationsSheet(
    _ session: FestivalSession, mode: BottomChromeFadeMode, defaults: UserDefaults, size: CGSize
) -> NSHostingView<NativeHostedRoot<some View>> {
    nativeHostedView(
        mode.system(
            NotificationsSheet(session: session)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .background(BrandTokens.appBackground)
                .defaultAppStorage(defaults)
        ),
        size: size, forceGlassFallback: false
    )
}

/// Issues #462 and #308: with rows scrolled under the pinned "New" or "Older" title, in
/// every transparency and contrast mode, the sheet reads as headings and named rows.
///
/// - The pinned title is an `AXHeading` with its visible text, read before every row,
///   and it lies in the pinned band at the top of the list.
/// - Every row is one named button at least 44 pt tall and as wide as the list, read
///   in list order; the fades add no other element, and nothing is unnamed.
/// - Rendered: no row text beside the pinned title in any mode, and in the 9 pt strip
///   just under its edge (swept across one 93 pt row pitch) row text is dimmed by the
///   ramp in the standard mode but drawn whole at a hard edge in the other modes (R7).
@MainActor
@Test(.serialized, arguments: BottomChromeFadeMode.allCases, [160.0, 900.0])
func notificationsPinnedTitleIsAHeadingReadBeforeItsRows(mode: BottomChromeFadeMode, offset: Double) async throws {
    let pinned = offset < 800 ? "New" : "Older"
    let (session, accountId) = await scrollingNotificationsSession(newCount: 8, olderCount: 24)
    defer { forgetScrollingAccount(accountId) }
    let (defaults, suite) = mode.storage()
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let size = CGSize(width: 420, height: 640)
    let host = hostNotificationsSheet(session, mode: mode, defaults: defaults, size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: ["New"])
    let scroll = try #require(listScrollView(in: host))
    let table = try #require(scroll.documentView as? NSTableView)
    let headerRow = table.rect(ofRow: 0).height
    #expect(headerRow > 20)
    let image = try await scrollHosted(scroll, to: offset, host: host, untilText: [pinned])
    let top = pinTop(of: scroll, in: host)

    // Tree: the pinned heading first, then rows in list order; nothing else.
    let nodes = macAccessibilityTree(host, navigationOrder: true)
    macAccessibilityDump(nodes, name: "notifications-pinned-\(pinned.lowercased())-\(mode.rawValue)")
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
    let elements = readableElements(nodes)
    let rowPrefix = "fst.notifications.row.\(accountId)-"
    let firstRow = try #require(elements.firstIndex { $0.identifier.hasPrefix(rowPrefix) }, "rows are readable")
    let lead = elements[..<firstRow]
    #expect(lead.map(\.role) == ["AXHeading"], "only the pinned title precedes the rows: \(lead.map(\.description))")
    #expect(lead.first?.spokenName == pinned)
    let unexpected = elements.filter {
        !($0.role == "AXHeading" && ["New", "Older"].contains($0.spokenName))
            && !($0.role == "AXButton" && $0.identifier.hasPrefix(rowPrefix))
    }
    #expect(unexpected.isEmpty, "the fades add no element: \(unexpected.map(\.description))")
    let rows = elements.filter { $0.identifier.hasPrefix(rowPrefix) }
    let indices = rows.compactMap { Int($0.identifier.dropFirst(rowPrefix.count)) }
    #expect(indices.count == rows.count)
    #expect(indices == indices.sorted(), "rows read in list order: \(indices)")
    #expect(Set(indices).count == indices.count)
    for row in rows {
        #expect(row.spokenName.contains("Fixture Anthem"), "row is named by its song: \(row)")
        #expect(row.spokenName.contains("Rank Up"), "row names its event: \(row)")
        let frame = try #require(nativeHostedAccessibilityFrame(row.identifier, in: host))
        #expect(frame.height >= 44 && frame.width >= size.width - 60, "\(row.identifier) is a full-width 44 pt target: \(frame)")
    }

    // The pinned heading is where it is drawn: in the band at the list's top.
    let heading = try #require(nativeHostedAccessibilityElement(in: host) {
        nativeHostedAccessibilityString($0, "accessibilityRole") == "AXHeading"
            && nativeHostedAccessibilityString($0, "accessibilityLabel") == pinned
    })
    let headingFrame = try #require(nativeHostedAccessibilityFrame(of: heading, in: host))
    #expect(headingFrame.minY >= top - 1 && headingFrame.maxY <= top + headerRow + 1,
            "the pinned title's frame is its pinned band: \(headingFrame), band \(top)…\(top + headerRow)")

    // Rendered: nothing beside the pinned title; R7 at its edge.
    let band = CGRect(x: 90, y: top + 1, width: size.width - 110, height: headerRow - 2)
    #expect(nativeHostedBrightSamples(in: band, of: image, hostSize: size) == 0, "no row text beside the pinned title")
    var stripBright = 0
    for step in 0..<11 {
        let shot = try await scrollHosted(scroll, to: offset + Double(step) * 9, host: host, untilText: [pinned])
        let strip = CGRect(x: 20, y: top + headerRow + 1, width: size.width - 40, height: 9)
        stripBright += nativeHostedBrightSamples(in: strip, of: shot, hostSize: size, threshold: fadedTextThreshold)
        if step == 0 {
            _ = try nativeHostedPNG(
                shot, filename: "notifications-a11y-\(pinned.lowercased())-\(mode.rawValue).png",
                environment: "FST_HISTORY_RENDER_OUT"
            )
        }
    }
    if mode.hardEdge {
        #expect(stripBright > 0, "\(mode.rawValue) draws rows whole up to the pinned title (hard edge)")
    } else {
        #expect(stripBright == 0, "rows fade in under the pinned title")
    }
}

// MARK: - Pinned title text scaling

/// A Notifications-style sheet list whose title and rows scale with Dynamic Type on the
/// Mac host (``ReloadGateA11yText``: the HIG iOS size table), using the canonical pinned
/// title fade exactly as the Notifications sheet does, or (`fades` false) the same
/// List without it.
private struct PinnedTitleScalingHarness: View {
    static let titleID = "fst.tests.pinned-title.new"

    static func rowID(_ index: Int) -> String { "fst.tests.pinned-title.row.\(index)" }

    let state: PinnedHeaderEdgeFadeState
    let typeSize: DynamicTypeSize
    var fades = true

    var body: some View {
        list
            .environment(\.dynamicTypeSize, typeSize)
            .environment(\._accessibilityReduceTransparency, false)
            .environment(\._colorSchemeContrast, .standard)
            .preferredColorScheme(.dark)
            .background(BrandTokens.appBackground)
    }

    @ViewBuilder private var list: some View {
        let list = List {
            Section {
                ForEach(0..<30, id: \.self) { index in
                    let row = ReloadGateA11yText(text: "Row \(index)", style: .body)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .accessibilityIdentifier(Self.rowID(index))
                    if fades { row.pinnedHeaderEdgeFadeRow(state, first: index == 0) } else { row }
                }
            } header: {
                let title = ReloadGateA11yText(text: "New", style: .subheadline)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.titleID)
                if fades { title.pinnedHeaderEdgeFadeHeader(state, first: true) } else { title }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        if fades { list.pinnedHeaderEdgeFadeList(state, showsHeaders: true) } else { list }
    }
}

/// One reading of the scaling harness: its title's frame and ink and the fade's edge.
private struct PinnedTitleReading {
    let headingFrame: CGRect
    let titleInk: CGFloat
    let headerHeight: CGFloat
    let edge: CGFloat
}

/// Issue #462: at the largest accessibility text size the pinned title is still a
/// whole, readable heading. Its glyphs grow at least 200% over the default size (HIG
/// Accessibility), its frame fits its text, the fade's edge moves down by the title's
/// growth so rows clear the taller title, and no row text draws beside it once rows
/// scroll under it.
@MainActor
@Test func pinnedTitleScalesToTheLargestAccessibilitySizeAndRowsStillClearIt() async throws {
    let size = CGSize(width: 420, height: 720)
    var readings: [DynamicTypeSize: PinnedTitleReading] = [:]
    for typeSize in [DynamicTypeSize.large, .accessibility5] {
        let state = PinnedHeaderEdgeFadeState()
        let host = nativeHostedView(
            PinnedTitleScalingHarness(state: state, typeSize: typeSize).frame(width: size.width, height: size.height),
            size: size, forceGlassFallback: false
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host) { state.headerHeight > 0 }
        let scroll = try #require(listScrollView(in: host))
        let top = pinTop(of: scroll, in: host)
        let rest = try nativeHostedImage(host)

        let headingFrame = try #require(nativeHostedAccessibilityFrame(PinnedTitleScalingHarness.titleID, in: host))
        let needed = ReloadGateAccessibilityTests.idealSize("New", .subheadline, typeSize)
        #expect(headingFrame.height >= needed.height - 0.5 && headingFrame.width >= needed.width - 0.5,
                "\(typeSize): the title is whole: \(headingFrame) for \(needed)")
        let titleInk = inkHeight(in: headingFrame, of: rest, hostSize: size)

        // Scrolled: rows pass under the taller title without drawing beside it.
        let image = try await scrollHosted(scroll, to: 300, host: host)
        let pinnedFrame = try #require(nativeHostedAccessibilityFrame(PinnedTitleScalingHarness.titleID, in: host))
        let nodes = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "pinned-title-\(typeSize)")
        #expect(macAccessibilityFindings(nodes).isEmpty)
        let elements = readableElements(nodes)
        #expect(elements.first?.role == "AXHeading", "\(typeSize): the pinned title is read first: \(elements.prefix(2))")
        #expect(elements.first?.spokenName == "New")
        #expect(abs(pinnedFrame.minY - headingFrame.minY) <= 1, "\(typeSize): the title stays pinned")
        let edgeY = top - state.pinLine + state.edge
        #expect(edgeY >= pinnedFrame.maxY - 0.5, "\(typeSize): rows fade out by the title's bottom: \(edgeY) vs \(pinnedFrame)")
        let beside = CGRect(
            x: pinnedFrame.maxX + 12, y: top + 1,
            width: size.width - pinnedFrame.maxX - 32, height: edgeY - top - 2
        )
        #expect(nativeHostedBrightSamples(in: beside, of: image, hostSize: size) == 0,
                "\(typeSize): no row text beside the pinned title")
        _ = try nativeHostedPNG(
            image, filename: "pinned-title-\(typeSize).png", environment: "FST_HISTORY_RENDER_OUT"
        )
        readings[typeSize] = PinnedTitleReading(
            headingFrame: headingFrame, titleInk: titleInk, headerHeight: state.headerHeight, edge: state.edge
        )
    }
    let large = try #require(readings[.large]), largest = try #require(readings[.accessibility5])
    #expect(large.titleInk > 0)
    #expect(largest.titleInk >= large.titleInk * 2, "title glyphs grow ≥200%: \(large.titleInk) → \(largest.titleInk)")
    #expect(largest.headerHeight > large.headerHeight)
    #expect(abs((largest.edge - large.edge) - (largest.headerHeight - large.headerHeight)) <= 1,
            "the fade edge moves down with the title: \(large.edge) → \(largest.edge)")
}

/// Issue #462: the pinned title fade is decorative. At rest, part-scrolled and with rows
/// under the pinned title, the List with the fade exposes exactly the elements of the
/// same List without it, in the same order, with the same roles and names.
///
/// (At rest macOS exposes a plain List's first section header after its rows, as a
/// floating group row; once pinned it is read first. The fade keeps both orders.)
@MainActor
@Test func pinnedTitleFadeLeavesTheListsAccessibilityTreeUnchanged() async throws {
    let size = CGSize(width: 420, height: 640)
    var trees: [Bool: [[String]]] = [:]
    for fades in [false, true] {
        let state = PinnedHeaderEdgeFadeState()
        let host = nativeHostedView(
            PinnedTitleScalingHarness(state: state, typeSize: .large, fades: fades)
                .frame(width: size.width, height: size.height),
            size: size, forceGlassFallback: false
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Row 1"])
        let scroll = try #require(listScrollView(in: host))
        var readings: [[String]] = []
        for offset in [0.0, 20.0, 200.0] {
            try await scrollHosted(scroll, to: offset, host: host)
            let nodes = macAccessibilityTree(host, navigationOrder: true)
            #expect(macAccessibilityFindings(nodes).isEmpty)
            let elements = readableElements(nodes).filter { $0.role != "AXGroup" }
            readings.append(elements.map { "\($0.role) \($0.spokenName) #\($0.identifier)" })
        }
        trees[fades] = readings
    }
    let plain = try #require(trees[false]), faded = try #require(trees[true])
    #expect(plain == faded, "the fade adds, drops or reorders nothing")
    let pinned = try #require(faded.last)
    #expect(pinned.first == "AXHeading New #\(PinnedTitleScalingHarness.titleID)", "the pinned title is read first: \(pinned.prefix(2))")
}

// MARK: - Board bottom chrome fade

extension BottomChromeBandBoard {
    /// Identifier prefix of the board's pager controls.
    var pagerPrefix: String {
        switch self {
        case .bandRankings: "fst.band-rankings"
        case .songBand: "fst.song-band-leaderboard"
        }
    }
}

/// Issues #462 and #308: the bottom chrome fade over a band board's rows is decorative.
/// In every transparency and contrast mode, mid-list and at the end of the page:
///
/// - Rows are read in rank order, all before the pager that floats over them.
/// - The pager's four arrows and its page badge keep their names; on page 1 First and
///   Previous are disabled and Next and Last enabled; the badge is adjustable ("Page").
/// - Each arrow is a 44×44 pt target and the badge is 44 pt tall, all wholly below the
///   fade's edge (the chrome's top), never under the fade.
/// - At the end of the page the last row's frame rests above the chrome, so focus on it
///   lands on fully drawn text.
/// - The fade adds no element and nothing is unnamed.
@MainActor
@Test(.serialized, arguments: BottomChromeBandBoard.allCases, BottomChromeFadeMode.allCases)
func boardBottomChromeFadeKeepsRowsAndPagerReadable(board: BottomChromeBandBoard, mode: BottomChromeFadeMode) async throws {
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongBandBoardsTransport())
    let session = FestivalSession(factory: { client })
    let (defaults, suite) = mode.storage()
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let size = CGSize(width: 402, height: 700)
    let host = nativeHostedView(
        mode.system(
            try await board.screen(session)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .defaultAppStorage(defaults)
        ),
        size: size, forceGlassFallback: false
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: [board.loadedText], timeout: .seconds(60))
    let scroll = try #require(longScrollView(in: host))
    let scrollFrame = scroll.convert(scroll.bounds, to: host)
    #expect(host.isFlipped)
    let chromeTop = scrollFrame.maxY - scroll.contentInsets.bottom
    let document = try #require(scroll.documentView)
    let end = document.frame.height + scroll.contentInsets.bottom - scroll.contentView.bounds.height
        + scroll.contentInsets.top
    let rowIDs = (1...25).map(board.rowId)
    let pagerIDs = ["page-first", "page-previous", "page-info", "page-next", "page-last"].map { "\(board.pagerPrefix).\($0)" }

    for (place, offset) in [("mid", CGFloat(300)), ("end", end)] {
        try await scrollHosted(scroll, to: offset, host: host)
        let nodes = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "\(board.rawValue)-\(place)-\(mode.rawValue)")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(place): \(macAccessibilityFindings(nodes))")
        let elements = readableElements(nodes)
        #expect(!elements.contains { $0.role == "AXImage" && $0.spokenName.isEmpty },
                "\(place): no unnamed image (the fade is decorative)")

        // Rows in rank order, then the pager.
        let rowPositions = elements.indices.filter { rowIDs.contains(elements[$0].identifier) }
        let ranks = rowPositions.compactMap { rowIDs.firstIndex(of: elements[$0].identifier) }
        #expect(!ranks.isEmpty, "\(place): rows are readable")
        #expect(ranks == ranks.sorted() && Set(ranks).count == ranks.count, "\(place): rows read in rank order: \(ranks)")
        let pagerPositions = pagerIDs.map { id in elements.firstIndex { $0.identifier == id } }
        #expect(pagerPositions.allSatisfy { $0 != nil }, "\(place): pager controls are readable: \(pagerPositions)")
        let pager = pagerPositions.compactMap { $0 }
        #expect(pager == pager.sorted(), "\(place): pager reads First, Previous, Page, Next, Last")
        if let lastRow = rowPositions.last, let firstPager = pager.first {
            #expect(lastRow < firstPager, "\(place): rows are read before the pager over them")
        }

        // Names, state and targets of the pager.
        // Band Rankings' glass pager titles its arrows "First Page"; the Song Band pager
        // "First page". VoiceOver speaks both alike.
        let names = pagerIDs.compactMap { id in elements.first { $0.identifier == id }?.spokenName.lowercased() }
        #expect(names == ["first page", "previous page", "page", "next page", "last page"], "\(place): \(names)")
        for (index, id) in pagerIDs.enumerated() {
            let element = try #require(nativeHostedAccessibilityElement(id, in: host))
            let frame = try #require(nativeHostedAccessibilityFrame(of: element, in: host))
            #expect(frame.minY >= chromeTop - 0.5, "\(place): \(id) is below the fade's edge: \(frame) vs \(chromeTop)")
            #expect(frame.maxY <= size.height + 0.5, "\(place): \(id) is on the page: \(frame)")
            if index == 2 {
                #expect(frame.height >= 44, "\(place): the page badge is 44 pt tall: \(frame)")
            } else {
                #expect(frame.width >= 44 && frame.height >= 44, "\(place): \(id) is a 44×44 pt target: \(frame)")
                #expect(isAccessibilityEnabled(element) == (index > 2), "\(place): \(id) enabled on page 1")
            }
        }
    }

    // At the end the last row rests above the chrome, not under the fade.
    let last = try #require(nativeHostedAccessibilityFrame(board.rowId(25), in: host))
    #expect(last.maxY <= chromeTop + 0.5, "the last row's frame ends above the chrome: \(last) vs \(chromeTop)")
}
#endif
