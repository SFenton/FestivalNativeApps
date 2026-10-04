#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Presentation (issue #292)

/// Ordinary text sizes keep the name on one line (scrolling when it overflows);
/// accessibility sizes wrap it instead.
@Test(arguments: [
    (DynamicTypeSize.xSmall, LeaderboardNameText.Presentation.marquee),
    (.large, .marquee),
    (.xxxLarge, .marquee),
    (.accessibility1, .wrapping),
    (.accessibility5, .wrapping),
])
func leaderboardNamePresentation(size: DynamicTypeSize, expected: LeaderboardNameText.Presentation) {
    #expect(LeaderboardNameText.presentation(for: size) == expected)
}

/// The selected player's row draws its name bold; others regular body.
@Test func leaderboardNameFontFollowsEmphasis() {
    #expect(LeaderboardNameText.font(emphasized: false) == .body)
    #expect(LeaderboardNameText.font(emphasized: true) == .body.bold())
}

// MARK: - Hosted layout (issue #292)

/// A name far wider than any phone row.
private let longName = "GingerNINZ-IN_JPN The Extremely Long Display Name Of Doom"

/// Holds a measured size across the hosted render.
@MainActor
private final class SizeBox {
    var sizes: [Int: CGSize] = [:]
}

/// Lay `rows` out in a column of `width` and measure each row's own size, i.e. the
/// space it asks for (a row whose fixed columns overflow reports more than `width`).
///
/// - Parameters:
///   - rows: Rows to measure, top to bottom.
///   - width: Column width in points.
///   - dynamicTypeSize: Text size to render at.
/// - Returns: Each row's size, plus every exposed accessibility text.
@MainActor
private func measuredRows(
    _ rows: [AnyView], width: CGFloat, dynamicTypeSize: DynamicTypeSize = .large
) async throws -> (sizes: [CGSize], texts: [String]) {
    let box = SizeBox()
    let size = CGSize(width: width, height: 200 * CGFloat(rows.count))
    let host = nativeHostedView(
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                row.onGeometryChange(for: CGSize.self) { $0.size } action: { box.sizes[index] = $0 }
            }
        }
        .frame(width: width, alignment: .topLeading)
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host) { box.sizes.count == rows.count }
    let sizes = (0..<rows.count).compactMap { box.sizes[$0] }
    return (sizes, nativeHostedAccessibility(host).texts)
}

/// A song score row with `name`.
private func scoreRow(_ name: String, rank: Int) -> AnyView {
    AnyView(SongLeaderboardEntryRow(entry: LeaderboardEntry(
        accountId: "name\(rank)", displayName: name, score: 118_633, rank: rank,
        localRank: nil, accuracy: 1_000_000, isFullCombo: true, stars: 6, season: 8,
        difficulty: 3
    )))
}

/// A rankings row (Leaderboards, Full Rankings, Compete) with `name`.
private func rankingRow(_ name: String, emphasized: Bool = false) -> AnyView {
    AnyView(RankingRowLayout(
        rank: 1_234, name: name, songs: "728 / 729", spokenSongs: "728 of 729 songs",
        rating: "912,345,678", bayesian: nil, emphasized: emphasized, showsChevron: true
    ))
}

/// The Song Detail card from the report: a long name stays one line, so its row is
/// exactly as tall as a short name's, never wider than the card, and still spoken in
/// full (it used to wrap onto a second line).
@MainActor
@Test(arguments: [CGFloat(300), 390])
func longScoreRowNameStaysOneLineInsideTheRow(width: CGFloat) async throws {
    let (sizes, texts) = try await measuredRows(
        [scoreRow("uwphe", rank: 5), scoreRow(longName, rank: 10)], width: width
    )
    #expect(sizes.count == 2)
    guard sizes.count == 2 else { return }
    #expect(abs(sizes[1].height - sizes[0].height) < 0.5, "\(sizes)")
    #expect(sizes[1].width <= width + 0.5, "\(sizes[1]) in \(width)")
    #expect(texts.contains(longName), "\(texts)")
}

/// Rankings rows (plain and the bold selected row) keep their rank, songs, value and
/// chevron inside the row however long the name is, and VoiceOver reads it in full.
@MainActor
@Test(arguments: [false, true])
func longRankingRowNameStaysInsideTheRow(emphasized: Bool) async throws {
    let width: CGFloat = 320
    let (sizes, texts) = try await measuredRows(
        [rankingRow("uwphe", emphasized: emphasized), rankingRow(longName, emphasized: emphasized)],
        width: width
    )
    #expect(sizes.count == 2)
    guard sizes.count == 2 else { return }
    #expect(abs(sizes[1].height - sizes[0].height) < 0.5, "\(sizes)")
    #expect(sizes[1].width <= width + 0.5, "\(sizes[1]) in \(width)")
    #expect(texts.contains { $0.contains(longName) }, "\(texts)")
}

/// At accessibility sizes the stacked score row wraps a long name instead of
/// scrolling it, and still stays inside the row.
@MainActor
@Test func accessibilitySizeWrapsLongNamesInsideTheRow() async throws {
    let width: CGFloat = 390
    let (sizes, texts) = try await measuredRows(
        [scoreRow("uwphe", rank: 5), scoreRow(longName, rank: 10)],
        width: width, dynamicTypeSize: .accessibility3
    )
    #expect(sizes.count == 2)
    guard sizes.count == 2 else { return }
    #expect(sizes[1].height > sizes[0].height + 0.5, "\(sizes)")
    #expect(sizes[1].width <= width + 0.5, "\(sizes[1]) in \(width)")
    #expect(texts.contains(longName), "\(texts)")
}
#endif
