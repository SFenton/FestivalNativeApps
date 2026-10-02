#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Host the Sort sheet with and without the selected-player "Filtered Instrument Sort
/// Mode" section (Score / Percentile / Stars), including a chosen player mode.
@MainActor
@Test func songsSortSheetPaintsPlayerModesOnlyWhenOffered() throws {
    let size = CGSize(width: 390, height: 1100)
    var images: [String: Data] = [:]
    for (name, mode, offered) in [
        ("catalogue-only", SongSortMode.title, [SongSortMode]()),
        ("player-modes", .title, SongSortMode.playerChartModes),
        ("player-stars-chosen", .stars, SongSortMode.playerChartModes),
        ("player-score-only", .score, [.score]),
    ] {
        let host = nativeHostedView(
            SongsSortSheet(mode: mode, ascending: true, playerModes: offered) { _, _ in }
                .preferredColorScheme(.dark)
                .tint(BrandTokens.accentBlue)
                .background(BrandTokens.appBackground),
            size: size
        )
        let image = try nativeHostedImage(host)
        let pixels = nativeHostedControlPixels(image)
        #expect(pixels.bright > 20 && pixels.placeholder == 0)
        images[name] = try nativeHostedPNG(
            image, filename: "songs-sort-\(name).png", environment: "FST_SORT_RENDER_OUT"
        )
    }
    #expect(images["catalogue-only"] != images["player-modes"])
    #expect(images["player-modes"] != images["player-stars-chosen"])
    #expect(images["player-modes"] != images["player-score-only"])
}

/// Host the Filter sheet's Percentile and Stars sections: absent without a Songs
/// instrument, present (and expanded when a bucket is hidden) with one.
@MainActor
@Test func songsFilterSheetPaintsBucketSectionsWithAnInstrument() throws {
    let size = CGSize(width: 390, height: 2600)
    let visible: Set<Instrument> = [.lead, .drums]
    let hiddenBuckets = SongPlayerScoreFilter().showingOnlyStars(6).settingPercentile(0, included: false)
    var images: [String: Data] = [:]
    for (name, instrument, saved) in [
        ("no-instrument", Instrument?.none, SongPlayerScoreFilter()),
        ("lead-default", Instrument?.some(.lead), SongPlayerScoreFilter()),
        ("lead-buckets", Instrument?.some(.lead), hiddenBuckets),
    ] {
        let host = nativeHostedView(
            SongsFilterSheet(
                showShop: true, shopAvailable: true,
                appliedPlayerFilter: saved,
                appliedInstrument: instrument, visibleInstruments: visible,
                selectedPlayer: true, scoreAvailable: true,
                onApply: { _, _, _ in }
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .background(BrandTokens.appBackground),
            size: size
        )
        let image = try nativeHostedImage(host)
        let pixels = nativeHostedControlPixels(image)
        // macOS hosts the toggles as checkboxes; their unchecked fill reads as
        // "placeholder" pixels, so only brightness is checked here.
        #expect(pixels.bright > 20)
        images[name] = try nativeHostedPNG(
            image, filename: "songs-filter-\(name).png", environment: "FST_FILTER_RENDER_OUT"
        )
    }
    #expect(images["no-instrument"] != images["lead-default"])
    #expect(images["lead-default"] != images["lead-buckets"])
}
#endif
