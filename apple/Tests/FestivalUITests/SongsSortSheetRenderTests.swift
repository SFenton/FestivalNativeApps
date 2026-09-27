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
/// - Parameter image: Real native Sort content inside its opaque dark host surface.
/// - Returns: Nonblack purple pixels across the content's middle row.
@MainActor
private func sortFormSurfacePixels(_ image: CGImage) -> Int {
    let bitmap = NSBitmapImageRep(cgImage: image)
    let row = image.height * 2 / 5
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
        #expect(pixels.selected > 10)
        #expect(pixels.placeholder == 0)
        #expect(sortFormSurfacePixels(image) > image.width / 8)
        images[scenario.name] = try nativeHostedPNG(
            image, filename: "songs-sort-\(scenario.name).png",
            environment: "FST_SORT_RENDER_OUT"
        )
    }
    #expect(images["phone-default"] != images["phone-shop-unavailable"])
    #expect(images["wide-artist-descending"] != images["wide-shop-loaded"])
    #expect(images["wide-shop-loaded"] != images["wide-shop-hidden"])
}
#endif
