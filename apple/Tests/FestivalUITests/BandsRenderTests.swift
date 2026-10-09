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

/// #555 accessibility: the rebuilt page reads its subtitle, then Members, Band Summary,
/// Band Statistics, Band Rank History, Five Best and Five Worst Songs in web order; member
/// cards and song rows are single labelled elements at least 44 pt tall; the chart reads
/// as one titled element.
@MainActor
@Test(arguments: [DynamicTypeSize.large, .accessibility3])
func bandDetailReadsSectionsInWebOrderWithLabelledTargets(typeSize: DynamicTypeSize) async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let size = CGSize(width: 402, height: typeSize.isAccessibilitySize ? 5200 : 2000)
    let host = nativeHostedView(
        NavigationStack {
            BandDetailScreen(
                session: session, bandId: "fixture-band-1", name: "Band 1 Member A + Band 1 Member B",
                bandType: "Band_Duets", teamKey: "fixture-team-1"
            )
        }
        .dynamicTypeSize(typeSize)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Five Worst Songs", "Fixture Pulse"])
    let suffix = typeSize.isAccessibilitySize ? "-ax3" : ""
    _ = try nativeHostedPNG(image, filename: "band-detail-a11y\(suffix).png", environment: "FST_BANDS_RENDER_OUT")

    let tree = nativeHostedAccessibility(host)
    let order = [
        "fst.band.subtitle", "fst.band.members-section", "fst.band.summary-section",
        "fst.band.statistics-section", "fst.band.history-section", "fst.band.best-songs",
        "fst.band.worst-songs",
    ]
    let positions = order.map { tree.identifiers.firstIndex(of: $0) }
    #expect(positions.allSatisfy { $0 != nil }, "missing sections: \(tree.identifiers)")
    #expect(positions.compactMap { $0 } == positions.compactMap { $0 }.sorted(), "reading order: \(tree.identifiers)")
    #expect(tree.contains("Duos • 29 appearances"))
    #expect(tree.contains("View Band 1 Member A, Lead"))
    #expect(tree.contains("Band rank history"))

    for identifier in [
        "fst.band.member.fixture-band-1-a", "fst.band.member.fixture-band-1-b",
        "fst.band.song-row.fixture-pulse", "fst.band.song-row.fixture-ghost-song",
    ] {
        let frame = try #require(nativeHostedAccessibilityFrame(identifier, in: host), "\(identifier) unreachable")
        #expect(frame.height >= 44, "\(identifier) is \(frame.height) pt tall")
    }
    let pulse = try #require(nativeHostedAccessibilityElement("fst.band.song-row.fixture-pulse", in: host))
    #expect(nativeHostedAccessibilityString(pulse, "accessibilityLabel").hasPrefix("Fixture Pulse, Top 10%, rank 1 of 10"))
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
    let tree = nativeHostedAccessibility(host)
    // No selected player: no pinned band footer (issue #306).
    #expect(!tree.identifiers.contains(songBandFooterID))
    // The solo board's song header, with the band size where the instrument goes, and
    // no "<Band> Scores" title (issue #317). The shared header names the song once
    // (issue #315; row behavior: `SongHeaderTextTests`).
    #expect(tree.identifiers.contains(songBandHeaderID))
    #expect(tree.texts.filter { $0.contains(song.title) }.count == 1, "texts: \(tree.texts)")
    #expect(tree.contains(song.artist))
    #expect(tree.contains("Duos · 29 entries"))
    #expect(!tree.contains("Duos Scores"))
    // The bar stays empty until the header scrolls away.
    #expect(!tree.identifiers.contains("fst.song-band-leaderboard.pinned-title"))
}

private let songBandHeaderID = "fst.song-band-leaderboard.header"

/// Beside Song Detail in a split the band board is titled by its band size alone and
/// never repeats the song's art, title or artist (owner-approved variant, #342).
@MainActor
@Test func songBandLeaderboardBesideSongDetailIsTitledByBandSize() async throws {
    let (session, _, _) = try await bandsFixtureSession()
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    let host = nativeHostedView(
        NavigationStack {
            SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets")
                .splitPaneContext(SplitPaneContext(role: .trailing, besideList: .songDetail))
        }
        .preferredColorScheme(.dark),
        size: CGSize(width: 520, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 520, height: 900))
    defer { window.orderOut(nil) }
    await settle(host)
    let image = try nativeHostedImage(host)
    _ = try nativeHostedPNG(image, filename: "song-band-leaderboard-split-title.png", environment: "FST_BANDS_RENDER_OUT")
    let tree = nativeHostedAccessibility(host)
    #expect(tree.identifiers.contains("fst.song-band-leaderboard.board-title"))
    #expect(!tree.identifiers.contains(songBandHeaderID))
    #expect(!tree.contains(song.title) && !tree.contains(song.artist), "texts: \(tree.texts)")
    #expect(tree.contains("Duos"))
    #expect(tree.contains("29 entries"))
}

/// The header's board line names the board and adds the entry total only when the
/// service asks for totals, for the solo and band boards alike (issue #317).
@Test func songLeaderboardBoardLineAddsTotalsOnlyWhenAsked() {
    #expect(SongLeaderboardBoardLine.text(name: "Duos", totalEntries: 1234, showsTotals: true)
        == "Duos · \(1234.formatted()) entries")
    #expect(SongLeaderboardBoardLine.text(name: "Quads", totalEntries: 1234, showsTotals: false) == "Quads")
    #expect(SongLeaderboardBoardLine.text(name: "Lead", totalEntries: 7, showsTotals: nil) == "Lead")
    // A band size just picked, before its first response: the name alone.
    #expect(SongLeaderboardBoardLine.text(name: "Trios", totalEntries: nil, showsTotals: nil) == "Trios")
    #expect(SongLeaderboardBoardLine.text(name: "Trios", totalEntries: nil, showsTotals: true) == "Trios")
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
    // Another band size keeps the song header with its own label (issue #317).
    let tree = nativeHostedAccessibility(host)
    #expect(tree.identifiers.contains(songBandHeaderID))
    #expect(tree.contains("Trios · 0 entries"))
}

/// Passes requests to the fixture service, holding Trios band-board reads until the
/// test releases them, so the page can be inspected mid-reload.
private actor HeldTriosTransport: HTTPTransport {
    private let base = URLSessionHTTPTransport()
    private var released = false
    private var heldCount = 0
    private var held: [CheckedContinuation<Void, Never>] = []
    private var arrival: CheckedContinuation<Void, Never>?

    /// Send a request, holding a Trios band-board read until ``release()``.
    ///
    /// - Parameter request: Public GET to the fixture service.
    /// - Returns: The fixture service's response.
    /// - Throws: Transport failures from the fixture service.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        if !released, request.url?.path.hasSuffix("/bands/Band_Trios") == true {
            heldCount += 1
            arrival?.resume()
            arrival = nil
            await withCheckedContinuation { held.append($0) }
        }
        return try await base.send(request)
    }

    /// Wait until a Trios read is being held.
    func waitForHeldRead() async {
        if heldCount > 0 { return }
        await withCheckedContinuation { arrival = $0 }
    }

    /// Let held and later Trios reads through.
    func release() {
        released = true
        held.forEach { $0.resume() }
        held = []
    }
}

/// The band size a hosted test switches, standing in for the Band Size tool.
@MainActor @Observable
private final class BandSizeSelection {
    var size: BandType = .duets
}

/// Hosts the band board on a band size the test owns.
private struct BandSizeHarness: View {
    let session: FestivalSession
    let song: Song
    @Bindable var selection: BandSizeSelection

    var body: some View {
        SongBandLeaderboardContent(session: session, song: song, bandType: $selection.size)
    }
}

/// Switching Duos to Trios keeps the song header on screen through the reload and
/// names Trios at once; the Trios total joins only once Trios answers, and a Duos
/// total never sits under "Trios" (song-leaderboard-header R5, issue #317).
@MainActor
@Test func songBandLeaderboardKeepsTheHeaderWhileAnotherBandSizeLoads() async throws {
    let transport = HeldTriosTransport()
    let client = try FestivalAPI(baseURL: try await RivalsMockService.shared.baseURL(), transport: transport)
    let session = FestivalSession(factory: { client })
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    let selection = BandSizeSelection()
    let host = nativeHostedView(
        NavigationStack { BandSizeHarness(session: session, song: song, selection: selection) }
            .preferredColorScheme(.dark),
        size: CGSize(width: 402, height: 900)
    )
    let window = nativeHostedWindow(host, size: CGSize(width: 402, height: 900))
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: ["Duos · 29 entries"])

    selection.size = .trios
    await transport.waitForHeldRead()
    var sawSpinner = false
    for _ in 0..<8 {
        try await Task.sleep(for: .milliseconds(100))
        host.layoutSubtreeIfNeeded()
        let tree = nativeHostedAccessibility(host)
        sawSpinner = sawSpinner || tree.identifiers.contains("fst.song-band-leaderboard.loading")
        #expect(tree.identifiers.contains(songBandHeaderID), "Header dropped mid-reload: \(tree.texts)")
        #expect(tree.contains(song.title))
        #expect(tree.contains("Trios"), "Header does not name Trios mid-reload: \(tree.texts)")
        #expect(!tree.contains("Duos ·") && !tree.contains("Trios ·"), "Stale total mid-reload: \(tree.texts)")
    }
    #expect(sawSpinner, "The rows never reloaded behind the header")
    _ = try nativeHostedPNG(
        try nativeHostedImage(host), filename: "song-band-leaderboard-trios-reloading.png",
        environment: "FST_BANDS_RENDER_OUT"
    )

    await transport.release()
    let image = try await nativeHostedSettle(host, untilText: ["Trios · 0 entries"])
    _ = try nativeHostedPNG(image, filename: "song-band-leaderboard-duos-to-trios.png", environment: "FST_BANDS_RENDER_OUT")
    #expect(nativeHostedAccessibility(host).identifiers.contains(songBandHeaderID))
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
    #expect(tree.contains("View All Bands (18), Duos"))
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
    // The title and View All stay usable while the cards are unavailable.
    #expect(tree.contains("Fixture Player 1's Bands"))
    #expect(tree.identifiers.contains("fst.player.bands-link"))
    #expect(tree.contains("View All Fixture Player 1's Bands"))
}

// MARK: - Song Detail band preview columns (#366)

/// Frames of Song Detail's Duos, Trios and Quads sections and of their headers (a header's
/// text is centred in its 44 pt row, so header centres share a row's line) once loaded.
@MainActor
private func songDetailBandFrames(
    width: CGFloat
) async throws -> (sections: [BandType: CGRect], headers: [BandType: CGRect]) {
    let (session, _, _) = try await bandsFixtureSession()
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    let size = CGSize(width: width, height: 6000)
    let host = nativeHostedView(
        NavigationStack { SongDetailScreen(song: song, session: session) }
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    func read(_ prefix: String) -> [BandType: CGRect] {
        BandType.allCases.reduce(into: [:]) { result, bandType in
            result[bandType] = nativeHostedAccessibilityFrame("\(prefix).\(bandType.rawValue)", in: host)
        }
    }
    for _ in 0..<60 {
        await settle(host, iterations: 1)
        if read("fst.song-detail.band").count == BandType.allCases.count,
           nativeHostedAccessibilityFrame("fst.song-detail.band-row.Band_Duets.0", in: host) != nil { break }
    }
    // Let the rows' load-in rise (`FestivalFadeIn.riseDistance`) finish.
    await settle(host, iterations: 10)
    return (read("fst.song-detail.band"), read("fst.song-detail.band-header"))
}

/// Wide Song Detail flows the band previews into the instrument cards' columns
/// (`SongDetailCardGrid`, pattern `hinge-columns`): Duos beside Trios, Quads under Duos.
/// Before #366 they were full-width sections stacked under the grid.
@MainActor
@Test func songDetailBandPreviewsFlowInCardColumnsWhenWide() async throws {
    let (sections, headers) = try await songDetailBandFrames(width: 1000)
    let duos = try #require(sections[.duets])
    let trios = try #require(sections[.trios])
    let quads = try #require(sections[.quad])
    #expect(abs(try #require(headers[.duets]).midY - (try #require(headers[.trios]).midY)) < 1.5)
    #expect(trios.minX - duos.maxX >= SongDetailCardColumns.spacing - 1.5)
    #expect(abs(duos.width - trios.width) < 1.5)
    #expect(duos.width >= SongDetailCardColumns.minimumWidth)
    #expect(abs(quads.minX - duos.minX) < 1.5)
    #expect(quads.minY > max(duos.maxY, trios.maxY))
}

/// iPhone width keeps one column: Duos, Trios and Quads stack at full width.
@MainActor
@Test func songDetailBandPreviewsStayOneColumnOnIPhone() async throws {
    let (sections, _) = try await songDetailBandFrames(width: 402)
    let duos = try #require(sections[.duets])
    let trios = try #require(sections[.trios])
    let quads = try #require(sections[.quad])
    #expect(abs(trios.minX - duos.minX) < 1.5)
    #expect(abs(quads.minX - duos.minX) < 1.5)
    #expect(trios.minY > duos.maxY)
    #expect(quads.minY > trios.maxY)
}

@Test func playerBandsRouteDefaultsToAllAndCarriesGroup() {
    #expect(AppRoute.playerBands(accountId: "a", displayName: nil)
        == .playerBands(accountId: "a", displayName: nil, group: .all))
    #expect(AppRoute.playerBands(accountId: "a", displayName: nil, group: .duos)
        != .playerBands(accountId: "a", displayName: nil))
}

/// The full band board's page rows are one card, like the Song Detail band preview
/// (owner #543): 48 pt rows in rank order, abutting, labels and identifiers unchanged.
@MainActor
@Test func songBandLeaderboardRowsAreOneAccessibleCard() async throws {
    nativeHostedEnableAccessibility()
    let (session, _, _) = try await bandsFixtureSession()
    let song = try await fixtureSong(session, songId: "fixture-pulse")
    let size = CGSize(width: 402, height: 900)
    let host = nativeHostedView(
        NavigationStack {
            SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets")
        }
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let prefix = "fst.song-band-leaderboard.row."
    func firstRows() -> [String] {
        var seen = Set<String>()
        return Array(nativeHostedAccessibility(host).identifiers.filter {
            $0.hasPrefix(prefix) && seen.insert($0).inserted
        }.prefix(3))
    }
    let image = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        let rows = firstRows()
        return rows.count == 3 && boardRowsAbut(rows, in: host)
    }
    _ = try nativeHostedPNG(image, filename: "song-band-leaderboard-group-card.png", environment: "FST_BANDS_RENDER_OUT")
    try expectBoardRowsInOneCard(firstRows(), in: host)
}
#endif
