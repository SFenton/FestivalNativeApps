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
        size: CGSize(width: 956, height: 440), widthClass: .regular, heightClass: .compact,
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

/// Among phones only the iPhone Duo inner display splits; iPhone (either orientation)
/// and folded Duo keep one stack. The sidebar shell splits only where it is enabled
/// (iPad, not yet macOS).
@Test func listDetailSplitsOnlyOnDuoInnerDisplay() {
    #expect(!ListDetailPolicy.usesSplit(ListDetailLayouts.iPhonePortrait))
    #expect(!ListDetailPolicy.usesSplit(ListDetailLayouts.largeIPhoneLandscape))
    #expect(!ListDetailPolicy.usesSplit(ListDetailLayouts.iPad, sidebarShellSplits: false))
    #expect(ListDetailPolicy.usesSplit(ListDetailLayouts.iPad, sidebarShellSplits: true))
    #expect(!ListDetailPolicy.usesSplit(ListDetailLayouts.duoFolded))
    #expect(!ListDetailPolicy.usesSplit(.standardPhone))
    #expect(ListDetailPolicy.usesSplit(ListDetailLayouts.duoUnfolded))
    // Portrait inner display: two columns too (`/duo` D1, operator 2026-10-02).
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

// MARK: - Empty selection

/// Operator 2026-09-28: a wide window always shows two populated columns. An
/// unselected list page splits (the stack auto-selects), unless its list produced no
/// row, which collapses to one full-width stack. Compact (folded) windows never await.
@Test func unselectedListSplitsUnlessEmpty() throws {
    for (section, path) in [(FestivalSection.songs, [AppRoute]()), (.rivals, []), (.leaderboards, [rankings])] {
        let split = try #require(ListDetailPolicy.split(section: section, path: path))
        #expect(ListDetailPolicy.arrangement(section: section, path: path, layout: ListDetailLayouts.duoUnfolded) == .split(split))
        #expect(ListDetailPolicy.arrangement(
            section: section, path: path, layout: ListDetailLayouts.duoUnfolded, emptyListCollapsed: true
        ) == .stack)
        #expect(ListDetailPolicy.awaitsSelection(section: section, path: path, layout: ListDetailLayouts.duoUnfolded))
        #expect(!ListDetailPolicy.awaitsSelection(section: section, path: path, layout: ListDetailLayouts.duoFolded))
        // Inner portrait is wide enough too (`/duo` D1, operator 2026-10-02).
        #expect(ListDetailPolicy.awaitsSelection(section: section, path: path, layout: ListDetailLayouts.duoUnfoldedPortrait))
    }
    #expect(!ListDetailPolicy.awaitsSelection(section: .leaderboards, path: [], layout: ListDetailLayouts.duoUnfolded))
    let detail = try AppRoute.songDetail(song("a"))
    #expect(!ListDetailPolicy.awaitsSelection(section: .songs, path: [detail], layout: ListDetailLayouts.duoUnfolded))
    // A selection is never collapsed away.
    #expect(ListDetailPolicy.arrangement(
        section: .songs, path: [detail], layout: ListDetailLayouts.duoUnfolded, emptyListCollapsed: true
    ) == .split(.init(list: [], detail: [detail], page: .songs)))
}


// MARK: - iPad sidebar shell

/// The iPad sidebar shell splits by window width alone (sidebar | list | detail from
/// 1000 pt): 11-inch landscape splits, portrait and narrow windows keep one stack.
@Test func iPadSplitFollowsWindowWidth() {
    func iPad(_ width: CGFloat) -> DeviceLayout {
        DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: width, height: 834), widthClass: .regular, usesSidebarShell: true
        ))
    }
    #expect(ListDetailPolicy.usesSplit(iPad(1194), sidebarShellSplits: true))
    #expect(ListDetailPolicy.usesSplit(iPad(1000), sidebarShellSplits: true))
    #expect(!ListDetailPolicy.usesSplit(iPad(999), sidebarShellSplits: true))
    #expect(!ListDetailPolicy.usesSplit(iPad(834), sidebarShellSplits: true))
    #expect(!ListDetailPolicy.usesSplit(iPad(1194), sidebarShellSplits: false))
}

/// ⌘[ pops one stack's top page, or in a split the column that has a Back button.
@Test func backCommandPopsTheFrontColumn() throws {
    let detail = AppRoute.songDetail(try song("a"))
    // Stack: plain pop.
    #expect(ListDetailPolicy.pathAfterBack(section: .songs, path: [detail], isSplit: false) == [])
    #expect(ListDetailPolicy.pathAfterBack(section: .songs, path: [], isSplit: false) == nil)
    // Split: the detail root alone has no Back.
    #expect(ListDetailPolicy.pathAfterBack(section: .songs, path: [detail], isSplit: true) == nil)
    // Split: a page pushed in the detail column pops first.
    #expect(ListDetailPolicy.pathAfterBack(section: .songs, path: [detail, .shop], isSplit: true) == [detail])
    // Split: a pushed list page pops with its detail.
    #expect(ListDetailPolicy.pathAfterBack(
        section: .leaderboards, path: [rankings, player("p")], isSplit: true
    ) == [])
    // A non-splittable section pops normally even if reported split.
    #expect(ListDetailPolicy.pathAfterBack(section: .settings, path: [.licenses], isSplit: true) == [])
}

/// `/duo` D2: size classes decide, not the hinge or a width breakpoint. A regular-width,
/// compact-height window never splits even with a vertical bar; a regular × regular one
/// splits with or without hinge data, in either orientation and with a horizontal fold.
@Test func listDetailGateUsesSizeClassesOnly() {
    let shortWide = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 440), widthClass: .regular, heightClass: .compact,
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    #expect(!ListDetailPolicy.usesSplit(shortWide))
    #expect(!shortWide.usesRegularSectionSet)
    let noHinge = DeviceLayout.resolve(LayoutSignals(size: CGSize(width: 669, height: 951), widthClass: .regular))
    #expect(ListDetailPolicy.usesSplit(noHinge))
    #expect(noHinge.usesRegularSectionSet)
    let halfPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .partiallyOpen,
        divisions: [CGRect(x: 0, y: 455, width: 669, height: 41)]
    ))
    #expect(ListDetailPolicy.usesSplit(halfPortrait))
}

/// `/duo` D6: after a stack ↔ split switch the rebuilt list scrolls back to the song
/// that was open, once, and only when it still lists that song.
@Test func listScrollRestoresToAnchorOnce() throws {
    let current = try song("a")
    let other = try song("b")
    let anchor = AppRoute.songDetail(current)
    let rowID: (AppRoute) -> String? = { route in
        if case let .songDetail(song) = route { return song.id }
        return nil
    }
    #expect(ListDetailScrollRestore.anchor(selection: anchor, lastSelection: .songDetail(other)) == anchor)
    #expect(ListDetailScrollRestore.anchor(selection: nil, lastSelection: anchor) == anchor)
    #expect(ListDetailScrollRestore.anchor(selection: nil, lastSelection: nil) == nil)
    let ids: Set<String> = [current.id, other.id]
    #expect(ListDetailScrollRestore.target(anchor: anchor, restored: nil, rowIDs: ids, rowID: rowID) == current.id)
    #expect(ListDetailScrollRestore.target(anchor: anchor, restored: anchor, rowIDs: ids, rowID: rowID) == nil)
    #expect(ListDetailScrollRestore.target(anchor: anchor, restored: nil, rowIDs: [other.id], rowID: rowID) == nil)
    #expect(ListDetailScrollRestore.target(anchor: nil, restored: nil, rowIDs: ids, rowID: rowID) == nil)
    #expect(ListDetailScrollRestore.target(
        anchor: .player(accountId: "a", displayName: nil), restored: nil, rowIDs: ids, rowID: rowID
    ) == nil)
}

/// iPad: collapsing a split (portrait, narrower window, compact tab shell) pops a detail
/// the split chose by itself, never a picked row or a page pushed inside the detail.
@Test func collapsePopsOnlyTheAutomaticDetail() throws {
    let first = AppRoute.songDetail(try song("a"))
    let second = AppRoute.songDetail(try song("b"))
    #expect(ListDetailPolicy.pathDroppingAutomaticDetail(section: .songs, path: [first], automatic: first) == [])
    // A picked row (automatic cleared, or a different route) stays.
    #expect(ListDetailPolicy.pathDroppingAutomaticDetail(section: .songs, path: [second], automatic: first) == nil)
    #expect(ListDetailPolicy.pathDroppingAutomaticDetail(section: .songs, path: [first], automatic: nil) == nil)
    // Something pushed inside the detail column stays.
    #expect(ListDetailPolicy.pathDroppingAutomaticDetail(
        section: .songs, path: [first, .shop], automatic: first
    ) == nil)
    // Full Rankings keeps its list page.
    #expect(ListDetailPolicy.pathDroppingAutomaticDetail(
        section: .leaderboards, path: [rankings, player("p")], automatic: player("p")
    ) == [rankings])
    // Non-splittable sections never change.
    #expect(ListDetailPolicy.pathDroppingAutomaticDetail(section: .settings, path: [.licenses], automatic: .licenses) == nil)
}
