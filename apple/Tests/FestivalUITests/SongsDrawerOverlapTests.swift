import CoreGraphics
import Testing
@testable import FestivalUI

/// `/duo` P3: the Songs list clears the pinned Filter field only where the navigation
/// bar under-reports its safe area, and only in compact height.
struct SongsDrawerOverlapTests {
    @Test func duoOuterLandscapePadsByTheMeasuredOverlap() {
        // Live iPhone Duo outer landscape, iOS 27.1: bar to 136 pt, safe area 65 pt.
        #expect(SongsDrawerOverlap.padding(barBottom: 136, safeTop: 65, compactHeight: true) == 71)
    }

    @Test func regularHeightNeverPads() {
        // iPhone, iPad, inner display and outer portrait keep the system inset.
        #expect(SongsDrawerOverlap.padding(barBottom: 136, safeTop: 65, compactHeight: false) == 0)
        #expect(SongsDrawerOverlap.padding(barBottom: 136, safeTop: 136, compactHeight: false) == 0)
    }

    @Test func matchingOrRoundingDifferencesDoNotPad() {
        #expect(SongsDrawerOverlap.padding(barBottom: 136, safeTop: 136, compactHeight: true) == 0)
        #expect(SongsDrawerOverlap.padding(barBottom: 136.4, safeTop: 136, compactHeight: true) == 0)
        // A bar that ends above the safe area (hidden drawer) never pads negatively.
        #expect(SongsDrawerOverlap.padding(barBottom: 60, safeTop: 65, compactHeight: true) == 0)
    }

    @Test func nonFiniteMeasurementsDoNotPad() {
        #expect(SongsDrawerOverlap.padding(barBottom: .infinity, safeTop: 65, compactHeight: true) == 0)
        #expect(SongsDrawerOverlap.padding(barBottom: 136, safeTop: .nan, compactHeight: true) == 0)
    }
}
