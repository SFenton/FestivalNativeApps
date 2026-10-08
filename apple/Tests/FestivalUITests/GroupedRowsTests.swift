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

// MARK: - In-card View All (issue #382)

/// The "View All" call to action ends its group card inside it (view-all-cta R1, #382).
@Suite struct CardActionTests {
    @Test("The in-card action's corners are concentric with the card's")
    func actionInsetIsConcentric() {
        #expect(FestivalGlassSection<EmptyView, EmptyView>.actionInset == 10)
        #expect(
            FestivalGlassSection<EmptyView, EmptyView>.cornerRadius
                - FestivalGlassSection<EmptyView, EmptyView>.actionInset
                == PurpleActionSurface.cornerRadius
        )
    }

    @Test("The accessible name is the visible label first, then the card")
    func spokenNameIsLabelFirst() {
        #expect(PurpleActionName.spoken("View Full Leaderboard", card: "Lead") == "View Full Leaderboard, Lead")
        #expect(PurpleActionName.spoken("View All Bands (18)", card: "Duos") == "View All Bands (18), Duos")
        #expect(PurpleActionName.spoken("View All Rivals", card: nil) == "View All Rivals")
        #expect(PurpleActionName.spoken("View All Rivals", card: "") == "View All Rivals")
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

    // MARK: In-card action

    /// Three 48 pt rows in a 280 pt flush group card, optionally ending with View All.
    private struct ActionProbe: View {
        var action = true
        var backdrop = Color.white

        var body: some View {
            ZStack {
                backdrop
                FestivalGlassSection(rows: .flush()) {
                    ForEach(0..<3, id: \.self) { _ in Color.clear.frame(height: 48) }
                } action: {
                    if action { PurpleActionLabel(title: "View All") }
                }
                .frame(width: 280)
            }
        }
    }

    /// Height the probe's card takes on its own.
    private static func cardHeight(action: Bool) -> CGFloat {
        let host = NSHostingView(rootView: ActionProbe(action: action).body.fixedSize(horizontal: false, vertical: true))
        return host.fittingSize.height
    }

    private static let actionSize = CGSize(width: 320, height: 300)
    /// Card: 3 × 48 rows + 2 hairlines + 10 + 48 (44 pt label, 2 pt padding) + 10.
    private static let actionCardHeight: CGFloat = 146 + 68
    private static var actionCardTop: CGFloat { (actionSize.height - actionCardHeight) / 2 }
    /// Vertical centre of the View All button.
    private static var actionMidY: CGFloat { actionCardTop + 146 + 10 + 24 }

    @Test("An absent action adds no space; a present one adds the button and its 10 pt inset")
    func actionHeight() {
        let bare = Self.cardHeight(action: false)
        let withAction = Self.cardHeight(action: true)
        #expect(abs(bare - 146) <= 1, "\(bare)")
        #expect(abs(withAction - bare - 68) <= 1, "\(withAction) vs \(bare)")
    }

    @Test("Inside the card View All is a flat, opaque brand purple with the card around it")
    func actionIsFlatPurpleInsideCard() throws {
        // The brand purple as the capture renders it (same colour-space conversion).
        let swatch = nativeHostedView(BrandTokens.accentPurple, size: CGSize(width: 20, height: 20))
        let purple = try meanColour(swatch, in: CGRect(x: 5, y: 5, width: 10, height: 10))
        // Left of the centred label, clear of the button's 12 pt corners.
        let button = CGRect(x: 36, y: Self.actionMidY - 2, width: 6, height: 4)
        // The card's 10 pt margin beside the button, and the page just outside the card.
        let margin = CGRect(x: 23, y: Self.actionMidY - 2, width: 4, height: 4)
        let outside = CGRect(x: 4, y: Self.actionMidY - 2, width: 4, height: 4)
        for backdrop in [Color.white, Color.black] {
            let host = nativeHostedView(ActionProbe(backdrop: backdrop), size: Self.actionSize)
            let fill = try meanColour(host, in: button)
            // Opaque: the same purple whatever is behind the card (no material of its own).
            #expect(abs(fill.red - purple.red) < 0.04, "\(fill)")
            #expect(abs(fill.green - purple.green) < 0.04, "\(fill)")
            #expect(abs(fill.blue - purple.blue) < 0.04, "\(fill)")
            let card = try meanColour(host, in: margin)
            let page = try meanColour(host, in: outside)
            // The margin is the card, not purple and not the bare page.
            #expect(card.blue - card.green < 0.3, "margin \(card)")
            let drift = abs(card.red - page.red) + abs(card.green - page.green) + abs(card.blue - page.blue)
            #expect(drift > 0.05, "margin \(card) vs page \(page)")
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
