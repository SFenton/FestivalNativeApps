import CoreGraphics
import Testing
@testable import FestivalUI

/// Far list jumps teleport instead of animating through unbuilt rows (`ListJump`).
struct ListJumpTests {
    @Test func visibleRowsOverEstimatesFromTheShortestRow() {
        #expect(ListJump.visibleRows(viewportHeight: 0) == 1)
        #expect(ListJump.visibleRows(viewportHeight: -10) == 1)
        #expect(ListJump.visibleRows(viewportHeight: .infinity) == 1)
        #expect(ListJump.visibleRows(viewportHeight: 56) == 1)
        #expect(ListJump.visibleRows(viewportHeight: 57) == 2)
        // iPad Pro 11" portrait list (~1100 pt) and iPhone 17 Pro (~760 pt).
        #expect(ListJump.visibleRows(viewportHeight: 1100) == 20)
        #expect(ListJump.visibleRows(viewportHeight: 760) == 14)
    }

    @Test func farMeansMoreThanOneScreenfulEitherWay() {
        #expect(!ListJump.isFar(rowDistance: 14, viewportHeight: 760))
        #expect(ListJump.isFar(rowDistance: 15, viewportHeight: 760))
        #expect(ListJump.isFar(rowDistance: -15, viewportHeight: 760))
        #expect(!ListJump.isFar(rowDistance: 0, viewportHeight: 0))
        #expect(ListJump.isFar(rowDistance: 2, viewportHeight: 0))
    }

    @Test @MainActor func teleportScrollsInstantlyTwiceAndRestoresOpacity() async {
        var opacities: [Double] = []
        var scrolls = 0
        await ListJump.teleport(setOpacity: { opacities.append($0) }, scroll: { scrolls += 1 })
        #expect(scrolls == 2)
        #expect(opacities == [0, 1])
    }

    @Test @MainActor func fadeStateDecidesWithItsViewport() async {
        let fade = ListJumpFade()
        fade.viewportHeight = 760
        #expect(!fade.isFar(rowDistance: 10))
        #expect(fade.isFar(rowDistance: 40))
        await fade.teleport {}
        #expect(fade.opacity == 1)
    }
}

/// Stress-pass row arithmetic.
struct SongsScrollStressRowTests {
    @Test func sectionsStartAfterTheirTitleAndSongs() {
        #expect(SongsScrollStress.rowOffsets(sectionSizes: []) == [])
        #expect(SongsScrollStress.rowOffsets(sectionSizes: [3, 0, 5, 2]) == [0, 4, 5, 11])
        #expect(SongsScrollStress.rowOffsets(sectionSizes: [-1, 2]) == [0, 1])
    }
}
