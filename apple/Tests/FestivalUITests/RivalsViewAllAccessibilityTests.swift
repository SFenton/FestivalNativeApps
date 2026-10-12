#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - View All Rivals accessibility (issue #41, backfilled by #412)

/// #41 replaced the Rivals cards' plain "View All Rivals" row with the shared purple
/// button "View Full Leaderboard" draws (``RivalsViewAllButton`` → ``PurpleActionLink``).
/// These hosted checks pin that the two buttons also match for VoiceOver, Voice Control
/// and large text, on the page that shows both (Compete; the Rivals hub and the Duo
/// Compete pane draw the same ``RivalInstrumentSongCard``). Each is one button, named
/// label first and then its card (view-all-cta R4), read after its card's heading and
/// rows. Each is a full-width target at least 44 pt tall, with the same size and inset as
/// the other (R1, R3), and keeps all of that at the largest accessibility size. macOS
/// has no Dynamic Type, so `RivalsViewAllAccessibilityJourneyTests` is the iPhone AX5
/// text-growth and audit evidence.
///
/// HIG Accessibility: "Strive for the platform's recommended minimum control size"
/// (iOS 44×44 pt) and "Describe the interface and content for VoiceOver"; HIG Buttons:
/// "the hit region is at least 44x44 pt".
@MainActor
@Suite(.serialized)
struct RivalsViewAllAccessibilityTests {
    // MARK: - Fixture

    static let viewAllRivals = "fst.rivals.song.\(Instrument.lead.rawValue).view-all"
    static let viewFullLeaderboard = "fst.compete.leaderboard-card.\(Instrument.lead.rawValue).view-all"
    /// Accessible names: the visible label first, then the card (WCAG 2.5.3).
    static let rivalsName = "View All Rivals, Lead Rivals"
    static let leaderboardName = "View Full Leaderboard, Lead"

    /// Checked-in fixture under `contracts/fixtures`.
    static func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/\(name)"))
    }

    /// Three rivals ahead, three behind (`rivals-list-demo.json`).
    static func rivals() throws -> RivalsListResponse {
        try JSONDecoder().decode(RivalsListResponse.self, from: fixture("rivals-list-demo.json"))
    }

    /// Lead's top three (`rankings-demo.json`).
    static func rankings() throws -> RankingsPayload {
        let response = try JSONDecoder().decode(RankingsResponse.self, from: fixture("rankings-demo.json"))
        return RankingsPayload(page: 1, rankings: response, publicationId: 1, observedPublicationId: 1, isStale: false)
    }

    /// One hosted Compete-style column.
    struct Hosted {
        let host: NSView
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }
    }

    static let size = CGSize(width: 402, height: 1500)

    /// Host Compete's Lead leaderboard card above its Lead rivals card on a phone-width
    /// page at a Dynamic Type size, and wait for both buttons.
    ///
    /// - Parameter typeSize: Dynamic Type size for the whole page.
    /// - Returns: The settled host, its window and storage.
    /// - Throws: A missing fixture or an unsettled page.
    static func hostCards(_ typeSize: DynamicTypeSize) async throws -> Hosted {
        let rivals = try rivals()
        let rankings = try rankings()
        let suiteName = "fst-rivals-view-all-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        // No client and no selected player: the cards render from their states only.
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            CompeteInstrumentLeaderboardSection(
                                session: session, instrument: .lead, state: .loaded(rankings), retry: {}
                            )
                            RivalInstrumentSongCard(
                                instrument: .lead, state: .loaded(rivals), registersQuickLink: false, retry: {}
                            )
                        }
                        .padding(.vertical, 16)
                    }
                }
                .frame(width: size.width, height: size.height)
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            [viewAllRivals, viewFullLeaderboard].allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
        }
        return Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
    }

    /// The element carrying an identifier in a tree walk.
    static func node(_ id: String, in nodes: [MacAXNode]) throws -> MacAXNode {
        try #require(
            nodes.first { $0.identifier == id && $0.isElement },
            "\(id) in\n\(nodes.map(\.description).joined(separator: "\n"))"
        )
    }

    /// Both buttons are one Button each, named label first and then their card.
    static func expectNamesAndRoles(_ nodes: [MacAXNode]) throws {
        let rivals = try node(viewAllRivals, in: nodes)
        let leaderboard = try node(viewFullLeaderboard, in: nodes)
        #expect(rivals.role == "AXButton", "View All Rivals is a button: \(rivals)")
        #expect(rivals.role == leaderboard.role, "same role as View Full Leaderboard: \(rivals) vs \(leaderboard)")
        #expect(rivals.spokenName == rivalsName, "\(rivals)")
        #expect(leaderboard.spokenName == leaderboardName, "\(leaderboard)")
        #expect(!rivals.selected, "a push button has no selected state: \(rivals)")
        // The label is read once, through the button, not again as loose text.
        let elements = nodes.filter(\.isElement)
        #expect(elements.filter { $0.spokenName.contains("View All Rivals") }.count == 1,
                "one element reads View All Rivals")
        #expect(elements.filter { $0.spokenName.contains("View Full Leaderboard") }.count == 1,
                "one element reads View Full Leaderboard")
    }

    /// Visual reading order: each card's heading, its rows, then its button.
    static func expectReadingOrder(_ host: NSView) throws {
        let rivals = try Self.rivals()
        let rankings = try Self.rankings()
        let order = macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
        func index(_ match: (MacAXNode) -> Bool, _ what: String) throws -> Int {
            let found = order.firstIndex(where: match)
            return try #require(found, "\(what) in the reading order:\n\(order.map(\.description).joined(separator: "\n"))")
        }
        var sequence = [try index({ $0.spokenName == "Lead" }, "Lead heading")]
        for entry in rankings.rankings.entries {
            sequence.append(try index({ $0.identifier == "fst.rankings.row.\(entry.id)" }, entry.accountId))
        }
        sequence.append(try index({ $0.identifier == viewFullLeaderboard }, "View Full Leaderboard"))
        sequence.append(try index({ $0.spokenName == "Lead Rivals" }, "Lead Rivals heading"))
        for rival in Array(rivals.above.prefix(3)) + Array(rivals.below.prefix(3)) {
            sequence.append(try index({ $0.identifier == "fst.rivals.row.\(rival.accountId)" }, rival.accountId))
        }
        sequence.append(try index({ $0.identifier == viewAllRivals }, "View All Rivals"))
        #expect(sequence == sequence.sorted() && Set(sequence).count == sequence.count,
                "heading, rows, then the button, card by card: \(sequence)")
    }

    /// Both buttons are the same full-width target, at least 44 pt tall, below their rows.
    static func expectMatchingTargets(_ host: NSView) throws {
        let rivals = try Self.rivals()
        let button = try #require(nativeHostedAccessibilityFrame(viewAllRivals, in: host))
        let reference = try #require(nativeHostedAccessibilityFrame(viewFullLeaderboard, in: host))
        #expect(button.height >= 44 - 0.5, "View All Rivals is at least 44 pt tall: \(button)")
        // The page's 16 pt margins and the card's action inset on each side.
        let cardWidth = size.width - 32 - 2 * FestivalGlassSection<EmptyView, EmptyView>.actionInset
        #expect(button.width >= cardWidth - 1, "View All Rivals spans its card: \(button)")
        #expect(abs(button.height - reference.height) <= 0.5, "same height as View Full Leaderboard: \(button) vs \(reference)")
        #expect(abs(button.width - reference.width) <= 0.5, "same width as View Full Leaderboard: \(button) vs \(reference)")
        #expect(abs(button.minX - reference.minX) <= 0.5, "same inset as View Full Leaderboard: \(button) vs \(reference)")
        #expect(button.minY >= reference.maxY, "the rivals card follows the leaderboard card")
        let lastRow = try #require(rivals.below.prefix(3).last)
        let row = try #require(nativeHostedAccessibilityFrame("fst.rivals.row.\(lastRow.accountId)", in: host))
        #expect(button.minY >= row.maxY - 0.5, "View All Rivals ends the card below its last row: \(button) under \(row)")
    }

    // MARK: - Names, roles and state

    /// View All Rivals is one button named "View All Rivals, Lead Rivals", exposed the
    /// way View Full Leaderboard is ("View Full Leaderboard, Lead").
    @Test func viewAllRivalsIsNamedLikeViewFullLeaderboard() async throws {
        let hosted = try await Self.hostCards(.large)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "rivals-view-all-large")
        try Self.expectNamesAndRoles(nodes)
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Reading order and target size

    /// Each card reads heading, rows, then its button, and View All Rivals is the same
    /// full-width 44 pt target View Full Leaderboard is.
    @Test func viewAllRivalsReadsLastAndMatchesViewFullLeaderboardTarget() async throws {
        let hosted = try await Self.hostCards(.large)
        defer { hosted.close() }
        try Self.expectReadingOrder(hosted.host)
        try Self.expectMatchingTargets(hosted.host)
    }

    // MARK: - Text scaling

    /// At the largest accessibility size both buttons keep their names, roles, reading
    /// position and matching full-width 44 pt targets.
    @Test func viewAllRivalsStaysReachableAtAccessibilitySizes() async throws {
        let hosted = try await Self.hostCards(.accessibility5)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "rivals-view-all-ax5")
        try Self.expectNamesAndRoles(nodes)
        try Self.expectReadingOrder(hosted.host)
        try Self.expectMatchingTargets(hosted.host)
        #expect(macAccessibilityFindings(nodes) == [])
    }
}
#endif
