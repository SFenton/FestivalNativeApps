import FestivalCore
import SwiftUI
import Testing
@testable import FestivalUI

/// Scroll-edge R7 for the shared bottom-chrome fade (``BottomChromeFade``) on the Solo
/// chart, Full Rankings and the band boards, including the full band leaderboard's
/// selected-band footer (issue #306): the web's 36-point fade normally, a hard cut at
/// the chrome's top edge under Reduce Transparency, Less Transparency or Increase
/// Contrast (system or in-app).
struct BottomChromeFadeTests {
    @Test func fadesByDefault() {
        let distance = BottomChromeFade.fadeDistance(
            ScrollEdgeFade.distance, systemReduceTransparency: false, lessTransparency: false,
            systemContrast: .standard, moreContrast: false
        )
        #expect(distance == 36)
        let stops = ScrollEdgeFade.bottom(height: 800, obscured: 200, distance: distance)
        #expect(stops.fadeStart < stops.fadeEnd)
    }

    @Test(arguments: [
        (true, false, false, false), (false, true, false, false),
        (false, false, true, false), (false, false, false, true),
    ])
    func accessibilitySettingsCutHardAtTheChrome(
        systemReduceTransparency: Bool, lessTransparency: Bool, systemIncreased: Bool, moreContrast: Bool
    ) {
        let distance = BottomChromeFade.fadeDistance(
            ScrollEdgeFade.distance, systemReduceTransparency: systemReduceTransparency,
            lessTransparency: lessTransparency, systemContrast: systemIncreased ? .increased : .standard,
            moreContrast: moreContrast
        )
        #expect(distance == 0)
        let stops = ScrollEdgeFade.bottom(height: 800, obscured: 200, distance: distance)
        #expect(stops == .init(fadeStart: 0.75, fadeEnd: 0.75))
    }

    @Test func shrinkingEndOfListFadeIsKeptWhenNoSettingIsOn() {
        #expect(BottomChromeFade.fadeDistance(
            12.5, systemReduceTransparency: false, lessTransparency: false,
            systemContrast: .standard, moreContrast: false
        ) == 12.5)
    }
}
