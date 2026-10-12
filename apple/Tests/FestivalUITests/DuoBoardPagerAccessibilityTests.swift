#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Duo board pager accessibility (issue #481, for #345)

/// #345 put every paged board's pager back under the board on the iPhone Duo vertical
/// bar (folded, outer landscape and unfolded, where ``PagerScreenPlacement`` moves it to
/// the screen beside the bar) and in a split's trailing pane, instead of First, Previous,
/// Next and Last rail toolbar items (``RankingsPagerView``; Band Rankings'
/// ``RankingsFloatingBar`` shows the pager alone there). `DuoBoardPagerHostedTests` pins
/// where it sits; these hosted checks pin what assistive technologies get from it on every
/// board shape that changed (the song board and Full Rankings with a pinned selected row,
/// Band Rankings' floating bar), in each Duo pose and the split's trailing pane:
///
/// - each pager control is exposed once (no second, rail copy), with its name, button
///   role and page-1 state, and the badge reads "Page, 1 of N";
/// - reading order is the board's rows, then the pinned selected row, then the pager left
///   to right, and the pager's frames run in that order;
/// - every control is a 44 pt target on the board, and on the screen beside the vertical
///   bar when a hinge crosses the board;
/// - the accessibility press (VoiceOver, Voice Control, Switch Control) on Next pages the
///   board, and First and Previous then enable;
/// - at the largest accessibility size the controls stay on the board, 44 pt each, under
///   the pinned row and clear of the hinge.
///
/// The SwiftUI is the same on iPhone Duo, iPad and Mac. macOS keeps its font size, so the
/// iOS journey `DuoBoardPagerAccessibilityJourneyTests` (with
/// `SongLeaderboardEndJourneyTests`' folded Duo case) checks real AX5 text, the rail and
/// the system audit.
///
/// HIG Designing for iPhone Duo: "Keep controls near the content they affect". HIG
/// Accessibility: iOS, iPadOS default control size 44×44 pt. HIG VoiceOver: "Specify how
/// elements are grouped, ordered or linked where relationships are only visual".
@MainActor
@Suite(.serialized)
struct DuoBoardPagerAccessibilityTests {
    // MARK: - Fixture

    /// A paged board #345 changed.
    enum Board: String, CustomTestStringConvertible {
        /// The full song board (`RankingsPagerView`), selected player pinned off page.
        case song
        /// Full Rankings (`RankingsPagerView`), selected player pinned off page.
        case fullRankings
        /// Band Rankings (`RankingsFloatingBar`), no selected player.
        case bandRankings

        var testDescription: String { rawValue }

        var idPrefix: String {
            switch self {
            case .song: "fst.song-leaderboard"
            case .fullRankings: "fst.full-rankings"
            case .bandRankings: "fst.band-rankings"
            }
        }

        var rowPrefix: String {
            switch self {
            case .song: "fst.song-leaderboard.row."
            case .fullRankings: "fst.rankings.row."
            case .bandRankings: "fst.band-rankings.row."
            }
        }

        /// The pinned selected row's Jump control, where the board pins one.
        var footerID: String? {
            switch self {
            case .song: "fst.song-leaderboard.spotlight-jump"
            case .fullRankings: "fst.full-rankings.spotlight-jump"
            case .bandRankings: nil
            }
        }

        /// Pages in the fixture board.
        var totalPages: Int {
            switch self {
            case .song: 20
            case .fullRankings, .bandRankings: 3
            }
        }

        /// Whether the fixture transport serves page 2, so the board can page.
        var pages: Bool { self != .song }
    }

    /// Where the board is shown.
    enum Placement: String, CustomTestStringConvertible {
        case duoFolded, duoOuterLandscape, duoUnfolded, splitTrailing

        var testDescription: String { rawValue }

        var layout: DeviceLayout {
            switch self {
            case .duoFolded: DuoBoardPose.folded.layout
            case .duoOuterLandscape: DuoBoardPose.outerLandscape.layout
            case .duoUnfolded: DuoBoardPose.unfolded.layout
            case .splitTrailing: .standardPhone
            }
        }

        var size: CGSize {
            switch self {
            case .duoFolded: DuoBoardPose.folded.boardSize
            case .duoOuterLandscape: DuoBoardPose.outerLandscape.boardSize
            case .duoUnfolded: DuoBoardPose.unfolded.boardSize
            case .splitTrailing: CGSize(width: 520, height: 900)
            }
        }
    }

    /// One board in one placement.
    struct Case: CustomTestStringConvertible, Sendable {
        let board: Board
        let placement: Placement

        var testDescription: String { "\(board.rawValue)-\(placement.rawValue)" }
    }

    /// Every board in every Duo vertical-bar pose, and the song board in a split's
    /// trailing pane (Full Rankings and Band Rankings never open there).
    nonisolated static let cases: [Case] = [Board.song, .fullRankings, .bandRankings].flatMap { board in
        [Placement.duoFolded, .duoOuterLandscape, .duoUnfolded].map { Case(board: board, placement: $0) }
    } + [Case(board: .song, placement: .splitTrailing)]

    /// Boards that page through their fixture transport, in every Duo pose.
    nonisolated static let pagingCases: [Case] = cases.filter { $0.board.pages }

    /// The pager's arrows in visual order, with the word each name carries and whether
    /// page 1 enables it.
    static let arrows = [
        (suffix: "page-first", word: "First", enabledOnFirst: false),
        (suffix: "page-previous", word: "Previous", enabledOnFirst: false),
        (suffix: "page-next", word: "Next", enabledOnFirst: true),
        (suffix: "page-last", word: "Last", enabledOnFirst: true),
    ]
    /// The pager's controls in visual and reading order.
    static let pagerSuffixes = ["page-first", "page-previous", "page-info", "page-next", "page-last"]
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    static let minimumTarget: CGFloat = 44

    /// One hosted board.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String
        let testCase: Case

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        func id(_ suffix: String) -> String { "\(testCase.board.idPrefix).\(suffix)" }
    }

    /// The board's screen on page 1 over its keyless fixture transport.
    static func screen(_ board: Board) async throws -> AnyView {
        switch board {
        case .song:
            let session = try await spotlightSelectedSession()
            // The selected player (rank 57) is off this page, so the pinned Jump shows.
            let payload = try spotlightFixtureLeaderboard(spotlightRank: nil)
            return AnyView(SoloLeaderboardScreen(
                song: try spotlightFixtureSong(), instrument: .lead, session: session,
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            ))
        case .fullRankings:
            let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongRankingsTransport())
            let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
            {"accountId":"\(LongRankingsTransport.selectedAccount)","displayName":"Reveal Player"}
            """.utf8))
            let session = FestivalSession(
                factory: { client }, debugSelectedPlayer: try SelectedPlayerIdentity(searchResult: result)
            )
            return AnyView(FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore", page: 1))
        case .bandRankings:
            let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongBandBoardsTransport())
            return AnyView(BandRankingsScreen(session: FestivalSession(factory: { client }), bandType: "Band_Duets"))
        }
    }

    /// Host `testCase`'s board with the placement's layout and wait for its rows, pinned
    /// row and pager.
    ///
    /// - Parameters:
    ///   - testCase: The board and placement.
    ///   - typeSize: Dynamic Type size for the whole page.
    /// - Returns: The settled board.
    /// - Throws: A board that never settles.
    static func host(_ testCase: Case, typeSize: DynamicTypeSize = .large) async throws -> Hosted {
        nativeHostedEnableAccessibility()
        let board = testCase.board, placement = testCase.placement
        let suiteName = "fst-duo-board-pager-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let context: SplitPaneContext? = placement == .splitTrailing
            ? SplitPaneContext(paneWidth: placement.size.width, role: .trailing, besideList: .songDetail) : nil
        let screen = try await screen(board)
        let size = placement.size
        let host = nativeHostedView(
            AnyView(
                NavigationStack { screen.splitPaneContext(context) }
                    .environment(\.deviceLayout, placement.layout)
                    .environment(\.dynamicTypeSize, typeSize)
                    .frame(width: size.width, height: size.height)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let hosted = Hosted(host: host, window: window, storage: storage, suiteName: suiteName, testCase: testCase)
        let chrome = (board.footerID.map { [$0] } ?? []) + pagerSuffixes.map(hosted.id)
        do {
            try await nativeHostedSettle(host, timeout: .seconds(60)) {
                chrome.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
                    && macAccessibilityTree(host).contains { $0.identifier.hasPrefix(board.rowPrefix) && $0.isElement }
            }
        } catch {
            hosted.close()
            throw error
        }
        return hosted
    }

    /// The page badge's spoken value. An adjustable element on macOS (AXUnknown) reports
    /// it as the value description, which VoiceOver reads.
    static func pageValue(_ hosted: Hosted, in nodes: [MacAXNode]) -> String {
        guard let info = nodes.first(where: { $0.identifier == hosted.id("page-info") && $0.isElement }) else { return "" }
        if !info.value.isEmpty { return info.value }
        return nativeHostedAccessibilityElement(info.identifier, in: hosted.host)?
            .value(forKey: "accessibilityValueDescription") as? String ?? ""
    }

    /// Press a control the way VoiceOver (VO-Space), Voice Control and Switch Control do.
    static func press(_ identifier: String, in host: NSView) throws {
        let control = try #require(nativeHostedAccessibilityElement(identifier, in: host), "\(identifier) to press")
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(control.responds(to: press), "\(identifier) offers a press action")
        _ = control.perform(press)
    }

    /// Every pager frame, in visual order.
    static func pagerFrames(_ hosted: Hosted) throws -> [CGRect] {
        hosted.host.layoutSubtreeIfNeeded()
        return try pagerSuffixes.map { suffix in
            try #require(nativeHostedAccessibilityFrame(hosted.id(suffix), in: hosted.host), "\(hosted.id(suffix)) frame")
        }
    }

    /// Each control is a 44 pt target wholly on the board, left to right, and on the
    /// screen beside the vertical bar where a hinge crosses the board.
    static func expectTargets(
        _ frames: [CGRect], _ hosted: Hosted, _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let placement = hosted.testCase.placement
        let board = placement.size
        for (suffix, frame) in zip(pagerSuffixes, frames) {
            #expect(frame.width >= minimumTarget - 0.5 && frame.height >= minimumTarget - 0.5,
                    "\(context): \(suffix) target \(frame)", sourceLocation: sourceLocation)
            #expect(frame.minX >= -0.5 && frame.maxX <= board.width + 0.5 && frame.minY >= -0.5
                        && frame.maxY <= board.height + 0.5,
                    "\(context): \(suffix) \(frame) leaves the board \(board)", sourceLocation: sourceLocation)
        }
        for (left, right) in zip(frames, frames.dropFirst()) {
            #expect(right.minX >= left.maxX - 0.5, "\(context): pager out of visual order \(left) → \(right)",
                    sourceLocation: sourceLocation)
        }
        if let hinge = placement.layout.screenDivide(), hinge.minX < board.width {
            let span = frames.reduce(frames[0]) { $0.union($1) }
            #expect(span.minX >= hinge.maxX, "\(context): pager \(span) is not on the screen beside the bar (\(hinge))",
                    sourceLocation: sourceLocation)
        }
    }

    // MARK: - Names, roles, state and reading order

    /// Each pager control is exposed once, named, a button with its page-1 state; the
    /// badge reads "Page, 1 of N"; and the board reads rows → pinned row → pager left to
    /// right, matching the layout.
    @Test(arguments: cases)
    func pagerIsNamedOnceAndReadsAfterTheBoard(_ testCase: Case) async throws {
        let hosted = try await Self.host(testCase)
        defer { hosted.close() }
        let context = testCase.testDescription
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "duo-board-pager-\(context)")
        let tree = nodes.map(\.description).joined(separator: "\n")

        for arrow in Self.arrows {
            let id = hosted.id(arrow.suffix)
            let matches = nodes.filter { $0.identifier == id && $0.isElement }
            #expect(matches.count == 1, "\(context): \(id) is exposed once, not again in a rail:\n\(tree)")
            let node = try #require(matches.first, "\(context): \(id)")
            #expect(node.role == "AXButton", "\(context): \(id) is a button: \(node)")
            #expect(node.spokenName.localizedCaseInsensitiveContains(arrow.word) && node.spokenName.contains(" "),
                    "\(context): \(id) reads '\(node.spokenName)'")
            #expect(node.isEnabled == arrow.enabledOnFirst, "\(context): \(id) enabled on page 1: \(node)")
            // No other element speaks the arrow's action (the old rail's "Next" items).
            let sameName = nodes.filter {
                $0.isElement && $0.identifier != id && $0.spokenName.localizedCaseInsensitiveCompare(node.spokenName) == .orderedSame
            }
            #expect(sameName.isEmpty, "\(context): a second '\(node.spokenName)': \(sameName)")
        }
        let info = try #require(nodes.first { $0.identifier == hosted.id("page-info") && $0.isElement })
        #expect(info.spokenName == "Page", "\(context): the badge is named Page: \(info)")
        #expect(Self.pageValue(hosted, in: nodes) == "1 of \(testCase.board.totalPages)", "\(context): badge value")
        #expect(macAccessibilityFindings(nodes) == [], "\(context): unnamed controls or images")

        let order = macAccessibilityTree(hosted.host, navigationOrder: true).filter(\.isElement)
        let rows = order.indices.filter { order[$0].identifier.hasPrefix(testCase.board.rowPrefix) }
        let chromeIDs = (testCase.board.footerID.map { [$0] } ?? []) + Self.pagerSuffixes.map(hosted.id)
        let chrome = try chromeIDs.map { id in
            try #require(order.firstIndex { $0.identifier == id }, "\(context): \(id) in the reading order")
        }
        let lastRow = try #require(rows.last, "\(context): rows in the reading order")
        #expect(chrome.allSatisfy { $0 > lastRow }, "\(context): rows (\(rows)) read before the chrome (\(chrome))")
        #expect(chrome == chrome.sorted(), "\(context): the pinned row, then the pager left to right: \(chrome)")

        let frames = try Self.pagerFrames(hosted)
        Self.expectTargets(frames, hosted, context)
        if let footerID = testCase.board.footerID {
            let footer = try #require(nativeHostedAccessibilityFrame(footerID, in: hosted.host))
            #expect(footer.maxY <= (frames.map(\.minY).min() ?? 0) + 0.5,
                    "\(context): the pinned row \(footer) reads and sits above the pager")
            #expect(footer.height >= Self.minimumTarget - 0.5, "\(context): the pinned row target \(footer)")
        }
    }

    // MARK: - Activation

    /// The accessibility press on Next shows page 2 in place: the badge reads "2 of N",
    /// First and Previous enable, and the pager stays one set of 44 pt targets under the
    /// board (beside the bar when unfolded).
    @Test(arguments: pagingCases)
    func pressingNextPagesTheBoardInPlace(_ testCase: Case) async throws {
        let hosted = try await Self.host(testCase)
        defer { hosted.close() }
        let context = testCase.testDescription
        try Self.press(hosted.id("page-next"), in: hosted.host)
        let total = testCase.board.totalPages
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            let nodes = macAccessibilityTree(hosted.host)
            return Self.pageValue(hosted, in: nodes) == "2 of \(total)"
                && nodes.contains { $0.identifier == hosted.id("page-first") && $0.isElement && $0.isEnabled }
        }
        let nodes = macAccessibilityTree(hosted.host)
        for suffix in ["page-first", "page-previous", "page-next", "page-last"] {
            let matches = nodes.filter { $0.identifier == hosted.id(suffix) && $0.isElement }
            #expect(matches.count == 1, "\(context): \(suffix) once after paging")
            #expect(matches.first?.isEnabled == true, "\(context): \(suffix) enabled on page 2")
        }
        Self.expectTargets(try Self.pagerFrames(hosted), hosted, "\(context) page 2")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the pager keeps its five controls, 44 pt each,
    /// wholly on the board under the pinned row and clear of the hinge, with the same
    /// names. macOS text keeps its size, so this pins the accessibility-size layouts
    /// (the pinned row stacks); the iOS journey measures real AX5 text.
    @Test(arguments: cases)
    func pagerStaysReachableAtAccessibilitySizes(_ testCase: Case) async throws {
        let hosted = try await Self.host(testCase, typeSize: .accessibility5)
        defer { hosted.close() }
        let context = "\(testCase.testDescription) AX5"
        let nodes = macAccessibilityTree(hosted.host)
        for arrow in Self.arrows {
            let node = try #require(nodes.first { $0.identifier == hosted.id(arrow.suffix) && $0.isElement })
            #expect(node.spokenName.localizedCaseInsensitiveContains(arrow.word), "\(context): \(node)")
        }
        let frames = try Self.pagerFrames(hosted)
        Self.expectTargets(frames, hosted, context)
        if let footerID = testCase.board.footerID {
            let footer = try #require(nativeHostedAccessibilityFrame(footerID, in: hosted.host))
            #expect(footer.minY >= -0.5, "\(context): the pinned row stays on screen: \(footer)")
            #expect(footer.maxY <= (frames.map(\.minY).min() ?? 0) + 0.5, "\(context): the pinned row \(footer) over the pager")
        }
        #expect(macAccessibilityFindings(nodes) == [], "\(context): unnamed controls or images")
    }
}
#endif
