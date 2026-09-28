import AppKit
import SwiftUI
import Testing
@testable import FestivalDesign

// MARK: - Helpers

/// WCAG relative luminance of an sRGB SwiftUI colour.
///
/// - Parameter color: Colour to measure.
/// - Returns: Relative luminance in 0...1.
private func luminance(_ color: Color) -> Double {
    let ns = NSColor(color).usingColorSpace(.sRGB)!
    func channel(_ value: CGFloat) -> Double {
        let v = Double(value)
        return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * channel(ns.redComponent) + 0.7152 * channel(ns.greenComponent)
        + 0.0722 * channel(ns.blueComponent)
}

/// WCAG contrast ratio between two opaque colours.
private func contrast(_ a: Color, _ b: Color) -> Double {
    let (la, lb) = (luminance(a), luminance(b))
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// MARK: - Tests

@Test("Primary text is pure white, per the operator's white-text rule")
func festivalTextPrimaryIsWhite() {
    let ns = NSColor(FestivalText.primary).usingColorSpace(.sRGB)!
    #expect(ns.redComponent == 1 && ns.greenComponent == 1 && ns.blueComponent == 1)
}

@Test("De-emphasized text stays readable (WCAG AA) on the app and card backgrounds")
func festivalTextDeemphasizedMeetsContrast() {
    #expect(contrast(FestivalText.deemphasized, BrandTokens.appBackground) >= 4.5)
    #expect(contrast(FestivalText.deemphasized, BrandTokens.cardBackground) >= 4.5)
    // De-emphasis must be visibly quieter than primary, or the exception is meaningless.
    #expect(luminance(FestivalText.deemphasized) < luminance(FestivalText.primary) * 0.5)
}
