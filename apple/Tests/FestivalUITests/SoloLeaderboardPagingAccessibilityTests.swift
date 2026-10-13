#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Song Leaderboard paging accessibility (issue #464, for #316)

/// Keyless fixture transport for the Song Leaderboard's page changes: the publication
/// and `fixture-pulse` Lead's 25-row pages (500 entries), each answered at once unless
/// the test holds it or makes it fail. Rejects the privileged key, selected-profile
/// headers, writes and any other route.
actor SoloPagingTransport: HTTPTransport {
    static let generation = 13
    static let boardPath = "/api/leaderboard/fixture-pulse/Solo_Guitar"

    private var held: Set<Int> = []
    private var failing: Set<Int> = []
    /// Pages requested so far, in order.
    private(set) var requested: [Int] = []

    /// Keep `page`'s response back until ``release(_:)``.
    func hold(_ page: Int) { held.insert(page) }
    /// Answer `page` (and any held request for it).
    func release(_ page: Int) { held.remove(page) }
    /// Answer `page` with a 500 from now on.
    func fail(_ page: Int) { failing.insert(page) }

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
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let top = query.first { $0.name == "top" }?.value.flatMap(Int.init)
        let offset = query.first { $0.name == "offset" }?.value.flatMap(Int.init) ?? 0
        guard url.path == Self.boardPath,
              request.value(forHTTPHeaderField: "X-FST-Publication-Id") == String(Self.generation),
              let top, top == 25, offset >= 0, offset % top == 0 else {
            throw FestivalAPIError.invalidResource
        }
        let page = offset / top + 1
        requested.append(page)
        while held.contains(page) {
            try await Task.sleep(for: .milliseconds(20))
        }
        let pinned = ["X-FST-Publication-Id": String(Self.generation)]
        if failing.contains(page) {
            return HTTPResult(status: 500, data: Data(#"{"status":"fixture_page_failed"}"#.utf8), headers: pinned)
        }
        let rows = (offset + 1...offset + top).map { rank in
            #"{"accountId":"fixture-other-\#(rank)","displayName":"Row \#(rank)","score":\#(99_000 - rank),"rank":\#(rank)}"#
        }
        return HTTPResult(status: 200, data: Data("""
        {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":\(top),
         "localEntries":500,"totalEntries":500,"entries":[\(rows.joined(separator: ","))]}
        """.utf8), headers: pinned)
    }
}

/// Accessibility of the Song Leaderboard's page change as #316 left it (issue #464).
///
/// #316 kept the song header and its List from the first load on and swaps only the rows
/// on a page change (``FestivalReloadGate``'s retained frame, load-transition R4), with a
/// failed page's error and Retry in the rows' place under the header (song-leaderboard-
/// header R5). `ReloadGateAccessibilityTests` pins that gate form on a fixture page; these
/// hosted checks pin it on the real screen, paged the way VoiceOver, Voice Control and the
/// Mac keyboard page it (the pager arrow's accessibility press):
///
/// - while the next page loads, the header stays one heading reading the title, artist
///   and board, and reads before one busy indicator named "Loading leaderboard"; no row
///   of the old page and nothing unnamed is reachable;
/// - the pager stays: named 44 pt buttons, enabled for the page being loaded, read after
///   the header and the spinner;
/// - once the page arrives, the header (still one heading) reads before its rows in rank
///   order, then the pager;
/// - a failed page reads the header, then the error and a named, pressable Retry, then
///   the pager, with no stale rows;
/// - all of it with fades off, system and in-app Reduce Motion, and the animated fades.
///
/// The SwiftUI is the same on iPhone, iPad, iPhone Duo and Mac. macOS keeps its font size,
/// so the iOS journey `SongLeaderboardPagingJourneyTests` pages the board at the largest
/// accessibility text size with the system audit.
///
/// HIG VoiceOver: "be sure to keep labels current as interface and content change"; "Use
/// titles and headings to convey hierarchy". HIG Accessibility: iOS, iPadOS default
/// control size 44×44 pt; "When Reduce Motion is on, reduce automatic and repetitive
/// animation".
@MainActor
@Suite(.serialized)
struct SoloLeaderboardPagingAccessibilityTests {
    typealias Motion = ReloadGateAccessibilityTests.Motion

    static let size = CGSize(width: 402, height: 700)
    static let rowPrefix = "fst.song-leaderboard.row."
    static let headerID = "fst.song-leaderboard.header"
    static let spinnerID = "fst.song-leaderboard.loading"
    static let spinnerLabel = "Loading leaderboard"
    static let retryID = "fst.service-status.retry"
    /// The pager's controls in reading order, with the word each arrow's name carries.
    static let pager = [
        (id: "fst.song-leaderboard.page-first", word: "First"),
        (id: "fst.song-leaderboard.page-previous", word: "Previous"),
        (id: "fst.song-leaderboard.page-info", word: "Page"),
        (id: "fst.song-leaderboard.page-next", word: "Next"),
        (id: "fst.song-leaderboard.page-last", word: "Last"),
    ]
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    static let minimumTarget: CGFloat = 44

    /// One hosted board.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let transport: SoloPagingTransport
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// The current tree in VoiceOver's reading order (rows by List row index), after
        /// one layout pass: no waiting, so no timed reload step runs.
        func readingOrder() throws -> [MacAXNode] {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let table = try #require(SoloLeaderboardPagingAccessibilityTests.table(in: host), "the board's List")
            return macListReadingOrder(host, table: table).all
        }
    }

    /// Host `fixture-pulse` Lead's page 1, loaded, anonymous, at phone width.
    ///
    /// - Parameter motion: Fade and Reduce Motion settings.
    /// - Returns: The settled board with its header, rows and pager in the tree.
    private func hostBoard(motion: Motion) async throws -> Hosted {
        let suiteName = "fst-solo-paging-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let transport = SoloPagingTransport()
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let song = try spotlightFixtureSong()
        let payload = try spotlightFixtureLeaderboard(spotlightRank: nil)
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    SoloLeaderboardScreen(
                        song: song, instrument: .lead, session: session,
                        initialPage: 1, path: .constant([]), initialState: .loaded(payload)
                    )
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .environment(\.festivalFadeInEnabled, motion != .instant)
                .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
                .environment(\.horizontalSizeClass, .compact)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
            ),
            size: Self.size, forceGlassFallback: false
        )
        let hosted = Hosted(
            host: host, window: nativeHostedWindow(host, size: Self.size), transport: transport,
            storage: storage, suiteName: suiteName
        )
        try await Self.settle(hosted) { nodes in
            nodes.contains { $0.identifier == Self.headerID }
                && nodes.contains { $0.identifier == "\(Self.rowPrefix)fixture-other-1" }
                && nodes.contains { $0.identifier == Self.pager[0].id }
        }
        return hosted
    }

    // MARK: Tree helpers

    /// The board's List table, the deepest under `view`.
    static func table(in view: NSView) -> NSTableView? {
        for subview in view.subviews {
            if let found = table(in: subview) { return found }
        }
        return view as? NSTableView
    }

    /// Wait until the reading order satisfies `done`.
    static func settle(
        _ hosted: Hosted, sourceLocation: SourceLocation = #_sourceLocation,
        until done: @MainActor ([MacAXNode]) -> Bool
    ) async throws {
        try await nativeHostedSettle(hosted.host, timeout: .seconds(60), sourceLocation: sourceLocation) {
            guard let table = table(in: hosted.host) else { return false }
            return done(macListReadingOrder(hosted.host, table: table).all)
        }
    }

    static func rows(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.identifier.hasPrefix(rowPrefix) }
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    /// Press a control the way VoiceOver, Voice Control and the Mac keyboard do.
    static func press(_ identifier: String, in hosted: Hosted, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let element = try #require(
            nativeHostedAccessibilityElement(identifier, in: hosted.host), "\(identifier) is reachable",
            sourceLocation: sourceLocation
        )
        let press = NSSelectorFromString("accessibilityPerformPress")
        try #require(element.responds(to: press), "\(identifier) is pressable", sourceLocation: sourceLocation)
        _ = element.perform(press)
    }

    /// Wait until the transport has received `count` page requests.
    static func waitForRequests(
        _ count: Int, _ hosted: Hosted, sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(30)
        while await hosted.transport.requested.count < count, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        let requested = await hosted.transport.requested
        #expect(requested.count >= count, "\(count) page requests: \(requested)", sourceLocation: sourceLocation)
    }

    // MARK: Expectations

    /// The header is exactly one heading reading the song's title, artist and board.
    static func expectHeader(
        _ nodes: [MacAXNode], _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> Int {
        let headers = nodes.indices.filter { nodes[$0].identifier == headerID }
        let index = try #require(
            headers.count == 1 ? headers.first : nil,
            "\(context): one song header:\n\(dump(nodes))", sourceLocation: sourceLocation
        )
        let header = nodes[index]
        #expect(header.role == "AXHeading", "\(context): the header is a heading: \(header)", sourceLocation: sourceLocation)
        let spoken = [header.label, header.title, header.value].joined(separator: " ")
        for part in ["Fixture Pulse", "Fixture Artist", "Lead"] {
            #expect(spoken.contains(part), "\(context): the header reads \(part): \(spoken)", sourceLocation: sourceLocation)
        }
        return index
    }

    /// The pager's controls, after `index` in reading order and left to right: each
    /// named, a 44×44 pt target wholly on the page; the arrows buttons, enabled for `page`
    /// of `pageCount`.
    static func expectPager(
        _ nodes: [MacAXNode], after index: Int, page: Int, pageCount: Int, in hosted: Hosted,
        _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let bounds = hosted.host.bounds.insetBy(dx: -0.5, dy: -0.5)
        var previous = index
        for control in pager {
            guard let position = nodes.firstIndex(where: { $0.identifier == control.id }) else {
                Issue.record("\(context): \(control.id) is reachable:\n\(dump(nodes))", sourceLocation: sourceLocation)
                continue
            }
            let node = nodes[position]
            #expect(position > previous, "\(context): \(control.id) reads after what precedes it", sourceLocation: sourceLocation)
            previous = position
            #expect(node.spokenName.localizedCaseInsensitiveContains(control.word),
                    "\(context): \(control.id) reads \(node.spokenName)", sourceLocation: sourceLocation)
            guard let frame = nativeHostedAccessibilityFrame(control.id, in: hosted.host) else {
                Issue.record("\(context): \(control.id) has a frame", sourceLocation: sourceLocation)
                continue
            }
            #expect(frame.width >= minimumTarget - 0.5 && frame.height >= minimumTarget - 0.5,
                    "\(context): \(control.id) is a 44×44 pt target: \(frame)", sourceLocation: sourceLocation)
            #expect(bounds.contains(frame), "\(context): \(control.id) lies on the page: \(frame)", sourceLocation: sourceLocation)
            guard control.id != "fst.song-leaderboard.page-info" else {
                // An adjustable element on macOS (AXUnknown) reports its value as the
                // value description, which VoiceOver reads (MaterialCardControlsAccessibilityTests).
                let element = nativeHostedAccessibilityElement(control.id, in: hosted.host)
                let value = node.value.isEmpty
                    ? element?.value(forKey: "accessibilityValueDescription") as? String ?? ""
                    : node.value
                #expect(value == "\(page) of \(pageCount)", "\(context): the badge reads page \(page): '\(value)'",
                        sourceLocation: sourceLocation)
                continue
            }
            #expect(node.role == "AXButton", "\(context): \(control.id) is a button: \(node)", sourceLocation: sourceLocation)
            let backward = control.id.hasSuffix("first") || control.id.hasSuffix("previous")
            #expect(node.isEnabled == (backward ? page > 1 : page < pageCount),
                    "\(context): \(control.id) enabled on page \(page): \(node)", sourceLocation: sourceLocation)
        }
    }

    /// Every element the board contributes, apart from containers, has a name. AppKit's
    /// own List outline and its scroller parts are system-named and are skipped.
    static func expectNothingUnnamed(
        _ nodes: [MacAXNode], _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) {
        var scrollerDepth: Int?
        let own = nodes.filter { node in
            if let depth = scrollerDepth, node.depth > depth { return false }
            scrollerDepth = node.role == "AXScrollBar" ? node.depth : nil
            return node.role != "AXScrollBar" && node.role != "AXOutline"
        }
        let unnamed = ReloadGateAccessibilityTests.leaves(own).filter { $0.spokenName.isEmpty }
        #expect(unnamed.isEmpty, "\(context): nothing unnamed:\n\(dump(unnamed))", sourceLocation: sourceLocation)
    }

    /// The page being loaded: header (one heading), then one named spinner, then the
    /// pager for `page`; no rows.
    static func expectLoading(
        _ hosted: Hosted, page: Int, _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let nodes = try hosted.readingOrder()
        let header = try expectHeader(nodes, context, sourceLocation: sourceLocation)
        #expect(rows(nodes).isEmpty, "\(context): no row of another page:\n\(dump(nodes))", sourceLocation: sourceLocation)
        let spinners = nodes.indices.filter { nodes[$0].identifier == spinnerID }
        let spinner = try #require(spinners.count == 1 ? spinners.first : nil,
                                   "\(context): one spinner:\n\(dump(nodes))", sourceLocation: sourceLocation)
        #expect(nodes[spinner].spokenName == spinnerLabel, "\(context): \(nodes[spinner])", sourceLocation: sourceLocation)
        #expect(header < spinner, "\(context): the header reads before the spinner:\n\(dump(nodes))", sourceLocation: sourceLocation)
        let busy = ReloadGateAccessibilityTests.busyIndicators(ReloadGateAccessibilityTests.reachable(hosted.host))
        #expect(busy.count == 1 && busy.first?.spokenName == spinnerLabel,
                "\(context): one named busy indicator: \(busy)", sourceLocation: sourceLocation)
        expectNothingUnnamed(ReloadGateAccessibilityTests.reachable(hosted.host), context, sourceLocation: sourceLocation)
        expectPager(nodes, after: spinner, page: page, pageCount: 20, in: hosted, context, sourceLocation: sourceLocation)
    }

    /// `page` shown: header (one heading), its rows in rank order, then the pager.
    static func expectShown(
        _ hosted: Hosted, page: Int, _ context: String, sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let nodes = try hosted.readingOrder()
        let header = try expectHeader(nodes, context, sourceLocation: sourceLocation)
        #expect(!nodes.contains { $0.identifier == spinnerID }, "\(context): the spinner left:\n\(dump(nodes))",
                sourceLocation: sourceLocation)
        let shown = rows(nodes)
        let ranks = shown.compactMap { Int($0.identifier.dropFirst("\(rowPrefix)fixture-other-".count)) }
        let first = (page - 1) * 25 + 1
        #expect(ranks.first == first && ranks == Array(first..<first + ranks.count) && ranks.count >= 3,
                "\(context): page \(page)'s rows in rank order: \(ranks)", sourceLocation: sourceLocation)
        let firstRow = try #require(nodes.firstIndex { $0.identifier.hasPrefix(rowPrefix) }, sourceLocation: sourceLocation)
        let lastRow = try #require(nodes.lastIndex { $0.identifier.hasPrefix(rowPrefix) }, sourceLocation: sourceLocation)
        #expect(header < firstRow, "\(context): the header reads before the rows", sourceLocation: sourceLocation)
        expectNothingUnnamed(ReloadGateAccessibilityTests.reachable(hosted.host), context, sourceLocation: sourceLocation)
        expectPager(nodes, after: lastRow, page: page, pageCount: 20, in: hosted, context, sourceLocation: sourceLocation)
    }

    // MARK: Tests

    /// Next, then Previous: each page change keeps the header as one heading read before
    /// one named spinner, with no old rows and the pager usable, then reads the new
    /// page's rows after the header; in every motion setting.
    @Test(arguments: Motion.allCases)
    func pageChangeKeepsTheHeadingAndSwapsOnlyTheRows(_ motion: Motion) async throws {
        let hosted = try await hostBoard(motion: motion)
        defer { hosted.close() }
        try Self.expectShown(hosted, page: 1, "\(motion) page 1")

        await hosted.transport.hold(2)
        try Self.press(Self.pager[3].id, in: hosted)
        // Read in the same update, then again once page 2's request is waiting.
        try Self.expectLoading(hosted, page: 2, "\(motion) Next pressed")
        try await Self.waitForRequests(1, hosted)
        try await Self.settle(hosted) { _ in true }
        try Self.expectLoading(hosted, page: 2, "\(motion) page 2 loading")

        await hosted.transport.release(2)
        try await Self.settle(hosted) { nodes in
            nodes.contains { $0.identifier == "\(Self.rowPrefix)fixture-other-26" }
                && !nodes.contains { $0.identifier == Self.spinnerID }
        }
        try Self.expectShown(hosted, page: 2, "\(motion) page 2")

        await hosted.transport.hold(1)
        try Self.press(Self.pager[1].id, in: hosted)
        try Self.expectLoading(hosted, page: 1, "\(motion) Previous pressed")
        try await Self.waitForRequests(2, hosted)
        await hosted.transport.release(1)
        try await Self.settle(hosted) { nodes in
            nodes.contains { $0.identifier == "\(Self.rowPrefix)fixture-other-1" }
                && !nodes.contains { $0.identifier == Self.spinnerID }
        }
        try Self.expectShown(hosted, page: 1, "\(motion) back on page 1")
    }

    /// A failed page keeps the header and reads its error and a named Retry in the rows'
    /// place, before the pager, with no stale rows; Retry reloads under the same header.
    @Test(arguments: [Motion.instant, .systemReduceMotion])
    func failedPageReadsTheHeadingThenTheErrorAndRetry(_ motion: Motion) async throws {
        let hosted = try await hostBoard(motion: motion)
        defer { hosted.close() }
        await hosted.transport.fail(2)
        try Self.press(Self.pager[3].id, in: hosted)
        try Self.expectLoading(hosted, page: 2, "\(motion) Next pressed")
        try await Self.settle(hosted) { nodes in
            nodes.contains { $0.identifier == Self.retryID }
        }

        let nodes = try hosted.readingOrder()
        let header = try Self.expectHeader(nodes, "\(motion) failed")
        #expect(Self.rows(nodes).isEmpty, "no stale rows under the error:\n\(Self.dump(nodes))")
        #expect(!nodes.contains { $0.identifier == Self.spinnerID }, "the spinner left:\n\(Self.dump(nodes))")
        let title = try #require(nodes.firstIndex { $0.identifier == "fst.service-status.title" }, "\(Self.dump(nodes))")
        let retry = try #require(nodes.firstIndex { $0.identifier == Self.retryID }, "\(Self.dump(nodes))")
        #expect(nodes[title].spokenName.contains("Leaderboard unavailable"), "\(nodes[title])")
        #expect(nodes[retry].role == "AXButton" && nodes[retry].spokenName.localizedCaseInsensitiveContains("Retry"),
                "Retry is a named button: \(nodes[retry])")
        #expect(header < title && title < retry, "header, then the error, then Retry:\n\(Self.dump(nodes))")
        let retryFrame = try #require(nativeHostedAccessibilityFrame(Self.retryID, in: hosted.host))
        #expect(retryFrame.height >= Self.minimumTarget - 0.5, "Retry is a 44 pt target: \(retryFrame)")
        Self.expectNothingUnnamed(ReloadGateAccessibilityTests.reachable(hosted.host), "\(motion) failed")
        Self.expectPager(nodes, after: retry, page: 2, pageCount: 20, in: hosted, "\(motion) failed")

        let requests = await hosted.transport.requested.count
        await hosted.transport.hold(2)
        try Self.press(Self.retryID, in: hosted)
        try await Self.waitForRequests(requests + 1, hosted)
        try Self.expectLoading(hosted, page: 2, "\(motion) Retry pressed")
        await hosted.transport.release(2)
    }
}
#endif
