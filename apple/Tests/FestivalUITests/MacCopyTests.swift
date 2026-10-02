#if os(macOS)
import AppKit
import Foundation
import Testing
@testable import FestivalCore
@testable import FestivalUI

private func copyFixtureSong() throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"fixture-song","title":"Fixture Song","artist":"Fixture Artist"}
    """.utf8))
}

/// Edit › Copy names the selected row: a song's title on every song page, a player's,
/// band's or rival's name; nothing for roots or unnamed entities.
@Test func macCopyTextNamesTheSelectedRow() throws {
    let song = try copyFixtureSong()
    #expect(MacCopyPolicy.text(for: .songDetail(song)) == "Fixture Song")
    #expect(MacCopyPolicy.text(for: .songLeaderboard(song, .lead, 1)) == "Fixture Song")
    #expect(MacCopyPolicy.text(for: .playerHistory(song, .bass)) == "Fixture Song")
    #expect(MacCopyPolicy.text(for: .player(accountId: "a", displayName: "SFentonX")) == "SFentonX")
    #expect(MacCopyPolicy.text(for: .player(accountId: "a", displayName: nil)) == nil)
    #expect(MacCopyPolicy.text(for: .player(accountId: "a", displayName: "  ")) == nil)
    #expect(MacCopyPolicy.text(for: .band(bandId: "b", name: "The Band")) == "The Band")
    #expect(MacCopyPolicy.text(for: .rivalDetail(rivalId: "r", name: "Rival", scope: nil)) == "Rival")
    #expect(MacCopyPolicy.text(for: .leaderboards) == nil)
}

/// With two columns Copy uses the list's selection, even when the detail column has
/// pushed pages; in one column it uses the page on top.
@Test func macCopyUsesSelectionInTwoColumnsAndTopPageInOne() throws {
    let song = try copyFixtureSong()
    let leaderboard = AppRoute.songLeaderboard(song, .lead, 1)
    let player = AppRoute.player(accountId: "a", displayName: "Top Player")
    #expect(MacCopyPolicy.selectedRoute(path: [.songDetail(song)], section: .songs, split: true) == .songDetail(song))
    #expect(MacCopyPolicy.selectedRoute(path: [.songDetail(song), leaderboard, player], section: .songs, split: true)
        == .songDetail(song))
    #expect(MacCopyPolicy.selectedRoute(path: [.songDetail(song), leaderboard, player], section: .songs, split: false)
        == player)
    #expect(MacCopyPolicy.selectedRoute(path: [], section: .songs, split: false) == nil)
}

/// The window responder answers `copy:` only while there is a selection, and copies it.
@MainActor
@Test func macSelectionCopyResponderCopiesOnlyWithASelection() {
    let responder = MacSelectionCopyResponder()
    #expect(!responder.responds(to: #selector(MacSelectionCopyResponder.copy(_:))))
    responder.selectionText = { "Fixture Song" }
    #expect(responder.responds(to: #selector(MacSelectionCopyResponder.copy(_:))))
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("fst.tests.copy.\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    responder.pasteboard = pasteboard
    responder.copy(nil)
    #expect(pasteboard.string(forType: .string) == "Fixture Song")
}
#endif
