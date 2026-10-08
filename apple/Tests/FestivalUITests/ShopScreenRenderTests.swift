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

/// Where the Shop list is hosted for the wide-columns checks (issue #378).
enum ShopListPlacement: String, CaseIterable, CustomTestStringConvertible {
    /// A Mac page wider than tall: two columns.
    case wide
    /// A page taller than wide: one column.
    case tall
    /// The wide page at an accessibility text size: one column.
    case wideAccessibility

    var testDescription: String { rawValue }

    var size: CGSize {
        self == .tall ? CGSize(width: 760, height: 1000) : CGSize(width: 1100, height: 760)
    }

    var typeSize: DynamicTypeSize { self == .wideAccessibility ? .accessibility3 : .large }

    var columns: Int { self == .wide ? 2 : 1 }
}

/// Item Shop list rows pair row-major in a wide page and stay one column on a tall page
/// or at accessibility sizes; switching to the grid and back reuses the loaded Shop
/// instead of reading it again (pattern `wide-columns` R1/R2/R4, issue #378).
@MainActor
@Test(.serialized, arguments: ShopListPlacement.allCases)
func shopListUsesTwoColumnsOnlyInWideLayouts(placement: ShopListPlacement) async throws {
    nativeHostedEnableAccessibility()
    let bytes = try shopFixtureBytes()
    let suiteName = "fst-shop-columns-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    storage.set(ShopViewMode.list.rawValue, forKey: "fst.shop.viewMode")
    let transport = HostedShopTransport(
        scenario: .populated, offers: bytes.offers, catalogue: bytes.catalogue
    )
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let size = placement.size
    let host = nativeHostedView(
        NavigationStack {
            ShopScreen(session: session, isVisible: true)
        }
        .frame(width: size.width, height: size.height)
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
        .environment(\.horizontalSizeClass, .regular)
        .environment(\.dynamicTypeSize, placement.typeSize),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let ids = ["fixture-pulse", "fixture-orbit"].map { "fst.shop.external.\($0)" }
    let image = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        ids.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
    }
    _ = try nativeHostedPNG(
        image, filename: "shop-list-columns-\(placement.rawValue).png", environment: "FST_SHOP_RENDER_OUT"
    )
    let frames = try ids.map { try #require(nativeHostedAccessibilityFrame($0, in: host)) }
        .sorted { ($0.minY, $0.minX) < ($1.minY, $1.minX) }
    if placement.columns == 2 {
        #expect(abs(frames[0].minY - frames[1].minY) < 1, "\(placement): the second offer is not beside the first")
        #expect(frames[1].minX > frames[0].maxX + WideColumns.spacing, "\(placement): no second column")
    } else {
        #expect(frames[1].minY > frames[0].maxY, "\(placement): the second offer is not under the first")
        #expect(abs(frames[1].minX - frames[0].minX) < 1)
    }
    let reads = await transport.recordedPaths()
    guard placement == .wide else { return }
    storage.set(ShopViewMode.grid.rawValue, forKey: "fst.shop.viewMode")
    try await nativeHostedSettle(host, timeout: .seconds(30)) {
        nativeHostedAccessibilityFrame(ids[0], in: host) != nil
    }
    storage.set(ShopViewMode.list.rawValue, forKey: "fst.shop.viewMode")
    try await nativeHostedSettle(host, timeout: .seconds(30)) {
        ids.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
    }
    #expect(await transport.recordedPaths() == reads, "Switching List and Grid read the Shop again")
}

/// Owns an injected iPhone Duo layout so a test can fold the same Shop in place.
@MainActor
private final class ShopLayoutBox: ObservableObject {
    @Published var layout: DeviceLayout
    init(_ layout: DeviceLayout) { self.layout = layout }
}

/// The Shop under a swappable device layout.
private struct ShopLayoutHost: View {
    @ObservedObject var box: ShopLayoutBox
    let session: FestivalSession
    let storage: UserDefaults

    var body: some View {
        NavigationStack {
            ShopScreen(session: session, isVisible: true)
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
        .environment(\.horizontalSizeClass, .regular)
        .environment(\.deviceLayout, box.layout)
    }
}

/// On the unfolded iPhone Duo the two list columns meet at the hinge only in book pose
/// and at the page's midpoint flat; folding reflows the loaded rows without reading the
/// Shop again (pattern `wide-columns` R3/R4, `hinge-columns`, issue #378).
@MainActor
@Test func shopListColumnsMeetAtTheHingeOnlyInBookPose() async throws {
    nativeHostedEnableAccessibility()
    let size = CGSize(width: 951, height: 669)
    // Off the middle, so the book-pose gutter cannot pass for the flat midpoint.
    let fold = CGRect(x: 420, y: 0, width: 30, height: 669)
    let flat = DeviceLayout.resolve(LayoutSignals(
        size: size, widthClass: .regular, hinge: .fullyOpen, hinges: [fold]
    ))
    let book = DeviceLayout.resolve(LayoutSignals(
        size: size, widthClass: .regular, hinge: .partiallyOpen, divisions: [fold], hinges: [fold]
    ))
    let bytes = try shopFixtureBytes()
    let suiteName = "fst-shop-hinge-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suiteName))
    defer { storage.removePersistentDomain(forName: suiteName) }
    storage.set(true, forKey: "fst.accessibility.reduceMotion")
    storage.set(ShopViewMode.list.rawValue, forKey: "fst.shop.viewMode")
    let transport = HostedShopTransport(
        scenario: .populated, offers: bytes.offers, catalogue: bytes.catalogue
    )
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let box = ShopLayoutBox(flat)
    let host = nativeHostedView(ShopLayoutHost(box: box, session: session, storage: storage), size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let ids = ["fixture-pulse", "fixture-orbit"].map { "fst.shop.song.\($0)" }

    /// The two rows, leading first, once the gutter's middle settles at `middle`.
    func rows(meetingAt middle: CGFloat) async throws -> [CGRect] {
        var frames: [CGRect] = []
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            frames = ids.compactMap { nativeHostedAccessibilityFrame($0, in: host) }.sorted { $0.minX < $1.minX }
            return frames.count == 2 && abs((frames[0].maxX + frames[1].minX) / 2 - middle) < 1.5
        }
        return frames
    }

    let flatRows = try await rows(meetingAt: size.width / 2)
    #expect(abs(flatRows[0].minY - flatRows[1].minY) < 1, "flat: the rows are not side by side")
    #expect(abs(flatRows[0].width - flatRows[1].width) < 1.5, "flat: uneven columns")
    let reads = await transport.recordedPaths()

    box.layout = book
    let bookRows = try await rows(meetingAt: fold.midX)
    #expect(abs(bookRows[0].maxX - fold.minX) < 1.5, "book: the leading column does not end at the fold")
    #expect(abs(bookRows[1].minX - fold.maxX) < 1.5, "book: the trailing column does not start at the fold")
    #expect(await transport.recordedPaths() == reads, "Folding read the Shop again")
}
#endif
