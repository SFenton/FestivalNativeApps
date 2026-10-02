#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Synthetic fixtures
//
// `SuggestionCategoryCardView`/`SuggestionSongRowView` are pure presentation over
// already-generated `SuggestionCategory`/`SuggestionSongItem` values, so these are
// built directly rather than depending on `SuggestionGenerator` picking a specific
// pipeline out of the shared fixture's two-song catalogue (the two-song catalogue
// legitimately yields zero categories for most pipelines — see
// `SuggestionsJourneyTests.swift`'s own header comment on this).

private func sampleSong(id: String, title: String, artist: String = "Fixture Artist") throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"\(id)","title":"\(title)","artist":"\(artist)","album":null,"year":null,
     "durationSeconds":null,"albumArt":null,"difficulty":null,
     "pathArtifactGenerationId":null,"sig":null,"maxScores":null}
    """.utf8))
}

@MainActor
private func cardHost(_ category: SuggestionCategory) -> NSHostingView<some View> {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    return nativeHostedView(
        SuggestionCategoryCardView(category: category, session: session)
            .frame(width: 380)
            .preferredColorScheme(.dark),
        size: CGSize(width: 380, height: 500)
    )
}

// MARK: - SuggestionCategoryCardView / SuggestionSongRowView

@MainActor
@Test func suggestionCardRendersFullComboStarsAndPercent() throws {
    let song = try sampleSong(id: "fixture-pulse", title: "Fixture Pulse")
    let category = SuggestionCategory(
        key: "near_fc_lead", title: "Near Full Combo", description: "So close!",
        type: .nearFC, instrument: .lead,
        songs: [SuggestionSongItem(song: song, stars: 5, percent: 98.5, fullCombo: true)]
    )
    let host = cardHost(category)
    let window = nativeHostedWindow(host, size: CGSize(width: 380, height: 500))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "suggestion-card-fc.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func suggestionCardRendersRivalBadgeWithPositiveAndNegativeDelta() throws {
    let ahead = try sampleSong(id: "fixture-pulse", title: "Fixture Pulse")
    let behind = try sampleSong(id: "fixture-orbit", title: "Fixture Orbit")
    let category = SuggestionCategory(
        key: "song_rival_battleground", title: "Battleground Songs", description: "Rivals cluster here.",
        type: .songRivals, instrument: .lead,
        songs: [
            SuggestionSongItem(
                song: ahead, stars: 4, percent: 91, fullCombo: false,
                percentileDisplay: "Top 10%", rivalName: "Fixture Rival",
                rivalAccountId: "fixture-rival-1", rivalRankDelta: 3
            ),
            SuggestionSongItem(
                song: behind, stars: 2, percent: 70, fullCombo: false,
                rivalName: "A Very Long Rival Display Name", rivalAccountId: "fixture-rival-2",
                rivalRankDelta: -2
            ),
        ]
    )
    let host = cardHost(category)
    let window = nativeHostedWindow(host, size: CGSize(width: 380, height: 500))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "suggestion-card-rival.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func rivalSpotlightCardRendersRankDeltaWithoutRepeatingTheRivalName() throws {
    let ahead = try sampleSong(id: "fixture-pulse", title: "Fixture Pulse")
    let behind = try sampleSong(id: "fixture-orbit", title: "Fixture Orbit")
    let category = SuggestionCategory(
        key: "song_rival_spotlight_fixture-rival-1", title: "Rival Spotlight: Fixture Rival",
        description: "A curated mix of your rivalry with Fixture Rival.",
        type: .songRivals, instrument: nil,
        songs: [ahead, behind].enumerated().map { index, song in
            SuggestionSongItem(
                song: song, instrument: .lead, rivalName: "Fixture Rival",
                rivalAccountId: "fixture-rival-1", rivalRankDelta: index == 0 ? 3 : -1
            )
        }
    )
    #expect(!SuggestionRowLayout.showsRivalName(categoryKey: category.key))
    let host = cardHost(category)
    let window = nativeHostedWindow(host, size: CGSize(width: 380, height: 500))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "suggestion-card-rival-spotlight.png", environment: "FST_SUGGESTIONS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func suggestionCardRendersMultiInstrumentMixWithoutScoreAnnotations() throws {
    let song = try sampleSong(id: "fixture-orbit", title: "Fixture Orbit")
    let category = SuggestionCategory(
        key: "variety_pack", title: "Variety Pack", description: "A mix across charts.",
        type: .varietyPack, instrument: nil,
        songs: [SuggestionSongItem(song: song, instrument: .drums)]
    )
    let host = cardHost(category)
    let window = nativeHostedWindow(host, size: CGSize(width: 380, height: 300))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "suggestion-card-variety.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - SuggestionsFilterSheet

@MainActor
private func filterSheetHost(
    applied: SuggestionFilterSettings, visible: [Instrument] = [.lead, .bass, .drums]
) -> NSHostingView<some View> {
    nativeHostedView(
        SuggestionsFilterSheet(applied: applied, visibleInstruments: visible, onChange: { _ in })
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
}

@MainActor
@Test func suggestionsFilterSheetRendersDefaultDraft() throws {
    let host = filterSheetHost(applied: .defaults())
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "suggestions-filter-default.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func suggestionsFilterSheetRendersInstrumentDisabledAndPerInstrumentOverrides() throws {
    var settings = SuggestionFilterSettings.defaults()
    settings.setInstrumentEnabled(.bass, enabled: false)
    settings.setGlobalType(.nearFC, enabled: false, instruments: [.lead, .bass, .drums])
    settings.setPerInstrumentType(.starProgress, instrument: .lead, enabled: false, allInstruments: [.lead, .bass, .drums])
    #expect(settings.isActive())
    let host = filterSheetHost(applied: settings)
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "suggestions-filter-overrides.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func suggestionsFilterSheetRendersWithNoVisibleInstruments() throws {
    let host = filterSheetHost(applied: .defaults(), visible: [])
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "suggestions-filter-no-instruments.png", environment: "FST_SUGGESTIONS_RENDER_OUT"
    )
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - SuggestionsScreen states
//
// Reuses the shared real loopback fixture server (`RivalsMockService`) so
// `session.catalog()`/`session.viewPlayer`/`rivalsAll` all resolve consistently.

@MainActor
private func suggestionsFixtureSession(
    identity accountId: String? = nil
) async throws -> (session: FestivalSession, storage: UserDefaults?, suite: String?) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    guard let accountId else {
        return (FestivalSession(factory: { client }), nil, nil)
    }
    let suite = "fst.tests.suggestions.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": accountId, "displayName": "Fixture Suggestions Player"]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    return (session, storage, suite)
}

@MainActor
private func suggestionsScreenImage(
    session: FestivalSession, storage: UserDefaults, iterations: Int = 20
) async throws -> CGImage {
    let host = nativeHostedView(
        NavigationStack { SuggestionsScreen(session: session, visibleInstruments: Set(Instrument.allCases)) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1200)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1200))
    defer { window.orderOut(nil) }
    for _ in 0..<iterations {
        try await Task.sleep(for: .milliseconds(200))
        host.layoutSubtreeIfNeeded()
    }
    return try nativeHostedImage(host)
}

@MainActor
@Test func suggestionsScreenShowsNoProfileGuard() async throws {
    let (session, _, _) = try await suggestionsFixtureSession()
    let storage = UserDefaults(suiteName: "fst.tests.suggestions.anon.\(UUID().uuidString)")!
    let image = try await suggestionsScreenImage(session: session, storage: storage, iterations: 2)
    _ = try nativeHostedPNG(image, filename: "suggestions-no-profile.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func suggestionsScreenShowsSyncingState() async throws {
    let (session, storage, suite) = try await suggestionsFixtureSession(identity: "fixture-syncing")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    let appStorage = UserDefaults(suiteName: "fst.tests.suggestions.syncing.\(UUID().uuidString)")!
    let image = try await suggestionsScreenImage(session: session, storage: appStorage)
    #expect(session.playerLoadState == .syncing)
    _ = try nativeHostedPNG(image, filename: "suggestions-syncing.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func suggestionsScreenShowsFailedStateForDeniedProfile() async throws {
    let (session, storage, suite) = try await suggestionsFixtureSession(identity: "fixture-denied")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    let appStorage = UserDefaults(suiteName: "fst.tests.suggestions.denied.\(UUID().uuidString)")!
    let image = try await suggestionsScreenImage(session: session, storage: appStorage)
    guard case .failed = session.playerLoadState else {
        Issue.record("Expected a failed player load state for a denied profile")
        return
    }
    _ = try nativeHostedPNG(image, filename: "suggestions-failed.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// The fixture catalogue may or may not produce a populated mix for this account;
/// either reachable outcome (`fst.suggestions.list` or `.no-results`) is a valid,
/// fully-loaded render — this proves `ensureLoaded`/the generator path actually ran
/// to completion, matching `SuggestionsJourneyTests`'s own tolerant assertion.
@MainActor
@Test func suggestionsScreenSettlesToListOrEmptyAfterSelection() async throws {
    let (session, storage, suite) = try await suggestionsFixtureSession(identity: "fixture-player-1")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    let appStorage = UserDefaults(suiteName: "fst.tests.suggestions.loaded.\(UUID().uuidString)")!
    let image = try await suggestionsScreenImage(session: session, storage: appStorage)
    #expect(session.playerLoadState == .available)
    _ = try nativeHostedPNG(image, filename: "suggestions-settled.png", environment: "FST_SUGGESTIONS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}
#endif
