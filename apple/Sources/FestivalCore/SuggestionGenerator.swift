import Foundation

// MARK: - RNG

/// Pluggable random source so `SuggestionGenerator` tests can force deterministic output.
public protocol SuggestionRng {
    mutating func nextDouble() -> Double
    mutating func nextInt(_ maxExclusive: Int) -> Int
}

/// Mulberry32, the same small seeded PRNG the web generator uses, ported bit-for-bit
/// (32-bit wrapping arithmetic) so a fixed seed reproduces a fixed shuffle order.
public struct SeededSuggestionRng: SuggestionRng, Sendable {
    private var state: UInt32

    /// Start a new deterministic sequence.
    ///
    /// - Parameter seed: Any 32-bit value; the same seed always yields the same sequence.
    public init(seed: UInt32) { state = seed }

    public mutating func nextDouble() -> Double {
        state = state &+ 0x6D2B79F5
        let t1 = (state ^ (state >> 15)) &* (state | 1)
        let t2 = (t1 &+ ((t1 ^ (t1 >> 7)) &* (t1 | 61))) ^ t1
        return Double(t2 ^ (t2 >> 14)) / 4_294_967_296.0
    }

    public mutating func nextInt(_ maxExclusive: Int) -> Int {
        guard maxExclusive > 0 else { return 0 }
        return Int(nextDouble() * Double(maxExclusive))
    }
}

// MARK: - Generator

/// Produces score-driven Suggestions categories from the catalogue and the selected
/// player's score index, ported from the web `SuggestionGenerator`
/// (`packages/core/src/suggestions/suggestionGenerator.ts`).
///
/// Band-driven pipelines are not included: Suggestions here is solo-profile only (band mode
/// needs a selected-band context this app doesn't have). Rival-driven `song_rival_*`
/// pipelines *are* included once `setRivalData(_:)` supplies a `RivalDataIndex` (built from
/// `GET /rivals/all` — see `FestivalSession+Suggestions.swift`); with no rival data they
/// simply never run, same as the web with `rivalData: null`. Everything else the web
/// generates from `songs` + `scoresIndex` alone is ported, including the endless-scroll
/// session state (recently shown songs, per-category history, skip-streak smoothing) so
/// repeated `getNext` calls behave like the web's infinite scroll rather than repeating
/// themselves.
///
/// Not thread-safe; use from one isolation context (the app calls it from `@MainActor`).
public final class SuggestionGenerator {
    /// Tuning knobs, mirroring `SuggestionGeneratorOptions` on the web.
    public struct Options: Sendable {
        public var seed: UInt32
        /// Skip the emit-probability roll entirely; used by tests for determinism.
        public var disableSkipping: Bool
        /// Force every category to this many songs instead of a random 2–5.
        public var fixedDisplayCount: Int?
        /// Current published season; stale-song categories are disabled at 0.
        public var currentSeason: Int

        public init(
            seed: UInt32 = 1, disableSkipping: Bool = false, fixedDisplayCount: Int? = nil,
            currentSeason: Int = 0
        ) {
            self.seed = seed
            self.disableSkipping = disableSkipping
            self.fixedDisplayCount = fixedDisplayCount
            self.currentSeason = currentSeason
        }
    }

    /// One (song, chart) pairing considered by a pipeline before final selection.
    private struct Candidate {
        let song: Song
        let score: PlayerScore?
        let instrument: Instrument?
    }

    private static let percentileThresholds = [1, 2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50, 60, 70, 80, 90, 100]
    private static let percentileBuckets = [2, 3, 4, 5, 10, 15, 20, 25, 30, 40, 50]

    private var rng: SuggestionRng
    private let disableSkipping: Bool
    private let fixedDisplayCount: Int?
    private let currentSeason: Int

    private var songs: [Song] = []
    /// `songs` indexed by `Song.songId`, built alongside `songs` in `setSource` so the
    /// rival pipelines (which look songs up by ID from `RivalSongMatch`, not by scanning
    /// the catalogue) don't pay an O(songs) scan per match (web `findSong` does scan its
    /// array, but its arrays are much smaller in practice; this is a native-only optimization
    /// with no behavioral difference).
    private var songsById: [String: Song] = [:]
    private var scoresIndex: [String: [Instrument: PlayerScore]] = [:]
    private var rivalData: RivalDataIndex?

    private var emitted = Set<String>()
    private var pipelines: [() -> [SuggestionCategory]] = []
    private var initialized = false

    private var sessionShownSongs = Set<String>()
    private var recentSongIds: [String] = []
    private var recentArtists: [String] = []
    private var categorySongHistory: [String: Set<String>] = [:]
    private var categorySkipStreak: [String: Int] = [:]
    private var firstPlaysMixedLastInstrument: [String: Instrument] = [:]

    /// Create a generator; call `setSource` before the first `getNext`.
    ///
    /// - Parameter options: Tuning knobs; defaults match normal app behavior.
    public init(options: Options = Options()) {
        rng = SeededSuggestionRng(seed: options.seed)
        disableSkipping = options.disableSkipping
        fixedDisplayCount = options.fixedDisplayCount
        currentSeason = options.currentSeason
    }

    /// Inject a custom RNG (tests only); replaces the default seeded one.
    ///
    /// - Parameter rng: Deterministic or scripted random source.
    public init(rng: SuggestionRng, options: Options = Options()) {
        self.rng = rng
        disableSkipping = options.disableSkipping
        fixedDisplayCount = options.fixedDisplayCount
        currentSeason = options.currentSeason
    }

    /// Supply the catalogue and the selected player's score index.
    ///
    /// - Parameters:
    ///   - songs: Current validated catalogue rows.
    ///   - scoresIndex: `FestivalSession.selectedPlayerScores` (songId → chart → score).
    public func setSource(songs: [Song], scoresIndex: [String: [Instrument: PlayerScore]]) {
        self.songs = songs
        self.scoresIndex = scoresIndex
        songsById = songs.reduce(into: [:]) { dict, song in
            if dict[song.songId] == nil { dict[song.songId] = song }
        }
    }

    /// Inject rival data for the `song_rival_*` pipelines. Pass nil to disable them.
    ///
    /// Ported from the web `SuggestionGenerator.setRivalData`: called *before* the pipeline
    /// list is built (the native `ensureLoaded` flow — rivals load alongside the catalogue
    /// before the generator's first `getNext`), the rival pipelines simply join the one
    /// startup shuffle in `ensurePipelines()` like every other family. Called *after*
    /// (a slower rivals fetch resolving once a page is already showing), it builds the rival
    /// pipelines fresh, shuffles only those, and splices them in at the front of the
    /// remaining queue — so they still show up soon, not only after every already-queued
    /// pipeline has had a turn.
    ///
    /// - Parameter data: Index built by `RivalDataIndex.build(from:)`, or nil to clear it.
    public func setRivalData(_ data: RivalDataIndex?) {
        rivalData = data
        guard let data, initialized else { return }
        var additions = rivalPipelines(data)
        shuffleInPlace(&additions)
        pipelines = additions + pipelines
    }

    /// A catalogue row by ID, or nil if it's left the catalogue (web `findSong`).
    private func findSong(_ songId: String) -> Song? { songsById[songId] }

    /// Produce up to `count` more categories, continuing from where the last call left off.
    ///
    /// - Parameter count: Maximum categories to return (a page size).
    /// - Returns: Newly generated categories; may be fewer than `count`, or empty once the
    ///   generator has exhausted every pipeline for the current source and session history.
    public func getNext(_ count: Int) -> [SuggestionCategory] {
        ensurePipelines()
        var produced: [SuggestionCategory] = []
        var safety = 0
        while produced.count < count, !pipelines.isEmpty, safety < 500 {
            safety += 1
            let pipe = pipelines.removeFirst()
            for category in pipe() {
                guard !category.songs.isEmpty, !emitted.contains(category.key) else { continue }
                emitted.insert(category.key)
                produced.append(category)
                if produced.count >= count { break }
            }
        }
        return produced
    }

    /// Start a fresh "mix": clears emitted-category and shown-song history but keeps the
    /// current source, so the same songs can resurface (web "Start New Mix").
    public func resetForEndless() {
        initialized = false
        pipelines = []
        emitted.removeAll()
        sessionShownSongs.removeAll()
        ensurePipelines()
    }

    // MARK: - Pipeline construction

    private func ensurePipelines() {
        guard !initialized else { return }
        initialized = true

        var list: [() -> [SuggestionCategory]] = [
            { [unowned self] in self.fcTheseNext() },
            { [unowned self] in self.fcTheseNextDecade() },
            { [unowned self] in self.nearFcRelaxed() },
            { [unowned self] in self.nearFcRelaxedDecade() },
            { [unowned self] in self.almostSixStars() },
            { [unowned self] in self.almostSixStarsDecade() },
            { [unowned self] in self.starGains() },
            { [unowned self] in self.starGainsDecade() },
            { [unowned self] in self.firstPlaysMixed() },
            { [unowned self] in self.firstPlaysMixedDecade() },
            { [unowned self] in self.unplayedAll() },
            { [unowned self] in self.unplayedAllDecade() },
            { [unowned self] in self.varietyPack() },
            { [unowned self] in self.artistSamplerRotating() },
            { [unowned self] in self.getMoreStars() },
            { [unowned self] in self.getMoreStarsDecade() },
            { [unowned self] in self.almostElite() },
            { [unowned self] in self.almostEliteDecade() },
            { [unowned self] in self.percentilePush() },
            { [unowned self] in self.percentilePushDecade() },
            { [unowned self] in self.artistFocusUnplayed() },
            { [unowned self] in self.sameNameSets() },
            { [unowned self] in self.sameNameNearFc() },
            { [unowned self] in self.samePercentileBucket() },
        ]

        for instrument in Instrument.allCases {
            list.append({ [unowned self] in self.unFcInstrument(instrument) })
            list.append({ [unowned self] in self.unFcInstrumentDecade(instrument) })
            list.append({ [unowned self] in self.unplayedInstrument(instrument) })
            list.append({ [unowned self] in self.unplayedInstrumentDecade(instrument) })
            list.append({ [unowned self] in self.almostEliteInstrument(instrument) })
            list.append({ [unowned self] in self.almostEliteInstrumentDecade(instrument) })
            list.append({ [unowned self] in self.percentilePushInstrument(instrument) })
            list.append({ [unowned self] in self.percentilePushInstrumentDecade(instrument) })
            list.append({ [unowned self] in self.improveInstrumentRankings(instrument) })
            for seasons in 1...5 {
                list.append({ [unowned self] in self.staleInstrument(instrument, minSeasonsAgo: seasons) })
            }
            for bucket in Self.percentileBuckets {
                list.append({ [unowned self] in self.percentileImproveInstrument(instrument, bucket) })
            }
        }
        for seasons in 1...5 {
            list.append({ [unowned self] in self.staleGlobal(minSeasonsAgo: seasons) })
        }
        for bucket in Self.percentileBuckets {
            list.append({ [unowned self] in self.samePercentileBucketSpecific(bucket) })
            list.append({ [unowned self] in self.percentileImproveBucket(bucket) })
        }
        for tier in Self.nearMaxTiers {
            list.append({ [unowned self] in self.nearMaxScore(minGap: tier.minGap, maxGap: tier.maxGap, tierLabel: tier.label) })
            list.append({ [unowned self] in self.nearMaxScoreDecade(minGap: tier.minGap, maxGap: tier.maxGap, tierLabel: tier.label) })
        }

        // Rival-driven pipelines join the same startup shuffle as everything else when rival
        // data is already available (matches the web: `...(this.rivalData ? this.rivalPipelines(...) : [])`
        // appended right before its own `shuffleInPlace(list)`). A later `setRivalData(_:)`
        // call (after this method has already run once) instead splices them in separately —
        // see that method's doc comment.
        if let rivalData {
            list.append(contentsOf: rivalPipelines(rivalData))
        }

        shuffleInPlace(&list)
        pipelines = list
    }

    /// The `song_rival_*` pipeline closures: one call per generic (non-rival-keyed) family,
    /// plus five per kept rival (`RivalDataIndex.songRivals`). Ported from the web
    /// `rivalPipelines`.
    ///
    /// - Parameter data: Rival data to close over (same instance as `self.rivalData`).
    /// - Returns: Unshuffled closures, in the same order the web builds them.
    private func rivalPipelines(_ data: RivalDataIndex) -> [() -> [SuggestionCategory]] {
        var list: [() -> [SuggestionCategory]] = [
            { [unowned self] in self.songRivalBattleground() },
            { [unowned self] in self.songRivalNearFc() },
            { [unowned self] in self.songRivalStale() },
            { [unowned self] in self.songRivalStarGains() },
            { [unowned self] in self.songRivalPctPush() },
        ]
        for rival in data.songRivals {
            list.append({ [unowned self] in self.songRivalGap(rivalId: rival.accountId) })
            list.append({ [unowned self] in self.songRivalProtect(rivalId: rival.accountId) })
            list.append({ [unowned self] in self.songRivalSpotlight(rivalId: rival.accountId) })
            list.append({ [unowned self] in self.songRivalSlipping(rivalId: rival.accountId) })
            list.append({ [unowned self] in self.songRivalDominate(rivalId: rival.accountId) })
        }
        return list
    }

    // MARK: - Shared helpers

    private func shuffleInPlace<T>(_ array: inout [T]) {
        guard array.count > 1 else { return }
        var i = array.count - 1
        while i > 0 {
            let j = rng.nextInt(i + 1)
            array.swapAt(i, j)
            i -= 1
        }
    }

    private func displayCount() -> Int {
        if let fixedDisplayCount { return max(1, fixedDisplayCount) }
        return 2 + rng.nextInt(4)
    }

    private func canon(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func rawPercentile(_ score: PlayerScore) -> Double? {
        guard let rank = score.rank, let total = score.totalEntries, rank > 0, total > 0 else { return nil }
        return Double(rank) / Double(total)
    }

    private static func percentileBucket(_ rawPct: Double) -> Int? {
        guard rawPct > 0 else { return nil }
        var topPct = rawPct * 100
        topPct = min(max(topPct, 1), 100)
        return percentileThresholds.first { topPct <= Double($0) } ?? 100
    }

    private static func nextLowerThreshold(_ bucket: Int) -> Int? {
        guard let index = percentileThresholds.firstIndex(of: bucket), index > 0 else { return nil }
        return percentileThresholds[index - 1]
    }

    private static func isNearNextBracket(_ rawPct: Double) -> Bool {
        guard let bucket = percentileBucket(rawPct), bucket > 1 else { return false }
        guard let next = nextLowerThreshold(bucket) else { return false }
        let topPct = rawPct * 100
        let midpoint = Double(next) + Double(bucket - next) / 2
        return topPct <= midpoint
    }

    private static func decadeStart(for year: Int?) -> Int? {
        guard let year, year >= 1970, year <= 2099 else { return nil }
        return (year / 10) * 10
    }

    private static func decadeLabel(_ start: Int) -> String {
        let two = start % 100
        return two == 0 ? "00's" : String(format: "%02d's", two)
    }

    private func latestSeason(_ songId: String) -> Int {
        guard let scores = scoresIndex[songId] else { return 0 }
        return Instrument.allCases.compactMap { scores[$0]?.season }.max() ?? 0
    }

    private func instrumentSeason(_ songId: String, _ instrument: Instrument) -> Int {
        scoresIndex[songId]?[instrument]?.season ?? 0
    }

    /// Fresh-candidate count feeding the emit-probability table; mirrors the web's
    /// `getFreshCount` / `getFreshSongCount`, which always key on plain song id.
    private func freshCount(_ pool: [Candidate]) -> Int {
        pool.filter { !sessionShownSongs.contains($0.song.songId) }.count
    }

    private func shouldEmit(key: String, candidateCount: Int) -> Bool {
        if disableSkipping { return candidateCount > 0 }
        let table: [(min: Int, prob: Double)] = [
            (80, 1.0), (50, 0.98), (35, 0.95), (25, 0.9), (18, 0.85),
            (12, 0.75), (8, 0.62), (5, 0.5), (0, 0.38),
        ]
        var prob = 0.38
        for row in table where candidateCount >= row.min {
            prob = row.prob
            break
        }
        let skipped = categorySkipStreak[key] ?? 0
        if skipped >= 2 {
            categorySkipStreak[key] = 0
            return true
        }
        let emit = rng.nextDouble() < prob
        categorySkipStreak[key] = emit ? 0 : skipped + 1
        return emit
    }

    /// A candidate's identity for de-dup history: song+instrument for the mixed
    /// first-plays family (so each instrument can resurface separately), song id otherwise.
    private func historyId(_ candidate: Candidate, categoryKey: String) -> String {
        guard categoryKey == "first_plays_mixed" || categoryKey.hasPrefix("first_plays_mixed_") else {
            return candidate.song.songId
        }
        return "\(candidate.song.songId):\(candidate.instrument?.rawValue ?? "any")"
    }

    /// New-first selection with graceful fallback to category- and session-repeated
    /// songs, ported line-for-line from the web `selectNewFirst`.
    private func selectNewFirst(categoryKey: String, pool: [Candidate], take: Int) -> [Candidate] {
        guard !pool.isEmpty, take > 0 else { return [] }
        var used = categorySongHistory[categoryKey] ?? []
        if pool.allSatisfy({ used.contains(historyId($0, categoryKey: categoryKey)) }) {
            used.removeAll()
        }

        var freshNew = pool.filter {
            !sessionShownSongs.contains(historyId($0, categoryKey: categoryKey))
                && !used.contains(historyId($0, categoryKey: categoryKey))
        }
        shuffleInPlace(&freshNew)
        let freshNewIds = Set(freshNew.map { $0.song.songId })

        var categoryNew = pool.filter {
            !used.contains(historyId($0, categoryKey: categoryKey)) && !freshNewIds.contains($0.song.songId)
        }
        shuffleInPlace(&categoryNew)

        var oldOnes = pool.filter { used.contains(historyId($0, categoryKey: categoryKey)) }
        shuffleInPlace(&oldOnes)

        var result: [Candidate] = []
        var chosenSongs = Set<String>()
        for tier in [freshNew, categoryNew, oldOnes] {
            for candidate in tier {
                guard !chosenSongs.contains(candidate.song.songId) else { continue }
                chosenSongs.insert(candidate.song.songId)
                result.append(candidate)
                if result.count == take { break }
            }
            if result.count == take { break }
        }

        for chosen in result {
            let id = historyId(chosen, categoryKey: categoryKey)
            used.insert(id)
            sessionShownSongs.insert(id)
        }
        categorySongHistory[categoryKey] = used
        return result
    }

    private func mapItem(_ candidate: Candidate, includeInstrument: Bool) -> SuggestionSongItem {
        let percentileDisplay: String? = candidate.score.flatMap { score in
            guard let rank = score.rank, let total = score.totalEntries else { return nil }
            return ScoreFormatting.percentileBucket(rank: rank, totalEntries: total)
        }
        return SuggestionSongItem(
            song: candidate.song, instrument: includeInstrument ? candidate.instrument : nil,
            stars: candidate.score?.stars, percent: candidate.score?.accuracy.map { $0 / 10_000 },
            fullCombo: candidate.score?.isFullCombo, percentileDisplay: percentileDisplay
        )
    }

    private func recordRecent(_ song: Song) {
        recentSongIds.append(song.songId)
        while recentSongIds.count > 40 { recentSongIds.removeFirst() }
        let artist = canon(song.artist)
        guard !artist.isEmpty else { return }
        recentArtists.append(artist)
        while recentArtists.count > 12 { recentArtists.removeFirst() }
    }

    private func finalizeOne(_ candidate: Candidate, includeInstrument: Bool) -> SuggestionSongItem {
        recordRecent(candidate.song)
        return mapItem(candidate, includeInstrument: includeInstrument)
    }

    private func finalize(_ candidates: [Candidate], includeInstrument: Bool) -> [SuggestionSongItem] {
        candidates.map { finalizeOne($0, includeInstrument: includeInstrument) }
    }

    /// Every (song, chart) pair across the catalogue matching a predicate.
    private func candidatesForSong(_ song: Song, matching predicate: (PlayerScore, Instrument) -> Bool) -> [Candidate] {
        guard let scores = scoresIndex[song.songId] else { return [] }
        var out: [Candidate] = []
        for instrument in Instrument.allCases {
            guard let score = scores[instrument], predicate(score, instrument) else { continue }
            out.append(Candidate(song: song, score: score, instrument: instrument))
        }
        return out
    }

    private func candidates(matching predicate: (PlayerScore, Instrument) -> Bool) -> [Candidate] {
        songs.flatMap { candidatesForSong($0, matching: predicate) }
    }

    private func candidates(instrument: Instrument, matching predicate: (PlayerScore) -> Bool) -> [Candidate] {
        var out: [Candidate] = []
        for song in songs {
            guard let score = scoresIndex[song.songId]?[instrument], predicate(score) else { continue }
            out.append(Candidate(song: song, score: score, instrument: instrument))
        }
        return out
    }

    /// Shared shuffle → probability → select → map pipeline for a "plain" (non-decade) category.
    private func emit(
        key: String, title: String, description: String, type: SuggestionCategoryType,
        instrument: Instrument?, pool: [Candidate], includeInstrumentInItems: Bool
    ) -> [SuggestionCategory] {
        var shuffled = pool
        shuffleInPlace(&shuffled)
        guard shouldEmit(key: key, candidateCount: freshCount(shuffled)) else { return [] }
        let selected = selectNewFirst(categoryKey: key, pool: shuffled, take: displayCount())
        guard !selected.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: title, description: description, type: type, instrument: instrument,
            songs: finalize(selected, includeInstrument: includeInstrumentInItems)
        )]
    }

    /// Ported `buildDecadeVariant`: picks one decade with 2+ eligible songs and re-titles
    /// the category for it. Only categories that have a decade sibling in `ensurePipelines`
    /// need their special-cased titles below (the web has the same restriction).
    private func buildDecadeVariant(
        baseKey: String, baseTitle: String, baseDescription: String, type: SuggestionCategoryType,
        instrument: Instrument?, includeInstrumentInItems: Bool, pool: [Candidate]
    ) -> [SuggestionCategory] {
        let valid = pool.filter { ($0.song.year ?? 0) > 0 }
        guard valid.count >= 2 else { return [] }

        var byDecade: [Int: [Candidate]] = [:]
        for candidate in valid {
            guard let start = Self.decadeStart(for: candidate.song.year) else { continue }
            byDecade[start, default: []].append(candidate)
        }
        var groups = byDecade.filter { $0.value.count >= 2 }.sorted { $0.key < $1.key }
        guard !groups.isEmpty else { return [] }
        shuffleInPlace(&groups)
        let (decadeStartValue, chosen) = groups[0]
        let label = Self.decadeLabel(decadeStartValue)
        let variantKey = "\(baseKey)_decade_\(String(format: "%02d", decadeStartValue % 100))"
        let selection = selectNewFirst(categoryKey: variantKey, pool: chosen, take: displayCount())
        guard selection.count >= 2 else { return [] }

        if baseKey == "first_plays_mixed" {
            for candidate in selection {
                if let instrument = candidate.instrument {
                    firstPlaysMixedLastInstrument[candidate.song.songId] = instrument
                }
            }
        }

        var title = "\(baseTitle) (\(label))"
        var description = "\(baseDescription) Limited to \(label) songs."
        switch true {
        case baseKey == "more_stars", baseKey == "almost_six_star":
            title = "Push \(label) to Gold"
        case baseKey.hasPrefix("unfc_"):
            title = "Close \(instrument?.label ?? "") FCs (\(label))"
        case baseKey == "unplayed_any":
            title = "First Plays (\(label))"
        case baseKey.hasPrefix("unplayed_"):
            title = "First \(instrument?.label ?? "") Plays (\(label))"
        case baseKey == "first_plays_mixed":
            title = "First Plays (Mixed \(label))"
        case baseKey == "near_fc_relaxed":
            title = "Close to FC (92%+) - \(label)"
        case baseKey == "near_fc_any":
            title = "FC These Next! (\(label))"
        case baseKey == "star_gains":
            title = "Easy Star Gains (\(label))"
        case baseKey == "almost_elite":
            title = "Almost Elite (\(label))"
            description = "You're in the top 5% on these \(label) songs — one good run could crack the top 1%."
        case baseKey.hasPrefix("almost_elite_"):
            title = "Almost Elite on \(instrument?.label ?? "") (\(label))"
            description = "Your \(instrument?.label ?? "") scores on these \(label) songs are in the top 5% — push them into the top 1%."
        case baseKey == "pct_push":
            title = "Percentile Push (\(label))"
            description = "These \(label) scores are close to the next percentile bracket — replay them to climb."
        case baseKey.hasPrefix("pct_push_"):
            title = "Percentile Push: \(instrument?.label ?? "") (\(label))"
            description = "Replay these \(label) \(instrument?.label ?? "") songs to jump to the next percentile bracket."
        default:
            break
        }
        if baseKey == "unplayed_any" {
            description = "Unplayed songs from the \(label)."
        } else if baseKey.hasPrefix("unplayed_") {
            description = "Unplayed \(instrument?.label ?? "") songs from the \(label)."
        }

        return [SuggestionCategory(
            key: variantKey, title: title, description: description, type: type, instrument: instrument,
            songs: finalize(selection, includeInstrument: includeInstrumentInItems)
        )]
    }

    // MARK: - Near FC

    private func fcTheseNext() -> [SuggestionCategory] {
        let pool = candidates { score, _ in
            (score.stars ?? 0) == 6 && score.isFullCombo != true && (score.accuracy ?? 0) >= 950_000
        }
        return emit(
            key: "near_fc_any", title: "FC These Next!",
            description: "If you can get gold stars, you can FC it!", type: .nearFC, instrument: nil,
            pool: pool, includeInstrumentInItems: true
        )
    }

    private func fcTheseNextDecade() -> [SuggestionCategory] {
        let pool = candidates { score, _ in
            (score.stars ?? 0) == 6 && score.isFullCombo != true && (score.accuracy ?? 0) >= 950_000
        }
        guard shouldEmit(key: "near_fc_any_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "near_fc_any", baseTitle: "FC These Next!",
            baseDescription: "If you can get gold stars, you can FC it!", type: .nearFC, instrument: nil,
            includeInstrumentInItems: true, pool: pool
        )
    }

    private func nearFcRelaxed() -> [SuggestionCategory] {
        let pool = candidates { score, _ in
            (score.stars ?? 0) >= 5 && (score.accuracy ?? 0) >= 920_000 && score.isFullCombo != true
        }
        return emit(
            key: "near_fc_relaxed", title: "Close to FC (92%+)",
            description: "Great runs to try and FC next!", type: .nearFC, instrument: nil, pool: pool,
            includeInstrumentInItems: true
        )
    }

    private func nearFcRelaxedDecade() -> [SuggestionCategory] {
        let pool = candidates { score, _ in
            (score.stars ?? 0) >= 5 && (score.accuracy ?? 0) >= 920_000 && score.isFullCombo != true
        }
        guard shouldEmit(key: "near_fc_relaxed_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "near_fc_relaxed", baseTitle: "Close to FC (92%+)",
            baseDescription: "Great runs to try and FC next!", type: .nearFC, instrument: nil,
            includeInstrumentInItems: true, pool: pool
        )
    }

    private func unFcInstrument(_ instrument: Instrument) -> [SuggestionCategory] {
        let pool = candidates(instrument: instrument) { ($0.stars ?? 0) == 6 && $0.isFullCombo != true }
        return emit(
            key: "unfc_\(instrument.rawValue)", title: "Finish the \(instrument.label) FCs",
            description: "Play these songs again on \(instrument.label) and grab an FC!", type: .nearFC,
            instrument: instrument, pool: pool, includeInstrumentInItems: false
        )
    }

    private func unFcInstrumentDecade(_ instrument: Instrument) -> [SuggestionCategory] {
        let pool = candidates(instrument: instrument) { ($0.stars ?? 0) == 6 && $0.isFullCombo != true }
        let baseKey = "unfc_\(instrument.rawValue)"
        guard shouldEmit(key: "\(baseKey)_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: baseKey, baseTitle: "Finish the \(instrument.label) FCs",
            baseDescription: "Play these songs again on \(instrument.label) and grab an FC!", type: .nearFC,
            instrument: instrument, includeInstrumentInItems: false, pool: pool
        )
    }

    private func sameNameNearFc() -> [SuggestionCategory] {
        var buckets: [String: [Song]] = [:]
        for song in songs where scoresIndex[song.songId] != nil {
            buckets[canon(song.title), default: []].append(song)
        }
        let groupsSorted = buckets.filter { $0.value.count >= 2 }.sorted { $0.key < $1.key }
        guard !groupsSorted.isEmpty else { return [] }
        var groups = groupsSorted
        shuffleInPlace(&groups)
        let pickedGroup = groups[0].value
        let displayTitle = pickedGroup.first?.title.trimmingCharacters(in: .whitespaces) ?? ""

        var poolAll: [Candidate] = []
        for song in pickedGroup {
            poolAll += candidatesForSong(song) { score, _ in
                (score.stars ?? 0) == 6 && score.isFullCombo != true && (score.accuracy ?? 0) >= 900_000
            }
        }
        shuffleInPlace(&poolAll)
        let trimmed = Array(poolAll.prefix(30))
        let final = selectNewFirst(categoryKey: "samename_nearfc", pool: trimmed, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: "samename_nearfc_\(displayTitle)", title: "Close to FC: '\(displayTitle)' Variants",
            description: "FC these same-name songs for a unique achievement!", type: .nearFC, instrument: nil,
            songs: finalize(final, includeInstrument: true)
        )]
    }

    // MARK: - Star progress

    private func almostSixStars() -> [SuggestionCategory] {
        let pool = candidates { score, _ in (score.stars ?? 0) == 5 && (score.accuracy ?? 0) >= 900_000 }
        return emit(
            key: "almost_six_star", title: "Push to Gold Stars",
            description: "Push these five-star runs to gold stars!", type: .starProgress, instrument: nil,
            pool: pool, includeInstrumentInItems: true
        )
    }

    private func almostSixStarsDecade() -> [SuggestionCategory] {
        let pool = candidates { score, _ in (score.stars ?? 0) == 5 && (score.accuracy ?? 0) >= 900_000 }
        guard shouldEmit(key: "almost_six_star_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "almost_six_star", baseTitle: "Push to Gold Stars",
            baseDescription: "Push these five-star runs to gold stars!", type: .starProgress, instrument: nil,
            includeInstrumentInItems: true, pool: pool
        )
    }

    private func starGains() -> [SuggestionCategory] {
        let pool = candidates { score, _ in (score.stars ?? 0) >= 3 && (score.stars ?? 0) < 6 }
        return emit(
            key: "star_gains", title: "Easy Star Gains",
            description: "Hit a new high score to get even more stars on these songs!", type: .starProgress,
            instrument: nil, pool: pool, includeInstrumentInItems: true
        )
    }

    private func starGainsDecade() -> [SuggestionCategory] {
        let pool = candidates { score, _ in (score.stars ?? 0) >= 3 && (score.stars ?? 0) < 6 }
        guard shouldEmit(key: "star_gains_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "star_gains", baseTitle: "Easy Star Gains",
            baseDescription: "Hit a new high score to get even more stars on these songs!", type: .starProgress,
            instrument: nil, includeInstrumentInItems: true, pool: pool
        )
    }

    private func getMoreStars() -> [SuggestionCategory] {
        let pool = candidates { score, _ in (score.stars ?? 0) >= 1 && (score.stars ?? 0) < 6 }
        return emit(
            key: "more_stars", title: "Push These to Gold Stars",
            description: "Try gold-starring this selection of tracks!", type: .starProgress, instrument: nil,
            pool: pool, includeInstrumentInItems: true
        )
    }

    private func getMoreStarsDecade() -> [SuggestionCategory] {
        let pool = candidates { score, _ in (score.stars ?? 0) >= 1 && (score.stars ?? 0) < 6 }
        guard shouldEmit(key: "more_stars_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "more_stars", baseTitle: "Push These to Gold Stars",
            baseDescription: "Try gold-starring this selection of tracks!", type: .starProgress, instrument: nil,
            includeInstrumentInItems: true, pool: pool
        )
    }

    // MARK: - Unplayed

    private func unplayedInstruments(for song: Song) -> [Instrument] {
        let scores = scoresIndex[song.songId]
        return Instrument.allCases.filter { instrument in
            guard song.supports(instrument) else { return false }
            guard let score = scores?[instrument] else { return true }
            return (score.stars ?? 0) == 0
        }
    }

    private func firstPlaysMixedPool() -> [Candidate] {
        var pool: [Candidate] = []
        for song in songs {
            let unplayed = unplayedInstruments(for: song)
            guard !unplayed.isEmpty else { continue }
            let last = firstPlaysMixedLastInstrument[song.songId]
            let eligible = (last != nil && unplayed.count > 1) ? unplayed.filter { $0 != last } : unplayed
            for instrument in eligible {
                pool.append(Candidate(song: song, score: nil, instrument: instrument))
            }
        }
        return pool
    }

    private func firstPlaysMixed() -> [SuggestionCategory] {
        var pool = firstPlaysMixedPool()
        guard !pool.isEmpty else { return [] }
        shuffleInPlace(&pool)
        let final = selectNewFirst(categoryKey: "first_plays_mixed", pool: pool, take: displayCount())
        for candidate in final {
            if let instrument = candidate.instrument {
                firstPlaysMixedLastInstrument[candidate.song.songId] = instrument
            }
        }
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: "first_plays_mixed", title: "First Plays (Mixed)",
            description: "Unplayed picks across instruments.", type: .unplayed, instrument: nil,
            songs: finalize(final, includeInstrument: true)
        )]
    }

    private func firstPlaysMixedDecade() -> [SuggestionCategory] {
        let pool = firstPlaysMixedPool()
        guard shouldEmit(key: "first_plays_mixed_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "first_plays_mixed", baseTitle: "First Plays (Mixed)",
            baseDescription: "Unplayed picks across instruments.", type: .unplayed, instrument: nil,
            includeInstrumentInItems: true, pool: pool
        )
    }

    private func unplayedAll() -> [SuggestionCategory] {
        var list = songs.filter { scoresIndex[$0.songId] == nil }
        shuffleInPlace(&list)
        let pool = list.map { Candidate(song: $0, score: nil, instrument: nil) }
        guard shouldEmit(key: "unplayed_any", candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: "unplayed_any", pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: "unplayed_any", title: "Try Something New",
            description: "Songs you haven't played on any instrument yet.", type: .unplayed, instrument: nil,
            songs: finalize(final, includeInstrument: false)
        )]
    }

    private func unplayedAllDecade() -> [SuggestionCategory] {
        let list = songs.filter { scoresIndex[$0.songId] == nil }
        let pool = list.map { Candidate(song: $0, score: nil, instrument: nil) }
        guard shouldEmit(key: "unplayed_any_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "unplayed_any", baseTitle: "Try Something New",
            baseDescription: "Songs you haven't played on any instrument yet.", type: .unplayed, instrument: nil,
            includeInstrumentInItems: false, pool: pool
        )
    }

    private func unplayedInstrument(_ instrument: Instrument) -> [SuggestionCategory] {
        var list = songs.filter { song in
            guard song.supports(instrument) else { return false }
            guard let score = scoresIndex[song.songId]?[instrument] else { return true }
            return (score.stars ?? 0) == 0
        }
        shuffleInPlace(&list)
        let pool = list.map { Candidate(song: $0, score: nil, instrument: nil) }
        let key = "unplayed_\(instrument.rawValue)"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: "New on \(instrument.label)",
            description: "Songs you haven't played on \(instrument.label) yet.", type: .unplayed,
            instrument: instrument, songs: finalize(final, includeInstrument: false)
        )]
    }

    private func unplayedInstrumentDecade(_ instrument: Instrument) -> [SuggestionCategory] {
        let list = songs.filter { song in
            guard song.supports(instrument) else { return false }
            guard let score = scoresIndex[song.songId]?[instrument] else { return true }
            return (score.stars ?? 0) == 0
        }
        let pool = list.map { Candidate(song: $0, score: nil, instrument: nil) }
        let baseKey = "unplayed_\(instrument.rawValue)"
        guard shouldEmit(key: "\(baseKey)_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: baseKey, baseTitle: "New on \(instrument.label)",
            baseDescription: "Songs you haven't played on \(instrument.label) yet.", type: .unplayed,
            instrument: instrument, includeInstrumentInItems: false, pool: pool
        )
    }

    // MARK: - Variety, artists, same name

    private func varietyPack() -> [SuggestionCategory] {
        var sorted = songs.sorted { a, b in
            let artistOrder = canon(a.artist).compare(canon(b.artist))
            if artistOrder != .orderedSame { return artistOrder == .orderedAscending }
            return a.songId < b.songId
        }
        shuffleInPlace(&sorted)

        var usedArtists = Set<String>()
        var picks: [Song] = []
        for song in sorted {
            let key = canon(song.artist)
            guard !usedArtists.contains(key), !recentSongIds.contains(song.songId),
                  !sessionShownSongs.contains(song.songId) else { continue }
            usedArtists.insert(key)
            picks.append(song)
            if picks.count == 5 { break }
        }

        let freshPicks = picks.filter { !sessionShownSongs.contains($0.songId) }.count
        guard shouldEmit(key: "variety_pack", candidateCount: freshPicks) else { return [] }
        shuffleInPlace(&picks)

        let pool = picks.map { song -> Candidate in
            let scores = scoresIndex[song.songId]
            return Candidate(song: song, score: scores?[.lead] ?? scores?[.drums], instrument: nil)
        }
        let selected = selectNewFirst(categoryKey: "variety_pack", pool: pool, take: displayCount())
        let display = finalize(selected, includeInstrument: false)
        guard display.count >= 2 else { return [] }

        let description: String
        switch display.count {
        case 2: description = "Two different artists for variety."
        case 3: description = "Three different artists for variety."
        case 4: description = "Four different artists for variety."
        default: description = "Five different artists for variety."
        }
        return [SuggestionCategory(
            key: "variety_pack", title: "Variety Pack", description: description, type: .varietyPack,
            instrument: nil, songs: display
        )]
    }

    private func artistSamplerRotating() -> [SuggestionCategory] {
        var groups: [String: [Song]] = [:]
        for song in songs { groups[canon(song.artist), default: []].append(song) }
        var eligible = groups.filter { $0.value.count >= 3 }.sorted { $0.key < $1.key }
        guard !eligible.isEmpty else { return [] }
        shuffleInPlace(&eligible)
        let chosen = eligible[0]
        let artist = canon(chosen.key)
        guard !artist.isEmpty else { return [] }
        recentArtists.append(artist)
        while recentArtists.count > 12 { recentArtists.removeFirst() }

        var picked = Array(chosen.value.sorted { $0.songId < $1.songId }.prefix(10))
        shuffleInPlace(&picked)
        if picked.count > 5 { picked = Array(picked.prefix(displayCount())) }

        var artistName = picked.first?.artist ?? chosen.key
        if artistName.trimmingCharacters(in: .whitespaces).count <= 1 { artistName = "Featured Artist" }
        guard !picked.isEmpty, artistName != "Featured Artist" else { return [] }

        let items = picked.map { song -> SuggestionSongItem in
            let scores = scoresIndex[song.songId]
            let candidate = Candidate(song: song, score: scores?[.lead] ?? scores?[.drums], instrument: nil)
            return finalizeOne(candidate, includeInstrument: false)
        }
        return [SuggestionCategory(
            key: "artist_sampler_\(artistName)", title: "\(artistName) Essentials",
            description: "A selection of songs by \(artistName).", type: .artistEssentials, instrument: nil,
            songs: items
        )]
    }

    private func artistFocusUnplayed() -> [SuggestionCategory] {
        let unplayed = songs.filter { scoresIndex[$0.songId] == nil }
        guard !unplayed.isEmpty else { return [] }
        var groups: [String: [Song]] = [:]
        for song in unplayed { groups[canon(song.artist), default: []].append(song) }
        var entries = groups.sorted { $0.key < $1.key }
        shuffleInPlace(&entries)
        guard let (artistKey, groupSongs) = entries.first else { return [] }
        let displayName = groupSongs.first?.artist ?? "Unknown Artist"
        let pool = groupSongs.map { Candidate(song: $0, score: nil, instrument: nil) }
        let key = "artist_unplayed_\(artistKey)"
        let picked = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !picked.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: "Discover \(displayName)", description: "Unplayed songs from \(displayName).",
            type: .artistDiscover, instrument: nil, songs: finalize(picked, includeInstrument: false)
        )]
    }

    private func sameNameSets() -> [SuggestionCategory] {
        var groups: [String: [Song]] = [:]
        for song in songs { groups[canon(song.title), default: []].append(song) }
        var duplicateGroups = groups.filter { $0.value.count >= 2 }.sorted { $0.key < $1.key }
        guard !duplicateGroups.isEmpty else { return [] }
        shuffleInPlace(&duplicateGroups)
        let groupSongs = duplicateGroups[0].value
        let pool = groupSongs.map { Candidate(song: $0, score: nil, instrument: nil) }
        let selected = selectNewFirst(categoryKey: "samename", pool: pool, take: displayCount())
        guard !selected.isEmpty else { return [] }
        let displayTitle = selected[0].song.title.trimmingCharacters(in: .whitespaces)
        return [SuggestionCategory(
            key: "samename_\(displayTitle)", title: "Songs Named '\(displayTitle)'",
            description: "Different tracks sharing the same title.", type: .sameName, instrument: nil,
            songs: finalize(selected, includeInstrument: false)
        )]
    }

    // MARK: - Almost elite / percentile push

    private func almostElite() -> [SuggestionCategory] {
        let pool = candidates { score, _ in
            guard let raw = self.rawPercentile(score), let bucket = Self.percentileBucket(raw) else { return false }
            return (2...5).contains(bucket)
        }
        return emit(
            key: "almost_elite", title: "Almost Elite",
            description: "You're in the top 5% on these — one good run could crack the top 1%.",
            type: .almostElite, instrument: nil, pool: pool, includeInstrumentInItems: true
        )
    }

    private func almostEliteDecade() -> [SuggestionCategory] {
        let pool = candidates { score, _ in
            guard let raw = self.rawPercentile(score), let bucket = Self.percentileBucket(raw) else { return false }
            return (2...5).contains(bucket)
        }
        guard shouldEmit(key: "almost_elite_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "almost_elite", baseTitle: "Almost Elite",
            baseDescription: "You're in the top 5% on these — one good run could crack the top 1%.",
            type: .almostElite, instrument: nil, includeInstrumentInItems: true, pool: pool
        )
    }

    private func almostEliteInstrument(_ instrument: Instrument) -> [SuggestionCategory] {
        let pool = candidates(instrument: instrument) { score in
            guard let raw = self.rawPercentile(score), let bucket = Self.percentileBucket(raw) else { return false }
            return (2...5).contains(bucket)
        }
        return emit(
            key: "almost_elite_\(instrument.rawValue)", title: "Almost Elite on \(instrument.label)",
            description: "Your \(instrument.label) scores are in the top 5% — push them into the top 1%.",
            type: .almostElite, instrument: instrument, pool: pool, includeInstrumentInItems: false
        )
    }

    private func almostEliteInstrumentDecade(_ instrument: Instrument) -> [SuggestionCategory] {
        let pool = candidates(instrument: instrument) { score in
            guard let raw = self.rawPercentile(score), let bucket = Self.percentileBucket(raw) else { return false }
            return (2...5).contains(bucket)
        }
        let baseKey = "almost_elite_\(instrument.rawValue)"
        guard shouldEmit(key: "\(baseKey)_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: baseKey, baseTitle: "Almost Elite on \(instrument.label)",
            baseDescription: "Your \(instrument.label) scores are in the top 5% — push them into the top 1%.",
            type: .almostElite, instrument: instrument, includeInstrumentInItems: false, pool: pool
        )
    }

    private func percentilePush() -> [SuggestionCategory] {
        let pool = candidates { score, _ in
            guard let raw = self.rawPercentile(score) else { return false }
            return Self.isNearNextBracket(raw)
        }
        return emit(
            key: "pct_push", title: "Percentile Push",
            description: "These scores are close to the next percentile bracket — replay them to climb.",
            type: .percentilePush, instrument: nil, pool: pool, includeInstrumentInItems: true
        )
    }

    private func percentilePushDecade() -> [SuggestionCategory] {
        let pool = candidates { score, _ in
            guard let raw = self.rawPercentile(score) else { return false }
            return Self.isNearNextBracket(raw)
        }
        guard shouldEmit(key: "pct_push_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: "pct_push", baseTitle: "Percentile Push",
            baseDescription: "These scores are close to the next percentile bracket — replay them to climb.",
            type: .percentilePush, instrument: nil, includeInstrumentInItems: true, pool: pool
        )
    }

    private func percentilePushInstrument(_ instrument: Instrument) -> [SuggestionCategory] {
        let pool = candidates(instrument: instrument) { score in
            guard let raw = self.rawPercentile(score) else { return false }
            return Self.isNearNextBracket(raw)
        }
        return emit(
            key: "pct_push_\(instrument.rawValue)", title: "Percentile Push: \(instrument.label)",
            description: "Replay these \(instrument.label) songs to jump to the next percentile bracket.",
            type: .percentilePush, instrument: instrument, pool: pool, includeInstrumentInItems: false
        )
    }

    private func percentilePushInstrumentDecade(_ instrument: Instrument) -> [SuggestionCategory] {
        let pool = candidates(instrument: instrument) { score in
            guard let raw = self.rawPercentile(score) else { return false }
            return Self.isNearNextBracket(raw)
        }
        let baseKey = "pct_push_\(instrument.rawValue)"
        guard shouldEmit(key: "\(baseKey)_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: baseKey, baseTitle: "Percentile Push: \(instrument.label)",
            baseDescription: "Replay these \(instrument.label) songs to jump to the next percentile bracket.",
            type: .percentilePush, instrument: instrument, includeInstrumentInItems: false, pool: pool
        )
    }

    // MARK: - Stale songs

    private func staleGlobal(minSeasonsAgo: Int) -> [SuggestionCategory] {
        guard currentSeason > 0 else { return [] }
        var pool: [Candidate] = []
        for song in songs {
            let latest = latestSeason(song.songId)
            guard latest > 0 else { continue }
            let ago = currentSeason - latest
            let match = minSeasonsAgo >= 5 ? ago >= 5 : ago >= minSeasonsAgo
            if match { pool.append(Candidate(song: song, score: nil, instrument: nil)) }
        }
        shuffleInPlace(&pool)
        let suffix = minSeasonsAgo >= 5 ? "5plus" : "\(minSeasonsAgo)"
        let key = "stale_global_\(suffix)"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        let title = minSeasonsAgo == 1 ? "Play This Season"
            : minSeasonsAgo >= 5 ? "Untouched for 5+ Seasons" : "Untouched for \(minSeasonsAgo) Seasons"
        let description = minSeasonsAgo == 1 ? "Songs you haven't played on any instrument this season."
            : minSeasonsAgo >= 5 ? "Songs you haven't played on any instrument in 5 or more seasons."
            : "Songs you haven't played on any instrument in at least \(minSeasonsAgo) seasons."
        return [SuggestionCategory(
            key: key, title: title, description: description, type: .stale, instrument: nil,
            songs: finalize(final, includeInstrument: false)
        )]
    }

    private func staleInstrument(_ instrument: Instrument, minSeasonsAgo: Int) -> [SuggestionCategory] {
        guard currentSeason > 0 else { return [] }
        var pool: [Candidate] = []
        for song in songs {
            let season = instrumentSeason(song.songId, instrument)
            guard season > 0 else { continue }
            let ago = currentSeason - season
            let match = minSeasonsAgo >= 5 ? ago >= 5 : ago >= minSeasonsAgo
            if match {
                let score = scoresIndex[song.songId]?[instrument]
                pool.append(Candidate(song: song, score: score, instrument: instrument))
            }
        }
        shuffleInPlace(&pool)
        let suffix = minSeasonsAgo >= 5 ? "5plus" : "\(minSeasonsAgo)"
        let key = "stale_\(instrument.rawValue)_\(suffix)"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        let name = instrument.label
        let title = minSeasonsAgo == 1 ? "Play \(name) This Season"
            : minSeasonsAgo >= 5 ? "\(name) Untouched for 5+ Seasons" : "\(name) Untouched for \(minSeasonsAgo) Seasons"
        let description = minSeasonsAgo == 1 ? "Songs you haven't played on \(name) this season."
            : minSeasonsAgo >= 5 ? "Songs you haven't played on \(name) in 5 or more seasons."
            : "Songs you haven't played on \(name) in at least \(minSeasonsAgo) seasons."
        return [SuggestionCategory(
            key: key, title: title, description: description, type: .stale, instrument: instrument,
            songs: finalize(final, includeInstrument: true)
        )]
    }

    // MARK: - Percentile improvement

    private func samePercentileBucket() -> [SuggestionCategory] {
        var pool: [Candidate] = []
        var songBucket: [String: Int] = [:]
        for song in songs {
            guard let scores = scoresIndex[song.songId] else { continue }
            var buckets: [Int] = []
            for instrument in Instrument.allCases {
                guard let score = scores[instrument], let raw = rawPercentile(score), raw > 0,
                      let bucket = Self.percentileBucket(raw) else { continue }
                buckets.append(bucket)
            }
            if buckets.count >= 2, let first = buckets.first, buckets.allSatisfy({ $0 == first }), first > 1 {
                pool.append(Candidate(song: song, score: nil, instrument: nil))
                songBucket[song.songId] = first
            }
        }
        shuffleInPlace(&pool)
        let key = "same_pct_improve"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        let items = final.map { candidate -> SuggestionSongItem in
            var item = finalizeOne(candidate, includeInstrument: false)
            if let bucket = songBucket[candidate.song.songId] { item.percentileDisplay = "Top \(bucket)%" }
            return item
        }
        return [SuggestionCategory(
            key: key, title: "Competitive Improvements",
            description: "Songs where your percentile is the same across all instruments. An improvement on any instrument moves you up everywhere.",
            type: .pctImprove, instrument: nil, songs: items
        )]
    }

    private func samePercentileBucketSpecific(_ bucket: Int) -> [SuggestionCategory] {
        var pool: [Candidate] = []
        for song in songs {
            guard let scores = scoresIndex[song.songId] else { continue }
            var buckets: [Int] = []
            for instrument in Instrument.allCases {
                guard let score = scores[instrument], let raw = rawPercentile(score), raw > 0,
                      let b = Self.percentileBucket(raw) else { continue }
                buckets.append(b)
            }
            if buckets.count >= 2, buckets.allSatisfy({ $0 == bucket }) {
                pool.append(Candidate(song: song, score: nil, instrument: nil))
            }
        }
        shuffleInPlace(&pool)
        let key = "same_pct_\(bucket)"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        let next = Self.nextLowerThreshold(bucket)
        let target = next.map { "Top \($0)%" } ?? "a higher bracket"
        let items = final.map { candidate -> SuggestionSongItem in
            var item = finalizeOne(candidate, includeInstrument: false)
            item.percentileDisplay = "Top \(bucket)%"
            return item
        }
        return [SuggestionCategory(
            key: key, title: "Break Into \(target)",
            description: "Songs where all your instruments are ranked Top \(bucket)%. Improve any instrument to break the tie and climb to \(target).",
            type: .pctImprove, instrument: nil, songs: items
        )]
    }

    private func percentileImproveBucket(_ bucket: Int) -> [SuggestionCategory] {
        guard bucket > 1 else { return [] }
        let pool = candidates { score, _ in
            guard let raw = self.rawPercentile(score) else { return false }
            return Self.percentileBucket(raw) == bucket
        }
        return emit(
            key: "pct_improve_\(bucket)", title: "Top \(bucket)% Push",
            description: "Songs with at least one instrument ranked Top \(bucket)%. A small score bump could push you higher.",
            type: .pctImprove, instrument: nil, pool: pool, includeInstrumentInItems: true
        )
    }

    private func percentileImproveInstrument(_ instrument: Instrument, _ bucket: Int) -> [SuggestionCategory] {
        guard bucket > 1 else { return [] }
        let pool = candidates(instrument: instrument) { score in
            guard let raw = self.rawPercentile(score) else { return false }
            return Self.percentileBucket(raw) == bucket
        }
        return emit(
            key: "pct_improve_\(instrument.rawValue)_\(bucket)", title: "Top \(bucket)% Push",
            description: "Songs with \(instrument.label) scores ranked Top \(bucket)%. A small score bump could push you higher.",
            type: .pctImprove, instrument: instrument, pool: pool, includeInstrumentInItems: false
        )
    }

    private func improveInstrumentRankings(_ instrument: Instrument) -> [SuggestionCategory] {
        var byBucket: [Int: [Candidate]] = [:]
        for song in songs {
            guard let score = scoresIndex[song.songId]?[instrument], let raw = rawPercentile(score), raw > 0,
                  let bucket = Self.percentileBucket(raw), bucket > 1 else { continue }
            byBucket[bucket, default: []].append(Candidate(song: song, score: score, instrument: instrument))
        }
        guard byBucket.count >= 3 else { return [] }

        var picks: [Candidate] = []
        for bucket in byBucket.keys.sorted() {
            var group = byBucket[bucket] ?? []
            shuffleInPlace(&group)
            if let first = group.first { picks.append(first) }
        }
        shuffleInPlace(&picks)

        let key = "improve_rankings_\(instrument.rawValue)"
        guard shouldEmit(key: key, candidateCount: freshCount(picks)) else { return [] }
        let take = min(displayCount(), picks.count)
        let final = selectNewFirst(categoryKey: key, pool: picks, take: take)
        guard final.count >= 3 else { return [] }
        return [SuggestionCategory(
            key: key, title: "Improve \(instrument.label) Rankings",
            description: "A varied mix of \(instrument.label) songs across different percentile brackets — all with room to grow.",
            type: .pctImprove, instrument: instrument, songs: finalize(final, includeInstrument: false)
        )]
    }

    // MARK: - Near max score

    /// One exclusive CHOpt-max-score gap tier, ported from the web's three `nearMaxScore`
    /// call sites (`(0, 5k]`, `(5k, 10k]`, `(10k, 15k]`).
    private struct NearMaxTier { let minGap: Int; let maxGap: Int; let label: String }

    private static let nearMaxTiers: [NearMaxTier] = [
        NearMaxTier(minGap: 0, maxGap: 5_000, label: "5k"),
        NearMaxTier(minGap: 5_000, maxGap: 10_000, label: "10k"),
        NearMaxTier(minGap: 10_000, maxGap: 15_000, label: "15k"),
    ]

    private static let nearMaxTitles: [String: String] = [
        "5k": "Almost Perfect (Within 5k)",
        "10k": "Close to Max (Within 10k)",
        "15k": "Approaching Max (Within 15k)",
    ]

    private static let nearMaxDescriptions: [String: String] = [
        "5k": "Scores within 5,000 of the theoretical max. You're almost there!",
        "10k": "Scores within 10,000 of the theoretical max. A great run could close the gap.",
        "15k": "Scores within 15,000 of the theoretical max. Keep pushing!",
    ]

    /// Every (song, chart) pair where the player has a positive score, the catalogue
    /// reports a positive CHOpt theoretical max for that chart, and the gap between them
    /// falls in `(minGap, maxGap]` — ported from the web's `nearMaxScore`/`eachTracker`.
    private func nearMaxCandidates(minGap: Int, maxGap: Int) -> [Candidate] {
        var out: [Candidate] = []
        for song in songs {
            guard song.maxScores != nil, let scores = scoresIndex[song.songId] else { continue }
            for instrument in Instrument.allCases {
                guard let score = scores[instrument], score.score > 0,
                      let choptMax = song.maxScore(for: instrument) else { continue }
                let gap = choptMax - score.score
                guard gap > minGap, gap <= maxGap else { continue }
                out.append(Candidate(song: song, score: score, instrument: instrument))
            }
        }
        return out
    }

    private func nearMaxScore(minGap: Int, maxGap: Int, tierLabel: String) -> [SuggestionCategory] {
        let pool = nearMaxCandidates(minGap: minGap, maxGap: maxGap)
        let key = "near_max_\(tierLabel)"
        return emit(
            key: key, title: Self.nearMaxTitles[tierLabel] ?? "Near Max Score (\(tierLabel))",
            description: Self.nearMaxDescriptions[tierLabel] ?? "Scores within \(tierLabel) of the CHOpt theoretical max.",
            type: .nearMax, instrument: nil, pool: pool, includeInstrumentInItems: true
        )
    }

    private func nearMaxScoreDecade(minGap: Int, maxGap: Int, tierLabel: String) -> [SuggestionCategory] {
        let pool = nearMaxCandidates(minGap: minGap, maxGap: maxGap)
        let key = "near_max_\(tierLabel)"
        guard shouldEmit(key: "\(key)_decade_wrap", candidateCount: freshCount(pool)) else { return [] }
        return buildDecadeVariant(
            baseKey: key, baseTitle: Self.nearMaxTitles[tierLabel] ?? "Near Max Score (\(tierLabel))",
            baseDescription: Self.nearMaxDescriptions[tierLabel] ?? "Scores within \(tierLabel) of the CHOpt theoretical max.",
            type: .nearMax, instrument: nil, includeInstrumentInItems: true, pool: pool
        )
    }

    // MARK: - Rival strategies

    /// Look up a rival match by song/chart from one rival's own match list, mirroring the
    /// web's re-`find` after `selectNewFirst` reorders the pool (rather than threading a
    /// parallel tuple array through shuffle/selection).
    private func matchLookup(_ matches: [RivalSongMatch]) -> [String: RivalSongMatch] {
        var out: [String: RivalSongMatch] = [:]
        for match in matches { out[RivalDataIndex.closestKey(match.songId, match.instrument)] = match }
        return out
    }

    private func matchKey(_ candidate: Candidate) -> String? {
        guard let instrument = candidate.instrument else { return nil }
        return RivalDataIndex.closestKey(candidate.song.songId, instrument)
    }

    /// Web `mapRivalSong`: a rival-keyed category's own item, always instrument-included.
    private func mapRivalItem(_ candidate: Candidate, rival: RivalInfo, rankDelta: Int) -> SuggestionSongItem {
        var item = finalizeOne(candidate, includeInstrument: true)
        item.rivalName = rival.displayName
        item.rivalAccountId = rival.accountId
        item.rivalRankDelta = rankDelta
        return item
    }

    /// Web `annotateWithRival` + a non-rival-keyed category's own `mapUniqueSongWithInstrument`
    /// spread: attach the closest rival match, if any, without requiring one to exist.
    private func mapWithClosestRival(_ candidate: Candidate) -> SuggestionSongItem {
        var item = finalizeOne(candidate, includeInstrument: true)
        if let instrument = candidate.instrument,
           let match = rivalData?.closestRivalBySong[RivalDataIndex.closestKey(candidate.song.songId, instrument)] {
            item.rivalName = match.rival.displayName
            item.rivalAccountId = match.rival.accountId
            item.rivalRankDelta = match.rankDelta
        }
        return item
    }

    /// The closest rival's display name on the first selected candidate's song/chart, or a
    /// generic fallback — used by the cross-pollination titles (web falls back to `'a rival'`).
    private func closestRivalName(_ candidate: Candidate) -> String {
        guard let instrument = candidate.instrument,
              let match = rivalData?.closestRivalBySong[RivalDataIndex.closestKey(candidate.song.songId, instrument)]
        else { return "a rival" }
        return match.rival.displayName
    }

    /// Close the Gap vs {rival}: songs where the rival barely leads (`rankDelta < 0`),
    /// closest gaps first.
    private func songRivalGap(rivalId: String) -> [SuggestionCategory] {
        guard let matches = rivalData?.byRival[rivalId], !matches.isEmpty else { return [] }
        let rival = matches[0].rival
        let lookup = matchLookup(matches)
        var pool: [Candidate] = []
        for match in matches where match.rankDelta < 0 {
            guard let song = findSong(match.songId) else { continue }
            pool.append(Candidate(song: song, score: scoresIndex[match.songId]?[match.instrument], instrument: match.instrument))
        }
        guard !pool.isEmpty else { return [] }
        pool.sort { abs(lookup[matchKey($0) ?? ""]?.rankDelta ?? 999) < abs(lookup[matchKey($1) ?? ""]?.rankDelta ?? 999) }

        let key = "song_rival_gap_\(rivalId)"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: "Close the Gap vs \(rival.displayName)",
            description: "Songs where \(rival.displayName) barely leads you. One good run could overtake them.",
            type: .songRivals, instrument: nil,
            songs: final.map { mapRivalItem($0, rival: rival, rankDelta: lookup[matchKey($0) ?? ""]?.rankDelta ?? 0) }
        )]
    }

    /// Protect Your Lead vs {rival}: songs where the player barely leads (`rankDelta > 0`),
    /// closest leads first.
    private func songRivalProtect(rivalId: String) -> [SuggestionCategory] {
        guard let matches = rivalData?.byRival[rivalId], !matches.isEmpty else { return [] }
        let rival = matches[0].rival
        let lookup = matchLookup(matches)
        var pool: [Candidate] = []
        for match in matches where match.rankDelta > 0 {
            guard let song = findSong(match.songId) else { continue }
            pool.append(Candidate(song: song, score: scoresIndex[match.songId]?[match.instrument], instrument: match.instrument))
        }
        guard !pool.isEmpty else { return [] }
        pool.sort { (lookup[matchKey($0) ?? ""]?.rankDelta ?? 999) < (lookup[matchKey($1) ?? ""]?.rankDelta ?? 999) }

        let key = "song_rival_protect_\(rivalId)"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: "Protect Your Lead vs \(rival.displayName)",
            description: "You're barely ahead of \(rival.displayName) on these. Don't let them pass you.",
            type: .songRivals, instrument: nil,
            songs: final.map { mapRivalItem($0, rival: rival, rankDelta: lookup[matchKey($0) ?? ""]?.rankDelta ?? 0) }
        )]
    }

    /// Battleground Songs: song/chart pairings where 2+ rivals cluster within 10 ranks of
    /// the player, across every rival (not scoped to one). Dictionary iteration is sorted by
    /// key for run-to-run determinism (Swift's hash seed is randomized per process, unlike
    /// the web's Map insertion order — see `ios.md` for why literal cross-language byte
    /// parity isn't the bar here, same caveat as `near_max_*`).
    private func songRivalBattleground() -> [SuggestionCategory] {
        guard let rivalData else { return [] }
        var rivalCountBySong: [String: Int] = [:]
        for matches in rivalData.byRival.values {
            for match in matches where abs(match.rankDelta) <= 10 {
                rivalCountBySong[RivalDataIndex.closestKey(match.songId, match.instrument), default: 0] += 1
            }
        }
        var pool: [Candidate] = []
        for key in rivalCountBySong.keys.sorted() where (rivalCountBySong[key] ?? 0) >= 2 {
            guard let separator = key.lastIndex(of: ":") else { continue }
            let songId = String(key[key.startIndex..<separator])
            let instrumentRaw = String(key[key.index(after: separator)...])
            guard let instrument = Instrument(rawValue: instrumentRaw), let song = findSong(songId) else { continue }
            pool.append(Candidate(song: song, score: scoresIndex[songId]?[instrument], instrument: instrument))
        }
        guard !pool.isEmpty else { return [] }
        shuffleInPlace(&pool)

        let key = "song_rival_battleground"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: "Battleground Songs",
            description: "Multiple rivals are clustered around your rank on these songs. Every position matters.",
            type: .songRivals, instrument: nil, songs: final.map { mapWithClosestRival($0) }
        )]
    }

    /// Rival Spotlight: a curated mix (1-2 catch-up, 1-2 protect, 1 closest overall) for one
    /// rival. Unlike every other rival family, the web gates this only on "already emitted
    /// this session" — no `shouldEmit` probability roll — so it always shows once a rival
    /// has 3+ shared songs.
    private func songRivalSpotlight(rivalId: String) -> [SuggestionCategory] {
        guard let matches = rivalData?.byRival[rivalId], matches.count >= 3 else { return [] }
        let rival = matches[0].rival

        let behind = matches.filter { $0.rankDelta < 0 }.sorted { abs($0.rankDelta) < abs($1.rankDelta) }
        let ahead = matches.filter { $0.rankDelta > 0 }.sorted { $0.rankDelta < $1.rankDelta }
        let closest = matches.sorted { abs($0.rankDelta) < abs($1.rankDelta) }

        var picks: [RivalSongMatch] = []
        if behind.count > 0 { picks.append(behind[0]) }
        if behind.count > 1 { picks.append(behind[1]) }
        if ahead.count > 0 { picks.append(ahead[0]) }
        if ahead.count > 1 { picks.append(ahead[1]) }
        if let closestNew = closest.first(where: { candidate in !picks.contains { $0.songId == candidate.songId } }) {
            picks.append(closestNew)
        }

        var pool: [Candidate] = []
        for match in picks {
            guard let song = findSong(match.songId) else { continue }
            pool.append(Candidate(song: song, score: scoresIndex[match.songId]?[match.instrument], instrument: match.instrument))
        }
        guard pool.count >= 3 else { return [] }

        let key = "song_rival_spotlight_\(rivalId)"
        guard !emitted.contains(key) else { return [] }
        let lookup = matchLookup(matches)
        return [SuggestionCategory(
            key: key, title: "Rival Spotlight: \(rival.displayName)",
            description: "A curated mix of your rivalry with \(rival.displayName) — catches, defenses, and closest battles.",
            type: .songRivals, instrument: nil,
            songs: pool.map { mapRivalItem($0, rival: rival, rankDelta: lookup[matchKey($0) ?? ""]?.rankDelta ?? 0) }
        )]
    }

    /// {rival} is Pulling Ahead: large rival leads (`rankDelta < -20`).
    private func songRivalSlipping(rivalId: String) -> [SuggestionCategory] {
        guard let matches = rivalData?.byRival[rivalId], !matches.isEmpty else { return [] }
        let rival = matches[0].rival
        let lookup = matchLookup(matches)
        var pool: [Candidate] = []
        for match in matches where match.rankDelta < -20 {
            guard let song = findSong(match.songId) else { continue }
            pool.append(Candidate(song: song, score: scoresIndex[match.songId]?[match.instrument], instrument: match.instrument))
        }
        guard !pool.isEmpty else { return [] }
        shuffleInPlace(&pool)

        let key = "song_rival_slipping_\(rivalId)"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: "\(rival.displayName) is Pulling Ahead",
            description: "\(rival.displayName) has a big lead on these songs. Time to close the gap.",
            type: .songRivals, instrument: nil,
            songs: final.map { mapRivalItem($0, rival: rival, rankDelta: lookup[matchKey($0) ?? ""]?.rankDelta ?? 0) }
        )]
    }

    /// Dominate {rival}: large player leads (`rankDelta > 30`).
    private func songRivalDominate(rivalId: String) -> [SuggestionCategory] {
        guard let matches = rivalData?.byRival[rivalId], !matches.isEmpty else { return [] }
        let rival = matches[0].rival
        let lookup = matchLookup(matches)
        var pool: [Candidate] = []
        for match in matches where match.rankDelta > 30 {
            guard let song = findSong(match.songId) else { continue }
            pool.append(Candidate(song: song, score: scoresIndex[match.songId]?[match.instrument], instrument: match.instrument))
        }
        guard !pool.isEmpty else { return [] }
        shuffleInPlace(&pool)

        let key = "song_rival_dominate_\(rivalId)"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: "Dominate \(rival.displayName)",
            description: "You're crushing \(rival.displayName) on these. Keep up the dominance.",
            type: .songRivals, instrument: nil,
            songs: final.map { mapRivalItem($0, rival: rival, rankDelta: lookup[matchKey($0) ?? ""]?.rankDelta ?? 0) }
        )]
    }

    /// FC These to Beat {rival}!: near-FC runs (web `nearFcRelaxed`'s own predicate) where a
    /// rival also has a score on that song/chart, regardless of who currently leads.
    private func songRivalNearFc() -> [SuggestionCategory] {
        guard let rivalData else { return [] }
        var pool: [Candidate] = []
        for candidate in candidates(matching: { score, _ in
            (score.stars ?? 0) >= 5 && (score.accuracy ?? 0) >= 920_000 && score.isFullCombo != true
        }) {
            guard let instrument = candidate.instrument,
                  rivalData.closestRivalBySong[RivalDataIndex.closestKey(candidate.song.songId, instrument)] != nil
            else { continue }
            pool.append(candidate)
        }
        guard !pool.isEmpty else { return [] }
        shuffleInPlace(&pool)

        let key = "song_rival_near_fc"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        let rivalName = closestRivalName(final[0])
        return [SuggestionCategory(
            key: key, title: "FC These to Beat \(rivalName)!",
            description: "Almost FC songs where your rival also competes. Nail the combo to pull ahead.",
            type: .songRivals, instrument: nil, songs: final.map { mapWithClosestRival($0) }
        )]
    }

    /// Stale songs where a rival is beating the player (`rankDelta < 0`) and the player's own
    /// run is at least two seasons old.
    private func songRivalStale() -> [SuggestionCategory] {
        guard let rivalData, currentSeason != 0 else { return [] }
        var pool: [Candidate] = []
        for candidate in candidates(matching: { score, _ in
            guard let season = score.season, season != 0 else { return false }
            return self.currentSeason - season >= 2
        }) {
            guard let instrument = candidate.instrument,
                  let match = rivalData.closestRivalBySong[RivalDataIndex.closestKey(candidate.song.songId, instrument)],
                  match.rankDelta < 0
            else { continue }
            pool.append(candidate)
        }
        guard !pool.isEmpty else { return [] }
        shuffleInPlace(&pool)

        let key = "song_rival_stale"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        return [SuggestionCategory(
            key: key, title: "Stale Songs Your Rivals Are Beating You On",
            description: "Songs you haven't touched in a while where rivals have pulled ahead.",
            type: .songRivals, instrument: nil, songs: final.map { mapWithClosestRival($0) }
        )]
    }

    /// Star-gain songs (3–5 stars) where a rival is ahead (`rankDelta < 0`) — improving would
    /// also pass them.
    private func songRivalStarGains() -> [SuggestionCategory] {
        guard let rivalData else { return [] }
        var pool: [Candidate] = []
        for candidate in candidates(matching: { score, _ in
            let stars = score.stars ?? 0
            return stars >= 3 && stars <= 5
        }) {
            guard let instrument = candidate.instrument,
                  let match = rivalData.closestRivalBySong[RivalDataIndex.closestKey(candidate.song.songId, instrument)],
                  match.rankDelta < 0
            else { continue }
            pool.append(candidate)
        }
        guard !pool.isEmpty else { return [] }
        shuffleInPlace(&pool)

        let key = "song_rival_star_gains"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        let rivalName = closestRivalName(final[0])
        return [SuggestionCategory(
            key: key, title: "Gain Stars & Beat \(rivalName)",
            description: "Improving your star count on these would also overtake a rival.",
            type: .songRivals, instrument: nil, songs: final.map { mapWithClosestRival($0) }
        )]
    }

    /// Percentile-push songs (not already top 1%) where a rival is ahead (`rankDelta < 0`) —
    /// climbing would also pass them.
    private func songRivalPctPush() -> [SuggestionCategory] {
        guard let rivalData else { return [] }
        var pool: [Candidate] = []
        for candidate in candidates(matching: { score, _ in
            guard let raw = self.rawPercentile(score), let bucket = Self.percentileBucket(raw) else { return false }
            return bucket > 1
        }) {
            guard let instrument = candidate.instrument,
                  let match = rivalData.closestRivalBySong[RivalDataIndex.closestKey(candidate.song.songId, instrument)],
                  match.rankDelta < 0
            else { continue }
            pool.append(candidate)
        }
        guard !pool.isEmpty else { return [] }
        shuffleInPlace(&pool)

        let key = "song_rival_pct_push"
        guard shouldEmit(key: key, candidateCount: freshCount(pool)) else { return [] }
        let final = selectNewFirst(categoryKey: key, pool: pool, take: displayCount())
        guard !final.isEmpty else { return [] }
        let rivalName = closestRivalName(final[0])
        return [SuggestionCategory(
            key: key, title: "Climb Past \(rivalName)",
            description: "A percentile push on these would also move you past a rival.",
            type: .songRivals, instrument: nil, songs: final.map { mapWithClosestRival($0) }
        )]
    }
}
