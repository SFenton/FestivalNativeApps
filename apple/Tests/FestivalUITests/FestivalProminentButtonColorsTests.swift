import AppKit
import SwiftUI
import Testing
import FestivalDesign
@testable import FestivalUI

// MARK: - Prominent button label contrast (issue #477)

/// Pins the fill and label of `festivalProminentButton()` (Choose Profile, Start New Mix):
/// under Increase Contrast its white fill had kept `.borderedProminent`'s white label, a blank
/// capsule (found by `DuoPageTitleAccessibilityJourneyTests`).
@Suite("Prominent button colours")
struct FestivalProminentButtonColorsTests {
    /// WCAG relative luminance of an opaque sRGB colour.
    private static func luminance(_ color: Color) -> Double {
        let ns = NSColor(color).usingColorSpace(.sRGB)!
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(ns.redComponent) + 0.7152 * channel(ns.greenComponent)
            + 0.0722 * channel(ns.blueComponent)
    }

    /// WCAG contrast ratio of two opaque colours.
    private static func contrast(_ a: Color, _ b: Color) -> Double {
        let (la, lb) = (luminance(a), luminance(b))
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    @Test("By default the label is white on the readable accent blue (WCAG AA)")
    func defaultColours() {
        let colors = FestivalProminentButtonColors(increasedContrast: false)
        #expect(colors.fill == AccentText.prominentFill)
        #expect(colors.label == BrandTokens.textPrimary)
        #expect(Self.contrast(colors.label, colors.fill) >= 4.5)
    }

    @Test("Under Increase Contrast the white root tint gets a dark label (WCAG AAA)")
    func increasedContrastColours() {
        let colors = FestivalProminentButtonColors(increasedContrast: true)
        #expect(colors.fill == BrandTokens.textPrimary)
        #expect(colors.label != colors.fill)
        #expect(Self.contrast(colors.label, colors.fill) >= 7)
    }
}
