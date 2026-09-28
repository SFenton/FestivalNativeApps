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
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "compete-no-profile.png", environment: "FST_COMPETE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
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
    try await Task.sleep(for: .milliseconds(600))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "compete-no-instruments.png", environment: "FST_COMPETE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
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
    try await Task.sleep(for: .milliseconds(1500))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "compete-leaderboards-and-rivals.png", environment: "FST_COMPETE_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
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
    try await Task.sleep(for: .milliseconds(1300))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "compete-rivals-error-leaderboards-ok.png", environment: "FST_COMPETE_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
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
    try await Task.sleep(for: .milliseconds(1300))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "compete-rivals-empty.png", environment: "FST_COMPETE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}
#endif
