#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

private struct SelectedRowFixtures {
    let song: Song
    let season: Int
    let profiles: [String: Data]
}

private actor HostedPlayerCardTransport: HTTPTransport {
    let profiles: [String: Data]
    private var paths: [String] = []

    /// Serve only the checked-in synthetic compact player envelopes.
    ///
    /// - Parameter profiles: Identity-keyed original fixture bytes.
    init(profiles: [String: Data]) { self.profiles = profiles }

    /// Reject writes, privileged selection headers and mixed-account reads.
    ///
    /// - Parameter request: One response-proven native public GET.
    /// - Returns: Pinned publication or the requested synthetic player.
    /// - Throws: Invalid method, header, publication or account.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        if url.path == "/api/publication" {
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":7,"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        let prefix = "/api/player/"
        guard url.path.hasPrefix(prefix),
              request.value(forHTTPHeaderField: "X-FST-Publication-Id") == "7",
              let profile = profiles[String(url.path.dropFirst(prefix.count))] else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        paths.append(url.path)
        return HTTPResult(
            status: 200, data: profile,
            headers: ["X-FST-Publication-Id": "7"]
        )
    }

    /// Prove each selected row was backed by its own headerless profile GET.
    ///
    /// - Returns: Actual in-memory transport paths, excluding publication.
    func recordedPaths() -> [String] { paths }
}

/// Keep the original song/score fixtures coherent while omitting test-only art requests.
///
/// - Returns: Validated catalogue row, season and compact profile envelopes.
/// - Throws: Missing or internally inconsistent checked-in fixture data.
private func selectedRowFixtures() throws -> SelectedRowFixtures {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let songsURL = root.appendingPathComponent("contracts/fixtures/songs-demo.json")
    let playersURL = root.appendingPathComponent("contracts/fixtures/player-demo.json")
    let songObject = try JSONSerialization.jsonObject(with: Data(contentsOf: songsURL))
    guard var catalog = songObject as? [String: Any],
          var rows = catalog["songs"] as? [[String: Any]],
          let index = rows.firstIndex(where: { $0["songId"] as? String == "fixture-pulse" })
    else { throw FestivalAPIError.invalidCatalogue }
    rows[index].removeValue(forKey: "albumArt")
    catalog["songs"] = rows
    let songs = try JSONDecoder().decode(
        SongsResponse.self, from: JSONSerialization.data(withJSONObject: catalog)
    )
    try songs.validate()
    let song = try #require(songs.songs.first { $0.songId == "fixture-pulse" })
    let season = try #require(songs.currentSeason)
    #expect(song.albumArt == nil)
    let playerObject = try JSONSerialization.jsonObject(with: Data(contentsOf: playersURL))
    guard let envelope = playerObject as? [String: Any],
          let profiles = envelope["profiles"] as? [String: [String: Any]]
    else { throw FestivalAPIError.invalidPlayerProfile }
    let bytes = try profiles.mapValues { try JSONSerialization.data(withJSONObject: $0) }
    return SelectedRowFixtures(song: song, season: season, profiles: bytes)
}

/// Select one validated synthetic identity without persisting score bytes.
///
/// - Parameters:
///   - accountId: Fixture account one or two.
///   - fixtures: Shared coherent score and song bytes.
/// - Returns: Available in-process score index and selected public identity.
/// - Throws: Wrong player, publication or compact score.
@MainActor
private func selectedRowSession(
    accountId: String, fixtures: SelectedRowFixtures
) async throws -> FestivalSession {
    let transport = HostedPlayerCardTransport(profiles: fixtures.profiles)
    let client = try FestivalAPI(transport: transport)
    let session = FestivalSession(factory: { client })
    let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
    {"accountId":"\(accountId)","displayName":"Fixture Player \(accountId.suffix(1))"}
    """.utf8))
    try session.selectPlayer(result, from: await session.viewPlayer(result))
    #expect(session.playerLoadState == .available)
    #expect(await transport.recordedPaths() == ["/api/player/\(accountId)"])
    return session
}

/// Render one actual selected Song control, never a fabricated score label.
///
/// - Parameters:
///   - name: Private evidence state identifier.
///   - song: Typed charted fixture row without network-backed artwork.
///   - session: Anonymous or validated selected fixture identity.
///   - season: Current catalogue season for the inverted pill.
///   - chart: First visible or explicitly selected chart.
///   - filter: Optional real Songs instrument filter.
///   - icons: Saved Show Instrument Icons setting.
///   - visible: Enabled instrument set.
///   - metadata: Independent score-field settings.
///   - invalidFilter: Deliberately paused invalid-score policy.
///   - shop: Optional validated synthetic Shop accent.
///   - typeSize: Ordinary or accessibility text size.
///   - size: Available native card content dimensions.
/// - Returns: Real AppKit pixels, status fills and optional private screenshot bytes.
/// - Throws: Failed native render or evidence encoding.
@MainActor
private func selectedSongRow(
    name: String, song: Song, session: FestivalSession, season: Int,
    chart: Instrument = .lead, filter: Instrument? = nil,
    icons: Bool = true, visible: Set<Instrument> = Set(Instrument.allCases),
    metadata: SongMetadataVisibility = SongMetadataVisibility(),
    invalidFilter: Bool = false, shop: ShopHighlight? = nil,
    typeSize: DynamicTypeSize = .large, size: CGSize = CGSize(width: 390, height: 320)
) throws -> (data: Data, fills: (gold: Int, green: Int, red: Int)) {
    let host = nativeHostedView(
        SongRowView(
            song: song, instrument: filter, session: session, highContrast: false,
            shopHighlight: shop, profileChart: chart, catalogueObservation: 7,
            metadata: metadata,
            filterInvalidScores: invalidFilter, showInstrumentIcons: icons,
            visibleInstruments: visible, currentSeason: season
        )
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, typeSize)
        .background(BrandTokens.appBackground),
        size: size
    )
    let image = try nativeHostedImage(host)
    let scale = CGFloat(image.width) / size.width
    #expect((1...3).contains(scale))
    #expect(abs(CGFloat(image.height) / size.height - scale) < 0.02)
    #expect(nativeHostedControlPixels(image).bright > 20)
    return (
        try nativeHostedPNG(
            image, filename: "songs-selected-\(name).png",
            environment: "FST_SONG_ROW_RENDER_OUT"
        ),
        nativeHostedStatusPixels(image)
    )
}

/// Two real selected accounts must change chips, Score/FC and visible Drums context.
@MainActor
@Test func selectedSongsRowsPaintProfileSettingsAndFirstVisibleChart() async throws {
    let fixtures = try selectedRowFixtures()
    let first = try await selectedRowSession(accountId: "fixture-player-1", fixtures: fixtures)
    let second = try await selectedRowSession(accountId: "fixture-player-2", fixtures: fixtures)
    #expect(first.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_900)
    #expect(second.selectedPlayerScores["fixture-pulse"]?[.lead]?.score == 99_800)
    #expect(second.selectedPlayerScores["fixture-pulse"]?[.drums]?.score == 88_800)
    let anonymous = FestivalSession(factory: { throw FestivalAPIError.invalidResource })

    let plain = try selectedSongRow(
        name: "anonymous", song: fixtures.song, session: anonymous,
        season: fixtures.season, icons: false
    )
    let firstChips = try selectedSongRow(
        name: "first-chips", song: fixtures.song, session: first, season: fixtures.season
    )
    let secondChips = try selectedSongRow(
        name: "second-chips", song: fixtures.song, session: second, season: fixtures.season
    )
    #expect(plain.data != firstChips.data)
    #expect(firstChips.data != secondChips.data)
    #expect(firstChips.fills.green > 10 && firstChips.fills.red > 10)
    #expect(secondChips.fills.gold > 10 && secondChips.fills.green > 10)
    #expect(secondChips.fills.red > 10)

    let lead = try selectedSongRow(
        name: "player-two-fc", song: fixtures.song, session: second,
        season: fixtures.season, icons: false, shop: .new
    )
    var hiddenScore = SongMetadataVisibility()
    hiddenScore.score = false
    let accuracyFirst = try selectedSongRow(
        name: "score-hidden-fc", song: fixtures.song, session: second,
        season: fixtures.season, icons: false, metadata: hiddenScore
    )
    let drums = try selectedSongRow(
        name: "filtered-drums", song: fixtures.song, session: second,
        season: fixtures.season, chart: .drums, filter: .drums
    )
    let visibleDrums = try selectedSongRow(
        name: "first-visible-drums", song: fixtures.song, session: second,
        season: fixtures.season, chart: .drums, icons: false,
        visible: [.drums, .vocals, .proDrums]
    )
    let paused = try selectedSongRow(
        name: "invalid-filter-paused", song: fixtures.song, session: second,
        season: fixtures.season, icons: false, invalidFilter: true
    )
    let largest = try selectedSongRow(
        name: "chips-ax5", song: fixtures.song, session: second,
        season: fixtures.season, typeSize: .accessibility5,
        size: CGSize(width: 390, height: 620)
    )
    #expect(lead.data != accuracyFirst.data)
    #expect(lead.data != drums.data)
    #expect(drums.data == visibleDrums.data)
    #expect(lead.data != paused.data)
    #expect(lead.fills.gold > 10)
    #expect(largest.fills.gold > 10 && largest.fills.green > 10)
}

/// The same anonymous native card must paint the source's optional duration.
@MainActor
@Test func songRowPaintsOptionalCatalogueDuration() throws {
    let plain = try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-duration","title":"Fixture Ballad","artist":"Test Ensemble",
     "year":2026}
    """.utf8))
    let timed = try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-duration","title":"Fixture Ballad","artist":"Test Ensemble",
     "year":2026,"durationSeconds":366}
    """.utf8))
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let withoutDuration = try selectedSongRow(
        name: "without-duration", song: plain, session: session, season: 9, icons: false
    )
    let withDuration = try selectedSongRow(
        name: "with-duration", song: timed, session: session, season: 9, icons: false
    )
    #expect(withoutDuration.data != withDuration.data)
}
#endif
