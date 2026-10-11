#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Compete Leaderboards without an overview link (issue #36, backfilled by #408)

/// #36 removed Compete's "Leaderboards Overview" row under the Leaderboards heading
/// (`CompeteScreen`) and, on the iPhone Duo inner display, the Leaderboards pane's
/// Overview card and header View All link (`CompeteLeaderboardsCarousel`), matching the
/// web `CompetePage`: each board's View Full Leaderboard opens that board.
///
/// These hosted checks (macOS host, `apple-ci`) pin that region for VoiceOver, Voice
/// Control and Dynamic Type on the stacked page (iPhone, iPad and Mac share it) and on the
/// Duo inner display's Leaderboards pane: the Leaderboards heading leads straight into the
/// first board's heading; no Overview element and no Leaderboards View All link is
/// reachable; the section's only buttons are ranking rows and one "View Full Leaderboard,
/// <board>" button per board (the Lead + Bass combo, #602, then each instrument), each a
/// 44 × 44 pt target that ends its card; and, on Duo, the Rivals pane keeps its own View
/// All link, so the missing Leaderboards link is #36's removal, not a broken pane header.
/// The largest accessibility size changes none of it. macOS keeps the font size, so the AX5 cases pin the tree only; the iPhone journey
/// `CompeteAccessibilityJourneyTests` proves AX5 text growth and fails on any extra button
/// in the section. `CompeteLoadingAccessibilityTests` pins the spinner before this state.
///
/// HIG Accessibility: "Describe the interface and content for VoiceOver" and "Strive for
/// the platform's recommended minimum control size" (iOS/iPadOS 44 × 44 pt); HIG VoiceOver:
/// "Specify how elements are grouped, ordered or linked".
@MainActor
@Suite(.serialized)
struct CompeteLeaderboardsAccessibilityTests {
    /// Where Compete draws its Leaderboards.
    enum Layout: String, CaseIterable, CustomTestStringConvertible {
        /// The stacked page: iPhone, and the shared column iPad and Mac draw.
        case stacked
        /// iPhone Duo inner display, portrait and half open: the Leaderboards pane above
        /// the fold, the Rivals pane below.
        case duo

        var testDescription: String { rawValue }

        /// The injected device layout, or nil for the host's own.
        var deviceLayout: DeviceLayout? {
            switch self {
            case .stacked:
                nil
            case .duo:
                DeviceLayout.resolve(LayoutSignals(
                    size: CGSize(width: 669, height: 951), widthClass: .regular,
                    hinge: .partiallyOpen, divisions: [CGRect(x: 0, y: 463, width: 669, height: 25)]
                ), dualSource: true)
            }
        }

        /// The window's size.
        var size: CGSize {
            switch self {
            case .stacked: CGSize(width: 402, height: 1400)
            case .duo: CGSize(width: 669, height: 951)
            }
        }
    }

    typealias Page = CompeteLoadingAccessibilityTests

    /// The Duo panes' header View All links (`DualSourcePane`).
    static let leaderboardsViewAll = "fst.dual.compete.leaderboards.view-all"
    static let rivalsViewAll = "fst.dual.compete.rivals.view-all"

    /// Host Compete with every read answered and wait until both boards and the Rivals
    /// heading are in the tree.
    ///
    /// - Parameters:
    ///   - layout: Stacked page or Duo panes.
    ///   - typeSize: Dynamic Type size for the page.
    /// - Returns: The settled host.
    static func hostLoaded(_ layout: Layout, _ typeSize: DynamicTypeSize) async throws -> Page.Hosted {
        let hosted = try await Page.host(.pass, typeSize: typeSize, layout: layout.deviceLayout, size: layout.size)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            let tree = macAccessibilityTree(hosted.host)
            return !tree.contains { $0.identifier == Page.spinnerID }
                && Page.boards.allSatisfy { board in
                    tree.contains { $0.spokenName == "View Full Leaderboard, \(board.name)" }
                }
                && tree.contains { $0.role == "AXHeading" && $0.spokenName == "Rivals" }
        }
        return hosted
    }

    // MARK: - Reading order, names and targets

    /// The Leaderboards heading leads straight into Lead's heading; nothing reads as an
    /// overview or a Leaderboards View All; between the Leaderboards and Rivals headings
    /// the only buttons are ranking rows and each board's View Full Leaderboard, a
    /// named 44 × 44 pt button that ends its card. On Duo the Rivals pane keeps its View All.
    @Test(arguments: Layout.allCases, [DynamicTypeSize.large, .accessibility5])
    func leaderboardsHeadingLeadsStraightIntoTheBoards(_ layout: Layout, _ typeSize: DynamicTypeSize) async throws {
        let context = "\(layout), \(typeSize)"
        let hosted = try await Self.hostLoaded(layout, typeSize)
        defer { hosted.close() }
        let loaded = Page.content(hosted)
        let dump = Page.dump(loaded)
        macAccessibilityDump(loaded, name: "compete-leaderboards-\(layout)-\(typeSize)")

        let heading = try #require(loaded.firstIndex { $0.role == "AXHeading" && $0.spokenName == "Leaderboards" },
                                   "\(context): the Leaderboards heading:\n\(dump)")
        let rivals = try #require(loaded.firstIndex { $0.role == "AXHeading" && $0.spokenName == "Rivals" },
                                  "\(context): the Rivals heading:\n\(dump)")
        #expect(heading < rivals, "\(context): Leaderboards reads before Rivals:\n\(dump)")
        let first = try #require(Page.boards.first?.name)
        #expect(heading + 1 < loaded.count && loaded[heading + 1].role == "AXHeading"
                && loaded[heading + 1].spokenName == first,
                "\(context): nothing between the Leaderboards heading and \(first)'s:\n\(dump)")

        #expect(!loaded.contains { $0.spokenName.localizedCaseInsensitiveContains("overview") },
                "\(context): no Leaderboards Overview element:\n\(dump)")
        #expect(!loaded.contains { $0.identifier.localizedCaseInsensitiveContains("overview") },
                "\(context): no overview identifier:\n\(dump)")
        #expect(!loaded.contains { $0.identifier == Self.leaderboardsViewAll || $0.spokenName == "View All Leaderboards" },
                "\(context): no Leaderboards View All link:\n\(dump)")

        let section = loaded[(heading + 1)..<rivals]
        let buttons = section.filter { ["AXButton", "AXLink"].contains($0.role) }
        let strays = buttons.filter {
            !$0.identifier.hasPrefix("fst.rankings.row.") && !$0.spokenName.hasPrefix("View Full Leaderboard, ")
        }
        #expect(strays.isEmpty, "\(context): only rows and View Full Leaderboard act in Leaderboards:\n\(Page.dump(strays))")
        let viewFull = buttons.filter { $0.spokenName.hasPrefix("View Full Leaderboard, ") }.map(\.spokenName)
        #expect(viewFull == Page.boards.map { "View Full Leaderboard, \($0.name)" },
                "\(context): one View Full Leaderboard per board, in order:\n\(dump)")

        for (index, board) in Page.boards.enumerated() {
            let button = try #require(loaded.firstIndex { $0.spokenName == "View Full Leaderboard, \(board.name)" })
            #expect(loaded[button].role == "AXButton", "\(context): \(loaded[button])")
            #expect(button + 1 < loaded.count, "\(context): \(board.name)'s card is followed:\n\(dump)")
            guard button + 1 < loaded.count else { continue }
            let following = loaded[button + 1]
            if index + 1 < Page.boards.count {
                #expect(following.role == "AXHeading" && following.spokenName == Page.boards[index + 1].name,
                        "\(context): \(board.name)'s View Full Leaderboard ends its card:\n\(dump)")
            } else if layout == .duo {
                // The Leaderboards carousel's page indicator closes the pane (`HorizontalCarousel`).
                #expect(following.identifier == "fst.carousel.indicator" && following.spokenName == "Leaderboards"
                        && loaded[button + 2].role == "AXHeading" && loaded[button + 2].spokenName == "Rivals",
                        "\(context): the last card, the pane's page indicator, then Rivals:\n\(dump)")
            } else {
                #expect(following.role == "AXHeading" && following.spokenName == "Rivals",
                        "\(context): the last View Full Leaderboard ends the section:\n\(dump)")
            }
            let id = "fst.compete.leaderboard-card.\(board.id).view-all"
            if layout == .stacked {
                Page.expectTarget(hosted, id, context)
            } else {
                // A card on the carousel's next page lies past the window's edge until swiped.
                let frame = try #require(nativeHostedAccessibilityFrame(id, in: hosted.host), "\(context): \(id)")
                #expect(frame.width >= Page.minimumTarget - 0.5 && frame.height >= Page.minimumTarget - 0.5,
                        "\(context): \(id) is a 44×44 pt target: \(frame)")
            }
        }

        if layout == .duo {
            let rivalsLink = try #require(loaded.first { $0.identifier == Self.rivalsViewAll },
                                          "\(context): the Rivals pane keeps its View All:\n\(dump)")
            #expect(rivalsLink.spokenName == "View All Rivals", "\(context): \(rivalsLink)")
        }
        #expect(loaded.allSatisfy { !$0.spokenName.isEmpty }, "\(context): nothing unnamed:\n\(dump)")
        #expect(macAccessibilityFindings(hosted.tree()).isEmpty, "\(context)")
    }
}
#endif
