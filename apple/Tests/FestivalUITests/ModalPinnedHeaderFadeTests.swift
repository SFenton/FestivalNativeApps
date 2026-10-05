import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - Pinned header row fade (issue #301)

/// Rows must have faded out by the bottom of the pinned header, which sits on the pin line.
@Test func pinnedHeaderEdgeIsThePinLinePlusTheHeader() {
    #expect(ModalPinnedHeaderFade.edge(pinLine: 64, headerHeight: 36) == 100)
    #expect(ModalPinnedHeaderFade.edge(pinLine: 64, headerHeight: 0) == 64)
    #expect(ModalPinnedHeaderFade.edge(pinLine: -4, headerHeight: 36) == 36)
    #expect(ModalPinnedHeaderFade.edge(pinLine: .nan, headerHeight: .infinity) == 0)
}

/// Nothing is dimmed at rest or pulled down; the fade grows 1:1 with scrolling up to its
/// full height, and the accessibility hard edge (0) never fades.
@Test func pinnedHeaderFadeDepthFollowsTheFirstPointsOfScrolling() {
    #expect(ModalPinnedHeaderFade.depth(scrollOffset: 0, fade: 28) == 0)
    #expect(ModalPinnedHeaderFade.depth(scrollOffset: -20, fade: 28) == 0)
    #expect(ModalPinnedHeaderFade.depth(scrollOffset: 10, fade: 28) == 10)
    #expect(ModalPinnedHeaderFade.depth(scrollOffset: 500, fade: 28) == 28)
    #expect(ModalPinnedHeaderFade.depth(scrollOffset: 500, fade: 0) == 0)
    #expect(ModalPinnedHeaderFade.depth(scrollOffset: .nan, fade: 28) == 0)
}

/// A row clear of the edge and its fade needs no mask; a row reaching into the fade or
/// past the edge is cut where the edge falls inside it.
@Test func pinnedHeaderRowCutStartsAtTheEdge() {
    // Well below the fade: no mask.
    #expect(ModalPinnedHeaderFade.cut(rowTop: 200, edge: 100, depth: 28) == nil)
    // At rest, first row flush under the header: nothing to hide or fade.
    #expect(ModalPinnedHeaderFade.cut(rowTop: 100, edge: 100, depth: 0) == nil)
    // Just inside the fade (edge 10 pt above the row).
    #expect(ModalPinnedHeaderFade.cut(rowTop: 110, edge: 100, depth: 28) == -10)
    // Sliding under the header: its top 30 pt are hidden.
    #expect(ModalPinnedHeaderFade.cut(rowTop: 70, edge: 100, depth: 28) == 30)
    // Hard edge (Reduce Transparency): cut once the row passes the edge.
    #expect(ModalPinnedHeaderFade.cut(rowTop: 90, edge: 100, depth: 0) == 10)
    #expect(ModalPinnedHeaderFade.cut(rowTop: 101, edge: 100, depth: 0) == nil)
    #expect(ModalPinnedHeaderFade.cut(rowTop: .nan, edge: 100, depth: 28) == nil)
}

/// Header height counts only while the List shows headers, and a measurement made while
/// they were hidden still applies once they return.
@MainActor @Test func pinnedHeaderStateDropsTheHeaderWhenHidden() {
    let state = ModalPinnedHeaderFadeState()
    state.modalPinnedHeaderTestSet(pinLine: 64, headerHeight: 36, showsHeaders: true)
    #expect(state.edge == 100)
    state.modalPinnedHeaderTestSet(pinLine: 64, headerHeight: nil, showsHeaders: false)
    #expect(state.edge == 64)
    state.modalPinnedHeaderTestSet(pinLine: 64, headerHeight: nil, showsHeaders: true)
    #expect(state.edge == 100)
}

/// The pinned band is the header's whole cell: the List centres the content, so the
/// padding above it (read at rest) is added again below it; it needs a header.
@Test func pinnedHeaderEdgeIncludesTheCellPaddingAroundTheContent() {
    // macOS 26: 14 pt title in a 28 pt cell.
    #expect(ModalPinnedHeaderFade.edge(pinLine: 52, headerHeight: 14, headerInset: 7) == 80)
    #expect(ModalPinnedHeaderFade.edge(pinLine: 52, headerHeight: 0, headerInset: 7) == 52)
    #expect(ModalPinnedHeaderFade.edge(pinLine: 52, headerHeight: 14, headerInset: 400) == 114)
    #expect(ModalPinnedHeaderFade.edge(pinLine: 52, headerHeight: 14, headerInset: .nan) == 66)
}

/// The first header's layout: the padding is the space between its content and the
/// first row; any space left above the padded band is the gap. Unbelievable readings are
/// rejected.
@Test func pinnedHeaderLayoutReadsTheRestingFirstHeader() {
    typealias Layout = ModalPinnedHeaderFade.HeaderLayout
    // iOS 26: 18 pt title, 10 pt padding, 22 pt gap above the band.
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: 102, headerHeight: 18, firstRowTop: 130, pinLine: 70)
        == Layout(inset: 10, gap: 22))
    // macOS 26: 14 pt title centred in a 28 pt band on the pin line.
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: 7, headerHeight: 14, firstRowTop: 28, pinLine: 0)
        == Layout(inset: 7, gap: 0))
    // No first row yet: the band is assumed to start on the pin line.
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: 62, headerHeight: 14, firstRowTop: nil, pinLine: 52)
        == Layout(inset: 10, gap: 0))
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: 51.8, headerHeight: 14, firstRowTop: nil, pinLine: 52)
        == Layout(inset: 0, gap: 0))
    // Without a row, a header far below the pin line is not resting padding.
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: 84, headerHeight: 14, firstRowTop: nil, pinLine: 52) == nil)
    // A pinned or pushed header (above the pin line) is rejected.
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: 40, headerHeight: 14, firstRowTop: 64, pinLine: 52) == nil)
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: 62, headerHeight: 14, firstRowTop: 400, pinLine: 52) == nil)
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: .infinity, headerHeight: 14, firstRowTop: nil, pinLine: 52) == nil)
    #expect(ModalPinnedHeaderFade.headerLayout(headerTop: 62, headerHeight: 0, firstRowTop: nil, pinLine: 52) == nil)
}

/// The first header is drawn on its pinned position while the gap scrolls away, then
/// moves with the List once pinned or pushed, and with content pulled down past the top.
@Test func pinnedHeaderLiftHoldsTheFirstHeaderOnThePinLine() {
    let layout = ModalPinnedHeaderFade.HeaderLayout(inset: 10, gap: 22)
    // At rest: the band (content top minus padding) sits 22 pt below the pin line.
    #expect(ModalPinnedHeaderFade.lift(contentTop: 102, pinLine: 70, layout: layout) == 22)
    // Scrolled 15 pt into the gap.
    #expect(ModalPinnedHeaderFade.lift(contentTop: 87, pinLine: 70, layout: layout) == 7)
    // Pinned, or pushed up by the next header.
    #expect(ModalPinnedHeaderFade.lift(contentTop: 80, pinLine: 70, layout: layout) == 0)
    #expect(ModalPinnedHeaderFade.lift(contentTop: 40, pinLine: 70, layout: layout) == 0)
    // Pulled down: never more than the gap.
    #expect(ModalPinnedHeaderFade.lift(contentTop: 160, pinLine: 70, layout: layout) == 22)
    #expect(ModalPinnedHeaderFade.lift(contentTop: .nan, pinLine: 70, layout: layout) == 0)
    #expect(ModalPinnedHeaderFade.lift(
        contentTop: 102, pinLine: 70, layout: ModalPinnedHeaderFade.HeaderLayout(inset: 10, gap: 0)
    ) == 0)
}

/// The state reads the layout from the scroll view's top (the List's frame, which starts
/// at the pin line, minus the inset), only while the List rests at its top, so a pinned or pushed first header never changes it.
@MainActor @Test func pinnedHeaderStateReadsTheLayoutOnlyAtRest() {
    let state = ModalPinnedHeaderFadeState()
    state.modalPinnedHeaderTestSet(
        pinLine: 70, headerHeight: 18, showsHeaders: true, listTop: 132,
        scrollOffset: 0, firstHeaderTop: 164, firstRowTop: 192
    )
    #expect(state.headerLayout == ModalPinnedHeaderFade.HeaderLayout(inset: 10, gap: 22))
    #expect(state.edge == 108)
    // Scrolled: the pinned (or pushed) header is ignored.
    state.modalPinnedHeaderTestSet(
        pinLine: 70, headerHeight: nil, showsHeaders: true, scrollOffset: 300, firstHeaderTop: 100, firstRowTop: -200
    )
    #expect(state.headerLayout.gap == 22)
    // Back at rest with larger Dynamic Type.
    state.modalPinnedHeaderTestSet(
        pinLine: 70, headerHeight: 24, showsHeaders: true, scrollOffset: 0, firstHeaderTop: 164, firstRowTop: 198
    )
    #expect(state.edge == 114)
}

/// Without a scroll offset (iOS 17 / macOS 14) the readings made as the sheet opens at
/// its top are kept: the first, then the first with the first row.
@MainActor @Test func pinnedHeaderStateKeepsTheOpeningLayoutWithoutAScrollOffset() {
    let state = ModalPinnedHeaderFadeState()
    state.modalPinnedHeaderTestSet(pinLine: 52, headerHeight: 14, showsHeaders: true, listTop: 52, firstHeaderTop: 59)
    #expect(state.headerLayout == ModalPinnedHeaderFade.HeaderLayout(inset: 7, gap: 0))
    state.modalPinnedHeaderTestSet(pinLine: 52, headerHeight: nil, showsHeaders: true, firstHeaderTop: 53)
    #expect(state.headerLayout.inset == 7)
    state.modalPinnedHeaderTestSet(pinLine: 52, headerHeight: nil, showsHeaders: true, firstHeaderTop: 81, firstRowTop: 105)
    #expect(state.headerLayout == ModalPinnedHeaderFade.HeaderLayout(inset: 10, gap: 19))
    state.modalPinnedHeaderTestSet(pinLine: 52, headerHeight: nil, showsHeaders: true, firstHeaderTop: 53, firstRowTop: 77)
    #expect(state.headerLayout.gap == 19)
}
