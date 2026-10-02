#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// A decoded rankings row with distinct name, songs played and total score.
///
/// - Parameters:
///   - rank: Total-score rank.
///   - name: Display name.
///   - songsPlayed: Songs played (out of 729 charted).
///   - totalScore: Total score.
/// - Returns: A rankings entry.
private func rankingRow(rank: Int, name: String, songsPlayed: Int, totalScore: Int) throws -> AccountRankingEntry {
    let data = Data("""
    {"accountId":"fit\(rank)","displayName":"\(name)","songsPlayed":\(songsPlayed),
     "totalChartedSongs":729,"coverage":0.5,"rawSkillRating":0.01,
     "adjustedSkillRating":0.01,"adjustedSkillRank":\(rank),"weightedRating":0.02,
     "weightedRank":\(rank),"fcRate":0.4,"fcRateRank":\(rank),"totalScore":\(totalScore),
     "totalScoreRank":\(rank),"maxScorePercent":0.9,"maxScorePercentRank":\(rank),
     "avgAccuracy":950000,"fullComboCount":5,"avgStars":4.0,"bestRank":1,"avgRank":2.0}
    """.utf8)
    return try JSONDecoder().decode(AccountRankingEntry.self, from: data)
}

/// A Compete-like card: two top rows plus the selected player's bold row with a
/// four-digit rank and the longest name.
private func competeRows() throws -> [AccountRankingEntry] {
    try [
        rankingRow(rank: 1, name: "Short One", songsPlayed: 728, totalScore: 912_345_678),
        rankingRow(rank: 2, name: "Second Player", songsPlayed: 9, totalScore: 88_000_000),
        rankingRow(rank: 1_234, name: "Selected Player X", songsPlayed: 611, totalScore: 7_654_321),
    ]
}

/// The selected (bold, pinned) row in `competeRows()`.
private let selectedAccount = "fit1234"

/// Every exposed accessibility label/title/value, in walk order.
///
/// Rankings rows combine their texts into one element (`children: .combine`), so a
/// row reads like `#1, Name, 728 of 729 songs, 912,345,678`; a hidden songs column
/// moves the spoken songs into that element's value.
///
/// - Parameter view: Hosting view to walk.
/// - Returns: `(label, value)` per element that has either.
@MainActor
private func accessibilityElements(_ view: NSView) -> [(label: String, value: String)] {
    var elements: [(String, String)] = []
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func walk(_ node: Any, depth: Int) {
        guard depth < 80, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return }
        let label = (read(object, "accessibilityLabel") as? String) ?? ""
        let value = (read(object, "accessibilityValue") as? String) ?? ""
        if !label.isEmpty || !value.isEmpty { elements.append((label, value)) }
        for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, depth: depth + 1)
        }
        if let view = object as? NSView {
            for subview in view.subviews { walk(subview, depth: depth + 1) }
        }
    }
    walk(view, depth: 0)
    return elements
}

/// Receives a measured width from inside a hosted view.
@MainActor
private final class WidthBox {
    var value: CGFloat = 0
}

/// The names `competeRows()` draw, bold for the selected row.
private func rowNames(_ entries: [AccountRankingEntry]) -> [RankingRowName] {
    entries.map {
        RankingRowName(name: AccountRankingRow.displayName($0), emphasized: $0.accountId == selectedAccount)
    }
}

/// Host the rows as one Compete card at `width`.
///
/// - Parameters:
///   - entries: Rows top to bottom.
///   - width: Card width in points.
///   - fitsSongs: Apply `leaderboardSectionColumns(_:hidingCrowdedSongsFor:)`; false
///     applies only the shared #37 columns (songs always shown).
///   - rowPadding: Horizontal padding per side between the measured section and its
///     rows (Full Rankings pads 16).
///   - declaredInset: The `rowInset` passed to the fit.
/// - Returns: Every exposed element.
@MainActor
private func hostedCard(
    _ entries: [AccountRankingEntry], width: CGFloat, fitsSongs: Bool = true,
    rowPadding: CGFloat = 0, declaredInset: CGFloat = 0
) async throws -> [(label: String, value: String)] {
    let size = CGSize(width: width, height: 60 * CGFloat(entries.count) + 32)
    let columns = LeaderboardRowColumns.rankings(entries, metric: .totalscore)
    let rows = VStack(spacing: 6) {
        ForEach(entries) { entry in
            AccountRankingRow(
                entry: entry, metric: .totalscore,
                isSelected: entry.accountId == selectedAccount, glassSurface: true
            )
        }
    }
    .padding(.horizontal, rowPadding)
    let host = nativeHostedView(
        NavigationStack {
            Group {
                if fitsSongs {
                    rows.leaderboardSectionColumns(
                        columns, hidingCrowdedSongsFor: rowNames(entries), rowInset: declaredInset
                    )
                } else {
                    rows.leaderboardSectionColumns(columns)
                }
            }
            .frame(width: size.width)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(width: size.width, height: size.height)
        .background(BrandTokens.appBackground)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: entries.map { AccountRankingRow.displayName($0) })
    return accessibilityElements(host)
}

/// Spoken songs for a row (`RankingsCountText.spokenSongs`).
private func spokenSongs(_ entry: AccountRankingEntry) -> String {
    RankingsCountText.spokenSongs(entry.songsLabel(for: .totalscore))
}

/// The unselected rows' combined elements (the selected row speaks a custom label).
private func otherRows(
    _ entries: [AccountRankingEntry], in elements: [(label: String, value: String)]
) -> [(entry: AccountRankingEntry, label: String, value: String)] {
    entries.filter { $0.accountId != selectedAccount }.compactMap { entry in
        let name = AccountRankingRow.displayName(entry)
        return elements.first { $0.label.contains(name) }.map { (entry, $0.label, $0.value) }
    }
}

/// Measure a view's ideal (fixed-size) width in a hosted window.
@MainActor
private func idealWidth<Content: View>(_ content: Content) async throws -> CGFloat {
    let box = WidthBox()
    let size = CGSize(width: 1_200, height: 120)
    let host = nativeHostedView(
        content
            .fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { box.value = $0 }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    _ = try await nativeHostedSettle(host) { box.value > 0 }
    return box.value
}

// MARK: - Tests

/// Portrait-phone-narrow card: songs played/total leave every row at once, and
/// VoiceOver still reads them as the row's value (issue #38).
@MainActor
@Test func crowdedCardHidesSongsOnEveryRowButKeepsThemSpoken() async throws {
    let entries = try competeRows()
    let elements = try await hostedCard(entries, width: 300)
    let rows = otherRows(entries, in: elements)
    #expect(rows.count == 2, "\(elements)")
    for row in rows {
        #expect(!row.label.contains(spokenSongs(row.entry)), "\(row.label)")
        #expect(row.value == spokenSongs(row.entry), "\(row.value)")
    }
    // The same card without the fit keeps songs on screen (the #37 behaviour).
    let control = otherRows(entries, in: try await hostedCard(entries, width: 300, fitsSongs: false))
    #expect(control.count == 2 && control.allSatisfy { $0.label.contains(spokenSongs($0.entry)) })
}

/// A roomy card keeps songs on every row.
@MainActor
@Test func roomyCardKeepsSongs() async throws {
    let entries = try competeRows()
    let rows = otherRows(entries, in: try await hostedCard(entries, width: 700))
    #expect(rows.count == 2)
    for row in rows {
        #expect(row.label.contains(spokenSongs(row.entry)), "\(row.label)")
        #expect(row.value.isEmpty, "\(row.value)")
    }
}

/// The hidden template row is exactly as wide as the real row of the section's
/// longest (bold) name at its ideal size, i.e. the narrowest width at which no name
/// truncates with songs shown, so the fit never keeps songs at the cost of a name.
@MainActor
@Test func probeMatchesTheWidestRealRow() async throws {
    let entries = try competeRows()
    var columns = LeaderboardRowColumns.rankings(entries, metric: .totalscore)
    columns.showsSongs = true
    var widest: CGFloat = 0
    for entry in entries {
        let songs = entry.songsLabel(for: .totalscore)
        let row = RankingRowLayout(
            rank: entry.rank(for: .totalscore), name: AccountRankingRow.displayName(entry),
            songs: songs, spokenSongs: RankingsCountText.spokenSongs(songs),
            rating: RankingFormatting.rating(entry.ratingValue(for: .totalscore), metric: .totalscore),
            bayesian: nil, emphasized: entry.accountId == selectedAccount, showsChevron: true
        )
        widest = max(widest, try await idealWidth(row.leaderboardSectionColumns(columns)))
    }
    let probe = try await idealWidth(RankingRowWidthProbe(columns: columns, names: rowNames(entries)))
    #expect(widest > 0)
    #expect(abs(probe - widest) < 0.5, "probe \(probe) vs widest row \(widest)")
}

/// Across a sweep of card widths the whole card flips at one width (the probe's),
/// showing songs above it and hiding them below.
@MainActor
@Test func songsFollowTheMeasuredCardWidth() async throws {
    let entries = try competeRows()
    let columns = LeaderboardRowColumns.rankings(entries, metric: .totalscore)
    let required = try await idealWidth(RankingRowWidthProbe(columns: columns, names: rowNames(entries)))
    var outcomes = Set<Bool>()
    for width in [required - 12, required - 1, required + 1, required + 12] {
        let rows = otherRows(entries, in: try await hostedCard(entries, width: width))
        let shown = rows.map { $0.label.contains(spokenSongs($0.entry)) }
        #expect(rows.count == 2 && Set(shown).count == 1, "width \(width): \(shown)")
        #expect(shown.first == (width >= required), "width \(width) vs required \(required)")
        shown.first.map { outcomes.insert($0) }
    }
    #expect(outcomes == [true, false])
}
/// `/duo` J2: a page that pads its rows (Full Rankings, 16 pt per side) declares the
/// padding, so a section whose padded rows are too narrow hides songs even though
/// the section itself would fit the widest row.
@MainActor
@Test func paddedRowsDeclareTheirInset() async throws {
    let entries = try competeRows()
    let columns = LeaderboardRowColumns.rankings(entries, metric: .totalscore)
    let required = try await idealWidth(RankingRowWidthProbe(columns: columns, names: rowNames(entries)))
    let width = required + 20  // rows get required - 12 after 16 pt per side
    let declared = otherRows(entries, in: try await hostedCard(
        entries, width: width, rowPadding: 16, declaredInset: 32
    ))
    #expect(declared.count == 2 && declared.allSatisfy { !$0.label.contains(spokenSongs($0.entry)) })
    let undeclared = otherRows(entries, in: try await hostedCard(entries, width: width, rowPadding: 16))
    #expect(undeclared.count == 2 && undeclared.allSatisfy { $0.label.contains(spokenSongs($0.entry)) })
}
#endif
