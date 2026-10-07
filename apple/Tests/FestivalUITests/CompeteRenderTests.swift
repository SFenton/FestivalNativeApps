#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixture session
//
// Reuses the same real loopback `tools/mock_service.py` process as
// `RivalsRenderTests.swift` (`RivalsMockService`): `CompeteScreen` combines a
// Rivals section (bypasses `HTTPTransport`, needs a real loopback origin — see
// that file's header comment) with a Leaderboards section (`session.rankings`,
// which *does* go through the injectable transport, but the same real mock
// server answers `/api/rankings/{instrument}` too, so one client/session
// configuration serves both sections consistently).

private let allInstrumentKeys = [
    "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
    "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
    "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
]

@MainActor
private func competeFixtureSession(
    accountId: String, displayName: String = "Fixture Viewer",
    visible: Set<String> = ["fst.settings.showLead"]
) async throws -> (session: FestivalSession, storage: UserDefaults, suite: String) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    let suite = "fst.tests.compete.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": accountId, "displayName": displayName]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    for key in allInstrumentKeys { storage.set(visible.contains(key), forKey: key) }
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    return (session, storage, suite)
}

@MainActor
private func anonymousCompeteSession() async throws -> FestivalSession {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    return FestivalSession(factory: { client })
}

// MARK: - No profile / no instruments

@MainActor
@Test func competeScreenRendersChooseProfileWhenNoPlayerSelected() async throws {
    let session = try await anonymousCompeteSession()
    #expect(session.selectedPlayer == nil)
    let host = nativeHostedView(
        NavigationStack { CompeteScreen(session: session) }
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["No Player Selected", "Choose Profile"])
    _ = try nativeHostedPNG(image, filename: "compete-no-profile.png", environment: "FST_COMPETE_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["No Player Selected", "Choose Profile"])
}

@MainActor
@Test func competeScreenRendersNoInstrumentsEnabledState() async throws {
    let (session, storage, suite) = try await competeFixtureSession(accountId: "fixture-riv", visible: [])
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { CompeteScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host,
        untilText: [
            "Enable at least one instrument in Settings to see leaderboards.",
            "Enable at least one instrument in Settings to see rivals.",
        ]
    )
    _ = try nativeHostedPNG(image, filename: "compete-no-instruments.png", environment: "FST_COMPETE_RENDER_OUT")
    assertRendersContent(
        host, image: image,
        containing: [
            "Enable at least one instrument in Settings to see leaderboards.",
            "Enable at least one instrument in Settings to see rivals.",
        ]
    )
}

// MARK: - Loading (#354)

/// Holds or fails Compete's leaderboard reads, forwarding everything else to the real
/// loopback fixture.
private actor ControlledRankingsTransport: HTTPTransport {
    private let inner = URLSessionHTTPTransport()
    private let delay: Duration
    private let failsRankings: Bool

    init(delay: Duration = .zero, failsRankings: Bool = false) {
        self.delay = delay
        self.failsRankings = failsRankings
    }

    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard request.url?.path.hasPrefix("/api/rankings/") == true else { return try await inner.send(request) }
        try await Task.sleep(for: delay)
        if failsRankings { return HTTPResult(status: 503, data: Data(#"{"error":"unavailable"}"#.utf8)) }
        return try await inner.send(request)
    }
}

@MainActor
private func controlledCompeteHost(
    _ transport: ControlledRankingsTransport, visible: Set<String>, size: CGSize
) async throws -> (host: NSHostingView<some View>, window: NSWindow, cleanup: () -> Void) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: transport)
    let suite = "fst.tests.compete.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": "fixture-riv", "displayName": "Fixture Viewer"]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    for key in allInstrumentKeys { storage.set(visible.contains(key), forKey: key) }
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    let host = nativeHostedView(
        NavigationStack { CompeteScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    return (host, window, {
        window.orderOut(nil)
        storage.removePersistentDomain(forName: suite)
    })
}

/// Like the web's `CompetePage`, the page loads behind one centred spinner: no section
/// or instrument header, and no per-card spinner, shows until every leaderboard and
/// rivals read settles (load-transition R1). It used to show its headers at once with a
/// spinner inside each card (#35, superseded by #354).
@MainActor
@Test func competeScreenShowsOnePageSpinnerUntilEveryReadSettles() async throws {
    let transport = ControlledRankingsTransport(delay: .seconds(4))
    let (host, _, cleanup) = try await controlledCompeteHost(
        transport, visible: ["fst.settings.showLead", "fst.settings.showBass"], size: CGSize(width: 402, height: 1400)
    )
    defer { cleanup() }
    let loading = try await nativeHostedSettle(host, untilText: ["Loading Compete"], timeout: .seconds(30))
    _ = try nativeHostedPNG(loading, filename: "compete-loading.png", environment: "FST_COMPETE_RENDER_OUT")
    // Rivals (no delay) settle first; the page still waits for the held leaderboards.
    try await Task.sleep(for: .milliseconds(500))
    host.layoutSubtreeIfNeeded()
    let pending = nativeHostedAccessibility(host)
    #expect(pending.contains("Loading Compete"))
    #expect(pending.identifiers.contains("fst.compete.loading"))
    for text in ["Leaderboards", "Rivals", "Lead", "Bass", "Fixture Rival Golf", "Loading Lead leaderboard"] {
        #expect(!pending.contains(text), "Compete shows \"\(text)\" before the page loaded")
    }

    let image = try await nativeHostedSettle(
        host, untilText: ["Leaderboards", "Rivals", "Fixture Player 1", "Fixture Rival Golf"],
        excluding: ["Loading"], timeout: .seconds(30)
    )
    assertRendersContent(
        host, image: image, containing: ["Leaderboards", "Fixture Player 1", "Fixture Rival Golf"],
        notContaining: ["Loading"]
    )
}

/// Every leaderboard failing shows one page-wide error, as the web's
/// `allLeaderboardsErrored` empty state does, instead of a header over each failed card.
@MainActor
@Test func competeScreenShowsPageErrorWhenEveryLeaderboardFails() async throws {
    let transport = ControlledRankingsTransport(failsRankings: true)
    let (host, _, cleanup) = try await controlledCompeteHost(
        transport, visible: ["fst.settings.showLead"], size: CGSize(width: 402, height: 900)
    )
    defer { cleanup() }
    let image = try await nativeHostedSettle(
        host, untilText: ["Compete unavailable"], excluding: ["Loading"], timeout: .seconds(30)
    )
    _ = try nativeHostedPNG(image, filename: "compete-page-error.png", environment: "FST_COMPETE_RENDER_OUT")
    assertRendersContent(
        host, image: image, containing: ["Compete unavailable"], notContaining: ["Leaderboards", "Loading"]
    )
}

// MARK: - Loaded: Leaderboards + Rivals sections together

@MainActor
@Test func competeScreenRendersLeaderboardAndRivalsSections() async throws {
    let (session, storage, suite) = try await competeFixtureSession(
        accountId: "fixture-riv", visible: ["fst.settings.showLead", "fst.settings.showBass"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { CompeteScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1800)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1800))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["View Full Leaderboard", "Fixture Player 1", "Fixture Rival Golf"],
        excluding: ["Loading", "Leaderboards Overview"]
    )
    _ = try nativeHostedPNG(
        image, filename: "compete-leaderboards-and-rivals.png", environment: "FST_COMPETE_RENDER_OUT"
    )
    assertRendersContent(
        host, image: image, containing: ["View Full Leaderboard", "Fixture Player 1", "Fixture Rival Golf"],
        notContaining: ["Leaderboards Overview"]
    )
}

/// A 503 from the Rivals endpoints must not blank the Leaderboards cards next to
/// it: the page reveals once every read settled, and each failed card shows its own
/// inline error beside the loaded ones (web `CompetePage` keeps per-card errors too).
@MainActor
@Test func competeScreenRendersRivalsSectionErrorWithLeaderboardsStillLoaded() async throws {
    let (session, storage, suite) = try await competeFixtureSession(
        accountId: "fixture-riv-503", visible: ["fst.settings.showLead"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { CompeteScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1200)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1200))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture Player 1", "Scores are updating"], excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(
        image, filename: "compete-rivals-error-leaderboards-ok.png", environment: "FST_COMPETE_RENDER_OUT"
    )
    assertRendersContent(host, image: image, containing: ["Fixture Player 1", "Scores are updating"])
}

/// The Rivals section's own empty state ("no rivals yet") renders while the
/// Leaderboards section next to it still shows populated rows.
@MainActor
@Test func competeScreenRendersRivalsEmptySection() async throws {
    let (session, storage, suite) = try await competeFixtureSession(
        accountId: "fixture-riv-empty", visible: ["fst.settings.showLead"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { CompeteScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture Player 1", "No rivals found for Lead yet."], excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(image, filename: "compete-rivals-empty.png", environment: "FST_COMPETE_RENDER_OUT")
    // Regression for a fixed product bug: an all-empty Rivals section used to
    // render its "Rivals" header with nothing underneath it (the shared
    // `RivalInstrumentSongSection` hid entirely when a result was empty, which
    // is correct for `RivalsScreen` but left Compete's own section looking
    // broken). It now shows the same honest empty copy as the web
    // (`compete.noRivalsSubtitle`) per instrument, mirroring how the
    // Leaderboards section already never goes fully blank.
    assertRendersContent(
        host, image: image, containing: ["Fixture Player 1", "Rivals", "No rivals found for Lead yet."],
        notContaining: ["Fixture Rival Golf", "Loading"]
    )
}

// MARK: - Back from a pushed page (#39)

/// Counts the rankings reads Compete's leaderboard previews make, forwarding every
/// request to the real loopback fixture.
private actor CountingTransport: HTTPTransport {
    private let inner = URLSessionHTTPTransport()
    private(set) var rankingsReads = 0

    func send(_ request: URLRequest) async throws -> HTTPResult {
        if request.url?.path.hasPrefix("/api/rankings/") == true { rankingsReads += 1 }
        return try await inner.send(request)
    }
}

/// Back from View Full Leaderboard used to restart every section's `.task(id:)`, which
/// reset it to a spinner and read the rankings again: the cards collapsed, then
/// re-expanded and re-faded under the pop, shifting the page (#39). A reappearance with
/// the same instruments, account and publication must keep the loaded page, with no
/// page spinner (#354; `CompeteHubModel`'s `ReappearanceLoadGate`).
///
/// On iOS a `NavigationStack` push makes the root disappear and Back makes it appear
/// again. A hosted macOS stack keeps its root appeared, so the test takes the host out
/// of its window and back, which runs the same disappear/appear cycle (without the fix
/// it reads the rankings a second time).
@MainActor
@Test func competeKeepsLoadedLeaderboardsWhenItReappears() async throws {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let transport = CountingTransport()
    let client = try FestivalAPI(baseURL: baseURL, transport: transport)
    let suite = "fst.tests.compete.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    defer { storage.removePersistentDomain(forName: suite) }
    let identity: [String: String] = ["accountId": "fixture-riv", "displayName": "Fixture Viewer"]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    for key in allInstrumentKeys { storage.set(key == "fst.settings.showLead", forKey: key) }
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    let host = nativeHostedView(
        NavigationStack { CompeteScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }

    try await nativeHostedSettle(
        host, untilText: ["Fixture Player 1", "Fixture Rival Golf"], excluding: ["Loading"]
    )
    let readsBeforeLeaving = await transport.rankingsReads
    #expect(readsBeforeLeaving == 1)

    window.contentView = NSView()
    try await Task.sleep(for: .milliseconds(200))
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    try await Task.sleep(for: .milliseconds(300))
    host.layoutSubtreeIfNeeded()
    let afterReturn = nativeHostedAccessibility(host)
    #expect(afterReturn.contains("Fixture Player 1"))
    #expect(afterReturn.contains("Fixture Rival Golf"))
    #expect(!afterReturn.contains("Loading"))
    #expect(await transport.rankingsReads == readsBeforeLeaving)

    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture Player 1", "Fixture Rival Golf"], excluding: ["Loading"]
    )
    _ = try nativeHostedPNG(image, filename: "compete-after-back.png", environment: "FST_COMPETE_RENDER_OUT")
    #expect(await transport.rankingsReads == readsBeforeLeaving)
}
#endif
