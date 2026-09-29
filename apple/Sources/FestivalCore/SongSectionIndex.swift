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
/// naturally: alphabetical for Title/Artist. Year (decades), Duration, Item
/// Shop and score-based sorts use Quick Links instead, so callers should
/// animate the scrubber away when `sections` returns at most one bucket.
public enum SongSectionIndex {
    /// Group an already-sorted, already-filtered song list into jump sections.
    ///
    /// Chunks by **consecutive** key changes rather than by unique key. Native
    /// Contacts-style labeling (see `firstLetter`) already keeps every
    /// non-letter-leading title in one shared "#" bucket that sorts first, so
    /// this mainly guards against any future label scheme, or a stray locale
    /// tie, putting the same label in two places: merging by unique key would
    /// silently pull a later, unrelated run into an earlier one and misplace
    /// real rows, where chunking instead accepts an occasional extra section
    /// (and an occasional repeated scrubber label), never wrong grouping.
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
        // Year uses decade sections and Quick Links instead (operator, 2026-09-28).
        case .year, .duration, .shop: return []
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

    /// Native Contacts-style bucket key: the diacritic-folded first character
    /// when it is A–Z, otherwise a single shared "#" bucket.
    ///
    /// Never skips ahead past leading punctuation or digits to find "a real
    /// letter" deeper in the string: doing that put a title's section under a
    /// letter unrelated to where it actually sorts (`"24K Magic"` sorting to
    /// the front of the list but labeled "K", stranding it away from other
    /// K-titled songs). Every non-letter-leading title instead shares one "#"
    /// bucket, matching how the sort already puts them all before "A" — so
    /// they land in one contiguous run, not scattered ones.
    ///
    /// - Parameter text: Raw catalogue string, possibly starting with
    ///   punctuation, a digit or an accented letter (e.g. "Öyster" → "O").
    /// - Returns: A single uppercase ASCII letter, or "#".
    private static func firstLetter(_ text: String) -> String {
        guard let first = text.trimmingCharacters(in: .whitespacesAndNewlines).first else {
            return "#"
        }
        let folded = String(first).folding(options: .diacriticInsensitive, locale: nil)
        guard let scalar = folded.uppercased().unicodeScalars.first,
              scalar.isASCII, ("A"..."Z").contains(scalar)
        else {
            return "#"
        }
        return String(scalar)
    }
}
