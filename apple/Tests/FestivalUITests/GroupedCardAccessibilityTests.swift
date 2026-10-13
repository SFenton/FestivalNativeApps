#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Grouped dashboard cards accessibility (issue #381, backfilled by #499)

/// #381 put the repeated rows of the dashboard sections into one
/// ``FestivalGlassSection`` group card, like the Rivals cards (surface-materials R8):
/// rows sit edge to edge with inset hairlines between them, draw no card of their own,
/// and the selected player's row is a flat purple band. These hosted checks pin what that
/// grouping exposes to VoiceOver, Voice Control, Switch Control and Dynamic Type on every
/// Apple platform (iPhone, iPad, iPhone Duo and Mac share the SwiftUI) for the
/// Leaderboards overview card, the Song Details top-scores card and the Score History
/// card, plus the canonical flush group on both row layouts:
///
/// - each card reads its heading, then its rows in visual order, then its View All;
///   the hairlines between rows never reach the tree, and nothing else sits between;
/// - each row is one named element (a button that opens the player, or a Score History
///   text row) and the selected player's row says so in words ("Your rank, 2nd"; the
///   best score "best score"), not only with the purple band (HIG: "Never rely on color
///   alone");
/// - each row is a target at least 44 pt tall spanning the card, the rows tile the card
///   with only the 1 pt hairline between them, and View All ends the card below them;
/// - AXPress still activates a grouped row on the iOS 18 / macOS 15 and the iOS 17 /
///   macOS 14 row layouts;
/// - at the largest accessibility size all of that holds.
///
/// macOS keeps the font size, so the AX5 cases pin the tree and the layout; the iPhone and
/// iPad journey `GroupedCardAccessibilityJourneyTests` proves text growth and runs the
/// scoped audit on device. Compete's grouped previews are covered by
/// `CompeteLeaderboardsAccessibilityTests` and `CompeteAccessibilityJourneyTests`.
///
/// HIG Accessibility: "Strive for the platform's recommended minimum control size"
/// (iOS/iPadOS 44 × 44 pt); HIG VoiceOver: "Specify how elements are grouped, ordered or
/// linked"; HIG Lists and tables: grouped style.
@MainActor
@Suite(.serialized)
struct GroupedCardAccessibilityTests {
    // MARK: - Hosting

    /// One hosted page, its window and storage.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// The tree in VoiceOver's reading order.
        func order() -> [MacAXNode] { macAccessibilityTree(host, navigationOrder: true) }

        /// The frame of the first element with `identifier`.
        func frame(_ identifier: String) throws -> CGRect {
            try #require(nativeHostedAccessibilityFrame(identifier, in: host), "\(identifier) frame")
        }
    }

    /// Host `content` on a phone-width dark page at a Dynamic Type size with the app's
    /// Reduce Motion on, and wait until every `ready` identifier is realized.
    ///
    /// - Parameters:
    ///   - width: Page width in points.
    ///   - typeSize: Dynamic Type size for the page.
    ///   - ready: Accessibility identifiers that must be in the tree.
    ///   - content: The page under test.
    /// - Returns: The settled host.
    /// - Throws: A page that never settles.
    static func host(
        width: CGFloat = 402, typeSize: DynamicTypeSize, ready: [String],
        @ViewBuilder content: () -> some View
    ) async throws -> Hosted {
        let suiteName = "fst-grouped-card-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let size = CGSize(width: width, height: 1600)
        let host = nativeHostedView(
            AnyView(
                content()
                    .frame(width: size.width, height: size.height)
                    .defaultAppStorage(storage)
                    .background(BrandTokens.appBackground)
                    .environment(\.horizontalSizeClass, .compact)
                    .environment(\.dynamicTypeSize, typeSize)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            ready.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
        }
        return Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
    }

    /// A fixture session with `accountId` selected in memory (never `UserDefaults`).
    ///
    /// - Parameters:
    ///   - client: The fixture client, or nil for a session that never reads.
    ///   - accountId: The selected player.
    ///   - displayName: Their display name.
    /// - Returns: The session.
    /// - Throws: A malformed identity.
    static func session(
        client: FestivalAPI? = nil, selecting accountId: String, displayName: String
    ) throws -> FestivalSession {
        let result = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
        {"accountId":"\(accountId)","displayName":"\(displayName)"}
        """.utf8))
        return FestivalSession(
            factory: { if let client { return client }; throw FestivalAPIError.invalidResource },
            debugSelectedPlayer: try SelectedPlayerIdentity(searchResult: result)
        )
    }

    // MARK: - Tree and layout checks

    /// The elements VoiceOver stops on between two nodes, one per row: an element's own
    /// descendants (a row button's text) are skipped, containers are looked through.
    ///
    /// - Parameters:
    ///   - nodes: The tree in reading order.
    ///   - start: Index of the element before the range (the card's heading).
    ///   - end: Index of the element after the range (the card's View All).
    /// - Returns: The top-level elements in between, in reading order.
    static func stops(_ nodes: [MacAXNode], after start: Int, before end: Int) -> [MacAXNode] {
        guard start + 1 < end else { return [] }
        var result: [MacAXNode] = []
        var ownerDepth: Int?
        for node in nodes[(start + 1)..<end] {
            if let depth = ownerDepth, node.depth > depth { continue }
            ownerDepth = nil
            if node.isElement {
                result.append(node)
                ownerDepth = node.depth
            }
        }
        return result
    }

    /// The index of the first element matching `match`.
    static func index(
        _ nodes: [MacAXNode], _ what: String, sourceLocation: SourceLocation = #_sourceLocation,
        where match: (MacAXNode) -> Bool
    ) throws -> Int {
        try #require(
            nodes.firstIndex { $0.isElement && match($0) },
            "\(what) in the reading order:\n\(dump(nodes))", sourceLocation: sourceLocation
        )
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.filter(\.isElement).map(\.description).joined(separator: "\n")
    }

    /// The rows tile one card: each at least 44 pt tall, all the same full width at the
    /// same x, one under the other with at most the 1 pt hairline between them (no
    /// untappable gap), and the card's View All below the last row.
    ///
    /// - Parameters:
    ///   - rows: Row frames, top to bottom.
    ///   - cardWidth: The group card's width.
    ///   - viewAll: The View All button's frame.
    ///   - context: Failure context.
    static func expectRowsTileTheCard(
        _ rows: [CGRect], cardWidth: CGFloat, viewAll: CGRect, _ context: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for row in rows {
            #expect(row.height >= 44 - 0.5, "\(context): a row is a 44 pt target: \(row)",
                    sourceLocation: sourceLocation)
            #expect(row.width >= cardWidth - 1, "\(context): a row spans the \(cardWidth) pt card: \(row)",
                    sourceLocation: sourceLocation)
        }
        for (upper, lower) in zip(rows, rows.dropFirst()) {
            #expect(abs(upper.minX - lower.minX) <= 0.5 && abs(upper.width - lower.width) <= 0.5,
                    "\(context): rows share the card's edges: \(upper) vs \(lower)", sourceLocation: sourceLocation)
            let gap = lower.minY - upper.maxY
            #expect(gap >= -0.5 && gap <= FestivalLeadingHairline.height + 0.5,
                    "\(context): only the hairline separates rows (gap \(gap)): \(upper) / \(lower)",
                    sourceLocation: sourceLocation)
        }
        if let last = rows.last {
            #expect(viewAll.minY >= last.maxY - 0.5, "\(context): View All ends the card: \(viewAll) under \(last)",
                    sourceLocation: sourceLocation)
            #expect(viewAll.height >= 44 - 0.5, "\(context): View All is a 44 pt target: \(viewAll)",
                    sourceLocation: sourceLocation)
            // View All sits `actionInset` inside the card on each side.
            let inset = FestivalGlassSection<EmptyView, EmptyView>.actionInset
            #expect(abs(viewAll.minX - inset - last.minX) <= 1 && abs(viewAll.width + 2 * inset - last.width) <= 1,
                    "\(context): View All is inside the rows' card: \(viewAll) vs \(last)",
                    sourceLocation: sourceLocation)
        }
    }

    // MARK: - Leaderboards overview

    static let leadCard = "fst.leaderboards.card.\(Instrument.lead.rawValue)"
    static let leadViewAll = "\(leadCard).view-all"
    static let rankingRows = (1...3).map { "fst.rankings.row.fixture-rank-\($0)" }

    /// The Lead card of the Leaderboards overview reads "Lead", its three rows (the
    /// selected player's second, spoken "Your rank, 2nd"), then View all rankings: one
    /// named button per row, no hairline or extra stop between, every row a full-width
    /// 44 pt target in one card, at the default and the largest text size.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func leaderboardsCardReadsHeadingRowsThenViewAll(_ typeSize: DynamicTypeSize) async throws {
        let context = "Leaderboards Lead, \(typeSize)"
        let client = try FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: HostedRankingsTransport())
        let session = try Self.session(client: client, selecting: "fixture-rank-2", displayName: "Fixture Rank 2")
        let hosted = try await Self.host(typeSize: typeSize, ready: Self.rankingRows + [Self.leadViewAll]) {
            NavigationStack { LeaderboardsScreen(session: session) }
        }
        defer { hosted.close() }
        let nodes = hosted.order()
        macAccessibilityDump(nodes, name: "grouped-leaderboards-\(typeSize)")

        let heading = try Self.index(nodes, "Lead heading") { $0.role == "AXHeading" && $0.spokenName == "Lead" }
        let viewAll = try Self.index(nodes, "View all rankings") { $0.identifier == Self.leadViewAll }
        let stops = Self.stops(nodes, after: heading, before: viewAll)
        #expect(stops.map(\.identifier) == Self.rankingRows,
                "\(context): heading, the rows in rank order, then View All:\n\(Self.dump(stops))")
        for row in stops {
            #expect(row.role == "AXButton", "\(context): a row is one button: \(row)")
            #expect(!row.selected, "\(context): a row is a link, not a selectable item: \(row)")
        }
        if stops.count == 3 {
            #expect(stops[1].spokenName == "Your rank, \(RankingFormatting.ordinal(2)). Fixture Rank 2.",
                    "\(context): the purple band is also spoken: \(stops[1])")
            for row in [stops[0], stops[2]] {
                #expect(!row.spokenName.hasPrefix("Your rank"), "\(context): \(row)")
            }
            #expect(stops[0].spokenName.contains("Fixture Rank 1") && stops[2].spokenName.contains("Fixture Rank 3"),
                    "\(context): rows are named by their player: \(Self.dump(stops))")
        }
        let button = nodes[viewAll]
        #expect(button.role == "AXButton" && button.spokenName == "View all rankings (3), Lead",
                "\(context): \(button)")

        let rows = try Self.rankingRows.map { try hosted.frame($0) }
        let viewAllFrame = try hosted.frame(Self.leadViewAll)
        let card = viewAllFrame.width + 2 * FestivalGlassSection<EmptyView, EmptyView>.actionInset
        Self.expectRowsTileTheCard(rows, cardWidth: card, viewAll: viewAllFrame, context)
        #expect(macAccessibilityFindings(nodes) == [], "\(context)")
    }

    // MARK: - Song Details top scores

    static let previewRows = SongSeasonAccessibilityTests.topRows
    static let previewViewFull = "fst.song-detail.leaderboard.\(Instrument.lead.rawValue)"
    static let previewHeader = "fst.song-detail.card-header.\(Instrument.lead.rawValue)"

    /// The Lead top-scores card on Song Details reads its instrument header, the three
    /// rows (the selected player's spoken "Your rank, 2nd"), then View Full Leaderboard;
    /// each row is one button and a full-width 44 pt target in the one card.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func songTopScoresCardReadsHeaderRowsThenViewFull(_ typeSize: DynamicTypeSize) async throws {
        let context = "Song Details top scores, \(typeSize)"
        let payload = try SongSeasonAccessibilityTests.topScores()
        let session = try Self.session(selecting: "p2", displayName: "Player Two")
        let hosted = try await Self.host(typeSize: typeSize, ready: Self.previewRows + [Self.previewViewFull]) {
            NavigationStack {
                ScrollView {
                    SongScorePreview(
                        song: SongSeasonAccessibilityTests.song, instrument: .lead, session: session,
                        initialState: .loaded(payload)
                    )
                    .padding(16)
                }
            }
        }
        defer { hosted.close() }
        let nodes = hosted.order()
        macAccessibilityDump(nodes, name: "grouped-song-top-scores-\(typeSize)")

        let header = try Self.index(nodes, "Lead header") { $0.identifier == Self.previewHeader }
        #expect(nodes[header].role == "AXHeading", "\(context): \(nodes[header])")
        let viewFull = try Self.index(nodes, "View Full Leaderboard") { $0.identifier == Self.previewViewFull }
        let stops = Self.stops(nodes, after: header, before: viewFull)
        #expect(stops.map(\.identifier) == Self.previewRows,
                "\(context): header, the rows in rank order, then View Full Leaderboard:\n\(Self.dump(stops))")
        for row in stops { #expect(row.role == "AXButton", "\(context): \(row)") }
        if stops.count == 3 {
            #expect(stops[1].spokenName.hasPrefix("Your rank, \(RankingFormatting.ordinal(2)), Player Two"),
                    "\(context): the purple band is also spoken: \(stops[1])")
            #expect(stops[0].spokenName.hasPrefix("#1, Player One") && stops[2].spokenName.hasPrefix("#3, Player Three"),
                    "\(context): \(Self.dump(stops))")
        }
        #expect(nodes[viewFull].role == "AXButton" && nodes[viewFull].spokenName == "View Full Leaderboard, Lead",
                "\(context): \(nodes[viewFull])")

        let rows = try Self.previewRows.map { try hosted.frame($0) }
        let viewFullFrame = try hosted.frame(Self.previewViewFull)
        let card = viewFullFrame.width + 2 * FestivalGlassSection<EmptyView, EmptyView>.actionInset
        Self.expectRowsTileTheCard(rows, cardWidth: card, viewAll: viewFullFrame, context)
        #expect(macAccessibilityFindings(nodes) == [], "\(context)")
    }

    // MARK: - Score History

    /// Six Lead scores, so the card shows its five best and View All Scores.
    ///
    /// - Returns: Decoded history rows, the best (950,000) third chronologically.
    /// - Throws: Malformed fixture JSON.
    static func historyEntries() throws -> [ScoreHistoryEntry] {
        let scores = [700_000, 800_000, 950_000, 600_000, 750_000, 650_000]
        let rows = scores.enumerated().map { day, score in
            """
            {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":\(score),
             "newRank":\(day + 1),"accuracy":950000,"isFullCombo":false,
             "scoreAchievedAt":"2024-01-0\(day + 1)T12:00:00Z","changedAt":"2024-01-0\(day + 1)T12:00:00Z"}
            """
        }
        return try JSONDecoder().decode([ScoreHistoryEntry].self, from: Data("[\(rows.joined(separator: ","))]".utf8))
    }

    static let historyRows = (0..<SongScoreHistoryModel.listLimit).map { "fst.song-detail.history.row.\($0)" }
    static let historyViewAll = "fst.song-detail.history.view-all"
    static let historyChart = "fst.song-detail.history.chart"

    /// The Score History card reads its heading, the instrument selector and chart, the
    /// five best scores (the best one spoken "best score", not only purple and bold), then
    /// View All Scores; the rows tile the card under the chart and View All Scores ends it.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func scoreHistoryCardReadsHeadingChartRowsThenViewAll(_ typeSize: DynamicTypeSize) async throws {
        let context = "Score History, \(typeSize)"
        let entries = try Self.historyEntries()
        let hosted = try await Self.host(typeSize: typeSize, ready: Self.historyRows + [Self.historyViewAll]) {
            NavigationStack {
                ScrollView {
                    SongScoreHistorySection(
                        song: SongSeasonAccessibilityTests.song, entries: entries, pool: [.lead],
                        instrument: .constant(nil), viewportWidth: 402, currentSeason: 40
                    )
                    .padding(16)
                }
            }
        }
        defer { hosted.close() }
        let nodes = hosted.order()
        macAccessibilityDump(nodes, name: "grouped-score-history-\(typeSize)")

        let heading = try Self.index(nodes, "Score History heading") {
            $0.role == "AXHeading" && $0.spokenName == "Score History"
        }
        let chart = try Self.index(nodes, "chart") { $0.identifier == Self.historyChart }
        let viewAll = try Self.index(nodes, "View All Scores") { $0.identifier == Self.historyViewAll }
        #expect(heading < chart && chart < viewAll, "\(context): heading, chart, then View All Scores")
        // After the chart (and its legend and pager), the card's rows are its last stops.
        let stops = Self.stops(nodes, after: chart, before: viewAll)
        let rowStops = stops.filter { $0.identifier.hasPrefix("fst.song-detail.history.row.") }
        #expect(rowStops.map(\.identifier) == Self.historyRows, "\(context): best first:\n\(Self.dump(stops))")
        #expect(Array(stops.suffix(Self.historyRows.count)).map(\.identifier) == Self.historyRows,
                "\(context): nothing but rows between the chart's controls and View All Scores:\n\(Self.dump(stops))")
        #expect(stops.allSatisfy { !$0.spokenName.isEmpty }, "\(context): no unnamed stop:\n\(Self.dump(stops))")
        for (index, row) in rowStops.enumerated() {
            #expect(row.role == "AXStaticText", "\(context): \(row)")
            #expect(row.spokenName.hasSuffix("best score") == (index == 0),
                    "\(context): only the best score says so: \(row)")
        }
        if let best = rowStops.first {
            #expect(best.spokenName.contains("950,000"), "\(context): the best score leads: \(best)")
        }
        let button = nodes[viewAll]
        #expect(button.role == "AXButton" && button.spokenName == "View All Scores, Lead Score History",
                "\(context): \(button)")

        let rows = try Self.historyRows.map { try hosted.frame($0) }
        let viewAllFrame = try hosted.frame(Self.historyViewAll)
        let card = viewAllFrame.width + 2 * FestivalGlassSection<EmptyView, EmptyView>.actionInset
        Self.expectRowsTileTheCard(rows, cardWidth: card, viewAll: viewAllFrame, context)
        let chartFrame = try hosted.frame(Self.historyChart)
        if let first = rows.first {
            #expect(first.minY >= chartFrame.maxY - 0.5, "\(context): rows follow the chart: \(first) under \(chartFrame)")
        }
        #expect(macAccessibilityFindings(nodes) == [], "\(context)")
    }

    // MARK: - Canonical flush group

    /// Records which grouped row was activated.
    @MainActor
    final class PressLog {
        var pressed: [Int] = []
    }

    /// Three 48 pt grouped row buttons, the middle one the selected player's, in a flush
    /// group card with a View All action, drawn with either row layout.
    struct GroupProbe: View {
        let stacked: Bool
        let log: PressLog

        private func row(_ index: Int) -> some View {
            Button { log.pressed.append(index) } label: {
                Text("Row \(index + 1)")
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .modifier(RankingRowSurface(isSelected: index == 1))
                    .contentShape(Rectangle())
            }
            .festivalRowButtonStyle()
            .accessibilityIdentifier("fst.test.group.row.\(index)")
        }

        var body: some View {
            let section = FestivalGlassSection("Group", rows: .flush()) {
                ForEach(0..<3, id: \.self) { row($0) }
            } action: {
                Button {} label: { PurpleActionLabel(title: "View All") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fst.test.group.view-all")
            }
            Group {
                if stacked { section.stackedRows() } else { section }
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    static let groupRows = (0..<3).map { "fst.test.group.row.\($0)" }
    static let groupViewAll = "fst.test.group.view-all"

    // MARK: - Stacked rankings rows

    /// Three rankings rows, the middle one the selected player's, in a flush group card
    /// narrow enough that accessibility sizes stack each row (rank and name, then songs,
    /// then the value), as an iPhone does at AX5.
    struct StackedRankingsProbe: View {
        var body: some View {
            FestivalGlassSection("Ranks", rows: .flush(separatorInset: RankingRowLayout.horizontalPadding)) {
                ForEach(0..<3, id: \.self) { index in
                    RankingRowLayout(
                        rank: index + 1, name: "P\(index + 1)", songs: "40 / 50", spokenSongs: "40 of 50 songs",
                        rating: "89,999,000", bayesian: nil, emphasized: index == 1, showsChevron: true
                    )
                    .modifier(RankingRowSurface(isSelected: index == 1))
                    .accessibilityIdentifier("fst.test.ranks.row.\(index)")
                }
            } action: {
                Button {} label: { PurpleActionLabel(title: "View All") }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("fst.test.ranks.view-all")
            }
            .padding(16)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    /// A stacked rankings row still fills its band of the group card: its target and the
    /// selected player's purple band span the card, not just the stacked text (#499: on an
    /// iPhone at AX5 the Leaderboards rows hugged their text, leaving a dead strip at the
    /// trailing edge and a purple band that stopped short of it).
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func stackedRankingRowsFillTheGroupCard(_ typeSize: DynamicTypeSize) async throws {
        let context = "stacked rankings rows, \(typeSize)"
        let rows = (0..<3).map { "fst.test.ranks.row.\($0)" }
        let viewAll = "fst.test.ranks.view-all"
        let hosted = try await Self.host(width: 200, typeSize: typeSize, ready: rows + [viewAll]) {
            StackedRankingsProbe()
        }
        defer { hosted.close() }
        let frames = try rows.map { try hosted.frame($0) }
        let viewAllFrame = try hosted.frame(viewAll)
        let card = viewAllFrame.width + 2 * FestivalGlassSection<EmptyView, EmptyView>.actionInset
        Self.expectRowsTileTheCard(frames, cardWidth: card, viewAll: viewAllFrame, context)
        let nodes = hosted.order()
        #expect(nodes.filter { $0.identifier.hasPrefix("fst.test.ranks.row.") && $0.isElement }.count == 3,
                "\(context): one element per row:\n\(Self.dump(nodes))")
        #expect(macAccessibilityFindings(nodes) == [], "\(context)")
    }

    /// On the iOS 18 / macOS 15 enumerated rows and the iOS 17 / macOS 14 stacked rows
    /// alike, the flush group exposes exactly its heading, one button per row and View
    /// All: the hairlines (enumerated separators and `FestivalLeadingHairline`) never
    /// reach the tree, rows tile the card, and AXPress activates the row it names.
    @Test(arguments: [false, true])
    func flushGroupExposesOnlyRowsAndActivatesThem(stacked: Bool) async throws {
        let context = stacked ? "stacked rows" : "enumerated rows"
        let log = PressLog()
        let hosted = try await Self.host(typeSize: .large, ready: Self.groupRows + [Self.groupViewAll]) {
            GroupProbe(stacked: stacked, log: log)
        }
        defer { hosted.close() }
        let nodes = hosted.order()
        let heading = try Self.index(nodes, "Group heading") { $0.role == "AXHeading" && $0.spokenName == "Group" }
        let viewAll = try Self.index(nodes, "View All") { $0.identifier == Self.groupViewAll }
        let stops = Self.stops(nodes, after: heading, before: viewAll)
        #expect(stops.map(\.identifier) == Self.groupRows, "\(context): rows only:\n\(Self.dump(stops))")
        #expect(stops.map(\.spokenName) == ["Row 1", "Row 2", "Row 3"], "\(context): \(Self.dump(stops))")
        #expect(stops.allSatisfy { $0.role == "AXButton" }, "\(context): \(Self.dump(stops))")
        #expect(viewAll == nodes.lastIndex { $0.isElement }, "\(context): View All is the card's last stop")

        let rows = try Self.groupRows.map { try hosted.frame($0) }
        Self.expectRowsTileTheCard(rows, cardWidth: 402 - 32, viewAll: try hosted.frame(Self.groupViewAll), context)

        let middle = try #require(nativeHostedAccessibilityElement(Self.groupRows[1], in: hosted.host))
        _ = middle.perform(NSSelectorFromString("accessibilityPerformPress"))
        try await nativeHostedSettle(hosted.host) { !log.pressed.isEmpty }
        #expect(log.pressed == [1], "\(context): AXPress opens the named row")
        #expect(macAccessibilityFindings(nodes) == [], "\(context)")
    }
}
#endif
