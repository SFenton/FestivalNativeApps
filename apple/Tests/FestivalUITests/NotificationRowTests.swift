import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

/// Decode one wire row and present it with a fixed locale and a catalogue song.
private func notification(_ json: String, albumArt: String? = "art.jpg") throws -> AppNotification {
    let dto = try JSONDecoder().decode(ImprovementNotificationDto.self, from: Data(json.utf8))
    return NotificationText.format(
        dto, song: NotificationSongInfo(title: "Night Terror", artist: "x", albumArt: albumArt),
        locale: Locale(identifier: "en_US")
    )
}

private let firstScore = """
{"eventId":1,"notificationGuid":"g1","eventKind":"player_first_score","songId":"s","instrument":"Solo_Guitar",
 "newNumeric":596888,"newRank":18,"detectedAt":"2026-10-01T00:00:00Z","expiresAt":"2026-10-08T00:00:00Z",
 "payload":{"newFullCombo":true,"newStars":6}}
"""

private let multiChart = """
{"eventId":2,"notificationGuid":"g2","eventKind":"player_score_pb","songId":"s","instrument":"Solo_Drums",
 "detectedAt":"2026-10-01T00:00:00Z","expiresAt":"2026-10-08T00:00:00Z",
 "payload":{"coalescedEvents":[
   {"eventKind":"player_score_pb","instrument":"Solo_Drums","newNumeric":1},
   {"eventKind":"player_fc_achieved","instrument":"Solo_Guitar"}]}}
"""

@Test func chipFlowWrapsGreedilyAndGivesOversizedChipsTheirOwnLine() {
    let sizes = [CGSize(width: 40, height: 20), CGSize(width: 50, height: 24), CGSize(width: 30, height: 20)]
    let oneLine = NotificationChipFlow.arrange(sizes, width: 200, spacing: 4)
    #expect(oneLine.map(\.minX) == [0, 44, 98])
    #expect(oneLine.allSatisfy { $0.minY == 0 })

    let wrapped = NotificationChipFlow.arrange(sizes, width: 100, spacing: 4)
    #expect(wrapped.map(\.minX) == [0, 44, 0])
    #expect(wrapped.map(\.minY) == [0, 0, 28])

    let narrow = NotificationChipFlow.arrange(sizes, width: 10, spacing: 4)
    #expect(narrow.map(\.minX) == [0, 0, 0])
    #expect(narrow.map(\.minY) == [0, 24, 52])
    #expect(NotificationChipFlow.arrange([], width: 100, spacing: 4).isEmpty)
}

@MainActor
@Test func messageBoldsExactlyTheEmphasizedRuns() throws {
    let row = try notification(firstScore)
    let message = NotificationRow.message(row.messageParts)
    #expect(String(message.characters) == row.message)
    let bold = message.runs[\.inlinePresentationIntent]
        .filter { $0.0 == .stronglyEmphasized }
        .map { String(message.characters[$0.1]) }
    #expect(bold == ["Lead", "Night Terror", "596,888", "#18", "Full Combo", "gold stars"])
}

@MainActor
@Test func spokenLabelAppendsFlagNamesSoMeaningIsNotColourOnly() throws {
    let single = try notification(firstScore)
    #expect(NotificationRow.accessibilityLabel(single) == "Night Terror · Lead. Your first Lead play on Night Terror "
        + "scored 596,888 points, started at #18, got a Full Combo, and earned gold stars. "
        + "First Play, Full Combo, Gold Stars.")

    let grouped = try notification(multiChart)
    #expect(NotificationRow.accessibilityLabel(grouped).hasSuffix("Lead: Full Combo. Drums: New High Score."))
    #expect(grouped.media == .songInstrumentGrid(albumArt: "art.jpg", instruments: [.lead, .drums]))

    let shop = try notification("""
    {"eventId":3,"notificationGuid":"g3","eventKind":"service_new_shop_song","songId":"s",
     "detectedAt":"2026-10-01T00:00:00Z","expiresAt":"2026-10-08T00:00:00Z"}
    """)
    #expect(NotificationRow.accessibilityLabel(shop) == shop.accessibilityLabel)
}

@Test func everyFlagKindHasADistinctWebColour() {
    let colours = NotificationFlagKind.allCases.map { "\(NotificationFlagChip.color($0))" }
    #expect(Set(colours).count == NotificationFlagKind.allCases.count)
}
