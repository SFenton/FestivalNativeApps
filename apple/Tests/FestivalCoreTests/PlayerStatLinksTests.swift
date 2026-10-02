import Foundation
import Testing
@testable import FestivalCore

// MARK: - Songs presets

/// Saved Songs state with checks on two charts, General filters on and a non-default sort.
private func busySavedState() -> SongsSavedState {
    SongsSavedState(
        instrument: .drums, sortMode: .shop, sortAscending: false,
        generalFilter: busyGeneralFilter,
        playerFilter: SongPlayerScoreFilter(
            missingScores: [.lead], hasScores: [.bass], missingFCs: [.lead], hasFCs: [.drums]
        )
    )
}

private let busyGeneralFilter = SongGeneralFilter(
    excludedDecades: [1970], shop: .availableOnly, doubleBassUnsupported: false
)

@Test func overallPresetResetsEverythingAndChecksEveryVisibleChart() {
    let visible: Set<Instrument> = [.lead, .bass, .drums]
    let played = SongsFilterPreset.overall(.hasScores, visible: visible)
        .applied(to: busySavedState(), visibleInstruments: visible)
    // Web `songsPlayedUpdater`: `defaultSongFilters()` + hasScores on every visible key,
    // no instrument, Title ascending.
    #expect(played == SongsSavedState(playerFilter: SongPlayerScoreFilter(hasScores: visible)))

    let combos = SongsFilterPreset.overall(.hasFCs, visible: visible)
        .applied(to: busySavedState(), visibleInstruments: visible)
    #expect(combos.playerFilter == SongPlayerScoreFilter(hasFCs: visible))
    #expect(combos.instrument == nil && combos.sortMode == .title && combos.sortAscending)
    #expect(combos.generalFilter == SongGeneralFilter())
}

@Test func overallPresetNeverChecksAChartHiddenSinceTheTileWasBuilt() {
    let preset = SongsFilterPreset.overall(.hasScores, visible: [.lead, .bass])
    let saved = preset.applied(to: SongsSavedState(), visibleInstruments: [.lead])
    #expect(saved.playerFilter == SongPlayerScoreFilter(hasScores: [.lead]))
}

@Test func instrumentPresetCleansOnlyItsChartAndKeepsShopAndOtherCharts() {
    let visible: Set<Instrument> = [.lead, .bass, .drums]
    let saved = SongsFilterPreset.instrument(.hasFCs, .lead)
        .applied(to: busySavedState(), visibleInstruments: visible)
    // Web `cleanFilters` + `instFCsUpdater`: Lead's four checks cleared then hasFCs set;
    // Bass/Drums checks and the General filters kept; Lead becomes the Songs instrument.
    #expect(saved.playerFilter == SongPlayerScoreFilter(hasScores: [.bass], hasFCs: [.lead, .drums]))
    #expect(saved.instrument == .lead)
    #expect(saved.generalFilter == busyGeneralFilter)
    // Web `instFCsUpdater`: Score ascending.
    #expect(saved.sortMode == .score && saved.sortAscending)
}

@Test func instrumentPresetForAHiddenChartShowsAllInstrumentsAndSavesNoHiddenCheck() {
    let saved = SongsFilterPreset.instrument(.hasScores, .proBass)
        .applied(to: busySavedState(), visibleInstruments: [.lead, .bass])
    #expect(saved.instrument == nil)
    // Saved checks on other charts (hidden Drums included) are kept, as the filter
    // sheet keeps them; the hidden Pro Bass gets no new check.
    #expect(saved.playerFilter == SongPlayerScoreFilter(
        missingScores: [.lead], hasScores: [.bass], missingFCs: [.lead], hasFCs: [.drums]
    ))
    #expect(SongsFilterPreset.instrument(.hasScores, .proBass).instrument == .proBass)
    #expect(SongsFilterPreset.overall(.hasScores, visible: [.lead]).instrument == nil)
}

// MARK: - Link table

/// Decode a compact profile with one ranked Lead score and an unranked Drums score.
private func linkProfile() throws -> PlayerProfileResponse {
    try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-links","displayName":"Fixture Links","totalScores":3,
     "scores":[
       {"si":"pulse","ins":"01","sc":100,"fc":true,"st":6,"rk":7,"te":50},
       {"si":"orbit","ins":"01","sc":90,"fc":false,"st":5,"rk":3,"te":50},
       {"si":"pulse","ins":"04","sc":80,"fc":false,"st":4}
     ]}
    """.utf8))
}

@Test func linkTableMatchesTheWebTargets() throws {
    let profile = try linkProfile()
    let visible: Set<Instrument> = [.lead, .drums]
    #expect(PlayerStatLinks.overallSongsPlayed(visible: visible) == .songs(.overall(.hasScores, visible: visible)))
    #expect(PlayerStatLinks.overallFullCombos(visible: visible) == .songs(.overall(.hasFCs, visible: visible)))
    let overall = profile.overallStats(visibleInstruments: visible)
    #expect(PlayerStatLinks.overallBestRank(overall) == .songDetail(songId: "orbit", instrument: .lead))

    #expect(PlayerStatLinks.instrumentSongsPlayed(.lead) == .songs(.instrument(.hasScores, .lead)))
    #expect(PlayerStatLinks.instrumentFullCombos(.lead) == .songs(.instrument(.hasFCs, .lead)))
    #expect(PlayerStatLinks.instrumentBestRank(profile.instrumentStats(.lead)) == .songDetail(songId: "orbit", instrument: .lead))
    // No ranked Drums score: Best Rank stays a plain tile.
    #expect(PlayerStatLinks.instrumentBestRank(profile.instrumentStats(.drums)) == nil)

    #expect(PlayerStatLinks.globalRank(.lead, rank: 12) == .fullRankings(.lead, rankBy: "totalscore"))
    #expect(PlayerStatLinks.globalRank(.lead, rank: nil) == nil)
    #expect(PlayerStatLinks.globalRank(.lead, rank: 0) == nil)
}

@Test func overallBestRankNeedsASongAndItsChart() throws {
    let empty = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-empty","displayName":"Empty","totalScores":0,"scores":[]}
    """.utf8))
    #expect(PlayerStatLinks.overallBestRank(empty.overallStats(visibleInstruments: [.lead])) == nil)
}

@Test func onlySongsFiltersRequireTheViewedPlayerSelected() {
    #expect(PlayerStatLink.songs(.instrument(.hasScores, .lead)).requiresSelection)
    #expect(!PlayerStatLink.songDetail(songId: "pulse", instrument: .lead).requiresSelection)
    #expect(!PlayerStatLink.fullRankings(.lead, rankBy: "totalscore").requiresSelection)
}

// MARK: - Grid columns

@Test func statGridIsTwoColumnsOnIPhoneAndUpToFourWhenWider() {
    // iPhone 17 Pro card content: 402 - 32 page - 32 row insets = 338 pt.
    #expect(StatGridColumns.count(forWidth: 338) == 2)
    // iPhone SE / large Dynamic Type never collapses to one column.
    #expect(StatGridColumns.count(forWidth: 200) == 2)
    #expect(StatGridColumns.count(forWidth: 0) == 2)
    #expect(StatGridColumns.count(forWidth: .infinity) == 2)
    // Three at 3 × 140 + 2 × 8 = 436, four at 584, never more than four.
    #expect(StatGridColumns.count(forWidth: 435) == 2)
    #expect(StatGridColumns.count(forWidth: 436) == 3)
    #expect(StatGridColumns.count(forWidth: 584) == 4)
    #expect(StatGridColumns.count(forWidth: 1_200) == 4)
    #expect(StatGridColumns.count(forWidth: 300, minimumTileWidth: 90, spacing: 10) == 3)
}
