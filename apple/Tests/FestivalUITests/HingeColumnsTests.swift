import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Hinge-aligned columns (issue #343, pattern `hinge-columns`)

/// The Duo inner display in book pose: a vertical fold centred at x 475 (window coordinates).
private let fold = CGRect(x: 465, y: 0, width: 20, height: 669)
/// A full-width grid left of the ~84 pt vertical bar, inset 16 pt each side.
private let grid = HorizontalSpan(minX: 16, maxX: 851)

@Test func bandCentresTheClearanceOnTheFold() throws {
    let band = try #require(HingeColumns.band(span: grid, fold: fold, gutter: 20, minimumSide: 120))
    // The 20 pt fold is no wider than the 20 pt gutter: the clearance is 20 pt at 465–485.
    #expect(band == HingeBand(leadingWidth: 449, gap: 20, trailingWidth: 366))
    #expect(band.width == grid.width)
    // A wider fold is the clearance itself.
    let wide = CGRect(x: 455, y: 0, width: 40, height: 669)
    #expect(HingeColumns.band(span: grid, fold: wide, gutter: 12, minimumSide: 120)
            == HingeBand(leadingWidth: 439, gap: 40, trailingWidth: 356))
    // A narrow fold keeps the gutter, still centred on the fold.
    #expect(HingeColumns.band(span: grid, fold: CGRect(x: 474, y: 0, width: 2, height: 669),
                              gutter: 12, minimumSide: 120)
            == HingeBand(leadingWidth: 453, gap: 12, trailingWidth: 370))
}

@Test func noBandWithoutAVerticalFoldThroughTheContainer() {
    // Fully open or folded: no active fold, the flat layout.
    #expect(HingeColumns.band(span: grid, fold: nil, gutter: 20, minimumSide: 120) == nil)
    // Unmeasured container.
    #expect(HingeColumns.band(span: nil, fold: fold, gutter: 20, minimumSide: 120) == nil)
    // A horizontal fold (portrait book) never splits columns.
    #expect(HingeColumns.band(span: grid, fold: CGRect(x: 0, y: 465, width: 951, height: 20),
                              gutter: 20, minimumSide: 120) == nil)
    // A grid entirely on one side (a split pane, a half-width column).
    #expect(HingeColumns.band(span: HorizontalSpan(minX: 16, maxX: 449), fold: fold,
                              gutter: 20, minimumSide: 120) == nil)
    #expect(HingeColumns.band(span: HorizontalSpan(minX: 495, maxX: 851), fold: fold,
                              gutter: 20, minimumSide: 120) == nil)
    // The fold near an edge leaves a side too narrow to be worth a column.
    #expect(HingeColumns.band(span: HorizontalSpan(minX: 380, maxX: 851), fold: fold,
                              gutter: 20, minimumSide: 120) == nil)
}

@Test func twoColumnGridsMeetAtTheFold() throws {
    let band = try #require(HingeColumns.band(span: grid, fold: fold, gutter: 20, minimumSide: 120))
    let spec = HingeColumns.spec(band: band, spacing: 20, perSide: .columns(1))
    #expect(spec.widths == [449, 366])
    #expect(spec.offsets == [0, 469])
    #expect(spec.gaps == [20, 0])
    #expect(spec.width == grid.width)
    // The gutter's centre is the fold's centre in window coordinates.
    #expect(grid.minX + spec.offsets[0] + spec.widths[0] + spec.gap / 2 == fold.midX)
}

@Test func fittedGridsKeepTheSameCountOnEachSide() throws {
    // Item Shop: 12 pt spacing, 160 pt fold minimum, 40 pt fold.
    let wide = CGRect(x: 455, y: 0, width: 40, height: 669)
    let band = try #require(HingeColumns.band(span: grid, fold: wide, gutter: 12, minimumSide: 160))
    let spec = HingeColumns.spec(band: band, spacing: 12, perSide: .fit(minimum: 160))
    #expect(spec.leadingCount == 2)
    #expect(spec.trailingCount == 2)
    #expect(spec.widths == [213.5, 213.5, 172, 172])
    #expect(spec.gaps == [12, 40, 12, 0])
    #expect(spec.width == grid.width)
    // The narrower side decides: a wider minimum leaves one card a side, never 2 | 1.
    let one = HingeColumns.spec(band: band, spacing: 12, perSide: .fit(minimum: 190))
    #expect(one.leadingCount == 1)
    #expect(one.trailingCount == 1)
}

@Test func fitCountIsAtLeastOne() {
    #expect(HingeColumns.fitCount(width: 356, minimum: 160, spacing: 12) == 2)
    #expect(HingeColumns.fitCount(width: 100, minimum: 160, spacing: 12) == 1)
    #expect(HingeColumns.fitCount(width: 0, minimum: 160, spacing: 12) == 1)
    #expect(HingeColumns.fitCount(width: 500, minimum: 0, spacing: 12) == 1)
}

@Test func perSideFollowsTheFlatColumns() {
    let two = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]
    #expect(HingeColumns.perSide(for: two) == .columns(1))
    let four = Array(repeating: GridItem(.flexible()), count: 4)
    #expect(HingeColumns.perSide(for: four) == .columns(2))
    #expect(HingeColumns.perSide(for: [GridItem(.adaptive(minimum: 210))]) == .fit(minimum: 210))
}

@Test func gridItemsFixTheLeadingSideAndGapTheFold() throws {
    let band = try #require(HingeColumns.band(span: grid, fold: fold, gutter: 20, minimumSide: 120))
    let items = HingeColumns.gridItems(HingeColumns.spec(band: band, spacing: 20, perSide: .columns(1)),
                                       alignment: .top)
    #expect(items.count == 2)
    #expect(items.map(\.spacing) == [20, 0])
    if case let .fixed(width) = items[0].size { #expect(width == 449) } else { Issue.record("leading not fixed") }
    if case .flexible = items[1].size {} else { Issue.record("trailing not flexible") }
}

@Test func titlesStayOnTheirSideOfTheFold() {
    // A full-width title wraps before the fold, 16 pt clear of its centre line.
    #expect(HingeColumns.titleWidth(span: HorizontalSpan(minX: 20, maxX: 847), fold: fold) == 439)
    // No fold, or a title inside one side: no limit.
    #expect(HingeColumns.titleWidth(span: HorizontalSpan(minX: 20, maxX: 847), fold: nil) == nil)
    #expect(HingeColumns.titleWidth(span: HorizontalSpan(minX: 20, maxX: 440), fold: fold) == nil)
    #expect(HingeColumns.titleWidth(span: HorizontalSpan(minX: 511, maxX: 847), fold: fold) == nil)
    // A title starting just before the fold keeps its width rather than a sliver.
    #expect(HingeColumns.titleWidth(span: HorizontalSpan(minX: 400, maxX: 847), fold: fold) == nil)
}

@Test func hingeRowSplitsOnlyAMatchingBand() throws {
    let band = try #require(HingeColumns.band(span: grid, fold: fold, gutter: 12, minimumSide: 120))
    let row = HingeRowLayout(spacing: 12, band: band)
    let cells = row.cells(width: grid.width, count: 2)
    #expect(cells.map(\.x) == [0, 469])
    #expect(cells.map(\.width) == [449, 366])
    // A width the band was not measured for (mid-resize) falls back to equal cells.
    let flat = row.cells(width: 500, count: 2)
    #expect(flat.map(\.width) == [244, 244])
    #expect(flat.map(\.x) == [0, 256])
    // No band: equal cells.
    #expect(HingeRowLayout(spacing: 12, band: nil).cells(width: grid.width, count: 2).map(\.width)
            == [411.5, 411.5])
    #expect(row.cells(width: grid.width, count: 0).isEmpty)
}

@Test func statGridSplitsTilesAtTheFold() throws {
    let band = try #require(HingeColumns.band(span: grid, fold: fold, gutter: 8, minimumSide: 140))
    let layout = StatTileGridLayout(spacing: 8, minimumTileWidth: 140, minimumColumns: 2, band: band)
    let columns = layout.columnFrames(for: grid.width)
    // Two tiles a side: 449 pt fits three, 366 pt two, and the narrower side decides.
    #expect(columns.count == 4)
    #expect(columns[1].x + columns[1].width + band.gap == columns[2].x)
    #expect(grid.minX + columns[1].x + columns[1].width + band.gap / 2 == fold.midX)
    // Without a band the flat equal-width columns return.
    let flat = StatTileGridLayout(spacing: 8, minimumTileWidth: 140, minimumColumns: 2)
    let (count, width) = flat.metrics(for: grid.width)
    #expect(flat.columnFrames(for: grid.width).count == count)
    #expect(flat.columnFrames(for: grid.width).allSatisfy { $0.width == width })
}
