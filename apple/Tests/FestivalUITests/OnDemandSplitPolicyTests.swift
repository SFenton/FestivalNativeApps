import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// Window layouts (points) for the on-demand split (`split-view.md`).
private enum SplitLayouts {
    static let iPhonePortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 402, height: 874), widthClass: .compact
    ))
    static let largeIPhoneLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 956, height: 440), widthClass: .regular, heightClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)
    ))
    static let iPadLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 1210, height: 834), widthClass: .regular, usesSidebarShell: true
    ))
    static let iPadPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 834, height: 1210), widthClass: .regular, usesSidebarShell: true
    ))
    /// A regular Stage Manager window too narrow for two 360 pt panes.
    static let iPadNarrowLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 700, height: 600), widthClass: .regular, usesSidebarShell: true
    ))
    static let duoFolded = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 466, height: 678), widthClass: .compact,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
        verticalBarEdge: .trailing, hinge: .closed
    ))
    static let duoInnerLandscape = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
        verticalBarEdge: .trailing, hinge: .fullyOpen
    ))
    static let duoInnerPortrait = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
    ))
    /// Book pose: an active vertical fold, offset from the middle to prove alignment.
    static let duoBook = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .partiallyOpen,
        divisions: [CGRect(x: 460, y: 0, width: 30, height: 669)]
    ))
    /// Flat, with the hinge reported as an inactive division.
    static let duoFlatReported = DeviceLayout.resolve(LayoutSignals(
        size: CGSize(width: 951, height: 669), widthClass: .regular,
        verticalBarEdge: .trailing, hinge: .fullyOpen,
        hinges: [CGRect(x: 470, y: 0, width: 11, height: 669)]
    ))
}

private func song(_ id: String) throws -> Song {
    try JSONDecoder().decode(Song.self, from: Data("""
    {"songId":"\(id)","title":"Song \(id)","artist":"Fixture Artist"}
    """.utf8))
}

private func player(_ id: String) -> AppRoute { .player(accountId: id, displayName: "P \(id)") }
private func rival(_ id: String) -> AppRoute {
    .rivalDetail(rivalId: id, name: "R \(id)", scope: .song(instruments: ["Solo_Guitar"]))
}
private func band(_ id: String) -> AppRoute { .band(bandId: id, name: nil, bandType: "Band_Duets", teamKey: id) }
private let rankings = AppRoute.fullRankings(instrument: .lead, rankBy: "adjusted")
private let bandRankings = AppRoute.bandRankings(bandType: "Band_Duets")
private let allRivals = AppRoute.allRivals(scope: .song(instruments: ["Solo_Guitar"]))

/// Geometry of a split filling a whole window.
private func windowGeometry(_ layout: DeviceLayout) -> OnDemandSplitPolicy.Geometry? {
    OnDemandSplitPolicy.geometry(OnDemandSplitPolicy.context(
        layout: layout, container: CGRect(origin: .zero, size: layout.size)
    ))
}

// MARK: - Page classification

/// Each split page accepts exactly its detail routes (operator 2026-10-04 table).
@Test func splitPagesAcceptOnlyTheirDetails() throws {
    let detail = try AppRoute.songDetail(song("a"))
    let board = try AppRoute.songLeaderboard(song("a"), .lead, 1)
    let history = try AppRoute.playerHistory(song("a"), .lead)
    let bandBoard = try AppRoute.songBandLeaderboard(song("a"), bandType: "Band_Duets")
    typealias Page = OnDemandSplitPolicy.ListPage
    #expect(Page.rivals.accepts(rival("r")) && !Page.rivals.accepts(player("p")))
    #expect(Page.leaderboards.accepts(player("p")) && Page.leaderboards.accepts(band("b")))
    #expect(!Page.leaderboards.accepts(rankings))
    #expect(Page.rankings.accepts(player("p")) && !Page.rankings.accepts(band("b")))
    #expect(Page.bandRankings.accepts(band("b")) && !Page.bandRankings.accepts(player("p")))
    #expect(Page.songDetail.accepts(board) && Page.songDetail.accepts(history))
    // Song Detail's player rows, band boards and other songs push full width.
    #expect(!Page.songDetail.accepts(player("p")) && !Page.songDetail.accepts(bandBoard))
    #expect(!Page.songDetail.accepts(detail))
    #expect(Page.settings.accepts(.licenses) && !Page.settings.accepts(.shop))
}

/// Never-split pages: Songs, Song Leaderboard, Shop, Statistics, Suggestions, Compete,
/// Band Detail, Player Bands and Rivalry have no cut, so their pushes are full width.
@Test func neverSplitPagesHaveNoCut() throws {
    let board = try AppRoute.songLeaderboard(song("a"), .lead, 1)
    #expect(OnDemandSplitPolicy.cut(section: .songs, path: []) == nil)
    #expect(OnDemandSplitPolicy.cut(section: .songs, path: [try .songDetail(song("a")), board, player("p")])
        == .init(list: [try .songDetail(song("a"))], detail: [board, player("p")], page: .songDetail))
    for section in [FestivalSection.shop, .statistics, .suggestions, .compete] {
        #expect(OnDemandSplitPolicy.cut(section: section, path: []) == nil)
    }
    #expect(OnDemandSplitPolicy.cut(section: .songs, path: [board]) == nil)
    // Band Detail and Player Bands never split (a band opened from Compete pushes).
    #expect(OnDemandSplitPolicy.cut(section: .compete, path: [band("b"), .playerBands(accountId: "p", displayName: nil)]) == nil)
    #expect(OnDemandSplitPolicy.cut(section: .rivals, path: [rival("r"), .rivalry(rivalId: "r", mode: "song", name: nil, scope: nil)])
        == .init(list: [], detail: [rival("r"), .rivalry(rivalId: "r", mode: "song", name: nil, scope: nil)], page: .rivals))
}

/// Root and pushed list pages cut at their first accepted route.
@Test func listPagesCutAtTheirFirstDetail() {
    #expect(OnDemandSplitPolicy.cut(section: .rivals, path: []) == .init(list: [], detail: [], page: .rivals))
    #expect(OnDemandSplitPolicy.cut(section: .rivals, path: [allRivals, rival("x")])
        == .init(list: [allRivals], detail: [rival("x")], page: .rivals))
    #expect(OnDemandSplitPolicy.cut(section: .leaderboards, path: [player("p")])
        == .init(list: [], detail: [player("p")], page: .leaderboards))
    // "View all rankings" pushes Full Rankings full width (a list page, nothing open).
    #expect(OnDemandSplitPolicy.cut(section: .leaderboards, path: [rankings])
        == .init(list: [rankings], detail: [], page: .rankings))
    #expect(OnDemandSplitPolicy.cut(section: .leaderboards, path: [bandRankings, band("b")])
        == .init(list: [bandRankings], detail: [band("b")], page: .bandRankings))
    #expect(OnDemandSplitPolicy.cut(section: .settings, path: [.licenses])
        == .init(list: [], detail: [.licenses], page: .settings))
    // Compete › Leaderboards (pushed) is a list page too.
    #expect(OnDemandSplitPolicy.cut(section: .compete, path: [.leaderboards, player("p")])
        == .init(list: [.leaderboards], detail: [player("p")], page: .leaderboards))
}

// MARK: - Path writes

/// Selecting replaces the open item; closing returns to the list; a non-detail push
/// from the list closes the item with it; trailing pushes extend the detail.
@Test func pathWritesKeepOneNavigationState() {
    let open = [rankings, player("a")]
    #expect(OnDemandSplitPolicy.path(selecting: player("b"), in: open, section: .leaderboards) == [rankings, player("b")])
    #expect(OnDemandSplitPolicy.path(selecting: player("b"), in: [rankings], section: .leaderboards) == [rankings, player("b")])
    #expect(OnDemandSplitPolicy.pathClosingDetail(open, section: .leaderboards) == [rankings])
    #expect(OnDemandSplitPolicy.pathClosingDetail([rankings], section: .leaderboards) == nil)
    // Leading stack writes: unchanged keeps the item, a pop or other push replaces.
    #expect(OnDemandSplitPolicy.path(settingList: [rankings], in: open, section: .leaderboards) == open)
    #expect(OnDemandSplitPolicy.path(settingList: [], in: open, section: .leaderboards) == [])
    #expect(OnDemandSplitPolicy.path(settingList: [rankings, .shop], in: open, section: .leaderboards) == [rankings, .shop])
    // Trailing stack writes.
    #expect(OnDemandSplitPolicy.path(settingDetailTail: [.playerBands(accountId: "a", displayName: nil)], in: open, section: .leaderboards)
        == open + [.playerBands(accountId: "a", displayName: nil)])
    #expect(OnDemandSplitPolicy.path(settingDetailTail: [], in: [rankings], section: .leaderboards) == [rankings])
}

/// Back on the leading pane's page closes an open item first, keeping the list page;
/// with nothing open it pops the list page; at the section root there is no Back
/// (issue #347).
@Test func listBackClosesTheOpenItemFirst() throws {
    let detail = try AppRoute.songDetail(song("s"))
    let board = try AppRoute.songLeaderboard(song("s"), .lead, 1)
    #expect(OnDemandSplitPolicy.pathAfterListBack([detail, board], section: .songs) == [detail])
    #expect(OnDemandSplitPolicy.pathAfterListBack([detail], section: .songs) == [])
    // A page pushed in the trailing pane closes with the item it was pushed from.
    let open = [rankings, player("a"), .playerBands(accountId: "a", displayName: nil)]
    #expect(OnDemandSplitPolicy.pathAfterListBack(open, section: .leaderboards) == [rankings])
    #expect(OnDemandSplitPolicy.pathAfterListBack([detail, board, player("p")], section: .songs) == [detail])
    #expect(OnDemandSplitPolicy.pathAfterListBack([rankings], section: .leaderboards) == [])
    // A section root list page (Rivals) closes its item; at the root there is no Back.
    #expect(OnDemandSplitPolicy.pathAfterListBack([rival("r")], section: .rivals) == [])
    #expect(OnDemandSplitPolicy.pathAfterListBack([], section: .rivals) == nil)
    // A page that never splits pops normally.
    #expect(OnDemandSplitPolicy.pathAfterListBack([.bands, player("p")], section: .statistics) == [.bands])
}

// MARK: - Eligibility and geometry

/// Landscape regular windows split; portrait, compact, large iPhone landscape and
/// folded Duo never do.
@Test func splitAppliesOnlyInLandscapeRegularWindows() {
    #expect(windowGeometry(SplitLayouts.iPhonePortrait) == nil)
    #expect(windowGeometry(SplitLayouts.largeIPhoneLandscape) == nil)
    #expect(windowGeometry(SplitLayouts.iPadPortrait) == nil)
    #expect(windowGeometry(SplitLayouts.duoFolded) == nil)
    #expect(windowGeometry(SplitLayouts.duoInnerPortrait) == nil)
    #expect(windowGeometry(.standardPhone) == nil)
    #expect(windowGeometry(SplitLayouts.iPadLandscape) != nil)
    #expect(windowGeometry(SplitLayouts.duoInnerLandscape) != nil)
}

/// Each half must be at least 360 pt.
@Test func eachPaneNeedsMinimumWidth() {
    #expect(windowGeometry(SplitLayouts.iPadNarrowLandscape) == nil)
    let context = { (width: CGFloat) in
        OnDemandSplitPolicy.Context(container: CGRect(x: 0, y: 0, width: width, height: 600), isLandscape: true, isRegular: true)
    }
    #expect(OnDemandSplitPolicy.geometry(context(720)) == nil)
    #expect(OnDemandSplitPolicy.geometry(context(721)) != nil)
}

/// iPad: the divider is exactly the midpoint, 50/50, 1 pt wide.
@Test func iPadSplitsAtExactMidpoint() throws {
    let geometry = try #require(windowGeometry(SplitLayouts.iPadLandscape))
    #expect(geometry.dividerMidX == 605)
    #expect(geometry.dividerWidth == 1)
    #expect(geometry.leadingWidth == geometry.trailingWidth)
    #expect(geometry.leadingWidth + geometry.dividerWidth + geometry.trailingWidth == 1210)
}

/// Mac: the midpoint of the content area right of the sidebar, in its own coordinates.
@Test func macContentAreaSplitsAtItsMidpoint() throws {
    let geometry = try #require(OnDemandSplitPolicy.geometry(.init(
        container: CGRect(x: 0, y: 0, width: 1060, height: 800), isLandscape: true, isRegular: true
    )))
    #expect(geometry.dividerMidX == 530 && geometry.leadingWidth == 529.5 && geometry.trailingWidth == 529.5)
}

/// Duo: the divider aligns to the hinge, never to the safe area; the vertical bar stays
/// inside the trailing pane.
@Test func duoSplitsAtTheHinge() throws {
    // Flat, hinge unreported: the line through the window's middle.
    let flat = try #require(windowGeometry(SplitLayouts.duoInnerLandscape))
    #expect(flat.dividerMidX == 475.5)
    // A container that stops at the vertical bar keeps the divider on the hinge.
    let insideBar = try #require(OnDemandSplitPolicy.geometry(OnDemandSplitPolicy.context(
        layout: SplitLayouts.duoInnerLandscape, container: CGRect(x: 0, y: 0, width: 867, height: 669)
    )))
    #expect(insideBar.dividerMidX == 475.5)
    #expect(insideBar.leadingWidth == 475 && insideBar.trailingWidth == 391)
    // Book pose: the panes end at the fold's edges, whatever its offset.
    let book = try #require(windowGeometry(SplitLayouts.duoBook))
    #expect(book.leadingWidth == 460 && book.dividerWidth == 30 && book.trailingWidth == 461)
    // Flat with the hinge reported as an inactive division.
    let reported = try #require(windowGeometry(SplitLayouts.duoFlatReported))
    #expect(reported.leadingWidth == 470 && reported.dividerWidth == 11)
}

/// No split draws a divider line (#344): the band's space and the panes' margins separate
/// them. Increase Contrast restores the 1 pt hairline at a midpoint (iPad, Mac), never on
/// the iPhone Duo hinge, whether the fold is reported or not.
@Test func dividerLineOnlyUnderIncreaseContrastAtAMidpoint() throws {
    let iPad = try #require(windowGeometry(SplitLayouts.iPadLandscape))
    let mac = try #require(OnDemandSplitPolicy.geometry(.init(
        container: CGRect(x: 0, y: 0, width: 1060, height: 800), isLandscape: true, isRegular: true
    )))
    let duo = try [SplitLayouts.duoInnerLandscape, SplitLayouts.duoBook, SplitLayouts.duoFlatReported]
        .map { try #require(windowGeometry($0)) }
    for midpoint in [iPad, mac] {
        #expect(!midpoint.isHinge)
        #expect(!OnDemandSplitPolicy.drawsDividerLine(midpoint, increasedContrast: false))
        #expect(OnDemandSplitPolicy.drawsDividerLine(midpoint, increasedContrast: true))
    }
    for hinge in duo {
        #expect(hinge.isHinge)
        #expect(!OnDemandSplitPolicy.drawsDividerLine(hinge, increasedContrast: false))
        #expect(!OnDemandSplitPolicy.drawsDividerLine(hinge, increasedContrast: true))
    }
}

/// The rendered band between the panes is clear (#344): a midpoint band and a hinge band
/// both show what lies under the split, never a lighter line.
@MainActor
@Test func renderedSplitBandDrawsNoLine() throws {
    let midpoint = try #require(OnDemandSplitPolicy.geometry(.init(
        container: CGRect(x: 0, y: 0, width: 801, height: 40), isLandscape: true, isRegular: true
    )))
    let hinge = try #require(OnDemandSplitPolicy.geometry(.init(
        container: CGRect(x: 0, y: 0, width: 801, height: 40), isLandscape: true, isRegular: true,
        hinge: CGRect(x: 395, y: 0, width: 11, height: 40)
    )))
    for geometry in [midpoint, hinge] {
        let split = OnDemandSplitLayout(geometry: geometry) {
            Color.black
        } trailing: {
            Color.black
        }
        .frame(width: 801, height: 40)
        .background(Color.black)
        let renderer = ImageRenderer(content: split)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let context = try #require(CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try #require(context.data).bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let row = image.height / 2
        let brightest = (0..<image.width).map { pixels[(row * image.width + $0) * 4] }.max() ?? 0
        #expect(brightest < 8, "no divider line across the band (hinge: \(geometry.isHinge)): \(brightest)")
    }
}

/// Folding, rotating or resizing across the split threshold changes the stacks' shape a
/// run-loop turn later (#346); the first measurement applies at once.
@Test func windowChangesApplyOneTurnLater() {
    typealias State = OnDemandSplitPolicy.WindowState
    let unmeasured = State(measured: false, allowsSplit: false)
    let split = State(measured: true, allowsSplit: true)
    let single = State(measured: true, allowsSplit: false)
    // Launch: the container's first measurement shapes the stacks immediately.
    #expect(!OnDemandSplitPolicy.defersWindowChange(from: unmeasured, to: split))
    #expect(!OnDemandSplitPolicy.defersWindowChange(from: unmeasured, to: single))
    // Fold (or portrait) and unfold (or landscape) wait for the window's own update.
    #expect(OnDemandSplitPolicy.defersWindowChange(from: split, to: single))
    #expect(OnDemandSplitPolicy.defersWindowChange(from: single, to: split))
    // Resizes and hinge moves that keep the split need no deferral.
    #expect(!OnDemandSplitPolicy.defersWindowChange(from: split, to: split))
    #expect(!OnDemandSplitPolicy.defersWindowChange(from: single, to: single))
}

/// While a collapse is pending the stacks keep the last panes; while an expansion is
/// pending they stay one stack; once applied they follow the window.
@Test func appliedGeometryHoldsShapeUntilApplied() throws {
    let inner = try #require(windowGeometry(SplitLayouts.duoInnerLandscape))
    let folded = windowGeometry(SplitLayouts.duoFolded)
    #expect(folded == nil)
    // Before the first application: the live window.
    #expect(OnDemandSplitPolicy.appliedGeometry(live: inner, held: nil, applied: nil) == inner)
    #expect(OnDemandSplitPolicy.appliedGeometry(live: nil, held: inner, applied: nil) == nil)
    // Folded, collapse pending: the split keeps its panes for one turn.
    #expect(OnDemandSplitPolicy.appliedGeometry(live: folded, held: inner, applied: true) == inner)
    // Collapse applied: one stack, the open item pushed.
    #expect(OnDemandSplitPolicy.appliedGeometry(live: folded, held: inner, applied: false) == nil)
    // Unfolded, expansion pending: still one stack, then the split.
    #expect(OnDemandSplitPolicy.appliedGeometry(live: inner, held: inner, applied: false) == nil)
    #expect(OnDemandSplitPolicy.appliedGeometry(live: inner, held: inner, applied: true) == inner)
    // A resize while split follows the window at once.
    let book = try #require(windowGeometry(SplitLayouts.duoBook))
    #expect(OnDemandSplitPolicy.appliedGeometry(live: book, held: inner, applied: true) == book)
}

/// The hinge line comes from the fold, the reported hinge, or the inner display's middle.
@Test func splitHingeSources() {
    #expect(SplitLayouts.duoBook.splitHinge == CGRect(x: 460, y: 0, width: 30, height: 669))
    #expect(SplitLayouts.duoFlatReported.splitHinge == CGRect(x: 470, y: 0, width: 11, height: 669))
    #expect(SplitLayouts.duoInnerLandscape.splitHinge == CGRect(x: 475.5, y: 0, width: 0, height: 669))
    #expect(SplitLayouts.iPadLandscape.splitHinge == nil)
    #expect(SplitLayouts.duoFolded.splitHinge == nil)
}

/// The select action opens only the list page's detail routes and compares by page.
@Test func selectActionAcceptsPageDetails() {
    let action = ListDetailSelectAction(section: .leaderboards, page: .rankings) { _ in }
    #expect(action.accepts(player("p")) && !action.accepts(rankings))
    #expect(action == ListDetailSelectAction(section: .leaderboards, page: .rankings) { _ in })
    #expect(action != ListDetailSelectAction(section: .leaderboards, page: .leaderboards) { _ in })
    // The shelved dual-source regions accept everything.
    #expect(ListDetailSelectAction(section: .songs) { _ in }.accepts(rankings))
}

/// Songs uses two cards per row only in landscape regular windows.
@Test func songsGridColumns() {
    #expect(SongGridPolicy.columns(layout: SplitLayouts.iPadLandscape) == 2)
    #expect(SongGridPolicy.columns(layout: SplitLayouts.duoInnerLandscape) == 2)
    #expect(SongGridPolicy.columns(layout: SplitLayouts.iPadPortrait) == 1)
    #expect(SongGridPolicy.columns(layout: SplitLayouts.iPhonePortrait) == 1)
    #expect(SongGridPolicy.columns(layout: SplitLayouts.largeIPhoneLandscape) == 1)
    #expect(SongGridPolicy.columns(layout: SplitLayouts.duoFolded) == 1)
    #expect(SongGridPolicy.rows([1, 2, 3, 4, 5], columns: 2) == [[1, 2], [3, 4], [5]])
    #expect(SongGridPolicy.rows([1, 2], columns: 1) == [[1], [2]])
}

/// The flyout opens from a leading-edge swipe only.
@Test func flyoutEdgeSwipeRule() {
    #expect(FlyoutEdgeSwipe.opens(startFromLeading: 10, translation: CGSize(width: 90, height: 10)))
    #expect(!FlyoutEdgeSwipe.opens(startFromLeading: 80, translation: CGSize(width: 90, height: 10)))
    #expect(!FlyoutEdgeSwipe.opens(startFromLeading: 10, translation: CGSize(width: 30, height: 0)))
    #expect(!FlyoutEdgeSwipe.opens(startFromLeading: 10, translation: CGSize(width: 70, height: 120)))
}
