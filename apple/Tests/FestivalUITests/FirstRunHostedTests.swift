#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Carousel slide/page states

/// A lone slide is simultaneously the first and last: only "Done" shows — no Skip, no
/// Back and no page dots (operator batch 6, item 6.7).
@MainActor
@Test func firstRunCarouselSingleSlideShowsDoneNotSkip() async throws {
    var finished = false
    var viewing = FirstRunViewing(slides: [])
    let slide = FirstRunSlide(
        id: "songs-song-list", version: 1, title: "Browse Every Song",
        description: "Search, sort and filter the full catalogue.", gate: .always
    )
    let size = CGSize(width: 390, height: 700)
    let host = nativeHostedView(
        FirstRunCarouselView(
            page: .songs, slides: [slide],
            viewing: Binding(get: { viewing }, set: { viewing = $0 })
        ) { finished = true }
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Browse Every Song", "Done"])
    _ = try nativeHostedPNG(image, filename: "first-run-single-slide.png", environment: "FST_FIRST_RUN_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["Browse Every Song", "Done"],
        notContaining: ["Skip", "Back", "Next", "Page"]
    )
    #expect(viewing.seenSlides([slide]).map(\.id) == ["songs-song-list"])
    #expect(!finished, "onFinish must only fire from a user action, never on render")
}

/// A multi-slide carousel starts on its first slide with "Next" first, Skip, no
/// reachable Back, white page dots ("Page", 1 of 3), and only slide zero viewed.
@MainActor
@Test func firstRunCarouselMultiSlideStartsOnFirstSlideWithNextOnly() async throws {
    let slides = [
        FirstRunSlide(
            id: "songs-song-list", version: 1, title: "Browse Every Song",
            description: "Search, sort and filter the full catalogue.", gate: .always
        ),
        FirstRunSlide(
            id: "songs-sort", version: 1, title: "Sort Your Way",
            description: "Sort by title, artist, year or difficulty.", gate: .always
        ),
        FirstRunSlide(
            id: "songs-shop-highlight", version: 1, title: "Shop Highlights",
            description: "New Item Shop songs are called out inline.", gate: .shopHighlightEnabled
        ),
    ]
    let size = CGSize(width: 390, height: 700)
    var viewing = FirstRunViewing(slides: slides)
    let host = nativeHostedView(
        FirstRunCarouselView(
            page: .songs, slides: slides,
            viewing: Binding(get: { viewing }, set: { viewing = $0 })
        ) {}
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Browse Every Song", "Page", "Next", "Skip"]
    )
    _ = try nativeHostedPNG(image, filename: "first-run-multi-slide.png", environment: "FST_FIRST_RUN_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["Browse Every Song", "Page", "Next", "Skip"],
        notContaining: ["Back", "Done"]
    )
    #expect(viewing.seenSlides(slides).map(\.id) == ["songs-song-list"])
}

/// The gated third slide is excluded by `FirstRunSlideEvaluator` when Shop highlighting
/// is off, leaving only the two always-visible slides — the `gated` control state.
@Test func gatedSlideIsExcludedFromTheUnseenListWhenItsGateFails() {
    let slides = [
        FirstRunSlide(id: "a", version: 1, title: "A", description: "A.", gate: .always),
        FirstRunSlide(id: "b", version: 1, title: "B", description: "B.", gate: .shopHighlightEnabled),
    ]
    let context = FirstRunGateContext(shopHighlightEnabled: false)
    let unseen = FirstRunSlideEvaluator.unseenSlides(
        slides, context: context, seen: [:]
    )
    #expect(unseen.map(\.id) == ["a"])
}

/// Replaying via Settings ignores both seen-state and gates (`allSlides`), the
/// `replay-all` control state.
@Test func replayShowsEveryDeclaredSlideRegardlessOfGateOrSeenState() {
    let slides = [
        FirstRunSlide(id: "a", version: 1, title: "A", description: "A.", gate: .always),
        FirstRunSlide(id: "b", version: 1, title: "B", description: "B.", gate: .hasPlayer),
    ]
    #expect(FirstRunSlideEvaluator.allSlides(slides).map(\.id) == ["a", "b"])
}

// MARK: - Settings replay section

/// One "Show" row per registered first-run page (`fst.settings.first-run.<page>`).
@MainActor
@Test func firstRunSettingsSectionListsEveryRegisteredPage() async throws {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 390, height: 700)
    let host = nativeHostedView(
        FirstRunSettingsSection(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["First Run Guides", "Songs", "Show Songs guide", "Show Item Shop guide"]
    )
    _ = try nativeHostedPNG(image, filename: "first-run-settings.png", environment: "FST_FIRST_RUN_RENDER_OUT")
    assertRendersContent(
        host, image: image,
        containing: ["First Run Guides", "Songs", "Show Songs guide", "Show Item Shop guide"],
        notContaining: ["Slide", "slides"]
    )
    #expect(FirstRunCenter.registeredPages.count == FirstRunPageKey.allCases.count)
}
// MARK: - Native Songs demos (operator batch 7)

/// Every Songs slide renders the app's real Songs UI (rows, sheets, tab bar, chips) without a
/// session, with redacted placeholder songs instead of invented titles (issue #26).
@MainActor
@Test func nativeSongsDemosRenderRealSongsUI() async throws {
    try await renderDemos(FirstRunCatalog.slides(for: .songs).map { (.songs, $0) })
}

/// Every non-Songs demo that shows songs (Statistics top songs, Rivals detail, Suggestions
/// card, Item Shop) still renders while the catalogue is loading or unavailable (issue #26).
@MainActor
@Test func songDemosRenderPlaceholdersWithoutCatalogue() async throws {
    let ids: [FirstRunPageKey: Set<String>] = [
        .statistics: ["statistics-top-songs"],
        .rivals: ["rivals-detail"],
        .suggestions: ["suggestions-category-card"],
        .shop: ["shop-overview", "shop-highlighting", "shop-new-items", "shop-leaving-tomorrow"],
    ]
    let slides = ids.keys.sorted { $0.rawValue < $1.rawValue }.flatMap { page in
        FirstRunCatalog.slides(for: page).filter { ids[page]!.contains($0.id) }.map { (page, $0) }
    }
    #expect(slides.count == ids.values.reduce(0) { $0 + $1.count })
    try await renderDemos(slides)
}

@MainActor
private func renderDemos(_ slides: [(FirstRunPageKey, FirstRunSlide)]) async throws {
    let size = CGSize(width: 390, height: 360)
    for (page, slide) in slides {
        let host = nativeHostedView(
            FirstRunDemoContent(page: page, slide: slide)
                .padding(20)
                .frame(width: size.width, height: size.height)
                .background(BrandTokens.cardBackground)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        // macOS draws a system TabView as a thin segmented control, not the iOS tab bar.
        let minimumInk = slide.id == "songs-navigation" ? 0.0005 : 0.002
        // Redacted placeholder songs are low-contrast bars, not ink, so they count as content.
        let painted: (NativeHostedContent) -> Bool = {
            $0.inkFraction > minimumInk || $0.nonBackgroundFraction > 0.05
        }
        // Two identical blank frames before the row stagger starts would otherwise count as
        // settled, so wait until the demo has painted; looping pulses end it after the grace.
        let image = try await nativeHostedSettle(host, animationGrace: .milliseconds(400)) {
            (try? nativeHostedImage(host)).map { painted(nativeHostedContent($0)) } ?? false
        }
        _ = try nativeHostedPNG(
            image, filename: "first-run-\(slide.id).png", environment: "FST_FIRST_RUN_RENDER_OUT"
        )
        let content = nativeHostedContent(image)
        #expect(painted(content), "\(slide.id) demo painted nothing: \(content)")
    }
}

#endif
