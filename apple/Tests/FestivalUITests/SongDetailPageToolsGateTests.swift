#if os(macOS)
import AppKit
import Observation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// The reads Song Details' first-load gate waits for that a test can hold back.
private enum HeldRead: Sendable {
    /// The cards' top-ten leaderboard reads.
    case leaderboard
    /// The Item Shop feed.
    case shop

    /// Which held read `request` is, if any.
    ///
    /// - Parameter request: Keyless public GET built by `FestivalAPI`.
    /// - Returns: The read kind, or nil for reads that always pass.
    static func kind(of request: URLRequest) -> Self? {
        let path = request.url?.path ?? ""
        if path.hasPrefix("/api/leaderboard/") { return .leaderboard }
        if path == "/api/shop" { return .shop }
        return nil
    }
}

/// Forwards to the loopback fixture service, holding leaderboard and Item Shop reads
/// (the reads Song Details' first-load gate waits for) until they are released, and
/// optionally failing the Shop read (the gate's completed-no-offer state).
private actor HeldGateTransport: HTTPTransport {
    private let base = URLSessionHTTPTransport()
    private var holding: Set<HeldRead> = [.leaderboard, .shop]
    private var held: [HeldRead: [CheckedContinuation<Void, Never>]] = [:]
    private var heldReads: [HeldRead: Int] = [:]
    private var finishedReads: [HeldRead: Int] = [:]
    private let failsShop: Bool

    /// - Parameter failsShop: Answer the Shop read with a transport failure.
    init(failsShop: Bool = false) {
        self.failsShop = failsShop
    }

    /// Send `request`, first waiting for its release when it is a held read.
    ///
    /// - Parameter request: Keyless public GET built by `FestivalAPI`.
    /// - Returns: The fixture service's response.
    /// - Throws: Transport failures from the fixture service, or the Shop failure.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let kind = HeldRead.kind(of: request) else { return try await base.send(request) }
        if holding.contains(kind) {
            heldReads[kind, default: 0] += 1
            await withCheckedContinuation { held[kind, default: []].append($0) }
        }
        defer { finishedReads[kind, default: 0] += 1 }
        if kind == .shop, failsShop { throw URLError(.notConnectedToInternet) }
        return try await base.send(request)
    }

    /// Hold `kind` reads again from now on.
    ///
    /// - Parameter kind: Read kind.
    func hold(_ kind: HeldRead) { holding.insert(kind) }

    /// Let every held `kind` read, and later ones, through.
    ///
    /// - Parameter kind: Read kind.
    func release(_ kind: HeldRead) {
        holding.remove(kind)
        held[kind]?.forEach { $0.resume() }
        held[kind] = []
    }

    /// Let every held read through.
    func releaseAll() {
        release(.leaderboard)
        release(.shop)
    }

    /// `kind` reads held so far.
    ///
    /// - Parameter kind: Read kind.
    /// - Returns: Their count.
    func heldCount(_ kind: HeldRead) -> Int { heldReads[kind, default: 0] }

    /// `kind` reads answered so far.
    ///
    /// - Parameter kind: Read kind.
    /// - Returns: Their count.
    func finishedCount(_ kind: HeldRead) -> Int { finishedReads[kind, default: 0] }
}

/// Every distinct tool count the accessory's front page went through, read once per
/// main-actor turn after a change (so tools that register in one update count once).
@MainActor
private final class PageToolCountRecorder {
    private(set) var counts: [Int] = []
    private let registry: PageToolsRegistry

    init(_ registry: PageToolsRegistry) {
        self.registry = registry
        track()
    }

    private func track() {
        let count = withObservationTracking { registry.frontItems.count } onChange: { [weak self] in
            Task { @MainActor in self?.track() }
        }
        if counts.last != count { counts.append(count) }
    }
}

/// Host Song Details for `fixture-pulse` in a `NavigationStack` above the real
/// tab-bar accessory bar, as on iPhone (its tools register in `registry`).
@MainActor
private func hostSongDetailWithAccessory(
    session: FestivalSession, storage: UserDefaults, registry: PageToolsRegistry
) async throws -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow) {
    let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(AnyView(
        VStack(spacing: 0) {
            NavigationStack {
                SongDetailScreen(song: song, session: session, visibleInstruments: [.lead, .bass])
                    .pageToolsScope(inSelectedTab: true)
            }
            PageToolsAccessoryBar(registry: registry)
                .frame(height: NavButtonAccessibilityTests.accessoryHeight)
                .buttonStyle(.borderless)
        }
        .environment(\.pageToolsRegistry, registry)
        .environment(\.festivalSession, session)
        .defaultAppStorage(storage)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark)
    ), size: size)
    return (host, nativeHostedWindow(host, size: size))
}

/// Song Details' tools in accessory order.
private let songDetailToolIDs = ["fst.song-detail.shop", "fst.song-detail.paths", "fst.quick-links.open"]

// MARK: - Tests

/// Song Details' page tools wait for the first-load gate (load-transition R1, #585).
///
/// Item Shop, Paths and Quick Links act on the loaded page, so none registers in the
/// iPhone tab-bar accessory or reaches VoiceOver while the spinner is up. The gate
/// includes the Item Shop read, so the applicable set is known before it appears: the
/// tools register together with the content, in accessory order with their names, each
/// a whole 44 pt slot (HIG Accessibility: "Strive for the platform's recommended minimum
/// control size"), and stay while the cards reload.
@MainActor
@Suite(.serialized) struct SongDetailPageToolsGateTests {
    /// Opens Song Details with the Shop unknown (as from a deep link), holding the Shop
    /// response past the card reads: no tool shows early, then all three in one update.
    @Test func songDetailToolsWaitForTheLoadGateAndStayThroughReloads() async throws {
        let transport = HeldGateTransport()
        let (session, storage, suite) = try await makeSession(transport)
        defer { storage.removePersistentDomain(forName: suite) }
        #expect(session.currentShop == nil, "the Shop is not known yet")

        let registry = PageToolsRegistry()
        let recorder = PageToolCountRecorder(registry)
        let (host, window) = try await hostSongDetailWithAccessory(
            session: session, storage: storage, registry: registry
        )
        defer {
            window.orderOut(nil)
            Task { await transport.releaseAll() }
        }

        // Loading: the spinner and no tool, in the accessory or the accessibility tree.
        try await waitFor(host) {
            let cards = await transport.heldCount(.leaderboard)
            let shop = await transport.heldCount(.shop)
            return cards > 0 && shop > 0
        }
        #expect(await transport.heldCount(.leaderboard) > 0, "the gate's leaderboard reads are held")
        #expect(await transport.heldCount(.shop) == 1, "the gate reads the Shop once")
        try await nativeHostedSettle(host, until: {
            nativeHostedAccessibilityElement("fst.song-detail.loading", in: host) != nil
        })
        expectNoTools(registry, host)

        // The cards have loaded but the Shop has not answered: still the spinner and no
        // tool, so Paths and Quick Links never show before the Item Shop action.
        await transport.release(.leaderboard)
        try await waitFor(host) {
            let held = await transport.heldCount(.leaderboard)
            return await transport.finishedCount(.leaderboard) >= held
        }
        try await idle(host, for: .milliseconds(500))
        #expect(nativeHostedAccessibilityElement("fst.song-detail.loading", in: host) != nil)
        expectNoTools(registry, host)

        // Loaded: all three at once, in order, named, full slots.
        await transport.release(.shop)
        try await nativeHostedSettle(host, until: {
            songDetailToolIDs.allSatisfy { nativeHostedAccessibilityElement($0, in: host) != nil }
        })
        #expect(nativeHostedAccessibilityElement("fst.song-detail.loading", in: host) == nil)
        #expect(registry.frontItems.count == 3)
        #expect(recorder.counts == [0, 3], "the tools appear together: \(recorder.counts)")
        let nodes = macAccessibilityTree(host)
        let tools = nodes.filter { songDetailToolIDs.contains($0.identifier) && $0.isElement }
        #expect(tools.map(\.identifier) == songDetailToolIDs, "accessory reading order: \(tools)")
        #expect(tools.first?.spokenName.hasPrefix("Item Shop") == true, "\(tools)")
        #expect(tools.dropFirst().map(\.spokenName) == ["Paths", "Quick Links"])
        for id in songDetailToolIDs {
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: host))
            #expect(frame.width >= PageToolsAccessoryFit.slot - 0.5, "\(id) \(frame)")
            #expect(frame.height >= PageToolsAccessoryFit.slot - 0.5, "\(id) \(frame)")
        }

        // A quiet reload (invalid-score filtering reloads every card): the tools stay.
        await transport.hold(.leaderboard)
        let before = await transport.heldCount(.leaderboard)
        storage.set(true, forKey: "fst.settings.filterInvalidScores")
        try await waitFor(host) { await transport.heldCount(.leaderboard) > before }
        #expect(await transport.heldCount(.leaderboard) > before, "the cards reload")
        host.layoutSubtreeIfNeeded()
        #expect(registry.frontItems.count == 3, "the tools stay while the cards reload")
        #expect(songDetailToolIDs.allSatisfy { nativeHostedAccessibilityElement($0, in: host) != nil })
        await transport.releaseAll()
        #expect(recorder.counts == [0, 3], "no tool left or came back: \(recorder.counts)")
    }

    /// A failed Shop read completes the gate with no offer: the page reveals with its
    /// Shop status notice, and Paths and Quick Links register together.
    @Test func failedShopReadRevealsTheOtherToolsTogether() async throws {
        let transport = HeldGateTransport(failsShop: true)
        let (session, storage, suite) = try await makeSession(transport)
        defer { storage.removePersistentDomain(forName: suite) }

        let registry = PageToolsRegistry()
        let recorder = PageToolCountRecorder(registry)
        let (host, window) = try await hostSongDetailWithAccessory(
            session: session, storage: storage, registry: registry
        )
        defer {
            window.orderOut(nil)
            Task { await transport.releaseAll() }
        }

        try await waitFor(host) {
            let cards = await transport.heldCount(.leaderboard)
            let shop = await transport.heldCount(.shop)
            return cards > 0 && shop > 0
        }
        await transport.release(.leaderboard)
        try await waitFor(host) {
            let held = await transport.heldCount(.leaderboard)
            return await transport.finishedCount(.leaderboard) >= held
        }
        try await idle(host, for: .milliseconds(500))
        expectNoTools(registry, host)

        await transport.release(.shop)
        let remaining = Array(songDetailToolIDs.dropFirst())
        try await nativeHostedSettle(host, until: {
            remaining.allSatisfy { nativeHostedAccessibilityElement($0, in: host) != nil }
        })
        #expect(nativeHostedAccessibilityElement("fst.song-detail.shop", in: host) == nil)
        #expect(nativeHostedAccessibilityElement("fst.song-detail.shop-error", in: host) != nil)
        #expect(registry.frontItems.count == 2)
        #expect(recorder.counts == [0, 2], "the tools appear together: \(recorder.counts)")
    }

    /// The rule behind the gate: nothing before the content shows; then Shop only with
    /// an offer, Paths only with a path chart, and Quick Links always.
    @Test func songDetailPageToolsResolveFromTheGate() {
        #expect(SongDetailPageTools.resolve(contentShown: false, hasShopOffer: true, hasPathCharts: true)
            == SongDetailPageTools(shop: false, paths: false, quickLinks: false))
        #expect(SongDetailPageTools.resolve(contentShown: true, hasShopOffer: true, hasPathCharts: true)
            == SongDetailPageTools(shop: true, paths: true, quickLinks: true))
        #expect(SongDetailPageTools.resolve(contentShown: true, hasShopOffer: false, hasPathCharts: false)
            == SongDetailPageTools(shop: false, paths: false, quickLinks: true))
    }

    // MARK: Helpers

    /// A session on the loopback fixture service through `transport`, with its own
    /// settings suite.
    ///
    /// - Parameter transport: The holding transport.
    /// - Returns: The session, its settings and the suite name to remove afterwards.
    private func makeSession(
        _ transport: HeldGateTransport
    ) async throws -> (FestivalSession, UserDefaults, String) {
        let baseURL = try await RivalsMockService.shared.baseURL()
        let client = try FestivalAPI(baseURL: baseURL, transport: transport)
        let suite = "fst.tests.song-detail-tools.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        return (FestivalSession(factory: { client }, selectionStorage: storage), storage, suite)
    }

    /// Lay out `host` until `condition` holds or 20 s pass.
    ///
    /// - Parameters:
    ///   - host: Hosted Song Details.
    ///   - condition: What to wait for.
    private func waitFor(
        _ host: NSView, _ condition: () async -> Bool
    ) async throws {
        var budget = NativeHostedPollBudget(.seconds(20))
        while await !condition(), !budget.isExhausted {
            host.layoutSubtreeIfNeeded()
            try await budget.sleep(for: .milliseconds(50))
        }
    }

    /// Keep laying out `host` for `duration`, so anything the page would do next shows.
    ///
    /// - Parameters:
    ///   - host: Hosted Song Details.
    ///   - duration: How long to wait.
    private func idle(_ host: NSView, for duration: Duration) async throws {
        let end = ContinuousClock.now + duration
        while ContinuousClock.now < end {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
        host.layoutSubtreeIfNeeded()
    }

    /// No Song Details tool in the accessory or the accessibility tree.
    ///
    /// - Parameters:
    ///   - registry: The accessory's registry.
    ///   - host: Hosted Song Details.
    private func expectNoTools(_ registry: PageToolsRegistry, _ host: NSView) {
        #expect(registry.frontItems.isEmpty, "no page tool while the spinner is up")
        let ids = nativeHostedAccessibility(host).identifiers
        #expect(songDetailToolIDs.allSatisfy { !ids.contains($0) }, "\(ids)")
    }
}
#endif
