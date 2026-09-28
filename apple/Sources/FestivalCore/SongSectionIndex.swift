import Foundation

/// One nonempty jump-to bucket for the right-edge Songs index scrubber.
///
/// Sections are built from an already-sorted song array, so grouping only needs
/// to notice when the section key changes; it never re-sorts its input.
public struct SongSection: Identifiable, Equatable, Sendable {
    /// Stable key: an uppercase letter, "#" for non-letters, or a year string.
    public let id: String
    /// Short scrubber label; currently identical to `id`.
    public var label: String { id }
    public let songs: [Song]
}

/// Compute a Contacts-style "drag to jump" index for sort modes where it reads
/// naturally: alphabetical for Title/Artist, numeric for Year. Duration, Item
/// Shop and score-based sorts have no meaningful section key, so callers should
/// animate the scrubber away when `sections` returns at most one bucket.
public enum SongSectionIndex {
    /// Group an already-sorted, already-filtered song list into jump sections.
    ///
    /// - Parameters:
    ///   - songs: Songs in their final on-screen order (after search/filter/sort).
    ///   - mode: The active catalogue sort; only Title, Artist and Year group.
    /// - Returns: Nonempty, first-seen-ordered sections; empty for other modes
    ///   or fewer than two songs.
    public static func sections(_ songs: [Song], mode: SongSortMode) -> [SongSection] {
        guard songs.count > 1 else { return [] }
        let key: (Song) -> String
        switch mode {
        case .title: key = { firstLetter($0.title) }
        case .artist: key = { firstLetter($0.artist) }
        case .year: key = { $0.year.map { String($0) } ?? "—" }
        case .duration, .shop: return []
        }
        var order: [String] = []
        var buckets: [String: [Song]] = [:]
        for song in songs {
            let bucketKey = key(song)
            if buckets[bucketKey] == nil {
                order.append(bucketKey)
                buckets[bucketKey] = []
            }
            buckets[bucketKey]?.append(song)
        }
        return order.map { SongSection(id: $0, songs: buckets[$0] ?? []) }
    }

    /// First letter of a title or artist, uppercased; "#" for anything else.
    ///
    /// - Parameter text: Raw catalogue string, possibly starting with punctuation.
    /// - Returns: A single-character bucket key, stable across locales' casing.
    private static func firstLetter(_ text: String) -> String {
        guard let scalar = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.first(where: CharacterSet.letters.contains)
        else {
            return "#"
        }
        return String(Character(scalar)).uppercased()
    }
}
