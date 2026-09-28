import Testing
import FestivalCore
@testable import FestivalUI

/// Every registered first-run slide (all 9 pages) must resolve to a live native demo, not the
/// static SF Symbol fallback — the follow-up this lane was created to close. Pure logic only (no
/// view rendering), so it runs on every platform `swift test` targets.
@Suite struct FirstRunDemoCoverageTests {
    @Test func everyCatalogSlideHasALiveDemo() {
        for page in FirstRunPageKey.allCases {
            for slide in FirstRunCatalog.slides(for: page) {
                #expect(
                    FirstRunDemoContent.hasLiveDemo(id: slide.id),
                    "\(page.rawValue)/\(slide.id) has no live demo"
                )
            }
        }
    }

    @Test func unknownSlideIDFallsBackToStaticIllustration() {
        #expect(!FirstRunDemoContent.hasLiveDemo(id: "not-a-real-slide"))
    }
}
