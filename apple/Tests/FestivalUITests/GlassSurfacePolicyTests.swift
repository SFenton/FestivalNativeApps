import SwiftUI
import Testing
@testable import FestivalUI

/// surface-materials R4 (issue #358): every accessibility setting that asks for less
/// transparency or more contrast, system or in-app, turns a glass surface opaque.
struct GlassSurfacePolicyTests {
    private func resolve(
        reduceTransparency: Bool = false, systemContrast: ColorSchemeContrast = .standard,
        lessTransparency: Bool = false, moreContrast: Bool = false, glassAvailable: Bool = true
    ) -> FestivalGlassSurface {
        FestivalGlassSurface.resolve(
            reduceTransparency: reduceTransparency, systemContrast: systemContrast,
            lessTransparency: lessTransparency, moreContrast: moreContrast,
            glassAvailable: glassAvailable
        )
    }

    @Test func defaultsDrawGlassOrThePre26Fallback() {
        #expect(resolve() == .glass)
        #expect(resolve(glassAvailable: false) == .frosted)
    }

    @Test func systemIncreaseContrastIsOpaque() {
        #expect(resolve(systemContrast: .increased) == .opaque)
        #expect(resolve(systemContrast: .increased, glassAvailable: false) == .opaque)
    }

    @Test func everyOtherAccessibilitySettingIsOpaque() {
        #expect(resolve(reduceTransparency: true) == .opaque)
        #expect(resolve(lessTransparency: true) == .opaque)
        #expect(resolve(moreContrast: true) == .opaque)
        #expect(resolve(reduceTransparency: true, glassAvailable: false) == .opaque)
    }
}
