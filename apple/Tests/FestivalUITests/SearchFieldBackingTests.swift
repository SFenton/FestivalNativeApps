import Testing
@testable import FestivalUI

/// The Filter Songs drawer field's backing (issue #559): Liquid Glass at every scroll
/// position, the opaque fallback under any Reduce Transparency or Increase Contrast
/// setting (surface-materials R4) and the classic system field before iOS 26.
@Suite("Search field backing")
struct SearchFieldBackingTests {
    @Test("Glass surfaces back the field with glass")
    func glassBacksWithGlass() {
        #expect(SearchFieldBacking.resolve(.glass, glassAvailable: true) == .glass)
    }

    @Test("Accessibility fallbacks back the field with the opaque capsule")
    func opaqueBacksOpaque() {
        #expect(SearchFieldBacking.resolve(.opaque, glassAvailable: true) == .opaque)
    }

    @Test("Before Liquid Glass the system field is left alone")
    func pre26IsUntouched() {
        #expect(SearchFieldBacking.resolve(.frosted, glassAvailable: false) == SearchFieldBacking.none)
        #expect(SearchFieldBacking.resolve(.opaque, glassAvailable: false) == SearchFieldBacking.none)
        #expect(SearchFieldBacking.resolve(.glass, glassAvailable: false) == SearchFieldBacking.none)
    }

    @Test("Each R4 setting resolves through the surface to the opaque backing")
    func r4SettingsResolveOpaque() {
        let settings: [(Bool, Bool, Bool)] = [(true, false, false), (false, true, false), (false, false, true)]
        for (reduce, less, more) in settings {
            let surface = FestivalGlassSurface.resolve(
                reduceTransparency: reduce, systemContrast: .standard,
                lessTransparency: less, moreContrast: more, glassAvailable: true
            )
            #expect(SearchFieldBacking.resolve(surface, glassAvailable: true) == .opaque)
        }
        let contrast = FestivalGlassSurface.resolve(
            reduceTransparency: false, systemContrast: .increased,
            lessTransparency: false, moreContrast: false, glassAvailable: true
        )
        #expect(SearchFieldBacking.resolve(contrast, glassAvailable: true) == .opaque)
    }

    @Test("A glass backing needs the transition fill at the top edge too")
    func glassNeedsFillAlways() {
        #expect(SearchFieldBacking.glass.needsTransitionFill(contentUnderBar: false))
        #expect(SearchFieldBacking.glass.needsTransitionFill(contentUnderBar: true))
    }

    @Test("An opaque backing draws in the transition portal and needs no fill")
    func opaqueNeedsNoFill() {
        #expect(!SearchFieldBacking.opaque.needsTransitionFill(contentUnderBar: false))
        #expect(!SearchFieldBacking.opaque.needsTransitionFill(contentUnderBar: true))
    }

    @Test("Without a backing the #544 rule holds: fill only while content is under the bar")
    func unbackedKeeps544Rule() {
        #expect(!SearchFieldBacking.none.needsTransitionFill(contentUnderBar: false))
        #expect(SearchFieldBacking.none.needsTransitionFill(contentUnderBar: true))
    }
}
