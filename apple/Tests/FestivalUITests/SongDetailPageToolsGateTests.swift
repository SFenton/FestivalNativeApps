#if os(macOS)
import AppKit
import Observation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// Forwards to the loopback fixture service, holding leaderboard reads (the reads Song
/// Details' first-load gate waits for) until ``release()``.
private actor HeldLeaderboardTransport: HTTPTransport {
    private let base = URLSessionHTTPTransport()
    private var holding = true
    private var held: [CheckedContinuation<Void, Never>] = []
    private var heldReads = 0

    /// Send `request`, first waiting for ``release()`` when it is a held leaderboard read.
    ///
    /// - Parameter request: Keyless public GET built by `FestivalAPI`.
    /// - Returns: The fixture service's response.
    /// - Throws: Transport failures from the fixture service.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        if holding, request.url?.path.hasPrefix("/api/leaderboard/") == true {
            heldReads += 1
            await withCheckedContinuation { held.append($0) }
        }
        return try await base.send(request)
    }

    /// Hold leaderboard reads again from now on.
    func hold() { holding = true }

    /// Let every held read, and later ones, through.
    func release() {
        holding = false
        held.forEach { $0.resume() }
        held = []
    }

    /// Leaderboard reads held so far.
    ///
    /// - Returns: Their count.
    func heldCount() -> Int { heldReads }
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
                    .pageToolsScope()
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
/// iPhone tab-bar accessory or reaches VoiceOver while the spinner is up. They appear
/// together with the content, in accessory order with their names, each a whole 44 pt
/// slot (HIG Accessibility: "Strive for the platform's recommended minimum control
/// size"), and stay while the cards reload.
@MainActor
@Suite(.serialized) struct SongDetailPageToolsGateTests {
    @Test func songDetailToolsWaitForTheLoadGateAndStayThroughReloads() async throws {
        let baseURL = try await RivalsMockService.shared.baseURL()
        let transport = HeldLeaderboardTransport()
        let client = try FestivalAPI(baseURL: baseURL, transport: transport)
        let suite = "fst.tests.song-detail-tools.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        // The Shop is already known, as when Song Details opens from Songs.
        _ = try await session.shop()
        #expect(session.shopOffersById["fixture-pulse"] != nil)

        let registry = PageToolsRegistry()
        let recorder = PageToolCountRecorder(registry)
        let (host, window) = try await hostSongDetailWithAccessory(
            session: session, storage: storage, registry: registry
        )
        defer {
            window.orderOut(nil)
            Task { await transport.release() }
        }

        // Loading: the spinner and no tool, in the accessory or the accessibility tree.
        var budget = NativeHostedPollBudget(.seconds(20))
        while await transport.heldCount() == 0, !budget.isExhausted {
            host.layoutSubtreeIfNeeded()
            try await budget.sleep(for: .milliseconds(50))
        }
        #expect(await transport.heldCount() > 0, "the gate's leaderboard reads are held")
        try await nativeHostedSettle(host, until: {
            nativeHostedAccessibilityElement("fst.song-detail.loading", in: host) != nil
        })
        #expect(registry.frontItems.isEmpty, "no page tool while the spinner is up")
        let loadingIDs = nativeHostedAccessibility(host).identifiers
        #expect(songDetailToolIDs.allSatisfy { !loadingIDs.contains($0) }, "\(loadingIDs)")

        // Loaded: all three at once, in order, named, full slots.
        await transport.release()
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
        await transport.hold()
        let before = await transport.heldCount()
        storage.set(true, forKey: "fst.settings.filterInvalidScores")
        budget = NativeHostedPollBudget(.seconds(20))
        while await transport.heldCount() == before, !budget.isExhausted {
            host.layoutSubtreeIfNeeded()
            try await budget.sleep(for: .milliseconds(50))
        }
        #expect(await transport.heldCount() > before, "the cards reload")
        host.layoutSubtreeIfNeeded()
        #expect(registry.frontItems.count == 3, "the tools stay while the cards reload")
        #expect(songDetailToolIDs.allSatisfy { nativeHostedAccessibilityElement($0, in: host) != nil })
        await transport.release()
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
}
#endif
