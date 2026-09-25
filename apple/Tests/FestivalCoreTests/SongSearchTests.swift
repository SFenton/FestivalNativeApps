import Foundation
import Testing
@testable import FestivalCore

/// Source search normalizes separators and diacritics without hiding raw matches.
@Test(arguments: [
    ("beyonce", true),
    ("ac dc", true),
    ("dont", true),
    ("!!!", true),
    ("no such track", false),
])
func songSearchGoldenQueries(_ query: String, _ expected: Bool) throws {
    let song = try JSONDecoder().decode(
        Song.self,
        from: Data(#"{"songId":"golden","title":"Don't Stop","artist":"Beyoncé / AC/DC"}"#.utf8)
    )
    #expect(SongSearch.matches(song, query: query) == expected)
}

/// Collapse multiple separators once and never mistake an apostrophe for a space.
@Test func searchNormalizationKeepsWordBoundaries() {
    #expect(SongSearch.normalized("  Don't—Stop / AC/DC! ") == "dont stop ac dc")
    #expect(SongSearch.normalized("Beyoncé") == "beyonce")
}
