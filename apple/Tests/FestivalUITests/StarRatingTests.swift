import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Semantics

@Test("Six stars draw five gold stars; lower counts draw that many white stars, at least one")
func starRatingDisplayMatchesWebMiniStars() {
    #expect(StarRating.display(stars: 6, gold: false) == (5, true))
    #expect(StarRating.display(stars: 7, gold: false) == (5, true))
    #expect(StarRating.display(stars: 5, gold: false) == (5, false))
    #expect(StarRating.display(stars: 3, gold: false) == (3, false))
    #expect(StarRating.display(stars: 0, gold: false) == (1, false))
    #expect(StarRating.display(stars: 2, gold: true) == (5, true))
}

@Test("Accessibility labels follow the web's starCount / goldStarCount strings")
func starRatingAccessibilityLabels() {
    #expect(StarRating.accessibilityLabel(count: 1, gold: false) == "1 star")
    #expect(StarRating.accessibilityLabel(count: 4, gold: false) == "4 stars")
    #expect(StarRating.accessibilityLabel(count: 5, gold: true) == "5 gold stars")
    #expect(StarRating.assetName(gold: true) == "star_gold")
    #expect(StarRating.assetName(gold: false) == "star_white")
}

// MARK: - Rendering

/// Render a star row and count gold-ish and white-ish painted pixels.
///
/// - Parameter view: Star row to render on a black backdrop.
/// - Returns: Gold and white pixel counts and the rendered width.
/// - Throws: An empty ImageRenderer result.
@MainActor
private func starPixels(_ view: StarRating) throws -> (gold: Int, white: Int, width: Int) {
    let renderer = ImageRenderer(content: view.background(Color.black))
    renderer.scale = 2
    let image = try #require(renderer.cgImage)
    let bitmap = NSBitmapImageRep(cgImage: image)
    var gold = 0
    var white = 0
    for x in 0..<bitmap.pixelsWide {
        for y in 0..<bitmap.pixelsHigh {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
            if r > 0.8, g > 0.6, b < 0.35 { gold += 1 }
            if r > 0.85, g > 0.85, b > 0.85 { white += 1 }
        }
    }
    return (gold, white, bitmap.pixelsWide)
}

@MainActor
@Test("Bundled star images render: gold for six stars, white otherwise")
func starRatingRendersBundledArtwork() throws {
    let gold = try starPixels(StarRating(stars: 6))
    #expect(gold.gold > 50)
    #expect(gold.gold > gold.white)

    let white = try starPixels(StarRating(stars: 3))
    #expect(white.white > 50)
    #expect(white.gold < 5)

    // Five inline stars (14 pt, 2 pt gap) are wider than three; mini circles are wider still.
    let five = try starPixels(StarRating(stars: 5))
    let mini = try starPixels(StarRating(stars: 5, style: .mini))
    #expect(five.width > white.width)
    #expect(mini.width > five.width)
}
