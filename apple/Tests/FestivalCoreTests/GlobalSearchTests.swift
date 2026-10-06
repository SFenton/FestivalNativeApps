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

/// "All" shows every section in the web's order; a single scope shows only itself.
@Test func globalSearchScopeSections() {
    #expect(GlobalSearchScope.all.sections == [.songs, .players, .bands])
    #expect(GlobalSearchScope.bands.sections == [.bands])
    #expect(GlobalSearchScope.players.sections == [.players])
    #expect(GlobalSearchScope.allCases.map(\.title) == ["All", "Songs", "Players", "Bands"])
}

/// Prompts mirror the web placeholders for the scopes in play.
@Test func globalSearchPrompts() {
    #expect(GlobalSearch.prompt(for: .all) == "Search songs, players, or bands")
    #expect(GlobalSearch.prompt(for: .bands) == "Search bands")
    #expect(GlobalSearch.songLimit == 20)
    #expect(GlobalSearch.playerLimit == 10)
    #expect(GlobalSearch.bandLimit == 10)
}

// MARK: - Result-count announcement

@Test func resultAnnouncementWaitsForSettledSectionsAndCountsThem() {
    typealias Outcome = GlobalSearch.SectionOutcome
    func say(_ scope: GlobalSearchScope, _ songs: Outcome, _ players: Outcome, _ bands: Outcome) -> String? {
        GlobalSearch.resultAnnouncement(
            scope: scope, outcomes: .init(songs: songs, players: players, bands: bands)
        )
    }
    #expect(say(.all, .found(3), .pending, .found(1)) == nil)
    #expect(say(.all, .found(3), .found(1), .pending) == nil)
    #expect(say(.all, .found(3), .found(1), .found(2)) == "3 songs, 1 player, 2 bands")
    #expect(say(.all, .found(0), .found(0), .found(0)) == "No results found.")
    #expect(say(.all, .found(1), .failed, .found(1)) == "1 song, Players unavailable, 1 band")
    #expect(say(.all, .found(1), .found(0), .failed) == "1 song, 0 players, Bands unavailable")
    #expect(say(.songs, .found(0), .pending, .pending) == "No songs found.")
    #expect(say(.songs, .found(2), .pending, .pending) == "2 songs")
    #expect(say(.players, .pending, .found(0), .pending) == "No players found.")
    #expect(say(.players, .found(4), .pending, .found(1)) == nil)
    #expect(say(.bands, .pending, .pending, .found(0)) == "No bands found.")
    #expect(say(.bands, .found(1), .found(1), .found(1)) == "1 band")
    #expect(say(.bands, .found(1), .found(1), .failed) == "Bands unavailable")
    #expect(say(.bands, .found(1), .found(1), .pending) == nil)
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
    #expect(all.subtitle == "Check the spelling or try a different song, artist, player or band.")
    #expect(!all.accessibilityLabel.contains("Retry"))

    let bands = try #require(GlobalSearch.emptyState(scope: .bands, query: "zz"))
    #expect(bands.title == "No Bands Found")
    #expect(bands.subtitle == "Check the spelling or try a different band member's name.")
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
    #expect(GlobalSearch.unavailableTitle(for: .bands) == "Bands unavailable")
}

/// One spinner: All waits for every section, Songs never waits for the network, and
/// Players and Bands each wait only for themselves.
@Test func isSearchingWaitsForEveryShownSection() {
    typealias Outcome = GlobalSearch.SectionOutcome
    func spins(_ scope: GlobalSearchScope, _ songs: Outcome, _ players: Outcome, _ bands: Outcome) -> Bool {
        GlobalSearch.isSearching(scope: scope, outcomes: .init(songs: songs, players: players, bands: bands))
    }
    #expect(spins(.all, .found(3), .pending, .found(1)))
    #expect(spins(.all, .pending, .found(0), .found(0)))
    #expect(spins(.all, .found(3), .found(0), .pending))
    #expect(!spins(.all, .found(3), .failed, .failed))
    #expect(!spins(.songs, .found(3), .pending, .pending))
    #expect(spins(.songs, .pending, .found(1), .found(1)))
    #expect(spins(.players, .found(3), .pending, .found(1)))
    #expect(!spins(.players, .pending, .found(0), .pending))
    #expect(spins(.bands, .found(3), .found(1), .pending))
    #expect(!spins(.bands, .pending, .pending, .found(0)))
}

/// Keyboard Search re-runs only a shown failed section or an empty player/band search.
@Test func submitRerunsFailedOrEmptySearches() {
    typealias Outcome = GlobalSearch.SectionOutcome
    func reruns(_ scope: GlobalSearchScope, _ songs: Outcome, _ players: Outcome, _ bands: Outcome) -> Bool {
        GlobalSearch.submitReruns(scope: scope, outcomes: .init(songs: songs, players: players, bands: bands))
    }
    #expect(reruns(.players, .found(2), .found(0), .found(1)))
    #expect(reruns(.players, .found(2), .failed, .found(1)))
    #expect(!reruns(.players, .failed, .found(2), .failed))
    #expect(!reruns(.players, .found(0), .pending, .found(0)))
    #expect(reruns(.songs, .failed, .found(2), .found(2)))
    #expect(!reruns(.songs, .found(0), .found(0), .found(0)))
    #expect(reruns(.all, .found(2), .found(0), .found(1)))
    #expect(reruns(.all, .found(2), .found(1), .found(0)))
    #expect(reruns(.all, .found(2), .found(1), .failed))
    #expect(!reruns(.all, .found(2), .found(1), .found(1)))
    #expect(reruns(.bands, .found(2), .found(2), .found(0)))
    #expect(reruns(.bands, .found(2), .found(2), .failed))
    #expect(!reruns(.bands, .failed, .failed, .found(1)))
}
