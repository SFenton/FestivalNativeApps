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

/// Every Songs slide renders the app's real Songs UI (rows, sheets, tab bar, chips) from the
/// offline fallback songs when no session is attached.
@MainActor
@Test func nativeSongsDemosRenderRealSongsUI() async throws {
    #expect(Song.firstRunFallback.count == 3)
    let size = CGSize(width: 390, height: 360)
    for slide in FirstRunCatalog.slides(for: .songs) {
        let host = nativeHostedView(
            FirstRunDemoContent(page: .songs, slide: slide)
                .padding(20)
                .frame(width: size.width, height: size.height)
                .background(BrandTokens.cardBackground)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let image = try nativeHostedImage(host)
        _ = try nativeHostedPNG(
            image, filename: "first-run-\(slide.id).png", environment: "FST_FIRST_RUN_RENDER_OUT"
        )
        let content = nativeHostedContent(image)
        // macOS draws a system TabView as a thin segmented control, not the iOS tab bar.
        let minimumInk = slide.id == "songs-navigation" ? 0.0005 : 0.002
        #expect(content.inkFraction > minimumInk, "\(slide.id) demo painted nothing: \(content)")
    }
}

#endif
