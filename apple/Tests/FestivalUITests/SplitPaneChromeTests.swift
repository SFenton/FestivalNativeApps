import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - One background per split

/// Only the parent (leading) page registers the split's background; trailing pages
/// leave it to the parent, and pages outside a split register as before.
@Test func onlyTheParentPaneRegistersTheBackground() {
    #expect(SplitPaneChrome.registersBackground(pane: nil))
    #expect(SplitPaneChrome.registersBackground(pane: .leading))
    #expect(!SplitPaneChrome.registersBackground(pane: .trailing))
}

/// A page draws its own backdrop copy only when no split container draws the shared one.
@Test func splitPagesDrawNoBackdropOfTheirOwn() {
    #expect(SplitPaneChrome.drawsOwnBackdrop(sharedBySplit: false))
    #expect(!SplitPaneChrome.drawsOwnBackdrop(sharedBySplit: true))
}

/// The trailing pane darkens its top edge to the leading page's depth, even when its own
/// bar is shorter (iPhone Duo vertical bar); the leading pane keeps its own height.
@Test func trailingTopScrimMatchesTheParentPage() {
    #expect(SplitPaneChrome.topScrimHeight(pane: .trailing, own: 52, leading: 150) == 150)
    #expect(SplitPaneChrome.topScrimHeight(pane: .trailing, own: 52, leading: nil) == 52)
    #expect(SplitPaneChrome.topScrimHeight(pane: .leading, own: 150, leading: 120) == 150)
    #expect(SplitPaneChrome.topScrimHeight(pane: nil, own: 106, leading: 150) == 106)
}

// MARK: - Full-page insets

/// A pane's bar gets a window edge's margin on both edges: the trailing pane's leading
/// edge sits mid-window, where UIKit reports a zero minimum (title flush with the divider,
/// operator 2026-10-05). Larger existing margins (safe areas) are kept.
@Test func paneBarMarginsMatchAWindowEdge() {
    let trailingPane = SplitPaneChrome.barMargins(current: (0, 20), windowEdge: 20)
    #expect(trailingPane.leading == 20 && trailingPane.trailing == 20)
    let leadingPane = SplitPaneChrome.barMargins(current: (20, 0), windowEdge: 20)
    #expect(leadingPane.leading == 20 && leadingPane.trailing == 20)
    let safeArea = SplitPaneChrome.barMargins(current: (20, 104), windowEdge: 20)
    #expect(safeArea.leading == 20 && safeArea.trailing == 104)
}

/// Each pane lays out from the divider band with its own margins: the safe area at its
/// mid-window edge (the Duo vertical bar's 84 pt on the leading pane) is ignored, but
/// a full-width leading pane keeps the window edge's safe area.
@Test func paneSafeAreaIgnoredOnlyAtTheDividerEdge() {
    #expect(SplitPaneChrome.edgesFacingDivider(role: .leading, isOpen: true) == .trailing)
    #expect(SplitPaneChrome.edgesFacingDivider(role: .leading, isOpen: false) == [])
    #expect(SplitPaneChrome.edgesFacingDivider(role: .trailing, isOpen: true) == .leading)
    // Widened over the list page (a profile, #352): the window's leading edge.
    #expect(SplitPaneChrome.edgesFacingDivider(role: .trailing, isOpen: false) == [])
    #expect(SplitPaneChrome.edgesFacingDivider(role: nil, isOpen: false) == [])
}
