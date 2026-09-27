import Foundation
import Testing
@testable import FestivalCore

/// Build three charted local rows without using a privileged or live profile.
///
/// - Returns: Valid Songs with distinct Lead/Drums support.
/// - Throws: Invalid locally authored catalogue.
private func filterSongs() throws -> [Song] {
    let songs = try JSONDecoder().decode(SongsResponse.self, from: Data("""
    {"count":3,"songs":[
      {"songId":"pulse","title":"Pulse","artist":"Fixture",
       "difficulty":{"guitar":4,"drums":3}},
      {"songId":"orbit","title":"Orbit","artist":"Fixture",
       "difficulty":{"guitar":3,"drums":2}},
      {"songId":"no-drums","title":"No Drums","artist":"Fixture",
       "difficulty":{"guitar":2,"drums":99}}
    ]}
    """.utf8))
    try songs.validate()
    return songs.songs
}

/// Decode original compact score flags rather than hand-building model values.
///
/// - Returns: Lead FC/zero and one non-FC Drums row.
/// - Throws: Invalid locally authored selected-player wire data.
private func filterScores() throws -> [String: [Instrument: PlayerScore]] {
    let player = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-filter","displayName":"Fixture Filter","totalScores":4,
     "scores":[
       {"si":"pulse","ins":"01","sc":100,"fc":true},
       {"si":"orbit","ins":"01","sc":0,"fc":true},
       {"si":"pulse","ins":"04","sc":80,"fc":false},
       {"si":"no-drums","ins":"01","sc":60,"fc":false}
     ]}
    """.utf8))
    return try player.scoreIndex(requestedAccountId: "fixture-filter")
}

/// A chart's score and FC checks combine, while different chart checks OR together.
@Test func playerScoreFiltersMatchSourceMultiChartAndZeroFlagRules() throws {
    let songs = try filterSongs()
    let scores = try filterScores()
    let visible: Set<Instrument> = [.lead, .drums]
    let hasDrums = SongPlayerScoreFilter(hasScores: [.drums])
    #expect(try hasDrums.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible,
        selectedInstrument: nil
    ).map(\.songId) == ["pulse"])
    let missingDrums = SongPlayerScoreFilter(missingScores: [.drums])
    #expect(try missingDrums.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible,
        selectedInstrument: nil
    ).map(\.songId) == ["orbit"])
    let hasCombo = SongPlayerScoreFilter(hasFCs: [.lead])
    #expect(try hasCombo.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible,
        selectedInstrument: nil
    ).map(\.songId) == ["pulse", "orbit"])
    let scoredCombo = SongPlayerScoreFilter(hasScores: [.lead], hasFCs: [.lead])
    #expect(try scoredCombo.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible,
        selectedInstrument: nil
    ).map(\.songId) == ["pulse"])
    let mixed = SongPlayerScoreFilter(
        missingScores: [.drums], hasScores: [.lead], hasFCs: [.lead]
    )
    #expect(try mixed.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible,
        selectedInstrument: nil
    ).map(\.songId) == ["pulse", "orbit"])
    #expect(try mixed.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible,
        selectedInstrument: .drums
    ).map(\.songId) == ["orbit"])
    #expect(try SongPlayerScoreFilter(missingFCs: [.drums]).filtered(
        songs, scoresBySong: scores, visibleInstruments: visible,
        selectedInstrument: nil
    ).map(\.songId) == ["pulse", "orbit"])
    #expect(try SongPlayerScoreFilter(
        missingScores: [.lead], hasScores: [.lead]
    ).filtered(
        songs, scoresBySong: scores, visibleInstruments: visible,
        selectedInstrument: .lead
    ).map(\.songId) == ["pulse", "orbit", "no-drums"])
}

/// Hidden or irrelevant charts cannot suppress rows or fabricate missing-score data.
@Test func playerScoreFiltersFailClosedAndRespectVisibility() throws {
    let songs = try filterSongs()
    let scores = try filterScores()
    let filter = SongPlayerScoreFilter(missingScores: [.drums])
    #expect(filter.isActive)
    #expect(!filter.scoped(to: [.lead]).isActive)
    #expect(try filter.filtered(
        songs, scoresBySong: nil, visibleInstruments: [.lead],
        selectedInstrument: nil
    ) == songs)
    #expect(try filter.filtered(
        songs, scoresBySong: nil, visibleInstruments: [.lead, .drums],
        selectedInstrument: .lead
    ) == songs)
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try filter.filtered(
            songs, scoresBySong: nil, visibleInstruments: [.lead, .drums],
            selectedInstrument: nil
        )
    }
    #expect(try filter.filtered(
        songs, scoresBySong: [:], visibleInstruments: [.lead, .drums],
        selectedInstrument: nil
    ).map(\.songId) == ["pulse", "orbit"])
    #expect(try SongPlayerScoreFilter().filtered(
        songs, scoresBySong: nil, visibleInstruments: [.lead, .drums],
        selectedInstrument: nil
    ) == songs)
    #expect(try filter.filtered(
        songs, scoresBySong: scores, visibleInstruments: [.lead, .drums],
        selectedInstrument: nil
    ).map(\.songId) == ["orbit"])
}

/// Global switches retain hidden choices and a persisted preference has stable wire bytes.
@Test func playerScoreFiltersGlobalDraftAndPersistenceStayTyped() throws {
    let visible: Set<Instrument> = [.lead, .drums]
    let hidden: Set<Instrument> = [.bass]
    let initial = SongPlayerScoreFilter(hasFCs: hidden)
    #expect(!initial.allVisible(.hasFCs, visibleInstruments: visible))
    let all = initial.settingAll(.hasFCs, visibleInstruments: visible, enabled: true)
    #expect(all.allVisible(.hasFCs, visibleInstruments: visible))
    #expect(all.hasFCs == [.lead, .bass, .drums])
    let partial = all.setting(.hasFCs, for: .drums, enabled: false)
    #expect(!partial.allVisible(.hasFCs, visibleInstruments: visible))
    #expect(partial.contains(.hasFCs, for: .lead))
    let cleared = partial.settingAll(.hasFCs, visibleInstruments: visible, enabled: false)
    #expect(cleared.hasFCs == hidden)
    #expect(!SongPlayerScoreFilter().allVisible(.hasScores, visibleInstruments: []))

    let encoded = try all.encoded()
    #expect(try SongPlayerScoreFilter.decodeSaved(encoded) == all)
    #expect(String(decoding: encoded, as: UTF8.self).contains(
        #""hasFCs":["Solo_Guitar","Solo_Bass","Solo_Drums"]"#
    ))
    #expect(try SongPlayerScoreFilter().encoded().isEmpty)
    #expect(try SongPlayerScoreFilter.decodeSaved(Data()) == SongPlayerScoreFilter())
    for invalid in [
        Data(#"{"missingScores":[],"hasScores":["Solo_FAKE"],"missingFCs":[],"hasFCs":[]}"#.utf8),
        Data(#"{"missingScores":[],"hasScores":[],"missingFCs":[],"hasFCs":["Solo_Guitar","Solo_Guitar"]}"#.utf8),
        Data(#"{"missingScores":1,"hasScores":[],"missingFCs":[],"hasFCs":[]}"#.utf8),
        Data(repeating: 0, count: 4_097),
    ] {
        #expect(throws: FestivalAPIError.invalidSongFilter) {
            try SongPlayerScoreFilter.decodeSaved(invalid)
        }
    }
}
