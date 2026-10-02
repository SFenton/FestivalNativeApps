import Foundation

/// The Songs filter sheet's General section (web `FilterModal` General): Year,
/// Duration, Item Shop availability and Double Bass support.
///
/// These choices use only public catalogue/Shop metadata, so they are offered and
/// applied with or without a selected player and survive player deselection. Every
/// category defaults on; an excluded category hides its songs, and excluding every
/// category may honestly leave an empty list (web `useFilteredSongs`).
public struct SongGeneralFilter: Codable, Sendable, Equatable, Hashable {
    /// Saved-preference key of the bounded JSON form.
    public static let storageKey = "fst.songs.generalFilters"
    /// Older In Shop toggle, migrated to ``SongShopFilter/availableOnly`` once.
    public static let legacyInShopKey = "fst.songs.filterInShop"
    /// Older Leaving Tomorrow toggle, migrated to ``SongShopFilter/availableOnly`` once.
    public static let legacyLeavingTomorrowKey = "fst.songs.filterLeavingTomorrow"

    /// Release decades (first year, e.g. 1990) whose songs are hidden.
    public var excludedDecades: Set<Int>
    /// Whole-minute duration buckets (0 = under 1 minute, 10 = 10+) whose songs are hidden.
    public var excludedDurations: Set<Int>
    /// Item Shop availability, applied only while the Shop is shown in Settings.
    public var shop: SongShopFilter
    /// Include songs whose Pro Drums chart has double bass.
    public var doubleBassSupported: Bool
    /// Include songs whose Pro Drums chart has no double bass.
    public var doubleBassUnsupported: Bool

    /// Create a General filter; the default hides nothing.
    ///
    /// - Parameters:
    ///   - excludedDecades: Hidden release decades.
    ///   - excludedDurations: Hidden duration buckets.
    ///   - shop: Item Shop availability choice.
    ///   - doubleBassSupported: Include songs with double bass support.
    ///   - doubleBassUnsupported: Include songs without double bass support.
    public init(
        excludedDecades: Set<Int> = [], excludedDurations: Set<Int> = [],
        shop: SongShopFilter = SongShopFilter(),
        doubleBassSupported: Bool = true, doubleBassUnsupported: Bool = true
    ) {
        self.excludedDecades = excludedDecades
        self.excludedDurations = excludedDurations
        self.shop = shop
        self.doubleBassSupported = doubleBassSupported
        self.doubleBassUnsupported = doubleBassUnsupported
    }

    // MARK: - Buckets

    /// Largest duration bucket: the open-ended "10+ Minutes".
    public static let longestDurationBucket = 10

    /// The decade of a release year, represented by its first year.
    ///
    /// - Parameter year: `Song.year`, or nil.
    /// - Returns: `floor(year / 10) * 10`, or nil for missing or nonpositive years.
    public static func decade(forYear year: Int?) -> Int? {
        guard let year, year > 0 else { return nil }
        return year / 10 * 10
    }

    /// The whole-minute duration bucket of a song.
    ///
    /// - Parameter seconds: `Song.durationSeconds`, or nil.
    /// - Returns: Minutes capped at 10, or nil for missing or nonpositive durations.
    public static func durationBucket(forSeconds seconds: Int?) -> Int? {
        guard let seconds, seconds > 0 else { return nil }
        return min(longestDurationBucket, seconds / 60)
    }

    /// Decade options present in a catalogue, ascending (web `yearOptions`).
    ///
    /// - Parameter songs: Validated catalogue rows.
    /// - Returns: Distinct decades of songs with a known year.
    public static func decades(in songs: [Song]) -> [Int] {
        Set(songs.compactMap { decade(forYear: $0.year) }).sorted()
    }

    /// Duration options: always 0–9 minutes, plus 10+ when a song lasts 600 s or more
    /// (web `getDurationFilterBuckets`).
    ///
    /// - Parameter songs: Validated catalogue rows.
    /// - Returns: Ascending bucket identifiers.
    public static func durationBuckets(in songs: [Song]) -> [Int] {
        let hasLongSongs = songs.contains {
            durationBucket(forSeconds: $0.durationSeconds) == longestDurationBucket
        }
        let buckets = Array(0..<longestDurationBucket)
        return hasLongSongs ? buckets + [longestDurationBucket] : buckets
    }

    /// Year option label (web `filter.decadeOption`).
    ///
    /// - Parameter decade: First year of the decade.
    /// - Returns: For example "1990s".
    public static func decadeLabel(_ decade: Int) -> String { "\(decade)s" }

    /// Duration option label (web `filter.durationUnderMinute`/`durationMinutes`/`durationLong`).
    ///
    /// - Parameter bucket: Whole-minute bucket.
    /// - Returns: "Under 1 Minute", "3-4 Minutes" or "10+ Minutes".
    public static func durationLabel(_ bucket: Int) -> String {
        switch bucket {
        case ..<1: "Under 1 Minute"
        case longestDurationBucket...: "\(longestDurationBucket)+ Minutes"
        default: "\(bucket)-\(bucket + 1) Minutes"
        }
    }

    // MARK: - State

    /// Whether the Year choice hides any song (including songs without a year).
    public var restrictsYear: Bool { !excludedDecades.isEmpty }

    /// Whether the Duration choice hides any song (including songs without a duration).
    public var restrictsDuration: Bool { !excludedDurations.isEmpty }

    /// Whether the Double Bass choice hides any song.
    public var restrictsDoubleBass: Bool { !(doubleBassSupported && doubleBassUnsupported) }

    /// Whether Year, Duration or Double Bass hides any song.
    public var restrictsMetadata: Bool { restrictsYear || restrictsDuration || restrictsDoubleBass }

    /// Whether any General choice that currently applies hides songs.
    ///
    /// - Parameter shopVisible: Whether Settings shows the Item Shop.
    /// - Returns: True when the filter indicator should show.
    public func isActive(shopVisible: Bool) -> Bool {
        restrictsMetadata || (shopVisible && shop.isActive)
    }

    /// Whether any saved choice differs from the default, including a Shop choice
    /// paused while the Shop is hidden.
    public var isCustomized: Bool { self != Self() }

    // MARK: - Filtering

    /// Apply Year, Duration and Double Bass without changing row order. The Item Shop
    /// choice is applied separately through ``SongShopFilter/filtered(_:offersById:)``
    /// so it can pause on a publication mismatch.
    ///
    /// - Parameter songs: Catalogue rows in their current order.
    /// - Returns: Rows matching every metadata choice. A song with an unknown year,
    ///   duration or double bass value is hidden only once that choice restricts.
    public func filteredMetadata(_ songs: [Song]) -> [Song] {
        guard restrictsMetadata else { return songs }
        return songs.filter(matchesMetadata)
    }

    /// Whether one song passes Year, Duration and Double Bass.
    ///
    /// - Parameter song: A catalogue row.
    /// - Returns: False when any restricting choice excludes or cannot classify it.
    public func matchesMetadata(_ song: Song) -> Bool {
        if restrictsDoubleBass {
            let matches = (doubleBassSupported && song.doubleBassSupported == true)
                || (doubleBassUnsupported && song.doubleBassSupported == false)
            guard matches else { return false }
        }
        if restrictsYear {
            guard let decade = Self.decade(forYear: song.year),
                  !excludedDecades.contains(decade) else { return false }
        }
        if restrictsDuration {
            guard let bucket = Self.durationBucket(forSeconds: song.durationSeconds),
                  !excludedDurations.contains(bucket) else { return false }
        }
        return true
    }

    // MARK: - Saved preferences

    /// Most saved decades: far beyond any catalogue, small enough to bound the bytes.
    static let maxSavedDecades = 64

    /// Decode bounded saved choices, migrating the older Item Shop toggles once.
    ///
    /// - Parameters:
    ///   - data: Saved JSON, empty for the default.
    ///   - legacyInShop: The older In Shop toggle, read only when `data` is empty.
    ///   - legacyLeavingTomorrow: The older Leaving Tomorrow toggle, read only when `data` is empty.
    /// - Returns: A validated filter without mutating user preferences.
    /// - Throws: `FestivalAPIError.invalidSongFilter` for malformed or oversized bytes.
    public static func decodeSaved(
        _ data: Data, legacyInShop: Bool = false, legacyLeavingTomorrow: Bool = false
    ) throws -> Self {
        guard !data.isEmpty else {
            return legacyInShop || legacyLeavingTomorrow
                ? Self(shop: .availableOnly) : Self()
        }
        guard data.count <= 4_096 else { throw FestivalAPIError.invalidSongFilter }
        do {
            return try JSONDecoder().decode(Self.self, from: data)
        } catch {
            throw FestivalAPIError.invalidSongFilter
        }
    }

    /// Store sorted choices with stable keys, or no bytes for the default.
    ///
    /// - Returns: Deterministic JSON.
    /// - Throws: Encoder failure, which must leave applied Settings unchanged.
    public func encoded() throws -> Data {
        guard isCustomized else { return Data() }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(self)
    }

    private enum CodingKeys: String, CodingKey {
        case excludedDecades, excludedDurations, shopAvailable, shopUnavailable
        case doubleBassSupported, doubleBassUnsupported
    }

    /// Reject duplicate, out-of-range or oversized buckets instead of reducing them.
    ///
    /// - Parameter decoder: Bounded saved-preference JSON decoder.
    /// - Throws: Invalid arrays, buckets or flags.
    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        let decades = try fields.decodeIfPresent([Int].self, forKey: .excludedDecades) ?? []
        let durations = try fields.decodeIfPresent([Int].self, forKey: .excludedDurations) ?? []
        guard decades.count <= Self.maxSavedDecades,
              Set(decades).count == decades.count,
              decades.allSatisfy({ $0 >= 0 && $0 <= 9_990 && $0 % 10 == 0 }),
              Set(durations).count == durations.count,
              durations.allSatisfy((0...Self.longestDurationBucket).contains) else {
            throw FestivalAPIError.invalidSongFilter
        }
        self.init(
            excludedDecades: Set(decades), excludedDurations: Set(durations),
            shop: SongShopFilter(
                available: try fields.decodeIfPresent(Bool.self, forKey: .shopAvailable) ?? true,
                unavailable: try fields.decodeIfPresent(Bool.self, forKey: .shopUnavailable) ?? true
            ),
            doubleBassSupported: try fields.decodeIfPresent(
                Bool.self, forKey: .doubleBassSupported
            ) ?? true,
            doubleBassUnsupported: try fields.decodeIfPresent(
                Bool.self, forKey: .doubleBassUnsupported
            ) ?? true
        )
    }

    /// Encode sorted buckets and every flag for reproducible preferences.
    ///
    /// - Parameter encoder: Saved-preference JSON encoder.
    /// - Throws: A failure to serialize the typed choices.
    public func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(excludedDecades.sorted(), forKey: .excludedDecades)
        try fields.encode(excludedDurations.sorted(), forKey: .excludedDurations)
        try fields.encode(shop.available, forKey: .shopAvailable)
        try fields.encode(shop.unavailable, forKey: .shopUnavailable)
        try fields.encode(doubleBassSupported, forKey: .doubleBassSupported)
        try fields.encode(doubleBassUnsupported, forKey: .doubleBassUnsupported)
    }
}
