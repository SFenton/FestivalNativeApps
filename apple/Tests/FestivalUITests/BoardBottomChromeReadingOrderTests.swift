#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Board bottom chrome reading order (issue #461)

/// Every paginated board pins its selected row and pager under the rows as a bottom
/// safe-area inset (``SwiftUI/View/boardBottomChrome(_:)``). SwiftUI orders an inset's
/// content before the view it insets, so VoiceOver read the pinned row and pager before
/// the board's rows until #461; these hosted checks keep the web DOM order — rows, then
/// the pinned row, then the pager — on each board that uses the inset ([leaderboard-row]
/// R5). The song band board's own footer checks live in `SongBandFooterAccessibilityTests`.
///
/// HIG VoiceOver: "Specify how elements are grouped, ordered or linked where relationships
/// are only visual"; it reads "top-to-bottom, left-to-right" in US English.
@MainActor
@Suite(.serialized)
struct BoardBottomChromeReadingOrderTests {
    /// A board with bottom chrome, its row identifiers and its chrome controls.
    enum Board: String, CaseIterable, CustomTestStringConvertible {
        case solo, fullRankings, bandRankings, playerBands

        var testDescription: String { rawValue }

        /// Identifier prefix shared by the board's rows.
        var rowPrefix: String {
            switch self {
            case .solo: "fst.song-leaderboard.row."
            case .fullRankings: "fst.rankings.row."
            case .bandRankings: "fst.band-rankings.row."
            case .playerBands: "fst.player-bands.row."
            }
        }

        /// The pinned selected row's action, where the board pins one.
        var footerID: String? {
            switch self {
            case .solo: "fst.song-leaderboard.spotlight-jump"
            case .fullRankings: "fst.full-rankings.spotlight-jump"
            case .bandRankings, .playerBands: nil
            }
        }

        /// The pager's controls, in visual order.
        var pagerIDs: [String] {
            let prefix = switch self {
            case .solo: "fst.song-leaderboard"
            case .fullRankings: "fst.full-rankings"
            case .bandRankings: "fst.band-rankings"
            case .playerBands: "fst.player-bands"
            }
            return ["first", "previous", "info", "next", "last"].map { "\(prefix).page-\($0)" }
        }

        /// The board on page 1, with a selected profile whose row is on a later page.
        @MainActor
        func screen() async throws -> AnyView {
            switch self {
            case .solo:
                let session = try await spotlightSelectedSession()
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
                return AnyView(FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore"))
            case .bandRankings:
                let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: LongBandBoardsTransport())
                return AnyView(BandRankingsScreen(session: FestivalSession(factory: { client }), bandType: "Band_Duets"))
            case .playerBands:
                let client = try FestivalAPI(
                    baseURL: try await RivalsMockService.shared.baseURL(), transport: URLSessionHTTPTransport()
                )
                return AnyView(PlayerBandsScreen(
                    session: FestivalSession(factory: { client }),
                    accountId: "fixture-player-1", displayName: "Fixture Player 1"
                ))
            }
        }
    }

    /// The board's rows read first, then its pinned row, then its pager, left to right.
    @Test(arguments: Board.allCases)
    func rowsReadBeforeThePinnedRowAndPager(board: Board) async throws {
        let size = CGSize(width: 402, height: 900)
        let screen = try await board.screen()
        let suite = "fst-board-chrome-order-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        defer { storage.removePersistentDomain(forName: suite) }
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let host = nativeHostedView(
            NavigationStack { screen }
                .frame(width: size.width, height: size.height)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, .compact),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let chromeIDs = (board.footerID.map { [$0] } ?? []) + board.pagerIDs
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            chromeIDs.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
                && macAccessibilityTree(host).contains { $0.identifier.hasPrefix(board.rowPrefix) && $0.isElement }
        }
        let tree = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(tree, name: "board-chrome-order-\(board.rawValue)")
        let order = tree.filter(\.isElement)
        let rows = order.indices.filter { order[$0].identifier.hasPrefix(board.rowPrefix) }
        let chrome = try chromeIDs.map { id in
            try #require(order.firstIndex { $0.identifier == id }, "\(id) in the reading order")
        }
        let lastRow = try #require(rows.last, "rows in the reading order")
        #expect(chrome.allSatisfy { $0 > lastRow }, "rows (\(rows)) read before the chrome (\(chrome))")
        #expect(chrome == chrome.sorted(), "the pinned row, then the pager left to right: \(chrome)")
    }
}
#endif
