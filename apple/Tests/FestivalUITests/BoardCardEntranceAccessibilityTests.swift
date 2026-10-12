#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Board card entrance accessibility (owner, issue #614)

// #543 drew each board page (Solo and band song boards, Full Rankings) as one group card,
// a `festivalGroupSegment` per row, but each row still took its own stagger slot: the
// card's rows appeared one by one inside it. The owner asked for the card and all its
// content to fade in at once (#614), so every segment now fades with its card
// (`festivalCardSegmentFadeIn(cardIndex:)`, pattern `load-transition`). These hosted
// checks (macOS host, the same SwiftUI on iPhone, iPad, iPhone Duo and Mac) pin what
// that exposes: while the card waits, none of its rows is reachable; then every row the
// list built joins the tree together (never row by row), in rank order, each a 48 pt
// row; Reduce Motion (system or in-app) shows the card at once; and AX5 text keeps the
// rows whole and in order.

/// Accessibility of a board card's one-unit entrance.
///
/// HIG Motion: "Add motion purposefully; gratuitous or excessive animation distracts";
/// HIG Accessibility: "When Reduce Motion is on, reduce automatic and repetitive
/// animation", targets at least 44×44 pt, and text enlargement "of at least 200%".
@MainActor
@Suite(.serialized)
struct BoardCardEntranceAccessibilityTests {
    typealias Motion = ReloadGateAccessibilityTests.Motion

    /// When each row first became reachable, from the first sample of the load.
    struct Arrivals {
        /// Seconds from the first sample to each row's first appearance in the tree.
        var firstSeen: [String: TimeInterval] = [:]
        /// Rows reachable in the very first sample, before any fade could start.
        var initial: Set<String> = []

        /// The time between the first and the last row to appear, among `ids`.
        func spread(_ ids: [String]) -> TimeInterval? {
            let times = ids.compactMap { firstSeen[$0] }
            guard times.count == ids.count, let first = times.min(), let last = times.max() else { return nil }
            return last - first
        }
    }

    /// The board rows (identifiers starting `prefix`) reachable now, in reading order.
    static func rows(_ host: NSView, prefix: String) -> [String] {
        var seen = Set<String>()
        return nativeHostedAccessibility(host).identifiers.filter { $0.hasPrefix(prefix) && seen.insert($0).inserted }
    }

    /// Sample the tree often through the load and record when each row joins it.
    ///
    /// - Parameters:
    ///   - host: The hosted board.
    ///   - prefix: The rows' identifier prefix.
    ///   - expected: How many rows the first screen shows once the card is in.
    /// - Returns: Each row's arrival, once `expected` rows are in and the card's fade has
    ///   had time to finish.
    static func recordArrivals(
        _ host: NSHostingView<some View>, prefix: String, expected: Int,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> Arrivals {
        let clock = ContinuousClock()
        let start = clock.now
        var arrivals = Arrivals()
        var sampled = false
        var completeAt: ContinuousClock.Instant?
        while clock.now - start < .seconds(60) {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let now = clock.now
            let reachable = rows(host, prefix: prefix)
            if !sampled {
                arrivals.initial = Set(reachable)
                sampled = true
            }
            let elapsed = Double((now - start).components.attoseconds) / 1e18 + Double((now - start).components.seconds)
            for id in reachable where arrivals.firstSeen[id] == nil { arrivals.firstSeen[id] = elapsed }
            if completeAt == nil, reachable.count >= expected { completeAt = now }
            // Past the card's whole entrance: a straggler would have shown by now.
            if let completeAt, now - completeAt > .milliseconds(Int(FestivalFadeIn.completionDelay(itemCount: FestivalFadeIn.maxStaggeredItems) * 1000)) {
                return arrivals
            }
            try await Task.sleep(for: .milliseconds(8))
        }
        Issue.record("the board never showed \(expected) rows: \(arrivals.firstSeen)", sourceLocation: sourceLocation)
        return arrivals
    }

    /// Host a Song Leaderboard page of 25 rows (no selected-row reveal scroll).
    ///
    /// - Parameter spotlightRank: The rank of the selected player's own row on the page
    ///   (`fixture-spotlight-player`), or nil to leave it off the page.
    static func hostSoloBoard(
        typeSize: DynamicTypeSize, motion: Motion, storage: UserDefaults, spotlightRank: Int? = nil
    ) async throws -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow) {
        nativeHostedEnableAccessibility()
        let session = try await spotlightSelectedSession()
        let song = try spotlightFixtureSong()
        let payload = try spotlightFixtureLeaderboard(spotlightRank: spotlightRank)
        let size = CGSize(width: 402, height: 900)
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    SoloLeaderboardScreen(
                        song: song, instrument: .lead, session: session,
                        initialPage: 1, path: .constant([]), initialState: .loaded(payload)
                    )
                }
                .frame(width: size.width, height: size.height)
                .environment(\.festivalFadeInEnabled, motion != .instant)
                .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
                .environment(\.dynamicTypeSize, typeSize)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
            ),
            size: size
        )
        return (host, nativeHostedWindow(host, size: size))
    }

    /// The first rows of the solo board fixture, in rank order.
    static func soloRowIDs(_ count: Int) -> [String] {
        (1...count).map { "fst.song-leaderboard.row.fixture-other-\($0)" }
    }

    // MARK: Solo board

    /// The board card's rows join the tree together, in rank order, as 48 pt rows of
    /// one card; under Reduce Motion (system or in-app) they are there from the start.
    @Test(arguments: [
        (Motion.animated, DynamicTypeSize.large),
        (Motion.animated, DynamicTypeSize.accessibility5),
        (Motion.systemReduceMotion, DynamicTypeSize.large),
        (Motion.appReduceMotion, DynamicTypeSize.large),
    ])
    func soloBoardRowsArriveWithTheirCard(_ motion: Motion, _ typeSize: DynamicTypeSize) async throws {
        let suiteName = "fst-board-card-entrance-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let (host, window) = try await Self.hostSoloBoard(typeSize: typeSize, motion: motion, storage: storage)
        defer { window.orderOut(nil) }

        // Rows at the top of the card: at AX5 a screenful holds fewer of them.
        let firstScreen = typeSize.isAccessibilitySize ? 3 : 6
        let ids = Self.soloRowIDs(firstScreen)
        let arrivals = try await Self.recordArrivals(host, prefix: "fst.song-leaderboard.row.", expected: firstScreen)
        let spread = try #require(arrivals.spread(ids), "rows \(ids) all arrive: \(arrivals.firstSeen)")
        switch motion {
        case .animated:
            // Waiting rows stay out of the tree (no reachable invisible row) …
            #expect(arrivals.initial.isEmpty, "\(motion) \(typeSize): no row is reachable before the card fades in: \(arrivals.initial)")
            // … and then the whole card's rows arrive together, not 125 ms apart.
            #expect(spread < FestivalFadeIn.staggerInterval,
                    "\(motion) \(typeSize): rows arrive together, not one by one: \(arrivals.firstSeen)")
        case .systemReduceMotion, .appReduceMotion, .instant:
            #expect(Set(ids).isSubset(of: arrivals.initial),
                    "\(motion): the card shows at once, with no fade: \(arrivals.initial)")
        }

        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) { boardRowsAbut(ids, in: host) }
        let order = Self.rows(host, prefix: "fst.song-leaderboard.row.")
        #expect(Array(order.prefix(ids.count)) == ids, "\(motion) \(typeSize): rows read in rank order: \(order)")
        try expectBoardRowsInOneCard(ids, in: host)
        let text = nativeHostedAccessibility(host)
        #expect(text.contains("#1, Row 1") && text.contains("#2, Row 2"),
                "\(motion) \(typeSize): rows keep their labels")
    }

    // MARK: Full Rankings and band boards

    /// Full Rankings' card arrives as one: every row of its first screen joins the tree
    /// together, after the title and count.
    @Test func fullRankingsRowsArriveWithTheirCard() async throws {
        nativeHostedEnableAccessibility()
        let suiteName = "fst-board-card-entrance-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        storage.set(false, forKey: "fst.accessibility.reduceMotion")
        let transport = HostedRankingsTransport()
        let client = try FestivalAPI(baseURL: try #require(URL(string: "http://localhost")), transport: transport)
        let session = FestivalSession(factory: { client })
        let size = CGSize(width: 402, height: 900)
        let host = nativeHostedView(
            NavigationStack { FullRankingsScreen(session: session, instrument: .lead, rankBy: "totalscore") }
                .frame(width: size.width, height: size.height)
                .environment(\.festivalFadeInEnabled, true)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let ids = (1...3).map { "fst.rankings.row.fixture-rank-\($0)" }
        let arrivals = try await Self.recordArrivals(host, prefix: "fst.rankings.row.", expected: ids.count)
        let spread = try #require(arrivals.spread(ids), "rows \(ids) all arrive: \(arrivals.firstSeen)")
        #expect(spread < FestivalFadeIn.staggerInterval, "rows arrive together, not one by one: \(arrivals.firstSeen)")
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) { boardRowsAbut(ids, in: host) }
        #expect(Array(Self.rows(host, prefix: "fst.rankings.row.").prefix(ids.count)) == ids, "rank order")
        try expectBoardRowsInOneCard(ids, in: host)
    }

    /// The song band board's card arrives as one.
    @Test func songBandBoardRowsArriveWithTheirCard() async throws {
        nativeHostedEnableAccessibility()
        let suiteName = "fst-board-card-entrance-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        storage.set(false, forKey: "fst.accessibility.reduceMotion")
        let (session, _, _) = try await bandsFixtureSession()
        let catalogue = try await session.catalog()
        let song = try #require(catalogue.catalog.songs.first { $0.songId == "fixture-pulse" })
        let size = CGSize(width: 402, height: 900)
        let host = nativeHostedView(
            NavigationStack { SongBandLeaderboardScreen(session: session, song: song, bandType: "Band_Duets") }
                .environment(\.festivalFadeInEnabled, true)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let prefix = "fst.song-band-leaderboard.row."
        let arrivals = try await Self.recordArrivals(host, prefix: prefix, expected: 3)
        let ids = Array(Self.rows(host, prefix: prefix).prefix(3))
        #expect(ids.count == 3, "three rows: \(ids)")
        let spread = try #require(arrivals.spread(ids), "rows \(ids) all arrive: \(arrivals.firstSeen)")
        #expect(spread < FestivalFadeIn.staggerInterval, "rows arrive together, not one by one: \(arrivals.firstSeen)")
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) { boardRowsAbut(ids, in: host) }
        try expectBoardRowsInOneCard(ids, in: host)
    }
}
#endif
