#if os(macOS)
import AppKit
#endif
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Policy (issue #342)

/// A song board in a split's trailing pane beside Song Detail drops the song header
/// (owner-approved `song-leaderboard-header` variant); every other place keeps it.
@Test func songBoardsDropTheSongHeaderOnlyBesideSongDetail() {
    #expect(!SongLeaderboardBoardLine.showsSongHeader(besideList: .songDetail))
    #expect(SongLeaderboardBoardLine.showsSongHeader(besideList: nil), "Pushed full width")
    for page: OnDemandSplitPolicy.ListPage in [.rivals, .compete, .leaderboards, .settings] {
        #expect(SongLeaderboardBoardLine.showsSongHeader(besideList: page), "\(page)")
    }
}

/// The board title's secondary line is the entry total, on the board line's terms.
@Test func boardTitleTotalFollowsTheServicesTotalsFlag() {
    #expect(SongLeaderboardBoardLine.totalText(totalEntries: 1234, showsTotals: true)
        == "\(1234.formatted()) entries")
    #expect(SongLeaderboardBoardLine.totalText(totalEntries: 1234, showsTotals: false) == nil)
    #expect(SongLeaderboardBoardLine.totalText(totalEntries: 7, showsTotals: nil) == nil)
    #expect(SongLeaderboardBoardLine.totalText(totalEntries: nil, showsTotals: true) == nil)
}

/// Only the item opened beside the list page knows that page: a page pushed inside the
/// trailing pane (a player, then their Song Detail and its board) is a page of its own.
@Test func pagesPushedInTheTrailingPaneAreNotBesideTheList() {
    let root = SplitPaneContext(paneWidth: 600, role: .trailing, besideList: .songDetail)
    let pushed = root.pushedPage
    #expect(pushed.besideList == nil)
    #expect(pushed.role == .trailing && pushed.paneWidth == 600, "Same pane otherwise")
    #expect(root != pushed, "The list page counts for equality")
    #expect(root == SplitPaneContext(paneWidth: 600, role: .trailing, besideList: .songDetail))
}

#if os(macOS)
// MARK: - Hosted renders

/// Host the solo board, optionally as the trailing root beside a list page.
@MainActor
private func hostedSoloBoard(besideList: OnDemandSplitPolicy.ListPage?) throws -> NSHostingView<some View> {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 520, height: 900)
    let song = try spotlightFixtureSong()
    let payload = try spotlightFixtureLeaderboard(spotlightRank: nil)
    return nativeHostedView(
        NavigationStack {
            SoloLeaderboardScreen(
                song: song, instrument: .lead, session: session,
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            )
            .splitPaneContext(besideList.map { SplitPaneContext(role: .trailing, besideList: $0) })
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
}

/// Beside Song Detail the board is titled by its instrument and never repeats the song's
/// title or artist; pushed full width it keeps the song header (#342).
@MainActor
@Test(arguments: [true, false])
func soloBoardTitleBesideSongDetail(besideSongDetail: Bool) async throws {
    let host = try hostedSoloBoard(besideList: besideSongDetail ? .songDetail : nil)
    let window = nativeHostedWindow(host, size: CGSize(width: 520, height: 900))
    defer { window.orderOut(nil) }
    let shown = besideSongDetail ? "Lead" : "Fixture Pulse"
    let image = try await nativeHostedSettle(host, untilText: [shown, "#1, Row 1"], timeout: .seconds(60))
    _ = try nativeHostedPNG(
        image, filename: "song-leaderboard-\(besideSongDetail ? "split" : "pushed")-title.png",
        environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    let tree = nativeHostedAccessibility(host)
    if besideSongDetail {
        #expect(tree.identifiers.contains("fst.song-leaderboard.board-title"))
        #expect(!tree.identifiers.contains("fst.song-leaderboard.header"))
        #expect(!tree.contains("Fixture Pulse") && !tree.contains("Fixture Artist"), "texts: \(tree.texts)")
    } else {
        #expect(tree.identifiers.contains("fst.song-leaderboard.header"))
        #expect(!tree.identifiers.contains("fst.song-leaderboard.board-title"))
        #expect(tree.contains("Fixture Artist"))
    }
}
#endif
