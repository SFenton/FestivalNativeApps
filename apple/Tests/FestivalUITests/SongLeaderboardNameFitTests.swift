import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Scope (issue #364)

/// Only a board in a split's trailing pane decides between one-line rows and multi-row
/// cards; full-width and iPhone boards keep the marquee, and accessibility sizes already
/// stack and wrap every row.
@Test(arguments: [
    (true, DynamicTypeSize.large, true),
    (true, .xxxLarge, true),
    (true, .accessibility1, false),
    (false, .large, false),
    (false, .accessibility3, false),
])
func songBoardFitsNamesOnlyInTheTrailingPane(subPage: Bool, size: DynamicTypeSize, expected: Bool) {
    #expect(SongLeaderboardNameFit.fitsNames(subPage: subPage, size: size) == expected)
}

/// A stacked name wraps at every text size; a one-line name scrolls until accessibility
/// sizes.
@Test func stackedNamesWrapAtEveryTextSize() {
    #expect(LeaderboardNameText.presentation(for: .large, stacked: true) == .wrapping)
    #expect(LeaderboardNameText.presentation(for: .xSmall, stacked: true) == .wrapping)
    #expect(LeaderboardNameText.presentation(for: .large) == .marquee)
}

/// A missing or empty name reads "Unknown User", as the row draws it.
@Test func songBoardRowDisplayName() {
    func entry(_ name: String?) -> LeaderboardEntry {
        LeaderboardEntry(
            accountId: "a", displayName: name, score: 1, rank: 1, localRank: nil,
            accuracy: nil, isFullCombo: nil, stars: nil, season: nil, difficulty: nil
        )
    }
    #expect(SongLeaderboardEntryRow.displayName(entry("Ada")) == "Ada")
    #expect(SongLeaderboardEntryRow.displayName(entry("")) == "Unknown User")
    #expect(SongLeaderboardEntryRow.displayName(entry(nil)) == "Unknown User")
}

#if os(macOS)
import AppKit
import FestivalDesign

// MARK: - Fixtures

/// A name far wider than a trailing pane's one-line row.
private let longName = "GingerNINZ-IN_JPN The Extremely Long Display Name Of Doom"

/// A 25-row Lead page whose row 3 is `row3Name`.
///
/// - Parameter row3Name: Row 3's display name.
/// - Returns: A validated chart page.
private func nameFitLeaderboard(row3Name: String) throws -> LeaderboardPayload {
    let rows: [String] = (1...25).map { rank in
        let name = rank == 3 ? row3Name : "Row \(rank)"
        return #"{"accountId":"fixture-other-\#(rank)","displayName":"\#(name)","score":\#(99_000 - rank),"rank":\#(rank),"accuracy":985000,"season":8}"#
    }
    let data = Data("""
    {"songId":"fixture-pulse","instrument":"Solo_Guitar","count":25,
     "localEntries":500,"totalEntries":500,"entries":[\(rows.joined(separator: ","))]}
    """.utf8)
    let result = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
    try result.validate(songId: "fixture-pulse", instrument: .lead)
    return LeaderboardPayload(
        page: 1, leaderboard: result, publicationId: 13, observedPublicationId: 13, isStale: false
    )
}

/// The on-screen frame of the first accessibility element with each label.
///
/// - Parameter view: Hosting view to walk.
/// - Returns: Frames keyed by label, value or title.
@MainActor
private func labelFrames(_ view: NSView) -> [String: NSRect] {
    var frames: [String: NSRect] = [:]
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func walk(_ node: Any, depth: Int) {
        guard depth < 80, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return }
        if let frame = (read(object, "accessibilityFrame") as? NSValue)?.rectValue {
            for key in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
                if let text = read(object, key) as? String, !text.isEmpty, frames[text] == nil {
                    frames[text] = frame
                }
            }
        }
        for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, depth: depth + 1)
        }
        if let view = object as? NSView {
            for subview in view.subviews { walk(subview, depth: depth + 1) }
        }
    }
    walk(view, depth: 0)
    return frames
}

// MARK: - Multi-row card geometry

/// Stacked columns draw each row as a multi-row card: the name on its own line above
/// the rank and score, rank and score on one line, and every score (the bold pinned
/// row's too) ending on the same x, so the section stays aligned (#364).
@MainActor
@Test func stackedCardsPutTheNameAboveAlignedRankAndScore() async throws {
    let entries = [
        LeaderboardEntry(
            accountId: "a", displayName: longName, score: 1_234_567, rank: 9, localRank: nil,
            accuracy: 980_000, isFullCombo: false, stars: nil, season: 8, difficulty: nil
        ),
        LeaderboardEntry(
            accountId: "b", displayName: "Short", score: 99_800, rank: 10, localRank: nil,
            accuracy: nil, isFullCombo: true, stars: nil, season: 9, difficulty: nil
        ),
        LeaderboardEntry(
            accountId: "c", displayName: "Pinned", score: 708_315, rank: 1_234, localRank: nil,
            accuracy: 1_000_000, isFullCombo: true, stars: nil, season: nil, difficulty: nil
        ),
    ]
    let width: CGFloat = 360
    let columns = LeaderboardRowColumns.fit(
        .songLeaderboard, width: Double(width),
        ranks: entries.map(\.rank), scores: entries.map(\.score)
    ).fittingName(availableWidth: Double(width - 32), requiredWidth: Double(width * 2))
    #expect(columns.stacksName)
    let size = CGSize(width: width, height: 420)
    let host = nativeHostedView(
        VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                SongLeaderboardRowCard(
                    entry: entry, isPlayer: index == entries.count - 1, currentSeason: 9
                )
            }
        }
        .leaderboardSectionColumns(columns)
        .padding(16)
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Short", "Pinned"])
    _ = try nativeHostedPNG(
        image, filename: "song-leaderboard-stacked-cards.png", environment: "FST_LEADERBOARDS_RENDER_OUT"
    )
    let frames = labelFrames(host)
    var scoreEdges: [CGFloat] = []
    for entry in entries {
        let name = try #require(frames[entry.displayName ?? ""], "frames: \(frames.keys.sorted())")
        let rank = try #require(frames["#\(entry.rank.formatted())"], "frames: \(frames.keys.sorted())")
        let score = try #require(frames[entry.score.formatted()], "frames: \(frames.keys.sorted())")
        // AppKit frames grow upward: the name line sits above (greater y than) the
        // rank and score line, which share one baseline row.
        #expect(name.minY >= rank.maxY - 1, "\(entry.rank): name \(name), rank \(rank)")
        #expect(abs(rank.midY - score.midY) <= 1, "\(entry.rank): rank \(rank), score \(score)")
        #expect(name.minX <= rank.minX + 1, "\(entry.rank): name \(name), rank \(rank)")
        scoreEdges.append(score.maxX)
    }
    #expect(Set(scoreEdges.map { $0.rounded() }).count == 1, "score edges: \(scoreEdges)")
    // The long name wraps onto more lines, in full, instead of scrolling.
    let long = try #require(frames[longName])
    #expect(long.width <= width - 32 && long.height > 30, "long name: \(long)")
}

// MARK: - Board decision

/// Host the Solo board with `payload`, in the trailing pane beside Song Detail or full
/// width, and return the heights of rows 1 and 3 once settled (`stacked`: once the rows
/// have become multi-row cards).
@MainActor
private func boardRowHeights(
    _ payload: LeaderboardPayload, trailing: Bool, stacked: Bool = false, width: CGFloat = 520
) async throws -> (row1: CGFloat, row3: CGFloat) {
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: width, height: 900)
    let song = try spotlightFixtureSong()
    let host = nativeHostedView(
        NavigationStack {
            SoloLeaderboardScreen(
                song: song, instrument: .lead, session: session,
                initialPage: 1, path: .constant([]), initialState: .loaded(payload)
            )
            .splitPaneContext(trailing ? SplitPaneContext(role: .trailing, besideList: .songDetail) : nil)
        }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    func heights() -> (row1: CGFloat, row3: CGFloat) {
        (nativeHostedAccessibilityFrame("fst.song-leaderboard.row.fixture-other-1", in: host)?.height ?? 0,
         nativeHostedAccessibilityFrame("fst.song-leaderboard.row.fixture-other-3", in: host)?.height ?? 0)
    }
    // Settled once both rows are exposed and the frame stops changing, after the
    // probe's measurement has landed (and, when expected, the rows have stacked).
    _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        let measured = heights()
        return nativeHostedAccessibility(host).contains("#1, Row 1")
            && measured.row1 > 0 && measured.row3 > 0
            && (!stacked || measured.row1 > LeaderboardRowMetrics.minHeight + 16)
    }
    return heights()
}

/// In the trailing pane, one long name turns **every** row into a multi-row card (rows
/// stay one height); full width, the same board keeps one-line rows and the long name
/// scrolls (leaderboard-row R3).
@MainActor
@Test(arguments: [true, false])
func longNameStacksTheWholeTrailingBoard(trailing: Bool) async throws {
    let heights = try await boardRowHeights(
        try nameFitLeaderboard(row3Name: longName), trailing: trailing, stacked: trailing
    )
    if trailing {
        #expect(heights.row1 > LeaderboardRowMetrics.minHeight + 16, "heights: \(heights)")
        #expect(abs(heights.row1 - heights.row3) < 1, "heights: \(heights)")
    } else {
        #expect(abs(heights.row1 - LeaderboardRowMetrics.minHeight) < 1, "heights: \(heights)")
        #expect(abs(heights.row3 - LeaderboardRowMetrics.minHeight) < 1, "heights: \(heights)")
    }
}

/// A trailing-pane board whose names all fit keeps today's one-line rows.
@MainActor
@Test func fittingNamesKeepOneLineRowsInTheTrailingPane() async throws {
    let heights = try await boardRowHeights(try nameFitLeaderboard(row3Name: "Row 3"), trailing: true)
    #expect(abs(heights.row1 - LeaderboardRowMetrics.minHeight) < 1, "heights: \(heights)")
    #expect(abs(heights.row3 - LeaderboardRowMetrics.minHeight) < 1, "heights: \(heights)")
}
#endif
