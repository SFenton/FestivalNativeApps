import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// Layouts (points) matching `ShellPresentationTests`; insets are illustrative.
private enum ListDetailLayouts {
    static let iPhonePortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 402, height: 874), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
    ))
    static let largeIPhoneLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 956, height: 440), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
    ))
    static let iPad = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 1180, height: 820), widthClass: .regular, usesSidebarShell: true
    ))
    static let duoFolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    ))
    static let duoUnfolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    static let duoUnfoldedPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
    ))
    static let duoPartiallyFolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .partiallyOpen,
        divisions: [CGRect(x: 455, y: 0, width: 41, height: 669)]
    ))
}

/// A decoded catalogue song (no network).
///
/// - Parameter id: Song ID.
/// - Returns: A minimal valid song.
private func song(_ id: String) throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"\(id)","title":"Song \(id)","artist":"Fixture Artist"}
    """.utf8))
}

private func player(_ id: String) -> AppRoute { .player(accountId: id, displayName: "P \(id)") }
private func rival(_ id: String) -> AppRoute {
    .rivalDetail(rivalId: id, name: "R \(id)", scope: .song(instruments: ["Solo_Guitar"]))
}
private let rankings = AppRoute.fullRankings(instrument: .lead, rankBy: "adjusted")
private let allRivals = AppRoute.allRivals(scope: .song(instruments: ["Solo_Guitar"]))

// MARK: - Layout gate

/// Only the iPhone Duo inner display splits; iPhone (either orientation), folded Duo
/// and (for now) iPad keep one stack.
@Test func listDetailSplitsOnlyOnDuoInnerDisplay() {
    #expect(!ListDetailPolicy.usesSplit(ListDetailLayouts.iPhonePortrait))
    #expect(!ListDetailPolicy.usesSplit(ListDetailLayouts.largeIPhoneLandscape))
    #expect(!ListDetailPolicy.usesSplit(ListDetailLayouts.iPad))
    #expect(!ListDetailPolicy.usesSplit(ListDetailLayouts.duoFolded))
    #expect(!ListDetailPolicy.usesSplit(.standardPhone))
    #expect(ListDetailPolicy.usesSplit(ListDetailLayouts.duoUnfolded))
    #expect(ListDetailPolicy.usesSplit(ListDetailLayouts.duoUnfoldedPortrait))
    #expect(ListDetailPolicy.usesSplit(ListDetailLayouts.duoPartiallyFolded))
}

/// iPhone stays exactly as before: every section path is one stack.
@Test func iPhoneNeverSplits() throws {
    let paths: [[AppRoute]] = try [[], [.songDetail(song("a"))], [rankings, player("p")], [rival("r")]]
    for section in FestivalSection.allCases {
        for path in paths {
            #expect(ListDetailPolicy.arrangement(
                section: section, path: path, layout: ListDetailLayouts.iPhonePortrait
            ) == .stack)
        }
    }
}

// MARK: - Path split per section

/// Songs: the list is the root, Song Detail and everything it pushes is the detail.
@Test func songsSplitAtSongDetail() throws {
    let detail = try AppRoute.songDetail(song("a"))
    let board = try AppRoute.songLeaderboard(song("a"), .lead, 1)
    #expect(ListDetailPolicy.split(section: .songs, path: [])
        == .init(list: [], detail: [], page: .songs))
    #expect(ListDetailPolicy.split(section: .songs, path: [detail, board])
        == .init(list: [], detail: [detail, board], page: .songs))
}

/// Songs › Shop is a full-width page, not a detail: one stack, even with a song on top.
@Test func songsShopStaysOneStack() throws {
    #expect(ListDetailPolicy.split(section: .songs, path: [.shop]) == nil)
    #expect(try ListDetailPolicy.split(section: .songs, path: [.shop, .songDetail(song("a"))]) == nil)
}

/// Leaderboards: the overview is a dashboard (one stack); Full Rankings splits with Player.
@Test func leaderboardsSplitAtFullRankings() {
    #expect(ListDetailPolicy.split(section: .leaderboards, path: []) == nil)
    #expect(ListDetailPolicy.split(section: .leaderboards, path: [player("p")]) == nil)
    #expect(ListDetailPolicy.split(section: .leaderboards, path: [rankings])
        == .init(list: [rankings], detail: [], page: .rankings))
    let deeper: [AppRoute] = [rankings, player("p"), .playerBands(accountId: "p", displayName: nil)]
    #expect(ListDetailPolicy.split(section: .leaderboards, path: deeper)
        == .init(list: [rankings], detail: Array(deeper.dropFirst()), page: .rankings))
}

/// Rivals: the hub and All Rivals are lists, Rival Detail (and Rivalry) the detail.
@Test func rivalsSplitAtRivalDetail() {
    let rivalry = AppRoute.rivalry(rivalId: "r", mode: "song", name: nil, scope: nil)
    #expect(ListDetailPolicy.split(section: .rivals, path: [])
        == .init(list: [], detail: [], page: .rivals))
    #expect(ListDetailPolicy.split(section: .rivals, path: [rival("r"), rivalry])
        == .init(list: [], detail: [rival("r"), rivalry], page: .rivals))
    #expect(ListDetailPolicy.split(section: .rivals, path: [allRivals])
        == .init(list: [allRivals], detail: [], page: .rivals))
    #expect(ListDetailPolicy.split(section: .rivals, path: [allRivals, rival("r")])
        == .init(list: [allRivals], detail: [rival("r")], page: .rivals))
}

/// A Compete path carried into Leaderboards on unfold (Rivals › Rival) still splits,
/// because list pages are recognised by route.
@Test func carriedRivalsPathSplitsInLeaderboards() {
    #expect(ListDetailPolicy.split(section: .leaderboards, path: [.rivals, rival("r")])
        == .init(list: [.rivals], detail: [rival("r")], page: .rivals))
}

/// Single-page sections never split.
@Test func singlePageSectionsNeverSplit() {
    for section in [FestivalSection.suggestions, .compete, .statistics, .settings] {
        #expect(ListDetailPolicy.split(section: section, path: [rankings, player("p")]) == nil)
        #expect(ListDetailPolicy.arrangement(
            section: section, path: [], layout: ListDetailLayouts.duoUnfolded
        ) == .stack)
    }
}

// MARK: - Round trip (fold/unfold keeps state)

/// Every representative path: the split re-joins to the original path, so the
/// stack ↔ split mapping is lossless.
@Test func splitRoundTripsToThePath() throws {
    let detail = try AppRoute.songDetail(song("a"))
    let cases: [(FestivalSection, [AppRoute])] = try [
        (.songs, []), (.songs, [detail]),
        (.songs, [detail, .songLeaderboard(song("a"), .bass, 3), player("p")]),
        (.leaderboards, [rankings]), (.leaderboards, [rankings, player("p")]),
        (.leaderboards, [rankings, player("p"), .playerBands(accountId: "p", displayName: nil)]),
        (.rivals, []), (.rivals, [rival("r")]), (.rivals, [allRivals, rival("r")]),
        (.leaderboards, [.rivals, allRivals, rival("r")]),
    ]
    for (section, path) in cases {
        let split = try #require(ListDetailPolicy.split(section: section, path: path))
        #expect(split.list + split.detail == path)
    }
}

/// Folding shows the selected detail pushed on the compact stack; unfolding again
/// lifts the same detail back into the detail column, unchanged.
@Test func selectedDetailSurvivesFoldAndUnfold() throws {
    let path: [AppRoute] = [rankings, player("p"), .playerBands(accountId: "p", displayName: nil)]
    let unfolded = ListDetailPolicy.arrangement(
        section: .leaderboards, path: path, layout: ListDetailLayouts.duoUnfolded
    )
    guard case let .split(split) = unfolded else {
        Issue.record("Expected a split when unfolded, got \(unfolded)")
        return
    }
    #expect(split.selection == player("p"))
    // Fold: nothing is rewritten; the same path is shown as one stack.
    #expect(ListDetailPolicy.arrangement(
        section: .leaderboards, path: path, layout: ListDetailLayouts.duoFolded
    ) == .stack)
    // Partially fold and unfold again: the same split and selection.
    for layout in [ListDetailLayouts.duoPartiallyFolded, ListDetailLayouts.duoUnfolded] {
        #expect(ListDetailPolicy.arrangement(section: .leaderboards, path: path, layout: layout)
            == .split(split))
    }
}

/// A detail pushed while folded (Songs › Song Detail) becomes the selection on unfold.
@Test func detailPushedWhileFoldedIsSelectedOnUnfold() throws {
    let detail = try AppRoute.songDetail(song("a"))
    #expect(ListDetailPolicy.arrangement(
        section: .songs, path: [detail], layout: ListDetailLayouts.duoUnfolded
    ) == .split(.init(list: [], detail: [detail], page: .songs)))
}

// MARK: - Column writes

/// Tapping a row pushes onto the list column; the write replaces the detail and the
/// re-split lifts it into the detail column, leaving the list unchanged.
@Test func listPushBecomesTheDetail() throws {
    let first = try AppRoute.songDetail(song("a"))
    let second = try AppRoute.songDetail(song("b"))
    let board = try AppRoute.songLeaderboard(song("a"), .lead, 1)
    // Nothing selected → select A.
    let selectedA = ListDetailPolicy.path(settingList: [first], in: [], section: .songs)
    #expect(selectedA == [first])
    // A (with a deeper push) selected → select B drops A's stack.
    let selectedB = ListDetailPolicy.path(settingList: [second], in: [first, board], section: .songs)
    #expect(selectedB == [second])
    #expect(ListDetailPolicy.split(section: .songs, path: selectedB)?.list == [])
    // Full Rankings row → Player.
    #expect(ListDetailPolicy.path(
        settingList: [rankings, player("q")], in: [rankings, player("p")], section: .leaderboards
    ) == [rankings, player("q")])
}

/// An unchanged list write keeps the detail; popping the list drops it with its page.
@Test func listWritesKeepOrDropTheDetail() {
    let path: [AppRoute] = [rankings, player("p")]
    #expect(ListDetailPolicy.path(settingList: [rankings], in: path, section: .leaderboards) == path)
    #expect(ListDetailPolicy.path(settingList: [], in: path, section: .leaderboards) == [])
    // All Rivals from the hub: a new list page clears the hub's selection.
    #expect(ListDetailPolicy.path(settingList: [allRivals], in: [rival("r")], section: .rivals)
        == [allRivals])
}

/// Detail-column pushes and pops rewrite only the part after the detail root.
@Test func detailTailWrites() throws {
    let detail = try AppRoute.songDetail(song("a"))
    let board = try AppRoute.songLeaderboard(song("a"), .lead, 1)
    #expect(ListDetailPolicy.path(settingDetailTail: [board], in: [detail], section: .songs)
        == [detail, board])
    #expect(ListDetailPolicy.path(settingDetailTail: [], in: [detail, board], section: .songs)
        == [detail])
    // Nothing selected: the placeholder cannot push, so the path is unchanged.
    #expect(ListDetailPolicy.path(settingDetailTail: [board], in: [], section: .songs) == [])
}
