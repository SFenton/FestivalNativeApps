#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalUI
import FestivalDesign

// MARK: - Sampling

/// One sRGB pixel, 0–255 per channel.
private struct FieldPixel {
    let red: Int, green: Int, blue: Int

    /// Largest per-channel difference from `other`.
    func distance(to other: FieldPixel) -> Int {
        max(abs(red - other.red), abs(green - other.green), abs(blue - other.blue))
    }

    /// The saturated red backdrop showing through.
    var isBackdrop: Bool { red > 120 && green < 80 && blue < 80 }
}

/// `BrandTokens.cardBackground`, the opaque fallback fill.
private let cardBackground = FieldPixel(red: 11, green: 18, blue: 32)
/// `BrandTokens.borderSubtle`, the opaque fallback stroke.
private let borderSubtle = FieldPixel(red: 30, green: 42, blue: 58)

extension NativeHostedPixels {
    /// The pixel at `point` (host points) of a capture of a `hostWidth`-point host.
    fileprivate func pixel(at point: CGPoint, hostWidth: CGFloat) -> FieldPixel {
        let scale = CGFloat(width) / hostWidth
        let x = min(width - 1, max(0, Int(point.x * scale)))
        let y = min(height - 1, max(0, Int(point.y * scale)))
        return withBytes { bytes in
            let index = (y * width + x) * 4
            return FieldPixel(red: Int(bytes[index]), green: Int(bytes[index + 1]), blue: Int(bytes[index + 2]))
        }
    }
}

// MARK: - Surface

/// Issue #358, surface-materials R4: the iPhone Duo bottom search field (Songs' Filter
/// Songs and the Search tab's field) wears Liquid Glass by default, and system Reduce
/// Transparency, system Increase Contrast and the app's Reduce Transparency and
/// Increase Contrast toggles each turn it into the opaque `cardBackground` field with
/// a `borderSubtle` border and readable text, over a saturated backdrop that would
/// show through any translucent surface.
@MainActor
@Test(.serialized, arguments: BottomChromeFadeMode.allCases)
func bottomSearchFieldIsOpaqueAndBorderedUnderAccessibilitySettings(mode: BottomChromeFadeMode) async throws {
    let (defaults, suite) = mode.storage()
    defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let size = CGSize(width: 420, height: 200)
    let identifier = "fst.test.bottom-search-field"
    let host = nativeHostedView(
        mode.system(
            ZStack(alignment: .bottom) {
                Color(.sRGB, red: 1, green: 0, blue: 0)
                BottomSearchField(
                    text: .constant("Song"), prompt: "Filter Songs", accessibilityLabel: "Filter Songs",
                    identifier: identifier, clearIdentifier: "\(identifier).clear", hinge: nil
                )
            }
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .defaultAppStorage(defaults)
        ),
        size: size, forceGlassFallback: false
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host) { nativeHostedAccessibilityFrame(identifier, in: host) != nil }
    let text = try #require(nativeHostedAccessibilityFrame(identifier, in: host))
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "bottom-search-field-\(mode.rawValue).png", environment: "FST_SEARCH_RENDER_OUT")
    let pixels = NativeHostedPixels(image)

    // The capsule starts at the column margin; sample just inside it, before the icon.
    let margin = BottomSearchFieldPlacement.margin
    let interior = pixels.pixel(at: CGPoint(x: margin + 7, y: text.midY), hostWidth: size.width)
    guard mode.hardEdge else {
        #expect(interior.distance(to: cardBackground) > 20, "default Liquid Glass is not the opaque fill: \(interior)")
        return
    }
    #expect(interior.distance(to: cardBackground) <= 6, "opaque cardBackground fill: \(interior)")

    // A blank column between the text and the clear button: opaque fill from the
    // centre up to a borderSubtle stroke, then the backdrop.
    let column = size.width / 2 + 40
    var y = text.midY
    var fillSamples = 0
    var sawBorder = false
    while y > 0 {
        let pixel = pixels.pixel(at: CGPoint(x: column, y: y), hostWidth: size.width)
        if pixel.isBackdrop { break }
        if pixel.distance(to: cardBackground) <= 6 { fillSamples += 1 }
        if pixel.distance(to: borderSubtle) <= 8 { sawBorder = true }
        y -= 0.5
    }
    #expect(fillSamples > 20, "the fill spans the field's upper half")
    #expect(sawBorder, "a borderSubtle stroke edges the field")

    // No backdrop anywhere inside the capsule, and the field's text is bright on it.
    let inside = CGRect(x: margin + 14, y: text.midY - 10, width: size.width - 2 * margin - 28, height: 20)
    var bleed = 0
    for px in stride(from: inside.minX, to: inside.maxX, by: 2) {
        for py in stride(from: inside.minY, to: inside.maxY, by: 2) {
            if pixels.pixel(at: CGPoint(x: px, y: py), hostWidth: size.width).isBackdrop { bleed += 1 }
        }
    }
    #expect(bleed == 0, "the backdrop never shows through the opaque field")
    #expect(nativeHostedBrightSamples(in: text, of: image, hostSize: size) > 0, "the field's text is readable")
}
#endif
