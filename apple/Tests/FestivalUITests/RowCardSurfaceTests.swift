#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// A leaderboard-row-sized ``RankingRowSurface`` over a white page.
private struct RankingRowProbe: View {
    var body: some View {
        ZStack {
            Color.white
            Text("Row")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 280, height: 64)
                .modifier(RankingRowSurface(isSelected: false))
        }
    }
}

/// A Song-row-sized card with one bright label over a white page.
private struct RowCardProbe: View {
    var body: some View {
        ZStack {
            Color.white
            Text("Row")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 280, height: 64)
                .festivalRowCard(cornerRadius: 12)
        }
    }
}

/// Throwaway defaults with one in-app accessibility toggle switched on.
///
/// - Parameter key: `fst.accessibility.*` key to enable, or nil for none.
/// - Returns: An isolated `UserDefaults` suite.
@MainActor
private func rowCardDefaults(_ key: String?) -> UserDefaults {
    let storage = UserDefaults(suiteName: "fst-row-card-\(UUID().uuidString)")!
    if let key { storage.set(true, forKey: key) }
    return storage
}

/// Mean colour of the card's centre band (away from the label and rim).
///
/// - Parameter image: 320×96 pt capture of ``RowCardProbe``.
/// - Returns: Mean red, green and blue (0–1).
/// - Throws: An empty crop.
@MainActor
private func cardCentre(_ image: CGImage) throws -> (red: Double, green: Double, blue: Double) {
    let scale = Double(image.width) / 320
    let rect = CGRect(x: 230 * scale, y: 40 * scale, width: 40 * scale, height: 16 * scale)
    let crop = try #require(image.cropping(to: rect.integral))
    var sum = (0.0, 0.0, 0.0)
    var count = 0.0
    nativeHostedForEachSample(crop) { red, green, blue in
        sum.0 += red; sum.1 += green; sum.2 += blue; count += 1
    }
    let samples = try #require(count > 0 ? count : nil)
    return (sum.0 / samples, sum.1 / samples, sum.2 / samples)
}

/// Whether this host's captures blend a material with the view behind it.
///
/// Some CI runners (GitHub `xcode-27-arm64`, issue #122) draw an offscreen material
/// opaque without sampling its backdrop, so a plain material over white reads dark.
///
/// - Returns: True when a bare `ultraThinMaterial` over white captures bright.
/// - Throws: An unavailable capture.
@MainActor
private func hostBlendsMaterials() throws -> Bool {
    let probe = ZStack {
        Color.white
        RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).frame(width: 280, height: 64)
    }
    let host = nativeHostedView(probe, size: CGSize(width: 320, height: 96), forceGlassFallback: false)
    let centre = try cardCentre(try nativeHostedImage(host))
    return max(centre.red, centre.green, centre.blue) >= 0.2
}

// MARK: - Tests

/// The Song row card (`festivalRowCard`) keeps every accessibility fallback of the
/// Liquid Glass card it replaced, and no longer blanks hosted captures.
@MainActor
@Suite struct RowCardSurfaceTests {
    @Test("System Reduce Transparency draws the opaque card")
    func systemReduceTransparencyIsOpaque() throws {
        let host = nativeHostedView(RowCardProbe(), size: CGSize(width: 320, height: 96))
        let centre = try cardCentre(try nativeHostedImage(host))
        #expect(max(centre.red, centre.green, centre.blue) < 0.2, "\(centre)")
    }

    @Test("In-app Reduce Transparency and Increase Contrast draw the opaque card",
          arguments: ["fst.accessibility.lessTransparency", "fst.accessibility.moreContrast"])
    func inAppTogglesAreOpaque(key: String) throws {
        let host = nativeHostedView(
            RowCardProbe().defaultAppStorage(rowCardDefaults(key)),
            size: CGSize(width: 320, height: 96), forceGlassFallback: false
        )
        let centre = try cardCentre(try nativeHostedImage(host))
        #expect(max(centre.red, centre.green, centre.blue) < 0.2, "\(centre)")
    }

    @Test("The material card captures: the white page and label stay visible")
    func materialCardCaptures() throws {
        let host = nativeHostedView(
            RowCardProbe().defaultAppStorage(rowCardDefaults(nil)),
            size: CGSize(width: 320, height: 96), forceGlassFallback: false
        )
        // Tinted Liquid Glass blanked the whole capture (see `NativeHostedRoot`); the
        // material card must not, and must not fall back to the opaque card.
        let pixels = nativeHostedControlPixels(try nativeHostedImage(host))
        #expect(pixels.bright > 0)
        let centre = try cardCentre(try nativeHostedImage(host))
        if try hostBlendsMaterials() {
            #expect(max(centre.red, centre.green, centre.blue) >= 0.2, "\(centre)")
        } else {
            withKnownIssue("This host draws materials without their backdrop (#122)") {
                #expect(max(centre.red, centre.green, centre.blue) >= 0.2, "\(centre)")
            }
        }
    }

    @Test("Leaderboard rows draw the material card, not per-row Liquid Glass (issue #295)")
    func rankingRowUsesMaterialCard() throws {
        // A per-row `glassEffect` skipped the staggered load-in fade, so the selected
        // player's non-glass row arrived last. Live tinted glass blanks this capture;
        // the shared material card keeps the page and label.
        let host = nativeHostedView(
            RankingRowProbe().defaultAppStorage(rowCardDefaults(nil)),
            size: CGSize(width: 320, height: 96), forceGlassFallback: false
        )
        #expect(nativeHostedControlPixels(try nativeHostedImage(host)).bright > 0)
    }
}
#endif
