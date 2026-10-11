#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// Score History entries on one date, so only the score column can change a row's width.
///
/// - Parameter scores: Each row's score and accuracy (nil for a row without one).
/// - Returns: Decoded entries in the given order.
private func historyEntries(_ scores: [(Int, Int?)]) throws -> [ScoreHistoryEntry] {
    let rows = scores.map { score, accuracy in
        """
        {"songId":"fixture-anthem","instrument":"Solo_Guitar","oldScore":null,"newScore":\(score),
         "oldRank":null,"newRank":4,"accuracy":\(accuracy.map(String.init) ?? "null"),"isFullCombo":false,
         "season":8,"scoreAchievedAt":"2026-02-08T00:00:00Z","changedAt":"2026-02-08T00:00:00Z"}
        """
    }
    return try JSONDecoder().decode([ScoreHistoryEntry].self, from: Data("[\(rows.joined(separator: ","))]".utf8))
}

/// The ideal (unconstrained) width of one Score History row with its season column on.
///
/// Rows of one list draw `date · season · score · accuracy` across the same width, so
/// equal ideal widths for the same date mean the season pills and scores line up.
///
/// - Parameters:
///   - entry: The row's score.
///   - columns: The list's shared columns, or nil for natural widths.
///   - textSize: Dynamic Type size.
/// - Returns: The row's fitting width in points.
@MainActor
private func idealWidth(
    _ entry: ScoreHistoryEntry, columns: LeaderboardRowColumns?, textSize: DynamicTypeSize = .large
) -> CGFloat {
    let host = NSHostingView(rootView:
        ScoreHistoryListRow(entry: entry, isBest: false, seasonColumn: true, currentSeason: 9)
            .leaderboardSectionColumns(columns)
            .environment(\.dynamicTypeSize, textSize)
            .fixedSize()
    )
    host.layoutSubtreeIfNeeded()
    return host.fittingSize.width
}

// MARK: - Alignment (#594)

/// Score History rows share one score column (web `scoreWidth`), so a six-digit score,
/// a seven-digit score and a row without accuracy keep the season pill and score on the
/// same x, at the default and the largest non-accessibility text sizes.
@MainActor
@Test(arguments: [DynamicTypeSize.large, .xxxLarge])
func scoreHistoryRowsShareOneScoreColumn(textSize: DynamicTypeSize) throws {
    let entries = try historyEntries([(99_800, 980_000), (1_234_567, 991_200), (708_315, nil)])
    let columns = LeaderboardRowColumns.scoreHistory(entries.map(\.newScore))
    let widths = entries.map { idealWidth($0, columns: columns, textSize: textSize) }
    #expect((widths.max() ?? 0) - (widths.min() ?? 0) < 0.5, "fitted widths at \(textSize): \(widths)")
}

/// Control (the #594 reproduction): without the shared column a shorter score moves the
/// season pill, so the alignment above comes from the shared column.
@MainActor
@Test func unfittedScoreHistoryRowsMisalign() throws {
    let entries = try historyEntries([(99_800, 980_000), (1_234_567, 991_200)])
    let widths = entries.map { idealWidth($0, columns: nil) }
    #expect(abs(widths[0] - widths[1]) > 4, "natural widths: \(widths)")
}

/// Accessibility: the hidden width template and the empty accuracy slot never reach
/// VoiceOver. Each row stays one element in list order whose label reads its own score,
/// with a 44 pt minimum height; at accessibility sizes rows stack at natural widths.
@MainActor
@Test(arguments: [DynamicTypeSize.large, .accessibility3])
func scoreHistoryColumnsKeepRowAccessibility(textSize: DynamicTypeSize) async throws {
    let entries = try historyEntries([(99_800, 980_000), (1_234_567, 991_200), (708_315, nil)])
    let size = CGSize(width: textSize.isAccessibilitySize ? 320 : 600, height: 720)
    let host = nativeHostedView(
        VStack(spacing: 8) {
            ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                ScoreHistoryListRow(entry: entry, isBest: index == 1, seasonColumn: true, currentSeason: 9)
                    .accessibilityIdentifier("fst.history.row.\(index)")
            }
            Spacer(minLength: 0)
        }
        .leaderboardSectionColumns(.scoreHistory(entries.map(\.newScore)))
        .padding(.horizontal, 10)
        .environment(\.dynamicTypeSize, textSize)
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host, untilText: entries.map { "score \($0.newScore.formatted())" })
    let tree = macAccessibilityTree(host).filter(\.isElement)
    let rows = entries.indices.compactMap { index in tree.first { $0.identifier == "fst.history.row.\(index)" } }
    #expect(rows.count == entries.count, "\(textSize): \(tree)")
    for (index, row) in rows.enumerated() {
        #expect(row.spokenName.contains("score \(entries[index].newScore.formatted())"), "\(textSize): \(row)")
    }
    #expect(rows[1].spokenName.hasSuffix(", best score"))
    #expect(!rows[2].spokenName.contains("accuracy"), "\(rows[2])")
    // Nothing but the three rows is exposed: no template "1,234,567", no empty slot.
    #expect(tree.filter { !$0.spokenName.isEmpty }.count == entries.count, "\(textSize): \(tree)")
    var previousY = -CGFloat.infinity
    for index in entries.indices {
        let frame = try #require(nativeHostedAccessibilityFrame("fst.history.row.\(index)", in: host))
        #expect(frame.height >= 44 && frame.maxX <= size.width, "\(textSize): row \(index) \(frame)")
        // Top-left frames: list order reads top to bottom.
        #expect(frame.minY > previousY, "\(textSize): row \(index) order")
        previousY = frame.minY
    }
}
#endif
