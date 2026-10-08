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

    /// Item Shop demo rows cycle like the web: the highlighting slide alternates green and
    /// plain; New and Leaving Tomorrow cycle their badge, green, then plain.
    @Test func shopDemoRowsCycleTheWebHighlightPhases() {
        let highlighting = (0..<4).map { FirstRunShopRowPhase.phase(at: $0, highlight: nil) }
        #expect(highlighting == [.inShop, .plain, .inShop, .plain])
        let new = (0..<6).map { FirstRunShopRowPhase.phase(at: $0, highlight: .new) }
        #expect(new == [.highlighted(.new), .inShop, .plain, .highlighted(.new), .inShop, .plain])
        let leaving = (0..<3).map { FirstRunShopRowPhase.phase(at: $0, highlight: .leavingTomorrow) }
        #expect(leaving == [.highlighted(.leavingTomorrow), .inShop, .plain])
    }

    /// The infinite-scroll demo shows the web's six category templates in its order.
    @Test func infiniteScrollUsesTheWebsSixTemplates() {
        #expect(FirstRunSuggestionsCategoryCardDemo.scrollTemplates.map(\.key) == [
            "unfc_guitar", "pct_push_bass", "stale_vocals_1", "near_fc_any", "unplayed_drums", "variety_pack",
        ])
    }
}
