import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Hit regions (issue #15)

/// Pins the cache behind the profile monogram's image bar button. The taps themselves
/// are covered by `NavButtonHitRegionJourneyTests` (XCUITest).
@Suite("Navigation button hit regions")
struct NavButtonHitRegionTests {
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
