#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

private enum HostedShopScenario: Sendable {
    case populated
    case empty
    case unavailable
}

private actor HostedShopTransport: HTTPTransport {
    let scenario: HostedShopScenario
    let offers: Data
    let catalogue: Data
    private var paths: [String] = []

    /// Pin a synthetic Shop feed and optional catalogue to one publication.
    ///
    /// - Parameters:
    ///   - scenario: Populated, verified empty or real HTTP failure.
    ///   - offers: Original local Shop JSON, not a production response.
    ///   - catalogue: Matching original synthetic Songs JSON.
    init(scenario: HostedShopScenario, offers: Data, catalogue: Data) {
        self.scenario = scenario
        self.offers = offers
        self.catalogue = catalogue
    }

    /// Reject writes, privileged headers, wrong generations and non-fixture reads.
    ///
    /// - Parameter request: One native public GET made while the sheet is hosted.
    /// - Returns: Pinned publication, validated offers or explicit HTTP 503.
    /// - Throws: Unsafe method, headers, route or catalogue access.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        if url.path == "/api/publication" {
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        guard request.value(forHTTPHeaderField: "X-FST-Publication-Id") == "7" else {
            throw FestivalAPIError.invalidPublication
        }
        paths.append(url.path)
        switch url.path {
        case "/api/shop":
            switch scenario {
            case .populated:
                return HTTPResult(
                    status: 200, data: offers,
                    headers: ["X-FST-Publication-Id": "7"]
                )
            case .empty:
                return HTTPResult(
                    status: 200,
                    data: Data(#"{"count":0,"songs":[],"newSongs":[]}"#.utf8),
                    headers: ["X-FST-Publication-Id": "7"]
                )
            case .unavailable:
                return HTTPResult(
                    status: 503, data: Data(#"{"status":"fixture_unavailable"}"#.utf8)
                )
            }
        case "/api/songs" where scenario == .populated:
            return HTTPResult(
                status: 200, data: catalogue,
                headers: ["X-FST-Publication-Id": "7"]
            )
        default:
            throw FestivalAPIError.invalidResource
        }
    }

    /// Prove that a verified-empty Shop never asks for irrelevant song details.
    ///
    /// - Returns: Ordered paths read only through the fake transport.
    func recordedPaths() -> [String] { paths }
}

/// Real native New and Leaving accents must paint on separate offer cards.
///
/// - Parameter image: Native AppKit-backed Shop bitmap.
/// - Returns: Sampled gold and red status pixels, not catalogue text.
@MainActor
private func shopStatusPixels(_ image: CGImage) -> (gold: Int, red: Int) {
    let bitmap = NSBitmapImageRep(cgImage: image)
    var gold = 0
    var red = 0
    for y in stride(from: 0, to: image.height, by: 4) {
        for x in stride(from: 0, to: image.width, by: 4) {
            guard let color = bitmap.colorAt(x: x, y: y) else { continue }
            let r = color.redComponent
            let g = color.greenComponent
            let b = color.blueComponent
            if r > 0.7 && g > 0.5 && b < 0.25 { gold += 1 }
            if r > 0.5 && g < 0.3 && b < 0.35 { red += 1 }
        }
    }
    return (gold, red)
}

/// Resolve original Shop and Songs fixture bytes without a live service.
///
/// - Returns: Publication-compatible synthetic offer and catalogue envelopes.
/// - Throws: Missing checked-in local fixture.
private func shopFixtureBytes() throws -> (offers: Data, catalogue: Data) {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    return (
        try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/shop-demo.json")),
        try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/songs-demo.json"))
    )
}

/// Host real List, grid and accessibility-size rows with both official offer states.
@MainActor
@Test func shopScreenPaintsValidatedPopulatedLayouts() async throws {
    let bytes = try shopFixtureBytes()
    let suiteName = "fst-shop-render-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.accessibility.lessTransparency")
    let cases: [(CGSize, UserInterfaceSizeClass, DynamicTypeSize, String)] = [
        (CGSize(width: 820, height: 1180), .regular, .large, "wide-grid"),
        (CGSize(width: 390, height: 844), .compact, .large, "phone-list"),
        (CGSize(width: 820, height: 1180), .regular, .accessibility5, "wide-ax5-list"),
    ]
    var snapshots: [Data] = []
    for (size, sizeClass, typeSize, name) in cases {
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
            .environment(\.horizontalSizeClass, sizeClass)
            .environment(\.dynamicTypeSize, typeSize),
            size: size
        )
        let window = sizeClass == .compact || typeSize.isAccessibilitySize
            ? nativeHostedWindow(host, size: size) : nil
        #expect(window?.isVisible != true)
        var painted: CGImage?
        var lastImage: CGImage?
        var lastAccents = (gold: 0, red: 0)
        for _ in 0..<30 {
            let image = try nativeHostedImage(host)
            let accents = shopStatusPixels(image)
            lastImage = image
            lastAccents = accents
            if accents.red > 10 && (typeSize.isAccessibilitySize || accents.gold > 10) {
                painted = image
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        if painted == nil, let lastImage {
            _ = try nativeHostedPNG(
                lastImage, filename: "shop-\(name)-unpainted.png",
                environment: "FST_SHOP_RENDER_OUT"
            )
        }
        let paths = await transport.recordedPaths()
        let error = session.shopError ?? "none"
        let count = session.currentShop?.shop.count ?? -1
        let diagnostic: Comment = """
        Synthetic \(name) Shop offers never painted; paths \(paths),
        shop error \(error), feed count \(count),
        gold \(lastAccents.gold), red \(lastAccents.red)
        """
        let image = try #require(painted, diagnostic)
        let measured = nativeHostedControlPixels(image)
        #expect(measured.bright > 20)
        #expect(paths.contains("/api/shop") && paths.contains("/api/songs"))
        #expect(paths.allSatisfy { $0 == "/api/shop" || $0 == "/api/songs" })
        snapshots.append(try nativeHostedPNG(
            image, filename: "shop-\(name).png",
            environment: "FST_SHOP_RENDER_OUT"
        ))
        withExtendedLifetime(window) {}
    }
    #expect(snapshots[0] != snapshots[1])
    #expect(snapshots[1] != snapshots[2])
}

/// An actual 503 and a validated empty feed must never paint the same state.
@MainActor
@Test func shopScreenDistinguishesEmptyFromUnavailable() async throws {
    let bytes = try shopFixtureBytes()
    let suiteName = "fst-shop-outcomes-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.accessibility.lessTransparency")
    var snapshots: [Data] = []
    for scenario: HostedShopScenario in [.empty, .unavailable] {
        let transport = HostedShopTransport(
            scenario: scenario, offers: bytes.offers, catalogue: bytes.catalogue
        )
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let host = nativeHostedView(
            NavigationStack {
                ShopScreen(session: session, isVisible: true)
            }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue),
            size: CGSize(width: 390, height: 844)
        )
        for _ in 0..<30 {
            if scenario == .empty, session.currentShop?.shop.count == 0 { break }
            if scenario == .unavailable, session.shopError != nil { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        if scenario == .empty {
            #expect(session.currentShop?.shop.count == 0)
        } else {
            #expect(session.shopError != nil && session.currentShop == nil)
        }
        try await Task.sleep(for: .milliseconds(50))
        let image = try nativeHostedImage(host)
        #expect(nativeHostedControlPixels(image).bright > 20)
        let name = scenario == .empty ? "empty" : "error"
        snapshots.append(try nativeHostedPNG(
            image, filename: "shop-\(name).png",
            environment: "FST_SHOP_RENDER_OUT"
        ))
        let paths = await transport.recordedPaths()
        #expect(paths.contains("/api/shop") && !paths.contains("/api/songs"))
        #expect(paths.allSatisfy { $0 == "/api/shop" })
    }
    #expect(snapshots[0] != snapshots[1])
}
#endif
