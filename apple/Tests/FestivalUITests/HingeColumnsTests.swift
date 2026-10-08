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

/// #365: `GridItem`'s default `.center` sank Song Detail's shorter instrument card to the
/// middle of its row; grid columns now top-align unless they name an alignment.
@Test func gridColumnsTopAlignUnlessTheyNameAnAlignment() {
    let columns = HingeColumns.topAligned([
        GridItem(.adaptive(minimum: 360), spacing: 12),
        GridItem(.flexible(), alignment: .bottomTrailing),
    ])
    #expect(columns.map(\.alignment) == [.top, .bottomTrailing])
    #expect(columns.map(\.spacing) == [12, nil])
    if case let .adaptive(minimum, _) = columns[0].size { #expect(minimum == 360) } else { Issue.record("size changed") }
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

@Test func adaptiveGridsWithTwoFlatColumnsAlwaysSplitAtTheFold() throws {
    // Song Detail cards (360 pt minimum, 12 pt spacing) under a 40 pt fold: the trailing
    // side is 356 pt, a little under the minimum, but the flat grid already has two
    // columns whose gutter would sit beside the fold, so it splits one card a side.
    let wide = CGRect(x: 455, y: 0, width: 40, height: 669)
    let band = try #require(HingeColumns.adaptiveBand(span: grid, fold: wide, gutter: 12, minimum: 360))
    #expect(band == HingeBand(leadingWidth: 439, gap: 40, trailingWidth: 356))
    let spec = HingeColumns.spec(band: band, spacing: 12, perSide: .fit(minimum: 360))
    #expect(spec.widths == [439, 356])
    // A grid that is one flat column stays one column.
    #expect(HingeColumns.adaptiveBand(span: HorizontalSpan(minX: 16, maxX: 716), fold: wide,
                                      gutter: 12, minimum: 360) == nil)
    // No fold, or a sliver of a side: the flat grid.
    #expect(HingeColumns.adaptiveBand(span: grid, fold: nil, gutter: 12, minimum: 360) == nil)
    #expect(HingeColumns.adaptiveBand(span: HorizontalSpan(minX: 360, maxX: 1200), fold: wide,
                                      gutter: 12, minimum: 360) == nil)
}

@Test func eagerGridSplitsItsRowsAtTheFold() throws {
    let wide = CGRect(x: 455, y: 0, width: 40, height: 669)
    let band = try #require(HingeColumns.adaptiveBand(span: grid, fold: wide, gutter: 12, minimum: 360))
    let folded = HingeEagerGridLayout(minimum: 360, spacing: 12, rowSpacing: 20, band: band)
    let columns = folded.columns(width: grid.width)
    #expect(columns.map(\.x) == [0, 479])
    #expect(columns.map(\.width) == [439, 356])
    // The gutter's centre is the fold's centre in window coordinates.
    #expect(grid.minX + columns[0].x + columns[0].width + band.gap / 2 == wide.midX)
    // Flat (no band, or a width the band was not measured for): equal adaptive columns.
    let flat = HingeEagerGridLayout(minimum: 360, spacing: 12, rowSpacing: 20)
    #expect(flat.columns(width: grid.width).map(\.width) == [411.5, 411.5])
    #expect(folded.columns(width: 700).map(\.width) == [700])
}

// MARK: - Two panes (issue #368)

@Test func panesMeetAtAVerticalFoldSideBySide() throws {
    let frame = CGRect(x: 16, y: 100, width: 835, height: 500)
    let split = try #require(HingeColumns.paneSplit(frame: frame, fold: fold, spacing: 16))
    #expect(split.axis == .horizontal)
    #expect(split.band == HingeBand(leadingWidth: 449, gap: 20, trailingWidth: 366))
    let panes = HingePanesLayout(spacing: 16, split: split).frames(in: frame.size)
    #expect(panes.first == CGRect(x: 0, y: 0, width: 449, height: 500))
    #expect(panes.second == CGRect(x: 469, y: 0, width: 366, height: 500))
}

@Test func panesStackAcrossAHorizontalFold() throws {
    let horizontal = CGRect(x: 0, y: 465, width: 669, height: 20)
    let frame = CGRect(x: 16, y: 60, width: 637, height: 840)
    let split = try #require(HingeColumns.paneSplit(frame: frame, fold: horizontal, spacing: 16))
    #expect(split.axis == .vertical)
    let panes = HingePanesLayout(spacing: 16, split: split).frames(in: frame.size)
    #expect(panes.first == CGRect(x: 0, y: 0, width: 637, height: 405))
    #expect(panes.second == CGRect(x: 0, y: 425, width: 637, height: 415))
}

@Test func flatPanesAreEqualHalves() throws {
    let size = CGSize(width: 816, height: 600)
    let flat = HingePanesLayout(spacing: 16, split: nil).frames(in: size)
    #expect(flat.first == CGRect(x: 0, y: 0, width: 400, height: 600))
    #expect(flat.second == CGRect(x: 416, y: 0, width: 400, height: 600))
    // No fold, an unmeasured container or a fold outside it: no split.
    #expect(HingeColumns.paneSplit(frame: CGRect(origin: .zero, size: size), fold: nil, spacing: 16) == nil)
    #expect(HingeColumns.paneSplit(frame: nil, fold: fold, spacing: 16) == nil)
    #expect(HingeColumns.paneSplit(frame: CGRect(x: 500, y: 0, width: 400, height: 600), fold: fold, spacing: 16) == nil)
    // A split measured for another size (mid-resize) falls back to halves.
    let split = try #require(HingeColumns.paneSplit(
        frame: CGRect(x: 16, y: 0, width: 835, height: 600), fold: fold, spacing: 16
    ))
    #expect(HingePanesLayout(spacing: 16, split: split).frames(in: size) == flat)
}
