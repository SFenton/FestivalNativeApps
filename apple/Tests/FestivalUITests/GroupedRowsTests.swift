import SwiftUI
import Testing
@testable import FestivalUI
import FestivalDesign
#if os(macOS)
import AppKit
import CoreGraphics
#endif

// MARK: - Grouped-row rules

/// Repeated entries share one ``FestivalGlassSection`` card (issue #381): grouped rows draw
/// no card of their own and the selected player's row becomes a flat band.
@Suite struct GroupedRowsTests {
    @Test("Inside a group a row drops its card; the selected row is a flat band")
    func groupedTreatment() {
        for card in [true, false] {
            #expect(RankingRowSurface.treatment(isSelected: false, card: card, grouped: true) == .bare)
            #expect(RankingRowSurface.treatment(isSelected: true, card: card, grouped: true) == .selectedBand)
        }
    }

    @Test("Outside a group the per-row card and the rounded selected card stay")
    func ungroupedTreatment() {
        #expect(RankingRowSurface.treatment(isSelected: false, card: true, grouped: false) == .card)
        #expect(RankingRowSurface.treatment(isSelected: false, card: false, grouped: false) == .bare)
        #expect(RankingRowSurface.treatment(isSelected: true, card: true, grouped: false) == .selectedCard)
        #expect(RankingRowSurface.treatment(isSelected: true, card: false, grouped: false) == .selectedCard)
    }

    @Test("Padded rows keep the Settings inset; flush rows inset to their own padding")
    func separatorInsets() {
        #expect(FestivalGroupRows.padded.separatorInset == 16)
        #expect(FestivalGroupRows.flush().separatorInset == 12)
        #expect(FestivalGroupRows.flush(separatorInset: RankingRowLayout.horizontalPadding).separatorInset == 14)
    }
}

#if os(macOS)
// MARK: - Hosted

/// Three 48 pt leaderboard rows, the middle one selected: in a flush group card, or as
/// separate row cards one point apart.
private struct GroupedRowsProbe: View {
    let grouped: Bool
    /// Draw the group with the iOS 17 / macOS 14 stacked rows.
    var stacked = false

    private func row(_ index: Int) -> some View {
        Color.clear
            .frame(height: 48)
            .frame(maxWidth: .infinity)
            .modifier(RankingRowSurface(isSelected: index == 1))
    }

    var body: some View {
        ZStack {
            Color.white
            Group {
                if grouped {
                    let section = FestivalGlassSection(rows: .flush()) {
                        ForEach(0..<3, id: \.self) { row($0) }
                    }
                    if stacked { section.stackedRows() } else { section }
                } else {
                    VStack(spacing: 1) {
                        ForEach(0..<3, id: \.self) { row($0) }
                    }
                }
            }
            .frame(width: 280)
        }
    }
}

/// Mean colour of `rect` in a hosted probe.
///
/// - Parameters:
///   - host: The hosted probe.
///   - rect: Top-left-origin rectangle in points.
/// - Returns: Mean red, green and blue (0–1).
/// - Throws: An empty capture.
@MainActor
private func meanColour<Content: View>(
    _ host: NSHostingView<Content>, in rect: CGRect
) throws -> (red: Double, green: Double, blue: Double) {
    let image = try nativeHostedImage(host, in: rect)
    var sum = (0.0, 0.0, 0.0)
    var count = 0.0
    nativeHostedForEachSample(image) { red, green, blue in
        sum.0 += red; sum.1 += green; sum.2 += blue; count += 1
    }
    let samples = try #require(count > 0 ? count : nil)
    return (sum.0 / samples, sum.1 / samples, sum.2 / samples)
}

/// Finds the selected row's dark player purple in a hosted capture.
@MainActor
private struct BandProbe {
    private let bitmap: NSBitmapImageRep
    private let height: Int
    private let scale: CGFloat

    /// Read `image`, a capture `height` points tall.
    init(_ image: CGImage, height: CGFloat) {
        bitmap = NSBitmapImageRep(cgImage: image)
        self.height = Int(height)
        scale = CGFloat(image.height) / height
    }

    /// Whether the point is the selected row's purple (not the card's blue-grey, its
    /// border, or the bright View All button).
    func isBand(_ x: CGFloat, _ y: Int) -> Bool {
        guard let colour = bitmap.colorAt(
            x: Int(x * scale), y: Int((CGFloat(y) + 0.5) * scale)
        ) else { return false }
        return colour.redComponent - colour.greenComponent > 0.08
            && colour.blueComponent - colour.greenComponent > 0.08
            && max(colour.redComponent, colour.greenComponent, colour.blueComponent) < 0.5
    }

    /// The contiguous band run (points) in column `x` that contains row `y`.
    func run(atX x: CGFloat, through y: Int) -> ClosedRange<Int>? {
        guard isBand(x, y) else { return nil }
        var top = y, bottom = y
        while top > 0, isBand(x, top - 1) { top -= 1 }
        while bottom < height - 1, isBand(x, bottom + 1) { bottom += 1 }
        return top...bottom
    }

    /// The band's run just past the old 12 pt row-card corner: its true height.
    func selectedRun() -> ClosedRange<Int>? {
        guard let first = (0..<height).first(where: { isBand(13, $0) }) else { return nil }
        return run(atX: 13, through: first)
    }
}

@MainActor
@Suite struct GroupedRowsHostedTests {
    /// Probe size: the 280 pt card spans x 20–300, three rows (plus two hairlines) are
    /// centred vertically.
    private static let size = CGSize(width: 320, height: 200)

    /// Top-left corner of the selected (middle) row, just inside the card's edge.
    ///
    /// - Parameter separators: Height between rows (hairline or spacing).
    /// - Returns: A small sample rectangle.
    private static func selectedCorner(separators: CGFloat) -> CGRect {
        let total = 3 * 48 + 2 * separators
        let top = (size.height - total) / 2 + 48 + separators
        return CGRect(x: 21, y: top + 1, width: 3, height: 3)
    }

    @Test("A grouped selected row fills the card edge to edge, corners included")
    func groupedSelectedRowIsFullBleed() throws {
        let host = nativeHostedView(GroupedRowsProbe(grouped: true), size: Self.size)
        let corner = try meanColour(host, in: Self.selectedCorner(separators: 1))
        // The web's purple highlight over the opaque card: blue well above green, not white.
        #expect(corner.blue - corner.green > 0.1, "\(corner)")
        #expect(max(corner.red, corner.green, corner.blue) < 0.7, "\(corner)")
    }

    @Test("iOS 17 / macOS 14 stacked rows fill the selected band edge to edge")
    func stackedSelectedRowIsFullBleed() throws {
        let host = nativeHostedView(GroupedRowsProbe(grouped: true, stacked: true), size: Self.size)
        let corner = try meanColour(host, in: Self.selectedCorner(separators: 1))
        #expect(corner.blue - corner.green > 0.1, "\(corner)")
        #expect(max(corner.red, corner.green, corner.blue) < 0.7, "\(corner)")
    }

    @Test("iOS 17 / macOS 14 stacked rows draw the same inset hairlines, none above the first row")
    func stackedRowsKeepHairlines() throws {
        let modern = nativeHostedView(GroupedRowsProbe(grouped: true), size: Self.size)
        let stacked = nativeHostedView(GroupedRowsProbe(grouped: true, stacked: true), size: Self.size)
        let top = (Self.size.height - (3 * 48 + 2)) / 2
        // Past the 12 pt inset, clear of the card's rounded corners.
        let firstHairline = CGRect(x: 100, y: top + 48, width: 100, height: 1)
        let rowInterior = CGRect(x: 100, y: top + 20, width: 100, height: 1)
        let cardTop = CGRect(x: 100, y: top, width: 100, height: 1)
        let modernHairline = try meanColour(modern, in: firstHairline)
        let modernRow = try meanColour(modern, in: rowInterior)
        // The hairline is visible against the row on iOS 18 / macOS 15 ...
        #expect(modernHairline.green - modernRow.green > 0.02, "\(modernHairline) vs \(modernRow)")
        // ... and the back-deployed stack draws the same hairline, row and card top.
        for (rect, label) in [(firstHairline, "hairline"), (rowInterior, "row"), (cardTop, "card top")] {
            let expected = try meanColour(modern, in: rect)
            let actual = try meanColour(stacked, in: rect)
            let drift = max(
                abs(expected.red - actual.red), abs(expected.green - actual.green),
                abs(expected.blue - actual.blue)
            )
            #expect(drift < 0.03, "\(label): \(actual) vs \(expected)")
        }
    }

    @Test("The First Run your-rank demo groups its rows: the selected row is a square-cornered band")
    func firstRunYourRankDemoIsGrouped() async throws {
        let size = CGSize(width: 320, height: 520)
        let host = nativeHostedView(
            VStack { FirstRunLeaderboardsYourRankDemo(); Spacer(minLength: 0) },
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { withExtendedLifetime(window) {} }
        // The rows fade in one after another; wait until the selected row is drawn and
        // the capture stops changing (a parallel bundle can delay the fade).
        let image = try await nativeHostedSettle(host) {
            guard let capture = try? nativeHostedImage(host) else { return false }
            return BandProbe(capture, height: size.height).selectedRun() != nil
        }
        let band = BandProbe(image, height: size.height)
        let inside = try #require(band.selectedRun(), "no selected band")
        #expect(inside.count >= 40, "\(inside)")
        // Inside the corner, on both sides, the band is just as tall: one rectangular
        // band across the group card's full width, not a rounded row card.
        let centre = (inside.lowerBound + inside.upperBound) / 2
        for x in [CGFloat(2), size.width - 2] {
            let edge = try #require(band.run(atX: x, through: centre), "no band at x \(x)")
            #expect(abs(edge.lowerBound - inside.lowerBound) <= 1, "x \(x): \(edge) vs \(inside)")
            #expect(abs(edge.upperBound - inside.upperBound) <= 1, "x \(x): \(edge) vs \(inside)")
        }
    }

    @Test("An ungrouped selected row keeps its own rounded card")
    func ungroupedSelectedRowIsRounded() throws {
        let host = nativeHostedView(GroupedRowsProbe(grouped: false), size: Self.size)
        let corner = try meanColour(host, in: Self.selectedCorner(separators: 1))
        // Outside the 12 pt rounded corner the white page shows through.
        #expect(min(corner.red, corner.green, corner.blue) > 0.8, "\(corner)")
    }
}
#endif
