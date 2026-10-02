#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// A score row whose rank, name and score are distinct accessibility labels.
private func scoreEntry(rank: Int, score: Int, season: Int? = 8) -> LeaderboardEntry {
    LeaderboardEntry(
        accountId: "row\(rank)", displayName: "Name \(rank)", score: score, rank: rank,
        localRank: nil, accuracy: 980_000, isFullCombo: false, stars: 5, season: season,
        difficulty: 3
    )
}

/// The on-screen frame of every accessibility element, keyed by its label.
///
/// - Parameter view: Hosting view to walk (accessibility and AppKit subviews).
/// - Returns: The first frame seen for each non-empty label.
@MainActor
private func accessibilityFrames(_ view: NSView) -> [String: NSRect] {
    var frames: [String: NSRect] = [:]
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func walk(_ node: Any, depth: Int) {
        guard depth < 80, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return }
        // Static text exposes its string as the label, title or value.
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

/// Host score rows for `entries` at `width`, optionally inside a fitted section.
///
/// - Parameters:
///   - entries: Rows to draw, top to bottom (the last one bold, like a pinned row).
///   - width: Section width in points.
///   - fitted: Apply `LeaderboardRowColumns.fit(.songLeaderboard, …)` to the section.
/// - Returns: Label frames once every row name is exposed, and every exposed text.
@MainActor
private func hostedRows(
    _ entries: [LeaderboardEntry], width: CGFloat, fitted: Bool
) async throws -> (frames: [String: NSRect], texts: [String]) {
    let size = CGSize(width: width, height: 60 * CGFloat(entries.count) + 32)
    let columns = LeaderboardRowColumns.fit(
        .songLeaderboard, width: Double(width),
        ranks: entries.map(\.rank), scores: entries.map(\.score)
    )
    let host = nativeHostedView(
        VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                SongLeaderboardEntryRow(
                    entry: entry, isPlayer: index == entries.count - 1, currentSeason: 9
                )
            }
        }
        .leaderboardSectionColumns(fitted ? columns : nil)
        .padding(16)
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: entries.map { "Name \($0.rank)" })
    return (accessibilityFrames(host), nativeHostedAccessibility(host).texts)
}

/// Label frames of `hostedRows`.
@MainActor
private func hostedRowFrames(
    _ entries: [LeaderboardEntry], width: CGFloat, fitted: Bool
) async throws -> [String: NSRect] {
    try await hostedRows(entries, width: width, fitted: fitted).frames
}

// MARK: - Alignment

/// Rows of one section share the rank and score widths (web `computeRankWidth` /
/// `scoreWidth`), so names start and scores end on the same x, including a bold
/// pinned row with a four-digit rank, at a phone and a wide width (issue #37).
@MainActor
@Test(arguments: [CGFloat(390), 820])
func fittedSectionAlignsNamesAndScores(width: CGFloat) async throws {
    let entries = [
        scoreEntry(rank: 9, score: 99_800),
        scoreEntry(rank: 10, score: 1_234_567),
        scoreEntry(rank: 1_234, score: 708_315),
    ]
    let (frames, texts) = try await hostedRows(entries, width: width, fitted: true)
    // The hidden width templates never reach assistive technology.
    let pinnedRank = LeaderboardRowColumns.rankLabel(1_234)
    let widestScore = LeaderboardRowColumns.scoreLabel(1_234_567)
    #expect(texts.filter { $0 == pinnedRank }.count == 1, "texts: \(texts)")
    #expect(texts.filter { $0 == widestScore }.count == 1, "texts: \(texts)")
    let names = entries.compactMap { frames["Name \($0.rank)"]?.minX }
    let scores = entries.compactMap { frames[$0.score.formatted()]?.maxX }
    #expect(names.count == entries.count && scores.count == entries.count, "frames: \(frames)")
    #expect((names.max() ?? 0) - (names.min() ?? 0) < 0.5, "name x: \(names)")
    #expect((scores.max() ?? 0) - (scores.min() ?? 0) < 0.5, "score max x: \(scores)")
}

/// Control: without fitted columns the same rows misalign, so the alignment above
/// comes from the shared columns rather than from coincidence.
@MainActor
@Test func unfittedRowsKeepTheirNaturalWidths() async throws {
    let entries = [scoreEntry(rank: 9, score: 99_800), scoreEntry(rank: 1_234, score: 708_315)]
    let frames = try await hostedRowFrames(entries, width: 390, fitted: false)
    let names = entries.compactMap { frames["Name \($0.rank)"]?.minX }
    #expect(names.count == 2 && abs(names[0] - names[1]) > 4, "name x: \(names)")
}

/// The season column follows the section width: off on a phone, on from 520 pt.
@MainActor
@Test func fittedSeasonColumnFollowsTheSectionWidth() async throws {
    let entries = [scoreEntry(rank: 1, score: 99_800, season: 8)]
    let narrow = try await hostedRowFrames(entries, width: 390, fitted: true)
    #expect(narrow["Season 8"] == nil)
    let wide = try await hostedRowFrames(entries, width: 600, fitted: true)
    #expect(wide["Season 8"] != nil, "labels: \(wide.keys.sorted())")
}
#endif
