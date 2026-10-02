import CoreGraphics
import Testing
@testable import FestivalUI

/// Issue #10: Songs rows fade out under the floating section title like content under
/// the navigation bar, and keep a hard edge under Reduce Transparency / Increase Contrast.
struct SectionBarEdgeFadeTests {
    @Test func fadesByDefault() {
        let height = SectionBarEdgeFade.height(reduceTransparency: false, increaseContrast: false)
        #expect(height == SectionBarEdgeFade.height)
        #expect(height > 0)
    }

    @Test(arguments: [(true, false), (false, true), (true, true)])
    func accessibilitySettingsKeepAHardEdge(reduceTransparency: Bool, increaseContrast: Bool) {
        #expect(SectionBarEdgeFade.height(
            reduceTransparency: reduceTransparency, increaseContrast: increaseContrast
        ) == 0)
    }

    @Test func rowsAreHiddenAtTheTitleEdgeAndOpaqueAfterTheFade() {
        #expect(SectionBarEdgeFade.opacity(at: 0) == 0)
        #expect(SectionBarEdgeFade.opacity(at: 1) == 1)
        #expect(SectionBarEdgeFade.opacity(at: -3) == 0)
        #expect(SectionBarEdgeFade.opacity(at: 4) == 1)
        #expect(SectionBarEdgeFade.opacity(at: 0.5) == 0.5)
    }

    @Test func opacityRisesSteadilyThroughTheFade() {
        let samples = stride(from: CGFloat(0), through: 1, by: 0.05).map(SectionBarEdgeFade.opacity(at:))
        #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test func gradientStopsSpanTheFade() {
        let stops = SectionBarEdgeFade.gradientStops
        #expect(stops.count == SectionBarEdgeFade.sampleLocations.count)
        #expect(stops.first?.location == 0)
        #expect(stops.last?.location == 1)
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.location < $1.location })
    }
}
