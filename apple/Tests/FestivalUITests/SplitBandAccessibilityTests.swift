#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Split band accessibility (issue #344, backfilled by #480)

/// The band between an on-demand split's panes (`.agents/patterns/split-panes.md` R1–R2,
/// issue #344): it draws no line, except a 1 pt hairline at a midpoint while the system's
/// **or the app's** Increase Contrast is on, never on the iPhone Duo hinge. These hosted
/// checks pin what that band means for assistive technologies on every Apple platform
/// (the same ``OnDemandSplitLayout`` runs on iPad, iPhone Duo and the Mac content area):
/// the hairline under each contrast setting, the band never being an accessibility element
/// or a splitter (it is fixed, not draggable), and both panes reading leading then
/// trailing, at the default text size and at AX5.
///
/// The app's Increase Contrast toggle (`fst.accessibility.moreContrast`) used to leave
/// the band clear (#480), unlike every other contrast consumer (`FestivalGlassSettings`,
/// `ScrollEdgeHardEdge`; same defect as #461).
///
/// HIG Accessibility: "provide a higher-contrast scheme when Increase Contrast is on"
/// (should); HIG Layout: "Group related information/functions using negative space,
/// containers, or separators" (should).
@MainActor
@Suite(.serialized)
struct SplitBandAccessibilityTests {
    // MARK: - Fixture

    /// The contrast settings the band follows.
    enum Contrast: String, CaseIterable, CustomTestStringConvertible {
        case standard, systemIncreaseContrast, appIncreaseContrast

        var testDescription: String { rawValue }

        /// Whether the band should draw its hairline at a midpoint.
        var drawsMidpointLine: Bool { self != .standard }
    }

    /// The band's position.
    enum Band: String, CaseIterable, CustomTestStringConvertible {
        /// iPad, Mac, a flat iPhone Duo: a 1 pt band at the midpoint.
        case midpoint
        /// iPhone Duo in book pose: the hinge itself.
        case hinge

        var testDescription: String { rawValue }
    }

    static let size = CGSize(width: 801, height: 240)

    /// The split's geometry for `band` in ``size``.
    static func geometry(_ band: Band) throws -> OnDemandSplitPolicy.Geometry {
        try #require(OnDemandSplitPolicy.geometry(.init(
            container: CGRect(origin: .zero, size: size), isLandscape: true, isRegular: true,
            hinge: band == .hinge ? CGRect(x: 395, y: 0, width: 11, height: size.height) : nil
        )))
    }

    /// One pane: a heading and a button, centred, over black.
    static func pane(_ name: String) -> some View {
        VStack(spacing: 12) {
            Text("\(name) title")
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("fst.test.\(name).title")
            Button("Open \(name)") {}
                .accessibilityIdentifier("fst.test.\(name).button")
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }

    /// Host the split with both panes open under `contrast` and `textSize`.
    ///
    /// - Parameters:
    ///   - band: Midpoint or hinge band.
    ///   - contrast: The contrast setting under test.
    ///   - textSize: Dynamic Type size for the panes' text.
    ///   - body: Receives the laid-out host and a capture of it while its window and
    ///     defaults are alive.
    static func withSplit<Result>(
        _ band: Band, _ contrast: Contrast, textSize: DynamicTypeSize = .large,
        _ body: (NSView, () throws -> CGImage) throws -> Result
    ) throws -> Result {
        let suite = "fst.tests.split-band.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(contrast == .appIncreaseContrast, forKey: "fst.accessibility.moreContrast")
        defaults.set(true, forKey: "fst.accessibility.reduceMotion")
        let content = OnDemandSplitLayout(geometry: try geometry(band)) {
            pane("leading")
        } trailing: {
            pane("trailing")
        }
        .background(Color.black)
        .environment(\._colorSchemeContrast, contrast == .systemIncreaseContrast ? .increased : .standard)
        .dynamicTypeSize(textSize)
        .defaultAppStorage(defaults)
        .preferredColorScheme(.dark)
        let host = nativeHostedView(content, size: size)
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        return try body(host) { try nativeHostedImage(host) }
    }

    /// The brightest red channel across the band's columns, in a row clear of the panes'
    /// centred content.
    static func bandBrightness(_ band: Band, _ contrast: Contrast) throws -> UInt8 {
        let geometry = try geometry(band)
        return try withSplit(band, contrast) { _, capture in
            let image = try capture()
            let width = image.width, height = image.height
            var pixels = [UInt8](repeating: 0, count: width * height * 4)
            let context = try #require(CGContext(
                data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let scale = CGFloat(width) / size.width
            let bandStart = Int(((geometry.dividerMidX - geometry.dividerWidth / 2 - 2) * scale).rounded(.down))
            let bandEnd = Int(((geometry.dividerMidX + geometry.dividerWidth / 2 + 2) * scale).rounded(.up))
            let row = Int((20 * scale).rounded())
            return (max(0, bandStart)..<min(width, bandEnd)).map { pixels[(row * width + $0) * 4] }.max() ?? 0
        }
    }

    // MARK: - Contrast

    /// The band is clear normally; under the system's or the app's Increase Contrast a
    /// midpoint band draws its hairline, and the hinge never does (R1, R2).
    @Test(arguments: Band.allCases, Contrast.allCases)
    func bandDrawsHairlineOnlyUnderIncreaseContrastAtAMidpoint(band: Band, contrast: Contrast) throws {
        let brightest = try Self.bandBrightness(band, contrast)
        if band == .midpoint, contrast.drawsMidpointLine {
            #expect(brightest > 25, "\(band)/\(contrast): a visible hairline between the panes (\(brightest))")
        } else {
            #expect(brightest < 8, "\(band)/\(contrast): no line between the panes (\(brightest))")
        }
        #expect(OnDemandSplitPolicy.drawsDividerLine(
            try Self.geometry(band), increasedContrast: contrast.drawsMidpointLine
        ) == (band == .midpoint && contrast.drawsMidpointLine))
    }

    // MARK: - Tree and reading order

    /// Whatever the band draws, assistive technologies never reach it: it is not an
    /// element and nothing reads as a splitter (the panes are fixed, not resizable). The
    /// leading pane's heading and button read before the trailing pane's, every control is
    /// named, and each button keeps a full target clear of the band, at the default size
    /// and at AX5.
    @Test(arguments: Band.allCases, Contrast.allCases)
    func bandIsNeverAnAccessibilityElementAndPanesReadInOrder(band: Band, contrast: Contrast) throws {
        let geometry = try Self.geometry(band)
        for textSize in [DynamicTypeSize.large, .accessibility5] {
            try Self.withSplit(band, contrast, textSize: textSize) { host, _ in
                let label = "\(band)/\(contrast)/\(textSize)"
                let nodes = macAccessibilityTree(host, navigationOrder: true)
                let elements = nodes.filter(\.isElement)
                #expect(!elements.contains { $0.identifier == "fst.split.divider" }, "\(label): the band is decorative")
                #expect(!nodes.contains { $0.role == "AXSplitter" || $0.role == "AXSplitGroup" },
                        "\(label): no splitter for VoiceOver to announce")
                let order = elements.map(\.identifier).filter { $0.hasPrefix("fst.test.") }
                #expect(order == [
                    "fst.test.leading.title", "fst.test.leading.button",
                    "fst.test.trailing.title", "fst.test.trailing.button",
                ], "\(label): leading pane, then trailing pane: \(order)")
                let headings = elements.filter { $0.identifier.hasSuffix(".title") }
                #expect(headings.allSatisfy { $0.role == "AXHeading" }, "\(label): pane titles are headings: \(headings)")
                #expect(macAccessibilityFindings(elements) == [], "\(label)")
                let bandMin = geometry.dividerMidX - geometry.dividerWidth / 2
                let bandMax = geometry.dividerMidX + geometry.dividerWidth / 2
                let leading = try #require(nativeHostedAccessibilityFrame("fst.test.leading.button", in: host))
                let trailing = try #require(nativeHostedAccessibilityFrame("fst.test.trailing.button", in: host))
                #expect(leading.maxX <= bandMin && trailing.minX >= bandMax,
                        "\(label): the band overlaps no target (\(leading), \(trailing), band \(bandMin)…\(bandMax))")
            }
        }
    }
}
#endif
