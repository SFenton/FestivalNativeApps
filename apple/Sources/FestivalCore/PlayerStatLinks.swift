import Foundation

// MARK: - Songs state a preset rewrites

/// The saved Songs state a player-page stat link rewrites before showing Songs: the
/// subset of the web `SongSettings` the native Songs tab can express today.
///
/// Season and difficulty filters are not ported to native Songs yet; the stars and
/// percentile buckets live in ``SongPlayerScoreFilter``.
public struct SongsSavedState: Equatable, Sendable {
    /// Songs instrument filter (the root-owned `songsInstrument`); nil shows every chart.
    public var instrument: Instrument?
    /// `fst.songs.sortMode`.
    public var sortMode: SongSortMode
    /// `fst.songs.sortAscending`.
    public var sortAscending: Bool
    /// `SongGeneralFilter.storageKey` (Year, Duration, Item Shop and Double Bass).
    public var generalFilter: SongGeneralFilter
    /// `SongPlayerScoreFilter.storageKey` (chart checks plus stars/percentile buckets).
    public var playerFilter: SongPlayerScoreFilter

    /// Create a saved Songs state; the defaults are the Songs tab's own defaults.
    ///
    /// - Parameters:
    ///   - instrument: Instrument filter.
    ///   - sortMode: Sort.
    ///   - sortAscending: Sort direction.
    ///   - generalFilter: Public General filters (Year, Duration, Item Shop, Double Bass).
    ///   - playerFilter: Selected-player score and full-combo checks.
    public init(
        instrument: Instrument? = nil, sortMode: SongSortMode = .title, sortAscending: Bool = true,
        generalFilter: SongGeneralFilter = SongGeneralFilter(),
        playerFilter: SongPlayerScoreFilter = SongPlayerScoreFilter()
    ) {
        self.instrument = instrument
        self.sortMode = sortMode
        self.sortAscending = sortAscending
        self.generalFilter = generalFilter
        self.playerFilter = playerFilter
    }
}

// MARK: - Songs presets

/// A stat tile's Songs filter, ported from the web's settings updaters
/// (`OverallSummarySection.tsx` `songsPlayedUpdater`/`fullCombosUpdater`,
/// `InstrumentStatsSection.tsx` `instSongsPlayedUpdater`/`instFCsUpdater`, and
/// `playerFilterHelpers.ts` `cleanFilters`).
public enum SongsFilterPreset: Hashable, Sendable {
    /// Overview "Songs Played" (``SongScoreFilterKind/hasScores``) or "Full Combos"
    /// (``SongScoreFilterKind/hasFCs``): every Songs filter reset to its default, the
    /// check set on every Settings-visible chart, no instrument, Title ascending.
    case overall(SongScoreFilterKind, visible: Set<Instrument>)
    /// An instrument's "Songs Played" or "FCs": that chart becomes the Songs
    /// instrument, its own four checks and the stars/percentile buckets are cleared and
    /// one check is set; other charts' checks and the General filters are kept (web
    /// `cleanFilters`), sorted by Score ascending (web `instSongsPlayedUpdater` /
    /// `instFCsUpdater`).
    case instrument(SongScoreFilterKind, Instrument)
    /// An instrument's Gold / 5…1 Stars tile: only that star bucket shown (`6` is gold),
    /// sorted by Stars ascending (web `instStarsUpdater`).
    case stars(Instrument, starKey: Int)
    /// An instrument's "Percentile" tile (web `instPercentileUpdater`), or with
    /// `scoredOnly` its "Songs Played" percentile tile (`instPercentileWithScoresUpdater`,
    /// which also sets Has Scores): sorted by Percentile ascending.
    case percentile(Instrument, scoredOnly: Bool)
    /// A percentile table row: only that bucket shown; the saved sort mode is kept and
    /// the direction becomes ascending (web `instPercentileBucketUpdater`).
    case percentileBucket(Instrument, percentile: Int)

    /// The Songs instrument filter this preset shows.
    public var instrument: Instrument? {
        switch self {
        case .overall: nil
        case let .instrument(_, instrument), let .stars(instrument, _),
             let .percentile(instrument, _), let .percentileBucket(instrument, _): instrument
        }
    }

    /// Rewrite the saved Songs state, like the web's `saveSongSettings(updater(load()))`.
    ///
    /// - Parameters:
    ///   - current: Saved Songs state (a corrupt saved player filter is passed as empty:
    ///     the preset is an explicit new choice that replaces it).
    ///   - visibleInstruments: Settings-visible charts; a preset never adds a check on a
    ///     hidden chart.
    /// - Returns: The state to save before showing Songs.
    public func applied(to current: SongsSavedState, visibleInstruments: Set<Instrument>) -> SongsSavedState {
        switch self {
        case let .overall(kind, visible):
            let charts = visible.intersection(visibleInstruments)
            return SongsSavedState(
                playerFilter: SongPlayerScoreFilter().settingAll(kind, visibleInstruments: charts, enabled: true)
            )
        case let .instrument(kind, instrument):
            return cleaned(current, instrument, visibleInstruments: visibleInstruments, sort: .score) {
                $0.setting(kind, for: instrument, enabled: true)
            }
        case let .stars(instrument, starKey):
            return cleaned(current, instrument, visibleInstruments: visibleInstruments, sort: .stars) {
                $0.showingOnlyStars(starKey)
            }
        case let .percentile(instrument, scoredOnly):
            return cleaned(current, instrument, visibleInstruments: visibleInstruments, sort: .percentile) {
                scoredOnly ? $0.setting(.hasScores, for: instrument, enabled: true) : $0
            }
        case let .percentileBucket(instrument, percentile):
            return cleaned(current, instrument, visibleInstruments: visibleInstruments, sort: nil) {
                $0.showingOnlyPercentile(percentile)
            }
        }
    }

    /// The web's `cleanFilters(s, inst)` plus a tile's own choice: clear the chart's
    /// four checks and the stars/percentile buckets, keep other charts' checks (hidden
    /// ones included, like the filter sheet) and the General filters, then add `choice`.
    ///
    /// A chart hidden since the tile was drawn gets no new, invisible choice: Songs
    /// shows every instrument, sorted by Title.
    ///
    /// - Parameters:
    ///   - current: Saved Songs state.
    ///   - instrument: The tile's chart.
    ///   - visibleInstruments: Settings-visible charts.
    ///   - sort: The preset's sort (ascending), or nil to keep the saved mode.
    ///   - choice: The tile's filter on the cleaned value.
    /// - Returns: The state to save.
    private func cleaned(
        _ current: SongsSavedState, _ instrument: Instrument, visibleInstruments: Set<Instrument>,
        sort: SongSortMode?, choice: (SongPlayerScoreFilter) -> SongPlayerScoreFilter
    ) -> SongsSavedState {
        var next = current
        let cleared = SongScoreFilterKind.allCases.reduce(current.playerFilter.clearingBuckets) {
            $0.setting($1, for: instrument, enabled: false)
        }
        guard visibleInstruments.contains(instrument) else {
            next.playerFilter = cleared
            next.instrument = nil
            next.sortMode = .title
            next.sortAscending = true
            return next
        }
        next.playerFilter = choice(cleared)
        next.instrument = instrument
        if let sort { next.sortMode = sort }
        next.sortAscending = true
        return next
    }
}

// MARK: - Link targets

/// What tapping a player-page stat tile does (the web `StatBox` `onClick`).
///
/// Every link on a viewed (not selected) player's page first selects that player,
/// confirming a switch when another player is selected (web `withProfileSwitch`).
public enum PlayerStatLink: Hashable, Sendable {
    /// Save a Songs filter, then show the Songs tab.
    case songs(SongsFilterPreset)
    /// Open Song Detail for the song behind a Best Rank tile.
    case songDetail(songId: String, instrument: Instrument)
    /// Open an instrument's full rankings (the web's per-metric rank tiles).
    case fullRankings(Instrument, rankBy: String)

    /// Whether the link is meaningless without the viewed player selected: a Songs
    /// filter reads the *selected* player's scores. Song Detail and rankings open even
    /// while selection is paused (unverified or changed publication).
    public var requiresSelection: Bool {
        if case .songs = self { return true }
        return false
    }
}

/// The web's stat-tile link table for the overview and per-instrument cards, limited
/// to targets the native app can open.
///
/// | Tile | Web target | Native |
/// |---|---|---|
/// | Overview Songs Played | Songs, `hasScores` on every visible chart | ``SongsFilterPreset/overall(_:visible:)`` |
/// | Overview Full Combos | Songs, `hasFCs` on every visible chart | ``SongsFilterPreset/overall(_:visible:)`` |
/// | Overview / instrument Best Rank | Song Detail (`?instrument=`) | ``PlayerStatLink/songDetail(songId:instrument:)`` |
/// | Instrument Songs Played / FCs | Songs, that chart, Score sort | ``SongsFilterPreset/instrument(_:_:)`` |
/// | Instrument Total Score Rank | Full rankings, Total Score | ``PlayerStatLink/fullRankings(_:rankBy:)`` |
/// | Gold / 5…1 Stars | Songs stars filter, Stars sort | ``SongsFilterPreset/stars(_:starKey:)`` |
/// | Percentile / Songs Played percentile | Songs Percentile sort (+ Has Scores) | ``SongsFilterPreset/percentile(_:scoredOnly:)`` |
/// | Percentile table row | Songs percentile bucket filter | ``SongsFilterPreset/percentileBucket(_:percentile:)`` |
public enum PlayerStatLinks {
    /// The web's un-experimental ranking metric (`DEFAULT_METRICS`).
    public static let defaultRankBy = "totalscore"

    /// Overview "Songs Played": always a link, like the web.
    ///
    /// - Parameter visible: Settings-visible charts.
    /// - Returns: The Songs filter link.
    public static func overallSongsPlayed(visible: Set<Instrument>) -> PlayerStatLink {
        .songs(.overall(.hasScores, visible: visible))
    }

    /// Overview "Full Combos": always a link, like the web.
    ///
    /// - Parameter visible: Settings-visible charts.
    /// - Returns: The Songs filter link.
    public static func overallFullCombos(visible: Set<Instrument>) -> PlayerStatLink {
        .songs(.overall(.hasFCs, visible: visible))
    }

    /// Overview "Best Rank": the best-ranked song on the chart it was set on.
    ///
    /// - Parameter stats: Overview aggregate.
    /// - Returns: A Song Detail link, or nil with no ranked score.
    public static func overallBestRank(_ stats: PlayerOverallStats) -> PlayerStatLink? {
        guard let songId = stats.bestRankSongId, let instrument = stats.bestRankInstrument else { return nil }
        return .songDetail(songId: songId, instrument: instrument)
    }

    /// Instrument "Songs Played" (shown only when non-zero).
    ///
    /// - Parameter instrument: Chart.
    /// - Returns: The Songs filter link.
    public static func instrumentSongsPlayed(_ instrument: Instrument) -> PlayerStatLink {
        .songs(.instrument(.hasScores, instrument))
    }

    /// Instrument "Full Combos" (shown only when non-zero, like the web's FCs card).
    ///
    /// - Parameter instrument: Chart.
    /// - Returns: The Songs filter link.
    public static func instrumentFullCombos(_ instrument: Instrument) -> PlayerStatLink {
        .songs(.instrument(.hasFCs, instrument))
    }

    /// Instrument Gold / 5…1 Stars tile (shown only when its count is non-zero).
    ///
    /// - Parameters:
    ///   - instrument: Chart.
    ///   - starKey: 6 for Gold Stars, else 5…1 (``PlayerStarBreakdown/countCards``).
    /// - Returns: The Songs filter link.
    public static func instrumentStars(_ instrument: Instrument, starKey: Int) -> PlayerStatLink {
        .songs(.stars(instrument, starKey: starKey))
    }

    /// Instrument "Percentile" tile, or with `scoredOnly` its "Songs Played" percentile
    /// tile (the web's average-percentile card).
    ///
    /// - Parameters:
    ///   - instrument: Chart.
    ///   - scoredOnly: Also require a score (web `instPercentileWithScoresUpdater`).
    /// - Returns: The Songs filter link.
    public static func instrumentPercentile(_ instrument: Instrument, scoredOnly: Bool = false) -> PlayerStatLink {
        .songs(.percentile(instrument, scoredOnly: scoredOnly))
    }

    /// A percentile table row (`PlayerPercentileRow`).
    ///
    /// - Parameters:
    ///   - instrument: Chart.
    ///   - percentile: The row's threshold (``SongPercentileBucket/thresholds``).
    /// - Returns: The Songs filter link.
    public static func percentileBucket(_ instrument: Instrument, percentile: Int) -> PlayerStatLink {
        .songs(.percentileBucket(instrument, percentile: percentile))
    }

    /// Instrument "Best Rank".
    ///
    /// - Parameter stats: That instrument's aggregate.
    /// - Returns: A Song Detail link, or nil with no ranked score.
    public static func instrumentBestRank(_ stats: PlayerInstrumentStats) -> PlayerStatLink? {
        stats.bestRankSongId.map { .songDetail(songId: $0, instrument: stats.instrument) }
    }

    /// Instrument "Global Rank" (web "Total Score Rank"): a link only for a real rank.
    ///
    /// - Parameters:
    ///   - instrument: Chart.
    ///   - rank: Total Score rank, or nil while unranked or loading.
    /// - Returns: A full-rankings link, or nil.
    public static func globalRank(_ instrument: Instrument, rank: Int?) -> PlayerStatLink? {
        guard let rank, rank > 0 else { return nil }
        return .fullRankings(instrument, rankBy: defaultRankBy)
    }
}

// MARK: - Stat grid columns

/// Column count for the player page's stat-tile grids: two on iPhone, three or four as
/// the card widens (an adaptive grid with a minimum tile width, clamped).
public enum StatGridColumns {
    /// Narrowest tile before another column is dropped.
    public static let minimumTileWidth: Double = 140
    /// Narrowest tile at accessibility text sizes: fewer, wider columns where three or four
    /// would fit (HIG Typography: "Reduce the number of text columns as size increases").
    /// At AX5 a 3-column iPad grid truncated "2 (66.6%)" even on two lines; iPhone keeps
    /// its two columns (``minimumColumns``).
    public static let accessibilityMinimumTileWidth: Double = 224
    /// Space between tiles, both axes.
    public static let spacing: Double = 8
    /// iPhone portrait always gets two columns, even at large Dynamic Type.
    public static let minimumColumns = 2
    /// Wider cards stop at four so tiles never shrink to a sliver of text.
    public static let maximumColumns = 4

    /// How many columns fit a card's content width.
    ///
    /// - Parameters:
    ///   - width: Content width inside the card, in points.
    ///   - minimumTileWidth: Narrowest tile; defaults to ``minimumTileWidth``.
    ///   - spacing: Gap between tiles; defaults to ``spacing``.
    /// - Returns: `2...4` columns.
    public static func count(
        forWidth width: Double, minimumTileWidth: Double = minimumTileWidth, spacing: Double = spacing
    ) -> Int {
        guard width.isFinite, width > 0 else { return minimumColumns }
        let fit = Int(((width + spacing) / (minimumTileWidth + spacing)).rounded(.down))
        return min(max(fit, minimumColumns), maximumColumns)
    }
}
