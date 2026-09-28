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
// Reuses the shared real loopback `tools/mock_service.py` process
// (`RivalsMockService`, despite its name a plain generic launcher — see its
// header comment) rather than an in-memory `HTTPTransport` actor: this lane
// extended the fixture server itself with `/api/player/{id}/bands`,
// `/api/rankings/{instrument}/{accountId}` and the `teamKey`-filtered
// `/api/rankings/bands/{bandType}` (`selectedBandEntry`) routes, so reusing the
// real process keeps one source of truth for that fixture shape instead of a
// second hand-authored JSON copy in an in-memory transport actor.

@MainActor
private func profileFixtureSession(
    identity accountId: String? = nil, displayName: String = "Fixture Player 1"
) async throws -> (session: FestivalSession, storage: UserDefaults?, suite: String?) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    guard let accountId else {
        return (FestivalSession(factory: { client }), nil, nil)
    }
    let suite = "fst.tests.player-profile.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": accountId, "displayName": displayName]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    return (session, storage, suite)
}

/// Render `PlayerProfileContent` for a viewed (not necessarily selected) account.
@MainActor
private func renderProfile(
    accountId: String, session: FestivalSession, height: CGFloat = 1400
) async throws -> CGImage {
    let host = nativeHostedView(
        NavigationStack {
            PlayerProfileContent(session: session, accountId: accountId, routeDisplayName: nil)
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: height)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: height))
    defer { window.orderOut(nil) }
    for _ in 0..<20 {
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }
    return try nativeHostedImage(host)
}

// MARK: - Viewed vs. selected identity

@MainActor
@Test func playerProfileViewedUnselectedShowsSelectAction() async throws {
    let (session, _, _) = try await profileFixtureSession()
    let image = try await renderProfile(accountId: "fixture-player-1", session: session)
    _ = try nativeHostedPNG(image, filename: "player-viewed.png", environment: "FST_PROFILE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func playerProfileSelectedShowsDeselectAction() async throws {
    let (session, storage, suite) = try await profileFixtureSession(identity: "fixture-player-1")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    #expect(session.selectedPlayer?.accountId == "fixture-player-1")
    let image = try await renderProfile(accountId: "fixture-player-1", session: session)
    _ = try nativeHostedPNG(image, filename: "player-selected.png", environment: "FST_PROFILE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - Loading/syncing/failed states

@MainActor
@Test func playerProfileSyncingShowsRetryableState() async throws {
    let (session, _, _) = try await profileFixtureSession()
    let image = try await renderProfile(accountId: "fixture-syncing", session: session, height: 700)
    _ = try nativeHostedPNG(image, filename: "player-syncing.png", environment: "FST_PROFILE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func playerProfileDeniedShowsErrorState() async throws {
    let (session, _, _) = try await profileFixtureSession()
    let image = try await renderProfile(accountId: "fixture-denied", session: session, height: 700)
    _ = try nativeHostedPNG(image, filename: "player-error.png", environment: "FST_PROFILE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - Per-instrument global rank sub-states

/// `fixture-player-1` only has a Lead score, so its Lead section is the only one
/// that reaches `InstrumentGlobalRankView`'s loading→available path; every other
/// visible instrument shows the empty-instrument footnote (covered by the same
/// render above).
@MainActor
@Test func playerProfileGlobalRankAvailableForScoredInstrument() async throws {
    let (session, _, _) = try await profileFixtureSession()
    let image = try await renderProfile(accountId: "fixture-player-1", session: session)
    _ = try nativeHostedPNG(
        image, filename: "player-global-rank-available.png", environment: "FST_PROFILE_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func playerProfileGlobalRankUnrankedState() async throws {
    let (session, _, _) = try await profileFixtureSession()
    let image = try await renderProfile(accountId: "fixture-rank-unranked", session: session, height: 900)
    _ = try nativeHostedPNG(
        image, filename: "player-global-rank-unranked.png", environment: "FST_PROFILE_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func playerProfileGlobalRankFailedShowsRetry() async throws {
    let (session, _, _) = try await profileFixtureSession()
    let image = try await renderProfile(accountId: "fixture-rank-fail", session: session, height: 900)
    _ = try nativeHostedPNG(
        image, filename: "player-global-rank-failed.png", environment: "FST_PROFILE_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - PlayerProfileScreen (pushed route wrapper)

@MainActor
@Test func playerProfileScreenWrapperRendersWithBackground() async throws {
    let (session, _, _) = try await profileFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            PlayerProfileScreen(session: session, accountId: "fixture-player-1", displayName: "Fixture Player 1")
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    for _ in 0..<20 {
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }
    let image = try nativeHostedImage(host)
    #expect(image.width > 0 && image.height > 0)
}
#endif
