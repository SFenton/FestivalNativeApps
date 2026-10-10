import CoreGraphics
import Testing
@testable import FestivalUI

/// When the drawer search field needs its transition fill (issue #544): only while
/// content is scrolled under the bar, the state in which the system field draws glass
/// that a navigation transition's portal cannot.
@Suite("Search drawer transition fill")
struct SearchDrawerTransitionFillTests {
    @Test("Content at its top edge is not under the bar")
    func atTopIsNotUnderBar() {
        // A large-title page at rest: offset is minus the expanded top inset.
        #expect(!SearchDrawerTransitionFill.isContentUnderBar(offsetY: -232, adjustedTopInset: 232))
        #expect(!SearchDrawerTransitionFill.isContentUnderBar(offsetY: -116, adjustedTopInset: 116))
    }

    @Test("Rounding below the tolerance does not count as scrolled")
    func roundingIsNotUnderBar() {
        #expect(!SearchDrawerTransitionFill.isContentUnderBar(offsetY: -115.6, adjustedTopInset: 116))
    }

    @Test("Scrolled content is under the bar")
    func scrolledIsUnderBar() {
        #expect(SearchDrawerTransitionFill.isContentUnderBar(offsetY: -115, adjustedTopInset: 116))
        #expect(SearchDrawerTransitionFill.isContentUnderBar(offsetY: 640, adjustedTopInset: 116))
    }

    @Test("Pulled down past the top (rubber band) is not under the bar")
    func overscrollIsNotUnderBar() {
        #expect(!SearchDrawerTransitionFill.isContentUnderBar(offsetY: -300, adjustedTopInset: 232))
    }
}
