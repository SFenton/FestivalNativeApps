#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Song Leaderboard end of list accessibility (issue #456, for #293)

/// Keyless fixture transport for the Song Leaderboard end-of-list checks: the
/// publication plus two compact player profiles, one with a ranked Lead score on
/// `fixture-pulse` (rank 57, page 3) and one whose only score is on another song.
/// Rejects the privileged key, selected-profile headers, writes and any other route.
private actor SoloEndTransport: HTTPTransport {
    static let generation = 13
    static let scoredPlayer = "fixture-spotlight-player"
    static let unscoredPlayer = "fixture-elsewhere-player"

    func send(_ request: URLRequest) async throws -> HTTPResult {
        guard let url = request.url, request.httpMethod == "GET",
              request.value(forHTTPHeaderField: "X-API-Key") == nil,
              request.allHTTPHeaderFields?.keys.contains(where: {
                  $0.lowercased().hasPrefix("x-fst-selected-")
              }) != true else {
            throw FestivalAPIError.invalidResponse
        }
        if url.path == "/api/publication" {
            return HTTPResult(status: 200, data: Data("""
            {"contractVersion":1,"publicationId":\(Self.generation),"publishedScrapeId":42,
             "readyForPinning":true,"pinningEnabled":true,"unreadySurfaces":[]}
            """.utf8))
        }
        let prefix = "/api/player/"
        guard url.path.hasPrefix(prefix),
              request.value(forHTTPHeaderField: "X-FST-Publication-Id") == String(Self.generation)
        else {
            throw FestivalAPIError.invalidPlayerProfile
        }
        let pinned = ["X-FST-Publication-Id": String(Self.generation)]
        switch String(url.path.dropFirst(prefix.count)) {
        case Self.scoredPlayer:
            return HTTPResult(status: 200, data: Data("""
            {"accountId":"\(Self.scoredPlayer)","displayName":"Spotlight Player","totalScores":1,
             "scores":[{"si":"fixture-pulse","ins":"01","sc":95000,"rk":57,"te":500}]}
            """.utf8), headers: pinned)
        case Self.unscoredPlayer:
            return HTTPResult(status: 200, data: Data("""
            {"accountId":"\(Self.unscoredPlayer)","displayName":"Elsewhere Player","totalScores":1,
             "scores":[{"si":"fixture-other-song","ins":"01","sc":91000,"rk":4,"te":500}]}
            """.utf8), headers: pinned)
        default:
            throw FestivalAPIError.invalidPlayerProfile
        }
    }
}

/// Accessibility of the Song Leaderboard's end of list and header as #293 left them
/// (issue #456).
///
/// #293 removed the header's dark gradient, dropped the 36 pt bottom content margin and
/// rested the last row one 8 pt row gap above the pinned footer, or above the pager when
/// there is no footer, with the bottom fade shrinking to nothing as the last row arrives
/// (`PinnedChromeSpacing`, `ScrollEdgeFade.bottomDistance`). Its tests were unit tests
/// of that arithmetic only. These hosted checks pin what VoiceOver, Voice Control and
/// a low-vision reader meet on the real screen at the end of page 1, for each footer
/// state (a selected player off this page, on it, with no score on this chart, and no
/// player), with the fade (standard) and with the scroll-edge R7 hard edge (the app's
/// Increase Contrast and system Reduce Transparency):
///
/// - the last row is one named, enabled 44 pt button, wholly above the chrome, one
///   8 pt row gap above the footer or pager, and as bright as the row above it;
/// - the footer (when shown) is one named 44 pt button one row gap above the pager,
///   and no footer appears without a ranked score here;
/// - the pager arrows are named 44 pt buttons in their page-1 enabled states, below
///   the chrome top;
/// - VoiceOver reads the rows, then the footer, then the pager;
/// - the song header is one heading reading the title, artist and board, with its text
///   drawn bright on the page background and nothing else reachable over it.
///
/// This SwiftUI is the same on iPhone, iPad, iPhone Duo and Mac. macOS keeps its font
/// size, so the iOS journey `SongLeaderboardEndJourneyTests` checks the same end of
/// list at the largest accessibility text size.
///
/// HIG Accessibility: iOS, iPadOS default control size 44×44 pt; text up to 17 pt needs
/// 4.5:1 contrast. HIG VoiceOver: "Specify how elements are grouped, ordered or linked
/// where relationships are only visual".
@MainActor
@Suite(.serialized)
struct SoloLeaderboardEndAccessibilityTests {
    /// What the pinned footer shows.
    enum Footer: String, CaseIterable, CustomTestStringConvertible {
        /// A selected player ranked on a later page: a Jump footer.
        case jump
        /// A selected player whose row is on this page: an Open footer.
        case open
        /// A selected player with no score on this chart: no footer.
        case noScore
        /// No selected player: no footer.
        case anonymous

        var testDescription: String { rawValue }

        /// The footer control's identifier, nil when no footer shows.
        var footerID: String? {
            switch self {
            case .jump: "fst.song-leaderboard.spotlight-jump"
            case .open: "fst.song-leaderboard.spotlight-open"
            case .noScore, .anonymous: nil
            }
        }

        /// What the footer's spoken name ends with.
        var footerAction: String? {
            switch self {
            case .jump: "Jump to your position."
            case .open: "Open your statistics."
            case .noScore, .anonymous: nil
            }
        }

        /// A session in this state, selected through the real `viewPlayer`/`selectPlayer` path.
        @MainActor
        func session() async throws -> FestivalSession {
            let client = try FestivalAPI(transport: SoloEndTransport())
            let session = FestivalSession(factory: { client })
            let accountId: String
            switch self {
            case .anonymous: return session
            case .jump, .open: accountId = SoloEndTransport.scoredPlayer
            case .noScore: accountId = SoloEndTransport.unscoredPlayer
            }
            let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
            {"accountId":"\(accountId)","displayName":"Selected Player"}
            """.utf8))
            try session.selectPlayer(result, from: await session.viewPlayer(result))
            #expect(session.playerLoadState == .available)
            return session
        }

        /// Page 1, with the selected player's row at rank 3 for ``open``.
        func payload() throws -> LeaderboardPayload {
            try spotlightFixtureLeaderboard(spotlightRank: self == .open ? 3 : nil)
        }
    }

    /// The pager's arrows: identifier suffix, a word its name carries, and whether page 1 enables it.
    static let pagerArrows = [
        (suffix: "page-first", word: "First", enabledOnFirstPage: false),
        (suffix: "page-previous", word: "Previous", enabledOnFirstPage: false),
        (suffix: "page-next", word: "Next", enabledOnFirstPage: true),
        (suffix: "page-last", word: "Last", enabledOnFirstPage: true),
    ]
    /// The space between two rows, and so between the last row and the chrome (#293).
    static let rowGap: CGFloat = 8
    /// Layout rounding allowed on a measured gap.
    static let gapTolerance: CGFloat = 1.5
    static let rowPrefix = "fst.song-leaderboard.row."
    static let size = CGSize(width: 402, height: 700)

    /// The board on page 1 in `footer`'s state and `mode`, in a navigation stack, settled.
    private func hostBoard(
        _ footer: Footer, mode: BottomChromeFadeMode
    ) async throws -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow, () -> Void) {
        let session = try await footer.session()
        let payload = try footer.payload()
        let song = try spotlightFixtureSong()
        let (defaults, suite) = mode.storage()
        let host = nativeHostedView(
            mode.system(
                NavigationStack {
                    SoloLeaderboardScreen(
                        song: song, instrument: .lead, session: session,
                        initialPage: 1, path: .constant([]), initialState: .loaded(payload)
                    )
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .preferredColorScheme(.dark)
                .defaultAppStorage(defaults)
                .environment(\.horizontalSizeClass, .compact)
            ),
            size: Self.size, forceGlassFallback: false
        )
        let window = nativeHostedWindow(host, size: Self.size)
        let chromeIDs = (footer.footerID.map { [$0] } ?? []) + ["fst.song-leaderboard.page-first"]
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            chromeIDs.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
                && nativeHostedAccessibilityFrame("fst.song-leaderboard.header", in: host) != nil
        }
        return (host, window, {
            window.orderOut(nil)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        })
    }

    /// The last row rests one row gap above the footer or pager, readable and reachable,
    /// and the footer and pager keep their names, states, targets and reading order.
    @Test(arguments: Footer.allCases, [BottomChromeFadeMode.standard, .moreContrast, .systemReduceTransparency])
    func lastRowRestsOneRowGapAboveTheChrome(footer: Footer, mode: BottomChromeFadeMode) async throws {
        let (host, _, cleanup) = try await hostBoard(footer, mode: mode)
        defer { cleanup() }
        let scroll = try #require(boardScrollView(in: host))
        let scrollFrame = scroll.convert(scroll.bounds, to: host)
        // The pinned footer and pager are the scroll view's bottom inset (#461).
        #expect(scroll.contentInsets.bottom > 30)
        let chromeTop = scrollFrame.maxY - scroll.contentInsets.bottom

        // Scroll to the end of the page.
        let document = try #require(scroll.documentView)
        let end = document.frame.height + scroll.contentInsets.bottom - scroll.contentView.bounds.height
            + scroll.contentInsets.top
        let image = try await scrollBoard(scroll, to: end, host: host)
        _ = try nativeHostedPNG(
            image, filename: "song-leaderboard-end-\(footer.rawValue)-\(mode.rawValue).png",
            environment: "FST_LEADERBOARDS_RENDER_OUT"
        )
        let nodes = boardAccessibilityNodes(in: host)
        func node(_ id: String) throws -> BoardAccessibilityNode {
            try #require(nodes.first { $0.identifier == id }, "\(id) is reachable")
        }
        func rowID(_ rank: Int) -> String {
            Self.rowPrefix + (footer == .open && rank == 3 ? SoloEndTransport.scoredPlayer : "fixture-other-\(rank)")
        }

        // The row's control: the identified row contains one button (`.contain`).
        func rowButton(_ rank: Int) throws -> BoardAccessibilityNode {
            let index = try #require(nodes.firstIndex { $0.identifier == rowID(rank) }, "row \(rank) is reachable")
            let row = nodes[index]
            let rowFrame = try #require(row.frame)
            #expect(row.role == NSAccessibility.Role.group.rawValue || row.isButton, "row \(rank) is a row: \(row.role)")
            return try #require(nodes[(index + 1)...].first {
                $0.isButton && ($0.frame.map { rowFrame.insetBy(dx: -1, dy: -1).contains($0) } ?? false)
            } ?? (row.isButton ? row : nil), "row \(rank) holds a button")
        }

        // The last row: one named, enabled 44 pt button, wholly above the chrome.
        let last = try rowButton(25)
        let lastFrame = try #require(try node(rowID(25)).frame)
        #expect(last.enabled, "the last row is enabled")
        #expect(last.text.contains("Row 25"), "the last row reads its player: \(last.text)")
        #expect((last.frame?.height ?? 0) >= 44, "the last row keeps a 44 pt target: \(String(describing: last.frame))")
        #expect(lastFrame.maxY <= chromeTop + 0.5, "the last row is not under the chrome: \(lastFrame) vs \(chromeTop)")

        // One row gap to the first chrome element, footer or pager.
        let firstChromeID = footer.footerID ?? "fst.song-leaderboard.page-first"
        let firstChrome = try #require(try node(firstChromeID).frame)
        let gap = firstChrome.minY - lastFrame.maxY
        #expect(abs(gap - Self.rowGap) <= Self.gapTolerance, "the last row rests one row gap above \(firstChromeID): \(gap) pt")

        // As readable as the row above: the fade has shrunk away (standard) or is a hard edge.
        let previous = try #require(try rowButton(24).frame)
        let lastBright = nativeHostedBrightSamples(in: lastFrame, of: image, hostSize: Self.size, threshold: rowTextThreshold)
        let previousBright = nativeHostedBrightSamples(in: previous, of: image, hostSize: Self.size, threshold: rowTextThreshold)
        #expect(previousBright > 0, "the row above the last is drawn")
        #expect(Double(lastBright) >= Double(previousBright) * 0.85, "the last row is unfaded: \(lastBright) vs \(previousBright)")

        // Footer: one named 44 pt button, one row gap above the pager; none without a score.
        let pagerFirst = try #require(try node("fst.song-leaderboard.page-first").frame)
        if let footerID = footer.footerID, let action = footer.footerAction {
            let control = try node(footerID)
            #expect(control.isButton, "the footer is a button: \(control.role)")
            #expect(control.text.hasPrefix("Your rank, 57th.") && control.text.hasSuffix(action), "the footer reads \(control.text)")
            let frame = try #require(control.frame)
            #expect(frame.height >= 44, "the footer keeps a 44 pt target: \(frame)")
            #expect(frame.minY >= chromeTop - 0.5, "the footer is pinned below the rows: \(frame) vs \(chromeTop)")
            let footerGap = pagerFirst.minY - frame.maxY
            #expect(abs(footerGap - Self.rowGap) <= Self.gapTolerance, "the footer rests one row gap above the pager: \(footerGap) pt")
        } else {
            #expect(!nodes.contains { $0.identifier.hasPrefix("fst.song-leaderboard.spotlight") }, "no footer without a ranked score here")
            #expect(!nodes.contains { $0.text.hasPrefix("Your rank") }, "nothing reads a rank without a score here")
        }

        // Pager: named buttons in their page-1 states, 44 pt, below the chrome top.
        for arrow in Self.pagerArrows {
            let control = try node("fst.song-leaderboard.\(arrow.suffix)")
            #expect(control.isButton, "\(arrow.suffix) is a button: \(control.role)")
            #expect(control.enabled == arrow.enabledOnFirstPage, "\(arrow.suffix) enabled on page 1: \(control.enabled)")
            #expect(control.text.localizedCaseInsensitiveContains(arrow.word), "\(arrow.suffix) reads \(control.text)")
            let frame = try #require(control.frame)
            #expect(frame.width >= 44 && frame.height >= 44, "\(arrow.suffix) target \(frame)")
            #expect(frame.minY >= chromeTop - 0.5, "\(arrow.suffix) sits below the chrome top: \(frame) vs \(chromeTop)")
        }
        let info = try node("fst.song-leaderboard.page-info")
        #expect(info.text.localizedCaseInsensitiveContains("Page"), "page-info reads \(info.text)")

        // Nothing reachable in the gap between the last row and the chrome.
        let gapBand = CGRect(x: 0, y: lastFrame.maxY + 1, width: Self.size.width, height: max(0, firstChrome.minY - lastFrame.maxY - 2))
        let strays = nodes.filter { node in
            guard let frame = node.frame, frame.height < Self.size.height / 2 else { return false }
            return frame.intersects(gapBand) && !frame.contains(lastFrame) && !frame.contains(firstChrome)
        }
        #expect(strays.isEmpty, "nothing reachable in the row gap: \(strays.map { "\($0.identifier) \($0.text)" })")

        // Reading order: rows in rank order, then the footer, then the pager.
        let rowIndices = nodes.indices.filter { nodes[$0].identifier.hasPrefix(Self.rowPrefix) }
        let lastRowIndex = try #require(rowIndices.last)
        #expect(nodes[lastRowIndex].identifier == rowID(25), "the last row reads last of the rows")
        let chromeOrder = try ((footer.footerID.map { [$0] } ?? [])
            + ["first", "previous", "info", "next", "last"].map { "fst.song-leaderboard.page-\($0)" })
            .map { id in try #require(nodes.firstIndex { $0.identifier == id }, "\(id) in the reading order") }
        #expect(chromeOrder.allSatisfy { $0 > lastRowIndex }, "rows read before the chrome: \(chromeOrder) vs \(lastRowIndex)")
        #expect(chromeOrder == chromeOrder.sorted(), "the footer, then the pager left to right: \(chromeOrder)")
    }

    /// The song header, with no gradient behind it since #293, is one heading reading the
    /// title, artist and board, its text drawn bright on the page background.
    @Test(arguments: [BottomChromeFadeMode.standard, .moreContrast])
    func headerIsOneHeadingDrawnOnThePageBackground(mode: BottomChromeFadeMode) async throws {
        let (host, _, cleanup) = try await hostBoard(.anonymous, mode: mode)
        defer { cleanup() }
        let image = try await nativeHostedSettle(host)
        let tree = macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
        let header = try #require(tree.first { $0.identifier == "fst.song-leaderboard.header" })
        let spoken = [header.label, header.title, header.value].joined(separator: " ")
        #expect(header.role == "AXHeading", "the header is a heading: \(header.role)")
        for part in ["Fixture Pulse", "Fixture Artist", "Lead"] {
            #expect(spoken.contains(part), "the header reads \(part): \(spoken)")
        }
        // It reads before the rows.
        let headerIndex = try #require(tree.firstIndex { $0.identifier == "fst.song-leaderboard.header" })
        let firstRow = try #require(tree.firstIndex { $0.identifier.hasPrefix(Self.rowPrefix) })
        #expect(headerIndex < firstRow, "the header reads before the rows")

        // No decorative band is reachable over it, and its text is drawn bright.
        let frame = try #require(nativeHostedAccessibilityFrame("fst.song-leaderboard.header", in: host))
        let nodes = boardAccessibilityNodes(in: host)
        let strays = nodes.filter { node in
            guard let other = node.frame, node.identifier != "fst.song-leaderboard.header",
                  other.height < Self.size.height / 2 else { return false }
            return frame.insetBy(dx: -1, dy: -1).contains(other) && node.text.isEmpty == false
                && !spoken.contains(node.text)
        }
        #expect(strays.isEmpty, "only the header is reachable over it: \(strays.map { "\($0.identifier) \($0.text)" })")
        let bright = nativeHostedBrightSamples(in: frame, of: image, hostSize: Self.size, threshold: 180)
        #expect(bright > 0, "the header text is drawn bright on the page background")
    }
}
#endif
