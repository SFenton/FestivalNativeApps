import Foundation

/// Website-equivalent song-title/artist matching without locale-dependent sort.
public enum SongSearch {
    /// Match raw text first, then normalized accents and word separators.
    ///
    /// - Parameters:
    ///   - song: Catalogue row to inspect.
    ///   - query: User-entered search string.
    /// - Returns: True if title or artist contains the query on either scale.
    public static func matches(_ song: Song, query: String) -> Bool {
        let raw = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if raw.isEmpty
            || song.title.lowercased().contains(raw)
            || song.artist.lowercased().contains(raw) {
            return true
        }
        let normalizedQuery = normalized(query)
        if normalizedQuery.isEmpty { return true }
        return normalized(song.title).contains(normalizedQuery)
            || normalized(song.artist).contains(normalizedQuery)
    }

    /// Apply the PWA's NFKD, combining-mark, apostrophe and separator rules.
    ///
    /// - Parameter value: Song title, artist or query text.
    /// - Returns: Collapsed, lowercase text with matching word boundaries.
    public static func normalized(_ value: String) -> String {
        let apostrophes = CharacterSet(charactersIn: "'\u{2018}\u{2019}`\u{00B4}")
        let separators = CharacterSet.whitespacesAndNewlines.union(
            CharacterSet(charactersIn: "()[]{}\"\u{201C}\u{201D}.,:;!?_-\u{2013}\u{2014}/\\")
        )
        var output = ""
        for scalar in value.decomposedStringWithCompatibilityMapping.lowercased().unicodeScalars {
            if (0x0300...0x036F).contains(scalar.value) || apostrophes.contains(scalar) {
                continue
            }
            if separators.contains(scalar) {
                if !output.isEmpty && output.last != " " { output.append(" ") }
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
