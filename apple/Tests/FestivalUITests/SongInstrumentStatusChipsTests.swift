import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Render the same nine semantic states at a concrete native layout width.
///
/// - Parameters:
///   - width: Narrow or wide Songs-card content width.
///   - typeSize: Actual SwiftUI Dynamic Type environment.
///   - statuses: Source-order modes, or the nine-state comparison fixture.
/// - Returns: One screenshot generated without visiting a service.
/// - Throws: An empty ImageRenderer result.
@MainActor
private func chipImage(
    width: CGFloat, typeSize: DynamicTypeSize = .large,
    statuses: [SongInstrumentStatus] = [
        .fullCombo, .scored, .noScore, .unavailable,
        .inconsistentFullCombo, .unavailable, .noScore, .scored, .unavailable
    ]
) throws -> CGImage {
    let badges = zip(Instrument.allCases, statuses)
        .map { SongInstrumentBadge(instrument: $0.0, status: $0.1) }
    let renderer = ImageRenderer(content:
        SongInstrumentStatusChips(songId: "fixture-pulse", badges: badges)
            .frame(width: width)
            .background(BrandTokens.cardBackground)
            .environment(\.dynamicTypeSize, typeSize)
    )
    renderer.scale = 1
    return try #require(renderer.cgImage)
}

/// Count painted, nearly solid sRGB pixels instead of assuming CSS intent is visible.
///
/// - Parameters:
///   - target: Expected source-backed fill channels.
///   - image: Native SwiftUI ImageRenderer output on a real opaque card.
///   - sampleStep: Sampling density; one checks thin painted text.
/// - Returns: Sampled pixels within three channels of the source fill.
func paintedPixels(
    near target: (Int, Int, Int), in image: CGImage,
    sampleStep: Int = 3
) -> Int {
    precondition(sampleStep > 0)
    let bitmap = NSBitmapImageRep(cgImage: image)
    var count = 0
    for y in stride(from: 0, to: image.height, by: sampleStep) {
        for x in stride(from: 0, to: image.width, by: sampleStep) {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            let rgb = [
                Int((color.redComponent * 255).rounded()),
                Int((color.greenComponent * 255).rounded()),
                Int((color.blueComponent * 255).rounded()),
            ]
            if zip(rgb, [target.0, target.1, target.2])
                .allSatisfy({ abs($0.0 - $0.1) <= 3 }) {
                count += 1
            }
        }
    }
    return count
}

/// Gold, green, red, amber and muted chips must each paint a distinct fill color:
/// with the corner star/check/minus/exclamation mark removed, color is the only
/// visual cue, so every status (including the once-shared red for no-score and
/// inconsistent-FC) must be separately identifiable on an actual card.
@MainActor
@Test func nativeStatusChipsPaintSourceStatesAsDistinctColors() throws {
    let image = try chipImage(width: 390)
    #expect(image.width == 390)
    #expect(paintedPixels(near: (255, 215, 0), in: image) > 25)
    #expect(paintedPixels(near: (46, 204, 113), in: image) > 25)
    #expect(paintedPixels(near: (198, 40, 40), in: image) > 25)
    #expect(paintedPixels(near: (34, 48, 71), in: image) > 25)
    #expect(paintedPixels(near: (245, 166, 35), in: image) > 25)
    let noScore = try chipImage(width: 80, statuses: [.noScore])
    let inconsistent = try chipImage(width: 80, statuses: [.inconsistentFullCombo])
    #expect(paintedPixels(near: (198, 40, 40), in: noScore) > 25)
    #expect(paintedPixels(near: (245, 166, 35), in: inconsistent) > 25)
    #expect(paintedPixels(near: (198, 40, 40), in: inconsistent) == 0)
    let ordinaryImage = try #require(
        NSBitmapImageRep(cgImage: noScore).representation(using: .png, properties: [:])
    )
    let contradictoryImage = try #require(
        NSBitmapImageRep(cgImage: inconsistent).representation(using: .png, properties: [:])
    )
    #expect(ordinaryImage != contradictoryImage)
}

/// Narrow and accessibility widths must wrap instead of clipping status chips.
@MainActor
@Test func nativeStatusChipsReflowAtNarrowAndLargestTextWidths() throws {
    let wide = try chipImage(width: 700)
    let phone = try chipImage(width: 390)
    let narrow = try chipImage(width: 208)
    let largest = try chipImage(width: 208, typeSize: .accessibility5)
    #expect(wide.width == 700)
    #expect(phone.width == 390)
    #expect(narrow.width == 208)
    #expect(largest.width == 208)
    #expect(narrow.height > wide.height)
    #expect(largest.height > narrow.height)
    #expect(paintedPixels(near: (255, 215, 0), in: largest) > 25)
}
