import Foundation
import Testing
@testable import FestivalCore

/// Build a minimal fixture DTO, overriding only the fields a test needs.
private func dto(
    eventKind: String, songId: String? = nil, instrument: String? = Instrument.lead.rawValue,
    metric: String? = nil, oldRank: Int? = nil, newRank: Int? = nil,
    newNumeric: Double? = nil, oldNumeric: Double? = nil
) -> ImprovementNotificationDto {
    ImprovementNotificationDto(
        eventId: 1, notificationGuid: "guid-1", accountId: "acc-1", eventKind: eventKind,
        songId: songId, instrument: instrument, metric: metric, oldNumeric: oldNumeric,
        newNumeric: newNumeric, oldRank: oldRank, newRank: newRank, payload: nil,
        detectedAt: "2024-01-01T00:00:00Z", expiresAt: "2024-02-01T00:00:00Z"
    )
}

// MARK: - Ranking metric mapping

@Test func rankMetricResolvesFromEventKindBeforeMetricString() {
    #expect(NotificationRankingMetric.metric(
        eventKind: "player_weighted_rank_improved", metric: nil
    ) == .weighted)
    #expect(NotificationRankingMetric.metric(
        eventKind: "player_skill_rank_improved", metric: "ignored"
    ) == .adjusted)
    #expect(NotificationRankingMetric.metric(eventKind: nil, metric: "fc_rate_rank") == .fcrate)
    #expect(NotificationRankingMetric.metric(eventKind: "player_score_pb", metric: nil) == nil)
}

// MARK: - Destination

@Test func songEventResolvesToSongDestination() {
    let event = dto(eventKind: "player_score_pb", songId: "song-1", instrument: "Solo_Bass")
    guard case let .song(songId, instrument) = NotificationDestinationResolver.destination(for: event) else {
        Issue.record("Expected a song destination")
        return
    }
    #expect(songId == "song-1")
    #expect(instrument == .bass)
}

@Test func rankEventResolvesToRankingsDestination() {
    let event = dto(eventKind: "player_weighted_rank_improved", instrument: "Solo_Guitar")
    guard case let .rankings(instrument, metric) = NotificationDestinationResolver.destination(for: event) else {
        Issue.record("Expected a rankings destination")
        return
    }
    #expect(instrument == .lead)
    #expect(metric == .weighted)
}

@Test func unknownEventHasNoDestination() {
    let event = dto(eventKind: "player_total_score_improved", songId: nil)
    #expect(NotificationDestinationResolver.destination(for: event) == nil)
}


// MARK: - Web text parity

/// One fixture row: a wire DTO, its catalogue facts and the web engine's output.
private struct ParityCase: Decodable {
    struct Song: Decodable { let title: String; let artist: String?; let albumArt: String? }
    struct Part: Decodable { let text: String; let emphasis: Bool }
    struct Group: Decodable { let instrument: String; let flags: [String] }
    struct Expected: Decodable {
        let title: String
        let message: String
        let parts: [Part]
        let flags: [String]
        let groups: [Group]
    }

    let name: String
    let dto: ImprovementNotificationDto
    let song: Song?
    let playerName: String?
    let expected: Expected
}

private struct ParityFixture: Decodable { let cases: [ParityCase] }

private let enUS = Locale(identifier: "en_US")

/// Format `dto` the way `NotificationsCenter.refresh` does, with a fixed locale.
private func present(
    _ dto: ImprovementNotificationDto, song: NotificationSongInfo? = nil, playerName: String? = nil
) -> AppNotification {
    NotificationText.format(dto, song: song, playerName: playerName, locale: enUS)
}

private func decodeDto(_ json: String) throws -> ImprovementNotificationDto {
    try JSONDecoder().decode(ImprovementNotificationDto.self, from: Data(json.utf8))
}

private let fixtureSong = NotificationSongInfo(title: "Fixture Anthem", artist: "The Fixtures", albumArt: "fixture.jpg")

/// Every case in `notification-text-web-parity.json` was produced by running the
/// web's `formatNotificationPresentation` over the same DTO (live SFentonX feed
/// rows plus synthetic edge cases); the Swift port must match title, message,
/// emphasis runs, flags and per-instrument flag groups exactly.
@Test func notificationTextMatchesWebEngineForEveryFixtureCase() throws {
    let url = try #require(Bundle.module.url(forResource: "notification-text-web-parity", withExtension: "json"))
    let fixture = try JSONDecoder().decode(ParityFixture.self, from: Data(contentsOf: url))
    #expect(fixture.cases.count >= 40)
    for parity in fixture.cases {
        let song = parity.song.map { NotificationSongInfo(title: $0.title, artist: $0.artist, albumArt: $0.albumArt) }
        let result = present(parity.dto, song: song, playerName: parity.playerName)
        let expected = parity.expected
        #expect(result.title == expected.title, "\(parity.name) title")
        #expect(result.message == expected.message, "\(parity.name) message")
        #expect(result.messageParts.map(\.text) == expected.parts.map(\.text), "\(parity.name) parts")
        #expect(result.messageParts.map(\.emphasis) == expected.parts.map(\.emphasis), "\(parity.name) emphasis")
        #expect(result.flags.map(\.rawValue) == expected.flags, "\(parity.name) flags")
        #expect(result.flagGroups.map(\.instrument.rawValue) == expected.groups.map(\.instrument), "\(parity.name) groups")
        #expect(result.flagGroups.map { $0.flags.map(\.rawValue) } == expected.groups.map(\.flags), "\(parity.name) group flags")
    }
}

// MARK: - Presentation model

@Test func liveFirstScoreRowEmphasisesValuesAndShowsAlbumArt() throws {
    let row = try decodeDto("""
    {"eventId":7,"notificationGuid":"g","eventKind":"player_first_score","songId":"s","instrument":"Solo_Guitar",
     "newNumeric":596888,"newRank":18,"detectedAt":"2026-10-01T00:00:00Z","expiresAt":"2026-10-08T00:00:00Z",
     "payload":{"newFullCombo":true,"newStars":6}}
    """)
    let result = present(row, song: NotificationSongInfo(title: "Night Terror", artist: "x", albumArt: "nt.jpg"))
    #expect(result.title == "Night Terror · Lead")
    #expect(result.message == "Your first Lead play on Night Terror scored 596,888 points, started at #18, got a Full Combo, and earned gold stars.")
    #expect(result.messageParts.filter(\.emphasis).map(\.text) == ["Lead", "Night Terror", "596,888", "#18", "Full Combo", "gold stars"])
    #expect(result.flags == [.firstPlay, .fullCombo, .goldStars])
    #expect(result.flagGroups.isEmpty)
    #expect(result.media == .song(albumArt: "nt.jpg"))
    #expect(result.accessibilityLabel.hasPrefix("Night Terror · Lead"))
    #expect(result.destination == .song(songId: "s", instrument: .lead))
}

@Test func multiChartRowShowsArtAboveInstrumentGridInCanonicalOrder() throws {
    let row = try decodeDto("""
    {"eventId":8,"notificationGuid":"g","eventKind":"player_score_pb","songId":"s","instrument":"Solo_Drums",
     "detectedAt":"2026-10-01T00:00:00Z","expiresAt":"2026-10-08T00:00:00Z",
     "payload":{"coalescedInstruments":["Solo_Drums","Solo_Guitar"],"coalescedEvents":[
       {"eventKind":"player_score_pb","instrument":"Solo_Drums","newNumeric":1},
       {"eventKind":"player_fc_achieved","instrument":"Solo_Guitar"}]}}
    """)
    let result = present(row, song: fixtureSong)
    #expect(result.media == .songInstrumentGrid(albumArt: "fixture.jpg", instruments: [.lead, .drums]))
    #expect(result.title == "Fixture Anthem")
    #expect(result.flagGroups.map(\.instrument) == [.lead, .drums])
    #expect(result.flagGroups.first?.accessibilityLabel == "Lead: Full Combo")
}

@Test func mediaFallsBackToInstrumentIconWithoutArtwork() {
    let pb = dto(eventKind: "player_score_pb", songId: "unknown", instrument: "Solo_Bass", newNumeric: 1)
    #expect(present(pb).media == .soloInstrument(.bass))
    #expect(present(pb).title == "unknown · Bass")

    let noInstrument = dto(eventKind: "totally_unknown_kind", instrument: nil)
    let unknown = present(noInstrument, playerName: "SFentonX")
    #expect(unknown.media == .soloInstrument(.lead))
    #expect(unknown.title == "SFentonX")
    #expect(unknown.message == "New improvement detected.")
    #expect(unknown.flags == [.improvement])
    #expect(present(noInstrument).title == "Notification")
}

@Test func shopSongRowPrefersCatalogueArtAndHasNoFlags() throws {
    let row = try decodeDto("""
    {"eventId":9,"notificationGuid":"g","eventKind":"service_new_shop_song","songId":"s",
     "detectedAt":"2026-10-01T00:00:00Z","expiresAt":"2026-10-08T00:00:00Z",
     "payload":{"songTitle":"Payload Title","artist":"Payload Artist","albumArt":"payload.jpg"}}
    """)
    let withCatalogue = present(row, song: fixtureSong)
    #expect(withCatalogue.title == "New Song · Payload Title - Payload Artist")
    #expect(withCatalogue.messageParts.filter(\.emphasis).map(\.text) == ["Payload Title", "Payload Artist"])
    #expect(withCatalogue.flags.isEmpty)
    #expect(withCatalogue.media == .song(albumArt: "fixture.jpg"))
    #expect(present(row).media == .song(albumArt: "payload.jpg"))

    let bare = dto(eventKind: "service_new_shop_song", songId: nil, instrument: nil)
    #expect(present(bare).title == "New Song · New Song - Unknown Artist")
    #expect(present(bare).media == .soloInstrument(.lead))
}

@Test func lenientPayloadDecodingAcceptsStringNumbersAndBooleans() throws {
    let row = try decodeDto("""
    {"eventId":10,"notificationGuid":"g","eventKind":"player_score_pb","songId":"s","instrument":"Solo_Guitar",
     "detectedAt":"2026-10-01T00:00:00Z","expiresAt":"2026-10-08T00:00:00Z",
     "payload":{"oldStars":"5","newStars":6,"newFullCombo":"true","coalescedInstruments":["Solo_Guitar",7,"bogus"],
       "coalescedEvents":[{"eventKind":"player_score_pb","newNumeric":"123456","oldRank":"10","newRank":9.0,"newLabel":42}]}}
    """)
    let payload = try #require(row.payload)
    #expect(payload.oldStars == 5)
    #expect(payload.newStars == 6)
    #expect(payload.newFullCombo == true)
    // Non-string elements and labels are dropped, as web `stringValue` does.
    #expect(payload.coalescedInstruments == ["Solo_Guitar", "bogus"])
    let event = try #require(payload.coalescedEvents?.first)
    #expect(event.newNumeric == 123_456)
    #expect(event.oldRank == 10)
    #expect(event.newRank == 9)
    #expect(event.newLabel == nil)
    #expect(present(row, song: fixtureSong).media == .song(albumArt: "fixture.jpg"))
}

@Test func flagKindsMapEventKindsAndUseWebLabels() {
    #expect(NotificationFlagKind.forEventKind("player_first_score") == .firstPlay)
    #expect(NotificationFlagKind.forEventKind("player_score_pb") == .newHighScore)
    #expect(NotificationFlagKind.forEventKind("player_skill_rank_improved") == .rankUp)
    #expect(NotificationFlagKind.forEventKind("player_fc_count_improved") == .progress)
    #expect(NotificationFlagKind.forEventKind("future") == .improvement)
    #expect(NotificationFlagKind.allCases.map(\.label) == [
        "Improvement", "First Play", "New High Score", "Full Combo", "Rank Up",
        "Gold Stars", "Stars Up", "Difficulty Up", "Progress",
    ])
}

@Test func emphasisSplitsLongestTermsFirstAndIgnoresFallbacks() {
    #expect(NotificationTextEngine.filterEmphasis(["#1", nil, " ", "this song", "#12", "#1"]) == ["#12", "#1"])
    let parts = NotificationTextEngine.emphasize("From #1 to #12.", terms: ["#1", "#12"])
    #expect(parts.map(\.text) == ["From ", "#1", " to ", "#12", "."])
    #expect(parts.map(\.emphasis) == [false, true, false, true, false])
    #expect(NotificationTextEngine.emphasize("Plain.", terms: []).map(\.text) == ["Plain."])
}
