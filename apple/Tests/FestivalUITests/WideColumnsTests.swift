import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Fixtures

/// Window layouts (points) for the wide-columns rule (`.agents/patterns/wide-columns.md`).
private enum Windows {
    static let iPhonePortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 402, height: 874), widthClass: .compact
    ))
    static let largeIPhoneLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 956, height: 440), widthClass: .regular, heightClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
    ))
    static let iPadLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 1210, height: 834), widthClass: .regular, usesSidebarShell: true
    ))
    static let iPadPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 834, height: 1210), widthClass: .regular, usesSidebarShell: true
    ))
    /// A Stage Manager window just too narrow for two 320 pt columns.
    static let iPadNarrowLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 680, height: 600), widthClass: .regular, usesSidebarShell: true
    ))
    static let duoFolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    ))
    static let duoInnerLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    static let duoInnerPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
    ))
    /// Book pose with an active fold off the middle.
    static let duoBook = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .partiallyOpen,
        divisions: [CGRect(x: 460, y: 0, width: 30, height: 669)]
    ))
}

// MARK: - Column count

/// Two columns only in a landscape window regular in both dimensions with room for two.
@Test func wideColumnsFollowWindowShapeAndSizeClasses() {
    #expect(WideColumns.count(layout: Windows.iPadLandscape) == 2)
    #expect(WideColumns.count(layout: Windows.duoInnerLandscape) == 2)
    #expect(WideColumns.count(layout: Windows.duoBook) == 2)
    #expect(WideColumns.count(layout: Windows.iPadPortrait) == 1)
    #expect(WideColumns.count(layout: Windows.duoInnerPortrait) == 1)
    #expect(WideColumns.count(layout: Windows.duoFolded) == 1)
    #expect(WideColumns.count(layout: Windows.iPhonePortrait) == 1)
    #expect(WideColumns.count(layout: Windows.largeIPhoneLandscape) == 1)
    #expect(WideColumns.count(layout: Windows.iPadNarrowLandscape) == 1)
}

/// A measured page width narrows the decision; a wide box in a portrait window (the
/// iPad keyboard shortening the page) never becomes two columns.
@Test func wideColumnsUseMeasuredWidthButWindowOrientation() {
    #expect(WideColumns.count(layout: Windows.iPadLandscape, width: 1210) == 2)
    #expect(WideColumns.count(layout: Windows.iPadLandscape, width: 600) == 1)
    #expect(WideColumns.count(layout: Windows.iPadPortrait, width: 834) == 1)
    let threshold = WideColumns.minimumTwoColumnWidth + WideColumns.rowMargins
    #expect(WideColumns.fits(width: threshold))
    #expect(!WideColumns.fits(width: threshold - 1))
    #expect(threshold == 684)
}

/// The Mac sheet splits from its own size: landscape and wide enough.
@Test func wideColumnsOnMacFollowTheSheetSize() {
    #expect(WideColumns.count(size: CGSize(width: 880, height: 560)) == 2)
    #expect(WideColumns.count(size: CGSize(width: 620, height: 600)) == 1)
    #expect(WideColumns.count(size: CGSize(width: 700, height: 900)) == 1)
    #expect(WideColumns.count(size: .zero) == 1)
}

/// The Mac Search sheet opens wide only in a landscape window with room around it.
@Test func macSearchSheetSizeFollowsTheWindow() {
    #expect(WideColumns.macSheetSize(window: CGSize(width: 1280, height: 820)) == WideColumns.macWideSheet)
    #expect(WideColumns.macSheetSize(window: CGSize(width: 760, height: 540)) == WideColumns.macNarrowSheet)
    #expect(WideColumns.macSheetSize(window: CGSize(width: 900, height: 1200)) == WideColumns.macNarrowSheet)
    #expect(WideColumns.macSheetSize(window: .zero) == WideColumns.macNarrowSheet)
}

/// Rows keep reading order; only the last may be short.
@Test func wideColumnsChunkRowMajor() {
    #expect(WideColumns.rows([1, 2, 3, 4, 5], columns: 2) == [[1, 2], [3, 4], [5]])
    #expect(WideColumns.rows([1, 2], columns: 1) == [[1], [2]])
    #expect(WideColumns.rows([1, 2], columns: 0) == [[1], [2]])
    #expect(WideColumns.rows([Int](), columns: 2).isEmpty)
}

// MARK: - Hinge

/// On a flat inner display the page hinge is the window's middle, so two columns meet
/// there (R3) even with the vertical bar's inset on one side; the fold-only hinge
/// keeps equal cells while flat.
@Test func wideColumnsMeetAtTheFlatDuoHinge() throws {
    let layout = Windows.duoInnerLandscape
    // A row inside the 16 pt list insets, left of the 84 pt vertical bar.
    let span = HorizontalSpan(minX: 16, maxX: 951 - 84 - 16)
    let hinge = try #require(layout.splitHinge)
    let band = try #require(HingeColumns.band(
        span: span, fold: hinge, gutter: WideColumns.spacing, minimumSide: HingeColumns.minimumSide
    ))
    let cells = HingeRowLayout(spacing: WideColumns.spacing, band: band).cells(width: span.width, count: 2)
    let gutterMid = span.minX + (cells[0].x + cells[0].width + cells[1].x) / 2
    #expect(abs(gutterMid - 951 / 2) < 0.5)
    #expect(layout.foldFrame == nil)
    #expect(HingeColumns.band(
        span: span, fold: layout.foldFrame, gutter: WideColumns.spacing, minimumSide: HingeColumns.minimumSide
    ) == nil)
}

/// In book pose both hinges are the fold, so the columns straddle it.
@Test func wideColumnsStraddleTheFoldInBookPose() throws {
    let layout = Windows.duoBook
    let span = HorizontalSpan(minX: 16, maxX: 935)
    let band = try #require(HingeColumns.band(
        span: span, fold: layout.splitHinge, gutter: WideColumns.spacing, minimumSide: HingeColumns.minimumSide
    ))
    let cells = HingeRowLayout(spacing: WideColumns.spacing, band: band).cells(width: span.width, count: 2)
    #expect(span.minX + cells[0].x + cells[0].width <= 460)
    #expect(span.minX + cells[1].x >= 490)
}

/// Songs keeps its grid through the shared rule.
@Test func songGridPolicyDelegatesToWideColumns() {
    for layout in [Windows.iPadLandscape, Windows.iPadPortrait, Windows.duoInnerLandscape, Windows.duoFolded] {
        #expect(SongGridPolicy.columns(layout: layout) == WideColumns.count(layout: layout))
    }
    #expect(SongGridPolicy.spacing == WideColumns.spacing)
}

// MARK: - Full boards (issue #353)

/// A split's sub-page is always one column; a full-width page follows the platform
/// rule from its own measured size.
@Test func wideColumnsKeepSplitSubPagesSingleColumn() {
    let wide = CGSize(width: 1210, height: 834)
    #expect(WideColumns.count(layout: Windows.iPadLandscape, size: wide, subPage: true) == 1)
    #expect(WideColumns.count(layout: Windows.iPadLandscape, size: .zero, subPage: true) == 1)
    #expect(WideColumns.count(layout: Windows.iPadPortrait, size: CGSize(width: 834, height: 1210), subPage: false) == 1)
    #if os(macOS)
    #expect(WideColumns.count(layout: Windows.iPadPortrait, size: wide, subPage: false) == 2)
    #expect(WideColumns.count(layout: Windows.iPadLandscape, size: CGSize(width: 600, height: 400), subPage: false) == 1)
    #else
    #expect(WideColumns.count(layout: Windows.iPadLandscape, size: wide, subPage: false) == 2)
    #expect(WideColumns.count(layout: Windows.iPadLandscape, size: .zero, subPage: false) == 2)
    #expect(WideColumns.count(layout: Windows.duoInnerLandscape, size: CGSize(width: 880, height: 669), subPage: false) == 2)
    #expect(WideColumns.count(layout: Windows.duoFolded, size: CGSize(width: 382, height: 678), subPage: false) == 1)
    #endif
}

/// A split context marks its open item, and pages pushed beside the list, as sub-pages;
/// a page pushed over a covering profile is full width again.
@Test func splitContextMarksSubPages() {
    let open = SplitPaneContext(role: .trailing, besideList: .leaderboards)
    #expect(open.isSubPage)
    #expect(open.pushedPage.isSubPage)
    let covering = SplitPaneContext(role: .trailing, besideList: nil, coversList: true)
    #expect(covering.isSubPage)
    #expect(!covering.pushedPage.isSubPage)
    #expect(!SplitPaneContext(paneWidth: 600, role: .leading).isSubPage)
}

/// One column's page-equivalent width: margins and gutter out, one column's margins
/// back, so width-driven row plans fit a column as a page of that width.
@Test func columnPageWidthSplitsTheRowsEvenly() {
    #expect(WideColumns.columnPageWidth(1200, columns: 1) == 1200)
    #expect(WideColumns.columnPageWidth(1200, columns: 2) == 610)
    #expect(WideColumns.columnPageWidth(0, columns: 2) == 0)
    // Two columns at the narrowest two-column page each lay out like a 352 pt page.
    #expect(WideColumns.columnPageWidth(684, columns: 2) == 352)
    #expect(RankingSongsFit.rowWidth(section: 1200, rowInset: 32, columns: 2) == 578)
    #expect(RankingSongsFit.rowWidth(section: 402, rowInset: 32, columns: 1) == 370)
    #expect(RankingSongsFit.rowWidth(section: 0, rowInset: 32, columns: 2) == 0)
}

private struct Ranked: Identifiable, Equatable {
    let id: Int
}

/// Board rows keep rank order row-major, remember each item's place on the page, and
/// take their first item's identity, which is where a scroll to any item lands.
@Test func indexedRowsKeepRankOrderAndScrollTargets() {
    let items = (1...5).map(Ranked.init)
    let pairs = WideColumns.indexedRows(items, columns: 2)
    #expect(pairs.map(\.id) == [1, 3, 5])
    #expect(pairs.map { $0.indexed.map(\.index) } == [[0, 1], [2, 3], [4]])
    #expect(pairs.flatMap { $0.items.map(\.id) } == [1, 2, 3, 4, 5])
    let singles = WideColumns.indexedRows(items, columns: 1)
    #expect(singles.map(\.id) == [1, 2, 3, 4, 5])
    #expect(WideColumns.rowStart(of: 3, columns: 2) == 2)
    #expect(WideColumns.rowStart(of: 4, columns: 2) == 4)
    #expect(WideColumns.rowStart(of: 3, columns: 1) == 3)
    #expect(items[WideColumns.rowStart(of: 3, columns: 2)].id == pairs[1].id)
    #expect(WideColumns.indexedRows([Ranked](), columns: 2).isEmpty)
}
