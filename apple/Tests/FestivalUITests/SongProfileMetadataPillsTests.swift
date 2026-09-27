import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Render six source-ordered selected-player fields without a live service.
///
/// - Parameters:
///   - fields: Synthetic typed metadata, not a copied production profile.
///   - width: Available card content width.
///   - typeSize: Effective platform Dynamic Type category.
/// - Returns: Real opaque SwiftUI pixels with bounded wrapping.
/// - Throws: An ImageRenderer failure.
@MainActor
private func metadataImage(
    _ fields: [SongMetadataField], width: CGFloat,
    typeSize: DynamicTypeSize = .large
) throws -> CGImage {
    let renderer = ImageRenderer(content:
        SongProfileMetadataPills(fields: fields, songId: "fixture-pulse")
            .frame(width: width)
            .background(BrandTokens.cardBackground)
            .environment(\.dynamicTypeSize, typeSize)
    )
    renderer.scale = 1
    return try #require(renderer.cgImage)
}

/// Count actual foreground pixels inside one unwrapped, opaque native badge.
///
/// - Parameters:
///   - field: Percentile, season or difficulty badge with a distinct text color.
///   - typeSize: Normal-large or accessibility-size text scaling.
///   - foreground: Expected rendered sRGB glyph bytes.
/// - Returns: Left/right glyph-to-badge-edge distances in rendered pixels.
/// - Throws: Missing screenshot or glyph paint.
@MainActor
private func renderedBadgeInsets(
    _ field: SongMetadataField, typeSize: DynamicTypeSize,
    foreground: (Int, Int, Int)
) throws -> (left: Int, right: Int) {
    let renderer = ImageRenderer(content:
        SongMetadataFieldView(field: field, songId: "fixture-pulse")
            .background(BrandTokens.cardBackground)
            .environment(\.dynamicTypeSize, typeSize)
    )
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    let bitmap = NSBitmapImageRep(cgImage: image)
    var first = image.width
    var last = -1
    for y in 0..<image.height {
        for x in 0..<image.width {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            let actual = [
                Int((color.redComponent * 255).rounded()),
                Int((color.greenComponent * 255).rounded()),
                Int((color.blueComponent * 255).rounded()),
            ]
            if zip(actual, [foreground.0, foreground.1, foreground.2])
                .allSatisfy({ abs($0.0 - $0.1) <= 3 }) {
                first = min(first, x)
                last = max(last, x)
            }
        }
    }
    #expect(first < image.width && last >= 0)
    return (first, image.width - 1 - last)
}

/// FC, bucket, stars, season, real meter and difficulty reflow in source order.
@MainActor
@Test func selectedMetadataPillsWrapAtActualCardWidthsAndLargestType() throws {
    let fields: [SongMetadataField] = [
        .accuracy(979_000, fullCombo: true, percentageVisible: true, tint: nil),
        .percentile("Top 10%", tier: .ordinary),
        .stars(count: 5, gold: false),
        .season(9, current: true),
        .intensity(2),
        .difficulty(3),
    ]
    let narrow = try metadataImage(fields, width: 280)
    let phone = try metadataImage(fields, width: 326)
    let tablet = try metadataImage(fields, width: 756)
    let desktop = try metadataImage(fields, width: 1_100)
    let largest = try metadataImage(fields, width: 280, typeSize: .accessibility5)
    #expect(narrow.width == 280)
    #expect(phone.width == 326)
    #expect(tablet.width == 756)
    #expect(desktop.width == 1_100)
    #expect(largest.width == 280)
    #expect(narrow.height >= phone.height)
    #expect(phone.height > tablet.height)
    #expect(desktop.height == tablet.height)
    #expect(largest.height > narrow.height)
    #expect(paintedPixels(near: (255, 215, 0), in: phone, sampleStep: 1) > 40)
    #expect(paintedPixels(near: (124, 58, 237), in: phone) > 25)
    #expect(paintedPixels(near: (215, 222, 232), in: phone) > 25)
}

/// Top 1% has an italic native cue absent from the plain Top 5% outline.
@MainActor
@Test func sourceTierAndGoldStarVariantsPaintSeparately() throws {
    let one = try metadataImage([.percentile("Top 1%", tier: .topOne)], width: 160)
    let five = try metadataImage([.percentile("Top 1%", tier: .topFive)], width: 160)
    let first = try #require(
        NSBitmapImageRep(cgImage: one).representation(using: .png, properties: [:])
    )
    let second = try #require(
        NSBitmapImageRep(cgImage: five).representation(using: .png, properties: [:])
    )
    #expect(first != second)
    let stars = try metadataImage([.stars(count: 5, gold: true)], width: 160)
    #expect(paintedPixels(near: (255, 215, 0), in: stars, sampleStep: 1) > 100)
}

/// Every game tier paints its real color rather than defaulting to Expert.
@MainActor
@Test func gameDifficultyPillsPaintAllFourSourceColors() throws {
    let colors: [(Int, (Int, Int, Int))] = [
        (0, (46, 204, 113)), (1, (198, 40, 40)),
        (2, (45, 130, 230)), (3, (124, 58, 237)),
    ]
    for (tier, color) in colors {
        let image = try metadataImage([.difficulty(tier)], width: 160)
        #expect(paintedPixels(near: color, in: image) > 25)
    }
}

/// A dated label and seven-digit score must grow instead of disappearing.
@MainActor
@Test func longMetadataFieldsRemainPaintedInNarrowCards() throws {
    let score = SongMetadataFieldView(
        field: .score(1_234_567), songId: "fixture-pulse"
    )
    let scoreRenderer = ImageRenderer(content: score.frame(width: 130)
        .background(BrandTokens.cardBackground))
    scoreRenderer.scale = 1
    let digits = try #require(scoreRenderer.cgImage)
    #expect(digits.width == 130)
    let wrapped = try metadataImage([
        .lastPlayed("Last played Sep 20, 2026"),
        .difficulty(3),
    ], width: 130)
    #expect(wrapped.width == 130)
    #expect(wrapped.height > 28)
    #expect(paintedPixels(near: (124, 58, 237), in: wrapped) > 25)
}

/// A wrapped AX date must reach the card edge, not only occupy an oversized layout slot.
@MainActor
@Test func wrappedLastPlayedBackgroundReachesTrailingEdge() throws {
    for width in [CGFloat(280), 326, 360, 380, 420] {
        let image = try metadataImage([
            .difficulty(3),
            .lastPlayed("Last played Sep 20, 2026"),
        ], width: width, typeSize: .accessibility5)
        let bitmap = NSBitmapImageRep(cgImage: image)
        var rightmost = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                let channels = [
                    Int((color.redComponent * 255).rounded()),
                    Int((color.greenComponent * 255).rounded()),
                    Int((color.blueComponent * 255).rounded()),
                ]
                if zip(channels, [22, 33, 51]).allSatisfy({ abs($0.0 - $0.1) <= 3 }) {
                    rightmost = max(rightmost, x)
                }
            }
        }
        #expect(rightmost >= 0)
        #expect(image.width - 1 - rightmost <= 2)
    }
}

/// Scaled badges must give glyphs real insets without changing the Solo control.
@MainActor
@Test func selectedMetadataBadgeTextKeepsFourPixelInsetsAtLargeSizes() throws {
    let fields: [(SongMetadataField, (Int, Int, Int))] = [
        (.percentile("Top 100%", tier: .ordinary), (215, 222, 232)),
        (.percentile("Top 1%", tier: .topOne), (255, 215, 0)),
        (.season(9, current: true), (22, 33, 51)),
        (.difficulty(3), (255, 255, 255)),
        (.lastPlayed("Last played Sep 20, 2026"), (215, 222, 232)),
    ]
    for typeSize: DynamicTypeSize in [.xLarge, .accessibility3, .accessibility5] {
        for (field, foreground) in fields {
            let insets = try renderedBadgeInsets(
                field, typeSize: typeSize, foreground: foreground
            )
            #expect(insets.left >= 4)
            #expect(insets.right >= 4)
        }
    }
}
