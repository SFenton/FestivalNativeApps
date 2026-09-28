import Foundation

/// Catalogue and public-Shop sort modes that work without a selected profile.
public enum SongSortMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case title
    case artist
    case year
    case duration
    case shop

    public var id: String { rawValue }

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
    case lt2
    case twoToThree = "2to3"
    case threeToFour = "3to4"
    case fourToFive = "4to5"
    case gte5

    public var id: String { rawValue }

    /// Web's long bucket label, used as the quick-link title.
    public var label: String {
        switch self {
        case .unknown: "Unknown Duration"
        case .lt2: "<2m"
        case .twoToThree: "2-3m"
        case .threeToFour: "3-4m"
        case .fourToFive: "4-5m"
        case .gte5: "5m+"
        }
    }

    /// Classify a catalogue duration into its bucket.
    ///
    /// - Parameter seconds: `Song.durationSeconds`, or nil.
    /// - Returns: `.unknown` for a missing or nonpositive duration.
    public init(seconds: Int?) {
        guard let seconds, seconds > 0 else {
            self = .unknown
            return
        }
        if seconds < 120 { self = .lt2 }
        else if seconds < 180 { self = .twoToThree }
        else if seconds < 240 { self = .threeToFour }
        else if seconds < 300 { self = .fourToFive }
        else { self = .gte5 }
    }
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
    /// - Returns: New array in the requested order, leaving its input unchanged.
    /// - Throws: `FestivalAPIError.invalidShop` if Shop sorting has no validated feed.
    public static func sorted(
        _ songs: [Song], mode: SongSortMode, ascending: Bool,
        shopSongIds: Set<String>? = nil
    ) throws -> [Song] {
        guard mode != .shop || shopSongIds != nil else {
            throw FestivalAPIError.invalidShop
        }
        let membership = shopSongIds ?? []
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
