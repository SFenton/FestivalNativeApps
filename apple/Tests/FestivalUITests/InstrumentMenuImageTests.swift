import CoreGraphics
import SwiftUI
import Testing
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif
@testable import FestivalCore
@testable import FestivalUI

/// Native menus (Paths' instrument pop-up, issue #88) ignore `resizable()`, so the
/// 144 pt instrument artwork must be pre-sized for every chart and keys variant.
struct InstrumentMenuImageTests {
    /// Every instrument, with and without the keys variant, resolves to a menu-sized image.
    @Test(arguments: Instrument.allCases, [false, true])
    func menuImageIsMenuSized(_ instrument: Instrument, keyboard: Bool) throws {
        let image = try #require(InstrumentIcon.menuPlatformImage(for: instrument, keyboard: keyboard))
        #expect(image.size == CGSize(width: InstrumentIcon.menuIconSide, height: InstrumentIcon.menuIconSide))
    }

    /// Quick Links (issue #303) draws the artwork at a Dynamic Type–scaled side: every
    /// chart redraws to that side instead of the 144 pt asset.
    @Test(arguments: Instrument.allCases, [CGFloat(20), 26, 53])
    func menuImageHonoursRequestedSide(_ instrument: Instrument, side: CGFloat) throws {
        let image = try #require(InstrumentIcon.menuPlatformImage(for: instrument, keyboard: false, side: side))
        #expect(image.size == CGSize(width: side, height: side))
    }

    /// Scaled sides snap to whole points (bounding the cache to one image per text size)
    /// and never collapse to zero.
    @Test func menuSideSnapsToWholePoints() {
        #expect(InstrumentIcon.menuSide(22.35) == 22)
        #expect(InstrumentIcon.menuSide(22.5) == 23)
        #expect(InstrumentIcon.menuSide(20) == 20)
        #expect(InstrumentIcon.menuSide(0.2) == 1)
        #expect(InstrumentIcon.menuSide(-4) == 1)
    }

    /// A fractional scaled side draws at the snapped size.
    @Test func menuImageDrawsAtSnappedSide() throws {
        let image = try #require(InstrumentIcon.menuPlatformImage(for: .drums, keyboard: false, side: 23.4))
        #expect(image.size == CGSize(width: 23, height: 23))
    }

    /// Quick Links instrument icons (issue #313) are sized for visual weight, not equal
    /// geometry: 24 pt on iOS/iPadOS (the Song Paths menu size) and 19 pt on macOS, far
    /// below the 144 pt artwork that overflowed the rows (#303).
    @MainActor @Test func quickLinkInstrumentIconBaseSide() {
        #if os(macOS)
        #expect(QuickLinkLabel.instrumentIconBaseSide == 19)
        #else
        #expect(QuickLinkLabel.instrumentIconBaseSide == InstrumentIcon.menuIconSide)
        #endif
    }

    /// Only the white disc inside each artwork's black ring reads on the dark sheet and
    /// menus. At the Quick Links base side it must look as large as the adjacent SF
    /// Symbols (within 95–110 %), not smaller as with #303's 20 pt frame.
    @MainActor @Test(arguments: Instrument.allCases, [false, true])
    func quickLinkInstrumentDiscMatchesSymbolSize(_ instrument: Instrument, keyboard: Bool) throws {
        let fraction = try #require(Self.visibleDiscFraction(instrument, keyboard: keyboard))
        let visible = QuickLinkLabel.instrumentIconBaseSide * fraction
        let symbol = QuickLinkLabel.adjacentSymbolSide
        #expect(visible >= symbol * 0.95, "\(instrument) disc \(visible) pt vs \(symbol) pt symbols")
        #expect(visible <= symbol * 1.1, "\(instrument) disc \(visible) pt vs \(symbol) pt symbols")
    }

    /// The icon follows the list-row symbols' Dynamic Type curve: it grows with body text
    /// to xxxLarge, holds through Accessibility 3 (where body text alone would make it
    /// 1.6× the symbols), then grows with body text again. macOS menus keep one size.
    @MainActor @Test func quickLinkInstrumentIconScalesLikeRowSymbols() {
        let base = QuickLinkLabel.instrumentIconBaseSide
        let side = QuickLinkLabel.instrumentIconSide(for:)
        #expect(side(.large) == base)
        #if os(macOS)
        for size in DynamicTypeSize.allCases { #expect(side(size) == base) }
        #else
        #expect(side(.xSmall) < base)
        #expect(side(.xLarge) > base)
        #expect(abs(side(.xxxLarge) - base * 23 / 17) < 0.5)
        #expect(side(.accessibility1) == side(.xxxLarge))
        #expect(side(.accessibility3) == side(.xxxLarge))
        #expect(side(.accessibility4) > side(.accessibility3))
        #expect(abs(side(.accessibility5) - side(.accessibility3) * 53 / 40) < 0.5)
        let ordered = DynamicTypeSize.allCases.map(side)
        #expect(ordered == ordered.sorted())
        #endif
    }

    /// Width of the artwork's light (visible on dark) pixels as a fraction of its side.
    ///
    /// - Parameters:
    ///   - instrument: Chart whose artwork to measure.
    ///   - keyboard: Use the keys variant.
    /// - Returns: The bright bounding-box width over the image width, or nil if unreadable.
    private static func visibleDiscFraction(_ instrument: Instrument, keyboard: Bool) -> CGFloat? {
        let platformImage = InstrumentIcon.menuPlatformImage(for: instrument, keyboard: keyboard, side: 144)
        #if canImport(UIKit)
        let source = platformImage?.cgImage
        #else
        let source = platformImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
        guard let image = source else { return nil }
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        var minX = width, maxX = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                let luminance = (Int(pixels[i]) + Int(pixels[i + 1]) + Int(pixels[i + 2])) / 3
                if pixels[i + 3] > 128, luminance > 128 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                }
            }
        }
        guard maxX >= minX else { return nil }
        return CGFloat(maxX - minX + 1) / CGFloat(width)
    }

    /// Only Lead and Pro Lead switch to the keys artwork on a keyboard song.
    @Test func keyboardVariantOnlyForLeadCharts() {
        for instrument in Instrument.allCases {
            let plain = InstrumentIcon.assetName(for: instrument, keyboard: false)
            let keys = InstrumentIcon.assetName(for: instrument, keyboard: true)
            #expect((plain != keys) == (instrument == .lead || instrument == .proLead))
        }
    }

}
