import Foundation

// MARK: - First-run demo songs

/// Chooses the real catalogue songs that first-run demos display, ported from the web's
/// `useDemoSongs` (Epic Games songs with artwork) and `useItemShopDemoSongs` (current Shop
/// songs first, then catalogue songs with artwork).
///
/// Demos never invent song titles: until the catalogue answers (or when it can't), they show
/// ``placeholders(count:)``, which views render redacted.
public enum FirstRunDemoSongs {
    /// Artist marker the web uses to pick neutral, first-party demo songs.
    public static let preferredArtistMarker = "Epic Games"

    /// Prefix of every placeholder `songId`; never a real catalogue identifier.
    static let placeholderPrefix = "fre-placeholder-"

    /// Pick up to `count` distinct catalogue songs with artwork for a demo.
    ///
    /// Order: songs whose IDs appear in `preferredIds` (in that order), then songs whose
    /// artist contains ``preferredArtistMarker``, then any other song with artwork. Within
    /// each group the catalogue order is kept, so the result is deterministic.
    ///
    /// - Parameters:
    ///   - catalog: Songs from the observed `/api/songs` response.
    ///   - count: Maximum number of songs to return; non-positive returns none.
    ///   - preferredIds: Song IDs to show first, e.g. current Item Shop songs.
    /// - Returns: At most `count` songs, each with a non-empty `albumArt`.
    public static func pick(from catalog: [Song], count: Int, preferring preferredIds: [String] = []) -> [Song] {
        guard count > 0 else { return [] }
        let withArt = catalog.filter { !($0.albumArt ?? "").isEmpty && !$0.isFirstRunPlaceholder }
        let byId = Dictionary(withArt.map { ($0.songId, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var result: [Song] = []
        func append(_ song: Song) {
            guard result.count < count, seen.insert(song.songId).inserted else { return }
            result.append(song)
        }
        for id in preferredIds {
            if let song = byId[id] { append(song) }
        }
        for song in withArt where song.artist.contains(preferredArtistMarker) { append(song) }
        for song in withArt { append(song) }
        return result
    }

    /// Neutral stand-ins shown while the catalogue loads or is unavailable.
    ///
    /// They carry no artist, year, duration or artwork, and their text exists only to size a
    /// redacted placeholder bar; views must render them redacted.
    ///
    /// - Parameter count: Number of placeholders; non-positive returns none.
    /// - Returns: `count` placeholder songs whose ``Song/isFirstRunPlaceholder`` is `true`.
    public static func placeholders(count: Int) -> [Song] {
        guard count > 0 else { return [] }
        let titles = ["Placeholder song title", "Placeholder title", "Placeholder song name"]
        let objects: [[String: Any]] = (0..<count).map { index in
            [
                "songId": "\(placeholderPrefix)\(index)",
                "title": titles[index % titles.count],
                "artist": "Placeholder artist",
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: objects),
              let songs = try? JSONDecoder().decode([Song].self, from: data) else { return [] }
        return songs
    }
}

extension Song {
    /// Whether this is a ``FirstRunDemoSongs/placeholders(count:)`` stand-in rather than a
    /// catalogue song.
    public var isFirstRunPlaceholder: Bool {
        songId.hasPrefix(FirstRunDemoSongs.placeholderPrefix)
    }
}
