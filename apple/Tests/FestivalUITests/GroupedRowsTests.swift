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
                    FestivalGlassSection(rows: .flush()) {
                        ForEach(0..<3, id: \.self) { row($0) }
                    }
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

    @Test("An ungrouped selected row keeps its own rounded card")
    func ungroupedSelectedRowIsRounded() throws {
        let host = nativeHostedView(GroupedRowsProbe(grouped: false), size: Self.size)
        let corner = try meanColour(host, in: Self.selectedCorner(separators: 1))
        // Outside the 12 pt rounded corner the white page shows through.
        #expect(min(corner.red, corner.green, corner.blue) > 0.8, "\(corner)")
    }
}
#endif
