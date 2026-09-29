#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Full-page fidelity (Settings, Player Profile)

/// Settings is a long native `Form` of glass sections; before the harness forced
/// the glass fallback it captured as a transparent page.
@MainActor
@Test func settingsScreenRendersSectionsHosted() async throws {
    let suite = "fst.tests.fidelity.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    defer { storage.removePersistentDomain(forName: suite) }
    let size = CGSize(width: 402, height: 1400)
    let host = nativeHostedView(
        NavigationStack {
            SettingsScreen(session: FestivalSession(factory: { throw FestivalAPIError.invalidResource }))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["App Settings", "Show Instrument Icons", "CHOpt Path Default View"]
    )
    _ = try nativeHostedPNG(image, filename: "settings.png", environment: "FST_SETTINGS_RENDER_OUT")
    assertRendersContent(
        host, image: image, minimumNonBackgroundFraction: 0.1,
        containing: ["App Settings", "Show Instrument Icons", "Filter Invalid Scores"]
    )
}

/// A viewed (not selected) public profile loads its overview and per-instrument
/// stats from the loopback fixture service (`RivalsMockService`).
@MainActor
@Test func playerProfileScreenRendersOverviewHosted() async throws {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    let session = FestivalSession(factory: { client })
    let suite = "fst.tests.fidelity.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    defer { storage.removePersistentDomain(forName: suite) }
    let size = CGSize(width: 402, height: 1400)
    let host = nativeHostedView(
        NavigationStack {
            PlayerProfileScreen(
                session: session, accountId: "fixture-player-1", displayName: "Fixture Player 1"
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        // Stat tiles are single accessibility elements labelled in Title Case (their
        // caption is only drawn uppercase).
        host, untilText: ["Fixture Player 1", "Overview", "Songs Played", "Avg Accuracy"]
    )
    _ = try nativeHostedPNG(image, filename: "player-profile.png", environment: "FST_PROFILE_RENDER_OUT")
    assertRendersContent(
        host, image: image, minimumNonBackgroundFraction: 0.1,
        containing: ["Fixture Player 1", "Songs Played", "Best Rank"],
        // No native "Public Profile"/"This Is Me" subtitle: the web has none (operator, 2026-09-28).
        notContaining: ["Public Profile", "This Is Me"]
    )
}
#endif
