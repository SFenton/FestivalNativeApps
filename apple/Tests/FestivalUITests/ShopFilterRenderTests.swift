#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Host the phone Shop list with a saved New / Available / Leaving Tomorrow filter
/// (issue #19) over the synthetic feed: one New offer (gold border) and one Leaving
/// Tomorrow offer (red border), no plain offers.
///
/// - Parameters:
///   - filter: The saved Shop filter.
///   - name: Evidence file stem.
/// - Returns: Accent counts of the settled render.
@MainActor
private func renderFilteredShop(
    _ filter: ShopOfferFilter, name: String
) async throws -> (gold: Int, red: Int, bright: Int) {
    let bytes = try shopFixtureBytes()
    let suiteName = "fst-shop-filter-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.accessibility.lessTransparency")
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    storage.set(filter.new, forKey: "fst.shop.filterNew")
    storage.set(filter.available, forKey: "fst.shop.filterAvailable")
    storage.set(filter.leavingTomorrow, forKey: "fst.shop.filterLeavingTomorrow")
    let size = CGSize(width: 390, height: 844)
    let transport = HostedShopTransport(
        scenario: .populated, offers: bytes.offers, catalogue: bytes.catalogue
    )
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let host = nativeHostedView(
        NavigationStack {
            ShopScreen(session: session, isVisible: true)
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
        .tint(BrandTokens.accentBlue)
        .environment(\.horizontalSizeClass, .compact),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { withExtendedLifetime(window) {} }
    for _ in 0..<30 {
        if session.currentShop != nil { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(session.currentShop?.shop.count == 2)
    // The reload gate holds its spinner briefly even under Reduce Motion (issue #71),
    // then the catalogue read and art priming finish.
    var last = (gold: 0, red: 0, bright: 0)
    for _ in 0..<30 {
        try await Task.sleep(for: .milliseconds(100))
        let image = try nativeHostedImage(host)
        let accents = nativeHostedStatusPixels(image)
        last = (accents.gold, accents.red, nativeHostedControlPixels(image).bright)
        _ = try nativeHostedPNG(
            image, filename: "shop-filter-\(name).png", environment: "FST_SHOP_RENDER_OUT"
        )
        if (filter.new && last.gold > 10) || (filter.leavingTomorrow && last.red > 10) {
            break
        }
    }
    return last
}

/// New shows only the gold New offer; Leaving Tomorrow only the red one.
@MainActor
@Test func shopFilterShowsOnlySelectedAvailability() async throws {
    let new = try await renderFilteredShop(ShopOfferFilter(new: true), name: "new")
    #expect(new.gold > 10)
    #expect(new.red < 5)
    let leaving = try await renderFilteredShop(
        ShopOfferFilter(leavingTomorrow: true), name: "leaving"
    )
    #expect(leaving.red > 10)
    #expect(leaving.gold < 5)
}

/// A filter that hides every offer paints the no-match card, not a highlighted row.
@MainActor
@Test func shopFilterWithNoMatchesPaintsResetCard() async throws {
    let none = try await renderFilteredShop(ShopOfferFilter(available: true), name: "no-match")
    #expect(none.bright > 20)
    // No gold New border; the only red is the Reset Filters text, not a Leaving border.
    #expect(none.gold < 5)
}

/// The sheet paints its switch rows and Reset over the Festival sheet surface.
@MainActor
@Test func shopFilterSheetPaints() async throws {
    let size = CGSize(width: 420, height: 360)
    let host = nativeHostedView(
        ShopFilterSheet(applied: ShopOfferFilter(new: true)) { _ in }
            .macSheetFrame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { withExtendedLifetime(window) {} }
    try await Task.sleep(for: .milliseconds(200))
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "shop-filter-sheet.png", environment: "FST_SHOP_RENDER_OUT")
    #expect(nativeHostedControlPixels(image).bright > 20)
}

/// The Filter button announces the selected groups in display order.
@Test func shopFilterButtonAccessibilityValue() {
    #expect(ShopScreen.filterAccessibilityValue(ShopOfferFilter()) == "No filters")
    #expect(
        ShopScreen.filterAccessibilityValue(ShopOfferFilter(new: true, leavingTomorrow: true))
            == "New, Leaving Tomorrow"
    )
    #expect(ShopAvailability.allCases.allSatisfy { !ShopFilterSheet.hint($0).isEmpty })
}
#endif
