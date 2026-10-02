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

// MARK: - Loading

/// Captured before the per-instrument `.task` loads settle: every section's initial
/// `@State` is `.loading`, so the Leaderboards previews (not only the off-screen
/// Rivals sections) must show a system spinner rather than redacted placeholder
/// bars (#35). The loaded/error tests below exclude "Loading", proving the spinners
/// leave once content or an error appears.
@MainActor
@Test func competeScreenRendersSpinnersWhileSectionsLoad() async throws {
    let (session, storage, suite) = try await competeFixtureSession(
        accountId: "fixture-riv", visible: ["fst.settings.showLead", "fst.settings.showBass"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { CompeteScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    // Capture synchronously, before any `.task` load can resolve (no settle: the
    // loopback fixture answers within one poll).
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "compete-loading.png", environment: "FST_COMPETE_RENDER_OUT")
    assertRendersContent(
        host, image: image,
        containing: ["Leaderboards", "Loading Lead leaderboard", "Loading Bass leaderboard"],
        notContaining: ["Fixture Player 1", "Leaderboards Overview"]
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
/// it: each `CompeteInstrumentLeaderboardSection`/`RivalInstrumentSongSection`
/// pair owns its own independent load state.
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
/// the same instrument, account and publication must keep the loaded rows.
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
