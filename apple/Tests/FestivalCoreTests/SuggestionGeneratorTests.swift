import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixture builders
//
// The generator's anti-repetition state (`sessionShownSongs`) is shared across every
// pipeline within one generator instance: once ANY pipeline selects a song this session,
// every other pipeline treats it as "stale" and may skip rather than reuse it. Categories
// with overlapping predicates (e.g. `near_fc_any` and `unfc_<instrument>` both match a
// six-star, non-full-combo run) race for the same songs, and "unplayed"-shaped pipelines
// (`unplayed_<instrument>`, `first_plays_mixed`) sweep up *any* song missing a chart. Real
// catalogues have thousands of songs, so this is never visible; fixtures need either (a)
// fully "inert" filler scores on every non-target chart so unplayed-shaped pipelines never
// see the song, and/or (b) enough redundant qualifying songs that a same-shaped competitor
// claiming its `take` worth still leaves the target pipeline something fresh.

/// Build one catalogue row with a unique default title/artist (so two bare calls never
/// accidentally collide with the "same name" family). All nine charts are "supported"
/// (difficulty 0).
private func fixtureSong(_ id: String, _ title: String? = nil, _ artist: String? = nil, year: Int? = nil) throws -> Song {
    var record: [String: Any] = [
        "songId": id, "title": title ?? "Song \(id)", "artist": artist ?? "Artist \(id)",
        "difficulty": [
            "guitar": 0, "bass": 0, "drums": 0, "vocals": 0, "proGuitar": 0,
            "proBass": 0, "proVocals": 0, "proCymbals": 0, "proDrums": 0,
        ],
    ]
    if let year { record["year"] = year }
    return try JSONDecoder().decode(Song.self, from: JSONSerialization.data(withJSONObject: record))
}

/// The single-bit hex code `PlayerInstrumentCode` expects for a solo chart.
private func hexCode(_ instrument: Instrument) -> String {
    let index = Instrument.allCases.firstIndex(of: instrument)!
    return String(format: "%02x", 1 << index)
}

/// Build one compact-wire score record. `accuracy` is the desired *decoded* value
/// (0...1,000,000); the wire field is scaled down by 1000 to match `PlayerScore`'s decoder.
private func fixtureScore(
    _ songId: String, _ instrument: Instrument, stars: Int, accuracy: Double,
    fullCombo: Bool = false, rank: Int? = nil, totalEntries: Int? = nil, season: Int? = nil
) -> [String: Any] {
    var record: [String: Any] = [
        "si": songId, "ins": hexCode(instrument), "sc": 1_000_000, "st": stars,
        "fc": fullCombo, "acc": accuracy / 1_000,
    ]
    if let rank { record["rk"] = rank }
    if let totalEntries { record["te"] = totalEntries }
    if let season { record["sn"] = season }
    return record
}

/// A fully "inert" score: gold-starred, full combo, unranked, unseasoned. It never
/// matches any ported predicate, so pipelines that scan for unplayed/stale/percentile
/// signal ignore it entirely.
private func fillerScore(_ songId: String, _ instrument: Instrument) -> [String: Any] {
    fixtureScore(songId, instrument, stars: 6, accuracy: 1_000_000, fullCombo: true)
}

/// One song where `instrument` carries the given score and every other chart is filled
/// with `fillerScore`, so only the caller's intended pipelines can pick this song up.
///
/// Every `signalSong` shares one fixed artist ("Signal Artist"): the generator's ungated
/// `variety_pack` pipeline (no `shouldEmit` gate) greedily claims any two songs by
/// different artists, so leaving the artist to vary (as `fixtureSong`'s own per-id
/// default does) would let it silently steal fixture songs before the pipeline under
/// test gets a turn. A shared artist keeps `variety_pack` (needs 2+ distinct artists)
/// out of the running; titles stay unique so "same name" pipelines don't fire either.
private func signalSong(
    _ id: String, _ instrument: Instrument, stars: Int, accuracy: Double,
    fullCombo: Bool = false, rank: Int? = nil, totalEntries: Int? = nil, season: Int? = nil,
    year: Int? = nil
) throws -> (song: Song, records: [[String: Any]]) {
    let song = try fixtureSong(id, "Signal \(id)", "Signal Artist", year: year)
    var records = [
        fixtureScore(
            id, instrument, stars: stars, accuracy: accuracy, fullCombo: fullCombo,
            rank: rank, totalEntries: totalEntries, season: season
        ),
    ]
    for other in Instrument.allCases where other != instrument {
        records.append(fillerScore(id, other))
    }
    return (song, records)
}

/// Build `count` `signalSong`s on the same instrument with the same score shape, indexed
/// `prefix0`, `prefix1`, … This concentrates redundancy on one chart deliberately: spreading
/// candidates across several instruments would instead create several independent
/// single-instrument competitor pipelines (`unfc_<X>`, `stale_<X>_N`, …), each capable of
/// claiming its own song regardless of the others — which drains a small fixture faster,
/// not slower. A single shared instrument means there is only one such competitor, and it
/// can claim at most one page (`fixedDisplayCount`) per turn, so enough redundancy here
/// reliably survives it.
private func signalSongs(
    prefix: String, count: Int, instrument: Instrument, stars: Int, accuracy: Double,
    fullCombo: Bool = false, rankStart: Int = 2, totalEntries: Int? = nil, season: Int? = nil,
    year: Int? = nil
) throws -> (songs: [Song], records: [[String: Any]]) {
    let built = try (0..<count).map { offset in
        try signalSong(
            "\(prefix)\(offset)", instrument, stars: stars, accuracy: accuracy, fullCombo: fullCombo,
            rank: totalEntries != nil ? rankStart + offset : nil, totalEntries: totalEntries,
            season: season, year: year
        )
    }
    return (built.map(\.song), built.flatMap(\.records))
}

/// Flatten several `signalSong` results into one (songs, records) fixture.
private func combine(_ built: [(song: Song, records: [[String: Any]])]) -> (songs: [Song], records: [[String: Any]]) {
    (built.map(\.song), built.flatMap(\.records))
}

/// Decode a batch of `fixtureScore` records into the session's `[songId: [Instrument: PlayerScore]]` shape.
private func scoreIndex(_ records: [[String: Any]]) throws -> [String: [Instrument: PlayerScore]] {
    guard !records.isEmpty else { return [:] }
    let data = try JSONSerialization.data(withJSONObject: records)
    let scores = try JSONDecoder().decode([PlayerScore].self, from: data)
    var index: [String: [Instrument: PlayerScore]] = [:]
    for score in scores { index[score.songId, default: [:]][score.instrument] = score }
    return index
}

/// One fresh, deterministic (non-skipping) generator over its own isolated fixture.
private func makeGenerator(
    songs: [Song], records: [[String: Any]] = [], currentSeason: Int = 0,
    fixedDisplayCount: Int = 2, seed: UInt32 = 7
) throws -> SuggestionGenerator {
    let generator = SuggestionGenerator(options: .init(
        seed: seed, disableSkipping: true, fixedDisplayCount: fixedDisplayCount, currentSeason: currentSeason
    ))
    generator.setSource(songs: songs, scoresIndex: try scoreIndex(records))
    return generator
}

/// Pull every category out of a small fixture in one page (small fixtures never need paging).
private func allCategories(_ generator: SuggestionGenerator) -> [SuggestionCategory] {
    generator.getNext(200)
}

// MARK: - RNG

@Test func seededRngIsDeterministicPerSeed() {
    var a = SeededSuggestionRng(seed: 42)
    var b = SeededSuggestionRng(seed: 42)
    var c = SeededSuggestionRng(seed: 43)
    let sequenceA = (0..<5).map { _ in a.nextDouble() }
    let sequenceB = (0..<5).map { _ in b.nextDouble() }
    let sequenceC = (0..<5).map { _ in c.nextDouble() }
    #expect(sequenceA == sequenceB)
    #expect(sequenceA != sequenceC)
    for value in sequenceA { #expect(value >= 0 && value < 1) }
}

@Test func seededRngNextIntStaysInRange() {
    var rng = SeededSuggestionRng(seed: 99)
    for _ in 0..<200 {
        let value = rng.nextInt(5)
        #expect((0..<5).contains(value))
    }
    #expect(rng.nextInt(0) == 0)
}

// MARK: - Near FC

@Test func nearFcAnyCollectsSixStarNonFullComboRunsAcrossInstruments() throws {
    // Single chart: its only competitor is `unfc_Solo_Guitar`, which can claim at most `take`.
    let fixture = try signalSongs(prefix: "nfa", count: 8, instrument: .lead, stars: 6, accuracy: 955_000)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "near_fc_any" })
    #expect(category.type == .nearFC)
    #expect(category.instrument == nil)
    #expect(category.songs.count == 2)
    #expect(category.songs.allSatisfy { $0.instrument != nil && $0.fullCombo == false })
}

@Test func nearFcRelaxedAcceptsFiveOrSixStarsAtNinetyTwoPercent() throws {
    // Six stars (not five) keeps this out of `almost_six_star` / `star_gains` / `more_stars`;
    // its only competitor is `unfc_<instrument>`, which can claim at most `take`.
    let fixture = try signalSongs(prefix: "nfr", count: 6, instrument: .bass, stars: 6, accuracy: 925_000)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "near_fc_relaxed" })
    #expect(category.songs.count == 2)
}

@Test(arguments: Instrument.allCases)
func unFcInstrumentIsScopedToOneChartWithNoPerSongInstrument(_ instrument: Instrument) throws {
    let built = try [
        signalSong("a", instrument, stars: 6, accuracy: 700_000),
        signalSong("b", instrument, stars: 6, accuracy: 750_000),
    ]
    let fixture = combine(built)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let key = "unfc_\(instrument.rawValue)"
    let category = try #require(allCategories(generator).first { $0.key == key })
    #expect(category.instrument == instrument)
    #expect(category.songs.count == 2)
    #expect(category.songs.allSatisfy { $0.instrument == nil })
}

@Test func sameNameNearFcGroupsDuplicateTitlesWithAQualifyingRun() throws {
    let a = try fixtureSong("a", "Echoes", "Artist One")
    let b = try fixtureSong("b", "Echoes", "Artist Two")
    let records = [
        fixtureScore("a", .proDrums, stars: 6, accuracy: 910_000),
        fixtureScore("b", .proDrums, stars: 1, accuracy: 400_000),
    ]
    let generator = try makeGenerator(songs: [a, b], records: records)
    let category = try #require(allCategories(generator).first { $0.key.hasPrefix("samename_nearfc_") })
    #expect(category.title.contains("Echoes"))
    #expect(category.type == .nearFC)
}

// MARK: - Star progress

@Test func almostSixStarsRequiresFiveStarsAtNinetyPercent() throws {
    // Five stars at 90%+ unavoidably also matches `star_gains` and `more_stars` (both
    // accept a five-star run); generous redundancy survives both claiming their `take`.
    let fixture = try signalSongs(prefix: "a6s", count: 8, instrument: .lead, stars: 5, accuracy: 905_000)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    #expect(allCategories(generator).contains { $0.key == "almost_six_star" })
}

@Test func starGainsAcceptsThreeToFiveStars() throws {
    // Three/four stars also matches `more_stars` (its only competitor here).
    let fixture = try signalSongs(prefix: "sg", count: 6, instrument: .lead, stars: 3, accuracy: 700_000)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    #expect(allCategories(generator).contains { $0.key == "star_gains" })
}

@Test func moreStarsAcceptsAnyPartialStarRun() throws {
    // One or two stars is isolated: too low for `star_gains` (needs 3+) or `almost_six_star`.
    let fixture = try signalSongs(prefix: "ms", count: 4, instrument: .lead, stars: 1, accuracy: 400_000)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    #expect(allCategories(generator).contains { $0.key == "more_stars" })
}

// MARK: - Unplayed

/// Totally unplayed songs sharing one artist (dodges `variety_pack`) so only the
/// unplayed-shaped pipelines (`unplayed_any`, `unplayed_<X>` for every X, `first_plays_mixed`,
/// `artist_unplayed_<artist>`) compete for them; each can claim only `take` per turn.
private func unplayedSongs(prefix: String, count: Int) throws -> [Song] {
    try (0..<count).map { try fixtureSong("\(prefix)\($0)", "Unplayed \(prefix)\($0)", "Unplayed Artist") }
}

@Test func unplayedAllOnlyIncludesSongsWithZeroScores() throws {
    let songs = try unplayedSongs(prefix: "u", count: 8)
    let generator = try makeGenerator(songs: songs)
    let category = try #require(allCategories(generator).first { $0.key == "unplayed_any" })
    #expect(category.type == .unplayed)
    #expect(category.songs.count == 2)
}

@Test(arguments: Instrument.allCases)
func unplayedInstrumentCoversEveryChart(_ instrument: Instrument) throws {
    // Every chart but `instrument` is filled with an inert score, so only
    // `unplayed_<instrument>` (and the always-eligible `first_plays_mixed`) see these songs.
    let built = try (0..<8).map { index -> (song: Song, records: [[String: Any]]) in
        let id = "u\(index)"
        let song = try fixtureSong(id, "Unplayed \(id)", "Unplayed Artist")
        let records = Instrument.allCases.filter { $0 != instrument }.map { fillerScore(id, $0) }
        return (song, records)
    }
    let fixture = combine(built)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let key = "unplayed_\(instrument.rawValue)"
    let category = try #require(allCategories(generator).first { $0.key == key })
    #expect(category.instrument == instrument)
}

@Test func firstPlaysMixedDrawsFromAnyUnplayedChart() throws {
    let songs = try unplayedSongs(prefix: "u", count: 4)
    let generator = try makeGenerator(songs: songs)
    let category = try #require(allCategories(generator).first { $0.key == "first_plays_mixed" })
    #expect(category.songs.allSatisfy { $0.instrument != nil })
}

// MARK: - Variety, artists, same name

@Test func varietyPackPicksDistinctArtists() throws {
    // Fully (inertly) scored so the ungated `first_plays_mixed` pipeline can't claim
    // these songs before `variety_pack` gets a turn.
    let ids = ["a", "b", "c"]
    let artists = ["Artist One", "Artist Two", "Artist Three"]
    let songs = try zip(ids, artists).map { id, artist in try fixtureSong(id, "Song \(id)", artist) }
    let records = ids.flatMap { id in Instrument.allCases.map { fillerScore(id, $0) } }
    let generator = try makeGenerator(songs: songs, records: records, fixedDisplayCount: 3)
    let category = try #require(allCategories(generator).first { $0.key == "variety_pack" })
    #expect(category.type == .varietyPack)
    let songArtists = Set(category.songs.map { $0.song.artist })
    #expect(songArtists.count == category.songs.count)
}

@Test func artistSamplerRotatingNeedsThreeSongsFromOneArtist() throws {
    let songs = try [
        fixtureSong("a", "One", "Prolific Artist"), fixtureSong("b", "Two", "Prolific Artist"),
        fixtureSong("c", "Three", "Prolific Artist"),
    ]
    let generator = try makeGenerator(songs: songs, fixedDisplayCount: 3)
    let category = try #require(allCategories(generator).first { $0.key.hasPrefix("artist_sampler_") })
    #expect(category.type == .artistEssentials)
    #expect(category.title.contains("Prolific Artist"))
}

@Test func artistFocusUnplayedGroupsUnplayedSongsByArtist() throws {
    let songs = try [fixtureSong("a", "One", "New Artist")]
    let generator = try makeGenerator(songs: songs, fixedDisplayCount: 1)
    let category = try #require(allCategories(generator).first { $0.key.hasPrefix("artist_unplayed_") })
    #expect(category.type == .artistDiscover)
    #expect(category.title == "Discover New Artist")
}

@Test func sameNameSetsGroupsDuplicateTitles() throws {
    let songs = try [fixtureSong("a", "Echoes", "Artist One"), fixtureSong("b", "Echoes", "Artist Two")]
    let generator = try makeGenerator(songs: songs)
    let category = try #require(allCategories(generator).first { $0.key.hasPrefix("samename_") && !$0.key.contains("nearfc") })
    #expect(category.type == .sameName)
    #expect(category.title.contains("Echoes"))
}

// MARK: - Almost elite / percentile push

@Test func almostEliteRequiresTopTwoToTopFivePercent() throws {
    // Bucket 2 (topPct in (1,2], i.e. rank 11...20 of 1000) unavoidably also matches
    // `pct_improve_2` and `pct_improve_<instrument>_2`; ten candidates outlast both.
    let fixture = try signalSongs(
        prefix: "ae", count: 10, instrument: .lead, stars: 4, accuracy: 800_000,
        rankStart: 11, totalEntries: 1_000
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "almost_elite" })
    #expect(category.type == .almostElite)
}

@Test(arguments: Instrument.allCases)
func almostEliteInstrumentIsScopedToOneChart(_ instrument: Instrument) throws {
    let fixture = try signalSongs(
        prefix: "aei", count: 18, instrument: instrument, stars: 4, accuracy: 800_000,
        rankStart: 11, totalEntries: 1_000
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let key = "almost_elite_\(instrument.rawValue)"
    let category = try #require(allCategories(generator).first { $0.key == key })
    #expect(category.instrument == instrument)
    #expect(category.songs.allSatisfy { $0.instrument == nil })
}

@Test func percentilePushFiresInTheLowerHalfOfABracket() throws {
    // Bucket 10 spans (5%, 10%]; near-next-bracket needs topPct <= 7.5, so rank 51...60
    // of 1000 (topPct 5.1...6.0) qualifies for both `pct_push` and `pct_improve_10`.
    let fixture = try signalSongs(
        prefix: "pp", count: 18, instrument: .lead, stars: 4, accuracy: 800_000,
        rankStart: 51, totalEntries: 1_000
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    #expect(allCategories(generator).contains { $0.key == "pct_push" })
}

@Test(arguments: Instrument.allCases)
func percentilePushInstrumentIsScopedToOneChart(_ instrument: Instrument) throws {
    let fixture = try signalSongs(
        prefix: "ppi", count: 10, instrument: instrument, stars: 4, accuracy: 800_000,
        rankStart: 51, totalEntries: 1_000
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let key = "pct_push_\(instrument.rawValue)"
    let category = try #require(allCategories(generator).first { $0.key == key })
    #expect(category.instrument == instrument)
}

// MARK: - Stale songs

@Test(arguments: [1, 2, 3, 4, 5])
func staleGlobalMatchesSeasonGap(_ minSeasonsAgo: Int) throws {
    // Concentrated on one instrument: `stale_<instrument>_<N>` is the only competitor,
    // and eight candidates outlast it claiming its own `take`.
    let currentSeason = 10
    let fixture = try signalSongs(
        prefix: "sg\(minSeasonsAgo)", count: 14, instrument: .lead, stars: 2, accuracy: 500_000,
        season: currentSeason - minSeasonsAgo
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records, currentSeason: currentSeason)
    let suffix = minSeasonsAgo >= 5 ? "5plus" : "\(minSeasonsAgo)"
    #expect(allCategories(generator).contains { $0.key == "stale_global_\(suffix)" })
}

@Test func staleGlobalRequiresAPositiveCurrentSeason() throws {
    let built = try [signalSong("a", .lead, stars: 2, accuracy: 500_000, season: 1)]
    let fixture = combine(built)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records, currentSeason: 0, fixedDisplayCount: 1)
    #expect(!allCategories(generator).contains { $0.key.hasPrefix("stale_") })
}

@Test(arguments: Instrument.allCases)
func staleInstrumentCoversEveryChart(_ instrument: Instrument) throws {
    // `stale_global_5plus` is the only competitor (same season gap, all instruments);
    // eight candidates outlast it claiming its own `take`.
    let fixture = try signalSongs(
        prefix: "si", count: 24, instrument: instrument, stars: 2, accuracy: 500_000, season: 1
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records, currentSeason: 6)
    let key = "stale_\(instrument.rawValue)_5plus"
    let category = try #require(allCategories(generator).first { $0.key == key })
    #expect(category.instrument == instrument)
    #expect(category.songs.allSatisfy { $0.instrument != nil })
}

// MARK: - Percentile improvement

/// Songs where `.lead` and `.bass` land in the same percentile bucket (needed for
/// `same_pct_improve` / `same_pct_<bucket>`), sharing one artist. `pct_improve_<bucket>`
/// and both `pct_improve_<lead/bass>_<bucket>` inevitably compete for the same songs
/// (by construction, every candidate here is also a valid entry for all three); enough
/// redundancy at a modest `take` survives all three claiming their share.
private func samePercentileBucketSongs(prefix: String, count: Int, rank: Int, totalEntries: Int) throws -> (songs: [Song], records: [[String: Any]]) {
    let built = try (0..<count).map { index -> (song: Song, records: [[String: Any]]) in
        let id = "\(prefix)\(index)"
        let song = try fixtureSong(id, "Signal \(id)", "Signal Artist")
        let records = [
            fixtureScore(id, .lead, stars: 2, accuracy: 600_000, rank: rank, totalEntries: totalEntries),
            fixtureScore(id, .bass, stars: 2, accuracy: 600_000, rank: rank, totalEntries: totalEntries),
        ] + Instrument.allCases.filter { $0 != .lead && $0 != .bass }.map { fillerScore(id, $0) }
        return (song, records)
    }
    return (built.map(\.song), built.flatMap(\.records))
}

@Test func samePercentileBucketNeedsTwoInstrumentsInOneNonEliteBucket() throws {
    // Bucket 10 (not 2...5) avoids competing directly with `almost_elite` too.
    let fixture = try samePercentileBucketSongs(prefix: "spb", count: 14, rank: 51, totalEntries: 1_000)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "same_pct_improve" })
    #expect(!category.songs.isEmpty)
    #expect(category.songs.allSatisfy { $0.percentileDisplay == "Top 10%" })
}

@Test func samePercentileBucketSpecificTargetsOneBucket() throws {
    let fixture = try samePercentileBucketSongs(prefix: "spbs", count: 24, rank: 51, totalEntries: 1_000)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "same_pct_10" })
    #expect(category.title == "Break Into Top 5%")
}

@Test func percentileImproveBucketMatchesAnyInstrumentAtThatBucket() throws {
    let fixture = try signalSongs(
        prefix: "pib", count: 10, instrument: .lead, stars: 2, accuracy: 600_000,
        rankStart: 51, totalEntries: 1_000
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    #expect(allCategories(generator).contains { $0.key == "pct_improve_10" })
}

@Test(arguments: Instrument.allCases)
func percentileImproveInstrumentIsScopedToOneChart(_ instrument: Instrument) throws {
    let fixture = try signalSongs(
        prefix: "pii", count: 10, instrument: instrument, stars: 2, accuracy: 600_000,
        rankStart: 51, totalEntries: 1_000
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let key = "pct_improve_\(instrument.rawValue)_10"
    let category = try #require(allCategories(generator).first { $0.key == key })
    #expect(category.instrument == instrument)
}

@Test(arguments: Instrument.allCases)
func improveInstrumentRankingsNeedsThreeDistinctBuckets(_ instrument: Instrument) throws {
    // Three buckets, several songs each: `pct_improve_<instrument>_<bucket>` competes
    // for every song in its own bucket, so each bucket needs more than one `take` worth.
    let buckets: [(rank: Int, total: Int)] = [(11, 1_000), (151, 1_000), (401, 1_000)] // buckets 2, 20, 50
    var songs: [Song] = []
    var records: [[String: Any]] = []
    for (bucketIndex, bucket) in buckets.enumerated() {
        for offset in 0..<28 {
            let id = "iir\(instrument.rawValue)_\(bucketIndex)_\(offset)"
            songs.append(try fixtureSong(id, "Signal \(id)", "Signal Artist"))
            records.append(fixtureScore(
                id, instrument, stars: 2, accuracy: 600_000,
                rank: bucket.rank + offset, totalEntries: bucket.total
            ))
            for other in Instrument.allCases where other != instrument {
                records.append(fillerScore(id, other))
            }
        }
    }
    let generator = try makeGenerator(songs: songs, records: records, fixedDisplayCount: 3)
    let key = "improve_rankings_\(instrument.rawValue)"
    let category = try #require(allCategories(generator).first { $0.key == key })
    #expect(category.songs.count == 3)
}

@Test func improveInstrumentRankingsNeedsAtLeastThreeBuckets() throws {
    let built = try [
        signalSong("a", .lead, stars: 2, accuracy: 600_000, rank: 2, totalEntries: 100),
        signalSong("b", .lead, stars: 2, accuracy: 600_000, rank: 20, totalEntries: 100),
    ]
    let fixture = combine(built)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    #expect(!allCategories(generator).contains { $0.key == "improve_rankings_Solo_Guitar" })
}

// MARK: - Decade variants

@Test func decadeVariantsRetitleAndStayWithinOneDecade() throws {
    // All 1980s candidates on one chart: only `unfc_Solo_Guitar` competes for them, and
    // twelve candidates outlast it claiming its own `take`. A single 1990s candidate
    // proves the decade split actually excludes other decades.
    let eighties = try signalSongs(
        prefix: "d85_", count: 24, instrument: .lead, stars: 6, accuracy: 955_000, year: 1985
    )
    let nineties = try signalSong("d95", .lead, stars: 6, accuracy: 960_000, year: 1995)
    let generator = try makeGenerator(
        songs: eighties.songs + [nineties.song], records: eighties.records + nineties.records
    )
    let categories = allCategories(generator)
    let decade = try #require(categories.first { $0.key == "near_fc_any_decade_80" })
    #expect(decade.title == "FC These Next! (80's)")
    #expect(decade.songs.count == 2)
    #expect(Set(decade.songs.map { $0.song.year }) == [1985])
}

@Test func unfcInstrumentDecadeVariantUsesInstrumentTitle() throws {
    // Several 1980s lead candidates so the non-decade `unfc_Solo_Guitar` pipeline
    // claiming its own `take` first still leaves the decade variant a same-decade pair.
    let fixture = try signalSongs(
        prefix: "ud85_", count: 24, instrument: .lead, stars: 6, accuracy: 700_000, year: 1985
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "unfc_Solo_Guitar_decade_80" })
    #expect(category.title == "Close Lead FCs (80's)")
    #expect(category.instrument == .lead)
}

@Test func unplayedAnyDecadeVariantUsesDecadeDescription() throws {
    // Extra redundancy: `unplayed_any` and `first_plays_mixed` both claim from this same
    // pool first, so the decade variant needs same-decade pairs left over afterwards.
    let songs = try (0..<24).map {
        try fixtureSong("u\($0)", "Unplayed u\($0)", "Unplayed Artist", year: 1985)
    }
    let generator = try makeGenerator(songs: songs)
    let category = try #require(allCategories(generator).first { $0.key == "unplayed_any_decade_80" })
    #expect(category.description == "Unplayed songs from the 80's.")
}

// MARK: - Session state across calls

@Test func getNextNeverRepeatsACategoryKeyWithinASession() throws {
    let songs = try [fixtureSong("a"), fixtureSong("b")]
    let generator = try makeGenerator(songs: songs)
    let first = generator.getNext(1)
    let rest = generator.getNext(200)
    #expect(Set(first.map(\.key)).isDisjoint(with: Set(rest.map(\.key))))
}

@Test func getNextEventuallyExhaustsThePipelineForAFixedSource() throws {
    let songs = try [fixtureSong("a"), fixtureSong("b")]
    let generator = try makeGenerator(songs: songs)
    _ = generator.getNext(1_000)
    #expect(generator.getNext(10).isEmpty)
}

@Test func resetForEndlessAllowsCategoriesToReappear() throws {
    let songs = try [fixtureSong("a"), fixtureSong("b")]
    let generator = try makeGenerator(songs: songs)
    let firstPass = generator.getNext(1_000)
    #expect(!firstPass.isEmpty)
    #expect(generator.getNext(10).isEmpty)

    generator.resetForEndless()
    let secondPass = generator.getNext(1_000)
    #expect(!secondPass.isEmpty)
    let overlap = Set(firstPass.map(\.key)).intersection(secondPass.map(\.key))
    #expect(!overlap.isEmpty)
}

@Test func emptySourceProducesNoCategories() {
    let generator = SuggestionGenerator(options: .init(disableSkipping: true))
    generator.setSource(songs: [], scoresIndex: [:])
    #expect(generator.getNext(50).isEmpty)
}

@Test func customRngInitializerIsUsable() throws {
    let songs = try [fixtureSong("a")]
    let generator = SuggestionGenerator(rng: SeededSuggestionRng(seed: 3), options: .init(disableSkipping: true))
    generator.setSource(songs: songs, scoresIndex: [:])
    #expect(!generator.getNext(50).isEmpty)
}

// MARK: - Remaining decade variant titles

@Test func moreStarsDecadeVariantSharesThePushToGoldTitle() throws {
    // One star: isolated from `star_gains` (needs 3+) and `almost_six_star` (needs exactly 5).
    let fixture = try signalSongs(
        prefix: "msd", count: 12, instrument: .lead, stars: 1, accuracy: 400_000, year: 1985
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "more_stars_decade_80" })
    #expect(category.title == "Push 80's to Gold")
}

@Test func starGainsDecadeVariantRetitlesForThatDecade() throws {
    let fixture = try signalSongs(
        prefix: "sgd", count: 12, instrument: .lead, stars: 3, accuracy: 700_000, year: 1985
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "star_gains_decade_80" })
    #expect(category.title == "Easy Star Gains (80's)")
}

@Test func firstPlaysMixedDecadeVariantStaysWithinOneDecade() throws {
    // Only `.lead` is unplayed (every other chart is inertly filled), so only
    // `unplayed_Solo_Guitar` and the ungated `first_plays_mixed`/`artist_sampler_*`
    // compete for these songs — not the whole "totally unplayed" pipeline army
    // (`unplayed_any` plus every other `unplayed_<X>`) that a zero-score fixture invites.
    let built = try (0..<20).map { index -> (song: Song, records: [[String: Any]]) in
        let id = "fpm\(index)"
        let song = try fixtureSong(id, "Signal \(id)", "Signal Artist", year: 1985)
        let records = Instrument.allCases.filter { $0 != .lead }.map { fillerScore(id, $0) }
        return (song, records)
    }
    let fixture = combine(built)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "first_plays_mixed_decade_80" })
    #expect(category.title == "First Plays (Mixed 80's)")
}

@Test func almostEliteDecadeVariantRetitlesForThatDecade() throws {
    let fixture = try signalSongs(
        prefix: "aed", count: 32, instrument: .lead, stars: 4, accuracy: 800_000,
        rankStart: 11, totalEntries: 1_000, year: 1985
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "almost_elite_decade_80" })
    #expect(category.title == "Almost Elite (80's)")
    #expect(category.description.contains("80's"))
}

@Test func almostEliteInstrumentDecadeVariantRetitlesForThatDecade() throws {
    let fixture = try signalSongs(
        prefix: "aeid", count: 20, instrument: .bass, stars: 4, accuracy: 800_000,
        rankStart: 11, totalEntries: 1_000, year: 1985
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "almost_elite_Solo_Bass_decade_80" })
    #expect(category.title == "Almost Elite on Bass (80's)")
    #expect(category.description.contains("Bass"))
}

@Test func percentilePushDecadeVariantRetitlesForThatDecade() throws {
    let fixture = try signalSongs(
        prefix: "ppd", count: 20, instrument: .lead, stars: 4, accuracy: 800_000,
        rankStart: 51, totalEntries: 1_000, year: 1985
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "pct_push_decade_80" })
    #expect(category.title == "Percentile Push (80's)")
}

@Test func percentilePushInstrumentDecadeVariantRetitlesForThatDecade() throws {
    let fixture = try signalSongs(
        prefix: "ppid", count: 20, instrument: .drums, stars: 4, accuracy: 800_000,
        rankStart: 51, totalEntries: 1_000, year: 1985
    )
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records)
    let category = try #require(allCategories(generator).first { $0.key == "pct_push_Solo_Drums_decade_80" })
    #expect(category.title == "Percentile Push: Drums (80's)")
}

// MARK: - Probability gate and history-reset edge cases

/// A scripted RNG that always rolls "high" (never below any emit probability) so
/// `shouldEmit`'s ordinary probability roll always skips, exercising the skip-streak
/// force-emit path deterministically. `nextInt` is a fixed no-op shuffle.
private struct AlwaysSkipRng: SuggestionRng {
    mutating func nextDouble() -> Double { 0.999 }
    mutating func nextInt(_ maxExclusive: Int) -> Int { 0 }
}

@Test func shouldEmitForcesEmitAfterTwoConsecutiveSkips() throws {
    let fixture = try signalSongs(prefix: "fe", count: 2, instrument: .lead, stars: 6, accuracy: 700_000)
    let generator = SuggestionGenerator(
        rng: AlwaysSkipRng(), options: .init(disableSkipping: false, fixedDisplayCount: 2)
    )
    generator.setSource(songs: fixture.songs, scoresIndex: try scoreIndex(fixture.records))

    #expect(!generator.getNext(1_000).contains { $0.key == "unfc_Solo_Guitar" })
    generator.resetForEndless()
    #expect(!generator.getNext(1_000).contains { $0.key == "unfc_Solo_Guitar" })
    generator.resetForEndless()
    // A third consecutive turn forces the emit regardless of the (still unfavorable) roll.
    #expect(generator.getNext(1_000).contains { $0.key == "unfc_Solo_Guitar" })
}

@Test func selectNewFirstClearsExhaustedCategoryHistoryOnReuse() throws {
    let fixture = try signalSongs(prefix: "hx", count: 2, instrument: .lead, stars: 6, accuracy: 700_000)
    let generator = try makeGenerator(songs: fixture.songs, records: fixture.records, fixedDisplayCount: 2)

    let first = generator.getNext(1_000).first { $0.key == "unfc_Solo_Guitar" }
    #expect(first?.songs.count == 2)

    generator.resetForEndless()
    // Both songs are already in `unfc_Solo_Guitar`'s own history; `selectNewFirst` clears
    // it rather than coming up empty a second time.
    let second = generator.getNext(1_000).first { $0.key == "unfc_Solo_Guitar" }
    #expect(second?.songs.count == 2)
}

// MARK: - Season fallback

@Test func suggestionSeasonFallsBackToHighestPlayerScoreSeason() throws {
    let scores = try scoreIndex([
        fixtureScore("a", .lead, stars: 1, accuracy: 500_000, season: 3),
        fixtureScore("a", .bass, stars: 1, accuracy: 500_000, season: 7),
    ])
    #expect(SuggestionSeason.effective(currentSeason: nil, scores: scores) == 7)
    #expect(SuggestionSeason.effective(currentSeason: 0, scores: scores) == 7)
    #expect(SuggestionSeason.effective(currentSeason: 9, scores: scores) == 9)
    #expect(SuggestionSeason.effective(currentSeason: nil, scores: [:]) == 0)
}



