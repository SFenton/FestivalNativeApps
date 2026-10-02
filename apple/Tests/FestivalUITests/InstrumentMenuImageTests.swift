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

    /// Only Lead and Pro Lead switch to the keys artwork on a keyboard song.
    @Test func keyboardVariantOnlyForLeadCharts() {
        for instrument in Instrument.allCases {
            let plain = InstrumentIcon.assetName(for: instrument, keyboard: false)
            let keys = InstrumentIcon.assetName(for: instrument, keyboard: true)
            #expect((plain != keys) == (instrument == .lead || instrument == .proLead))
        }
    }

}
