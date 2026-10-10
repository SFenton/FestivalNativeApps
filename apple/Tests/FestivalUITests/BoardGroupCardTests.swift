import SwiftUI
import Testing
@testable import FestivalUI
import FestivalDesign
#if os(macOS)
import AppKit
#endif

// MARK: - Segment rules (issue #543)

/// A full board's rows are segments of one group card per column (owner #543,
/// leaderboard-row R10): the first row carries the card's top corners, the last its
/// bottom corners.
@Suite struct BoardGroupSegmentTests {
    @Test("One column: the first row opens the card, the last closes it, a lone row does both")
    func oneColumn() {
        let segments = (0..<3).map { FestivalGroupSegment.position(index: $0, count: 3, columns: 1) }
        #expect(segments.map(\.isFirst) == [true, false, false])
        #expect(segments.map(\.isLast) == [false, false, true])
        #expect(segments.allSatisfy { !$0.fillsPair })
        let lone = FestivalGroupSegment.position(index: 0, count: 1, columns: 1)
        #expect(lone.isFirst && lone.isLast)
    }

    @Test("Wide-columns pairs: each column is its own card, a short last row closes both")
    func twoColumns() {
        // Row-major: 0 1 / 2 3 / 4 — the left column ends at 4, the right at 3.
        let segments = (0..<5).map { FestivalGroupSegment.position(index: $0, count: 5, columns: 2) }
        #expect(segments.map(\.isFirst) == [true, true, false, false, false])
        #expect(segments.map(\.isLast) == [false, false, false, true, true])
        #expect(segments.allSatisfy { $0.fillsPair })
        // A page of one row in two columns: one card in the left column only.
        let single = FestivalGroupSegment.position(index: 0, count: 1, columns: 2)
        #expect(single.isFirst && single.isLast)
    }

    @Test("A column count below one reads as one column")
    func invalidColumns() {
        #expect(FestivalGroupSegment.position(index: 1, count: 3, columns: 0)
            == FestivalGroupSegment.position(index: 1, count: 3, columns: 1))
    }

    @Test("Only the card's ends are rounded, with the group card's radius")
    @MainActor func cornerRadii() {
        let radius = FestivalGlassSection<EmptyView, EmptyView>.cornerRadius
        let first = FestivalGroupSegment(isFirst: true, isLast: false).cornerRadii(radius)
        #expect(first.topLeading == 22 && first.topTrailing == 22)
        #expect(first.bottomLeading == 0 && first.bottomTrailing == 0)
        let middle = FestivalGroupSegment(isFirst: false, isLast: false).cornerRadii(radius)
        #expect([middle.topLeading, middle.topTrailing, middle.bottomLeading, middle.bottomTrailing] == [0, 0, 0, 0])
        let last = FestivalGroupSegment(isFirst: false, isLast: true).cornerRadii(radius)
        #expect(last.topLeading == 0 && last.bottomLeading == 22 && last.bottomTrailing == 22)
    }

    @Test("Segment rows are grouped rows: no card of their own, the selected row a flat band")
    func segmentRowsAreGrouped() {
        // The segment sets `festivalGroupedRow`, so rows take the grouped treatment.
        #expect(RankingRowSurface.treatment(isSelected: false, card: true, grouped: true) == .bare)
        #expect(RankingRowSurface.treatment(isSelected: true, card: true, grouped: true) == .selectedBand)
    }

    @Test("Hairlines inset to each board row's own padding")
    func separatorInsets() {
        #expect(SongLeaderboardRowCard.horizontalPadding == 14)
        #expect(RankingRowLayout.horizontalPadding == 14)
    }
}

#if os(macOS)
// MARK: - Hosted

/// Mean colour of `rect` in a hosted view.
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

/// Largest channel difference between two colours.
private func drift(
    _ lhs: (red: Double, green: Double, blue: Double), _ rhs: (red: Double, green: Double, blue: Double)
) -> Double {
    max(abs(lhs.red - rhs.red), abs(lhs.green - rhs.green), abs(lhs.blue - rhs.blue))
}

/// Three 48 pt rows, the middle one selected, as a board draws them (one segment per
/// row) or as a flush group card draws them.
private struct SegmentProbe: View {
    let segments: Bool

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
                if segments {
                    VStack(spacing: 0) {
                        ForEach(0..<3, id: \.self) { index in
                            row(index).festivalGroupSegment(
                                .position(index: index, count: 3, columns: 1), separatorInset: 12
                            )
                        }
                    }
                } else {
                    FestivalGlassSection(rows: .flush()) {
                        ForEach(0..<3, id: \.self) { row($0) }
                    }
                }
            }
            .frame(width: 280)
        }
    }
}

/// A wide-columns pair whose right cell is twice as tall as its left.
private struct PairProbe: View {
    var body: some View {
        ZStack {
            Color.white
            WideColumnsRow(columns: 2, count: 2, matchesHeights: true) {
                ForEach([48, 96], id: \.self) { height in
                    Color.clear
                        .frame(height: CGFloat(height))
                        .frame(maxWidth: .infinity)
                        .festivalGroupSegment(
                            .position(index: height == 48 ? 0 : 1, count: 2, columns: 2), separatorInset: 12
                        )
                }
            }
            .frame(width: 300)
        }
    }
}

@MainActor
@Suite struct BoardGroupCardHostedTests {
    /// The probe: a 280 pt card at x 20–300, three rows and two hairlines centred.
    private static let size = CGSize(width: 320, height: 200)
    private static var top: CGFloat { (size.height - (3 * 48 + 2)) / 2 }

    @Test("Board segments draw the same card as a flush group: rows, hairlines, selected band")
    func segmentsMatchTheGroupCard() throws {
        let group = nativeHostedView(SegmentProbe(segments: false), size: Self.size)
        let board = nativeHostedView(SegmentProbe(segments: true), size: Self.size)
        let top = Self.top
        let samples: [(CGRect, String)] = [
            (CGRect(x: 100, y: top + 20, width: 100, height: 4), "first row"),
            (CGRect(x: 100, y: top + 48, width: 100, height: 1), "first hairline"),
            (CGRect(x: 21, y: top + 50, width: 3, height: 3), "selected band at the card edge"),
            (CGRect(x: 100, y: top + 49 + 24, width: 100, height: 4), "selected band"),
            (CGRect(x: 100, y: top + 98 + 20, width: 100, height: 4), "last row"),
            (CGRect(x: 100, y: top + 1, width: 100, height: 2), "card top"),
        ]
        for (rect, label) in samples {
            let expected = try meanColour(group, in: rect)
            let actual = try meanColour(board, in: rect)
            #expect(drift(expected, actual) < 0.04, "\(label): \(actual) vs \(expected)")
        }
        // The selected row fills the card to its edge: purple, not the white page.
        let edge = try meanColour(board, in: CGRect(x: 21, y: top + 50, width: 3, height: 3))
        #expect(edge.blue - edge.green > 0.1 && max(edge.red, edge.green, edge.blue) < 0.7, "\(edge)")
    }

    @Test("No rim or gap crosses the card between rows, left of the hairline inset")
    func noSeamBetweenSegments() throws {
        let board = nativeHostedView(SegmentProbe(segments: true), size: Self.size)
        let top = Self.top
        // Between the second and last rows the card's leading 12 pt carry no hairline:
        // the seam (the last segment's 1 pt top) reads as the row below it.
        let below = try meanColour(board, in: CGRect(x: 24, y: top + 120, width: 6, height: 4))
        let seam = try meanColour(board, in: CGRect(x: 24, y: top + 97, width: 6, height: 1))
        #expect(drift(below, seam) < 0.04, "seam \(seam) vs row \(below)")
        // The page between two old row cards was the white backdrop; here it is card.
        #expect(min(seam.red, seam.green, seam.blue) < 0.8, "\(seam)")
    }

    @Test("A shorter cell in a wide-columns pair stretches, so its column's card has no gap")
    func pairCellsShareTheirHeight() throws {
        let size = CGSize(width: 320, height: 160)
        let host = nativeHostedView(PairProbe(), size: size)
        let top = (size.height - 96) / 2
        // Under the 48 pt left cell, at the right cell's height: still card, not page.
        let below = try meanColour(host, in: CGRect(x: 60, y: top + 72, width: 40, height: 4))
        let inside = try meanColour(host, in: CGRect(x: 60, y: top + 20, width: 40, height: 4))
        #expect(drift(below, inside) < 0.04, "below \(below) vs inside \(inside)")
        #expect(min(below.red, below.green, below.blue) < 0.8, "\(below)")
    }
}

// MARK: - Accessibility

/// Whether a board's rows are realized and laid out as one card: the hosted settle
/// predicate, since the List can report a row's accessibility frame a pass before its
/// final position under load.
///
/// - Parameters:
///   - identifiers: The rows' accessibility identifiers, in page order.
///   - host: The hosting view.
/// - Returns: True once every row has a frame and each abuts the one above it.
@MainActor
func boardRowsAbut(_ identifiers: [String], in host: NSView) -> Bool {
    let frames = identifiers.compactMap { nativeHostedAccessibilityFrame($0, in: host) }
    guard frames.count == identifiers.count else { return false }
    return zip(frames, frames.dropFirst()).allSatisfy { upper, lower in
        let gap = lower.minY - upper.maxY
        return gap >= -0.5 && gap <= 1.5
    }
}

/// Assert that a board's rows read as entries of one card: realized, in reading order
/// top to bottom, each at least one 48 pt row tall (the hit target), the same width,
/// and abutting with only the 1 pt hairline between them, which is no element itself.
///
/// - Parameters:
///   - identifiers: The rows' accessibility identifiers, in page order.
///   - host: The hosting view.
/// - Throws: A row that is not realized.
@MainActor
func expectBoardRowsInOneCard(
    _ identifiers: [String], in host: NSView, sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let frames = try identifiers.map {
        try #require(nativeHostedAccessibilityFrame($0, in: host), "\($0) not realized", sourceLocation: sourceLocation)
    }
    for frame in frames {
        #expect(frame.height >= LeaderboardRowMetrics.minHeight - 0.5, "row \(frame) under 48 pt",
                sourceLocation: sourceLocation)
        #expect(abs(frame.width - frames[0].width) < 1, "row \(frame) vs \(frames[0])",
                sourceLocation: sourceLocation)
    }
    for (upper, lower) in zip(frames, frames.dropFirst()) {
        let gap = lower.minY - upper.maxY
        #expect(gap >= -0.5 && gap <= 1.5, "rows \(upper) and \(lower) are \(gap) pt apart, not one card",
                sourceLocation: sourceLocation)
    }
    let hairline = nativeHostedAccessibilityElement(in: host) { element in
        guard let frame = nativeHostedAccessibilityFrame(of: element, in: host) else { return false }
        return frame.height <= 2 && frame.width > 100 && frames.contains { abs($0.minY - frame.maxY) < 2 }
    }
    #expect(hairline == nil, "a hairline is exposed to accessibility", sourceLocation: sourceLocation)
}

/// The Song Leaderboard's page rows are one card on the iPhone width: labels and
/// identifiers unchanged, 48 pt rows in rank order, the selected row's band in place.
@MainActor
@Test func soloLeaderboardRowsAreOneAccessibleCard() async throws {
    nativeHostedEnableAccessibility()
    let session = try await spotlightSelectedSession()
    let song = try spotlightFixtureSong()
    let payload = try spotlightFixtureLeaderboard(spotlightRank: 2)
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(
        NavigationStack {
            SoloLeaderboardScreen(
                song: song, instrument: .lead, session: session,
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            )
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let ids = ["fixture-other-1", "fixture-spotlight-player", "fixture-other-3", "fixture-other-4"]
        .map { "fst.song-leaderboard.row.\($0)" }
    let image = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        boardRowsAbut(ids, in: host)
    }
    _ = try nativeHostedPNG(image, filename: "song-leaderboard-group-card.png", environment: "FST_LEADERBOARDS_RENDER_OUT")
    try expectBoardRowsInOneCard(ids, in: host)
    #expect(nativeHostedAccessibility(host).contains("#1, Row 1"))
}
#endif
