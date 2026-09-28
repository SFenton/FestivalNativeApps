import Foundation

/// One nonempty jump-to bucket for the right-edge Songs index scrubber.
///
/// Sections are built from an already-sorted song array by chunking on
/// consecutive key changes, so `id` is a stable position index rather than the
/// letter/year itself: the same `label` can legitimately recur in two separate,
/// non-adjacent chunks (see `SongSectionIndex.sections`), and `ForEach`/
/// `ScrollViewReader` both need a genuinely unique identifier per chunk.
public struct SongSection: Identifiable, Equatable, Sendable {
    public let id: Int
    /// Uppercase letter, "#" for non-letters, or a year string.
    public let label: String
    public let songs: [Song]
}

/// Compute a Contacts-style "drag to jump" index for sort modes where it reads
/// naturally: alphabetical for Title/Artist, numeric for Year. Duration, Item
/// Shop and score-based sorts have no meaningful section key, so callers should
/// animate the scrubber away when `sections` returns at most one bucket.
public enum SongSectionIndex {
    /// Group an already-sorted, already-filtered song list into jump sections.
    ///
    /// Chunks by **consecutive** key changes rather than by unique key: a title
    /// sorted by raw string (e.g. `"24K Magic"`) can land far from other titles
    /// that share its first *letter* once digits are skipped (e.g. `"Kryptonite"`).
    /// Merging by unique key would silently pull a later, unrelated `"K"` run
    /// into an earlier one and misplace real rows; chunking instead accepts an
    /// occasional extra one-song section (and an occasional repeated scrubber
    /// label) for such titles, never wrong grouping.
    ///
    /// - Parameters:
    ///   - songs: Songs in their final on-screen order (after search/filter/sort).
    ///   - mode: The active catalogue sort; only Title, Artist and Year group.
    /// - Returns: Nonempty, order-preserving sections; empty for other modes
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
        var result: [SongSection] = []
        var currentLabel: String?
        var currentSongs: [Song] = []
        for song in songs {
            let label = key(song)
            if label == currentLabel {
                currentSongs.append(song)
            } else {
                if let currentLabel {
                    result.append(SongSection(id: result.count, label: currentLabel, songs: currentSongs))
                }
                currentLabel = label
                currentSongs = [song]
            }
        }
        if let currentLabel {
            result.append(SongSection(id: result.count, label: currentLabel, songs: currentSongs))
        }
        return result
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
