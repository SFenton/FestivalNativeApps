import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Song row visual order (issue #372)

/// The default order is the web's `DEFAULT_METADATA_ORDER` (Stars after Percentile),
/// distinct from the Show Instrument Metadata switches' order.
@Test func songRowDefaultOrderMatchesWeb() {
    #expect(MetadataField.defaultSongRowOrder.map(\.rawValue) == [
        "score", "percentage", "percentile", "stars", "season", "intensity", "difficulty", "lastPlayed",
    ])
    #expect(Set(MetadataField.defaultSongRowOrder) == Set(MetadataField.allCases))
    #expect(MetadataField.defaultSongRowOrder.count == MetadataField.allCases.count)
    #expect(MetadataField.allCases.firstIndex(of: .stars)! > MetadataField.allCases.firstIndex(of: .difficulty)!)
}

/// Reset Settings restores the web default, not the switches' order.
@Test func songRowResetDefaultIsWebOrder() throws {
    let entry = try #require(SettingsRegistry.defaults.first { $0.key == "fst.settings.songRowVisualOrder" })
    guard case .string(let raw) = entry.value else {
        Issue.record("Song Row Visual Order default isn't a string")
        return
    }
    #expect(raw == SettingsOrder.encode(MetadataField.defaultSongRowOrder))
}

/// A saved order keeps its known fields once each, then appends missing ones in the web
/// default order.
@Test func songRowSavedOrderRestoresAndCompletes() {
    #expect(MetadataField.savedSongRowOrder("") == MetadataField.defaultSongRowOrder)
    #expect(MetadataField.savedSongRowOrder("lastPlayed,bogus,difficulty,lastPlayed") == [
        .lastPlayed, .difficulty, .score, .percentage, .percentile, .stars, .season, .intensity,
    ])
    let custom: [MetadataField] = [.intensity, .score, .stars, .percentage, .percentile, .season, .difficulty, .lastPlayed]
    #expect(MetadataField.savedSongRowOrder(SettingsOrder.encode(custom)) == custom)
}

/// Songs rows use the saved order only while Independent Visual Order is on (web
/// `SongsPage.visibleMetadataOrder`).
@Test func songRowOrderFollowsIndependentVisualOrderSwitch() {
    let saved = SettingsOrder.encode([MetadataField.lastPlayed, .score])
    #expect(MetadataField.songRowOrder(independent: false, saved: saved) == MetadataField.defaultSongRowOrder)
    #expect(MetadataField.songRowOrder(independent: true, saved: saved).prefix(2) == [.lastPlayed, .score])
}

/// The default order puts a selected player's Stars pill before Season on a row.
@Test func songRowDefaultOrderPlacesStarsBeforeSeason() {
    let fields: [SongMetadataField] = [
        .score(1), .season(1, current: false), .stars(count: 5, gold: false),
    ]
    let ordered = SongProfileCardPolicy.reordered(
        fields, by: MetadataField.songRowOrder(independent: false, saved: "")
    )
    #expect(ordered.map(\.id) == [.score, .stars, .season])
}
