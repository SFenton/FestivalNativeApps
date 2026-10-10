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

// MARK: - Notifications sheet header (Mac sheet presentation)

/// Presents the Notifications sheet the way `MacRootView` does (`.sheet` with
/// `macSheetFrame(width: 560, height: 680)` and `festivalSheet(.large)`), in `mode`, so
/// `FestivalModal`'s real header (its title bar and Close item) frames the list.
/// `height` is 680 unless the host's screen is too short for it (see
/// `macNotificationsSheetHeight(visibleHeight:)`).
private struct MacNotificationsSheetPresenter: View {
    let session: FestivalSession
    let mode: BottomChromeFadeMode
    let defaults: UserDefaults
    let height: CGFloat

    var body: some View {
        BrandTokens.appBackground
            .sheet(isPresented: .constant(true)) {
                mode.system(
                    NotificationsSheet(session: session)
                        .macSheetFrame(width: 560, height: height)
                        .festivalSheet(.large)
                        .preferredColorScheme(.dark)
                        .defaultAppStorage(defaults)
                )
            }
    }
}

/// A presented Notifications sheet and the window it is attached to.
private struct PresentedNotificationsSheet {
    let parent: NSWindow
    let sheet: NSWindow
    /// The sheet's SwiftUI content view: the whole sheet, header and bottom bar included.
    let view: NSView

    /// The sheet's size in points.
    var size: CGSize { view.bounds.size }

    /// Dismiss the sheet and put both windows away.
    @MainActor
    func close() {
        parent.endSheet(sheet)
        sheet.orderOut(nil)
        parent.orderOut(nil)
    }
}

/// Present the Notifications sheet on a titled window, which AppKit needs to attach a
/// sheet. Both windows are fully transparent and ignore the mouse, so the operator never
/// sees or clicks them; captures read the views, not the screen.
///
/// - Parameters:
///   - session: A session with a selected player and loaded notifications.
///   - mode: The transparency and contrast mode.
///   - defaults: The mode's settings suite.
///   - tallerThanScreen: Ask for a sheet taller than the screen, so AppKit shrinks it.
/// - Returns: The parent window, the sheet window and its content view.
/// - Throws: A sheet that never attaches, or one AppKit shrank when it should fit.
@MainActor
private func presentMacNotificationsSheet(
    _ session: FestivalSession, mode: BottomChromeFadeMode, defaults: UserDefaults,
    tallerThanScreen: Bool = false
) async throws -> PresentedNotificationsSheet {
    let visibleHeight = NSScreen.main?.visibleFrame.height ?? 0
    var (parentHeight, sheetHeight) = try #require(
        macNotificationsSheetHeight(visibleHeight: visibleHeight),
        "the screen (\(visibleHeight) pt visible) is too short for the Notifications sheet"
    )
    if tallerThanScreen { sheetHeight = visibleHeight + 120 }
    let size = CGSize(width: 900, height: parentHeight)
    let host = nativeHostedView(
        MacNotificationsSheetPresenter(session: session, mode: mode, defaults: defaults, height: sheetHeight),
        size: size, forceGlassFallback: false
    )
    let parent = NSWindow(
        contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
        styleMask: [.titled, .closable], backing: .buffered, defer: false
    )
    parent.isReleasedWhenClosed = false
    parent.appearance = NSAppearance(named: .darkAqua)
    parent.alphaValue = 0
    parent.ignoresMouseEvents = true
    parent.contentView = host
    parent.orderFrontRegardless()
    var budget = NativeHostedPollBudget(.seconds(10))
    while parent.attachedSheet == nil, !budget.isExhausted {
        try await budget.sleep(for: .milliseconds(50))
        host.layoutSubtreeIfNeeded()
    }
    let sheet = try #require(parent.attachedSheet, "the Notifications sheet attaches to its window")
    sheet.alphaValue = 0
    sheet.ignoresMouseEvents = true
    let view = try #require(sheet.contentView)
    view.layoutSubtreeIfNeeded()
    try #require(tallerThanScreen || view.bounds.height >= sheetHeight,
                 "AppKit clamped the sheet to \(view.bounds.height) pt, under its \(sheetHeight) pt list, on a \(visibleHeight) pt screen")
    return PresentedNotificationsSheet(parent: parent, sheet: sheet, view: view)
}

/// The parent window's content height and the sheet's `macSheetFrame` height for a
/// screen with `visibleHeight` points: the app's 820 and 680 when they fit, else smaller,
/// so AppKit never clamps the sheet window and pushes its header and bottom bar outside
/// the content view. Hosted CI runners have short virtual displays (about 768 pt).
///
/// - Parameter visibleHeight: The main screen's visible height, below the menu bar.
/// - Returns: Both heights in points; `nil` when the list would be under 420 pt.
func macNotificationsSheetHeight(visibleHeight: CGFloat) -> (parent: CGFloat, sheet: CGFloat)? {
    // The parent's title bar, plus room around the sheet and for its bottom bar.
    let parent = min(820, visibleHeight - 48)
    let sheet = min(680, parent - 110)
    return sheet >= 420 ? (parent, sheet) : nil
}

/// Lay out and capture `view` until every text in `texts` is in its accessibility tree
/// and two captures in a row match (or a second has passed since it became ready).
///
/// - Parameters:
///   - view: A presented sheet's content view.
///   - texts: Substrings that must each appear in some label, title or value.
/// - Returns: The settled capture, at least 2x, in the view's top-left points.
/// - Throws: An unavailable native bitmap.
@MainActor
private func settleSheet(_ view: NSView, untilText texts: [String]) async throws -> CGImage {
    var budget = NativeHostedPollBudget(.seconds(20))
    var previous: Int?
    var readySince: ContinuousClock.Instant?
    while true {
        try await budget.sleep(for: .milliseconds(40))
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let accessibility = nativeHostedAccessibility(view)
        guard texts.allSatisfy(accessibility.contains) else {
            if budget.isExhausted {
                Issue.record("the sheet never showed \(texts)")
                return try nativeHostedCache(view, in: view.bounds)
            }
            continue
        }
        let image = try nativeHostedCache(view, in: view.bounds)
        let signature = nativeHostedSignature(image)
        let since = readySince ?? .now
        readySince = since
        if signature == previous || ContinuousClock.now - since > .seconds(1) { return image }
        previous = signature
    }
}

/// Scroll a presented sheet's list so `offset` points of content sit above its top.
@MainActor
@discardableResult
private func scrollSheet(_ scroll: NSScrollView, to offset: CGFloat, view: NSView, untilText texts: [String]) async throws -> CGImage {
    let clip = scroll.contentView
    clip.scroll(to: NSPoint(x: 0, y: offset - scroll.contentInsets.top))
    scroll.reflectScrolledClipView(clip)
    return try await settleSheet(view, untilText: texts)
}

/// Issue #462: on a screen shorter than the sheet's ideal height (a small display, or a
/// "Larger Text" display scaling), AppKit shrinks the sheet window to the screen and
/// `macSheetFrame`'s `400` floor lets the content shrink with
/// it. The header's title and the bottom bar's Close button stay inside the sheet, are
/// read first and last, and Close stays enabled; before the floor, a minimum equal to the
/// ideal height overflowed both edges and pushed them outside the window.
@MainActor
@Test
func notificationsSheetKeepsItsTitleAndCloseOnAShortScreen() async throws {
    let (session, accountId) = await scrollingNotificationsSession(newCount: 8, olderCount: 24)
    defer { forgetScrollingAccount(accountId) }
    let mode = BottomChromeFadeMode.standard
    let (defaults, suite) = mode.storage()
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let presented = try await presentMacNotificationsSheet(session, mode: mode, defaults: defaults, tallerThanScreen: true)
    defer { presented.close() }
    let view = presented.view
    let size = presented.size
    _ = try await settleSheet(view, untilText: ["New", "Close"])
    let visibleHeight = NSScreen.main?.visibleFrame.height ?? 0
    #expect(size.height <= visibleHeight + 1, "AppKit fits the sheet to the screen: \(size), \(visibleHeight) pt visible")
    #expect(size.height >= MacSheetMetrics.shortestHeight, "the list keeps its floor: \(size)")

    let scroll = try #require(listScrollView(in: view))
    let top = pinTop(of: scroll, in: view)
    let scrollFrame = scroll.convert(scroll.bounds, to: view)
    let listBottom = view.isFlipped ? scrollFrame.maxY : size.height - scrollFrame.minY
    let title = try #require(nativeHostedAccessibilityElement(in: view) { element in
        nativeHostedAccessibilityString(element, "accessibilityRole") == "AXStaticText"
            && ["accessibilityLabel", "accessibilityValue"].contains {
                nativeHostedAccessibilityString(element, $0) == "Notifications"
            }
    })
    let titleFrame = try #require(nativeHostedAccessibilityFrame(of: title, in: view))
    #expect(titleFrame.minY >= 0 && titleFrame.maxY <= top + 1, "the title is in the header band: \(titleFrame), list top \(top)")
    let close = try #require(nativeHostedAccessibilityElement("fst.notifications.close", in: view))
    #expect(isAccessibilityEnabled(close), "Close is enabled")
    let closeFrame = try #require(nativeHostedAccessibilityFrame(of: close, in: view))
    #expect(closeFrame.minY >= listBottom - 1 && closeFrame.maxY <= size.height,
            "Close is in the bottom bar: \(closeFrame), list bottom \(listBottom), sheet \(size)")

    let elements = readableElements(macAccessibilityTree(view, navigationOrder: true))
    #expect(elements.first?.spokenName == "Notifications", "the title is read first: \(elements.prefix(2).map(\.description))")
    #expect(elements.last?.identifier == "fst.notifications.close", "Close is read last: \(elements.suffix(2).map(\.description))")
}

/// Issues #462 and #308: the real Mac sheet header around the Notifications list, in
/// every transparency and contrast mode, with rows scrolled under the pinned "New" or
/// "Older" title. `NotificationsSheet` is presented as `MacRootView` presents it, so
/// `FestivalModal` supplies its own header (the inline title and the
/// `fst.notifications.close` confirmation item) and `ModalTopEdgeFadeModifier` masks
/// the list under it.
///
/// - The header is readable: "Notifications" is the first element read and lies in the
///   header band above the list; Close is one enabled, named button (HIG Sheets on
///   macOS put it in the sheet's bottom bar, so it lies below the list and is read
///   after it, matching what VoiceOver users find by position).
/// - The pinned title and rows keep the bare-sheet guarantees: the pinned heading is
///   read before every row and lies in its band at the list's top; rows are named
///   44 pt buttons in list order; the fades add no element and nothing is unnamed.
/// - Rows never draw under the header: the list's scroll view starts at the sheet's top
///   and scrolls under the header (a top content inset), so only the modal fade's clear
///   band keeps rows out; once scrolled, and across a row pitch, the header band beside
///   the title holds no row text.
/// - Rendered R7 at the pinned title's edge: the 9 pt strip under it is dimmed by the
///   ramp in the standard mode and drawn whole at a hard edge in the other modes.
/// - The modal fade yields to the pinned title (`ModalTopEdgeFadeRampKey` = 0): pinned
///   right under the header, "Older" draws as much ink as it does mid-list, at rest
///   (within 10%). Its glyphs sit about 7 pt below the header's edge, so without the
///   yield the sheet header's 40 pt ramp would leave them under half opaque.
@MainActor
@Test(.serialized, arguments: BottomChromeFadeMode.allCases, [160.0, 900.0])
func notificationsSheetHeaderFramesThePinnedTitleAndRows(mode: BottomChromeFadeMode, offset: Double) async throws {
    let pinned = offset < 800 ? "New" : "Older"
    let newCount = 8
    let (session, accountId) = await scrollingNotificationsSession(newCount: newCount, olderCount: 24)
    defer { forgetScrollingAccount(accountId) }
    let (defaults, suite) = mode.storage()
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let presented = try await presentMacNotificationsSheet(session, mode: mode, defaults: defaults)
    defer { presented.close() }
    let view = presented.view
    let size = presented.size
    _ = try await settleSheet(view, untilText: ["New", "Close"])
    let scroll = try #require(listScrollView(in: view))
    let table = try #require(scroll.documentView as? NSTableView)
    let headerRow = table.rect(ofRow: 0).height
    #expect(headerRow > 20)
    let top = pinTop(of: scroll, in: view)
    let scrollFrame = scroll.convert(scroll.bounds, to: view)
    let listTopEdge = view.isFlipped ? scrollFrame.minY : size.height - scrollFrame.maxY
    let listBottom = view.isFlipped ? scrollFrame.maxY : size.height - scrollFrame.minY
    #expect(listTopEdge < top - 20, "the list scrolls under the header: frame \(scrollFrame), pins at \(top)")

    // At rest: the "Older" title mid-list, for the yield check below.
    var restInk: Int?
    if pinned == "Older" {
        let olderRow = table.rect(ofRow: newCount + 1).minY
        let rest = try await scrollSheet(scroll, to: olderRow - 240, view: view, untilText: ["Older"])
        let older = try #require(nativeHostedAccessibilityElement(in: view) {
            nativeHostedAccessibilityString($0, "accessibilityRole") == "AXHeading"
                && nativeHostedAccessibilityString($0, "accessibilityLabel") == "Older"
        })
        let frame = try #require(nativeHostedAccessibilityFrame(of: older, in: view))
        #expect(frame.minY > top + 100, "Older rests mid-list: \(frame), list top \(top)")
        restInk = nativeHostedBrightSamples(in: frame, of: rest, hostSize: size)
    }
    let image = try await scrollSheet(scroll, to: offset, view: view, untilText: [pinned, "Close"])
    _ = try nativeHostedPNG(
        image, filename: "notifications-sheet-a11y-\(pinned.lowercased())-\(mode.rawValue).png",
        environment: "FST_HISTORY_RENDER_OUT"
    )

    // Tree: the title, the pinned heading, the rows in list order, then Close.
    let nodes = macAccessibilityTree(view, navigationOrder: true)
    macAccessibilityDump(nodes, name: "notifications-sheet-\(pinned.lowercased())-\(mode.rawValue)")
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
    let elements = readableElements(nodes)
    let rowPrefix = "fst.notifications.row.\(accountId)-"
    let firstRow = try #require(elements.firstIndex { $0.identifier.hasPrefix(rowPrefix) }, "rows are readable")
    let lead = elements[..<firstRow]
    #expect(lead.map(\.spokenName) == ["Notifications", pinned], "the title, then the pinned heading: \(lead.map(\.description))")
    #expect(lead.last?.role == "AXHeading")
    let closeIndex = try #require(elements.firstIndex { $0.identifier == "fst.notifications.close" }, "Close is readable")
    #expect(elements[closeIndex].role == "AXButton" && elements[closeIndex].spokenName == "Close", "\(elements[closeIndex])")
    #expect(closeIndex == elements.count - 1, "Close, in the bottom bar, is read last: \(elements.suffix(3).map(\.description))")
    let unexpected = elements.filter {
        !($0.role == "AXHeading" && ["New", "Older"].contains($0.spokenName))
            && !($0.role == "AXButton" && $0.identifier.hasPrefix(rowPrefix))
            && !($0.identifier == "fst.notifications.close")
            && !($0.role == "AXStaticText" && $0.spokenName == "Notifications")
    }
    #expect(unexpected.isEmpty, "the fades add no element: \(unexpected.map(\.description))")
    let rows = elements.filter { $0.identifier.hasPrefix(rowPrefix) }
    let indices = rows.compactMap { Int($0.identifier.dropFirst(rowPrefix.count)) }
    #expect(indices.count == rows.count)
    #expect(indices == indices.sorted(), "rows read in list order: \(indices)")
    for row in rows {
        #expect(row.spokenName.contains("Fixture Anthem") && row.spokenName.contains("Rank Up"), "row is named: \(row)")
        let frame = try #require(nativeHostedAccessibilityFrame(row.identifier, in: view))
        #expect(frame.height >= 44 && frame.width >= size.width - 60, "\(row.identifier) is a full-width 44 pt target: \(frame)")
    }

    // The header: the title above the list, Close enabled below it.
    let title = try #require(nativeHostedAccessibilityElement(in: view) { element in
        nativeHostedAccessibilityString(element, "accessibilityRole") == "AXStaticText"
            && ["accessibilityLabel", "accessibilityValue"].contains {
                nativeHostedAccessibilityString(element, $0) == "Notifications"
            }
    })
    let titleFrame = try #require(nativeHostedAccessibilityFrame(of: title, in: view))
    #expect(titleFrame.minY >= 0 && titleFrame.maxY <= top + 1, "the title is in the header band: \(titleFrame), list top \(top)")
    let close = try #require(nativeHostedAccessibilityElement("fst.notifications.close", in: view))
    #expect(isAccessibilityEnabled(close), "Close is enabled")
    let closeFrame = try #require(nativeHostedAccessibilityFrame(of: close, in: view))
    #expect(closeFrame.minY >= listBottom - 1 && closeFrame.maxY <= size.height, "Close is in the bottom bar: \(closeFrame), list bottom \(listBottom)")

    // The pinned heading is where it is drawn: in the band at the list's top.
    let heading = try #require(nativeHostedAccessibilityElement(in: view) {
        nativeHostedAccessibilityString($0, "accessibilityRole") == "AXHeading"
            && nativeHostedAccessibilityString($0, "accessibilityLabel") == pinned
    })
    let headingFrame = try #require(nativeHostedAccessibilityFrame(of: heading, in: view))
    #expect(headingFrame.minY >= top - 1 && headingFrame.maxY <= top + headerRow + 1,
            "the pinned title's frame is its pinned band: \(headingFrame), band \(top)…\(top + headerRow)")

    // Rendered: no row text under the header or beside the pinned title.
    let titleZone = titleFrame.insetBy(dx: -6, dy: -6)
    let headerBand = CGRect(x: 0, y: 1, width: size.width, height: top - 2)
    var headerBright = 0
    for y in stride(from: headerBand.minY, to: headerBand.maxY, by: 1) {
        let line = CGRect(x: 0, y: y, width: size.width, height: 1)
        let left = CGRect(x: 0, y: y, width: max(0, titleZone.minX), height: 1)
        let right = CGRect(x: titleZone.maxX, y: y, width: max(0, size.width - titleZone.maxX), height: 1)
        headerBright += titleZone.intersects(line)
            ? nativeHostedBrightSamples(in: left, of: image, hostSize: size, threshold: fadedTextThreshold)
                + nativeHostedBrightSamples(in: right, of: image, hostSize: size, threshold: fadedTextThreshold)
            : nativeHostedBrightSamples(in: line, of: image, hostSize: size, threshold: fadedTextThreshold)
    }
    #expect(headerBright == 0, "no row text under the sheet header")
    let band = CGRect(x: 90, y: top + 1, width: size.width - 110, height: headerRow - 2)
    #expect(nativeHostedBrightSamples(in: band, of: image, hostSize: size) == 0, "no row text beside the pinned title")

    // The modal fade yields: the pinned title is drawn whole under the header.
    if let restInk {
        let pinnedInk = nativeHostedBrightSamples(in: headingFrame, of: image, hostSize: size)
        #expect(restInk > 20, "Older has ink at rest: \(restInk)")
        #expect(abs(pinnedInk - restInk) <= max(4, restInk / 10),
                "pinned Older draws whole (\(pinnedInk)) like at rest (\(restInk))")
    }

    // R7 at the pinned title's edge, swept across one row pitch.
    var stripBright = 0
    for step in 0..<11 {
        let shot = try await scrollSheet(scroll, to: offset + Double(step) * 9, view: view, untilText: [pinned])
        let strip = CGRect(x: 20, y: top + headerRow + 1, width: size.width - 40, height: 9)
        stripBright += nativeHostedBrightSamples(in: strip, of: shot, hostSize: size, threshold: fadedTextThreshold)
        let header = CGRect(x: titleZone.maxX, y: 1, width: size.width - titleZone.maxX, height: top - 2)
        #expect(nativeHostedBrightSamples(in: header, of: shot, hostSize: size, threshold: fadedTextThreshold) == 0,
                "no row text under the header at offset \(offset + Double(step) * 9)")
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

/// Keyless fixture transport for every board with a floating pager (scroll-edge R9) and
/// no selected player. The two band boards, the publication and the one-song catalog
/// come from ``LongBandBoardsTransport``; on the same pinned publication it adds 60-row
/// boards served 25 rows a page for the solo Song Leaderboard
/// (`/api/leaderboard/{songId}/{instrument}?top=&offset=`), Full Rankings
/// (`/api/rankings/{instrument}?rankBy=&page=&pageSize=`) and one player's bands
/// (`/api/player/{accountId}/bands?group=&page=&pageSize=`), so page 1 of each scrolls
/// under its pager. GET only; rejects the privileged key, selected-profile headers, a
/// read pinned to another publication and any other route.
private actor ScrollEdgeBoardsTransport: HTTPTransport {
    static let playerId = "fade-player"
    static let total = 60
    private let bands = LongBandBoardsTransport()
    /// The publication the forwarded `/api/publication` read announced.
    private var publicationId: String?

    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        let parts = url.pathComponents
        let solo = parts.count == 5 && parts[1] == "api" && parts[2] == "leaderboard"
            && parts[3] == LongBandBoardsTransport.songId && parts[4] != "bands"
        let rankings = parts.count == 4 && parts[1] == "api" && parts[2] == "rankings" && parts[3] != "bands"
        let playerBands = parts.count == 5 && parts[1] == "api" && parts[2] == "player"
            && parts[3] == Self.playerId && parts[4] == "bands"
        guard solo || rankings || playerBands else {
            let result = try await bands.send(request)
            if url.path == "/api/publication",
               let body = try JSONSerialization.jsonObject(with: result.data) as? [String: Any],
               let id = body["publicationId"] as? Int {
                publicationId = String(id)
            }
            return result
        }
        guard let publicationId, request.value(forHTTPHeaderField: "X-FST-Publication-Id") == publicationId else {
            throw FestivalAPIError.invalidPublication
        }
        let query = Dictionary(
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") },
            uniquingKeysWith: { first, _ in first }
        )
        let body: [String: Any]
        if solo {
            let top = Int(query["top"] ?? "25") ?? 25
            let offset = Int(query["offset"] ?? "0") ?? 0
            let entries = Self.ranks(from: offset + 1, count: top).map { rank in
                [
                    "accountId": "fade-solo-\(rank)", "displayName": "Solo \(rank)",
                    "score": 99_000 - rank * 100, "rank": rank, "accuracy": 985_000,
                    "isFullCombo": false, "stars": 5, "season": 10,
                ] as [String: Any]
            }
            body = [
                "songId": LongBandBoardsTransport.songId, "instrument": parts[4], "count": entries.count,
                "totalEntries": Self.total, "localEntries": Self.total, "entries": entries,
            ]
        } else if rankings {
            let page = Int(query["page"] ?? "1") ?? 1
            let pageSize = Int(query["pageSize"] ?? "25") ?? 25
            let entries = Self.ranks(from: (page - 1) * pageSize + 1, count: pageSize).map { rank in
                [
                    "accountId": "fade-ranked-\(rank)", "displayName": "Ranked \(rank)",
                    "songsPlayed": 40, "totalChartedSongs": 50, "coverage": 0.8,
                    "rawSkillRating": 0.02, "adjustedSkillRating": 0.02, "adjustedSkillRank": rank,
                    "weightedRating": 0.03, "weightedRank": rank, "fcRate": 0.5, "fcRateRank": rank,
                    "totalScore": 90_000_000 - rank * 1000, "totalScoreRank": rank,
                    "maxScorePercent": 0.97, "maxScorePercentRank": rank, "avgAccuracy": 0.98,
                    "fullComboCount": 20, "avgStars": 4.8, "bestRank": 1, "avgRank": 2.5,
                ] as [String: Any]
            }
            body = [
                "instrument": parts[3], "rankBy": query["rankBy"] ?? "totalscore", "page": page,
                "pageSize": pageSize, "totalAccounts": Self.total, "entries": entries,
            ]
        } else {
            let page = Int(query["page"] ?? "1") ?? 1
            let pageSize = Int(query["pageSize"] ?? "25") ?? 25
            let entries = Self.ranks(from: (page - 1) * pageSize + 1, count: pageSize).map { rank in
                [
                    "bandId": "fade-player-band-\(rank)", "teamKey": "fade-player-team-\(rank)",
                    "bandType": "Band_Duets", "appearanceCount": 80 - rank,
                    "members": [
                        ["accountId": Self.playerId, "displayName": "Fade Player", "instruments": ["Solo_Guitar"]],
                        ["accountId": "fade-partner-\(rank)", "displayName": "Partner \(rank)", "instruments": ["Solo_Bass"]],
                    ],
                ] as [String: Any]
            }
            body = ["accountId": Self.playerId, "totalCount": Self.total, "entries": entries]
        }
        return HTTPResult(
            status: 200, data: try JSONSerialization.data(withJSONObject: body),
            headers: ["X-FST-Publication-Id": publicationId]
        )
    }

    /// Ranks of one page: up to `count` from `first`, never past the board's end.
    private static func ranks(from first: Int, count: Int) -> [Int] {
        Array(first..<min(first + count, total + 1))
    }
}

/// Every board with a floating pager (scroll-edge R9), each through its real screen and
/// with no selected player, so its rows run straight into the pager: the solo Song
/// Leaderboard, Full Rankings, Band Rankings, the band song leaderboard and Player Bands.
enum ScrollEdgeBoard: String, CaseIterable, CustomTestStringConvertible {
    case songLeaderboard, fullRankings, bandRankings, songBand, playerBands

    var testDescription: String { rawValue }

    /// Accessibility identifier of the row at `rank` (1-based, page 1).
    func rowId(_ rank: Int) -> String {
        switch self {
        case .songLeaderboard: "fst.song-leaderboard.row.fade-solo-\(rank)"
        case .fullRankings: "fst.rankings.row.fade-ranked-\(rank)"
        case .bandRankings: "fst.band-rankings.row.fade-team-\(rank)"
        case .songBand: "fst.song-band-leaderboard.row.fade-band-\(rank):\(rank)"
        case .playerBands: "fst.player-bands.row.fade-player-band-\(rank)"
        }
    }

    /// Identifier prefix of the board's pager controls.
    var pagerPrefix: String {
        switch self {
        case .songLeaderboard: "fst.song-leaderboard"
        case .fullRankings: "fst.full-rankings"
        case .bandRankings: "fst.band-rankings"
        case .songBand: "fst.song-band-leaderboard"
        case .playerBands: "fst.player-bands"
        }
    }

    /// Text the first page shows once loaded.
    var loadedText: String {
        switch self {
        case .songLeaderboard: "Solo 1"
        case .fullRankings: "Ranked 1"
        case .bandRankings: "Member 1A"
        case .songBand: "Band 1 Member A"
        case .playerBands: "Partner 1"
        }
    }

    /// Rows on page 1 (the fixture serves 25 of 60).
    var pageRows: Int { 25 }

    /// The board, opened on page 1.
    @MainActor
    func screen(_ session: FestivalSession) async throws -> AnyView {
        switch self {
        case .songLeaderboard:
            let song = try #require(try await session.catalog().catalog.songs.first {
                $0.songId == LongBandBoardsTransport.songId
            })
            return AnyView(SoloLeaderboardScreen(
                song: song, instrument: .lead, session: session, initialPage: 1, path: .constant([])
            ))
        case .fullRankings:
            return AnyView(FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore"))
        case .bandRankings:
            return AnyView(BandRankingsScreen(session: session, bandType: "Band_Duets"))
        case .songBand:
            let song = try #require(try await session.catalog().catalog.songs.first {
                $0.songId == LongBandBoardsTransport.songId
            })
            return AnyView(SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets"))
        case .playerBands:
            return AnyView(PlayerBandsScreen(
                session: session, accountId: ScrollEdgeBoardsTransport.playerId, displayName: "Fade Player"
            ))
        }
    }
}

/// Issues #462 and #308: the bottom chrome fade over every board with a floating pager
/// (scroll-edge R9) is decorative and keeps the pager usable. For each board, in every
/// transparency and contrast mode, mid-list and at the end of page 1:
///
/// - Rows are read in rank order, all before the pager that floats over them.
/// - The pager's four arrows and its page badge keep their names (HIG VoiceOver); on
///   page 1 First and Previous are disabled and Next and Last enabled; the badge is the
///   adjustable "Page".
/// - Rows and arrows are at least 44×44 pt and the badge 44 pt tall (HIG
///   Accessibility), and the pager lies wholly below the fade's edge, never under
///   the fade. The edge is the chrome's top: every board pins its pager as the scroll
///   view's bottom safe-area inset, so the chrome's top is the scroll frame's bottom
///   minus its bottom content inset, and the pager's first arrow starts within its top
///   padding of it (nothing else, such as a player footer, sits in between).
/// - At the end of the page the last row's frame rests above the chrome, so focus on it
///   lands on fully drawn text.
/// - The fade adds no element and nothing is unnamed.
/// - Rendered: bright row text in a 9 pt strip 1–10 pt above the chrome's top, summed
///   over mid-list offsets 9 pt apart across one row pitch (so every line of row text
///   crosses the strip), is 0 in the standard mode (the canonical `bottomChromeFade`
///   ramp leaves it at most ~25% opaque there) and above 0 in every R7 mode (a hard
///   edge), while rows well above the fade are drawn. A board that lost the canonical
///   fade, or its R7 hard edge, fails here.
@MainActor
@Test(.serialized, arguments: ScrollEdgeBoard.allCases, BottomChromeFadeMode.allCases)
func boardBottomChromeFadeKeepsRowsAndPagerReadable(board: ScrollEdgeBoard, mode: BottomChromeFadeMode) async throws {
    let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: ScrollEdgeBoardsTransport())
    let session = FestivalSession(factory: { client })
    #expect(session.selectedPlayer == nil)
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
    let rowIDs = (1...board.pageRows).map(board.rowId)
    let pagerIDs = ["page-first", "page-previous", "page-info", "page-next", "page-last"].map { "\(board.pagerPrefix).\($0)" }

    // The fade's edge: the pager is the scroll view's bottom inset and starts at its top.
    #expect(scroll.contentInsets.bottom > 30, "the pinned pager is the scroll view's bottom inset")
    let chromeTop = scrollFrame.maxY - scroll.contentInsets.bottom
    let firstArrow = try #require(nativeHostedAccessibilityFrame(pagerIDs[0], in: host))
    #expect(firstArrow.minY >= chromeTop - 0.5 && firstArrow.minY <= chromeTop + 24,
            "the chrome's top is the pager's: \(firstArrow) vs \(chromeTop)")

    // Row pitch and row targets at rest.
    let firstRow = try #require(nativeHostedAccessibilityFrame(rowIDs[0], in: host))
    let secondRow = try #require(nativeHostedAccessibilityFrame(rowIDs[1], in: host))
    let pitch = secondRow.minY - firstRow.minY
    #expect(pitch > 44, "rows stack down the page: \(firstRow), \(secondRow)")
    #expect(firstRow.height >= 44 && firstRow.width >= 44, "a row is at least a 44×44 pt target: \(firstRow)")

    // Rendered: the canonical fade, or the R7 hard edge, just above the chrome.
    let near = CGRect(x: 0, y: chromeTop - 10, width: size.width, height: 9)
    let far = CGRect(x: 0, y: chromeTop - 160, width: size.width, height: 120)
    var nearBright = 0
    for step in 0..<max(6, Int((pitch / 9).rounded(.up))) {
        let image = try await scrollHosted(scroll, to: 300 + CGFloat(step) * 9, host: host)
        if step == 0 {
            _ = try nativeHostedPNG(
                image, filename: "a11y-\(board.rawValue)-mid-\(mode.rawValue).png",
                environment: "FST_LEADERBOARDS_RENDER_OUT"
            )
        }
        #expect(nativeHostedBrightSamples(in: far, of: image, hostSize: size, threshold: fadedTextThreshold) > 0,
                "rows above the fade are drawn")
        nearBright += nativeHostedBrightSamples(in: near, of: image, hostSize: size, threshold: fadedTextThreshold)
    }
    if mode.hardEdge {
        #expect(nearBright > 0, "\(mode.rawValue) draws rows whole up to the pager (hard edge)")
    } else {
        #expect(nearBright == 0, "row text fades out above the pager")
    }

    let document = try #require(scroll.documentView)
    let end = document.frame.height + scroll.contentInsets.bottom - scroll.contentView.bounds.height
        + scroll.contentInsets.top
    for (place, offset) in [("mid", CGFloat(300)), ("end", end)] {
        try await scrollHosted(scroll, to: offset, host: host)
        let nodes = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "\(board.rawValue)-\(place)-\(mode.rawValue)")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(place): \(macAccessibilityFindings(nodes))")
        let elements = readableElements(nodes)
        #expect(!elements.contains { $0.role == "AXImage" && $0.spokenName.isEmpty },
                "\(place): no unnamed image (the fade is decorative)")

        // Rows in rank order, then the pager. A row that contains its texts (Song
        // Leaderboard) is an unnamed group VoiceOver enters, so positions come from the
        // whole walk in reading order, each row and control at its first appearance.
        func position(_ id: String) -> Int? { nodes.firstIndex { $0.identifier == id } }
        let rowPositions = rowIDs.compactMap(position)
        #expect(!rowPositions.isEmpty, "\(place): rows are readable")
        #expect(rowPositions == rowPositions.sorted(), "\(place): rows read in rank order: \(rowPositions)")
        let pagerPositions = pagerIDs.map(position)
        #expect(pagerPositions.allSatisfy { $0 != nil }, "\(place): pager controls are readable: \(pagerPositions)")
        let pager = pagerPositions.compactMap { $0 }
        #expect(pager == pager.sorted(), "\(place): pager reads First, Previous, Page, Next, Last")
        if let firstPager = pager.first {
            let lateRows = rowIDs.filter { id in nodes.indices.contains { nodes[$0].identifier == id && $0 > firstPager } }
            #expect(lateRows.isEmpty, "\(place): rows are read before the pager over them: \(lateRows)")
        }

        // Names, state and targets of the pager.
        // Band Rankings' glass pager titles its arrows "First Page"; the others
        // "First page". VoiceOver speaks both alike.
        let names = pagerIDs.compactMap { id in nodes.first { $0.identifier == id }?.spokenName.lowercased() }
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
    let last = try #require(nativeHostedAccessibilityFrame(board.rowId(board.pageRows), in: host))
    #expect(last.maxY <= chromeTop + 0.5, "the last row's frame ends above the chrome: \(last) vs \(chromeTop)")
}
#endif
