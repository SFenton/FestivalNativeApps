import Foundation
import Testing
@testable import FestivalCore

// MARK: - Fixtures

private func song(_ id: String, artist: String = "Band", art: String? = "art/\(UUID()).jpg") throws -> Song {
    var record: [String: Any] = ["songId": id, "title": "Title \(id)", "artist": artist]
    if let art { record["albumArt"] = art }
    return try JSONDecoder().decode(Song.self, from: JSONSerialization.data(withJSONObject: record))
}

// MARK: - Picking

@Suite("FirstRunDemoSongs")
struct FirstRunDemoSongsTests {
    @Test("Epic Games songs with art come first, then other songs with art, in catalogue order")
    func prefersEpicGamesSongs() throws {
        let catalog = try [
            song("a"), song("b", artist: "Epic Games"), song("c", art: nil),
            song("d", artist: "Lennox & Epic Games"), song("e"),
        ]
        let picked = FirstRunDemoSongs.pick(from: catalog, count: 3)
        #expect(picked.map(\.songId) == ["b", "d", "a"])
    }

    @Test("Songs without artwork are never picked, even when that leaves fewer than requested")
    func requiresArtwork() throws {
        let catalog = try [song("a", art: nil), song("b", art: ""), song("c")]
        #expect(FirstRunDemoSongs.pick(from: catalog, count: 3).map(\.songId) == ["c"])
        #expect(FirstRunDemoSongs.pick(from: [], count: 3).isEmpty)
    }

    @Test("Preferred IDs (Item Shop) lead in their own order and are not repeated")
    func preferredIdsFirst() throws {
        let catalog = try [song("a", artist: "Epic Games"), song("b"), song("c"), song("d", art: nil)]
        let picked = FirstRunDemoSongs.pick(
            from: catalog, count: 4, preferring: ["c", "missing", "d", "c", "b"]
        )
        #expect(picked.map(\.songId) == ["c", "b", "a"])
    }

    @Test("Count bounds the result; non-positive counts return nothing")
    func countBounds() throws {
        let catalog = try (0..<10).map { try song("s\($0)") }
        #expect(FirstRunDemoSongs.pick(from: catalog, count: 4).count == 4)
        #expect(FirstRunDemoSongs.pick(from: catalog, count: 0).isEmpty)
        #expect(FirstRunDemoSongs.pick(from: catalog, count: -2).isEmpty)
    }

    @Test("Duplicate catalogue IDs appear once")
    func deduplicates() throws {
        let catalog = try [song("a"), song("a"), song("b")]
        #expect(FirstRunDemoSongs.pick(from: catalog, count: 3).map(\.songId) == ["a", "b"])
    }

    // MARK: Placeholders

    @Test("Placeholders carry no artwork or metadata and are flagged for redaction")
    func placeholders() {
        let placeholders = FirstRunDemoSongs.placeholders(count: 6)
        #expect(placeholders.count == 6)
        #expect(Set(placeholders.map(\.songId)).count == 6)
        #expect(placeholders.allSatisfy { $0.isFirstRunPlaceholder })
        #expect(placeholders.allSatisfy { $0.albumArt == nil && $0.year == nil && $0.durationSeconds == nil })
        #expect(FirstRunDemoSongs.placeholders(count: 0).isEmpty)
    }

    @Test("Catalogue songs are not placeholders, and placeholders are never picked")
    func placeholdersExcludedFromPick() throws {
        let catalogueSong = try song("a")
        #expect(!catalogueSong.isFirstRunPlaceholder)
        #expect(FirstRunDemoSongs.pick(from: FirstRunDemoSongs.placeholders(count: 3), count: 3).isEmpty)
    }
}
