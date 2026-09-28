#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Carousel slide/page states

/// A lone slide is simultaneously the first and last: Skip is hidden and the
/// trailing button reads "Done" (`fst.first-run.done`), matching `isLastSlide`.
@MainActor
@Test func firstRunCarouselSingleSlideShowsDoneNotSkip() throws {
    var finished = false
    let slide = FirstRunSlide(
        id: "songs-song-list", version: 1, title: "Browse Every Song",
        description: "Search, sort and filter the full catalogue.", gate: .always
    )
    let size = CGSize(width: 390, height: 700)
    let host = nativeHostedView(
        FirstRunCarouselView(page: .songs, slides: [slide]) { finished = true }
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "first-run-single-slide.png", environment: "FST_FIRST_RUN_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
    #expect(!finished, "onFinish must only fire from a user action, never on render")
}

/// A multi-slide carousel starts on its first slide with Skip visible and "Next"
/// as the trailing action, and the shown title/description match slide zero.
@MainActor
@Test func firstRunCarouselMultiSlideStartsOnFirstSlideWithSkipAndNext() throws {
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
    let host = nativeHostedView(
        FirstRunCarouselView(page: .songs, slides: slides) {}
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "first-run-multi-slide.png", environment: "FST_FIRST_RUN_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
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
@Test func firstRunSettingsSectionListsEveryRegisteredPage() throws {
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
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "first-run-settings.png", environment: "FST_FIRST_RUN_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
    #expect(FirstRunCenter.registeredPages.count == FirstRunPageKey.allCases.count)
}
#endif
