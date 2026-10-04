import Foundation
import Testing
@testable import FestivalCore

// MARK: - Bottom scroll edge fade (issue #93)

/// Rows fade over 36 pt above the chrome and are clear beneath it.
@Test func bottomFadeEndsAtChromeTop() {
    let stops = ScrollEdgeFade.bottom(height: 800, obscured: 200)
    #expect(stops.fadeEnd == 0.75)
    #expect(stops.fadeStart == 564.0 / 800)
}

/// No chrome: the fade sits on the bottom edge.
@Test func bottomFadeWithoutChromeUsesBottomEdge() {
    let stops = ScrollEdgeFade.bottom(height: 360, obscured: 0)
    #expect(stops.fadeEnd == 1)
    #expect(stops.fadeStart == 0.9)
}

/// Chrome taller than the area, negative input or an empty area clamp safely.
@Test func bottomFadeClampsDegenerateGeometry() {
    #expect(ScrollEdgeFade.bottom(height: 100, obscured: 400) == .init(fadeStart: 0, fadeEnd: 0))
    #expect(ScrollEdgeFade.bottom(height: 100, obscured: 80) == .init(fadeStart: 0, fadeEnd: 0.2))
    #expect(ScrollEdgeFade.bottom(height: 100, obscured: -10) == .init(fadeStart: 0.64, fadeEnd: 1))
    #expect(ScrollEdgeFade.bottom(height: 0, obscured: 10) == .init(fadeStart: 1, fadeEnd: 1))
    #expect(ScrollEdgeFade.bottom(height: .nan, obscured: 10) == .init(fadeStart: 1, fadeEnd: 1))
    #expect(ScrollEdgeFade.bottom(height: 100, obscured: .infinity) == .init(fadeStart: 1, fadeEnd: 1))
}

// MARK: - End-of-list fade and chrome spacing (issue #293)

/// Far from the end the full fade shows; it shrinks to nothing as the last row
/// reaches its resting place, so no band is reserved below it.
@Test func bottomFadeDistanceShrinksAtListEnd() {
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: nil) == 36)
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: 200) == 36)
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: 12.5) == 12.5)
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: 0) == 0)
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: -40) == 0)
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: .infinity) == 36)
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: -.infinity) == 0)
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: .nan) == 0)
    #expect(ScrollEdgeFade.bottomDistance(lastRowOverflow: 5, distance: -1) == 0)
}

/// The last row rests one row gap above the footer, or above the pager when the
/// player has no score; the footer rests one row gap above the pager.
@Test func pinnedChromeKeepsRowGap() {
    let both = PinnedChromeSpacing.resolve(
        rowGap: 8, rowBottomInset: 4, edgePadding: 8, hasFooter: true, hasPager: true
    )
    #expect(both == .init(footerTop: 4, footerBottom: 0, pagerTop: 8))
    let pagerOnly = PinnedChromeSpacing.resolve(
        rowGap: 8, rowBottomInset: 4, edgePadding: 8, hasFooter: false, hasPager: true
    )
    #expect(pagerOnly.pagerTop == 4)
    let footerOnly = PinnedChromeSpacing.resolve(
        rowGap: 8, rowBottomInset: 4, edgePadding: 8, hasFooter: true, hasPager: false
    )
    #expect(footerOnly == .init(footerTop: 4, footerBottom: 8, pagerTop: 8))
    let degenerate = PinnedChromeSpacing.resolve(
        rowGap: 2, rowBottomInset: 6, edgePadding: -3, hasFooter: true, hasPager: false
    )
    #expect(degenerate == .init(footerTop: 0, footerBottom: 0, pagerTop: 2))
}

// MARK: - Selected player on page while paging (issue #93)

/// Loaded rows decide, case-insensitively, regardless of the rank's page.
@Test func selectedOnPageUsesLoadedRows() {
    #expect(LeaderboardPaging.isSelectedOnPage(
        accountId: "ABC", rank: 80, page: 1, pageSize: 25, entries: ["x", "abc"]
    ))
    #expect(!LeaderboardPaging.isSelectedOnPage(
        accountId: "abc", rank: 3, page: 1, pageSize: 25, entries: ["x", "y"]
    ))
}

/// While the next page loads, the rank's page decides.
@Test func selectedOnPageFallsBackToRankWhileLoading() {
    #expect(LeaderboardPaging.isSelectedOnPage(
        accountId: "abc", rank: 26, page: 2, pageSize: 25, entries: nil
    ))
    #expect(!LeaderboardPaging.isSelectedOnPage(
        accountId: "abc", rank: 25, page: 2, pageSize: 25, entries: nil
    ))
    #expect(!LeaderboardPaging.isSelectedOnPage(
        accountId: "abc", rank: 0, page: 1, pageSize: 25, entries: nil
    ))
}
