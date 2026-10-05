import FestivalCore
import Testing
@testable import FestivalUI

/// Issue #306 review (scroll-edge R7): the shared bottom-chrome mask on the Solo chart,
/// Full Rankings and the full band leaderboard keeps the web's 36-point fade normally and
/// becomes a hard cut at the chrome's top edge under Reduce Transparency, Less
/// Transparency or Increase Contrast.
struct BottomChromeEdgeFadeTests {
    @Test func fadesByDefault() {
        let distance = BottomChromeEdgeFadeMask.fadeDistance(
            ScrollEdgeFade.distance, reduceTransparency: false, increaseContrast: false
        )
        #expect(distance == 36)
        let stops = ScrollEdgeFade.bottom(height: 800, obscured: 200, distance: distance)
        #expect(stops.fadeStart < stops.fadeEnd)
    }

    @Test(arguments: [(true, false), (false, true), (true, true)])
    func accessibilitySettingsCutHardAtTheChrome(reduceTransparency: Bool, increaseContrast: Bool) {
        let distance = BottomChromeEdgeFadeMask.fadeDistance(
            ScrollEdgeFade.distance,
            reduceTransparency: reduceTransparency, increaseContrast: increaseContrast
        )
        #expect(distance == 0)
        let stops = ScrollEdgeFade.bottom(height: 800, obscured: 200, distance: distance)
        #expect(stops == .init(fadeStart: 0.75, fadeEnd: 0.75))
    }

    @Test func shrinkingEndOfListFadeIsKeptWhenNoSettingIsOn() {
        #expect(BottomChromeEdgeFadeMask.fadeDistance(
            12.5, reduceTransparency: false, increaseContrast: false
        ) == 12.5)
    }
}
