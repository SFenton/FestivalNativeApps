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
// (`RivalsMockService`) rather than an in-memory `HTTPTransport` actor: this
// lane extended the fixture server itself with `/api/player/{id}/bands`,
// `/api/rankings/bands/{bandType}/{teamKey}/history`,
// `/api/rankings/bands/{bandType}/{teamKey}/songs`,
// `/api/leaderboard/{songId}/bands/{bandType}` and the `teamKey`-filtered
// `/api/rankings/bands/{bandType}` (`selectedBandEntry`) routes — see
// `tools/mock_service.py`'s `_band_detail`/`_player_band_entry`/
// `_song_band_leaderboard_entry` helpers and `.agents/testing/fixtures.md`.

@MainActor
private func bandsFixtureSession(
    selected accountId: String? = nil
) async throws -> (session: FestivalSession, storage: UserDefaults?, suite: String?) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    guard let accountId else {
        return (FestivalSession(factory: { client }), nil, nil)
    }
    let suite = "fst.tests.bands.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": accountId, "displayName": "Fixture Player 1"]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    let session = FestivalSession(factory: { client }, selectionStorage: storage)
    return (session, storage, suite)
}

@MainActor
private func settle(_ host: NSHostingView<some View>, iterations: Int = 20) async {
    for _ in 0..<iterations {
        try? await Task.sleep(for: .milliseconds(150))
        host.layoutSubtreeIfNeeded()
    }
}

// MARK: - BandsScreen (landing)

@MainActor
@Test func bandsScreenShowsRankingsOnlyWithoutSelectedPlayer() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    #expect(session.selectedPlayer == nil)
    let host = nativeHostedView(
        NavigationStack { BandsScreen(session: session) }.preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "bands-landing-no-player.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func bandsScreenShowsYourBandsLinkWithSelectedPlayer() async throws {
    let (session, storage, suite) = try await bandsFixtureSession(selected: "fixture-player-1")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    let host = nativeHostedView(
        NavigationStack { BandsScreen(session: session) }.preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "bands-landing-with-player.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - BandDetailScreen

@MainActor
@Test func bandDetailUnresolvedWithoutBandTypeOrTeamKey() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            BandDetailScreen(session: session, bandId: "fixture-band-1", name: "Some Band")
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    host.layoutSubtreeIfNeeded()
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "band-detail-unresolved.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func bandDetailLoadedRendersMembersSummaryHistoryAndCatalogLinkedSongs() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            BandDetailScreen(
                session: session, bandId: "fixture-band-1", name: "Band 1 Member A + Band 1 Member B",
                bandType: "Band_Duets", teamKey: "fixture-team-1"
            )
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1800)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1800))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "band-detail-loaded.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func bandDetailLoadedWithEmptyHistoryAndSongs() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            BandDetailScreen(
                session: session, bandId: "fixture-band-2", name: "Band 2 Member A + Band 2 Member B",
                bandType: "Band_Duets", teamKey: "fixture-team-2"
            )
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "band-detail-empty-history-songs.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func bandDetailFailedShowsServiceStatus() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            BandDetailScreen(
                session: session, bandId: "fixture-band-503", name: "Unavailable Band",
                bandType: "Band_Duets", teamKey: "fixture-team-503"
            )
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "band-detail-failed.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - PlayerBandsScreen

@MainActor
@Test func playerBandsScreenLoadsEntriesAndPager() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            PlayerBandsScreen(session: session, accountId: "fixture-player-1", displayName: "Fixture Player 1")
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1200)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1200))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "player-bands-loaded.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func playerBandsScreenShowsNoBandsYetWhenEmpty() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            PlayerBandsScreen(session: session, accountId: "fixture-player-2", displayName: "Fixture Player 2")
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "player-bands-empty.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

// MARK: - SongBandLeaderboardScreen

@MainActor
private func fixtureSong(_ session: FestivalSession, songId: String) async throws -> Song {
    let payload = try await session.catalog()
    return try #require(payload.catalog.songs.first { $0.songId == songId })
}

@MainActor
@Test func songBandLeaderboardScreenLoadsRows() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    let host = nativeHostedView(
        NavigationStack {
            SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets")
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "song-band-leaderboard-loaded.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func songBandLeaderboardScreenShowsEmptyState() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let song = try await fixtureSong(session, songId: "fixture-orbit")
    let host = nativeHostedView(
        NavigationStack {
            SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets")
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "song-band-leaderboard-empty.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func songBandLeaderboardScreenSwitchesBandType() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    let host = nativeHostedView(
        NavigationStack {
            SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Trios")
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "song-band-leaderboard-trios.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

/// The selected player's band is pinned above the pager like the Solo footer (issue
/// #307): page 1 offers "Jump to your band's position"; page 2, where rank 29 is
/// listed and highlighted, offers "Open band".
@MainActor
@Test func songBandLeaderboardFooterJumpsOffPageAndOpensBandOnPage() async throws {
    nativeHostedEnableAccessibility()
    let (session, storage, suite) = try await bandsFixtureSession(selected: "fixture-player-1")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    for (page, label, filename) in [
        (1, "Your band's rank, 29th. Jump to your band's position.", "song-band-leaderboard-footer-jump.png"),
        (2, "Your band's rank, 29th. Open band.", "song-band-leaderboard-footer-open.png"),
    ] {
        let host = nativeHostedView(
            NavigationStack {
                SongBandLeaderboardScreen(
                    session: session, song: song, bandType: "Band_Duets", initialPage: page
                )
            }
            .preferredColorScheme(.dark),
            size: CGSize(width: 402, height: 900)
        )
        let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(host, untilText: [label])
        _ = try nativeHostedPNG(image, filename: filename, environment: "FST_BANDS_RENDER_OUT")
    }
}

// MARK: - Song Detail band previews

@MainActor
private func songBandPreviewsFixture() throws -> SongBandLeaderboardsResponse {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent(
        "contracts/fixtures/song-band-leaderboards-demo.json"
    ))
    return try JSONDecoder().decode(SongBandLeaderboardsResponse.self, from: data)
}

@MainActor
private func renderSongBandPreviews(
    _ state: SongBandPreviewState, filename: String, dynamicTypeSize: DynamicTypeSize = .large
) async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    let host = nativeHostedView(
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(BandType.allCases) { bandType in
                        SongBandPreviewSection(song: song, bandType: bandType, state: state, onRetry: {})
                    }
                }
                .padding(16)
            }
        }
        .dynamicTypeSize(dynamicTypeSize)
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 1400)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 1400))
    defer { window.orderOut(nil) }
    await settle(host, iterations: 6)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: filename, environment: "FST_BANDS_RENDER_OUT")
    #expect(image.width > 0 && image.height > 0)
}

@MainActor
@Test func songBandPreviewsRenderRowsSelectedAndEmptySizes() async throws {
    try await renderSongBandPreviews(.loaded(songBandPreviewsFixture()), filename: "song-band-previews-loaded.png")
}

@MainActor
@Test func songBandPreviewsRenderAtAccessibilitySizes() async throws {
    try await renderSongBandPreviews(
        .loaded(songBandPreviewsFixture()), filename: "song-band-previews-ax5.png",
        dynamicTypeSize: .accessibility5
    )
}

@MainActor
@Test func songBandPreviewsRenderLoadingAndFailure() async throws {
    try await renderSongBandPreviews(.loading, filename: "song-band-previews-loading.png")
    try await renderSongBandPreviews(.failed("The service is busy."), filename: "song-band-previews-failed.png")
}

@MainActor
@Test func songBandPreviewSpokenLabelReadsRankMembersScoreAndAccuracy() throws {
    let duos = try songBandPreviewsFixture().preview(for: .duets)
    let top = try #require(duos.entries.first)
    #expect(SongBandPreviewText.spokenLabel(top, selected: false)
        == "Rank 1, Fixture Rank One + Unknown User, score 999,999, 5 stars, full combo, accuracy 99%")
    let footer = try #require(duos.footerEntry)
    #expect(SongBandPreviewText.spokenLabel(footer, selected: true).hasPrefix("Your band, Rank 14, "))
}

@MainActor
@Test func songBandPreviewsLoaderReadsTheMockAllRoute() async throws {
    let (session, storage, suite) = try await bandsFixtureSession(selected: "fixture-player-1")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    let state = await SongBandPreviewLoader.load(
        session: session, songId: "fixture-pulse", accountId: "fixture-player-1"
    )
    guard case let .loaded(response)? = state else {
        Issue.record("Expected loaded band previews, got \(String(describing: state))")
        return
    }
    #expect(response.preview(for: .duets).entries.count == 2)
    #expect(response.preview(for: .duets).footerEntry?.rank == 29)
    #expect(response.preview(for: .trios).entries.isEmpty)
}
#endif
