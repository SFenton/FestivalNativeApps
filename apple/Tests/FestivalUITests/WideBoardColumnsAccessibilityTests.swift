#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Two-column boards accessibility (issue #484, for #353)

/// #353 pairs a full leaderboard's rows in two row-major columns when the board fills a
/// wide landscape window (pattern `wide-columns` R1/R2/R8): Full Rankings, Band Rankings,
/// Song Leaderboard and Song Band Leaderboard. `fullRankingsUsesTwoColumnsOnlyFullWidthInWideLandscape`
/// pins the geometry; these hosted checks pin what assistive technologies get from it,
/// on every board:
///
/// - each row stays its own named button with its own identifier, at least 44 pt each way,
///   wholly on the page, never overlapping its neighbour (HIG Accessibility: 44×44 pt);
/// - VoiceOver reads the ranks in order, left then right and then down, which is the
///   visual row-major order and the very sequence (identifiers, roles and names) the
///   same board reads in one column (R2; HIG VoiceOver: "top-to-bottom, left-to-right");
/// - the pinned row and the pager still read after every row, left to right
///   ([leaderboard-row] R5);
/// - all of it with the stacked accessibility-size rows (`.accessibility5`; macOS keeps
///   its font size, so the iPad journey `WideBoardColumnsJourneyTests` shows real AX5
///   growth and runs the system audit);
/// - on the Mac, the arrow keys follow the grid: ↓/↑ move a line, ←/→ move across it
///   (HIG Focus and selection: "arrow keys move directionally" within a grid or list;
///   the Item Shop list's `macKeyboardRows(columns:)`, #378).
@MainActor
@Suite(.serialized)
struct WideBoardColumnsAccessibilityTests {
    /// A full board #353 pairs, with its row and chrome identifiers.
    enum Board: String, CaseIterable, CustomTestStringConvertible {
        case solo, fullRankings, bandRankings, songBand

        var testDescription: String { rawValue }

        /// Identifier prefix shared by the board's rows.
        var rowPrefix: String {
            switch self {
            case .solo: "fst.song-leaderboard.row."
            case .fullRankings: "fst.rankings.row."
            case .bandRankings: "fst.band-rankings.row."
            case .songBand: "fst.song-band-leaderboard.row."
            }
        }

        /// The identifier of the row at `rank` on page 1.
        func rowID(_ rank: Int) -> String {
            switch self {
            case .solo: "\(rowPrefix)fixture-other-\(rank)"
            case .fullRankings: "\(rowPrefix)fixture-ranked-\(rank)"
            case .bandRankings: BottomChromeBandBoard.bandRankings.rowId(rank)
            case .songBand: BottomChromeBandBoard.songBand.rowId(rank)
            }
        }

        /// The pinned row (where the board pins one) and the pager, in visual order.
        var chromeIDs: [String] {
            let prefix = switch self {
            case .solo: "fst.song-leaderboard"
            case .fullRankings: "fst.full-rankings"
            case .bandRankings: "fst.band-rankings"
            case .songBand: "fst.song-band-leaderboard"
            }
            let footer = switch self {
            case .solo, .fullRankings: ["\(prefix).spotlight-jump"]
            case .bandRankings, .songBand: [String]()
            }
            return footer + ["first", "previous", "info", "next", "last"].map { "\(prefix).page-\($0)" }
        }

        /// What Return opens for the row at `rank` (Mac arrow-key boards only).
        func routeMarker(_ rank: Int) -> String {
            switch self {
            case .fullRankings: "fixture-ranked-\(rank)"
            default: "fade-team-\(rank)"
            }
        }

        /// The board on page 1 with 25 rows; Solo and Full Rankings with a selected
        /// player ranked on a later page (a jump footer).
        @MainActor
        func screen() async throws -> AnyView {
            switch self {
            case .solo:
                let session = try await spotlightSelectedSession()
                return AnyView(SoloLeaderboardScreen(
                    song: try spotlightFixtureSong(), instrument: .lead, session: session,
                    initialPage: 1, path: .constant([]),
                    initialState: .loaded(try spotlightFixtureLeaderboard(spotlightRank: nil))
                ))
            case .fullRankings:
                let client = try FestivalAPI(
                    baseURL: try #require(URL(string: "http://localhost")), transport: LongRankingsTransport()
                )
                let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
                {"accountId":"\(LongRankingsTransport.selectedAccount)","displayName":"Reveal Player"}
                """.utf8))
                let session = FestivalSession(
                    factory: { client }, debugSelectedPlayer: try SelectedPlayerIdentity(searchResult: result)
                )
                return AnyView(FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore"))
            case .bandRankings, .songBand:
                let client = try FestivalAPI(
                    baseURL: try #require(URL(string: "http://localhost")), transport: LongBandBoardsTransport()
                )
                let board: BottomChromeBandBoard = self == .bandRankings ? .bandRankings : .songBand
                return try await board.screen(FestivalSession(factory: { client }))
            }
        }
    }

    /// Ranks checked on every board: two full lines and a third in two columns.
    static let ranks = Array(1...6)
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    static let minimumTarget: CGFloat = 44

    /// One hosted board.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }
    }

    // MARK: - Hosting

    /// Host `board` on page 1 at `placement`'s size and split role, fades off.
    ///
    /// - Parameters:
    ///   - board: The board.
    ///   - placement: Full width and wide (two columns), tall, or a split's sub-page.
    ///   - typeSize: Dynamic Type size.
    ///   - keyboard: Wrap the page in the Mac column's arrow-key navigation (as
    ///     `MacStack` does), in a titled window that can take key focus.
    ///   - push: Receives Return's route when `keyboard` is set.
    /// - Returns: The settled board with its first ranks and its chrome in the tree.
    static func host(
        _ board: Board, placement: WideBoardPlacement, typeSize: DynamicTypeSize = .large,
        keyboard: Bool = false, push: @escaping (AppRoute) -> Void = { _ in }
    ) async throws -> Hosted {
        let suiteName = "fst-wide-board-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let size = placement.size
        let page = try await board.screen()
            .splitPaneContext(placement.context)
        let navigated = keyboard
            ? AnyView(page.modifier(MacKeyboardNavigation(selection: nil, select: nil, push: push, isTop: true)))
            : AnyView(page)
        let host = nativeHostedView(
            AnyView(
                NavigationStack { navigated }
                    .frame(width: size.width, height: size.height)
                    .environment(\.festivalFadeInEnabled, false)
                    .environment(\.dynamicTypeSize, typeSize)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window: NSWindow
        if keyboard {
            window = NSWindow(
                contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            // Like the probe in `MacKeyboardNavigationTests`: an ordered-front window that
            // is not key keeps SwiftUI focus off the page, so keys never reach it.
            window.appearance = NSAppearance(named: .darkAqua)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
        } else {
            window = nativeHostedWindow(host, size: size)
        }
        let hosted = Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            ranks.allSatisfy { nativeHostedAccessibilityFrame(board.rowID($0), in: host) != nil }
                && board.chromeIDs.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
        }
        return hosted
    }

    // MARK: - Tree helpers

    /// The deepest table under `view` (the Solo board's `List`).
    static func table(in view: NSView) -> NSTableView? {
        for subview in view.subviews {
            if let found = table(in: subview) { return found }
        }
        return view as? NSTableView
    }

    /// The page's elements in VoiceOver's reading order: a `List` board's on-screen rows
    /// by row index (AppKit reorders recycled row views), else the navigation-order tree.
    static func readingOrder(_ host: NSView) -> [MacAXNode] {
        host.layoutSubtreeIfNeeded()
        if let table = table(in: host) {
            return macListReadingOrder(host, table: table).all
        }
        return macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    /// The element VoiceOver speaks for the row node at `index`: the row itself when it is
    /// the button (rankings boards), else the button it contains (the Song Leaderboard's
    /// row keeps its score texts as `.contain` children, so its button is the first child).
    static func rowButton(_ nodes: [MacAXNode], at index: Int) -> MacAXNode {
        let row = nodes[index]
        guard row.role != "AXButton" else { return row }
        return nodes[(index + 1)...].prefix { $0.depth > row.depth }.first { $0.isElement && $0.role == "AXButton" } ?? row
    }

    /// The board's row elements, in reading order.
    static func rows(_ nodes: [MacAXNode], _ board: Board) -> [MacAXNode] {
        nodes.filter { $0.identifier.hasPrefix(board.rowPrefix) }
    }

    // MARK: - Expectations

    /// Two columns are in effect: rank 2 sits beside rank 1 and rank 3 starts the next line.
    static func expectTwoColumns(_ hosted: Hosted, _ board: Board, _ context: String) throws {
        let frames = try (1...3).map { try #require(nativeHostedAccessibilityFrame(board.rowID($0), in: hosted.host)) }
        #expect(abs(frames[0].minY - frames[1].minY) < 1 && frames[1].minX > frames[0].maxX,
                "\(context): rank 2 beside rank 1: \(frames)")
        #expect(abs(frames[2].minX - frames[0].minX) < 1 && frames[2].minY >= frames[0].maxY - 0.5,
                "\(context): rank 3 starts the next line: \(frames)")
    }

    /// Each checked rank is one named button, a target of at least 44 pt each way, wholly
    /// on the page and clear of its neighbours.
    static func expectRowTargets(_ hosted: Hosted, _ board: Board, _ context: String) throws {
        let nodes = macAccessibilityTree(hosted.host)
        let bounds = hosted.host.bounds.insetBy(dx: -0.5, dy: -0.5)
        var frames: [CGRect] = []
        for rank in ranks {
            let id = board.rowID(rank)
            let matches = nodes.indices.filter { nodes[$0].isElement && nodes[$0].identifier == id }
            let index = try #require(matches.count == 1 ? matches.first : nil, "\(context): one element \(id):\n\(dump(nodes))")
            let node = rowButton(nodes, at: index)
            #expect(node.role == "AXButton", "\(context): rank \(rank) is a button: \(node)")
            #expect(!node.spokenName.isEmpty && !node.spokenName.contains("fst."),
                    "\(context): rank \(rank) has a spoken name: \(node)")
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: hosted.host))
            #expect(frame.width >= minimumTarget - 0.5 && frame.height >= minimumTarget - 0.5,
                    "\(context): rank \(rank) is a 44×44 pt target: \(frame)")
            #expect(frame.minX >= bounds.minX && frame.maxX <= bounds.maxX,
                    "\(context): rank \(rank) lies across the page, unclipped: \(frame)")
            frames.append(frame)
        }
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] {
                let overlap = frame.insetBy(dx: 0.5, dy: 0.5).intersection(other.insetBy(dx: 0.5, dy: 0.5))
                #expect(overlap.isNull || overlap.isEmpty, "\(context): rows overlap: \(frame) and \(other)")
            }
        }
    }

    /// VoiceOver reads the checked ranks consecutively in rank order, which is the drawn
    /// row-major order, and then the pinned row and pager after every row, left to right.
    static func expectReadingOrder(_ hosted: Hosted, _ board: Board, _ context: String) throws {
        let order = readingOrder(hosted.host)
        let rowIDs = rows(order, board).map(\.identifier)
        let expected = ranks.map(board.rowID)
        let first = try #require(rowIDs.firstIndex(of: expected[0]), "\(context): rank 1 is read:\n\(dump(order))")
        #expect(Array(rowIDs[first...].prefix(expected.count)) == expected,
                "\(context): ranks read in order: \(rowIDs)")
        // The rank order is the drawn order: each line left to right, then down.
        let frames = try expected.map { try #require(nativeHostedAccessibilityFrame($0, in: hosted.host)) }
        let drawn = zip(expected, frames).sorted { lhs, rhs in
            abs(lhs.1.minY - rhs.1.minY) < 1 ? lhs.1.minX < rhs.1.minX : lhs.1.minY < rhs.1.minY
        }.map(\.0)
        #expect(drawn == expected, "\(context): reading order matches the drawn order: \(drawn)")
        let lastRow = try #require(order.lastIndex { $0.identifier.hasPrefix(board.rowPrefix) })
        let chrome = try board.chromeIDs.map { id in
            try #require(order.firstIndex { $0.identifier == id }, "\(context): \(id) is read:\n\(dump(order))")
        }
        #expect(chrome.allSatisfy { $0 > lastRow }, "\(context): rows read before the chrome: \(chrome) vs \(lastRow)")
        #expect(chrome == chrome.sorted(), "\(context): the pinned row, then the pager left to right: \(chrome)")
    }

    // MARK: - Tests

    /// In two columns, at the default and the largest accessibility size, every row is a
    /// named 44 pt button on the page and the board reads in rank order before its chrome.
    @Test(arguments: Board.allCases, [DynamicTypeSize.large, .accessibility5])
    func twoColumnRowsKeepNamesTargetsAndOrder(board: Board, typeSize: DynamicTypeSize) async throws {
        let hosted = try await Self.host(board, placement: .wide, typeSize: typeSize)
        defer { hosted.close() }
        let context = "\(board) \(typeSize)"
        macAccessibilityDump(Self.readingOrder(hosted.host), name: "wide-board-\(board.rawValue)-\(typeSize)")
        try Self.expectTwoColumns(hosted, board, context)
        try Self.expectRowTargets(hosted, board, context)
        try Self.expectReadingOrder(hosted, board, context)
    }

    /// Pairing the rows changes nothing VoiceOver reads: the same board in one column (a
    /// split's sub-page at the same size) reads the same rows with the same identifiers,
    /// roles and names in the same order (wide-columns R2).
    @Test(arguments: Board.allCases)
    func twoColumnsReadTheSameSequenceAsOneColumn(board: Board) async throws {
        func sequence(_ placement: WideBoardPlacement) async throws -> [String] {
            let hosted = try await Self.host(board, placement: placement)
            defer { hosted.close() }
            if placement == .splitTrailing {
                let one = try #require(nativeHostedAccessibilityFrame(board.rowID(1), in: hosted.host))
                let two = try #require(nativeHostedAccessibilityFrame(board.rowID(2), in: hosted.host))
                #expect(two.minY >= one.maxY - 0.5 && abs(two.minX - one.minX) < 1,
                        "\(board): the sub-page is one column: \(one) \(two)")
            }
            // Every element from the first row to the last read row: the rows and what
            // they contain (the Song Leaderboard row's button).
            let order = Self.readingOrder(hosted.host)
            let first = try #require(order.firstIndex { $0.identifier.hasPrefix(board.rowPrefix) })
            let last = try #require(order.lastIndex { $0.identifier.hasPrefix(board.rowPrefix) })
            return order[first...last].map { "\($0.identifier) \($0.role) '\($0.spokenName)'" }
        }
        let paired = try await sequence(.wide)
        let single = try await sequence(.splitTrailing)
        let shared = min(paired.count, single.count)
        #expect(shared >= Self.ranks.count, "\(board): both read the first ranks: \(paired.count), \(single.count)")
        #expect(Array(paired.prefix(shared)) == Array(single.prefix(shared)),
                "\(board): two columns read like one:\n\(paired.joined(separator: "\n"))\nvs\n\(single.joined(separator: "\n"))")
    }

    /// On the Mac the arrow keys follow the two-column grid of a board that offers
    /// keyboard rows: ↓ ↓ moves from rank 1 down to rank 3, → to rank 4, ← back to rank 3,
    /// ↑ to rank 1, → to rank 2 (each the highlighted, selected row), and Return opens it.
    /// In one column ↓ ↓ still reaches rank 2.
    @Test(arguments: [Board.fullRankings, .bandRankings])
    func arrowKeysFollowTheTwoColumnGrid(board: Board) async throws {
        var pushed: [AppRoute] = []
        let hosted = try await Self.host(board, placement: .wide, keyboard: true) { pushed.append($0) }
        defer { hosted.close() }
        func selected() -> [String] {
            macAccessibilityTree(hosted.host)
                .filter { $0.isElement && $0.selected && $0.identifier.hasPrefix(board.rowPrefix) }
                .map(\.identifier)
        }
        func press(_ key: String, expect rank: Int) async throws {
            sendKey(key, to: hosted.window)
            _ = try await nativeHostedSettle(hosted.host, timeout: .seconds(5)) { selected() == [board.rowID(rank)] }
            #expect(selected() == [board.rowID(rank)], "\(board): \(key) highlights rank \(rank): \(selected())")
        }
        try Self.expectTwoColumns(hosted, board, "\(board) keyboard")
        try await press("down", expect: 1)
        try await press("down", expect: 3)
        try await press("right", expect: 4)
        try await press("left", expect: 3)
        try await press("up", expect: 1)
        try await press("right", expect: 2)
        sendKey("return", to: hosted.window)
        _ = try await nativeHostedSettle(hosted.host, timeout: .seconds(20)) { !pushed.isEmpty }
        #expect(pushed.count == 1 && "\(pushed[0])".contains(board.routeMarker(2)), "\(board): Return opens rank 2: \(pushed)")

        let tall = try await Self.host(board, placement: .tall, keyboard: true)
        defer { tall.close() }
        sendKey("down", to: tall.window)
        sendKey("down", to: tall.window)
        _ = try await nativeHostedSettle(tall.host, timeout: .seconds(20)) {
            macAccessibilityTree(tall.host).contains { $0.selected && $0.identifier == board.rowID(2) }
        }
        #expect(macAccessibilityTree(tall.host).contains { $0.selected && $0.identifier == board.rowID(2) },
                "\(board): one column, ↓ ↓ highlights rank 2")
    }
}
#endif
