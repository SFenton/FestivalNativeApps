#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// A decoded rankings row.
///
/// - Parameters:
///   - rank: Rank on every metric.
///   - name: Display name.
/// - Returns: A rankings entry.
private func rankingRow(rank: Int, name: String) throws -> AccountRankingEntry {
    let data = Data("""
    {"accountId":"height\(rank)","displayName":"\(name)","songsPlayed":700,
     "totalChartedSongs":731,"coverage":0.9,"rawSkillRating":0.01,
     "adjustedSkillRating":0.01,"adjustedSkillRank":\(rank),"weightedRating":0.02,
     "weightedRank":\(rank),"fcRate":0.4,"fcRateRank":\(rank),"totalScore":108213749,
     "totalScoreRank":\(rank),"maxScorePercent":0.9,"maxScorePercentRank":\(rank),
     "avgAccuracy":950000,"fullComboCount":5,"avgStars":4.0,"bestRank":1,"avgRank":2.0}
    """.utf8)
    return try JSONDecoder().decode(AccountRankingEntry.self, from: data)
}

/// The first Duos row of the committed band preview fixture.
private func bandRow() throws -> SongBandLeaderboardEntry {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appending(path: "contracts/fixtures/song-band-leaderboards-demo.json"))
    let response = try JSONDecoder().decode(SongBandLeaderboardsResponse.self, from: data)
    return try #require(response.preview(for: .duets).entries.first)
}

/// The height `view` takes at a 370 pt row width (iPhone 17 Pro content width).
///
/// - Parameters:
///   - view: Row to measure.
///   - dynamicTypeSize: Text size to lay it out at.
/// - Returns: The row's fitting height in points.
@MainActor
private func rowHeight(
    _ view: some View, dynamicTypeSize: DynamicTypeSize = .large
) -> CGFloat {
    return NSHostingView(
        rootView: view
            .frame(width: 370)
            .environment(\.dynamicTypeSize, dynamicTypeSize)
            .preferredColorScheme(.dark)
    ).fittingSize.height
}

// MARK: - Issue #90: one leaderboard row height

@Test @MainActor func leaderboardRowMetricMatchesWebEntryRowHeight() {
    // Web `Layout.entryRowHeight` (packages/theme/src/spacing.ts) and above the HIG's
    // 44 pt iOS minimum control size.
    #expect(LeaderboardRowMetrics.minHeight == 48)
}

@Test @MainActor func rankingsRowsMatchTheSongLeaderboardRowHeight() throws {
    let entry = try rankingRow(rank: 1, name: "Player One")
    let plain = rowHeight(AccountRankingRow(entry: entry, metric: .totalscore, cardSurface: true))
    let selected = rowHeight(
        AccountRankingRow(entry: entry, metric: .totalscore, isSelected: true, cardSurface: true)
    )
    #expect(plain == LeaderboardRowMetrics.minHeight)
    // The selected player's row (and the pinned footer, the same view) keeps the height.
    #expect(selected == plain)
}

@Test @MainActor func rankingsSkeletonRowsMatchLoadedRowHeight() throws {
    let entry = try rankingRow(rank: 1, name: "Player One")
    let loaded = rowHeight(AccountRankingRow(entry: entry, metric: .totalscore, cardSurface: true))
    let skeleton = rowHeight(RankingsSkeletonRows(count: 1, cardRows: true))
    #expect(skeleton == loaded)
}

@Test @MainActor func spotlightLoadingRowMatchesLoadedRowHeight() {
    let placeholder = rowHeight(
        RankingSpotlightLoadingRow()
            .frame(maxWidth: .infinity, minHeight: LeaderboardRowMetrics.minHeight)
    )
    #expect(placeholder == LeaderboardRowMetrics.minHeight)
}

@Test @MainActor func rankingsRowsGrowAtAccessibilityTextSizes() throws {
    let entry = try rankingRow(rank: 1, name: "Player One")
    let large = rowHeight(
        AccountRankingRow(entry: entry, metric: .totalscore, cardSurface: true),
        dynamicTypeSize: .accessibility3
    )
    // Stacked rank/name over songs/value: taller than the minimum, never clipped to it.
    #expect(large > LeaderboardRowMetrics.minHeight)
}

/// `/duo` Stage 5 Dynamic Type check: at AX5 a folded iPhone Duo row is ~350 pt wide
/// (466 pt window less the 84 pt vertical bar and margins), and its songs + value line
/// measured 596 pt, so the row ran under the bar and off the leading edge. macOS does not
/// scale fonts with Dynamic Type, so the same ratio is reproduced with a column narrower
/// than one line of songs + value: the stacked row must still fit the proposed width.
@Test(arguments: [DynamicTypeSize.accessibility1, .accessibility5])
@MainActor func rankingsRowsFitANarrowColumnAtAccessibilitySizes(_ size: DynamicTypeSize) throws {
    let entry = try rankingRow(rank: 868_662, name: "Cardinalsfan0351")
    let host = NSHostingController(
        rootView: AccountRankingRow(entry: entry, metric: .totalscore, isSelected: true, cardSurface: true)
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(.dark)
    )
    let width: CGFloat = 140
    let fitted = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    #expect(fitted.width <= width)
    #expect(fitted.height > LeaderboardRowMetrics.minHeight)
}

@Test @MainActor func bandScoreCardsAreAtLeastOneRowTall() throws {
    let height = rowHeight(SongBandPreviewRow(entry: try bandRow(), highlighted: false))
    #expect(height >= LeaderboardRowMetrics.minHeight)
}
#endif
