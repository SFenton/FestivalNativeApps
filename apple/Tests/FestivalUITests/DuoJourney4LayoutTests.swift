import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Fixtures

/// iPhone Duo inner display, landscape: vertical bar on the trailing edge.
private let innerLandscape = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 951, height: 669), widthClass: .regular, heightClass: .regular,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
    verticalBarEdge: .trailing, hinge: .fullyOpen
))

/// iPhone Duo inner display, portrait: horizontal tab bar.
private let innerPortrait = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 669, height: 951), widthClass: .regular, heightClass: .regular, hinge: .fullyOpen
))

/// iPhone Duo inner display, book pose: a vertical fold down the middle.
private let innerBook = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 951, height: 669), widthClass: .regular, heightClass: .regular,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
    verticalBarEdge: .trailing, hinge: .partiallyOpen,
    divisions: [CGRect(x: 463, y: 0, width: 24, height: 669)]
))

/// iPhone Duo outer display, folded portrait.
private let folded = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 466, height: 678), widthClass: .compact,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
    verticalBarEdge: .trailing, hinge: .closed
))

/// iPad in the sidebar shell.
private let iPad = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 1194, height: 834), widthClass: .regular, usesSidebarShell: true
))

// MARK: - S1 Item Shop grid

/// `/duo` S1: the Duo inner display draws an even column count (4 in landscape, 2 in
/// portrait), flat or folded; every other window keeps the adaptive 210 pt grid.
@Test func shopGridUsesEvenColumnsOnTheDuoInnerDisplay() {
    // Grid widths: window minus the 84 pt bar and 2 × 16 pt padding.
    #expect(ShopGridPolicy.evenColumnCount(width: 835, layout: innerLandscape) == 4)
    #expect(ShopGridPolicy.evenColumnCount(width: 835, layout: innerBook) == 4)
    #expect(ShopGridPolicy.evenColumnCount(width: 637, layout: innerPortrait) == 2)
    #expect(ShopGridPolicy.columnCount(width: 835, layout: innerLandscape) == 4)
    // The adaptive grid would have drawn 3 columns there (one across the fold).
    #expect(ShopGridPolicy.columnCount(width: 835, layout: .standardPhone) == 3)
    #expect(ShopGridPolicy.evenColumnCount(width: 835, layout: iPad) == nil)
    #expect(ShopGridPolicy.evenColumnCount(width: 350, layout: folded) == nil)
    #expect(ShopGridPolicy.evenColumnCount(width: 0, layout: innerLandscape) == nil)
    // Room for one column only: no even rounding.
    #expect(ShopGridPolicy.evenColumnCount(width: 300, layout: innerPortrait) == nil)
}

// MARK: - G1 Suggestions grid

/// `/duo` G1: two card columns at regular width, one on iPhone and the folded Duo.
@Test func suggestionsUseTwoColumnsAtRegularWidth() {
    #expect(SuggestionsLayout.usesGrid(innerLandscape))
    #expect(SuggestionsLayout.usesGrid(innerPortrait))
    #expect(!SuggestionsLayout.usesGrid(folded))
    #expect(!SuggestionsLayout.usesGrid(.standardPhone))
    #expect(SuggestionsLayout.gridColumns.count == 2)
}
