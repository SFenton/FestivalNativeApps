import CoreGraphics
import Testing
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

    /// Quick Links instrument icons start at the enclosed-circle SF Symbol size beside
    /// body text (20 pt on iOS/iPadOS, 16 pt beside macOS's 13 pt menu text), far below
    /// the 144 pt artwork that overflowed the rows.
    @Test func quickLinkInstrumentIconMatchesSymbolSize() {
        #if os(macOS)
        #expect(QuickLinkLabel.instrumentIconBaseSide == 16)
        #else
        #expect(QuickLinkLabel.instrumentIconBaseSide == 20)
        #endif
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
