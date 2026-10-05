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

/// A pill-sized material capsule (`festivalCardCapsule`, custom floating controls).
private struct CardCapsuleProbe: View {
    var body: some View {
        ZStack {
            Color.white
            Text("Row")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 280, height: 64)
                .festivalCardCapsule()
        }
    }
}

/// A section card (`FestivalGlassSection`, Settings/Profile/Statistics groups).
private struct SectionCardProbe: View {
    var body: some View {
        ZStack {
            Color.white
            FestivalGlassSection {
                Text("Row").foregroundStyle(.white)
            }
            .frame(width: 280, height: 64)
        }
    }
}

/// The material card's own layers (tint over `ultraThinMaterial`) drawn directly over
/// the same white page: what ``RowCardProbe``'s centre must match on any host.
private struct MaterialLayersProbe: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            Color.white
            shape.fill(RowCardStyle.tint(increasedContrast: false))
                .background(.ultraThinMaterial, in: shape)
                .frame(width: 280, height: 64)
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

/// Largest per-channel difference between two mean colours.
///
/// - Parameters:
///   - lhs: First mean colour (0–1).
///   - rhs: Second mean colour (0–1).
/// - Returns: The largest absolute channel difference.
private func channelDistance(
    _ lhs: (red: Double, green: Double, blue: Double),
    _ rhs: (red: Double, green: Double, blue: Double)
) -> Double {
    max(abs(lhs.red - rhs.red), abs(lhs.green - rhs.green), abs(lhs.blue - rhs.blue))
}

/// Host a probe with SwiftUI's Reduce Transparency pinned off, so the shipping
/// material branch is drawn whatever the host's system setting.
///
/// GitHub's macOS runner (issue #122) reports system Reduce Transparency on: unpinned,
/// the card correctly drew its opaque fallback there and the material check failed.
///
/// - Parameter probe: View to host over its own white page.
/// - Returns: A 320×96 pt offscreen host.
@MainActor
private func materialHost<Probe: View>(_ probe: Probe) -> NSHostingView<NativeHostedRoot<AnyView>> {
    nativeHostedView(
        AnyView(probe.environment(\._accessibilityReduceTransparency, false)),
        size: CGSize(width: 320, height: 96), forceGlassFallback: false
    )
}

/// Whether this host's captures blend a material with the view behind it.
///
/// AppKit draws materials opaque under the system Reduce Transparency setting (and
/// may without a compositing window server), whatever SwiftUI's environment says, so
/// a bare material over white then reads dark.
///
/// - Returns: True when a bare `ultraThinMaterial` over white captures bright.
/// - Throws: An unavailable capture.
@MainActor
private func hostBlendsMaterials() throws -> Bool {
    let probe = ZStack {
        Color.white
        RoundedRectangle(cornerRadius: 12).fill(.ultraThinMaterial).frame(width: 280, height: 64)
    }
    let centre = try cardCentre(try nativeHostedImage(materialHost(probe)))
    return max(centre.red, centre.green, centre.blue) >= 0.2
}

// MARK: - Tests

/// The material card (`festivalRowCard`, `festivalCard`, `festivalCardCapsule`,
/// `FestivalGlassSection`) keeps every accessibility fallback of the Liquid Glass card
/// it replaced, and no longer blanks hosted captures (issue #291).
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

    @Test("Section cards and control capsules keep the opaque fallbacks",
          arguments: [nil, "fst.accessibility.lessTransparency", "fst.accessibility.moreContrast"])
    func sectionAndCapsuleFallbacksAreOpaque(key: String?) throws {
        for probe in [AnyView(CardCapsuleProbe()), AnyView(SectionCardProbe())] {
            // nil: system Reduce Transparency (the harness's forced fallback).
            let host = nativeHostedView(
                probe.defaultAppStorage(rowCardDefaults(key)),
                size: CGSize(width: 320, height: 96), forceGlassFallback: key == nil
            )
            let centre = try cardCentre(try nativeHostedImage(host))
            #expect(max(centre.red, centre.green, centre.blue) < 0.2, "\(key ?? "system"): \(centre)")
        }
    }

    @Test("The material capsule and section card capture without blanking")
    func materialCapsuleAndSectionCapture() throws {
        for probe in [AnyView(CardCapsuleProbe()), AnyView(SectionCardProbe())] {
            let host = nativeHostedView(
                probe.defaultAppStorage(rowCardDefaults(nil)),
                size: CGSize(width: 320, height: 96), forceGlassFallback: false
            )
            // Tinted Liquid Glass blanks the whole capture; the white page must remain.
            #expect(nativeHostedControlPixels(try nativeHostedImage(host)).bright > 0)
        }
    }

    @Test("The material card captures: the white page and label stay visible")
    func materialCardCaptures() throws {
        let host = materialHost(RowCardProbe().defaultAppStorage(rowCardDefaults(nil)))
        // Tinted Liquid Glass blanked the whole capture (see `NativeHostedRoot`); the
        // material card must not, and must not fall back to the opaque card.
        let pixels = nativeHostedControlPixels(try nativeHostedImage(host))
        #expect(pixels.bright > 0)
        let centre = try cardCentre(try nativeHostedImage(host))

        // Host-independent: the card centre is its own material layers, not the opaque
        // card, even where AppKit draws the material itself opaque (issue #122).
        let layers = try cardCentre(try nativeHostedImage(materialHost(MaterialLayersProbe())))
        let opaque = try cardCentre(try nativeHostedImage(nativeHostedView(
            RowCardProbe(), size: CGSize(width: 320, height: 96), forceGlassFallback: true
        )))
        let blends = try hostBlendsMaterials()
        let system = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        let context = "system Reduce Transparency \(system), blends \(blends)"
        let toLayers = channelDistance(centre, layers)
        let toOpaque = channelDistance(centre, opaque)
        #expect(toLayers <= 0.01, "card \(centre) vs material layers \(layers); \(context)")
        #expect(toLayers < toOpaque, "card \(centre) nearer opaque \(opaque) than \(layers); \(context)")

        // Where the host blends materials (developer Macs), the white page must also
        // show through the card.
        if blends {
            #expect(max(centre.red, centre.green, centre.blue) >= 0.2, "\(centre); \(context)")
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
