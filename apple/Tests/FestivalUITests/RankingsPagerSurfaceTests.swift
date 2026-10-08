#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixture

/// Transparency and contrast settings the pager must follow exactly as the row cards do.
enum PagerSurfaceMode: String, CaseIterable, CustomTestStringConvertible {
    case standard, systemReduceTransparency, lessTransparency, moreContrast

    var testDescription: String { rawValue }

    /// Whether the shared card draws its opaque accessibility fallback.
    var opaque: Bool { self != .standard }
}

/// One capture: the pager's surface pixels along a line through its controls, above
/// their glyphs, and a row card's centre pixel, both over the same solid backdrop.
private struct PagerSurfaceSample {
    /// Surface pixels (RGB 0–255) where the scan line crosses an arrow or the badge.
    let pager: [(Int, Int, Int)]
    /// The row card's centre pixel.
    let row: (Int, Int, Int)
    /// Pixels per point.
    let scale: Double
}

/// Height of ``RankingsPagerView``: 8 pt above and below its 44 pt controls.
private let pagerHeight: CGFloat = 60

/// Render the pager above a row card over `backdrop` and sample both.
///
/// - Parameters:
///   - mode: Accessibility setting under test.
///   - backdrop: Solid page colour behind both surfaces.
/// - Returns: The sampled pixels.
@MainActor
private func samplePagerSurface(_ mode: PagerSurfaceMode, backdrop: Color) throws -> PagerSurfaceSample {
    let suite = "fst.tests.pager-surface.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(mode == .lessTransparency, forKey: "fst.accessibility.lessTransparency")
    defaults.set(mode == .moreContrast, forKey: "fst.accessibility.moreContrast")
    let size = CGSize(width: 402, height: pagerHeight + 44)
    let content = ZStack(alignment: .top) {
        backdrop
        VStack(spacing: 0) {
            RankingsPagerView(page: 1, totalPages: 3, idPrefix: "fst.test-pager") { _ in }
                .frame(height: pagerHeight)
            Color.clear
                .frame(height: 44)
                .festivalCard(cornerRadius: 12)
                .padding(.horizontal, 16)
        }
    }
    .environment(\._accessibilityReduceTransparency, mode == .systemReduceTransparency)
    .defaultAppStorage(defaults)
    .preferredColorScheme(.dark)
    // The standard material card must render for real; only the glass fallback is forced off.
    let host = nativeHostedView(content, size: size, forceGlassFallback: false)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try nativeHostedImage(host)

    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let scale = CGFloat(height) / size.height
    func rgb(_ x: Int, _ yPoints: CGFloat) -> (Int, Int, Int) {
        // CGContext rows run bottom-up.
        let y = height - 1 - Int((yPoints * scale).rounded())
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }
    // 6 pt into the controls: inside every 44 pt circle and the badge, above the glyphs.
    let lineY: CGFloat = 8 + 6
    let page = rgb(2, lineY)
    let pager = (0..<width).map { rgb($0, lineY) }.filter { distance($0, page) > 24 }
    return PagerSurfaceSample(pager: pager, row: rgb(width / 2, pagerHeight + 22), scale: Double(scale))
}

/// Largest per-channel difference between two pixels.
private func distance(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
    max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
}

// MARK: - Tests

/// The pager's arrows and `page / total` badge wear the row card's surface: same fill,
/// translucency and contrast fallback as the rows beside them (issue #319). The old
/// opaque navy `PagerPlate` read as a different control over the rows' frosted cards.
@MainActor
@Test(arguments: PagerSurfaceMode.allCases)
func pagerSurfaceMatchesTheRowCard(mode: PagerSurfaceMode) throws {
    let sample = try samplePagerSurface(mode, backdrop: Color(red: 0.85, green: 0.3, blue: 0.2))
    // Five controls cross the line; each spans ≥ 28 pt there, minus edges.
    #expect(Double(sample.pager.count) >= 5 * 24 * sample.scale, "pager surface not found")
    let matching = sample.pager.filter { distance($0, sample.row) <= 10 }.count
    let share = Double(matching) / Double(max(1, sample.pager.count))
    #expect(share >= 0.85, "\(mode): \(Int(share * 100))% of pager pixels match the row card \(sample.row)")
}

/// Reduce Transparency and both in-app contrast settings make the pager opaque like the
/// rows: its surface no longer depends on the page behind it.
@MainActor
@Test(arguments: PagerSurfaceMode.allCases.filter(\.opaque))
func pagerSurfaceTurnsOpaqueWithTheRowCard(mode: PagerSurfaceMode) throws {
    let warm = try samplePagerSurface(mode, backdrop: Color(red: 0.85, green: 0.3, blue: 0.2))
    let cool = try samplePagerSurface(mode, backdrop: Color(red: 0.2, green: 0.5, blue: 0.9))
    #expect(distance(warm.row, cool.row) <= 3)
    let opaqueRow = warm.row
    let warmShare = Double(warm.pager.filter { distance($0, opaqueRow) <= 10 }.count) / Double(max(1, warm.pager.count))
    let coolShare = Double(cool.pager.filter { distance($0, opaqueRow) <= 10 }.count) / Double(max(1, cool.pager.count))
    #expect(warmShare >= 0.85 && coolShare >= 0.85, "\(mode): warm \(warmShare), cool \(coolShare)")
}

// MARK: - Duo placement (issue #345)

/// The horizontal span (points) of the pager's controls rendered `width` wide under `layout`.
@MainActor
private func pagerSpan(width: CGFloat, layout: DeviceLayout) async throws -> ClosedRange<CGFloat> {
    let size = CGSize(width: width, height: pagerHeight)
    let backdrop = Color(red: 0.85, green: 0.3, blue: 0.2)
    let content = ZStack(alignment: .top) {
        backdrop
        RankingsPagerView(page: 2, totalPages: 48, idPrefix: "fst.test-pager") { _ in }
            .frame(height: pagerHeight)
    }
    .environment(\.deviceLayout, layout)
    .preferredColorScheme(.dark)
    let host = nativeHostedView(content, size: size, forceGlassFallback: false)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host)
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let scale = CGFloat(height) / size.height
    let y = height - 1 - Int(((8 + 22) * scale).rounded())
    func rgb(_ x: Int) -> (Int, Int, Int) {
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }
    let page = rgb(1)
    let columns = (0..<width).filter { distance(rgb($0), page) > 24 }
    let first = try #require(columns.first), last = try #require(columns.last)
    return CGFloat(first) / scale...CGFloat(last) / scale
}

/// Unfolded in landscape the pager sits whole on the screen beside the trailing
/// vertical bar (issue #345): beyond the free space's midpoint flat (owner #361), where
/// the board's columns meet; elsewhere it stays centred.
@MainActor
@Test func pagerMovesBesideTheVerticalBarWhenUnfolded() async throws {
    let unfolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 21, trailing: 71),
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    #expect(unfolded.splitHinge == nil)
    let divide = try #require(unfolded.screenDivide())
    #expect(divide.minX == 440)
    let moved = try await pagerSpan(width: 880, layout: unfolded)
    #expect(moved.lowerBound > divide.maxX, "pager \(moved) crosses the free-space midline at \(divide.minX)")
    // Centred on the trailing screen (440…880), within a point or two.
    #expect(abs((moved.lowerBound + moved.upperBound) / 2 - (divide.maxX + 880) / 2) <= 2)

    let centred = try await pagerSpan(width: 880, layout: .standardPhone)
    #expect(abs((centred.lowerBound + centred.upperBound) / 2 - 440) <= 2)
}
#endif
