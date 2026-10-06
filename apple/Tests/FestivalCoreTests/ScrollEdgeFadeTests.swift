import Foundation
import Testing
@testable import FestivalCore

// MARK: - Ramps (issue #308)

/// The web ramps: `useScrollMask` 40 px at top edges, `useScrollFade` 36 px at bottom
/// chrome.
@Test func scrollEdgeRampsMatchTheWeb() {
    #expect(ScrollEdgeFade.topDistance == 40)
    #expect(ScrollEdgeFade.distance == 36)
}

/// Accessibility settings turn any ramp into a hard edge; bad input never fades.
@Test func scrollEdgeRampBecomesAHardEdge() {
    #expect(ScrollEdgeFade.ramp(ScrollEdgeFade.topDistance, hardEdge: false) == 40)
    #expect(ScrollEdgeFade.ramp(ScrollEdgeFade.distance, hardEdge: false) == 36)
    #expect(ScrollEdgeFade.ramp(ScrollEdgeFade.topDistance, hardEdge: true) == 0)
    #expect(ScrollEdgeFade.ramp(ScrollEdgeFade.distance, hardEdge: true) == 0)
    #expect(ScrollEdgeFade.ramp(-4, hardEdge: false) == 0)
    #expect(ScrollEdgeFade.ramp(.nan, hardEdge: false) == 0)
    #expect(ScrollEdgeFade.ramp(.infinity, hardEdge: false) == 0)
}

/// A hard edge cuts rows exactly at the chrome's top: no ramp, nothing beneath.
@Test func bottomHardEdgeCutsAtChromeTop() {
    let stops = ScrollEdgeFade.bottom(
        height: 800, obscured: 200, distance: ScrollEdgeFade.ramp(ScrollEdgeFade.distance, hardEdge: true)
    )
    #expect(stops.fadeStart == 0.75)
    #expect(stops.fadeEnd == 0.75)
}

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

/// Overflow is the content left below the unobscured bottom: positive mid-list, 0 at
/// the end, negative for a short or overscrolled list.
@Test func contentOverflowTracksListEnd() {
    // 1,500 pt of rows in a 800 pt view with 120 pt chrome and a 100 pt top inset.
    #expect(ScrollEdgeFade.contentOverflow(
        contentHeight: 1500, offsetY: -100, containerHeight: 800, bottomInset: 120
    ) == 920)
    #expect(ScrollEdgeFade.contentOverflow(
        contentHeight: 1500, offsetY: 820, containerHeight: 800, bottomInset: 120
    ) == 0)
    #expect(ScrollEdgeFade.contentOverflow(
        contentHeight: 1500, offsetY: 850, containerHeight: 800, bottomInset: 120
    ) == -30)
    #expect(ScrollEdgeFade.contentOverflow(
        contentHeight: 300, offsetY: -100, containerHeight: 800, bottomInset: 120
    ) == -280)
    #expect(ScrollEdgeFade.contentOverflow(
        contentHeight: .nan, offsetY: 0, containerHeight: 800, bottomInset: 0
    ) == nil)
}

/// Readings at the end of an iPhone 17 Pro board (issue #305): a `ScrollView`'s
/// `containerSize` leaves out its 116 pt top and 135 pt bottom insets, so only the
/// full `visibleRect` height reaches 0 there; a `List` reports both as the full height.
@Test func contentOverflowReachesZeroWithFullScrollViewHeight() {
    #expect(ScrollEdgeFade.contentOverflow(
        contentHeight: 1441, offsetY: 702, containerHeight: 874, bottomInset: 135
    ) == 0)
    #expect(ScrollEdgeFade.contentOverflow(
        contentHeight: 1441, offsetY: 702, containerHeight: 623, bottomInset: 135
    ) == 251)
    #expect(ScrollEdgeFade.contentOverflow(
        contentHeight: 1520, offsetY: 785, containerHeight: 874, bottomInset: 139
    ) == 0)
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

/// Band boards (issue #305) pad the card stack's bottom by a full row gap, so the
/// pinned pager adds nothing and the last card rests one gap above it.
@Test func pinnedPagerAddsNothingWhenCardsCarryTheGap() {
    let band = PinnedChromeSpacing.resolve(
        rowGap: 6, rowBottomInset: 6, edgePadding: 8, hasFooter: false, hasPager: true
    )
    #expect(band == .init(footerTop: 0, footerBottom: 0, pagerTop: 0))
}

// MARK: - Accessibility hard edge (scroll-edge R7, issue #305)

/// Reduce Transparency or Increase Contrast turn the bottom ramp into a hard cut at
/// the chrome's top edge; with neither the scroll-driven fade height is kept.
@Test(arguments: [(false, false, 36.0), (true, false, 0.0), (false, true, 0.0), (true, true, 0.0)])
func bottomFadeIsAHardEdgeForAccessibility(reduceTransparency: Bool, increaseContrast: Bool, expected: Double) {
    #expect(ScrollEdgeFade.accessibleDistance(
        36, reduceTransparency: reduceTransparency, increaseContrast: increaseContrast
    ) == expected)
    #expect(ScrollEdgeFade.accessibleDistance(
        12.5, reduceTransparency: reduceTransparency, increaseContrast: increaseContrast
    ) == (expected == 0 ? 0 : 12.5))
}

/// A zero-height fade puts the opaque and clear stops on the chrome's top edge: rows
/// are fully drawn right up to it and still clear beneath it.
@Test func hardEdgeStopsMeetAtChromeTop() {
    let stops = ScrollEdgeFade.bottom(
        height: 800, obscured: 200,
        distance: ScrollEdgeFade.accessibleDistance(36, reduceTransparency: true, increaseContrast: false)
    )
    #expect(stops == .init(fadeStart: 0.75, fadeEnd: 0.75))
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
