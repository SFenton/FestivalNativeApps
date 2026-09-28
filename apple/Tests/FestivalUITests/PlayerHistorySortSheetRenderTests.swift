#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - PlayerHistorySortSheet

/// A standalone `Form`-based sheet (like Songs' Sort/Filter sheets): render its
/// content bare, without a window, per `hosted-snapshots.md`'s pitfall that
/// attaching a window makes native pickers look inactive.
@MainActor
@Test func playerHistorySortSheetPaintsEveryModeAndDirection() throws {
    let cases: [(name: String, mode: PlayerScoreSortMode, ascending: Bool)] = [
        ("date-desc", .date, false),
        ("score-asc", .score, true),
        ("accuracy-desc", .accuracy, false),
        ("season-asc", .season, true),
    ]
    let size = CGSize(width: 390, height: 500)
    var images: [String: Data] = [:]
    for scenario in cases {
        let host = nativeHostedView(
            PlayerHistorySortSheet(
                mode: scenario.mode, ascending: scenario.ascending, onApply: { _, _ in }
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .background(BrandTokens.appBackground),
            size: size
        )
        let image = try nativeHostedImage(host)
        let pixels = nativeHostedControlPixels(image)
        #expect(pixels.bright > 20)
        #expect(pixels.placeholder == 0)
        images[scenario.name] = try nativeHostedPNG(
            image, filename: "player-history-sort-\(scenario.name).png",
            environment: "FST_HISTORY_RENDER_OUT"
        )
    }
    #expect(images["date-desc"] != images["score-asc"])
    #expect(images["accuracy-desc"] != images["season-asc"])
}

/// Accessibility-size text still renders the whole real Form without truncation
/// crashes or a placeholder surface.
@MainActor
@Test func playerHistorySortSheetPaintsAtAccessibilitySize() throws {
    let size = CGSize(width: 390, height: 700)
    let host = nativeHostedView(
        PlayerHistorySortSheet(mode: .date, ascending: true, onApply: { _, _ in })
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .environment(\.dynamicTypeSize, .accessibility5)
            .background(BrandTokens.appBackground),
        size: size
    )
    let image = try nativeHostedImage(host)
    let pixels = nativeHostedControlPixels(image)
    #expect(pixels.bright > 20)
    #expect(pixels.placeholder == 0)
}
#endif
