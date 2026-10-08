#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Reading position of the gold (New) and red (Leaving Tomorrow) accents in a rendered
/// Shop: mean row for the list, mean column for a single-row grid.
///
/// - Parameters:
///   - image: The hosted Shop render.
///   - columns: Whether to measure across (grid) rather than down (list).
/// - Returns: Average sampled position of each accent, or nil where it is missing.
@MainActor
private func accentPositions(_ image: CGImage, columns: Bool) -> (gold: CGFloat?, red: CGFloat?) {
    let bitmap = NSBitmapImageRep(cgImage: image)
    var gold: [CGFloat] = []
    var red: [CGFloat] = []
    for y in stride(from: 0, to: image.height, by: 4) {
        for x in stride(from: 0, to: image.width, by: 4) {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            let (r, g, b) = (color.redComponent, color.greenComponent, color.blueComponent)
            let position = CGFloat(columns ? x : y)
            if r > 0.7 && g > 0.5 && b < 0.25 { gold.append(position) }
            if r > 0.5 && g < 0.3 && b < 0.35 { red.append(position) }
        }
    }
    func mean(_ rows: [CGFloat]) -> CGFloat? {
        rows.count < 10 ? nil : rows.reduce(0, +) / CGFloat(rows.count)
    }
    return (mean(gold), mean(red))
}

/// Host the phone list or the wide grid Shop with a saved sort over the synthetic feed: Fixture Orbit
/// (Leaving Tomorrow, red border) sorts before Fixture Pulse (New, gold border) by title.
///
/// - Parameters:
///   - choice: The saved Shop sort.
///   - grid: Whether the saved view mode is the grid.
///   - name: Evidence file stem.
/// - Returns: Mean accent positions of the settled render.
@MainActor
private func renderSortedShop(
    _ choice: ShopSortChoice, grid: Bool, name: String
) async throws -> (gold: CGFloat?, red: CGFloat?) {
    let bytes = try shopFixtureBytes()
    let suiteName = "fst-shop-sort-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.accessibility.lessTransparency")
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    storage.set(choice.mode.rawValue, forKey: ShopSortChoice.modeKey)
    storage.set(choice.ascending, forKey: ShopSortChoice.ascendingKey)
    storage.set(grid ? "grid" : "list", forKey: "fst.shop.viewMode")
    let size = grid ? CGSize(width: 820, height: 1180) : CGSize(width: 390, height: 844)
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
        .environment(\.horizontalSizeClass, grid ? .regular : .compact),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { withExtendedLifetime(window) {} }
    for _ in 0..<30 {
        if session.currentShop != nil { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    var last: (gold: CGFloat?, red: CGFloat?) = (nil, nil)
    for _ in 0..<30 {
        try await Task.sleep(for: .milliseconds(100))
        let image = try nativeHostedImage(host)
        last = accentPositions(image, columns: grid)
        _ = try nativeHostedPNG(
            image, filename: "shop-sort-\(name).png", environment: "FST_SHOP_RENDER_OUT"
        )
        if last.gold != nil && last.red != nil { break }
    }
    return last
}

/// The saved sort orders the list and the grid alike (issue #379).
@MainActor
@Test func shopSortOrdersListAndGrid() async throws {
    for grid in [false, true] {
        let mode = grid ? "grid" : "list"
        let ascending = try await renderSortedShop(ShopSortChoice(), grid: grid, name: "\(mode)-title-up")
        let descending = try await renderSortedShop(
            ShopSortChoice(mode: .title, ascending: false), grid: grid, name: "\(mode)-title-down"
        )
        let upGold = try #require(ascending.gold)
        let upRed = try #require(ascending.red)
        let downGold = try #require(descending.gold)
        let downRed = try #require(descending.red)
        // Orbit (red) before Pulse (gold) ascending; reversed descending.
        #expect(upRed < upGold, "\(mode) ascending")
        #expect(downGold < downRed, "\(mode) descending")
    }
}

/// The Shop's Sort sheet lists only the four catalogue modes under its own identifiers.
@MainActor
@Test func shopSortSheetPaintsCatalogueModes() async throws {
    let size = CGSize(width: 390, height: 844)
    var images: [String: Data] = [:]
    for (name, choice) in [
        ("default", ShopSortChoice()),
        ("duration-descending", ShopSortChoice(mode: .duration, ascending: false)),
    ] {
        let host = nativeHostedView(
            SongsSortSheet(
                mode: choice.mode, ascending: choice.ascending,
                modes: ShopSortChoice.modes, identifier: "fst.shop.sort",
                onApply: { _, _ in }
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .background(BrandTokens.appBackground),
            size: size
        )
        let image = try nativeHostedImage(host)
        #expect(nativeHostedControlPixels(image).bright > 20)
        images[name] = try nativeHostedPNG(
            image, filename: "shop-sort-sheet-\(name).png", environment: "FST_SHOP_RENDER_OUT"
        )
    }
    #expect(images["default"] != images["duration-descending"])
}

/// The Sort button names the paused Duration fallback.
@Test func shopSortChoiceDescribesPausedDuration() {
    let paused = ShopSortChoice(mode: .duration, ascending: false)
    #expect(paused.accessibilityValue(paused: true) == "Duration, descending, paused; showing Title order")
    #expect(!ShopScreen.sortPausedMessage.isEmpty)
}
#endif
