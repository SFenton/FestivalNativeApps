#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - StatisticsScreen
//
// `StatisticsScreen` is a thin wrapper reusing `PlayerProfileContent` (deeply
// covered by `PlayerProfileRenderTests.swift`) always in its selected (Deselect) state,
// plus its own no-profile guard. These tests cover just that wrapper's own two
// branches, not every `PlayerProfileContent` sub-state again.

@MainActor
private func statisticsFixtureSession(selected: Bool) async throws -> (
    session: FestivalSession, storage: UserDefaults?, suite: String?
) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    guard selected else {
        return (FestivalSession(factory: { client }), nil, nil)
    }
    let suite = "fst.tests.statistics.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": "fixture-player-1", "displayName": "Fixture Player 1"]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    return (session, storage, suite)
}

@MainActor
@Test func statisticsScreenShowsChooseProfileGuardWhenNoneSelected() async throws {
    let (session, _, _) = try await statisticsFixtureSession(selected: false)
    #expect(session.selectedPlayer == nil)
    let host = nativeHostedView(
        NavigationStack { StatisticsScreen(session: session) }.preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "statistics-no-profile.png", environment: "FST_PROFILE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// Captures the page title a hosted screen publishes with `festivalNavigationTitle(_:)`.
@MainActor
private final class PublishedPageTitle {
    var value: String?
}

/// Every root page keeps its system title in every iPhone Duo pose (pattern
/// page-tools-and-nav-chrome R14, issue #341), including Statistics' momentary no-profile
/// state. `DuoPageTitleJourneyTests.testNoProfileStatisticsShowsFullTitle` holds that
/// state open in the real shell and requires the whole visible system title per pose.
@MainActor
@Test func statisticsScreenNoProfileGuardKeepsStatisticsTitle() async throws {
    let (session, _, _) = try await statisticsFixtureSession(selected: false)
    let published = PublishedPageTitle()
    let host = nativeHostedView(
        NavigationStack {
            StatisticsScreen(session: session)
                .onPreferenceChange(FestivalPageTitleKey.self) { title in
                    MainActor.assumeIsolated { published.value = title }
                }
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    for _ in 0..<5 where published.value == nil {
        host.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
    }
    #expect(published.value == "Statistics")
}

@MainActor
@Test func statisticsScreenShowsSelectedPlayerProfileContent() async throws {
    let (session, storage, suite) = try await statisticsFixtureSession(selected: true)
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    let host = nativeHostedView(
        NavigationStack { StatisticsScreen(session: session) }.preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    for _ in 0..<20 {
        try await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "statistics-selected.png", environment: "FST_PROFILE_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}
#endif
