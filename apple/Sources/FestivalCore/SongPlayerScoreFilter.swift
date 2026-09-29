import Foundation

/// The source's four independent score and full-combo checks for each solo chart.
public enum SongScoreFilterKind: String, CaseIterable, Identifiable, Sendable {
    case missingScores
    case hasScores
    case missingFCs
    case hasFCs

    public var id: String { rawValue }
}

/// Selected-player song predicates persisted separately from public Shop filters.
public struct SongPlayerScoreFilter: Codable, Equatable, Sendable {
    public static let storageKey = "fst.songs.playerScoreFilters"

    public private(set) var missingScores: Set<Instrument>
    public private(set) var hasScores: Set<Instrument>
    public private(set) var missingFCs: Set<Instrument>
    public private(set) var hasFCs: Set<Instrument>
    /// Hidden star buckets (``SongStarsBucket/keys``) on the Songs instrument; empty
    /// shows every bucket (web `starsFilter` entries set to `false`).
    public private(set) var excludedStars: Set<Int>
    /// Hidden percentile buckets (``SongPercentileBucket/keys``) on the Songs
    /// instrument (web `percentileFilter` entries set to `false`).
    public private(set) var excludedPercentiles: Set<Int>

    private enum CodingKeys: String, CodingKey {
        case missingScores, hasScores, missingFCs, hasFCs, excludedStars, excludedPercentiles
    }

    /// Start with independent chart sets, including an inactive empty default.
    ///
    /// - Parameters:
    ///   - missingScores: Charted instruments requiring no positive score.
    ///   - hasScores: Charted instruments requiring a positive score.
    ///   - missingFCs: Charted instruments without an explicit full-combo flag.
    ///   - hasFCs: Charted instruments with an explicit full-combo flag.
    ///   - excludedStars: Hidden star buckets on the Songs instrument (unknown keys dropped).
    ///   - excludedPercentiles: Hidden percentile buckets on the Songs instrument
    ///     (unknown keys dropped).
    public init(
        missingScores: Set<Instrument> = [], hasScores: Set<Instrument> = [],
        missingFCs: Set<Instrument> = [], hasFCs: Set<Instrument> = [],
        excludedStars: Set<Int> = [], excludedPercentiles: Set<Int> = []
    ) {
        self.missingScores = missingScores
        self.hasScores = hasScores
        self.missingFCs = missingFCs
        self.hasFCs = hasFCs
        self.excludedStars = excludedStars.intersection(SongStarsBucket.keys)
        self.excludedPercentiles = excludedPercentiles.intersection(SongPercentileBucket.keys)
    }

    public var isActive: Bool {
        !missingScores.isEmpty || !hasScores.isEmpty
            || !missingFCs.isEmpty || !hasFCs.isEmpty
            || hasBucketChecks
    }

    /// Whether a stars or percentile bucket is hidden. These checks read the Songs
    /// instrument's score only, so they apply only while Songs shows one instrument
    /// (the web skips them without one, keeping the saved choice).
    public var hasBucketChecks: Bool {
        !excludedStars.isEmpty || !excludedPercentiles.isEmpty
    }

    // MARK: - Stars and percentile buckets

    /// Whether a star bucket is shown.
    ///
    /// - Parameter key: One of ``SongStarsBucket/keys``.
    /// - Returns: False once the bucket is hidden.
    public func includesStars(_ key: Int) -> Bool { !excludedStars.contains(key) }

    /// Whether a percentile bucket is shown.
    ///
    /// - Parameter key: One of ``SongPercentileBucket/keys``.
    /// - Returns: False once the bucket is hidden.
    public func includesPercentile(_ key: Int) -> Bool { !excludedPercentiles.contains(key) }

    /// Show or hide one star bucket.
    ///
    /// - Parameters:
    ///   - key: One of ``SongStarsBucket/keys``; other values are ignored.
    ///   - included: New value.
    /// - Returns: The updated filter.
    public func settingStars(_ key: Int, included: Bool) -> Self {
        guard SongStarsBucket.keys.contains(key) else { return self }
        var updated = self
        if included { updated.excludedStars.remove(key) } else { updated.excludedStars.insert(key) }
        return updated
    }

    /// Show or hide one percentile bucket.
    ///
    /// - Parameters:
    ///   - key: One of ``SongPercentileBucket/keys``; other values are ignored.
    ///   - included: New value.
    /// - Returns: The updated filter.
    public func settingPercentile(_ key: Int, included: Bool) -> Self {
        guard SongPercentileBucket.keys.contains(key) else { return self }
        var updated = self
        if included { updated.excludedPercentiles.remove(key) } else { updated.excludedPercentiles.insert(key) }
        return updated
    }

    /// The web's Select All / Clear All for the star buckets.
    ///
    /// - Parameter included: True shows every bucket, false hides every bucket.
    /// - Returns: The updated filter.
    public func settingAllStars(included: Bool) -> Self {
        var updated = self
        updated.excludedStars = included ? [] : Set(SongStarsBucket.keys)
        return updated
    }

    /// The web's Select All / Clear All for the percentile buckets.
    ///
    /// - Parameter included: True shows every bucket, false hides every bucket.
    /// - Returns: The updated filter.
    public func settingAllPercentiles(included: Bool) -> Self {
        var updated = self
        updated.excludedPercentiles = included ? [] : Set(SongPercentileBucket.keys)
        return updated
    }

    /// Show only one star bucket (web `buildStarFilter`), clearing the percentile buckets.
    ///
    /// - Parameter key: The star bucket to keep.
    /// - Returns: The updated filter.
    public func showingOnlyStars(_ key: Int) -> Self {
        var updated = self
        updated.excludedStars = Set(SongStarsBucket.keys).subtracting([key])
        return updated
    }

    /// Show only one percentile bucket (web `buildPercentileFilter`).
    ///
    /// - Parameter key: The percentile threshold to keep.
    /// - Returns: The updated filter.
    public func showingOnlyPercentile(_ key: Int) -> Self {
        var updated = self
        updated.excludedPercentiles = Set(SongPercentileBucket.keys).subtracting([key])
        return updated
    }

    /// The filter without any stars or percentile bucket choice (web `cleanFilters`).
    public var clearingBuckets: Self {
        var updated = self
        updated.excludedStars = []
        updated.excludedPercentiles = []
        return updated
    }

    /// Check one source toggle without conflating scored with full combo.
    ///
    /// - Parameters:
    ///   - kind: Score or full-combo requirement.
    ///   - instrument: Visible chart associated with the toggle.
    /// - Returns: Whether the specified condition is selected.
    public func contains(_ kind: SongScoreFilterKind, for instrument: Instrument) -> Bool {
        switch kind {
        case .missingScores: missingScores.contains(instrument)
        case .hasScores: hasScores.contains(instrument)
        case .missingFCs: missingFCs.contains(instrument)
        case .hasFCs: hasFCs.contains(instrument)
        }
    }

    /// Set a condition without silently disabling a potentially independent one.
    ///
    /// - Parameters:
    ///   - kind: Requirement to edit.
    ///   - instrument: A solo chart, whether currently shown or hidden in Settings.
    ///   - enabled: New draft value.
    /// - Returns: A new filter value leaving the other three sets unchanged.
    public func setting(
        _ kind: SongScoreFilterKind, for instrument: Instrument, enabled: Bool
    ) -> Self {
        var updated = self
        switch kind {
        case .missingScores:
            if enabled { updated.missingScores.insert(instrument) }
            else { updated.missingScores.remove(instrument) }
        case .hasScores:
            if enabled { updated.hasScores.insert(instrument) }
            else { updated.hasScores.remove(instrument) }
        case .missingFCs:
            if enabled { updated.missingFCs.insert(instrument) }
            else { updated.missingFCs.remove(instrument) }
        case .hasFCs:
            if enabled { updated.hasFCs.insert(instrument) }
            else { updated.hasFCs.remove(instrument) }
        }
        return updated
    }

    /// Match the source's global switch across only currently visible charts.
    ///
    /// - Parameters:
    ///   - kind: Global score or full-combo condition.
    ///   - visibleInstruments: Enabled solo charts in Settings.
    /// - Returns: Whether every visible chart has this condition.
    public func allVisible(
        _ kind: SongScoreFilterKind, visibleInstruments: Set<Instrument>
    ) -> Bool {
        !visibleInstruments.isEmpty
            && visibleInstruments.allSatisfy { contains(kind, for: $0) }
    }

    /// Apply a global draft change without erasing hidden saved chart choices.
    ///
    /// - Parameters:
    ///   - kind: Global score or full-combo requirement.
    ///   - visibleInstruments: Enabled solo charts in Settings.
    ///   - enabled: Whether to set or clear the condition.
    /// - Returns: Updated filter with only the visible chart choices changed.
    public func settingAll(
        _ kind: SongScoreFilterKind,
        visibleInstruments: Set<Instrument>, enabled: Bool
    ) -> Self {
        visibleInstruments.reduce(self) {
            $0.setting(kind, for: $1, enabled: enabled)
        }
    }

    /// Ignore saved hidden-chart checks until that chart becomes visible again.
    ///
    /// - Parameter visibleInstruments: Currently enabled Settings instruments.
    /// - Returns: Filter restricted to that set without mutating the saved choice.
    public func scoped(to visibleInstruments: Set<Instrument>) -> Self {
        Self(
            missingScores: missingScores.intersection(visibleInstruments),
            hasScores: hasScores.intersection(visibleInstruments),
            missingFCs: missingFCs.intersection(visibleInstruments),
            hasFCs: hasFCs.intersection(visibleInstruments),
            excludedStars: excludedStars,
            excludedPercentiles: excludedPercentiles
        )
    }

    /// Apply OR across charted instruments and AND within each chart's independent checks,
    /// then (with one Songs instrument) the stars and percentile buckets.
    ///
    /// - Parameters:
    ///   - songs: Search- and chart-filtered catalogue rows.
    ///   - scoresBySong: Available, matching-publication selected-player index; nil is unavailable.
    ///   - visibleInstruments: Settings-enabled solo charts.
    ///   - selectedInstrument: Optional active Songs chart filter.
    /// - Returns: Rows matching at least one active chart and every bucket check,
    ///   preserving source order.
    /// - Throws: `FestivalAPIError.invalidPlayerProfile` when active checks lack scores.
    public func filtered(
        _ songs: [Song],
        scoresBySong: [String: [Instrument: PlayerScore]]?,
        visibleInstruments: Set<Instrument>,
        selectedInstrument: Instrument?
    ) throws -> [Song] {
        let scoped = scoped(to: visibleInstruments)
        let charts = Instrument.allCases.filter { chart in
            (selectedInstrument == nil || selectedInstrument == chart)
                && (scoped.missingScores.contains(chart)
                    || scoped.hasScores.contains(chart)
                    || scoped.missingFCs.contains(chart)
                    || scoped.hasFCs.contains(chart))
        }
        // Bucket checks read one chart: only with a visible Songs instrument (web
        // `effectiveInstrument != null`).
        let bucketChart = hasBucketChecks
            ? selectedInstrument.flatMap { visibleInstruments.contains($0) ? $0 : nil } : nil
        guard !charts.isEmpty || bucketChart != nil else { return songs }
        guard let scoresBySong else { throw FestivalAPIError.invalidPlayerProfile }
        let chartMatched = charts.isEmpty ? songs : scoped.chartFiltered(songs, charts: charts, scoresBySong: scoresBySong)
        // The web also skips bucket checks for a player with no scores at all.
        guard let bucketChart, !scoresBySong.isEmpty else { return chartMatched }
        return chartMatched.filter { song in
            let score = scoresBySong[song.songId]?[bucketChart]
            return includesStars(SongStarsBucket.key(for: score))
                && includesPercentile(SongPercentileBucket.key(for: score))
        }
    }

    /// The four per-chart checks, OR across `charts`.
    ///
    /// - Parameters:
    ///   - songs: Rows to filter.
    ///   - charts: Charts with at least one active check.
    ///   - scoresBySong: Selected-player index.
    /// - Returns: Rows matching at least one chart.
    private func chartFiltered(
        _ songs: [Song], charts: [Instrument], scoresBySong: [String: [Instrument: PlayerScore]]
    ) -> [Song] {
        let scoped = self
        return songs.filter { song in
            charts.contains { chart in
                guard song.supports(chart) else { return false }
                let score = scoresBySong[song.songId]?[chart]
                let scored = (score?.score ?? 0) > 0
                let fullCombo = score?.isFullCombo == true
                let scoreChecks = scoped.missingScores.contains(chart)
                    || scoped.hasScores.contains(chart)
                let comboChecks = scoped.missingFCs.contains(chart)
                    || scoped.hasFCs.contains(chart)
                let scoreMatches = !scoreChecks
                    || (scoped.missingScores.contains(chart) && !scored)
                    || (scoped.hasScores.contains(chart) && scored)
                let comboMatches = !comboChecks
                    || (scoped.missingFCs.contains(chart) && !fullCombo)
                    || (scoped.hasFCs.contains(chart) && fullCombo)
                return scoreMatches && comboMatches
            }
        }
    }

    // MARK: - Saved preferences

    /// Decode only bounded, canonical chart names; corrupt preferences require explicit Reset.
    ///
    /// - Parameter data: Saved app-only filter JSON, empty for the default.
    /// - Returns: A validated, typed filter without mutating user preferences.
    /// - Throws: `FestivalAPIError.invalidSongFilter` for malformed or oversized bytes.
    public static func decodeSaved(_ data: Data) throws -> Self {
        guard !data.isEmpty else { return Self() }
        guard data.count <= 4_096 else { throw FestivalAPIError.invalidSongFilter }
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw FestivalAPIError.invalidSongFilter
        }
    }

    /// Store four chart sets in stable service order, or no bytes for defaults.
    ///
    /// - Returns: Valid JSON with sorted keys and deterministic chart arrays.
    /// - Throws: Encoder failure, which must leave applied Settings unchanged.
    public func encoded() throws -> Data {
        guard isActive else { return Data() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    /// Reject duplicate or unknown charts instead of silently reducing the saved predicates.
    ///
    /// - Parameter decoder: Bounded saved-preference JSON decoder.
    /// - Throws: Invalid arrays, chart identifiers or duplicate entries.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let missing = try fields.decode([Instrument].self, forKey: .missingScores)
        let scored = try fields.decode([Instrument].self, forKey: .hasScores)
        let missingCombo = try fields.decode([Instrument].self, forKey: .missingFCs)
        let combos = try fields.decode([Instrument].self, forKey: .hasFCs)
        // Added later (stars/percentile filters): absent in older saved filters.
        let stars = try fields.decodeIfPresent([Int].self, forKey: .excludedStars) ?? []
        let percentiles = try fields.decodeIfPresent([Int].self, forKey: .excludedPercentiles) ?? []
        guard Set(missing).count == missing.count,
              Set(scored).count == scored.count,
              Set(missingCombo).count == missingCombo.count,
              Set(combos).count == combos.count,
              Set(stars).count == stars.count,
              Set(percentiles).count == percentiles.count,
              stars.allSatisfy(SongStarsBucket.keys.contains),
              percentiles.allSatisfy(SongPercentileBucket.keys.contains) else {
            throw FestivalAPIError.invalidSongFilter
        }
        self.init(
            missingScores: Set(missing), hasScores: Set(scored),
            missingFCs: Set(missingCombo), hasFCs: Set(combos),
            excludedStars: Set(stars), excludedPercentiles: Set(percentiles)
        )
    }

    /// Encode only stable, validated service identifiers for reproducible preferences.
    ///
    /// - Parameter encoder: Saved-preference JSON encoder.
    /// - Throws: A failure to serialize the typed chart sets.
    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(Instrument.allCases.filter(missingScores.contains), forKey: .missingScores)
        try fields.encode(Instrument.allCases.filter(hasScores.contains), forKey: .hasScores)
        try fields.encode(Instrument.allCases.filter(missingFCs.contains), forKey: .missingFCs)
        try fields.encode(Instrument.allCases.filter(hasFCs.contains), forKey: .hasFCs)
        // Omitted when empty so filters without bucket choices keep their older bytes.
        if !excludedStars.isEmpty {
            try fields.encode(excludedStars.sorted(), forKey: .excludedStars)
        }
        if !excludedPercentiles.isEmpty {
            try fields.encode(excludedPercentiles.sorted(), forKey: .excludedPercentiles)
        }
    }
}
