import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

/// Four Lead-charted songs; `none` has no selected-player score.
private func bucketSongs() throws -> [Song] {
    let songs = try JSONDecoder().decode(SongsResponse.self, from: Data("""
    {"count":5,"songs":[
      {"songId":"gold","title":"Gold","artist":"Fixture","difficulty":{"guitar":4}},
      {"songId":"top1","title":"Top One","artist":"Fixture","difficulty":{"guitar":4}},
      {"songId":"mid","title":"Middle","artist":"Fixture","difficulty":{"guitar":3}},
      {"songId":"unranked","title":"Unranked","artist":"Fixture","difficulty":{"guitar":2}},
      {"songId":"none","title":"Absent","artist":"Fixture","difficulty":{"guitar":2}}
    ]}
    """.utf8))
    try songs.validate()
    return songs.songs
}

/// Compact Lead scores: gold stars at rank 30/1000 (Top 3%), five stars at 1/1000
/// (Top 1%), three stars at 400/1000 (Top 40%), and a scored row without a rank.
private func bucketScores() throws -> [String: [Instrument: PlayerScore]] {
    let player = try JSONDecoder().decode(PlayerProfileResponse.self, from: Data("""
    {"accountId":"fixture-buckets","displayName":"Fixture Buckets","totalScores":4,
     "scores":[
       {"si":"gold","ins":"01","sc":1250000,"fc":true,"st":6,"rk":30,"te":1000},
       {"si":"top1","ins":"01","sc":990000,"fc":false,"st":5,"rk":1,"te":1000},
       {"si":"mid","ins":"01","sc":420000,"fc":false,"st":3,"rk":400,"te":1000},
       {"si":"unranked","ins":"01","sc":45000,"fc":false,"st":1}
     ]}
    """.utf8))
    return try player.scoreIndex(requestedAccountId: "fixture-buckets")
}

private func leadScores(_ index: [String: [Instrument: PlayerScore]]) -> [String: PlayerScore] {
    index.compactMapValues { $0[.lead] }
}

// MARK: - Buckets

@Test func starAndPercentileBucketsMatchTheWeb() throws {
    let lead = leadScores(try bucketScores())
    #expect(SongStarsBucket.key(for: lead["gold"]) == 6)
    #expect(SongStarsBucket.key(for: nil) == 0)
    #expect(SongPercentileBucket.key(for: lead["gold"]) == 3)
    #expect(SongPercentileBucket.key(for: lead["top1"]) == 1)
    #expect(SongPercentileBucket.key(for: lead["mid"]) == 40)
    // A score without a rank, or no score at all, is "No Score" (web bucket 0).
    #expect(SongPercentileBucket.key(for: lead["unranked"]) == 0)
    #expect(SongPercentileBucket.key(for: nil) == 0)
    #expect(SongStarsBucket.label(6) == "5 gold stars" && SongStarsBucket.label(1) == "1 star")
    #expect(SongPercentileBucket.label(0) == "No Score" && SongPercentileBucket.label(5) == "Top 5%")
}

// MARK: - Filters

@Test func bucketFiltersApplyOnlyToTheSongsInstrument() throws {
    let songs = try bucketSongs()
    let scores = try bucketScores()
    let visible: Set<Instrument> = [.lead, .drums]
    let goldOnly = SongPlayerScoreFilter().showingOnlyStars(6)
    #expect(goldOnly.isActive && goldOnly.hasBucketChecks)
    #expect(try goldOnly.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible, selectedInstrument: .lead
    ).map(\.songId) == ["gold"])
    // Without one instrument the web skips bucket checks and keeps the saved choice.
    #expect(try goldOnly.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible, selectedInstrument: nil
    ).count == songs.count)
    // A hidden Songs instrument is not a bucket chart either.
    #expect(try goldOnly.filtered(
        songs, scoresBySong: scores, visibleInstruments: [.drums], selectedInstrument: .lead
    ).count == songs.count)

    let noScoreHidden = SongPlayerScoreFilter().settingPercentile(0, included: false)
    #expect(try noScoreHidden.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible, selectedInstrument: .lead
    ).map(\.songId) == ["gold", "top1", "mid"])
    let top1 = SongPlayerScoreFilter().showingOnlyPercentile(1)
    #expect(try top1.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible, selectedInstrument: .lead
    ).map(\.songId) == ["top1"])
}

@Test func bucketFiltersCombineWithChartChecksAndFailClosed() throws {
    let songs = try bucketSongs()
    let scores = try bucketScores()
    let visible: Set<Instrument> = [.lead]
    let filter = SongPlayerScoreFilter(hasScores: [.lead]).settingStars(5, included: false)
    #expect(try filter.filtered(
        songs, scoresBySong: scores, visibleInstruments: visible, selectedInstrument: .lead
    ).map(\.songId) == ["gold", "mid", "unranked"])
    // Active bucket checks without an available score index are not "no scores".
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try SongPlayerScoreFilter().showingOnlyStars(6).filtered(
            songs, scoresBySong: nil, visibleInstruments: visible, selectedInstrument: .lead
        )
    }
    // The web skips bucket checks for a player with no scores at all.
    #expect(try SongPlayerScoreFilter().showingOnlyStars(6).filtered(
        songs, scoresBySong: [:], visibleInstruments: visible, selectedInstrument: .lead
    ).count == songs.count)
}

@Test func bucketEditsSelectAllClearAllAndCleaning() {
    let cleared = SongPlayerScoreFilter().settingAllStars(included: false)
    #expect(SongStarsBucket.keys.allSatisfy { !cleared.includesStars($0) })
    #expect(!cleared.settingAllStars(included: true).isActive)
    let percent = SongPlayerScoreFilter().settingAllPercentiles(included: false)
    #expect(SongPercentileBucket.keys.allSatisfy { !percent.includesPercentile($0) })
    #expect(percent.settingAllPercentiles(included: true) == SongPlayerScoreFilter())
    // Unknown keys never enter the saved value.
    #expect(SongPlayerScoreFilter().settingStars(9, included: false) == SongPlayerScoreFilter())
    #expect(SongPlayerScoreFilter().settingPercentile(7, included: false) == SongPlayerScoreFilter())
    #expect(SongPlayerScoreFilter(excludedStars: [9], excludedPercentiles: [7]) == SongPlayerScoreFilter())
    let both = SongPlayerScoreFilter(hasFCs: [.lead]).showingOnlyStars(3).showingOnlyPercentile(10)
    #expect(both.clearingBuckets == SongPlayerScoreFilter(hasFCs: [.lead]))
    // Bucket choices are not per-chart: hiding charts keeps them.
    #expect(both.scoped(to: []).hasBucketChecks)
}

@Test func bucketFiltersPersistBoundedAndKeepOlderBytes() throws {
    let chartsOnly = SongPlayerScoreFilter(hasScores: [.lead])
    #expect(String(decoding: try chartsOnly.encoded(), as: UTF8.self)
            == #"{"hasFCs":[],"hasScores":["Solo_Guitar"],"missingFCs":[],"missingScores":[]}"#)
    let withBuckets = chartsOnly.showingOnlyStars(6).settingPercentile(0, included: false)
    let bytes = try withBuckets.encoded()
    #expect(try SongPlayerScoreFilter.decodeSaved(bytes) == withBuckets)
    #expect(String(decoding: bytes, as: UTF8.self).contains(#""excludedPercentiles":[0]"#))
    // A bucket-only filter is active, so it is saved.
    #expect(!(try SongPlayerScoreFilter().showingOnlyPercentile(5).encoded()).isEmpty)
    for corrupt in [
        #"{"hasFCs":[],"hasScores":[],"missingFCs":[],"missingScores":[],"excludedStars":[7]}"#,
        #"{"hasFCs":[],"hasScores":[],"missingFCs":[],"missingScores":[],"excludedStars":[1,1]}"#,
        #"{"hasFCs":[],"hasScores":[],"missingFCs":[],"missingScores":[],"excludedPercentiles":[6]}"#,
        #"{"hasFCs":[],"hasScores":[],"missingFCs":[],"missingScores":[],"excludedPercentiles":"5"}"#,
    ] {
        #expect(throws: FestivalAPIError.invalidSongFilter) {
            try SongPlayerScoreFilter.decodeSaved(Data(corrupt.utf8))
        }
    }
}

// MARK: - Sorts

@Test func playerSortsOrderLikeTheWebAndNeedAScoreIndex() throws {
    let songs = try bucketSongs()
    let lead = leadScores(try bucketScores())
    func order(_ mode: SongSortMode, _ ascending: Bool) throws -> [String] {
        try SongCatalogSort.sorted(songs, mode: mode, ascending: ascending, chartScores: lead).map(\.songId)
    }
    // Missing scores sort last ascending and (reversed, like `cmp * dir`) first descending.
    #expect(try order(.score, true) == ["unranked", "mid", "top1", "gold", "none"])
    #expect(try order(.score, false) == ["none", "gold", "top1", "mid", "unranked"])
    #expect(try order(.stars, true) == ["unranked", "mid", "top1", "gold", "none"])
    // Percentile: best rank fraction first; unranked scores after ranked ones.
    #expect(try order(.percentile, true) == ["top1", "gold", "mid", "unranked", "none"])
    #expect(throws: FestivalAPIError.invalidPlayerProfile) {
        try SongCatalogSort.sorted(songs, mode: .stars, ascending: true)
    }
    let playerModes = SongSortMode.playerChartModes.filter { $0.isPlayerChartMode }
    let cataloguePlayerModes = SongSortMode.catalogueModes.filter { $0.isPlayerChartMode }
    #expect(playerModes == [.score, .percentile, .stars])
    #expect(cataloguePlayerModes.isEmpty)
    #expect(SongSortMode.allCases.count
            == SongSortMode.catalogueModes.count + SongSortMode.playerChartModes.count)
    #expect(SongSectionIndex.sections(songs, mode: .score).isEmpty)
}

@Test func playerSortSectionsUseTheWebQuickLinkBuckets() throws {
    let songs = try bucketSongs()
    let lead = leadScores(try bucketScores())
    let byScore = try SongCatalogSort.sorted(songs, mode: .score, ascending: false, chartScores: lead)
    let scoreSections = SongCatalogSort.scoreSections(byScore, mode: .score, chartScores: lead)
    #expect(scoreSections.map(\.label) == ["No Score", "1.2M+", "950k+", "400k+", "0+"])
    let byStars = try SongCatalogSort.sorted(songs, mode: .stars, ascending: true, chartScores: lead)
    let starSections = SongCatalogSort.scoreSections(byStars, mode: .stars, chartScores: lead)
    #expect(starSections.map(\.label) == ["1★", "3★", "5★", "6★", "No Score"])
    #expect(starSections.map(\.spokenLabel) == ["1 star", "3 stars", "5 stars", "Gold stars", "No Score"])
    let byPercentile = try SongCatalogSort.sorted(songs, mode: .percentile, ascending: true, chartScores: lead)
    let percentileSections = SongCatalogSort.scoreSections(byPercentile, mode: .percentile, chartScores: lead)
    #expect(percentileSections.map(\.label) == ["1%", "3%", "40%", "No Rank"])
    #expect(percentileSections.last?.songs.map(\.songId) == ["unranked", "none"])
    #expect(SongCatalogSort.scoreSections(byScore, mode: .title, chartScores: lead).isEmpty)
    #expect(SongScoreSection.compactNumber(2_000_000) == "2M")
    #expect(SongScoreSection.compactNumber(500) == "500")
}

// MARK: - Profile presets

@Test func starAndPercentilePresetsMatchTheWebUpdaters() {
    let visible: Set<Instrument> = [.lead, .bass]
    let busy = SongsSavedState(
        instrument: .bass, sortMode: .shop, sortAscending: false, filterInShop: true,
        playerFilter: SongPlayerScoreFilter(hasScores: [.lead, .bass]).showingOnlyPercentile(50)
    )
    let stars = SongsFilterPreset.stars(.lead, starKey: 6).applied(to: busy, visibleInstruments: visible)
    #expect(stars.instrument == .lead && stars.sortMode == .stars && stars.sortAscending)
    #expect(stars.playerFilter == SongPlayerScoreFilter(hasScores: [.bass]).showingOnlyStars(6))
    #expect(stars.filterInShop)

    let percentile = SongsFilterPreset.percentile(.lead, scoredOnly: false).applied(to: busy, visibleInstruments: visible)
    #expect(percentile.sortMode == .percentile && percentile.playerFilter == SongPlayerScoreFilter(hasScores: [.bass]))
    let scored = SongsFilterPreset.percentile(.lead, scoredOnly: true).applied(to: busy, visibleInstruments: visible)
    #expect(scored.playerFilter == SongPlayerScoreFilter(hasScores: [.lead, .bass]))

    // A bucket row keeps the saved sort mode and makes it ascending.
    let bucket = SongsFilterPreset.percentileBucket(.lead, percentile: 5).applied(to: busy, visibleInstruments: visible)
    #expect(bucket.sortMode == .shop && bucket.sortAscending && bucket.instrument == .lead)
    #expect(bucket.playerFilter == SongPlayerScoreFilter(hasScores: [.bass]).showingOnlyPercentile(5))

    // A chart hidden since the tile was drawn: all instruments, Title, no new choice.
    let hidden = SongsFilterPreset.stars(.drums, starKey: 5).applied(to: busy, visibleInstruments: visible)
    #expect(hidden.instrument == nil && hidden.sortMode == .title && !hidden.playerFilter.hasBucketChecks)
    #expect(SongsFilterPreset.percentileBucket(.bass, percentile: 1).instrument == .bass)

    #expect(PlayerStatLinks.instrumentStars(.lead, starKey: 4) == .songs(.stars(.lead, starKey: 4)))
    #expect(PlayerStatLinks.instrumentPercentile(.lead) == .songs(.percentile(.lead, scoredOnly: false)))
    #expect(PlayerStatLinks.percentileBucket(.lead, percentile: 10)
            == .songs(.percentileBucket(.lead, percentile: 10)))
    #expect(PlayerStatLinks.instrumentStars(.lead, starKey: 4).requiresSelection)
}
