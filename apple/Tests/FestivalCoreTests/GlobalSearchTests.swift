import Foundation
import Testing
@testable import FestivalCore

/// Decode a minimal catalogue row.
private func song(_ id: String, _ title: String, _ artist: String) throws -> Song {
    try JSONDecoder().decode(
        Song.self,
        from: Data(#"{"songId":"\#(id)","title":"\#(title)","artist":"\#(artist)"}"#.utf8)
    )
}

/// Below two trimmed characters nothing is searched (web `useUnifiedSearch`).
@Test(arguments: [
    ("", nil), (" ", nil), ("a", nil), (" a ", nil), ("ab", "ab"), ("  love  ", "love"),
] as [(String, String?)])
func globalSearchEffectiveQuery(_ raw: String, _ expected: String?) {
    #expect(GlobalSearch.effectiveQuery(raw) == expected)
}

/// Songs keep catalogue order (no ranking), match title or artist, and stop at the limit.
@Test func globalSearchSongsKeepCatalogueOrderAndLimit() throws {
    let catalogue = [
        try song("a", "Love Me", "Lil Tecca"),
        try song("b", "Bazooka", "Miami XO"),
        try song("c", "Loser", "Beck"),
        try song("d", "Glove Box", "Band"),
        try song("e", "Anything", "Courtney Love"),
    ]
    #expect(GlobalSearch.songs(in: catalogue, matching: "love").map(\.songId) == ["a", "d", "e"])
    #expect(GlobalSearch.songs(in: catalogue, matching: "love", limit: 2).map(\.songId) == ["a", "d"])
    #expect(GlobalSearch.songs(in: catalogue, matching: "l").isEmpty)
    #expect(GlobalSearch.songs(in: catalogue, matching: "zz").isEmpty)
}

/// "All" shows the live sections in the web's order; a single scope shows only itself.
@Test func globalSearchScopeSections() {
    #expect(GlobalSearchScope.all.sections == [.songs, .players])
    #expect(GlobalSearchScope.bands.sections == [.bands])
    #expect(GlobalSearchScope.players.sections == [.players])
    #expect(GlobalSearchScope.allCases.map(\.title) == ["All", "Songs", "Players", "Bands"])
}

/// Prompts mirror the web placeholders for the scopes in play.
@Test func globalSearchPrompts() {
    #expect(GlobalSearch.prompt(for: .all) == "Search songs or players")
    #expect(GlobalSearch.prompt(for: .bands) == "Search bands")
    #expect(GlobalSearch.songLimit == 20)
    #expect(GlobalSearch.playerLimit == 10)
}

// MARK: - Result-count announcement

@Test func resultAnnouncementWaitsForSettledSectionsAndCountsThem() {
    typealias Outcome = GlobalSearch.SectionOutcome
    #expect(GlobalSearch.resultAnnouncement(scope: .all, songs: .found(3), players: .pending) == nil)
    #expect(GlobalSearch.resultAnnouncement(scope: .all, songs: .found(3), players: .found(1))
            == "3 songs, 1 player")
    #expect(GlobalSearch.resultAnnouncement(scope: .all, songs: .found(0), players: .found(0))
            == "No results found.")
    #expect(GlobalSearch.resultAnnouncement(scope: .all, songs: .found(1), players: .failed)
            == "1 song, Players unavailable")
    #expect(GlobalSearch.resultAnnouncement(scope: .songs, songs: .found(0), players: .pending)
            == "No songs found.")
    #expect(GlobalSearch.resultAnnouncement(scope: .songs, songs: .found(2), players: .pending) == "2 songs")
    #expect(GlobalSearch.resultAnnouncement(scope: .players, songs: .pending, players: .found(0))
            == "No players found.")
    #expect(GlobalSearch.resultAnnouncement(scope: .players, songs: .found(4), players: .pending) == nil)
    #expect(GlobalSearch.resultAnnouncement(scope: .bands, songs: Outcome.found(1), players: .found(1)) == nil)
}
