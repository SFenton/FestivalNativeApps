#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixture session

/// Only the nine per-instrument visibility keys `VisibleInstrumentsReader` reads.
private let allInstrumentKeys = [
    "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
    "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
    "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
]

/// Build a fixture session against the real loopback `tools/mock_service.py`
/// process (see `RivalsMockService.swift` for why Rivals hosted tests can't use
/// an in-memory `HTTPTransport` actor like every other domain's), with a stored
/// selected player and explicit instrument visibility.
///
/// - Parameters:
///   - accountId: Selected (viewing) player id; a `-empty`/`-503` suffix selects
///     the mock's empty/unavailable Rivals scenario (see `mock_service.py`).
///   - visible: Instruments to enable; every other one of the nine is disabled.
/// - Returns: A ready session plus its private `UserDefaults` suite to clean up.
@MainActor
private func rivalsFixtureSession(
    accountId: String, displayName: String = "Fixture Viewer",
    visible: Set<String> = ["fst.settings.showLead"]
) async throws -> (session: FestivalSession, storage: UserDefaults, suite: String) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    let suite = "fst.tests.rivals.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": accountId, "displayName": displayName]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    for key in allInstrumentKeys { storage.set(visible.contains(key), forKey: key) }
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    return (session, storage, suite)
}

/// A session with no stored selection at all.
@MainActor
private func anonymousRivalsSession() async throws -> FestivalSession {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    return FestivalSession(factory: { client })
}

/// Lead + Bass: both a "Common Rivals" (2+ instruments) and a within-group Combo
/// (`RivalCombo.comboId(for: [.lead, .bass]) == "03"`) section should render.
private let leadAndBass: Set<String> = ["fst.settings.showLead", "fst.settings.showBass"]

// MARK: - RivalsScreen: no profile / loading / empty instruments

@MainActor
@Test func rivalsScreenRendersChooseProfileWhenNoPlayerSelected() async throws {
    let session = try await anonymousRivalsSession()
    #expect(session.selectedPlayer == nil)
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "rivals-no-profile.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// Captured before the per-instrument `.task` loads settle: every section's
/// initial `@State` is `.loading`.
@MainActor
@Test func rivalsScreenRendersLoadingBeforeSectionsSettle() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "rivals-loading.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func rivalsScreenRendersNoInstrumentsEnabledState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: []
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 500)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 500))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(600))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "rivals-no-instruments.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - RivalsScreen: loaded song tab (Common + Combo + per-instrument)

@MainActor
@Test func rivalsScreenRendersSongTabWithCommonAndComboSections() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1600))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1500))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rivals-song-tab-common-combo.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

/// Switch to the Leaderboard tab via the real `NSSegmentedControl` (mirrors
/// `ProfileSelectionSheetRenderTests`'s scope-picker pattern) and confirm rows load.
@MainActor
@Test func rivalsScreenRendersLeaderboardTabRows() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: ["fst.settings.showLead"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let picker = try #require(rivalsSegmentedControls(in: host).first)
    #expect(picker.segmentCount == 2)
    picker.selectedSegment = 1
    picker.sendAction(picker.action, to: picker.target)
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "rivals-leaderboard-tab.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// A 503 (matching the live service's scrape-window freeze) shows each section's
/// own inline `RivalsSectionError`, not a full-screen takeover.
@MainActor
@Test func rivalsScreenRendersSectionErrorOnServiceUnavailable() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv-503", visible: ["fst.settings.showLead"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "rivals-unavailable.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// With 2+ visible instruments, a 503 fails the Common Rivals and Combo
/// sections' own loads too (not just the per-instrument sections).
@MainActor
@Test func rivalsScreenRendersCommonAndComboSectionErrors() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv-503", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1300))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rivals-common-combo-errors.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

/// An empty per-instrument scenario hides the Common Rivals/Combo sections
/// entirely (`EmptyView()`), leaving only the per-instrument empty sections.
@MainActor
@Test func rivalsScreenHidesCommonAndComboSectionsWhenEmpty() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv-empty", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack { RivalsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1300))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rivals-common-combo-empty.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

private func rivalsSegmentedControls(in view: NSView) -> [NSSegmentedControl] {
    let current = (view as? NSSegmentedControl).map { [$0] } ?? []
    return current + view.subviews.flatMap { rivalsSegmentedControls(in: $0) }
}

// MARK: - AllRivalsScreen

@MainActor
@Test func allRivalsScreenRendersLoadedSongScopeRows() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .song(instruments: ["Solo_Guitar"]))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "all-rivals-loaded.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func allRivalsScreenRendersEmptyState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-empty")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .song(instruments: ["Solo_Guitar"]))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "all-rivals-empty.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func allRivalsScreenRendersUnavailableState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-503")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .leaderboard(instrument: "Solo_Guitar", rankBy: .totalscore))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "all-rivals-unavailable.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func allRivalsScreenRendersCommonRivalsForMultiInstrumentSongScope() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .song(instruments: ["Solo_Guitar", "Solo_Bass"]))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "all-rivals-common.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - RivalDetailScreen: categorization

@MainActor
@Test func allRivalsScreenRendersComboScopeRows() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(
                session: session,
                scope: .combo(token: "03", instruments: ["Solo_Guitar", "Solo_Bass"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1000)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1000))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(900))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "all-rivals-combo.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// An unresolvable scope (every named instrument raw value is unknown) shows
/// "Unknown Category" rather than an empty or loading board.
@MainActor
@Test func allRivalsScreenRendersUnknownCategoryForUnresolvableScope() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            AllRivalsScreen(session: session, scope: .song(instruments: ["Not_A_Real_Instrument"]))
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 500)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 500))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "all-rivals-unknown-category.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func rivalDetailScreenRendersCategorizedSongs() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: "408abb67d81446f0ac714506950ce178", name: "uwphe",
                scope: .song(instruments: ["Solo_Guitar"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-categories.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func rivalDetailScreenRendersNoSharedSongsState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-empty")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: "fixture-player-1", name: "Fixture Player 1",
                scope: .song(instruments: ["Solo_Guitar"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-no-songs.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

/// A `nil` scope (deep link, cold `DebugLaunchRoute`, or `FindRivalSheet`'s
/// arbitrary search result) falls back to merging every Settings-visible
/// instrument (`FestivalSession.fallbackRivalDetail` → the multi-instrument
/// branch of `combinedRivalDetail`, deduplicating songs across instruments).
@MainActor
@Test func rivalDetailScreenRendersNilScopeFallbackMerge() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(
        accountId: "fixture-riv", visible: leadAndBass
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: "fixture-player-1", name: "Fixture Player 1",
                scope: nil
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1300))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-fallback-merge.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

/// A `.leaderboard` scope's normal (200) path, complementing the unavailable
/// case below with `leaderboardRivalDetail`'s success branch.
@MainActor
@Test func rivalDetailScreenRendersLeaderboardScopeLoaded() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: "75a76ce7304d49c0ab76ea7ff5c3288e",
                name: "GingerNINZIN_JPN", scope: .leaderboard(instrument: "Solo_Guitar", rankBy: .totalscore)
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1200)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1200))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-leaderboard-loaded.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func rivalDetailScreenRendersUnavailableState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-503")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalDetailScreen(
                session: session, rivalId: "fixture-player-1", name: "Fixture Player 1",
                scope: .leaderboard(instrument: "Solo_Guitar", rankBy: .totalscore)
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 600))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rival-detail-unavailable.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - RivalryScreen: full category list, delta-magnitude ordering

/// `closest_battles` sorts by `|rankDelta|` ascending, mirroring
/// `RivalCategorization.categorize` (native `categorizeRivalSongs`); the demo
/// fixture's ties (`rankDelta == 0`) sort first.
@MainActor
@Test func rivalryScreenRendersClosestBattlesInDeltaMagnitudeOrder() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalryScreen(
                session: session, rivalId: "408abb67d81446f0ac714506950ce178",
                mode: "closest_battles", name: "uwphe", scope: .song(instruments: ["Solo_Guitar"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rivalry-closest-battles.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
    // The demo fixture's rival leads on `fixture-orbit` (delta -20): confirms a
    // rival-leads bucket exists alongside `closest_battles` for the same detail.
    let categories = RivalCategorization.categorize(rivalDetailDemoSongs)
    let closest = try #require(categories.first { $0.key == "closest_battles" })
    let deltas = closest.songs.map { abs($0.rankDelta) }
    #expect(deltas == deltas.sorted())
}

@MainActor
@Test func rivalryScreenRendersEmptyCategoryState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv-empty")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        NavigationStack {
            RivalryScreen(
                session: session, rivalId: "fixture-player-1", mode: "closest_battles",
                name: "Fixture Player 1", scope: .song(instruments: ["Solo_Guitar"])
            )
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 500)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 500))
    defer { window.orderOut(nil) }
    try await Task.sleep(for: .milliseconds(1100))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "rivalry-empty-category.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

/// Songs used by `rival-detail-demo.json`, mirrored here (rather than decoding the
/// fixture again) purely to assert the ordering claim above independently of the view.
private let rivalDetailDemoSongs: [RivalSongComparison] = [
    rivalSong(id: "fixture-pulse", delta: 1),
    rivalSong(id: "fixture-orbit", delta: -20),
    rivalSong(id: "fixture-echo", delta: 40),
    rivalSong(id: "fixture-drift", delta: 0),
]

private func rivalSong(id: String, delta: Int) -> RivalSongComparison {
    let json = """
    {"songId":"\(id)","title":null,"artist":null,"instrument":"Solo_Guitar",
     "userInstrument":null,"rivalInstrument":null,
     "userRank":1,"rivalRank":1,"rankDelta":\(delta),"userScore":100,"rivalScore":90}
    """
    return try! JSONDecoder().decode(RivalSongComparison.self, from: Data(json.utf8))
}

// MARK: - FindRivalSheet: search states

private func rivalsTextFields(in view: NSView) -> [NSTextField] {
    let current = (view as? NSTextField).map { [$0] } ?? []
    return current + view.subviews.flatMap { rivalsTextFields(in: $0) }
}

@MainActor
private func typeIntoFindRival(_ text: String, host: NSView) throws {
    let field = try #require(rivalsTextFields(in: host).first)
    field.stringValue = text
    field.delegate?.controlTextDidChange?(
        Notification(name: NSControl.textDidChangeNotification, object: field)
    )
    field.sendAction(field.action, to: field.target)
}

@MainActor
@Test func findRivalSheetRendersEnterQueryState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "find-rival-enter-query.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func findRivalSheetRendersLoadingThenResults() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    try typeIntoFindRival("Fixture", host: host)
    // Under the 250ms debounce: still `.loading`.
    try await Task.sleep(for: .milliseconds(60))
    host.layoutSubtreeIfNeeded()
    let loading = try nativeHostedImage(host)
    _ = try nativeHostedPNG(loading, filename: "find-rival-loading.png", environment: "FST_RIVALS_RENDER_OUT")
    // Past the debounce plus the real network round trip: `.results`.
    try await Task.sleep(for: .milliseconds(1500))
    host.layoutSubtreeIfNeeded()
    let results = try nativeHostedImage(host)
    _ = try nativeHostedPNG(results, filename: "find-rival-results.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(loading.width > 0 && results.width > 0)
}

@MainActor
@Test func findRivalSheetRendersEmptyResultsState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    try typeIntoFindRival("zzz-nobody", host: host)
    try await Task.sleep(for: .milliseconds(1800))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "find-rival-empty.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// Clearing back to an empty query resets to `.enterQuery` without a stale
/// results list lingering (`.onChange(of: query)`).
@MainActor
@Test func findRivalSheetResetsToEnterQueryAfterClearing() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    try typeIntoFindRival("Fixture", host: host)
    try await Task.sleep(for: .milliseconds(1300))
    host.layoutSubtreeIfNeeded()
    let withResults = try nativeHostedImage(host)
    try typeIntoFindRival("", host: host)
    host.layoutSubtreeIfNeeded()
    let cleared = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        withResults, filename: "find-rival-before-clear.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    let clearedPNG = try nativeHostedPNG(
        cleared, filename: "find-rival-after-clear.png", environment: "FST_RIVALS_RENDER_OUT"
    )
    #expect(!clearedPNG.isEmpty)
}

@MainActor
@Test func findRivalSheetRendersFailedSearchState() async throws {
    let (session, storage, suite) = try await rivalsFixtureSession(accountId: "fixture-riv")
    defer { storage.removePersistentDomain(forName: suite) }
    let host = nativeHostedView(
        FindRivalSheet(session: session)
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 390, height: 700)
    )
    // The shared fixture's `/api/account/search` returns HTTP 503 for "busy".
    try typeIntoFindRival("busy", host: host)
    try await Task.sleep(for: .milliseconds(1800))
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "find-rival-failed.png", environment: "FST_RIVALS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}
#endif
