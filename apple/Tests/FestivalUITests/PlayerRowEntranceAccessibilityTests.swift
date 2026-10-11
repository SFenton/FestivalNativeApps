#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Player row entrance accessibility (issue #295, backfilled by #457)

// #295: on a song's board the selected player's own (purple) row faded in after the
// other rows, because they drew per-row Liquid Glass and skipped their stagger. Since
// then every row sits on the shared material surface (`RankingRowSurface`) and, as
// segments of the page's group card (#543), fades in with that card (#614). These hosted
// checks (macOS host, the same SwiftUI on iPhone, iPad, iPhone Duo and Mac) pin what the
// player's row exposes through that entrance: it joins the tree together with the rows
// around it (never late, never before them), in rank order, as a full 48 pt row of the
// card; Reduce Motion (system or in-app) shows it at once; AX5 text keeps it whole; and
// it says it is the player's own, not only through its purple fill and bold text.

/// Accessibility of the selected player's own row on a song board.
///
/// HIG Accessibility: "Don't rely solely on color to differentiate between objects or
/// communicate important information"; "When Reduce Motion is on, reduce automatic and
/// repetitive animation"; targets at least 44×44 pt. HIG VoiceOver: "Provide alternative
/// labels for all key interface elements".
@MainActor
@Suite(.serialized)
struct PlayerRowEntranceAccessibilityTests {
    typealias Board = BoardCardEntranceAccessibilityTests
    typealias Motion = ReloadGateAccessibilityTests.Motion

    /// The selected player's rank on the fixture page.
    static let playerRank = 3
    static let rowPrefix = "fst.song-leaderboard.row."
    static let playerRow = rowPrefix + "fixture-spotlight-player"

    /// The first `count` rows of the page in rank order, the player's at ``playerRank``.
    static func rowIDs(_ count: Int) -> [String] {
        (1...count).map { $0 == playerRank ? playerRow : rowPrefix + "fixture-other-\($0)" }
    }

    /// What VoiceOver speaks for a row: its own name, else its first named descendant's
    /// (the row is a `.contain` container around its button).
    ///
    /// - Parameters:
    ///   - identifier: The row's identifier.
    ///   - nodes: The tree in navigation order.
    /// - Returns: The spoken text, or nil when the row is not realized.
    static func spoken(_ identifier: String, in nodes: [MacAXNode]) -> String? {
        guard let start = nodes.firstIndex(where: { $0.identifier == identifier }) else { return nil }
        let row = nodes[start]
        if !row.spokenName.isEmpty { return row.spokenName }
        for node in nodes[(start + 1)...] {
            if node.depth <= row.depth { break }
            if node.isElement, !node.spokenName.isEmpty { return node.spokenName }
        }
        return ""
    }

    // MARK: Song board entrance

    /// The player's row arrives with the rows around it, reads in rank order as a whole
    /// row of the card and is named as the player's own; under Reduce Motion (system or
    /// in-app) it is there from the start.
    @Test(arguments: [
        (Motion.animated, DynamicTypeSize.large),
        (Motion.animated, DynamicTypeSize.accessibility5),
        (Motion.systemReduceMotion, DynamicTypeSize.large),
        (Motion.appReduceMotion, DynamicTypeSize.large),
    ])
    func playerRowArrivesWithTheOtherRows(_ motion: Motion, _ typeSize: DynamicTypeSize) async throws {
        let suiteName = "fst-player-row-entrance-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let (host, window) = try await Board.hostSoloBoard(
            typeSize: typeSize, motion: motion, storage: storage, spotlightRank: Self.playerRank
        )
        defer { window.orderOut(nil) }

        let firstScreen = typeSize.isAccessibilitySize ? 3 : 6
        let ids = Self.rowIDs(firstScreen)
        let arrivals = try await Board.recordArrivals(host, prefix: Self.rowPrefix, expected: firstScreen)
        let spread = try #require(arrivals.spread(ids), "rows \(ids) all arrive: \(arrivals.firstSeen)")
        let player = try #require(arrivals.firstSeen[Self.playerRow], "the player's row arrives")
        let others = ids.filter { $0 != Self.playerRow }.compactMap { arrivals.firstSeen[$0] }
        switch motion {
        case .animated:
            #expect(arrivals.initial.isEmpty, "\(typeSize): no row is reachable before the card fades in: \(arrivals.initial)")
            // The #295 symptom: the player's row arriving a stagger slot or more after
            // the rows around it.
            #expect(player - (others.min() ?? player) < FestivalFadeIn.staggerInterval,
                    "\(typeSize): the player's row arrives with the others, not after: \(arrivals.firstSeen)")
            #expect(spread < FestivalFadeIn.staggerInterval,
                    "\(typeSize): the card's rows arrive together: \(arrivals.firstSeen)")
        case .systemReduceMotion, .appReduceMotion, .instant:
            #expect(Set(ids).isSubset(of: arrivals.initial),
                    "\(motion): the player's row and the others show at once: \(arrivals.initial)")
        }

        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) { boardRowsAbut(ids, in: host) }
        let order = Board.rows(host, prefix: Self.rowPrefix)
        #expect(Array(order.prefix(ids.count)) == ids, "\(motion) \(typeSize): the player's row reads in rank order: \(order)")
        // A whole 48 pt row of the one card, as wide as the rows around it.
        try expectBoardRowsInOneCard(ids, in: host)

        let nodes = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "player-row-entrance-\(motion.rawValue)-\(typeSize)")
        let spokenPlayer = try #require(Self.spoken(Self.playerRow, in: nodes), "the player's row is in the tree")
        #expect(spokenPlayer.contains("Your rank, 3rd"),
                "\(motion) \(typeSize): the player's row says it is theirs, not only by colour: '\(spokenPlayer)'")
        #expect(spokenPlayer.contains("Row 3"), "\(motion) \(typeSize): and keeps their name: '\(spokenPlayer)'")
        for id in ids where id != Self.playerRow {
            let other = try #require(Self.spoken(id, in: nodes), "\(id) is in the tree")
            #expect(!other.contains("Your rank"), "\(id) is not the player's: '\(other)'")
        }
    }

    // MARK: Shared row

    /// The rank label: the player's own row says "Your rank" with the ordinal; other rows
    /// keep the drawn "#N".
    @Test func spokenRankNamesOnlyThePlayersOwnRow() {
        #expect(SongLeaderboardEntryRow.spokenRank(3, isPlayer: true) == "Your rank, 3rd")
        #expect(SongLeaderboardEntryRow.spokenRank(1_234, isPlayer: true) == "Your rank, \(RankingFormatting.ordinal(1_234))")
        #expect(SongLeaderboardEntryRow.spokenRank(3, isPlayer: false) == "#3")
        #expect(SongLeaderboardEntryRow.spokenRank(1_234, isPlayer: false) == "#\(1_234.formatted())")
    }

    /// The shared score row (``SongLeaderboardRowCard``: Song Detail's preview rows, the
    /// song boards and their pinned footers) names the player's own row as theirs as one
    /// button, at the default and the largest text size, and leaves other rows as drawn.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func sharedScoreRowNamesThePlayersOwnRow(_ typeSize: DynamicTypeSize) async throws {
        nativeHostedEnableAccessibility()
        let payload = try spotlightFixtureLeaderboard(spotlightRank: Self.playerRank)
        let entries = Array(payload.leaderboard.entries.prefix(4))
        let size = CGSize(width: 402, height: 900)
        let host = nativeHostedView(
            AnyView(
                VStack(spacing: 0) {
                    ForEach(entries) { entry in
                        Button {} label: {
                            SongLeaderboardRowCard(
                                entry: entry, isPlayer: entry.rank == Self.playerRank, currentSeason: nil
                            )
                            .contentShape(Rectangle())
                        }
                        .festivalRowButtonStyle()
                        .accessibilityIdentifier("fst.test.score-row.\(entry.rank)")
                    }
                }
                .padding(16)
                .frame(width: size.width, height: size.height, alignment: .top)
                .environment(\.dynamicTypeSize, typeSize)
                .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let ids = entries.map { "fst.test.score-row.\($0.rank)" }
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            ids.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
        }
        let nodes = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "player-score-row-\(typeSize)")
        for entry in entries {
            let id = "fst.test.score-row.\(entry.rank)"
            let row = try #require(nodes.first { $0.identifier == id && $0.isElement }, "\(id) is one element")
            #expect(row.role == "AXButton", "\(row)")
            if entry.rank == Self.playerRank {
                #expect(row.spokenName.contains("Your rank, 3rd") && row.spokenName.contains("Row 3"),
                        "\(typeSize): the player's row says it is theirs: \(row)")
            } else {
                #expect(row.spokenName.hasPrefix("#\(entry.rank)") || row.spokenName.hasPrefix("Row \(entry.rank)"),
                        "\(typeSize): other rows read as drawn: \(row)")
                #expect(!row.spokenName.contains("Your rank"), "\(row)")
            }
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: host))
            #expect(frame.height >= 44 - 0.5, "\(id) is a 44 pt target: \(frame)")
        }
    }
}
#endif
