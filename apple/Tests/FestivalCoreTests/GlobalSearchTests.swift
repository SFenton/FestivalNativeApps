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

// MARK: - Empty state (issue #99)

/// Each searched scope gets a title and the contract subtitle, without Retry (issue
/// #299); Bands and short queries have none.
@Test func emptyStateCopyPerScope() throws {
    let players = try #require(GlobalSearch.emptyState(scope: .players, query: "  The "))
    #expect(players.title == "No Players Found")
    #expect(players.subtitle == "Check the spelling or try a different player name.")
    #expect(players.accessibilityLabel
            == "No Players Found. Check the spelling or try a different player name.")

    let songs = try #require(GlobalSearch.emptyState(scope: .songs, query: "zz"))
    #expect(songs.title == "No Songs Found")
    #expect(songs.subtitle == "Check the spelling or try a different song or artist.")
    #expect(songs.accessibilityLabel == "No Songs Found. \(songs.subtitle)")

    let all = try #require(GlobalSearch.emptyState(scope: .all, query: "zz"))
    #expect(all.title == "No Results Found")
    #expect(all.subtitle == "Check the spelling or try a different song, artist or player.")
    #expect(!all.accessibilityLabel.contains("Retry"))

    #expect(GlobalSearch.emptyState(scope: .bands, query: "zz") == nil)
    #expect(GlobalSearch.emptyState(scope: .players, query: " a ") == nil)
}

// MARK: - Issue #299

/// The short-query hint names what each scope searches.
@Test func enterQueryHintNamesTheScope() {
    #expect(GlobalSearch.enterQueryHint(for: .all)
            == "Enter at least two characters to search for songs, players, or bands.")
    #expect(GlobalSearch.enterQueryHint(for: .songs) == "Enter at least two characters to search for songs.")
    #expect(GlobalSearch.enterQueryHint(for: .players) == "Enter at least two characters to search for players.")
    #expect(GlobalSearch.enterQueryHint(for: .bands) == "Enter at least two characters to search for bands.")
    #expect(Set(GlobalSearchScope.allCases.map(GlobalSearch.enterQueryHint(for:))).count == 4)
}

/// A failed section without a heading names what failed.
@Test func unavailableTitleNamesTheSection() {
    #expect(GlobalSearch.unavailableTitle(for: .songs) == "Songs unavailable")
    #expect(GlobalSearch.unavailableTitle(for: .players) == "Players unavailable")
}

/// One spinner: All waits for both sections, Songs never waits for Players, Players
/// waits only for players, Bands never spins.
@Test func isSearchingWaitsForEveryShownSection() {
    typealias Outcome = GlobalSearch.SectionOutcome
    #expect(GlobalSearch.isSearching(scope: .all, songs: .found(3), players: .pending))
    #expect(GlobalSearch.isSearching(scope: .all, songs: .pending, players: .found(0)))
    #expect(!GlobalSearch.isSearching(scope: .all, songs: .found(3), players: .failed))
    #expect(!GlobalSearch.isSearching(scope: .songs, songs: .found(3), players: .pending))
    #expect(GlobalSearch.isSearching(scope: .songs, songs: .pending, players: .found(1)))
    #expect(GlobalSearch.isSearching(scope: .players, songs: .found(3), players: .pending))
    #expect(!GlobalSearch.isSearching(scope: .players, songs: .pending, players: .found(0)))
    #expect(!GlobalSearch.isSearching(scope: .bands, songs: Outcome.pending, players: .pending))
}

/// Keyboard Search re-runs only a shown failed section or an empty player search.
@Test func submitRerunsFailedOrEmptySearches() {
    #expect(GlobalSearch.submitReruns(scope: .players, songs: .found(2), players: .found(0)))
    #expect(GlobalSearch.submitReruns(scope: .players, songs: .found(2), players: .failed))
    #expect(!GlobalSearch.submitReruns(scope: .players, songs: .failed, players: .found(2)))
    #expect(!GlobalSearch.submitReruns(scope: .players, songs: .found(0), players: .pending))
    #expect(GlobalSearch.submitReruns(scope: .songs, songs: .failed, players: .found(2)))
    #expect(!GlobalSearch.submitReruns(scope: .songs, songs: .found(0), players: .found(0)))
    #expect(GlobalSearch.submitReruns(scope: .all, songs: .found(2), players: .found(0)))
    #expect(!GlobalSearch.submitReruns(scope: .all, songs: .found(2), players: .found(1)))
    #expect(!GlobalSearch.submitReruns(scope: .bands, songs: .failed, players: .failed))
}
