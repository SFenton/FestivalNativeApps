import CoreGraphics
import FestivalCore
import Testing
@testable import FestivalUI

// MARK: - Shared ramp (issues #10, #301, #308)

/// One top ramp on Apple platforms: the web's `useScrollMask` 40 px, shared by pinned
/// section titles (Songs and sheet lists) and the sheet header fade.
@Test func pinnedHeaderRampIsTheWebTopMask() {
    #expect(PinnedHeaderEdgeFade.height == 40)
    #expect(PinnedHeaderEdgeFade.height == CGFloat(FestivalCore.ScrollEdgeFade.topDistance))
    #expect(ModalTopEdgeFade.rampHeight == PinnedHeaderEdgeFade.height)
    #expect(PinnedHeaderEdgeFade.height(hardEdge: false) == 40)
}

/// Reduce Transparency and Increase Contrast (system or in-app) give a hard edge.
@Test(arguments: [(true, false), (false, true), (true, true)])
func pinnedHeaderAccessibilitySettingsKeepAHardEdge(reduceTransparency: Bool, increaseContrast: Bool) {
    let hard = ScrollEdgeHardEdge.resolve(
        reduceTransparency: reduceTransparency, increaseContrast: increaseContrast
    )
    #expect(hard)
    #expect(PinnedHeaderEdgeFade.height(hardEdge: hard) == 0)
}

@Test func pinnedHeaderFadesWithoutAccessibilitySettings() {
    #expect(!ScrollEdgeHardEdge.resolve(reduceTransparency: false, increaseContrast: false))
}

/// Rows are clear at the title's edge and opaque after the ramp, rising linearly.
@Test func pinnedHeaderOpacityIsLinear() {
    #expect(PinnedHeaderEdgeFade.opacity(at: 0) == 0)
    #expect(PinnedHeaderEdgeFade.opacity(at: 1) == 1)
    #expect(PinnedHeaderEdgeFade.opacity(at: -3) == 0)
    #expect(PinnedHeaderEdgeFade.opacity(at: 4) == 1)
    #expect(PinnedHeaderEdgeFade.opacity(at: 0.25) == 0.25)
    #expect(PinnedHeaderEdgeFade.opacity(at: 0.5) == 0.5)
    #expect(PinnedHeaderEdgeFade.opacity(at: .nan) == 0)
}

@Test func pinnedHeaderGradientSpansTheRampFromClearToOpaque() {
    let stops = PinnedHeaderEdgeFade.gradientStops
    #expect(stops.map(\.location) == [0, 1])
}

// MARK: - Pinned header row fade (issue #301)

/// Rows must have faded out by the bottom of the pinned header, which sits on the pin line.
@Test func pinnedHeaderEdgeIsThePinLinePlusTheHeader() {
    #expect(PinnedHeaderEdgeFade.edge(pinLine: 64, headerHeight: 36) == 100)
    #expect(PinnedHeaderEdgeFade.edge(pinLine: 64, headerHeight: 0) == 64)
    #expect(PinnedHeaderEdgeFade.edge(pinLine: -4, headerHeight: 36) == 36)
    #expect(PinnedHeaderEdgeFade.edge(pinLine: .nan, headerHeight: .infinity) == 0)
}

/// Nothing is dimmed at rest or pulled down; the fade grows 1:1 with scrolling up to its
/// full height, and the accessibility hard edge (0) never fades.
@Test func pinnedHeaderFadeDepthFollowsTheFirstPointsOfScrolling() {
    let fade = PinnedHeaderEdgeFade.height
    #expect(PinnedHeaderEdgeFade.depth(scrollOffset: 0, fade: fade) == 0)
    #expect(PinnedHeaderEdgeFade.depth(scrollOffset: -20, fade: fade) == 0)
    #expect(PinnedHeaderEdgeFade.depth(scrollOffset: 10, fade: fade) == 10)
    #expect(PinnedHeaderEdgeFade.depth(scrollOffset: 39, fade: fade) == 39)
    #expect(PinnedHeaderEdgeFade.depth(scrollOffset: 500, fade: fade) == 40)
    #expect(PinnedHeaderEdgeFade.depth(scrollOffset: 500, fade: 0) == 0)
    #expect(PinnedHeaderEdgeFade.depth(scrollOffset: .nan, fade: fade) == 0)
}

/// A row clear of the edge and its fade needs no mask; a row reaching into the fade or
/// past the edge is cut where the edge falls inside it.
@Test func pinnedHeaderRowCutStartsAtTheEdge() {
    // Well below the fade: no mask.
    #expect(PinnedHeaderEdgeFade.cut(rowTop: 200, edge: 100, depth: 28) == nil)
    // At rest, first row flush under the header: nothing to hide or fade.
    #expect(PinnedHeaderEdgeFade.cut(rowTop: 100, edge: 100, depth: 0) == nil)
    // Just inside the fade (edge 10 pt above the row).
    #expect(PinnedHeaderEdgeFade.cut(rowTop: 110, edge: 100, depth: 28) == -10)
    // Sliding under the header: its top 30 pt are hidden.
    #expect(PinnedHeaderEdgeFade.cut(rowTop: 70, edge: 100, depth: 28) == 30)
    // Hard edge (Reduce Transparency): cut once the row passes the edge.
    #expect(PinnedHeaderEdgeFade.cut(rowTop: 90, edge: 100, depth: 0) == 10)
    #expect(PinnedHeaderEdgeFade.cut(rowTop: 101, edge: 100, depth: 0) == nil)
    #expect(PinnedHeaderEdgeFade.cut(rowTop: .nan, edge: 100, depth: 28) == nil)
}

/// Issue #322: the row's own separator runs between its separator guides in its
/// background's coordinates (on to the row edge on macOS), left to right in either
/// layout direction, and is 1 pt
/// thick like the system List separator.
@Test func pinnedHeaderRowSeparatorSpansTheSeparatorGuides() {
    // iPhone: text at 90 pt, content trailing at 386 pt, cell from 0.
    typealias Fade = PinnedHeaderEdgeFade
    let phone = CGRect(x: 0, y: 300, width: 402, height: 72)
    #expect(Fade.separatorSpan(leading: 90, trailing: 386, background: phone) == 90...386)
    // A cell that starts inside the window (sheet on iPad / Mac).
    #expect(Fade.separatorSpan(leading: 190, trailing: 486, background: phone.offsetBy(dx: 100, dy: 0)) == 90...386)
    // Right to left: leading is the right end.
    #expect(Fade.separatorSpan(leading: 312, trailing: 16, background: phone) == 16...312)
    // macOS runs it on to the row's trailing edge: the right edge, or the left one in RTL.
    let mac = CGRect(x: 0, y: 300, width: 402.5, height: 93)
    #expect(Fade.separatorSpan(leading: 82, trailing: 393.5, background: mac, toRowEdge: true) == 82...402.5)
    #expect(Fade.separatorSpan(leading: 320.5, trailing: 9, background: mac, toRowEdge: true, rightToLeft: true)
        == 0...320.5)
    // Empty or unreadable spans draw nothing.
    #expect(Fade.separatorSpan(leading: 90, trailing: 90.5, background: phone) == nil)
    #expect(Fade.separatorSpan(leading: .nan, trailing: 386, background: phone) == nil)
    #expect(Fade.separatorSpan(leading: 90, trailing: .infinity, background: phone) == nil)
    #expect(Fade.separatorSpan(leading: 90, trailing: 386, background: CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 1)) == nil)
    #if os(macOS)
    #expect(Fade.separatorRunsToRowEdge)
    #else
    #expect(!Fade.separatorRunsToRowEdge)
    #endif
    #expect(PinnedHeaderEdgeFade.separatorThickness == 1)
}

/// Header height counts only while the List shows headers, and a measurement made while
/// they were hidden still applies once they return.
@MainActor @Test func pinnedHeaderStateDropsTheHeaderWhenHidden() {
    let state = PinnedHeaderEdgeFadeState()
    state.testSet(pinLine: 64, headerHeight: 36, showsHeaders: true)
    #expect(state.edge == 100)
    state.testSet(pinLine: 64, headerHeight: nil, showsHeaders: false)
    #expect(state.edge == 64)
    state.testSet(pinLine: 64, headerHeight: nil, showsHeaders: true)
    #expect(state.edge == 100)
}

/// The pinned band is the header's whole cell: the List centres the content, so the
/// padding above it (read at rest) is added again below it; it needs a header.
@Test func pinnedHeaderEdgeIncludesTheCellPaddingAroundTheContent() {
    // macOS 26: 14 pt title in a 28 pt cell.
    #expect(PinnedHeaderEdgeFade.edge(pinLine: 52, headerHeight: 14, headerInset: 7) == 80)
    #expect(PinnedHeaderEdgeFade.edge(pinLine: 52, headerHeight: 0, headerInset: 7) == 52)
    #expect(PinnedHeaderEdgeFade.edge(pinLine: 52, headerHeight: 14, headerInset: 400) == 114)
    #expect(PinnedHeaderEdgeFade.edge(pinLine: 52, headerHeight: 14, headerInset: .nan) == 66)
}

/// The first header's layout: the padding is the space between its content and the
/// first row; any space left above the padded band is the gap. Unbelievable readings are
/// rejected.
@Test func pinnedHeaderLayoutReadsTheRestingFirstHeader() {
    typealias Layout = PinnedHeaderEdgeFade.HeaderLayout
    // iOS 26: 18 pt title, 10 pt padding, 22 pt gap above the band.
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: 102, headerHeight: 18, firstRowTop: 130, pinLine: 70)
        == Layout(inset: 10, gap: 22))
    // macOS 26: 14 pt title centred in a 28 pt band on the pin line.
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: 7, headerHeight: 14, firstRowTop: 28, pinLine: 0)
        == Layout(inset: 7, gap: 0))
    // No first row yet: the band is assumed to start on the pin line.
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: 62, headerHeight: 14, firstRowTop: nil, pinLine: 52)
        == Layout(inset: 10, gap: 0))
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: 51.8, headerHeight: 14, firstRowTop: nil, pinLine: 52)
        == Layout(inset: 0, gap: 0))
    // Without a row, a header far below the pin line is not resting padding.
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: 84, headerHeight: 14, firstRowTop: nil, pinLine: 52) == nil)
    // A pinned or pushed header (above the pin line) is rejected.
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: 40, headerHeight: 14, firstRowTop: 64, pinLine: 52) == nil)
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: 62, headerHeight: 14, firstRowTop: 400, pinLine: 52) == nil)
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: .infinity, headerHeight: 14, firstRowTop: nil, pinLine: 52) == nil)
    #expect(PinnedHeaderEdgeFade.headerLayout(headerTop: 62, headerHeight: 0, firstRowTop: nil, pinLine: 52) == nil)
}

/// The first header is drawn on its pinned position while the gap scrolls away, then
/// moves with the List once pinned or pushed, and with content pulled down past the top.
@Test func pinnedHeaderLiftHoldsTheFirstHeaderOnThePinLine() {
    let layout = PinnedHeaderEdgeFade.HeaderLayout(inset: 10, gap: 22)
    // At rest: the band (content top minus padding) sits 22 pt below the pin line.
    #expect(PinnedHeaderEdgeFade.lift(contentTop: 102, pinLine: 70, layout: layout) == 22)
    // Scrolled 15 pt into the gap.
    #expect(PinnedHeaderEdgeFade.lift(contentTop: 87, pinLine: 70, layout: layout) == 7)
    // Pinned, or pushed up by the next header.
    #expect(PinnedHeaderEdgeFade.lift(contentTop: 80, pinLine: 70, layout: layout) == 0)
    #expect(PinnedHeaderEdgeFade.lift(contentTop: 40, pinLine: 70, layout: layout) == 0)
    // Pulled down: never more than the gap.
    #expect(PinnedHeaderEdgeFade.lift(contentTop: 160, pinLine: 70, layout: layout) == 22)
    #expect(PinnedHeaderEdgeFade.lift(contentTop: .nan, pinLine: 70, layout: layout) == 0)
    #expect(PinnedHeaderEdgeFade.lift(
        contentTop: 102, pinLine: 70, layout: PinnedHeaderEdgeFade.HeaderLayout(inset: 10, gap: 0)
    ) == 0)
}

/// The state reads the layout from the scroll view's top (the List's frame, which starts
/// at the pin line, minus the inset), only while the List rests at its top, so a pinned or pushed first header never changes it.
@MainActor @Test func pinnedHeaderStateReadsTheLayoutOnlyAtRest() {
    let state = PinnedHeaderEdgeFadeState()
    state.testSet(
        pinLine: 70, headerHeight: 18, showsHeaders: true, listTop: 132,
        scrollOffset: 0, firstHeaderTop: 164, firstRowTop: 192
    )
    #expect(state.headerLayout == PinnedHeaderEdgeFade.HeaderLayout(inset: 10, gap: 22))
    #expect(state.edge == 108)
    // Scrolled: the pinned (or pushed) header is ignored.
    state.testSet(
        pinLine: 70, headerHeight: nil, showsHeaders: true, scrollOffset: 300, firstHeaderTop: 100, firstRowTop: -200
    )
    #expect(state.headerLayout.gap == 22)
    // Back at rest with larger Dynamic Type.
    state.testSet(
        pinLine: 70, headerHeight: 24, showsHeaders: true, scrollOffset: 0, firstHeaderTop: 164, firstRowTop: 198
    )
    #expect(state.edge == 114)
}

/// Without a scroll offset (iOS 17 / macOS 14) the readings made as the sheet opens at
/// its top are kept: the first, then the first with the first row.
@MainActor @Test func pinnedHeaderStateKeepsTheOpeningLayoutWithoutAScrollOffset() {
    let state = PinnedHeaderEdgeFadeState()
    state.testSet(pinLine: 52, headerHeight: 14, showsHeaders: true, listTop: 52, firstHeaderTop: 59)
    #expect(state.headerLayout == PinnedHeaderEdgeFade.HeaderLayout(inset: 7, gap: 0))
    state.testSet(pinLine: 52, headerHeight: nil, showsHeaders: true, firstHeaderTop: 53)
    #expect(state.headerLayout.inset == 7)
    state.testSet(pinLine: 52, headerHeight: nil, showsHeaders: true, firstHeaderTop: 81, firstRowTop: 105)
    #expect(state.headerLayout == PinnedHeaderEdgeFade.HeaderLayout(inset: 10, gap: 19))
    state.testSet(pinLine: 52, headerHeight: nil, showsHeaders: true, firstHeaderTop: 53, firstRowTop: 77)
    #expect(state.headerLayout.gap == 19)
}

// MARK: - Scroll readings on every system (issue #308 review)

/// The state grows the fade from its own scroll readings, whichever path supplies them,
/// and a hard edge (fade 0) drops it at once, then restores it from the last offset.
@MainActor @Test func pinnedHeaderStateDepthFollowsScrollReadings() {
    let state = PinnedHeaderEdgeFadeState(legacyScrollTracking: true)
    #expect(state.legacyScrollTracking)
    state.testSet(pinLine: 52, headerHeight: 14, showsHeaders: true, fade: PinnedHeaderEdgeFade.height)
    // No reading yet: nothing is dimmed.
    #expect(state.depth == 0)
    state.testSet(pinLine: 52, headerHeight: nil, showsHeaders: true, scrollOffset: 12)
    #expect(state.depth == 12)
    state.testSet(pinLine: 52, headerHeight: nil, showsHeaders: true, scrollOffset: 300)
    #expect(state.depth == 40)
    state.testSet(pinLine: 52, headerHeight: nil, showsHeaders: true, fade: 0)
    #expect(state.depth == 0)
    state.testSet(pinLine: 52, headerHeight: nil, showsHeaders: true, fade: PinnedHeaderEdgeFade.height)
    #expect(state.depth == 40)
    state.testSet(pinLine: 52, headerHeight: nil, showsHeaders: true, scrollOffset: -30)
    #expect(state.depth == 0)
}

/// UIKit readings match `ScrollGeometry`: offset 0 at the resting top (content offset
/// `-inset`), negative while pulled down; overflow 0 at the end of the content.
@Test func platformScrollReadingFromAUIScrollViewOffset() {
    func reading(_ y: CGFloat) -> PlatformScrollObserver.Reading {
        PlatformScrollObserver.reading(
            contentOffsetY: y, topInset: 64, contentHeight: 2000, containerHeight: 800, bottomInset: 90
        )
    }
    #expect(reading(-64) == .init(inset: 64, offset: 0, overflow: 1354))
    #expect(reading(-24) == .init(inset: 64, offset: 40, overflow: 1314))
    #expect(reading(-90) == .init(inset: 64, offset: -26, overflow: 1380))
    // At the end the content's bottom meets the bottom chrome (the bottom inset).
    #expect(reading(1290).overflow == 0)
    #expect(reading(1300).overflow == -10)
}

/// AppKit readings match `ScrollGeometry` for flipped (table) and unflipped documents.
@Test func platformScrollReadingFromAClipView() {
    // Flipped: the visible rect starts `inset` above the document's top at rest.
    #expect(PlatformScrollObserver.reading(
        visible: CGRect(x: 0, y: -52, width: 400, height: 600), documentHeight: 2000,
        topInset: 52, bottomInset: 48, flipped: true
    ) == .init(inset: 52, offset: 0, overflow: 1500))
    #expect(PlatformScrollObserver.reading(
        visible: CGRect(x: 0, y: 100, width: 400, height: 600), documentHeight: 2000,
        topInset: 52, flipped: true
    ) == .init(inset: 52, offset: 152, overflow: 1300))
    #expect(PlatformScrollObserver.reading(
        visible: CGRect(x: 0, y: 1448, width: 400, height: 600), documentHeight: 2000,
        topInset: 52, bottomInset: 48, flipped: true
    ).overflow == 0)
    // Unflipped: the document's top is its maxY.
    #expect(PlatformScrollObserver.reading(
        visible: CGRect(x: 0, y: 1452, width: 400, height: 600), documentHeight: 2000,
        topInset: 52, flipped: false
    ) == .init(inset: 52, offset: 0, overflow: 1452))
    #expect(PlatformScrollObserver.reading(
        visible: CGRect(x: 0, y: 1412, width: 400, height: 600), documentHeight: 2000,
        topInset: 52, flipped: false
    ) == .init(inset: 52, offset: 40, overflow: 1412))
}

/// From outside some content, the scroll view covering most of it is its scroll view: not
/// a small nested scroller, not one beside it, and nothing when none covers half of it.
@Test func enclosedScrollViewSearchPicksTheCoveringScrollView() {
    let content = CGRect(x: 0, y: 100, width: 400, height: 600)
    // The List reaches up under the header; a chip row inside it; a page beside it.
    let list = CGRect(x: 0, y: 40, width: 400, height: 660)
    let chips = CGRect(x: 0, y: 140, width: 400, height: 44)
    let beside = CGRect(x: 400, y: 0, width: 400, height: 800)
    #expect(EnclosedScrollViewSearch.best(target: content, candidates: [chips, beside, list]) == 2)
    #expect(EnclosedScrollViewSearch.best(target: content, candidates: [chips, beside]) == nil)
    // Equal cover: the outermost (first) wins.
    #expect(EnclosedScrollViewSearch.best(target: content, candidates: [list, list]) == 0)
    #expect(EnclosedScrollViewSearch.best(target: .zero, candidates: [list]) == nil)
}
