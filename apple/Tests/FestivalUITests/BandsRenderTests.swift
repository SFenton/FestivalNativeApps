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
    // No selected player: no pinned band footer (issue #306).
    #expect(!nativeHostedAccessibility(host).identifiers.contains(songBandFooterID))
}

private let songBandFooterID = "fst.song-band-leaderboard.spotlight-footer"

/// A selected player with a Duos score here gets their band pinned above the pager
/// (issue #306), labelled with its rank and destination (issue #307), at an iPhone width
/// and at a Mac window width where the footer adds season and stars.
@MainActor
@Test(arguments: [CGSize(width: 402, height: 900), CGSize(width: 1000, height: 760)])
func songBandLeaderboardScreenPinsTheSelectedPlayersBand(size: CGSize) async throws {
    let (session, storage, suite) = try await bandsFixtureSession(selected: "fixture-player-1")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    let host = nativeHostedView(
        NavigationStack {
            SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets")
        }
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(
        image, filename: "song-band-leaderboard-footer-\(Int(size.width)).png",
        environment: "FST_BANDS_RENDER_OUT"
    )
    let tree = nativeHostedAccessibility(host)
    #expect(tree.identifiers.contains(songBandFooterID))
    // Rank 29 sits on page 2, so page 1's footer jumps to it (issue #307).
    #expect(tree.contains("Your band's rank, 29th. Jump to your band's position."))
    #expect(tree.identifiers.contains("fst.song-band-leaderboard.page-info"))
}

/// The footer is per band size: the player has no Trios band here, so none shows.
@MainActor
@Test func songBandLeaderboardScreenHidesTheFooterWithoutABandOfThatSize() async throws {
    let (session, storage, suite) = try await bandsFixtureSession(selected: "fixture-player-1")
    defer { if let suite { storage?.removePersistentDomain(forName: suite) } }
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
    #expect(!nativeHostedAccessibility(host).identifiers.contains(songBandFooterID))
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
// MARK: - Profile bands preview (issue #312)

@MainActor
@Test func playerBandsPreviewReadsSixPerGroupWithTotals() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let preview = try await session.playerBandsPreview(accountId: "fixture-player-1")
    #expect(preview.groups.map(\.group) == [.duos, .trios, .quads])
    #expect(preview.groups.map(\.entries.count) == [6, 6, 4])
    #expect(preview.groups.map(\.totalCount) == [18, 8, 4])
    #expect(preview.groups.map(\.hasMore) == [true, true, false])
    #expect(preview.groups[0].entries.allSatisfy { $0.bandType == "Band_Duets" })

    let empty = try await session.playerBandsPreview(accountId: "fixture-player-2")
    #expect(empty.groups.allSatisfy { $0.entries.isEmpty && !$0.hasMore })
}

@MainActor
@Test func profileBandsSectionShowsGroupsCardsAndViewAll() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            ScrollView {
                PlayerBandsPreviewSection(
                    session: session, accountId: "fixture-player-1", displayName: "Fixture Player 1",
                    routeDisplayName: nil
                )
                .padding(16)
            }
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 2600)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 2600))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "profile-bands-loaded.png", environment: "FST_BANDS_RENDER_OUT")
    let tree = nativeHostedAccessibility(host)
    for id in [
        "fst.player.bands", "fst.player.bands-link",
        "fst.player.bands.group.duos", "fst.player.bands.group.trios", "fst.player.bands.group.quads",
        "fst.player.bands.view-all.duos", "fst.player.bands.view-all.trios",
        "fst.player-bands.row.fixture-band-1", "fst.player-bands.row.fixture-pband-quad-4",
    ] {
        #expect(tree.identifiers.contains(id), "missing \(id)")
    }
    // Six cards per group: the seventh Duo waits behind View All; Quads has no View All.
    #expect(!tree.identifiers.contains("fst.player-bands.row.fixture-pband-duo-7"))
    #expect(!tree.identifiers.contains("fst.player.bands.view-all.quads"))
    #expect(!tree.identifiers.contains("fst.player.bands.loading"))
    #expect(tree.contains("Fixture Player 1's Bands"))
    #expect(tree.contains("View all 18 duos"))
    assertRendersContent(host, image: image, containing: ["Duos", "Trios", "Quads"])
}

@MainActor
@Test func profileBandsSectionShowsNoBandsYetPerEmptyGroup() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let host = nativeHostedView(
        NavigationStack {
            ScrollView {
                PlayerBandsPreviewSection(
                    session: session, accountId: "fixture-player-2", displayName: "Fixture Player 2",
                    routeDisplayName: nil
                )
                .padding(16)
            }
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "profile-bands-empty.png", environment: "FST_BANDS_RENDER_OUT")
    let tree = nativeHostedAccessibility(host)
    for group in ["duos", "trios", "quads"] {
        #expect(tree.identifiers.contains("fst.player.bands.empty.\(group)"))
        #expect(!tree.identifiers.contains("fst.player.bands.view-all.\(group)"))
    }
    #expect(tree.contains("No Bands Yet"))
    #expect(tree.identifiers.contains("fst.player.bands-link"))
}

@MainActor
@Test func profileBandsSectionFailureStaysInlineWithRetry() async throws {
    let session = FestivalSession(factory: {
        try FestivalAPI(baseURL: URL(string: "http://127.0.0.1:9")!, transport: URLSessionHTTPTransport())
    })
    let host = nativeHostedView(
        NavigationStack {
            ScrollView {
                PlayerBandsPreviewSection(
                    session: session, accountId: "fixture-player-1", displayName: "Fixture Player 1",
                    routeDisplayName: nil
                )
                .padding(16)
            }
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 700)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 700))
    defer { window.orderOut(nil) }
    await settle(host)
    let tree = nativeHostedAccessibility(host)
    #expect(tree.identifiers.contains("fst.player.bands.error"))
    #expect(tree.contains("Retry"))
    // The title and See All stay usable while the cards are unavailable.
    #expect(tree.contains("Fixture Player 1's Bands"))
    #expect(tree.identifiers.contains("fst.player.bands-link"))
}

@Test func playerBandsRouteDefaultsToAllAndCarriesGroup() {
    #expect(AppRoute.playerBands(accountId: "a", displayName: nil)
        == .playerBands(accountId: "a", displayName: nil, group: .all))
    #expect(AppRoute.playerBands(accountId: "a", displayName: nil, group: .duos)
        != .playerBands(accountId: "a", displayName: nil))
}
#endif
