import Foundation
import Testing
@testable import FestivalUI

// MARK: - Modal top-edge fade (issue #94)

/// A typical iPhone sheet header (inline title + Close) is 70 pt: content is fully
/// transparent behind its top 46 pt and fades back in over the last 24 pt.
@Test func modalFadeRampsOverTheHeadersLowerEdge() {
    #expect(ModalTopEdgeFade.rampHeight(headerHeight: 70) == 24)
    #expect(abs(ModalTopEdgeFade.fadeStart(headerHeight: 70) - 46.0 / 70.0) < 1e-9)
}

/// A short header keeps at least its top half fully faded, behind the title and Close.
@Test func modalFadeRampNeverExceedsHalfTheHeader() {
    #expect(ModalTopEdgeFade.rampHeight(headerHeight: 30) == 15)
    #expect(ModalTopEdgeFade.fadeStart(headerHeight: 30) == 0.5)
    #expect(ModalTopEdgeFade.rampHeight(headerHeight: 500) == ModalTopEdgeFade.maxRampHeight)
}

/// With no header (a preview or a toolbar-less macOS sheet) nothing is faded.
@Test func modalFadeIsOffWithoutAHeader() {
    for height: CGFloat in [0, -10, .nan, .infinity] {
        #expect(ModalTopEdgeFade.rampHeight(headerHeight: height) == 0)
        #expect(ModalTopEdgeFade.fadeStart(headerHeight: height) == 1)
    }
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
