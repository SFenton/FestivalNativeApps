#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

/// Exact saved-mode and feed/Settings state without a production Shop request.
private struct HostedSortScenario {
    let mode: SongSortMode
    let ascending: Bool
    let showShop: Bool
    let shopAvailable: Bool
    let size: CGSize
    let typeSize: DynamicTypeSize
    let name: String
}

/// Refuse a black, unpresented Form masquerading as selected text and radio dots.
///
/// - Parameters:
///   - image: Real native Form content inside its opaque dark host surface.
///   - rowFraction: The rendered content row, not empty space around a short Form.
/// - Returns: Nonblack purple pixels across the requested content row.
@MainActor
private func songFormSurfacePixels(
    _ image: CGImage, rowFraction: CGFloat = 0.4
) -> Int {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let row = Int(CGFloat(image.height) * rowFraction)
    return stride(from: 0, to: image.width, by: 4).reduce(0) { count, x in
        guard let color = bitmap.colorAt(x: x, y: row) else { return count }
        let red = color.redComponent
        let green = color.greenComponent
        let blue = color.blueComponent
        return count + (
            red > 0.04 && red < 0.2 && green < 0.12
                && blue > red + 0.02 && blue < 0.4 ? 1 : 0
        )
    }
}

/// Render each real native draft, conditional Shop and AX footer state.
@MainActor
@Test func songsSortSheetPaintsConditionalModesAndSavedDrafts() throws {
    let cases: [HostedSortScenario] = [
        HostedSortScenario(
            mode: .title, ascending: true, showShop: false, shopAvailable: false,
            size: CGSize(width: 390, height: 844), typeSize: .large, name: "phone-default"
        ),
        HostedSortScenario(
            mode: .title, ascending: true, showShop: true, shopAvailable: false,
            size: CGSize(width: 390, height: 844), typeSize: .large, name: "phone-shop-unavailable"
        ),
        HostedSortScenario(
            mode: .artist, ascending: false, showShop: true, shopAvailable: true,
            size: CGSize(width: 820, height: 1180), typeSize: .large, name: "wide-artist-descending"
        ),
        HostedSortScenario(
            mode: .shop, ascending: false, showShop: true, shopAvailable: true,
            size: CGSize(width: 820, height: 1180), typeSize: .large, name: "wide-shop-loaded"
        ),
        HostedSortScenario(
            mode: .shop, ascending: true, showShop: false, shopAvailable: true,
            size: CGSize(width: 820, height: 1180), typeSize: .large, name: "wide-shop-hidden"
        ),
        HostedSortScenario(
            mode: .shop, ascending: false, showShop: true, shopAvailable: true,
            size: CGSize(width: 390, height: 844), typeSize: .accessibility5,
            name: "phone-shop-ax5"
        ),
    ]
    var images: [String: Data] = [:]
    for scenario in cases {
        let host = nativeHostedView(
            SongsSortSheet(
                mode: scenario.mode, ascending: scenario.ascending,
                showShop: scenario.showShop, shopAvailable: scenario.shopAvailable,
                onApply: { _, _ in }
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .environment(\.dynamicTypeSize, scenario.typeSize)
            .background(BrandTokens.appBackground),
            size: scenario.size
        )
        let image = try nativeHostedImage(host)
        let scale = CGFloat(image.width) / scenario.size.width
        #expect((1...3).contains(scale))
        #expect(abs(CGFloat(image.height) / scenario.size.height - scale) < 0.02)
        let pixels = nativeHostedControlPixels(image)
        #expect(pixels.bright > 20)
        // The selected direction is purple (web), so accent-blue "selected" pixels come
        // only from the mode checkmark, which a hidden Shop mode can leave off-screen.
        #expect(pixels.placeholder == 0)
        #expect(songFormSurfacePixels(image) > image.width / 8)
        images[scenario.name] = try nativeHostedPNG(
            image, filename: "songs-sort-\(scenario.name).png",
            environment: "FST_SORT_RENDER_OUT"
        )
    }
    #expect(images["phone-default"] != images["phone-shop-unavailable"])
    #expect(images["wide-artist-descending"] != images["wide-shop-loaded"])
    #expect(images["wide-shop-loaded"] != images["wide-shop-hidden"])
}

/// Host the actual native Filter Form in available, paused and accessibility states.
@MainActor
@Test func songsShopFilterSheetPaintsDraftAvailabilityAndLargeText() throws {
    let cases: [(
        name: String, filter: SongShopFilter, showShop: Bool,
        shopAvailable: Bool, profileAvailable: Bool,
        size: CGSize, typeSize: DynamicTypeSize
    )] = [
        ("phone-default", SongShopFilter(), true, true, true,
         CGSize(width: 390, height: 844), .large),
        ("phone-no-feed", SongShopFilter(), true, false, true,
         CGSize(width: 390, height: 844), .large),
        ("phone-profile-pending", SongShopFilter(inShop: true), true, true, false,
         CGSize(width: 390, height: 844), .large),
        ("wide-in-shop", SongShopFilter(inShop: true), true, true, true,
         CGSize(width: 820, height: 1180), .large),
        ("wide-leaving", SongShopFilter(leavingTomorrow: true), true, true, true,
         CGSize(width: 820, height: 1180), .large),
        ("wide-hidden", SongShopFilter(inShop: true), false, true, true,
         CGSize(width: 820, height: 1180), .large),
        ("phone-leaving-ax5", SongShopFilter(leavingTomorrow: true), true, true, true,
         CGSize(width: 390, height: 844), .accessibility5),
    ]
    var images: [String: Data] = [:]
    for scenario in cases {
        let host = nativeHostedView(
            SongsFilterSheet(
                applied: scenario.filter, showShop: scenario.showShop,
                shopAvailable: scenario.shopAvailable,
                profileAvailable: scenario.profileAvailable, onApply: { _, _, _ in }
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .environment(\.dynamicTypeSize, scenario.typeSize)
            .background(BrandTokens.appBackground),
            size: scenario.size
        )
        let image = try nativeHostedImage(host)
        let scale = CGFloat(image.width) / scenario.size.width
        #expect((1...3).contains(scale))
        #expect(abs(CGFloat(image.height) / scenario.size.height - scale) < 0.02)
        let pixels = nativeHostedControlPixels(image)
        #expect(pixels.bright > 20)
        #expect(pixels.placeholder == 0)
        #expect(songFormSurfacePixels(image, rowFraction: 0.5) > image.width / 8)
        if scenario.filter.isActive && scenario.showShop
            && scenario.shopAvailable && scenario.profileAvailable {
            #expect(pixels.selected > 10)
        }
        images[scenario.name] = try nativeHostedPNG(
            image, filename: "songs-filter-\(scenario.name).png",
            environment: "FST_FILTER_RENDER_OUT"
        )
    }
    #expect(images["phone-default"] != images["phone-no-feed"])
    #expect(images["phone-default"] != images["phone-profile-pending"])
    #expect(images["wide-in-shop"] != images["wide-leaving"])
    #expect(images["wide-in-shop"] != images["wide-hidden"])
}

/// Render the source's global score checks and per-chart disclosure without a GUI host.
@MainActor
@Test func songsFilterSheetPaintsSelectedScoreAndDisabledStates() throws {
    let both: Set<Instrument> = [.lead, .drums]
    let active = SongPlayerScoreFilter(hasScores: both, missingFCs: [.drums])
    let cases: [(String, SongPlayerScoreFilter, Bool, Bool, DynamicTypeSize)] = [
        ("score-default", SongPlayerScoreFilter(), true, false, .large),
        ("score-global-and-chart", active, true, false, .large),
        ("score-pending", active, false, false, .large),
        ("score-invalid-mode", active, true, true, .large),
        ("score-ax5", active, true, false, .accessibility5),
    ]
    var images: [String: Data] = [:]
    for (name, saved, available, invalidMode, size) in cases {
        let width = CGSize(width: 390, height: 844)
        let host = nativeHostedView(
            SongsFilterSheet(
                applied: SongShopFilter(), showShop: true, shopAvailable: true,
                profileAvailable: available, appliedPlayerFilter: saved,
                visibleInstruments: both, selectedPlayer: true,
                scoreAvailable: available,
                invalidScoreFilteringEnabled: invalidMode,
                onApply: { _, _, _ in }
            )
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
            .environment(\.dynamicTypeSize, size)
            .background(BrandTokens.appBackground),
            size: width
        )
        let image = try nativeHostedImage(host)
        let pixels = nativeHostedControlPixels(image)
        #expect(pixels.bright > 20 && pixels.placeholder == 0)
        #expect(songFormSurfacePixels(image, rowFraction: 0.5) > image.width / 8)
        if name == "score-global-and-chart" {
            #expect(pixels.selected > 10)
        }
        images[name] = try nativeHostedPNG(
            image, filename: "songs-filter-\(name).png",
            environment: "FST_FILTER_RENDER_OUT"
        )
    }
    #expect(images["score-default"] != images["score-global-and-chart"])
    #expect(images["score-global-and-chart"] != images["score-pending"])
    #expect(images["score-global-and-chart"] != images["score-invalid-mode"])
    // AX5 no longer changes the macOS-hosted render: the sheet has no custom title or
    // footer layout that read Dynamic Type (immediate-apply sheet with a toolbar Done).
}
#endif
