import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Hit regions (issue #15)

/// Pins the geometry behind the forgiving tap areas of the floating page tools and the
/// cache behind the profile monogram's image bar button. The taps themselves are covered
/// by `NavButtonHitRegionJourneyTests` (XCUITest).
@Suite("Navigation button hit regions")
struct NavButtonHitRegionTests {
    @Test("Floating tools are at least 44 pt square and their hit regions never touch")
    func floatingToolGeometry() {
        #expect(FloatingPageControls.buttonSize >= 44)
        #expect(FloatingPageControls.spacing > 0)
        #expect(FloatingPageControls.height == FloatingPageControls.buttonSize + 8)
    }

    @Test("Names with the same initial share one monogram image")
    func monogramKeySharesInitials() {
        let a = MonogramImageKey(name: "fixture Player", size: 30, scale: 3)
        let b = MonogramImageKey(name: "Fred", size: 30, scale: 3)
        #expect(a == b)
        #expect(a.initial == "F")
        #expect(a != MonogramImageKey(name: "Gina", size: 30, scale: 3))
    }

    @Test("Size and display scale produce distinct monogram images")
    func monogramKeySeparatesSizeAndScale() {
        let base = MonogramImageKey(name: "Fred", size: 30, scale: 3)
        #expect(base != MonogramImageKey(name: "Fred", size: 30, scale: 2))
        #expect(base != MonogramImageKey(name: "Fred", size: 36, scale: 3))
    }

    @Test("An unset display scale renders at 1x")
    func monogramKeyClampsScale() {
        #expect(MonogramImageKey(name: "Fred", size: 30, scale: 0).scale == 1)
    }
}

#if os(macOS)
import AppKit

/// The label style must give the label itself the full square: a `Menu` only answers
/// taps on its label, which is why Quick Links in the dock ignored near misses.
@MainActor
@Suite("Floating tool label")
struct FloatingPageToolLabelStyleTests {
    @Test("The label fills the floating tool's square")
    func labelFillsSquare() {
        let side = FloatingPageControls.buttonSize
        let host = NSHostingView(rootView: Label("Quick Links", systemImage: "list.bullet.indent")
            .labelStyle(FloatingPageToolLabelStyle(side: side)))
        #expect(host.fittingSize == CGSize(width: side, height: side))
    }
}
#endif
