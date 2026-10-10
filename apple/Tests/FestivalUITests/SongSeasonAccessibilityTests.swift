#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Song page season accessibility (issue #32, backfilled by #406)

/// Issue #32 added the season a score was achieved in to the song page's score rows:
/// a ``ScoreSeasonPill`` before the score in Score History list rows (from 520 pt of
/// page width), in the tapped bar's detail row (always) and in the instrument cards'
/// top-score rows (from 520 pt of card width), following ``ScoreRowSeasonPolicy``.
/// These hosted checks pin what those rows expose to VoiceOver, Voice Control and
/// Dynamic Type on every Apple platform (the same SwiftUI on iPhone, iPad, iPhone Duo
/// and Mac): the season and its current-season state are spoken, not only drawn as an
/// inverted pill; rows read in visual order with the season between date (or name) and
/// score; focus frames and targets span the row; and at accessibility sizes the pill
/// spells "Season N" out in full. HIG Accessibility: "Provide VoiceOver descriptions for
/// all interface elements"; "Never rely on color alone"; iOS/iPadOS default control size
/// 44×44 pt; HIG Typography: "Keep text truncation to a minimum as font size increases".
/// Real font growth on iPhone is checked by `SongSeasonAccessibilityJourneyTests`.
@MainActor
@Suite(.serialized)
struct SongSeasonAccessibilityTests {
    // MARK: - Fixtures

    /// The catalogue's current season in these fixtures.
    static let currentSeason = 40

    /// Three Lead scores: season 40 (current, the best), season 39 and one without a season.
    ///
    /// - Returns: Decoded history rows.
    /// - Throws: Malformed fixture JSON.
    static func historyEntries() throws -> [ScoreHistoryEntry] {
        try JSONDecoder().decode([ScoreHistoryEntry].self, from: Data("""
        [{"songId":"fixture-song","instrument":"Solo_Guitar","newScore":850000,
          "newRank":4,"accuracy":991200,"isFullCombo":true,"season":40,
          "scoreAchievedAt":"2024-01-05T12:00:00Z","changedAt":"2024-01-05T12:00:00Z"},
         {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":700000,
          "newRank":9,"accuracy":954500,"isFullCombo":false,"season":39,
          "scoreAchievedAt":"2024-01-01T12:00:00Z","changedAt":"2024-01-01T12:00:00Z"},
         {"songId":"fixture-song","instrument":"Solo_Guitar","newScore":600000,
          "newRank":15,"accuracy":901000,"isFullCombo":false,
          "scoreAchievedAt":"2023-12-20T12:00:00Z","changedAt":"2023-12-20T12:00:00Z"}]
        """.utf8))
    }

    static let song = Song(
        songId: "fixture-song", title: "Fixture Anthem", artist: "The Fixtures", album: nil,
        year: 2024, durationSeconds: 180, albumArt: nil, difficulty: nil,
        pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
    )

    /// A three-row Lead top-score card: seasons 9, 8 and none.
    ///
    /// - Returns: A validated, offline preview payload.
    /// - Throws: Malformed fixture JSON or leaderboard shape.
    static func topScores() throws -> LeaderboardPayload {
        let data = Data("""
        {"songId":"fixture-song","instrument":"Solo_Guitar","count":3,
         "localEntries":3,"totalEntries":3,"entries":[
          {"accountId":"p1","displayName":"Player One","score":99800,"rank":1,
           "accuracy":980000,"isFullCombo":false,"stars":5,"season":9},
          {"accountId":"p2","displayName":"Player Two","score":98700,"rank":2,
           "accuracy":970000,"isFullCombo":false,"stars":5,"season":8},
          {"accountId":"p3","displayName":"Player Three","score":97600,"rank":3,
           "accuracy":960000,"isFullCombo":false,"stars":5}]}
        """.utf8)
        let result = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
        try result.validate(songId: "fixture-song", instrument: .lead)
        return LeaderboardPayload(
            page: 1, leaderboard: result, publicationId: 7, observedPublicationId: 7, isStale: false
        )
    }

    /// One hosted view, its window and storage.
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

        /// The element with `identifier`, as the reading-order tree sees it.
        func node(_ identifier: String) throws -> MacAXNode {
            let nodes = macAccessibilityTree(host, navigationOrder: true)
            return try #require(
                nodes.first { $0.identifier == identifier && $0.isElement },
                "\(identifier) in\n\(nodes.map(\.description).joined(separator: "\n"))"
            )
        }

        func frame(_ identifier: String) throws -> CGRect {
            try #require(nativeHostedAccessibilityFrame(identifier, in: host), "\(identifier) frame")
        }
    }

    /// Host `content` at a page width and Dynamic Type size, settled once `ready` ids exist.
    ///
    /// - Parameters:
    ///   - width: Page width in points (393 is a portrait iPhone; 600 crosses 520).
    ///   - typeSize: Dynamic Type size for the whole page.
    ///   - ready: Accessibility identifiers that must be realized.
    ///   - content: The rows under test.
    /// - Returns: The settled host.
    /// - Throws: A capture that never settles.
    static func host(
        width: CGFloat, typeSize: DynamicTypeSize, ready: [String],
        @ViewBuilder content: () -> some View
    ) async throws -> Hosted {
        let suiteName = "fst-season-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let size = CGSize(width: width, height: 1400)
        let host = nativeHostedView(
            AnyView(
                ScrollView { VStack(spacing: 12) { content() }.padding(16) }
                    .frame(width: size.width, height: size.height)
                    .defaultAppStorage(storage)
                    .background(BrandTokens.appBackground)
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

    static let historyRows = (0..<3).map { "fst.song-detail.history.row.\($0)" }
    static let detailRow = "fst.test.history.detail"

    /// The Score History section at `width` plus the tapped bar's detail row, built with
    /// the same policy argument as the chart (`.historyDetail`), since a hosted Swift
    /// Charts selection cannot be tapped.
    static func hostHistory(width: CGFloat, typeSize: DynamicTypeSize = .large) async throws -> Hosted {
        let entries = try historyEntries()
        return try await host(width: width, typeSize: typeSize, ready: historyRows + [detailRow]) {
            SongScoreHistorySection(
                song: song, entries: entries, pool: [.lead], instrument: .constant(nil),
                viewportWidth: width, currentSeason: currentSeason
            )
            ScoreHistoryListRow(
                entry: entries[1], isBest: false,
                seasonColumn: ScoreRowSeasonPolicy.showsColumn(.historyDetail, width: 0),
                currentSeason: currentSeason
            )
            .accessibilityIdentifier(detailRow)
        }
    }

    static let topRows = ["p1", "p2", "p3"].map { "fst.song-detail.preview-row.Solo_Guitar.\($0)" }

    /// The Lead instrument card's top scores at `width`.
    static func hostTopScores(width: CGFloat, typeSize: DynamicTypeSize = .large) async throws -> Hosted {
        let payload = try topScores()
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        return try await host(width: width, typeSize: typeSize, ready: topRows) {
            NavigationStack {
                SongScorePreview(song: song, instrument: .lead, session: session, initialState: .loaded(payload))
            }
            .frame(height: 900)
        }
    }

    /// The pill's compact visible abbreviation must never reach the tree on its own
    /// ("S40" reads as "S forty").
    static func assertNoAbbreviatedSeason(_ nodes: [MacAXNode], sourceLocation: SourceLocation = #_sourceLocation) {
        let abbreviated = nodes.filter { node in
            node.isElement && node.spokenName.range(of: #"\bS\d+\b"#, options: .regularExpression) != nil
        }
        #expect(abbreviated.isEmpty, "abbreviated season exposed: \(abbreviated)", sourceLocation: sourceLocation)
    }

    // MARK: - Score History rows

    /// Each Score History row is one static-text element whose label reads date, season,
    /// score, accuracy in visual order; the current season is spoken as "current season",
    /// a row without a season says nothing about one, and the pill never reads on its own.
    /// Below 520 pt (every portrait iPhone) the list rows speak no season at all.
    @Test(arguments: [(393.0, false), (600.0, true)])
    func historyRowsSpeakTheSeasonBetweenDateAndScore(width: Double, shows: Bool) async throws {
        let hosted = try await Self.hostHistory(width: width)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "song-season-history-\(Int(width))")
        let rows = try Self.historyRows.map { try hosted.node($0) }
        for row in rows {
            #expect(row.role == "AXStaticText", "a score row is read-only text, not an unknown element: \(row)")
        }
        let best = rows[0].spokenName, older = rows[1].spokenName, unknown = rows[2].spokenName
        if shows {
            #expect(best.hasPrefix("Jan 5, 2024, current season 40, score 850,000"), "\(best)")
            #expect(best.hasSuffix("best score"), "\(best)")
            #expect(older.hasPrefix("Jan 1, 2024, season 39, score 700,000"), "\(older)")
            #expect(!older.contains("current"), "only the current season says current: \(older)")
        } else {
            for row in [best, older] { #expect(!row.contains("season"), "narrow pages hide the season: \(row)") }
        }
        #expect(unknown.hasPrefix("Dec 20, 2023, score 600,000"), "no season, no placeholder: \(unknown)")
        #expect(!nodes.contains { $0.isElement && ($0.spokenName.hasPrefix("Season ") || $0.spokenName.hasPrefix("Current season ")) },
                "the pill is folded into its row, not a separate stop")
        Self.assertNoAbbreviatedSeason(nodes)
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// The tapped bar's detail row always speaks the season, even on a portrait iPhone
    /// page where the list rows hide it (web `renderDetailCard`).
    @Test func tappedBarDetailRowAlwaysSpeaksTheSeason() async throws {
        let hosted = try await Self.hostHistory(width: 393)
        defer { hosted.close() }
        let detail = try hosted.node(Self.detailRow)
        #expect(detail.role == "AXStaticText", "\(detail)")
        #expect(detail.spokenName.hasPrefix("Jan 1, 2024, season 39, score 700,000"), "\(detail)")
    }

    /// Rows read top to bottom, best first, after the chart; every row's focus frame is
    /// the whole row (at least 44 pt tall and the card's width), so VoiceOver's cursor
    /// and touch exploration cover what the row draws, not just its text.
    @Test func historyRowsReadInVisualOrderWithWholeRowFrames() async throws {
        let hosted = try await Self.hostHistory(width: 600)
        defer { hosted.close() }
        let order = macAccessibilityTree(hosted.host, navigationOrder: true).filter(\.isElement)
        let ids = ["fst.song-detail.history.chart"] + Self.historyRows
        let indices = try ids.map { id in try #require(order.firstIndex { $0.identifier == id }, "\(id) is read") }
        #expect(indices == indices.sorted(), "chart, then rows best first: \(indices)")
        let card = try hosted.frame(SongScoreHistorySection.anchor)
        var previous: CGRect?
        for id in Self.historyRows {
            let row = try hosted.frame(id)
            #expect(row.height >= 44 - 0.5, "\(id) focus frame spans the 48 pt row: \(row)")
            #expect(row.width >= card.width - 2, "\(id) focus frame spans the card: \(row) in \(card)")
            if let previous { #expect(row.minY >= previous.maxY - 0.5, "\(id) stacks below the row before: \(row)") }
            previous = row
        }
    }

    // MARK: - Top-score rows

    /// On a card at least 520 pt wide each top-score row is one button reading rank, name,
    /// season, score and accuracy; a row without a season speaks no placeholder; rows
    /// read in rank order before View Full Leaderboard and stay full-width 44 pt targets.
    /// A phone-width card speaks no season.
    @Test(arguments: [(390.0, false), (600.0, true)])
    func topScoreRowsReadNameSeasonThenScore(width: Double, shows: Bool) async throws {
        let hosted = try await Self.hostTopScores(width: width)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "song-season-top-scores-\(Int(width))")
        let rows = try Self.topRows.map { try hosted.node($0) }
        for row in rows { #expect(row.role == "AXButton", "\(row)") }
        if shows {
            #expect(rows[0].spokenName.hasPrefix("#1, Player One, Season 9, 99,800"), "\(rows[0])")
            #expect(rows[1].spokenName.hasPrefix("#2, Player Two, Season 8, 98,700"), "\(rows[1])")
        } else {
            for row in rows { #expect(!row.spokenName.contains("Season"), "phone cards hide the season: \(row)") }
        }
        #expect(rows[2].spokenName.hasPrefix("#3, Player Three, 97,600"), "no season, no placeholder: \(rows[2])")
        Self.assertNoAbbreviatedSeason(nodes)
        #expect(macAccessibilityFindings(nodes) == [])

        let order = nodes.filter(\.isElement)
        let ids = Self.topRows + ["fst.song-detail.leaderboard.Solo_Guitar"]
        let indices = try ids.map { id in try #require(order.firstIndex { $0.identifier == id }, "\(id) is read") }
        #expect(indices == indices.sorted(), "rank order, then View Full Leaderboard: \(indices)")
        for id in Self.topRows {
            let frame = try hosted.frame(id)
            #expect(frame.height >= 44 - 0.5, "\(id) is a 44 pt target: \(frame)")
            #expect(frame.width >= width - 32 - 2, "\(id) target spans the card: \(frame)")
        }
    }

    // MARK: - Season pill

    /// The pill alone says "Season N" or "Current season N" (the inverted colours are
    /// not the only cue) and is static text, not a control.
    @Test func seasonPillNamesItsSeasonAndCurrentState() async throws {
        let hosted = try await Self.host(width: 393, typeSize: .large, ready: ["fst.test.pill.9", "fst.test.pill.8"]) {
            ScoreSeasonPill(season: 9, current: true).accessibilityIdentifier("fst.test.pill.9")
            ScoreSeasonPill(season: 8).accessibilityIdentifier("fst.test.pill.8")
            ScoreSeasonPill(season: nil).accessibilityIdentifier("fst.test.pill.none")
        }
        defer { hosted.close() }
        let current = try hosted.node("fst.test.pill.9")
        let past = try hosted.node("fst.test.pill.8")
        #expect(current.spokenName == "Current season 9" && current.role == "AXStaticText", "\(current)")
        #expect(past.spokenName == "Season 8" && past.role == "AXStaticText", "\(past)")
        let nodes = macAccessibilityTree(hosted.host)
        #expect(!nodes.contains { $0.identifier == "fst.test.pill.none" && $0.isElement },
                "the empty placeholder keeping the column aligned is hidden")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the pill drops its fixed 44 pt frame and spells
    /// "Season 39" out in full, never truncated; Score History rows (wide page and the
    /// tapped bar's row on a phone) still speak the season as whole-row static text inside
    /// the page and stack into one column; top-score rows restack, still read the season
    /// and stay inside the card.
    @Test func seasonStaysSpokenAndUntruncatedAtAccessibilitySizes() async throws {
        let full = Text("Season 39").font(.body.weight(.semibold)).monospacedDigit()
            .environment(\.dynamicTypeSize, .accessibility5)
        let needed = NSHostingView(rootView: full).fittingSize.width
        let pills = try await Self.host(width: 393, typeSize: .accessibility5, ready: ["fst.test.pill"]) {
            ScoreSeasonPill(season: 39).accessibilityIdentifier("fst.test.pill")
        }
        let pill = try pills.frame("fst.test.pill")
        #expect(try pills.node("fst.test.pill").spokenName == "Season 39")
        pills.close()
        #expect(pill.width >= needed - 0.5, "the spelled-out pill fits its text: \(pill.width) < \(needed)")
        #expect(pill.width > 44, "the pill drops its compact 44 pt frame: \(pill)")

        let standardHistory = try await Self.hostHistory(width: 600)
        let standardRow = try standardHistory.frame(Self.historyRows[1]).height
        standardHistory.close()
        let history = try await Self.hostHistory(width: 600, typeSize: .accessibility5)
        for id in Self.historyRows + [Self.detailRow] {
            let row = try history.node(id)
            let frame = try history.frame(id)
            #expect(row.role == "AXStaticText", "\(row)")
            #expect(frame.height >= 44 - 0.5 && frame.maxX <= 600 + 0.5, "\(id) stays a whole row on the page: \(frame)")
        }
        // Date, season, score and accuracy stack in one column rather than squeezing
        // each other a letter per line (#406; the iPhone journey reads it back at AX5).
        let stackedRow = try history.frame(Self.historyRows[1]).height
        #expect(stackedRow > standardRow * 2, "a season row stacks at AX5: \(stackedRow) vs \(standardRow)")
        #expect(try history.node(Self.historyRows[1]).spokenName.hasPrefix("Jan 1, 2024, season 39, score 700,000"))
        Self.assertNoAbbreviatedSeason(macAccessibilityTree(history.host))
        history.close()

        let phone = try await Self.hostHistory(width: 393, typeSize: .accessibility5)
        let detail = try phone.frame(Self.detailRow)
        #expect(try phone.node(Self.detailRow).spokenName.contains("season 39"))
        #expect(detail.maxX <= 393 + 0.5, "the tapped bar's row fits a phone page at AX5: \(detail)")
        phone.close()

        let standard = try await Self.hostTopScores(width: 600)
        let standardHeight = try standard.frame(Self.topRows[0]).height
        standard.close()
        let large = try await Self.hostTopScores(width: 600, typeSize: .accessibility5)
        defer { large.close() }
        let row = try large.frame(Self.topRows[0])
        #expect(row.height > standardHeight + 10, "the row restacks at AX5: \(row.height) vs \(standardHeight)")
        #expect(row.maxX <= 600 + 0.5, "the restacked row stays in the card: \(row)")
        #expect(try large.node(Self.topRows[0]).spokenName.hasPrefix("#1, Player One, Season 9, 99,800"))
        Self.assertNoAbbreviatedSeason(macAccessibilityTree(large.host))
    }
}
#endif
