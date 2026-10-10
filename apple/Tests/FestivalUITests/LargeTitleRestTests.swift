import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - LargeTitleRest (issue #560)

/// iPhone 17 Pro on iOS 27: the expanded title's top inset is 222 pt, the collapsed
/// bar's 170 pt, so the collapse band is 52 pt.
private let expanded: CGFloat = 222
private let collapsed: CGFloat = 170

/// A decision that has seen the List at its top with the title open.
private func openedAtTop(width: CGFloat = 402) -> LargeTitleRest {
    var rest = LargeTitleRest()
    rest.update(offsetY: -expanded, topInset: expanded, containerWidth: width)
    return rest
}

/// A decision that has also seen the title collapse.
private func collapsedOnce() -> LargeTitleRest {
    var rest = openedAtTop()
    rest.update(offsetY: -150, topInset: expanded, containerWidth: 402)
    rest.update(offsetY: 400, topInset: collapsed, containerWidth: 402)
    return rest
}

/// Before the title has collapsed once at this width the band is unknown, so nothing
/// moves: a List the bar does not track keeps the expanded inset however far it scrolls.
@Test func partWayRestBeforeAnyCollapseIsLeftAlone() {
    let rest = openedAtTop()
    #expect(rest.collapsedInset == expanded)
    #expect(rest.restingOffset(offsetY: -185, topInset: expanded) == nil)
    #expect(rest.restingOffset(offsetY: 600, topInset: expanded) == nil)
}

/// The reported state (the expanded inset with the content 37 pt past its top) and
/// others: once the band is known, the List settles at the nearer end, like UIKit's
/// drag-end snap.
@Test func partWayRestSettlesAtTheNearerEnd() {
    let rest = collapsedOnce()
    #expect(rest.collapsedInset == collapsed)
    #expect(rest.expandedInset == expanded)
    #expect(rest.restingOffset(offsetY: -207, topInset: expanded) == -expanded)
    #expect(rest.restingOffset(offsetY: -197, topInset: expanded) == -expanded)
    #expect(rest.restingOffset(offsetY: -185, topInset: expanded) == -collapsed)
    #expect(rest.restingOffset(offsetY: -172, topInset: expanded) == -collapsed)
}

/// Every legitimate rest is left alone: open at the top, pulled down, closed at the top
/// (an A–Z jump to "#"), scrolled into the list, and sub-point rounding.
@Test func legitimateRestsDoNotMove() {
    let rest = collapsedOnce()
    #expect(rest.restingOffset(offsetY: -expanded, topInset: expanded) == nil)
    #expect(rest.restingOffset(offsetY: -expanded + 0.5, topInset: expanded) == nil)
    #expect(rest.restingOffset(offsetY: -300, topInset: expanded) == nil)
    #expect(rest.restingOffset(offsetY: -collapsed, topInset: collapsed) == nil)
    #expect(rest.restingOffset(offsetY: -150, topInset: collapsed) == nil)
    #expect(rest.restingOffset(offsetY: 2400, topInset: collapsed) == nil)
    #expect(rest.restingOffset(offsetY: -collapsed - 0.5, topInset: expanded) == nil)
}

/// A List that has never rested at its top (it appeared scrolled) has no expanded inset
/// to compare with, so nothing moves; nor does a List whose inset never changes
/// (macOS, pages without a large title).
@Test func unknownInsetsNeverMove() {
    var deep = LargeTitleRest()
    deep.update(offsetY: 900, topInset: collapsed, containerWidth: 402)
    #expect(deep.restingOffset(offsetY: 30, topInset: collapsed) == nil)

    var flat = LargeTitleRest()
    flat.update(offsetY: -52, topInset: 52, containerWidth: 800)
    flat.update(offsetY: 30, topInset: 52, containerWidth: 800)
    #expect(flat.restingOffset(offsetY: 30, topInset: 52) == nil)
}

/// A new width (rotation, window resize) forgets both insets; zero or non-finite samples
/// are ignored.
@Test func widthChangeAndBadSamplesReset() {
    var rest = collapsedOnce()
    rest.update(offsetY: -116, topInset: 116, containerWidth: 874)
    #expect(rest.expandedInset == 116)
    #expect(rest.collapsedInset == 116)
    rest.update(offsetY: .nan, topInset: 116, containerWidth: 874)
    rest.update(offsetY: -500, topInset: 500, containerWidth: 0)
    #expect(rest.expandedInset == 116)
    #expect(rest.restingOffset(offsetY: .infinity, topInset: 116) == nil)
}

/// The expanded inset is the largest seen at the top, so the collapsed-at-top rest does
/// not replace it.
@Test func collapsedAtTopKeepsTheExpandedInset() {
    var rest = collapsedOnce()
    rest.update(offsetY: -collapsed, topInset: collapsed, containerWidth: 402)
    #expect(rest.expandedInset == expanded)
}

// MARK: - Debug park request

/// `FST_DEBUG_SONGS_PARK_TOP` takes points and an optional delay.
@Test func parkRequestParses() {
    #expect(SongsScrollStress.parseParkRequest("37") == .init(points: 37, delay: 3))
    #expect(SongsScrollStress.parseParkRequest("15@12.5") == .init(points: 15, delay: 12.5))
    #expect(SongsScrollStress.parseParkRequest("0") == nil)
    #expect(SongsScrollStress.parseParkRequest("-4") == nil)
    #expect(SongsScrollStress.parseParkRequest("x") == nil)
    #expect(SongsScrollStress.parseParkRequest("4@") == nil)
    #expect(SongsScrollStress.parseParkRequest("4@-1") == nil)
    #expect(SongsScrollStress.parseParkRequest("4@1@2") == nil)
}
