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

/// Web Over CHOpt Threshold: a chart check passes only for a score above the CHOpt
/// ceiling at the leeway, is inert while Filter Invalid Scores is off, and persists
/// without changing older saved bytes.
@Test func overThresholdChecksNeedFilterInvalidScoresAndAScoreAboveTheCeiling() throws {
    let songs = try JSONDecoder().decode(SongsResponse.self, from: Data("""
    {"count":2,"songs":[
      {"songId":"pulse","title":"Pulse","artist":"Fixture","difficulty":{"guitar":4,"drums":3},
       "maxScores":{"Solo_Guitar":100000,"Solo_Drums":100000}},
      {"songId":"orbit","title":"Orbit","artist":"Fixture","difficulty":{"guitar":3,"drums":2},
       "maxScores":{"Solo_Guitar":100000,"Solo_Drums":100000}}
    ]}
    """.utf8)).songs
    let player = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-over","totalScores":3,"scores":[
      {"si":"pulse","ins":"01","sc":102000,"fc":true},
      {"si":"orbit","ins":"01","sc":100500,"fc":true},
      {"si":"orbit","ins":"04","sc":105000,"fc":false}
    ]}
    """.utf8))
    let index = try player.scoreIndex(requestedAccountId: "fixture-over")
    let visible: Set<Instrument> = [.lead, .drums]
    let lead = SongPlayerScoreFilter().settingOverThreshold(.lead, enabled: true)
    #expect(lead.isActive)
    #expect(lead.containsOverThreshold(.lead))
    #expect(try lead.filtered(
        songs, scoresBySong: index, visibleInstruments: visible, selectedInstrument: nil,
        overThresholdLeeway: 1
    ).map(\.songId) == ["pulse"])
    #expect(try lead.filtered(
        songs, scoresBySong: index, visibleInstruments: visible, selectedInstrument: nil,
        overThresholdLeeway: 3
    ).isEmpty)
    #expect(try lead.filtered(
        songs, scoresBySong: index, visibleInstruments: visible, selectedInstrument: nil
    ).map(\.songId) == ["pulse", "orbit"])
    let fcAndOver = lead.setting(.hasFCs, for: .lead, enabled: true)
    #expect(try fcAndOver.filtered(
        songs, scoresBySong: index, visibleInstruments: visible, selectedInstrument: nil,
        overThresholdLeeway: 1
    ).map(\.songId) == ["pulse"])
    let all = SongPlayerScoreFilter().settingAllOverThreshold(visibleInstruments: visible, enabled: true)
    #expect(all.allVisibleOverThreshold(visibleInstruments: visible))
    #expect(try all.filtered(
        songs, scoresBySong: index, visibleInstruments: visible, selectedInstrument: .drums,
        overThresholdLeeway: 1
    ).map(\.songId) == ["orbit"])
    #expect(!all.clearingOverThreshold.isActive)
    #expect(all.scoped(to: [.lead]).overThreshold == [.lead])

    let encoded = try all.encoded()
    #expect(String(decoding: encoded, as: UTF8.self).contains(
        #""overThreshold":["Solo_Guitar","Solo_Drums"]"#
    ))
    #expect(try SongPlayerScoreFilter.decodeSaved(encoded) == all)
    #expect(!String(decoding: try SongPlayerScoreFilter(hasFCs: [.lead]).encoded(), as: UTF8.self)
        .contains("overThreshold"))
    #expect(throws: FestivalAPIError.invalidSongFilter) {
        try SongPlayerScoreFilter.decodeSaved(Data(
            #"{"missingScores":[],"hasScores":[],"missingFCs":[],"hasFCs":[],"overThreshold":["Solo_Guitar","Solo_Guitar"]}"#.utf8
        ))
    }
}

// MARK: - Filter Invalid Scores (#615)

/// Two charted songs with CHOpt maxima, so raw scores can be invalid.
///
/// - Returns: Valid Songs with Lead and Drums maxima of 100,000.
/// - Throws: Invalid locally authored catalogue.
private func invalidFilterSongs() throws -> [Song] {
    let songs = try JSONDecoder().decode(SongsResponse.self, from: Data("""
    {"count":2,"songs":[
      {"songId":"pulse","title":"Pulse","artist":"Fixture","difficulty":{"guitar":4,"drums":3},
       "maxScores":{"Solo_Guitar":100000,"Solo_Drums":100000}},
      {"songId":"orbit","title":"Orbit","artist":"Fixture","difficulty":{"guitar":3,"drums":2},
       "maxScores":{"Solo_Guitar":100000,"Solo_Drums":100000}}
    ]}
    """.utf8))
    try songs.validate()
    return songs.songs
}

/// Raw scores covering each effective-score outcome: Pulse Lead falls back to a valid
/// FC variant at 0.5%; Orbit Lead has no variant valid under 2% (raw valid from 4%);
/// Orbit Drums falls back to the legacy `validScore*` fields; Pulse Drums is valid.
///
/// - Returns: The raw selected-player index.
/// - Throws: Invalid locally authored selected-player wire data.
private func invalidFilterScores() throws -> [String: [Instrument: PlayerScore]] {
    let player = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-invalid-filter","totalScores":4,"scores":[
      {"si":"pulse","ins":"01","sc":120000,"fc":false,"st":6,"sn":9,"rk":1,"te":30,"ml":3,
       "vs":[{"sc":99500,"fc":true,"ml":0.5,"rt":[{"l":0.5,"r":9}]}]},
      {"si":"orbit","ins":"01","sc":130000,"fc":true,"st":6,"sn":8,"rk":1,"te":30,"ml":4,
       "vs":[{"sc":101500,"ml":2}]},
      {"si":"orbit","ins":"04","sc":150000,"fc":false,"st":6,"sn":7,"rk":1,"te":30,
       "validScore":98000,"validStars":4,"validIsFullCombo":true,"validRank":3,
       "validTotalEntries":30},
      {"si":"pulse","ins":"04","sc":90000,"fc":false,"st":5,"sn":7,"rk":4,"te":30}
    ]}
    """.utf8))
    return try player.scoreIndex(requestedAccountId: "fixture-invalid-filter")
}

/// Songs with Filter Invalid Scores on (#615): saved Score/FC, Over CHOpt Threshold
/// and season/percentile/stars checks apply to each chart's effective score (raw if
/// valid at the leeway, else the best valid fallback, else none), like the web's
/// `useFilteredSongs` over `SongsPage.effectiveScores`. The same saved filter re-applies
/// in place when the leeway changes or the setting turns off.
@Test func savedScoreFiltersApplyToEffectiveScoresAtEveryLeeway() throws {
    let songs = try invalidFilterSongs()
    let raw = try invalidFilterScores()
    let songsById = Dictionary(uniqueKeysWithValues: songs.map { ($0.songId, $0) })
    let visible: Set<Instrument> = [.lead, .drums]
    // SongsScreen: the effective index while the setting is on (nil leeway = off),
    // keeping raw scores on charts whose Over CHOpt Threshold check is on.
    func shown(
        _ filter: SongPlayerScoreFilter, leeway: Double?, instrument: Instrument? = nil
    ) throws -> [String] {
        let index = leeway.map {
            InvalidScorePolicy.resolve(
                index: raw, songsById: songsById, leeway: $0,
                overThreshold: filter.scoped(to: visible).overThreshold
            )
        } ?? raw
        return try filter.filtered(
            songs, scoresBySong: index, visibleInstruments: visible,
            selectedInstrument: instrument, overThresholdLeeway: leeway
        ).map(\.songId)
    }

    let hasLead = SongPlayerScoreFilter(hasScores: [.lead])
    #expect(try shown(hasLead, leeway: nil) == ["pulse", "orbit"])
    #expect(try shown(hasLead, leeway: 1) == ["pulse"])
    #expect(try shown(hasLead, leeway: 2) == ["pulse", "orbit"])
    #expect(try shown(hasLead, leeway: 5) == ["pulse", "orbit"])

    let missingLead = SongPlayerScoreFilter(missingScores: [.lead])
    #expect(try shown(missingLead, leeway: nil).isEmpty)
    #expect(try shown(missingLead, leeway: 1) == ["orbit"])

    // FCs follow the substituted score: the variant's and the legacy fields' FC flags.
    let fcLead = SongPlayerScoreFilter(hasFCs: [.lead])
    #expect(try shown(fcLead, leeway: nil) == ["orbit"])
    #expect(try shown(fcLead, leeway: 1) == ["pulse"])
    #expect(try shown(fcLead, leeway: 5) == ["orbit"])
    let fcDrums = SongPlayerScoreFilter(hasFCs: [.drums])
    #expect(try shown(fcDrums, leeway: nil).isEmpty)
    #expect(try shown(fcDrums, leeway: 1) == ["orbit"])
    let missingFCDrums = SongPlayerScoreFilter(missingFCs: [.drums])
    #expect(try shown(missingFCDrums, leeway: 1) == ["pulse"])

    // Over CHOpt Threshold keeps raw scores over max + leeway; inert while off.
    let overLead = SongPlayerScoreFilter().settingOverThreshold(.lead, enabled: true)
    #expect(try shown(overLead, leeway: 1) == ["pulse", "orbit"])
    #expect(try shown(overLead, leeway: 25) == ["orbit"])
    #expect(try shown(overLead, leeway: nil) == ["pulse", "orbit"])
    #expect(overLead.containsOverThreshold(.lead))

    // Season, percentile and stars buckets read the same effective score.
    let noSeasonLead = SongPlayerScoreFilter().settingExcluded(.season, [0])
    #expect(try shown(noSeasonLead, leeway: nil, instrument: .lead) == ["pulse", "orbit"])
    #expect(try shown(noSeasonLead, leeway: 1, instrument: .lead) == ["pulse"])
    #expect(SongStarsBucket.key(for: raw["orbit"]?[.drums]) == 6)
    let noGold = SongPlayerScoreFilter().settingStars(6, included: false)
    #expect(try shown(noGold, leeway: nil, instrument: .drums) == ["pulse"])
    #expect(try shown(noGold, leeway: 1, instrument: .drums) == ["pulse", "orbit"])
    // Raw Orbit Drums is rank 1 of 30 (top 4%); its legacy fallback is rank 3 (top 10%).
    let noTop4 = SongPlayerScoreFilter().settingPercentile(4, included: false)
    #expect(try shown(noTop4, leeway: nil, instrument: .drums) == ["pulse"])
    #expect(try shown(noTop4, leeway: 1, instrument: .drums) == ["pulse", "orbit"])
    let noTop10 = SongPlayerScoreFilter().settingPercentile(10, included: false)
    #expect(try shown(noTop10, leeway: 1, instrument: .drums) == ["pulse"])

    // The saved filter itself never changes with the setting or the leeway.
    let saved = hasLead.setting(.hasFCs, for: .drums, enabled: true)
        .settingOverThreshold(.lead, enabled: true)
    let bytes = try saved.encoded()
    for leeway in [nil, 1, 2, 5] as [Double?] { _ = try shown(saved, leeway: leeway) }
    #expect(try SongPlayerScoreFilter.decodeSaved(bytes) == saved)
    #expect(saved.isActive && !saved.clearingOverThreshold.overThreshold.contains(.lead))
}
