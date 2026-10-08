import CoreGraphics
import Testing
@testable import FestivalUI

// MARK: - Shared empty state copy (issue #377)

@Test func combinedEmptyStateReadsTitleThenSubtitle() {
    #expect(FestivalEmptyStateCopy.accessibilityLabel(title: "No Songs Found", subtitle: "Try again.")
            == "No Songs Found. Try again.")
    #expect(FestivalEmptyStateCopy.accessibilityLabel(title: "No Songs Found", subtitle: nil)
            == "No Songs Found")
    #expect(FestivalEmptyStateCopy.accessibilityLabel(title: "No Songs Found", subtitle: "")
            == "No Songs Found")
}

/// The Item Shop's empty states use the web's EmptyState copy (issue #377): the web Shop
/// has no filters, so the filtered state borrows the web's filtered-empty wording, and
/// neither offers a Reset.
@Test func shopEmptyCopyFollowsWeb() {
    #expect(ShopEmptyCopy.emptyTitle == "No songs in the Item Shop")
    #expect(ShopEmptyCopy.emptySubtitle == "Check back later \u{2014} the shop updates regularly.")
    #expect(ShopEmptyCopy.filteredTitle == "No Item Shop songs match your filters")
    #expect(ShopEmptyCopy.filteredSubtitle.hasPrefix("Try changing your filters"))
    for copy in [ShopEmptyCopy.filteredTitle, ShopEmptyCopy.filteredSubtitle] {
        #expect(!copy.localizedCaseInsensitiveContains("reset"))
        #expect(!copy.localizedCaseInsensitiveContains("offers"))
    }
}

#if os(macOS)
import AppKit
import SwiftUI

// MARK: - Hosted placement

/// A filling empty state centres in its whole region, horizontally and vertically.
@MainActor
@Test func fillingEmptyStateCentresInItsRegion() async throws {
    let size = CGSize(width: 390, height: 700)
    let host = nativeHostedView(
        FestivalEmptyState(
            "No Results", systemImage: "magnifyingglass", subtitle: "Try a different search.",
            accessibilityIdentifier: "fst.test.empty"
        )
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { withExtendedLifetime(window) {} }
    try await Task.sleep(for: .milliseconds(200))
    _ = try nativeHostedImage(host)
    let frame = try #require(nativeHostedAccessibilityFrame("fst.test.empty", in: host))
    #expect(abs(frame.midX - size.width / 2) < 2)
    #expect(abs(frame.midY - size.height / 2) < 4)
    let tree = nativeHostedAccessibility(host)
    #expect(tree.contains("No Results"))
    #expect(tree.contains("Try a different search."))
}

/// A combined state is one static element carrying the identifier, read title first.
@MainActor
@Test func combinedEmptyStateIsOneElement() async throws {
    let size = CGSize(width: 390, height: 500)
    let host = nativeHostedView(
        FestivalEmptyState(
            "No Players Found", subtitle: "Check the spelling.", reading: .combined,
            accessibilityIdentifier: "fst.test.combined"
        )
        .frame(width: size.width, height: size.height),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { withExtendedLifetime(window) {} }
    try await Task.sleep(for: .milliseconds(200))
    let tree = nativeHostedAccessibility(host)
    #expect(tree.identifiers.contains("fst.test.combined"))
    #expect(tree.texts.contains("No Players Found. Check the spelling."))
    #expect(!tree.texts.contains("No Players Found"))
}
#endif
