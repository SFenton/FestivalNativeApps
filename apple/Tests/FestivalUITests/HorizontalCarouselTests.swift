import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - Columns

/// One card on the outer display (or a half-fold region at outer width), two on the
/// inner display, never more than three.
@Test(arguments: [
    (CGFloat(0), 1), (320, 1), (466, 1), (669, 2), (951, 2), (2000, 3),
])
func carouselColumns(width: CGFloat, expected: Int) {
    #expect(CarouselPaging.columns(width: width, minimumCardWidth: 300, spacing: 12, margin: 16) == expected)
}

/// A degenerate minimum width never divides by zero.
@Test func carouselColumnsGuardZeroMinimum() {
    #expect(CarouselPaging.columns(width: 669, minimumCardWidth: 0, spacing: 12, margin: 16) == 1)
}

// MARK: - Paging

/// Adjustable steps clamp at both ends (no wrap, so VoiceOver hears the ends).
@Test func carouselStepClamps() {
    #expect(CarouselPaging.step(from: 0, count: 5, forward: true) == 1)
    #expect(CarouselPaging.step(from: 4, count: 5, forward: true) == 4)
    #expect(CarouselPaging.step(from: 0, count: 5, forward: false) == 0)
    #expect(CarouselPaging.step(from: 3, count: 5, forward: false) == 2)
    #expect(CarouselPaging.step(from: 0, count: 0, forward: true) == 0)
}

/// Endless sources load within two cards of the end, and only while more exist.
@Test func carouselLoadsMoreNearEnd() {
    #expect(!CarouselPaging.shouldLoadMore(appearing: 6, count: 10, hasMore: true))
    #expect(CarouselPaging.shouldLoadMore(appearing: 7, count: 10, hasMore: true))
    #expect(CarouselPaging.shouldLoadMore(appearing: 9, count: 10, hasMore: true))
    #expect(!CarouselPaging.shouldLoadMore(appearing: 9, count: 10, hasMore: false))
    #expect(!CarouselPaging.shouldLoadMore(appearing: 0, count: 0, hasMore: true))
}

// MARK: - Indicator

/// Dots for short finite carousels, a counter otherwise.
@Test func carouselIndicatorStyle() {
    #expect(!CarouselPaging.usesDots(count: 1, hasMore: false))
    #expect(CarouselPaging.usesDots(count: 2, hasMore: false))
    #expect(CarouselPaging.usesDots(count: 10, hasMore: false))
    #expect(!CarouselPaging.usesDots(count: 11, hasMore: false))
    #expect(!CarouselPaging.usesDots(count: 4, hasMore: true))
}

/// Visible counter and spoken value.
@Test func carouselCounterAndValue() {
    #expect(CarouselPaging.counter(index: 2, count: 12, hasMore: false) == "3 / 12")
    #expect(CarouselPaging.counter(index: 2, count: 12, hasMore: true) == "3 / 12+")
    #expect(CarouselPaging.accessibilityValue(index: 2, count: 12, hasMore: false) == "Page 3 of 12")
    #expect(CarouselPaging.accessibilityValue(index: 0, count: 10, hasMore: true) == "Page 1 of 10, more available")
}
