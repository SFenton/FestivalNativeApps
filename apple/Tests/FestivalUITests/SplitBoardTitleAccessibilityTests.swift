#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Split board title accessibility (issue #342, backfilled by #478)

/// A song board opened in a split's trailing pane beside Song Detail drops the repeated
/// song header and is titled by its chart instead (``InstrumentPageTitle``: the
/// instrument's artwork and name with the entry total under it, or the band size alone;
/// issue #342, owner-approved `song-leaderboard-header` variant). The same SwiftUI runs
/// in the iPad and iPhone Duo `OnDemandSplit` and the Mac `MacListDetailStack`, so these
/// hosted checks pin what that region exposes on every Apple split:
///
/// - the title is one heading naming the chart, then its entry total, once each; the
///   artwork is hidden and the pane never names the song or artist a second time;
/// - it is the pane's first heading and reads before the rows and the pager, above them
///   on screen;
/// - at the largest accessibility size in a narrow pane the longest chart name wraps
///   inside the pane instead of clipping, keeps its whole name, and the rows stay reachable;
/// - the bar copy shown once the heading scrolls away is one heading with no artwork;
/// - in the Mac split, Song Detail reads first and the pane's title is a heading inside
///   the trailing pane, which names the song nowhere.
///
/// Score History beside Song Detail (`fst.history.board-title`) is covered by
/// `playerHistoryScreenRootKeepsItsReadingOrder` (hosted) and on device at AX5 by
/// `ScoreHistoryAccessibilityJourneyTests/testScoreHistorySplitPaneAtAX5`; the Song
/// Leaderboard pane's on-device text growth, heading trait and focus move are
/// `SongBoardSplitAccessibilityJourneyTests`, and `IPadAccessibilityAuditTests` audits the
/// `song-board-split` page.
///
/// HIG VoiceOver: "Use titles and headings to convey hierarchy. Give each page or screen a
/// unique, succinct title describing its content and purpose"; "Exclude purely decorative
/// images". HIG Typography: "Keep text truncation to a minimum as font size increases."
@MainActor
@Suite(.serialized)
struct SplitBoardTitleAccessibilityTests {
    // MARK: - Fixture

    static let titleID = "fst.song-leaderboard.board-title"
    static let songHeaderID = "fst.song-leaderboard.header"
    static let rowPrefix = "fst.song-leaderboard.row."
    static let pagerIDs = ["first", "previous", "info", "next", "last"].map { "fst.song-leaderboard.page-\($0)" }
    static let total = "\(500.formatted()) entries"
    /// A trailing pane about as wide as half an 11-inch iPad in landscape.
    static let paneSize = CGSize(width: 402, height: 900)

    /// The song the board belongs to (`fixture-pulse`, "Fixture Pulse" by "Fixture Artist").
    static func song() throws -> Song {
        try spotlightFixtureSong()
    }

    /// A 25-row first page of `instrument`'s board out of 500 entries, with the service's
    /// entry-total disclosure on, so the title carries its total.
    ///
    /// - Parameter instrument: The chart.
    /// - Returns: A validated, pinned page.
    /// - Throws: A page that fails validation.
    static func payload(_ instrument: Instrument) throws -> LeaderboardPayload {
        let rows = (1...25).map { rank in
            #"{"accountId":"fixture-other-\#(rank)","displayName":"Row \#(rank)","score":\#(99_000 - rank),"rank":\#(rank)}"#
        }
        let data = Data("""
        {"songId":"fixture-pulse","instrument":"\(instrument.rawValue)","count":25,
         "localEntries":500,"totalEntries":500,"showLeaderboardEntryTotals":true,
         "entries":[\(rows.joined(separator: ","))]}
        """.utf8)
        let response = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
        try response.validate(songId: "fixture-pulse", instrument: instrument)
        return LeaderboardPayload(
            page: 1, leaderboard: response, publicationId: 13, observedPublicationId: 13, isStale: false
        )
    }

    /// Host `instrument`'s solo board as the trailing pane's root beside Song Detail and
    /// wait until its title and first row are reachable.
    ///
    /// - Parameters:
    ///   - instrument: The chart.
    ///   - typeSize: Dynamic Type size of the whole pane.
    ///   - size: The pane's size.
    /// - Returns: The settled host and its window.
    /// - Throws: A board that never shows its title and rows.
    static func hostSoloBoard(
        _ instrument: Instrument, typeSize: DynamicTypeSize = .large, size: CGSize = paneSize
    ) async throws -> (host: NSHostingView<NativeHostedRoot<AnyView>>, window: NSWindow) {
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let song = try song()
        let payload = try payload(instrument)
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    SoloLeaderboardScreen(
                        song: song, instrument: instrument, session: session,
                        initialPage: 1, path: .constant([]), initialState: .loaded(payload)
                    )
                    .splitPaneContext(SplitPaneContext(role: .trailing, besideList: .songDetail))
                }
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.marqueeAnimationEnabled, false)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityFrame(titleID, in: host) != nil
                && nativeHostedAccessibilityFrame("\(rowPrefix)fixture-other-1", in: host) != nil
        }
        return (host, window)
    }

    /// The title node assistive technologies reach.
    static func title(_ id: String = titleID, in nodes: [MacAXNode]) throws -> MacAXNode {
        try #require(
            nodes.first { $0.identifier == id && $0.isElement },
            "\(id) in\n\(nodes.map(\.description).joined(separator: "\n"))"
        )
    }

    /// Whether each part occurs exactly once in `label`, in the given order.
    static func readsOnceInOrder(_ parts: [String], in label: String) -> Bool {
        SongBandLeaderboardHeaderAccessibilityTests.readsOnceInOrder(parts, in: label)
    }

    // MARK: - Name, role and state

    /// The pane's title is one heading that reads the chart's name, then its entry total,
    /// each once, for a short, a two-word and the longest chart name. The artwork is
    /// hidden (no image is exposed), no element names the song or artist, the song header
    /// is gone, and nothing on the page is unnamed.
    @Test(arguments: [Instrument.lead, .karaoke, .proCymbals])
    func titleIsOneHeadingNamingTheChartThenItsTotal(instrument: Instrument) async throws {
        let (host, window) = try await Self.hostSoloBoard(instrument)
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "split-board-title-\(instrument.rawValue)")
        let title = try Self.title(in: nodes)
        #expect(title.role == "AXHeading", "the pane's title is a heading: \(title)")
        #expect(Self.readsOnceInOrder([instrument.label, Self.total], in: title.spokenName),
                "the chart, then its total, once each: \(title.spokenName)")
        #expect(!nodes.contains { $0.identifier == Self.songHeaderID }, "no repeated song header")
        let song = try Self.song()
        #expect(!nodes.contains { $0.spokenName.contains(song.title) || $0.spokenName.contains(song.artist) },
                "the pane names the song nowhere")
        #expect(!nodes.contains { $0.isElement && $0.role == "AXImage" }, "the artwork is decorative")
        #expect(nodes.filter { $0.isElement && $0.role == "AXHeading" && $0.spokenName.contains(instrument.label) }
            .count == 1, "one heading names the chart")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Reading order

    /// The title is the pane's first heading and reads before every row and the pager,
    /// matching the layout top to bottom, and sits above the first row on screen.
    @Test func titleReadsFirstBeforeRowsAndPager() async throws {
        let (host, window) = try await Self.hostSoloBoard(.lead)
        defer { window.orderOut(nil) }
        let tree = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(tree, name: "split-board-title-order")
        let order = tree.filter(\.isElement)
        let title = try #require(order.firstIndex { $0.identifier == Self.titleID }, "title in the reading order")
        let firstHeading = try #require(order.firstIndex { $0.role == "AXHeading" })
        #expect(firstHeading == title, "the board's title is the first heading: \(order[firstHeading])")
        let rows = order.indices.filter { order[$0].identifier.hasPrefix(Self.rowPrefix) }
        #expect(!rows.isEmpty, "rows in the reading order")
        #expect(rows.allSatisfy { $0 > title }, "the title reads before the rows: \(title) vs \(rows)")
        let pager = Self.pagerIDs.compactMap { id in order.firstIndex { $0.identifier == id } }
        #expect(pager.count == Self.pagerIDs.count, "every pager control in the reading order: \(pager)")
        #expect(pager.allSatisfy { $0 > title }, "the title reads before the pager: \(title) vs \(pager)")

        let titleFrame = try #require(nativeHostedAccessibilityFrame(Self.titleID, in: host))
        let rowFrame = try #require(nativeHostedAccessibilityFrame("\(Self.rowPrefix)fixture-other-1", in: host))
        #expect(titleFrame.maxY <= rowFrame.minY + 0.5, "the title sits above the rows: \(titleFrame) over \(rowFrame)")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size in a narrow pane, the longest chart name ("Pro
    /// Drums + Cymbals") wraps onto more lines inside the pane instead of clipping: the
    /// title keeps its whole name, stays a heading inside the pane's width and leaves the
    /// first row reachable below it.
    ///
    /// The Mac host keeps its font size (13 pt body), so a 160 pt pane reproduces the
    /// iOS AX5 ratio, as `playerHistoryScreenRootKeepsItsReadingOrder` does; the glyphs'
    /// growth on device is `SongBoardSplitAccessibilityJourneyTests`.
    @Test func longestChartNameWrapsInsideANarrowPaneAtAccessibilitySizes() async throws {
        let standard = try await Self.hostSoloBoard(.proCymbals)
        defer { standard.window.orderOut(nil) }
        let standardName = try Self.title(in: macAccessibilityTree(standard.host)).spokenName
        let standardFrame = try #require(nativeHostedAccessibilityFrame(Self.titleID, in: standard.host))

        let narrow = CGSize(width: 160, height: 900)
        let (host, window) = try await Self.hostSoloBoard(.proCymbals, typeSize: .accessibility5, size: narrow)
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "split-board-title-ax5")
        _ = try nativeHostedPNG(
            try nativeHostedImage(host), filename: "split-board-title-ax5.png", environment: "FST_LEADERBOARDS_RENDER_OUT"
        )
        let title = try Self.title(in: nodes)
        #expect(title.role == "AXHeading")
        #expect(title.spokenName == standardName, "the same whole name at AX5: \(title.spokenName)")
        let frame = try #require(nativeHostedAccessibilityFrame(Self.titleID, in: host))
        #expect(frame.height > standardFrame.height * 1.3,
                "the name wraps in the narrow pane: \(standardFrame.height) → \(frame.height)")
        #expect(frame.minX >= -0.5 && frame.maxX <= narrow.width + 0.5, "the title stays inside the pane: \(frame)")
        #expect(frame.minY >= -0.5 && frame.maxY < narrow.height, "the title stays on screen: \(frame)")
        #expect(nodes.contains { $0.isElement && $0.identifier.hasPrefix(Self.rowPrefix) },
                "rows stay reachable below the title at AX5")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Pinned bar title

    /// The bar copy shown once the title scrolls under the bar (``InstrumentPageTitle``
    /// `.pinned`, iOS and iPadOS) is one heading naming the chart, with its artwork hidden,
    /// at the standard and the largest accessibility size.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func pinnedTitleIsOneHeadingNamingTheChart(typeSize: DynamicTypeSize) throws {
        let size = CGSize(width: 320, height: 120)
        let host = nativeHostedView(
            InstrumentPageTitle(
                instrument: .lead, title: Instrument.lead.label, style: .pinned,
                identifier: "fst.song-leaderboard.pinned-title"
            )
            .environment(\.marqueeAnimationEnabled, false)
            .environment(\.dynamicTypeSize, typeSize),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let nodes = macAccessibilityTree(host)
        let title = try Self.title("fst.song-leaderboard.pinned-title", in: nodes)
        #expect(title.role == "AXHeading", "the bar title is a heading: \(title)")
        #expect(title.spokenName == Instrument.lead.label, "named by the chart alone: \(title.spokenName)")
        #expect(nodes.filter { $0.isElement && $0.role != "AXGroup" }.count == 1,
                "one element, no separate icon or text: \(nodes.map(\.description))")
    }

    // MARK: - Band board

    /// Hosts the `fixture-pulse` Duos board as the trailing pane's root beside Song Detail.
    struct BandBoardHarness: View {
        let session: FestivalSession
        let song: Song
        @State var bandType: BandType = .duets

        var body: some View {
            SongBandLeaderboardContent(session: session, song: song, bandType: $bandType)
                .splitPaneContext(SplitPaneContext(role: .trailing, besideList: .songDetail))
        }
    }

    /// A band board beside Song Detail is titled by its band size alone: one heading that
    /// names "Duos" once, read before its rows, with no artwork and no song or artist.
    @Test func bandBoardTitleIsOneHeadingNamingTheBandSize() async throws {
        let client = try FestivalAPI(
            baseURL: try await RivalsMockService.shared.baseURL(), transport: URLSessionHTTPTransport()
        )
        let session = FestivalSession(factory: { client })
        let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
        let id = "fst.song-band-leaderboard.board-title"
        let host = nativeHostedView(
            NavigationStack { BandBoardHarness(session: session, song: song) }
                .frame(width: Self.paneSize.width, height: Self.paneSize.height)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.marqueeAnimationEnabled, false),
            size: Self.paneSize
        )
        let window = nativeHostedWindow(host, size: Self.paneSize)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityFrame(id, in: host) != nil
                && (nativeHostedAccessibilityFrame("fst.song-band-leaderboard.page-info", in: host) != nil
                    || nativeHostedAccessibilityFrame("fst.song-band-leaderboard.empty", in: host) != nil)
        }
        let order = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(order, name: "split-band-board-title")
        let elements = order.filter(\.isElement)
        let titleIndex = try #require(elements.firstIndex { $0.identifier == id }, "title in the reading order")
        let title = elements[titleIndex]
        #expect(title.role == "AXHeading", "the pane's title is a heading: \(title)")
        #expect(title.spokenName.hasPrefix(BandType.duets.label), "led by the band size: \(title.spokenName)")
        #expect(Self.readsOnceInOrder([BandType.duets.label], in: title.spokenName), "\(title.spokenName)")
        #expect(elements.firstIndex { $0.role == "AXHeading" } == titleIndex, "the pane's first heading")
        let rows = elements.indices.filter { elements[$0].identifier.hasPrefix("fst.song-band-leaderboard.row.") }
        #expect(rows.allSatisfy { $0 > titleIndex }, "the title reads before the rows: \(titleIndex) vs \(rows)")
        #expect(!order.contains { $0.identifier == "fst.song-band-leaderboard.header" }, "no repeated song header")
        #expect(!order.contains { $0.spokenName.contains(song.title) || $0.spokenName.contains(song.artist) },
                "the pane names the song nowhere")
        #expect(!elements.contains { $0.role == "AXImage" }, "nothing decorative is exposed")
        #expect(macAccessibilityFindings(order) == [])
    }

    // MARK: - Mac split

    /// Holds the Mac list/detail stack's path.
    struct MacSplitHarness: View {
        let session: FestivalSession
        @State var path: [AppRoute]

        var body: some View {
            MacListDetailStack(
                section: .songs, session: session, visibleInstruments: Set(Instrument.allCases),
                path: $path, isVisible: true, onSplitChange: { _ in }
            ) { _ in Text("Songs Root") }
        }
    }

    /// Song Detail → View full leaderboard in the Mac split: Song Detail (which names the
    /// song) reads before the trailing pane, the pane's title is a heading inside that pane
    /// naming the chart, it is the pane's first heading, and nothing in the pane names the
    /// song or artist again.
    @Test func macSplitReadsSongDetailThenThePaneTitledByItsChart() async throws {
        let size = CGSize(width: 1280, height: 820)
        let client = try FestivalAPI(
            baseURL: try await RivalsMockService.shared.baseURL(), transport: URLSessionHTTPTransport()
        )
        let session = FestivalSession(factory: { client })
        let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
        let defaults = UserDefaults(suiteName: "fst.tests.split-board-title.host")!
        defaults.set(true, forKey: "fst.accessibility.reduceMotion")
        let host = nativeHostedView(
            MacSplitHarness(session: session, path: [.songDetail(song), .songLeaderboard(song, .lead, 1)])
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .defaultAppStorage(defaults),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityElement("fst.split.trailing", in: host) != nil
                && nativeHostedAccessibilityFrame(Self.titleID, in: host) != nil
        }
        let tree = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(tree, name: "mac-split-board-title")
        let pane = try #require(tree.firstIndex { $0.identifier == "fst.split.trailing" }, "the trailing pane")
        let paneEnd = tree[(pane + 1)...].firstIndex { $0.depth <= tree[pane].depth } ?? tree.endIndex
        let inPane = tree[(pane + 1)..<paneEnd].filter(\.isElement)
        let title = try #require(inPane.first { $0.identifier == Self.titleID }, "the title is inside the pane")
        #expect(title.role == "AXHeading", "the pane's title is a heading: \(title)")
        #expect(title.spokenName.hasPrefix(Instrument.lead.label), "named by the chart: \(title.spokenName)")
        #expect(inPane.first { $0.role == "AXHeading" }?.identifier == Self.titleID, "the pane's first heading")
        #expect(!inPane.contains { $0.identifier == Self.songHeaderID }, "no repeated song header")
        #expect(!inPane.contains { $0.spokenName.contains(song.title) || $0.spokenName.contains(song.artist) },
                "the pane names the song nowhere: \(inPane.map(\.description))")
        let songNamed = tree[..<pane].contains { $0.isElement && $0.spokenName.contains(song.title) }
        #expect(songNamed, "Song Detail, beside it, names the song before the pane")
    }
}
#endif
