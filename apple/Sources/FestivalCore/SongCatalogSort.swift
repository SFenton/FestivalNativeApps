import Foundation

/// The four catalogue-only sort modes that work without a selected profile.
public enum SongSortMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case title
    case artist
    case year
    case duration

    public var id: String { rawValue }

    /// Name the available sort without implying profile/shop-only data exists.
    ///
    /// - Returns: User-facing native sort choice.
    public var label: String {
        switch self {
        case .title: "Title"
        case .artist: "Artist"
        case .year: "Year"
        case .duration: "Duration"
        }
    }
}

/// Sort only typed public catalogue fields, never inventing profile scores.
public enum SongCatalogSort {
    /// Order catalogue rows with the source's title tie-break and a stable ID.
    ///
    /// - Parameters:
    ///   - songs: Typed songs after search and instrument filtering.
    ///   - mode: Catalogue-only sorting field selected by the user.
    ///   - ascending: Reverse all fields and title ties when false.
    /// - Returns: New array in the requested order, leaving its input unchanged.
    public static func sorted(
        _ songs: [Song], mode: SongSortMode, ascending: Bool
    ) -> [Song] {
        songs.sorted { left, right in
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
            }
            let title = left.title.localizedCompare(right.title)
            let result = primary == .orderedSame ? title : primary
            if result == .orderedSame {
                return ascending ? left.songId < right.songId : left.songId > right.songId
            }
            return ascending ? result == .orderedAscending : result == .orderedDescending
        }
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
