import Foundation
import Testing
@testable import FestivalUI

// MARK: - Modal top-edge fade (issue #94)

/// The fade below the header matches the web modal mask's 40 px.
@Test func modalFadeRampMatchesTheWebMask() {
    #expect(ModalTopEdgeFade.rampHeight == 40)
}

/// At rest (or pulled down past the top) content right below the header is fully drawn;
/// the fade grows over the first 40 pt of scrolling and then stays full.
@Test func modalFadeGrowsWithTheFirstRampOfScrolling() {
    #expect(ModalTopEdgeFade.progress(scrollOffset: 0) == 0)
    #expect(ModalTopEdgeFade.progress(scrollOffset: -30) == 0)
    #expect(ModalTopEdgeFade.progress(scrollOffset: 10) == 0.25)
    #expect(ModalTopEdgeFade.progress(scrollOffset: 40) == 1)
    #expect(ModalTopEdgeFade.progress(scrollOffset: 900) == 1)
    #expect(ModalTopEdgeFade.progress(scrollOffset: .nan) == 0)
    #expect(ModalTopEdgeFade.progress(scrollOffset: .infinity) == 0)
}

/// Content is opaque at the header edge at rest and fully transparent there once scrolled.
@Test func modalFadeEdgeOpacityFollowsProgress() {
    #expect(ModalTopEdgeFade.edgeOpacity(progress: 0) == 1)
    #expect(ModalTopEdgeFade.edgeOpacity(progress: 0.25) == 0.75)
    #expect(ModalTopEdgeFade.edgeOpacity(progress: 1) == 0)
    #expect(ModalTopEdgeFade.edgeOpacity(progress: 2) == 0)
    #expect(ModalTopEdgeFade.edgeOpacity(progress: -1) == 1)
    #expect(ModalTopEdgeFade.edgeOpacity(progress: .nan) == 1)
}

/// A full-bleed list reports the header as its inset; content below the bar reports it as
/// its offset and the same inset again. Neither layout may count the header twice.
@Test func modalHeaderHeightTakesTheLargerReading() {
    #expect(ModalTopEdgeFade.headerHeight(safeAreaInset: 70, containerOffset: 0) == 70)
    #expect(ModalTopEdgeFade.headerHeight(safeAreaInset: 70, containerOffset: 70) == 70)
    #expect(ModalTopEdgeFade.headerHeight(safeAreaInset: 0, containerOffset: 52) == 52)
    #expect(ModalTopEdgeFade.headerHeight(safeAreaInset: 0, containerOffset: 0) == 0)
    #expect(ModalTopEdgeFade.headerHeight(safeAreaInset: -5, containerOffset: -10) == 0)
    #expect(ModalTopEdgeFade.headerHeight(safeAreaInset: .nan, containerOffset: 40) == 40)
    #expect(ModalTopEdgeFade.headerHeight(safeAreaInset: .infinity, containerOffset: .nan) == 0)
}

/// Content that fades itself under pinned headers asks for a 0 pt ramp: a hard edge once
/// scrolled, still fully drawn at rest (issue #301).
@Test func modalFadeZeroRampIsAHardEdgeOnceScrolled() {
    #expect(ModalTopEdgeFade.progress(scrollOffset: 0, rampHeight: 0) == 0)
    #expect(ModalTopEdgeFade.progress(scrollOffset: -12, rampHeight: 0) == 0)
    #expect(ModalTopEdgeFade.progress(scrollOffset: 0.5, rampHeight: 0) == 1)
    #expect(ModalTopEdgeFade.progress(scrollOffset: .nan, rampHeight: 0) == 0)
    #expect(ModalTopEdgeFade.progress(scrollOffset: 10, rampHeight: 20) == 0.5)
}

/// The smallest requested ramp wins when several views set one.
@Test func modalFadeRampPreferenceKeepsTheSmallest() {
    var value: CGFloat? = ModalTopEdgeFadeRampKey.defaultValue
    ModalTopEdgeFadeRampKey.reduce(value: &value) { nil }
    #expect(value == nil)
    ModalTopEdgeFadeRampKey.reduce(value: &value) { 12 }
    #expect(value == 12)
    ModalTopEdgeFadeRampKey.reduce(value: &value) { 0 }
    #expect(value == 0)
    ModalTopEdgeFadeRampKey.reduce(value: &value) { 30 }
    #expect(value == 0)
}
