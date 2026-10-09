#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Host the phone Shop list with saved Shop filter preferences (issues #19, #376) over
/// the synthetic feed: one New offer (gold border) and one Leaving Tomorrow offer (red
/// border), no plain offers.
///
/// - Parameters:
///   - name: Evidence file stem.
///   - save: Writes the saved filter (or older "show only" switches) into the app storage.
///   - settled: Stops polling once the accents show the expected rows.
///   - inspect: Reads the settled host (accessibility tree, element frames).
/// - Returns: Accent counts of the settled render.
@MainActor
private func renderFilteredShop(
    name: String, save: (UserDefaults) -> Void,
    settled: ((gold: Int, red: Int, bright: Int)) -> Bool,
    inspect: ((NSView) -> Void)? = nil
) async throws -> (gold: Int, red: Int, bright: Int) {
    let bytes = try shopFixtureBytes()
    let suiteName = "fst-shop-filter-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.accessibility.lessTransparency")
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    save(storage)
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
        let accents = shopStatusPixels(image)
        last = (accents.gold, accents.red, nativeHostedControlPixels(image).bright)
        _ = try nativeHostedPNG(
            image, filename: "shop-filter-\(name).png", environment: "FST_SHOP_RENDER_OUT"
        )
        if settled(last) { break }
    }
    inspect?(host)
    return last
}

/// Host the Shop with a saved filter.
///
/// - Parameters:
///   - filter: The saved Shop filter.
///   - name: Evidence file stem.
///   - settled: Stops polling once the accents show the expected rows.
///   - inspect: Reads the settled host (accessibility tree, element frames).
/// - Returns: Accent counts of the settled render.
@MainActor
private func renderFilteredShop(
    _ filter: ShopOfferFilter, name: String,
    settled: ((gold: Int, red: Int, bright: Int)) -> Bool,
    inspect: ((NSView) -> Void)? = nil
) async throws -> (gold: Int, red: Int, bright: Int) {
    try await renderFilteredShop(
        name: name,
        save: { $0.set(filter.encoded(), forKey: ShopOfferFilter.storageKey) },
        settled: settled, inspect: inspect
    )
}

/// A fresh Shop filter (every switch on) lists both the New and Leaving Tomorrow offers.
@MainActor
@Test func shopFilterDefaultShowsEveryOffer() async throws {
    let all = try await renderFilteredShop(ShopOfferFilter(), name: "default") {
        $0.gold > 10 && $0.red > 10
    }
    #expect(all.gold > 10)
    #expect(all.red > 10)
}

/// Turning Leaving Tomorrow off hides the red offer; turning New off hides the gold one.
@MainActor
@Test func shopFilterHidesSwitchedOffAvailability() async throws {
    let hideLeaving = try await renderFilteredShop(
        ShopOfferFilter(leavingTomorrow: false), name: "hide-leaving"
    ) { $0.gold > 10 }
    #expect(hideLeaving.gold > 10)
    #expect(hideLeaving.red < 5)
    let hideNew = try await renderFilteredShop(
        ShopOfferFilter(new: false), name: "hide-new"
    ) { $0.red > 10 }
    #expect(hideNew.red > 10)
    #expect(hideNew.gold < 5)
}

/// Saved "show only" switches from before issue #376 keep the same offers on screen.
@MainActor
@Test func shopFilterMigratesSavedShowOnlySwitches() async throws {
    let newOnly = try await renderFilteredShop(
        name: "legacy-new",
        save: { $0.set(true, forKey: ShopOfferFilter.legacyNewKey) },
        settled: { $0.gold > 10 }
    )
    #expect(newOnly.gold > 10)
    #expect(newOnly.red < 5)
    let noneSelected = try await renderFilteredShop(
        name: "legacy-none",
        save: { storage in
            for key in [
                ShopOfferFilter.legacyNewKey, ShopOfferFilter.legacyAvailableKey,
                ShopOfferFilter.legacyLeavingTomorrowKey,
            ] { storage.set(false, forKey: key) }
        },
        settled: { $0.gold > 10 && $0.red > 10 }
    )
    #expect(noneSelected.gold > 10)
    #expect(noneSelected.red > 10)
}

/// A filter that hides every offer shows the shared centred empty state (issue #377):
/// web-modelled copy, no card, no Reset Filters button, centred in the page.
@MainActor
@Test func shopFilterWithNoMatchesShowsCentredEmptyState() async throws {
    var tree = NativeHostedAccessibility(texts: [], identifiers: [])
    var frame: CGRect?
    var hostSize = CGSize.zero
    let none = try await renderFilteredShop(
        ShopOfferFilter(new: false, leavingTomorrow: false), name: "no-match",
        settled: { _ in false },
        inspect: { host in
            tree = nativeHostedAccessibility(host)
            frame = nativeHostedAccessibilityFrame("fst.shop.filter-empty", in: host)
            hostSize = host.bounds.size
        }
    )
    #expect(none.bright > 20)
    // No gold New border, and no red at all: the Reset Filters button is gone.
    #expect(none.gold < 5)
    #expect(none.red < 5)
    #expect(tree.contains(ShopEmptyCopy.filteredTitle))
    #expect(tree.contains(ShopEmptyCopy.filteredSubtitle))
    #expect(!tree.contains("Reset Filters"))
    #expect(!tree.identifiers.contains("fst.shop.filter-empty.reset"))
    #expect(!tree.contains("No offers match these filters"))
    // Centred horizontally in the page, and below the page's top half-way mark.
    let empty = try #require(frame)
    #expect(abs(empty.midX - hostSize.width / 2) < 2)
    #expect(empty.midY > hostSize.height * 0.35)
}

/// The sheet paints its switch rows and Reset over the Festival sheet surface.
@MainActor
@Test func shopFilterSheetPaints() async throws {
    let size = CGSize(width: 420, height: 360)
    let host = nativeHostedView(
        ShopFilterSheet(applied: ShopOfferFilter(leavingTomorrow: false)) { _ in }
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

/// The Filter button announces the switched-off groups in display order.
@Test func shopFilterButtonAccessibilityValue() {
    #expect(ShopScreen.filterAccessibilityValue(ShopOfferFilter()) == "No filters")
    #expect(
        ShopScreen.filterAccessibilityValue(ShopOfferFilter(new: false, leavingTomorrow: false))
            == "Hiding New, Leaving Tomorrow"
    )
    #expect(
        ShopScreen.filterAccessibilityValue(
            ShopOfferFilter(new: false, available: false, leavingTomorrow: false)
        ) == "Hiding New, Available, Leaving Tomorrow"
    )
    #expect(ShopAvailability.allCases.allSatisfy { !ShopFilterSheet.hint($0).isEmpty })
}
#endif
