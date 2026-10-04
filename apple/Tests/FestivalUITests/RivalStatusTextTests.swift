import SwiftUI
import Testing
import FestivalDesign
@testable import FestivalUI

/// Rival status text stays readable on the dark cards (WCAG AA 4.5:1 for small text).
struct RivalStatusTextTests {
    /// Relative luminance of an sRGB colour (0…1 components).
    private func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }

    @Test func redTextIsLightenedOthersUnchanged() {
        #expect(RivalStatusText.readable(BrandTokens.statusRed) == RivalStatusText.red)
        #expect(RivalStatusText.readable(BrandTokens.statusGreen) == BrandTokens.statusGreen)
        #expect(RivalStatusText.readable(FestivalText.primary) == FestivalText.primary)
    }

    /// Against the darkest rendered card behind the pills ((45, 20, 25): the red pill's
    /// 16% fill over the card), the old red failed and the new one passes.
    @Test func redTextMeetsAAOnTheRedPill() {
        let background = luminance(45 / 255, 20 / 255, 25 / 255)
        let old = luminance(198 / 255, 40 / 255, 40 / 255)
        let new = luminance(1, 0.45, 0.45)
        #expect((old + 0.05) / (background + 0.05) < 4.5)
        #expect((new + 0.05) / (background + 0.05) >= 4.5)
    }
}
