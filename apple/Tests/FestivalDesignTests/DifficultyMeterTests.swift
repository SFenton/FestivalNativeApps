import Testing
@testable import FestivalDesign
#if os(macOS)
import AppKit
import SwiftUI
#endif

/// Seven source values have seven distinct visible filled-bar states.
@Test(arguments: Array(0...6))
func rawDifficultyStates(_ level: Int) {
    #expect(DifficultyMeter.filledBars(level: Double(level), raw: true) == level + 1)
}

/// Out-of-range web data cannot draw outside the seven-bar meter.
@Test func clampedDifficultyStates() {
    #expect(DifficultyMeter.filledBars(level: -10, raw: true) == 1)
    #expect(DifficultyMeter.filledBars(level: 50, raw: true) == 7)
    #expect(DifficultyMeter.filledBars(level: -1, raw: false) == 1)
    #expect(DifficultyMeter.filledBars(level: 9, raw: false) == 7)
    #expect(DifficultyMeter.filledBars(level: 5.9, raw: true) == 6)
    #expect(DifficultyMeter.filledBars(level: 3.5, raw: false) == 3)
    #expect(DifficultyMeter.displayLevel(level: 3.5, raw: false) == 3.5)
    #expect(DifficultyMeter.filledBars(level: .nan, raw: true) == 0)
}

#if os(macOS)
/// Render each reachable meter state and assert the actual foreground colors.
@MainActor
@Test(arguments: Array(1...7))
func renderedDifficultyBars(_ filled: Int) throws {
    let renderer = ImageRenderer(content: DifficultyMeter(level: Double(filled)))
    renderer.scale = 1
    let image = try #require(renderer.cgImage)
    #expect(image.width == 62)
    #expect(image.height == 20)

    let bitmap = NSBitmapImageRep(cgImage: image)
    for index in 0..<7 {
        let pixel = try #require(bitmap.colorAt(x: index * 9 + 4, y: 10))
        let expected = index < filled ? 1.0 : 0.4
        #expect(abs(pixel.redComponent - expected) < 0.02)
        #expect(pixel.alphaComponent > 0.95)
    }
}
#endif
