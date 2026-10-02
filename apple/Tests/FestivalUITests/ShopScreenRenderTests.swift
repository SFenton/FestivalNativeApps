#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

enum HostedShopScenario: Sendable {
    case populated
    case empty
    case unavailable
}

actor HostedShopTransport: HTTPTransport {
    let scenario: HostedShopScenario
    let offers: Data
    let catalogue: Data
    let player: Data?
    let rolloverPlayer: Data?
    let rolloverOffers: Data?
    let failSongsAfterRollover: Bool
    private var generation = 7
    private var requests: [(generation: Int, path: String)] = []

    /// Pin a synthetic Shop feed and optional catalogue to one publication.
    ///
    /// - Parameters:
    ///   - scenario: Populated, verified empty or real HTTP failure.
    ///   - offers: Original local Shop JSON, not a production response.
    ///   - catalogue: Matching original synthetic Songs JSON.
    ///   - player: Optional fixture player profile for selected Songs renders.
    ///   - rolloverPlayer: Distinct selected score bytes after the generation changes.
    ///   - rolloverOffers: Changed Shop membership only after a test advances publication.
    ///   - failSongsAfterRollover: Reproduce a retained old catalogue after generation eight.
    init(
        scenario: HostedShopScenario, offers: Data, catalogue: Data,
        player: Data? = nil, rolloverPlayer: Data? = nil,
        rolloverOffers: Data? = nil,
        failSongsAfterRollover: Bool = false
    ) {
        self.scenario = scenario
        self.offers = offers
        self.catalogue = catalogue
        self.player = player
        self.rolloverPlayer = rolloverPlayer
        self.rolloverOffers = rolloverOffers
        self.failSongsAfterRollover = failSongsAfterRollover
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
            {"contractVersion":1,"publicationId":\(generation),"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        guard request.value(forHTTPHeaderField: "X-FST-Publication-Id")
                == String(generation) else {
            throw FestivalAPIError.invalidPublication
        }
        requests.append((generation, url.path))
        switch url.path {
        case "/api/shop":
            switch scenario {
            case .populated:
                if generation == 8 && failSongsAfterRollover
                    && rolloverOffers == nil {
                    throw FestivalAPIError.invalidShop
                }
                return HTTPResult(
                    status: 200,
                    data: generation == 8 ? (rolloverOffers ?? offers) : offers,
                    headers: ["X-FST-Publication-Id": String(generation)]
                )
            case .empty:
                return HTTPResult(
                    status: 200,
                    data: Data(#"{"count":0,"songs":[],"newSongs":[]}"#.utf8),
                    headers: ["X-FST-Publication-Id": String(generation)]
                )
            case .unavailable:
                return HTTPResult(
                    status: 503, data: Data(#"{"status":"fixture_unavailable"}"#.utf8)
                )
            }
        case "/api/songs":
            if generation == 8 && failSongsAfterRollover {
                return HTTPResult(
                    status: 503, data: Data(#"{"status":"fixture_unavailable"}"#.utf8)
                )
            }
            return HTTPResult(
                status: 200, data: catalogue,
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        case "/api/player/fixture-player-2":
            guard let player else { throw FestivalAPIError.invalidResource }
            return HTTPResult(
                status: 200,
                data: generation == 8 ? (rolloverPlayer ?? player) : player,
                headers: ["X-FST-Publication-Id": String(generation)]
            )
        default:
            throw FestivalAPIError.invalidResource
        }
    }

    /// Prove that a verified-empty Shop never asks for irrelevant song details.
    ///
    /// - Returns: Ordered paths read only through the fake transport.
    func recordedPaths() -> [String] { requests.map(\.path) }

    /// Advance only this in-memory fixture after the first generation is proven.
    func advancePublication() { generation = 8 }

    /// Verify the exact generation and route of each synthetic product GET.
    ///
    /// - Returns: Logged generation/route pairs without account or payload content.
    func recordedGenerationPaths() -> [String] {
        requests.map { "\($0.generation):\($0.path)" }
    }
}

/// Resolve original Shop and Songs fixture bytes without a live service.
///
/// - Returns: Publication-compatible synthetic offer and catalogue envelopes.
/// - Throws: Missing checked-in local fixture.
func shopFixtureBytes() throws -> (offers: Data, catalogue: Data) {
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
    // Load-in fades (`festivalFadeIn`) would otherwise be captured mid-animation.
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
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
        var lastAccents = (gold: 0, green: 0, red: 0)
        for _ in 0..<30 {
            let image = try nativeHostedImage(host)
            let accents = nativeHostedStatusPixels(image)
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
    // Load-in fades (`festivalFadeIn`) would otherwise be captured mid-animation.
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
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
        // The reload gate holds its spinner briefly even under Reduce Motion (issue #71).
        try await Task.sleep(
            for: ReloadTransition.Timing.standard(reduceMotion: true).minimumSpinner + .milliseconds(150)
        )
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
