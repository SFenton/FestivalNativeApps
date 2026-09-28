#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Force `festivalGlassCapsule` onto its deterministic, opaque fallback.
///
/// Real Liquid Glass does not reliably reproduce through `NSHostingView.cacheDisplay`
/// (see `SelectedSongRowRenderTests.deterministicGlassDefaults`); each `#Test` below uses
/// its own throwaway suite so cases never share persisted state.
///
/// - Returns: A throwaway `UserDefaults` suite with `moreContrast` enabled.
@MainActor
private func deterministicScrubberGlassDefaults() -> UserDefaults {
    let suiteName = "fst-scrubber-glass-fallback-\(UUID().uuidString)"
    let storage = UserDefaults(suiteName: suiteName)!
    storage.set(true, forKey: "fst.accessibility.moreContrast")
    return storage
}

/// Render the right-edge section-index scrubber at a fixed size and text scale.
///
/// The host is sized close to the scrubber's own intrinsic content height (2026-09-28:
/// the scrubber no longer stretches to fill a `GeometryReader`-proposed height — see
/// `SongSectionIndexScrubber`'s doc comment — so a handful of short labels only occupy
/// a small natural span). A much taller host would dilute `nativeHostedControlPixels`'
/// sparse stride-4 sampling until it under-counts real glyph pixels, which is a sampling
/// artifact of an oversized canvas, not evidence of missing text.
///
/// - Parameters:
///   - sections: Labels the scrubber should paint, top to bottom.
///   - typeSize: Dynamic Type scale under test.
/// - Returns: The captured bitmap and its measured control pixels.
/// - Throws: A missing native bitmap.
@MainActor
private func renderScrubber(
    _ sections: [SongSection], typeSize: DynamicTypeSize = .large
) throws -> (image: CGImage, pixels: (bright: Int, selected: Int, placeholder: Int)) {
    let host = nativeHostedView(
        SongSectionIndexScrubber(sections: sections, onSelect: { _ in })
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .environment(\.dynamicTypeSize, typeSize)
            .defaultAppStorage(deterministicScrubberGlassDefaults())
            .background(BrandTokens.appBackground),
        size: CGSize(width: 40, height: 90)
    )
    let image = try nativeHostedImage(host)
    return (image, nativeHostedControlPixels(image))
}

/// Title/Artist letter buckets and the shared non-letter "#" bucket must paint distinct,
/// real AppKit text — never the yellow `ImageRenderer` placeholder.
@MainActor
@Test func sectionIndexScrubberPaintsTitleAndArtistLetterBuckets() throws {
    let title = [
        SongSection(id: 0, label: "#", songs: []),
        SongSection(id: 1, label: "A", songs: []),
        SongSection(id: 2, label: "F", songs: []),
        SongSection(id: 3, label: "P", songs: []),
    ]
    let (titleImage, titlePixels) = try renderScrubber(title)
    #expect(titlePixels.bright > 4)
    #expect(titlePixels.placeholder == 0)
    let titlePNG = try nativeHostedPNG(
        titleImage, filename: "section-index-title.png", environment: "FST_SECTION_INDEX_RENDER_OUT"
    )

    let artist = [
        SongSection(id: 0, label: "F", songs: []),
        SongSection(id: 1, label: "S", songs: []),
    ]
    let (artistImage, artistPixels) = try renderScrubber(artist)
    // Only two single-character labels: real content, but too few glyph pixels for
    // the sparse stride-4 sampler to guarantee hitting more than a couple of them
    // regardless of canvas size. `> 0` (never zero, i.e. never the placeholder path)
    // is the actual invariant; `placeholder == 0` below is the stronger check.
    #expect(artistPixels.bright > 0)
    #expect(artistPixels.placeholder == 0)
    let artistPNG = try nativeHostedPNG(
        artistImage, filename: "section-index-artist.png", environment: "FST_SECTION_INDEX_RENDER_OUT"
    )
    #expect(titlePNG != artistPNG)
}

/// Year buckets are numeric labels, including the missing-year "#" bucket as its own entry.
@MainActor
@Test func sectionIndexScrubberPaintsYearBucketsWithMissingYearMarker() throws {
    let years = [
        SongSection(id: 0, label: "#", songs: []),
        SongSection(id: 1, label: "2019", songs: []),
        SongSection(id: 2, label: "2024", songs: []),
        SongSection(id: 3, label: "2026", songs: []),
    ]
    let (image, pixels) = try renderScrubber(years)
    #expect(pixels.bright > 4)
    #expect(pixels.placeholder == 0)
    _ = try nativeHostedPNG(
        image, filename: "section-index-year.png", environment: "FST_SECTION_INDEX_RENDER_OUT"
    )
}

/// The control must stay legible (real painted text, no placeholder) at the largest
/// Dynamic Type size, matching the rest of Songs' accessibility-text coverage.
@MainActor
@Test func sectionIndexScrubberPaintsAtLargestDynamicType() throws {
    let sections = [
        SongSection(id: 0, label: "#", songs: []),
        SongSection(id: 1, label: "A", songs: []),
        SongSection(id: 2, label: "Z", songs: []),
    ]
    let normal = try renderScrubber(sections, typeSize: .large)
    let largest = try renderScrubber(sections, typeSize: .accessibility5)
    #expect(normal.pixels.placeholder == 0)
    #expect(largest.pixels.placeholder == 0)
    #expect(largest.pixels.bright > 0)
    _ = try nativeHostedPNG(
        normal.image, filename: "section-index-normal-text.png",
        environment: "FST_SECTION_INDEX_RENDER_OUT"
    )
    _ = try nativeHostedPNG(
        largest.image, filename: "section-index-largest-text.png",
        environment: "FST_SECTION_INDEX_RENDER_OUT"
    )
}
#endif
