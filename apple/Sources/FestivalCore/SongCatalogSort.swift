import Foundation

/// Songs sort modes: catalogue and public-Shop modes that work without a selected
/// profile, then the web's selected-player modes for one instrument
/// (`INSTRUMENT_SORT_MODES`; only Score, Percentile and Stars are ported).
public enum SongSortMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case title
    case artist
    case year
    case duration
    case shop
    case score
    case percentile
    case stars

    public var id: String { rawValue }

    /// Modes offered without a selected instrument (web `sort.mode` section).
    public static let catalogueModes: [SongSortMode] = [.title, .artist, .year, .duration, .shop]

    /// Selected-player modes offered once Songs shows a single instrument (web
    /// "Filtered Instrument Sort Mode", in the web's order).
    public static let playerChartModes: [SongSortMode] = [.score, .percentile, .stars]

    /// Whether the mode orders rows by the selected player's score on one chart.
    public var isPlayerChartMode: Bool { Self.playerChartModes.contains(self) }

    /// Name the available sort without implying profile-only data exists.
    ///
    /// - Returns: User-facing native sort choice.
    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .year: "Year"
        case .duration: "Duration"
        case .shop: "Item Shop"
        case .score: "Score"
        case .percentile: "Percentile"
        case .stars: "Stars"
        }
    }
}

/// Source Shop quick-link buckets, ordered by their first song in the sorted list.
public enum SongShopSectionKind: String, Identifiable, Sendable {
    case leavingTomorrow = "leaving-tomorrow"
    case inShop = "in-shop"
    case notInShop = "not-in-shop"

    public var id: String { rawValue }
}

/// A nonempty Shop bucket whose songs preserve their relative sorted order.
public struct SongShopSection: Identifiable, Sendable {
    public let kind: SongShopSectionKind
    public internal(set) var songs: [Song]

    public var id: SongShopSectionKind { kind }
}

/// Duration quick-link buckets, ported from web `songQuickLinks.ts:193-202`.
public enum SongDurationBucket: String, Identifiable, CaseIterable, Sendable {
    case unknown
    case under1
    case oneToTwo = "1to2"
    case twoToThree = "2to3"
    case threeToFour = "3to4"
    case fourToFive = "4to5"
    case fiveToSix = "5to6"
    case sixToSeven = "6to7"
    case sevenToEight = "7to8"
    case eightToNine = "8to9"
    case nineToTen = "9to10"
    case over10

    public var id: String { rawValue }

    /// Section header and quick-link title. Operator decision (2026-09-28): one-minute
    /// buckets from "Under 1 Minute" to "Over 10 Minutes", instead of the web's
    /// `<2m`…`5m+` (`.agents/pages/songs/spec.md`, operator decisions).
    public var label: String {
        switch self {
        case .unknown: "Unknown Duration"
        case .under1: "Under 1 Minute"
        case .over10: "Over 10 Minutes"
        default:
            "\(lowerMinute)–\(lowerMinute + 1) Minutes"
        }
    }

    /// Whole minutes at the bucket's lower bound (1 for `1to2`); 0 for the edge buckets.
    private var lowerMinute: Int {
        Self.allCases.firstIndex(of: self).map { max(0, $0 - 1) } ?? 0
    }

    /// Classify a catalogue duration into its bucket.
    ///
    /// - Parameter seconds: `Song.durationSeconds`, or nil.
    /// - Returns: `.unknown` for a missing or nonpositive duration; `.over10` from 600 s.
    public init(seconds: Int?) {
        guard let seconds, seconds > 0 else {
            self = .unknown
            return
        }
        let minutes = seconds / 60
        if minutes >= 10 {
            self = .over10
        } else {
            // allCases: unknown, under1, 1to2 … 9to10 → index minutes + 1.
            self = Self.allCases[minutes + 1]
        }
    }
}

/// A Year section: a decade ("1970s") or "Unknown Year" (web `songQuickLinks.ts:184-190`).
public struct SongYearSection: Identifiable, Sendable {
    /// Decade start (1970), or nil for a missing year.
    public let decade: Int?
    public internal(set) var songs: [Song]

    /// Stable id ("1970" or "unknown"), also the quick-link id suffix.
    public var id: String { decade.map(String.init) ?? "unknown" }

    /// Header and quick-link title.
    public var label: String { decade.map { "\($0)s" } ?? "Unknown Year" }
}

/// A nonempty Duration bucket whose songs preserve their relative sorted order.
public struct SongDurationSection: Identifiable, Sendable {
    public let bucket: SongDurationBucket
    public internal(set) var songs: [Song]

    public var id: SongDurationBucket { bucket }
}

/// Sort typed catalogue fields and validated public Shop membership, never profile scores.
public enum SongCatalogSort {
    /// Order catalogue rows with source ties and a stable ID for otherwise equal songs.
    ///
    /// - Parameters:
    ///   - songs: Typed songs after search and instrument filtering.
    ///   - mode: Public catalogue or Item Shop sorting field selected by the user.
    ///   - ascending: Reverse all fields and title ties when false.
    ///   - shopSongIds: Validated public Shop membership, required for `.shop` even when empty.
    ///   - chartScores: The selected player's scores on the Songs instrument, by song ID,
    ///     from an available score index matching the catalogue; required for the
    ///     player modes (``SongSortMode/isPlayerChartMode``) even when empty.
    /// - Returns: New array in the requested order, leaving its input unchanged.
    /// - Throws: `FestivalAPIError.invalidShop` if Shop sorting has no validated feed;
    ///   `FestivalAPIError.invalidPlayerProfile` if a player mode has no score index.
    public static func sorted(
        _ songs: [Song], mode: SongSortMode, ascending: Bool,
        shopSongIds: Set<String>? = nil,
        chartScores: [String: PlayerScore]? = nil
    ) throws -> [Song] {
        guard mode != .shop || shopSongIds != nil else {
            throw FestivalAPIError.invalidShop
        }
        guard !mode.isPlayerChartMode || chartScores != nil else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        let membership = shopSongIds ?? []
        let scores = chartScores ?? [:]
        return songs.sorted { left, right in
            let primary: ComparisonResult
            switch mode {
            case .title:
                primary = left.title.localizedCompare(right.title)
            case .artist:
                primary = left.artist.localizedCompare(right.artist)
            case .year:
                primary = compare(left.year ?? 0, right.year ?? 0)
            case .duration:
                primary = compare(left.durationSeconds ?? 0, right.durationSeconds ?? 0)
            case .shop:
                primary = compare(
                    membership.contains(right.songId) ? 1 : 0,
                    membership.contains(left.songId) ? 1 : 0
                )
            case .score, .percentile, .stars:
                primary = SongScoreSortKey.compare(
                    scores[left.songId], scores[right.songId], mode: mode
                )
            }
            let title = left.title.localizedCompare(right.title)
            let result: ComparisonResult
            if primary != .orderedSame {
                result = primary
            } else if title != .orderedSame || mode != .shop {
                result = title
            } else {
                let artist = left.artist.localizedCompare(right.artist)
                result = artist == .orderedSame
                    ? compare(left.year ?? 0, right.year ?? 0) : artist
            }
            if result == .orderedSame {
                return ascending ? left.songId < right.songId : left.songId > right.songId
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
    }

    /// Group sorted Shop rows as the source's first-seen quick-link buckets.
    ///
    /// - Parameters:
    ///   - sortedSongs: Catalogue songs already ordered by `.shop` and direction.
    ///   - offersById: Offers from a validated Shop response, including Leaving Tomorrow.
    /// - Returns: Nonempty buckets in first-seen order; one bucket needs no visible header.
    public static func shopSections(
        _ sortedSongs: [Song], offersById: [String: ShopSong]
    ) -> [SongShopSection] {
        var sections: [SongShopSection] = []
        for song in sortedSongs {
            let kind: SongShopSectionKind
            if let offer = offersById[song.songId] {
                kind = offer.leavingTomorrow ? .leavingTomorrow : .inShop
            } else {
                kind = .notInShop
            }
            if let index = sections.firstIndex(where: { $0.kind == kind }) {
                sections[index].songs.append(song)
            } else {
                sections.append(SongShopSection(kind: kind, songs: [song]))
            }
        }
        return sections
    }

    /// Group sorted Duration rows into the source's quick-link buckets.
    ///
    /// - Parameter sortedSongs: Catalogue songs already ordered by `.duration`.
    /// - Returns: Nonempty buckets in first-seen order; ascending duration keeps
    ///   `.unknown` (sorted as zero) first, descending keeps it last.
    public static func durationSections(_ sortedSongs: [Song]) -> [SongDurationSection] {
        var sections: [SongDurationSection] = []
        for song in sortedSongs {
            let bucket = SongDurationBucket(seconds: song.durationSeconds)
            if let index = sections.firstIndex(where: { $0.bucket == bucket }) {
                sections[index].songs.append(song)
            } else {
                sections.append(SongDurationSection(bucket: bucket, songs: [song]))
            }
        }
        return sections
    }

    /// Group sorted Year rows into decades plus "Unknown Year" (web quick-link buckets).
    ///
    /// - Parameter sortedSongs: Catalogue songs already ordered by `.year`.
    /// - Returns: Nonempty decades in first-seen order.
    public static func yearSections(_ sortedSongs: [Song]) -> [SongYearSection] {
        var sections: [SongYearSection] = []
        for song in sortedSongs {
            let decade = song.year.flatMap { $0 > 0 ? ($0 / 10) * 10 : nil }
            if let index = sections.firstIndex(where: { $0.decade == decade }) {
                sections[index].songs.append(song)
            } else {
                sections.append(SongYearSection(decade: decade, songs: [song]))
            }
        }
        return sections
    }

    /// Group rows sorted by a player mode into the web's quick-link buckets
    /// (`songQuickLinks.ts` `getScoreBucket` / `getPercentileBucket` / `getStarsBucket`).
    ///
    /// - Parameters:
    ///   - sortedSongs: Songs already ordered by `mode`.
    ///   - mode: ``SongSortMode/score``, ``SongSortMode/percentile`` or ``SongSortMode/stars``.
    ///   - chartScores: The same score map the sort used.
    /// - Returns: Nonempty buckets in first-seen order; empty for other modes.
    public static func scoreSections(
        _ sortedSongs: [Song], mode: SongSortMode, chartScores: [String: PlayerScore]
    ) -> [SongScoreSection] {
        guard mode.isPlayerChartMode else { return [] }
        var sections: [SongScoreSection] = []
        for song in sortedSongs {
            let bucket = SongScoreSection.bucket(for: chartScores[song.songId], mode: mode)
            if let index = sections.firstIndex(where: { $0.key == bucket.key }) {
                sections[index].songs.append(song)
            } else {
                sections.append(SongScoreSection(
                    key: bucket.key, label: bucket.label, spokenLabel: bucket.spoken, songs: [song]
                ))
            }
        }
        return sections
    }

    /// Compare numeric values without locale-dependent string conversion.
    ///
    /// - Parameters:
    ///   - left: First year or song duration.
    ///   - right: Second year or song duration.
    /// - Returns: Numeric comparison order.
    private static func compare(_ left: Int, _ right: Int) -> ComparisonResult {
        if left == right { return .orderedSame }
        return left < right ? .orderedAscending : .orderedDescending
    }
}
