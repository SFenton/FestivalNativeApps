#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Compete combo boards (issue #602)

/// The web's Compete shows each instrument family's within-group combo board ("Lead +
/// Bass") before its single instruments, each with its own View Full Leaderboard and a
/// combo rivals card (`resolveSupportedRankingScopes`). Apple showed instrument cards only.
/// These hosted checks run the real Compete page against the loopback fixture and pin:
///
/// - the combo leaderboard card comes first, titled by a heading "Lead + Bass" (its icons
///   are decorative), and reads heading, rows, then its button, before the Lead card;
/// - its View Full Leaderboard is the shared purple button: one `AXButton` named "View
///   Full Leaderboard, Lead + Bass" (view-all-cta R4), a full-width target at least 44 pt
///   tall matching the instrument card's (R1, R3), and it opens the combo's full board;
/// - the combo rivals card ("Lead + Bass Rivals") has View All Rivals for the combo.
///
/// HIG Accessibility: "Strive for the platform's recommended minimum control size"
/// (iOS 44×44 pt); HIG Buttons: "the hit region is at least 44x44 pt".
@MainActor
@Suite(.serialized)
struct CompeteComboBoardTests {
    static let combo = RankingCombo(instruments: [.lead, .bass])!
    static let comboCard = "fst.compete.leaderboard-card.03"
    static let comboViewAll = "fst.compete.leaderboard-card.03.view-all"
    static let leadViewAll = "fst.compete.leaderboard-card.\(Instrument.lead.rawValue).view-all"
    static let comboRivalsViewAll = "fst.rivals.combo.03.view-all"
    static let size = CGSize(width: 402, height: 3200)

    static let instrumentKeys = [
        "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
        "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
        "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
    ]

    /// A session on the loopback fixture with the fixture viewer selected and only Lead
    /// and Bass visible; `close` removes its defaults suite.
    static func fixtureSession() async throws -> (FestivalSession, UserDefaults, close: () -> Void) {
        let baseURL = try await RivalsMockService.shared.baseURL()
        let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
        let suite = "fst.tests.compete-combo.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suite))
        let identity: [String: String] = ["accountId": "fixture-riv", "displayName": "Fixture Viewer"]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        for key in instrumentKeys {
            storage.set(key == "fst.settings.showLead" || key == "fst.settings.showBass", forKey: key)
        }
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        return (session, storage, { storage.removePersistentDomain(forName: suite) })
    }

    /// Host Compete with Lead and Bass visible against the loopback fixture and wait until
    /// both leaderboard buttons and the combo rivals button exist.
    static func hostCompete() async throws -> (host: NSView, image: CGImage, close: () -> Void) {
        let (session, storage, removeStorage) = try await fixtureSession()
        let host = nativeHostedView(
            NavigationStack { CompeteScreen(session: session) }
                .environment(\.horizontalSizeClass, .compact)
                .defaultAppStorage(storage)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let image = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            [comboViewAll, leadViewAll, comboRivalsViewAll].allSatisfy {
                nativeHostedAccessibilityFrame($0, in: host) != nil
            }
        }
        return (host, image, {
            window.orderOut(nil)
            removeStorage()
        })
    }

    static func node(_ id: String, in nodes: [MacAXNode]) throws -> MacAXNode {
        try #require(
            nodes.first { $0.identifier == id && $0.isElement },
            "\(id) in\n\(nodes.map(\.description).joined(separator: "\n"))"
        )
    }

    /// The combo card is titled "Lead + Bass" and its View Full Leaderboard is one button
    /// named for its card, the same 44 pt full-width target as the Lead card's.
    @Test func comboCardHasItsOwnViewFullLeaderboard() async throws {
        let (host, image, close) = try await Self.hostCompete()
        defer { close() }
        _ = try nativeHostedPNG(image, filename: "compete-combo-card.png", environment: "FST_COMPETE_RENDER_OUT")
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "compete-combo-card")

        let heading = try #require(nodes.first { $0.isElement && $0.spokenName == "Lead + Bass" }, "combo heading")
        #expect(heading.role == "AXHeading", "the combo's label is a heading: \(heading)")
        let rivalsHeading = try #require(nodes.first { $0.isElement && $0.spokenName == "Lead + Bass Rivals" })
        #expect(rivalsHeading.role == "AXHeading", "\(rivalsHeading)")

        let button = try Self.node(Self.comboViewAll, in: nodes)
        #expect(button.role == "AXButton", "\(button)")
        #expect(button.spokenName == "View Full Leaderboard, Lead + Bass", "\(button)")
        let rivals = try Self.node(Self.comboRivalsViewAll, in: nodes)
        #expect(rivals.spokenName == "View All Rivals, Lead + Bass Rivals", "\(rivals)")

        let combo = try #require(nativeHostedAccessibilityFrame(Self.comboViewAll, in: host))
        let lead = try #require(nativeHostedAccessibilityFrame(Self.leadViewAll, in: host))
        #expect(combo.height >= 44 - 0.5, "at least 44 pt tall: \(combo)")
        #expect(abs(combo.width - lead.width) <= 0.5 && abs(combo.minX - lead.minX) <= 0.5,
                "the same full-width target as Lead's: \(combo) vs \(lead)")
        #expect(abs(combo.height - lead.height) <= 0.5, "same height as Lead's: \(combo) vs \(lead)")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// Reading order follows the web: the combo card (heading, rows, button) before the
    /// Lead and Bass cards, and the combo rivals card before Lead's.
    @Test func comboCardsReadBeforeTheirInstruments() async throws {
        let (host, _, close) = try await Self.hostCompete()
        defer { close() }
        let order = macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
        func index(_ match: (MacAXNode) -> Bool, _ what: String) throws -> Int {
            let found = order.firstIndex(where: match)
            return try #require(found, "\(what) in:\n\(order.map(\.description).joined(separator: "\n"))")
        }
        let sequence = [
            try index({ $0.spokenName == "Lead + Bass" }, "combo heading"),
            try index({ $0.identifier == "fst.rankings.row.fixture-player-1" }, "combo row"),
            try index({ $0.identifier == Self.comboViewAll }, "combo View Full Leaderboard"),
            try index({ $0.spokenName == "Lead" && $0.role == "AXHeading" }, "Lead heading"),
            try index({ $0.identifier == Self.leadViewAll }, "Lead View Full Leaderboard"),
            try index({ $0.spokenName == "Bass" && $0.role == "AXHeading" }, "Bass heading"),
            try index({ $0.spokenName == "Lead + Bass Rivals" }, "combo rivals heading"),
            try index({ $0.identifier == Self.comboRivalsViewAll }, "combo View All Rivals"),
            try index({ $0.spokenName == "Lead Rivals" }, "Lead rivals heading"),
        ]
        #expect(sequence == sequence.sorted() && Set(sequence).count == sequence.count, "\(sequence)")
    }

    /// View Full Leaderboard's destination: the combo's full board (web `FullRankingsPage`
    /// `?combo=`) titled by one heading "Lead + Bass Rankings" over the combo's rows, with
    /// no instrument switcher (a combo has no instrument to switch to).
    @Test func comboFullRankingsShowsTheComboBoard() async throws {
        let (session, storage, removeStorage) = try await Self.fixtureSession()
        defer { removeStorage() }
        let size = CGSize(width: 402, height: 900)
        let host = nativeHostedView(
            NavigationStack { FullRankingsScreen(session: session, combo: Self.combo, rankBy: "totalscore") }
                .defaultAppStorage(storage)
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityFrame("fst.rankings.row.fixture-player-1", in: host) != nil
        }
        _ = try nativeHostedPNG(image, filename: "full-combo-rankings.png", environment: "FST_COMPETE_RENDER_OUT")
        let nodes = macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
        let title = try Self.node("fst.full-rankings.title", in: nodes)
        #expect(title.role == "AXHeading" && title.spokenName.hasPrefix("Lead + Bass Rankings"), "\(title)")
        #expect(!nodes.contains { $0.identifier == "fst.full-rankings.instrument-menu" }, "no instrument switcher")
        let titleIndex = try #require(nodes.firstIndex { $0.identifier == "fst.full-rankings.title" })
        let rowIndex = try #require(nodes.firstIndex { $0.identifier == "fst.rankings.row.fixture-player-1" })
        #expect(titleIndex < rowIndex, "the heading reads before the rows")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// The combo card's buttons open the combo's boards: View Full Leaderboard the combo's
    /// full rankings, the player's own row their page on it, View All Rivals the combo
    /// rivals (web `Routes.fullComboRankings`, `Routes.allRivals(comboId)`).
    @Test func comboRoutesOpenTheCombosBoards() throws {
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let card = CompeteInstrumentLeaderboardSection(
            session: session, scope: .combo(Self.combo), state: .loading, retry: {}
        )
        #expect(card.fullBoardRoute == .fullComboRankings(combo: Self.combo, rankBy: "totalscore"))
        let single = CompeteInstrumentLeaderboardSection(
            session: session, instrument: .drums, state: .loading, retry: {}
        )
        #expect(single.fullBoardRoute == .fullRankings(instrument: .drums, rankBy: "totalscore"))

        let body: [String: Any] = [
            "accountId": "fixture-riv", "displayName": "Fixture Viewer", "songsPlayed": 40,
            "totalChartedSongs": 50, "coverage": 0.8, "rawSkillRating": 0.02, "adjustedSkillRating": 0.02,
            "adjustedSkillRank": 45, "weightedRating": 0.03, "weightedRank": 45, "fcRate": 0.5,
            "fcRateRank": 45, "totalScore": 1000, "totalScoreRank": 45, "maxScorePercent": 0.9,
            "maxScorePercentRank": 45, "avgAccuracy": 0.9, "fullComboCount": 2, "avgStars": 4.5,
            "bestRank": 1, "avgRank": 2.5,
        ]
        let entry = try JSONDecoder().decode(
            AccountRankingEntry.self, from: JSONSerialization.data(withJSONObject: body)
        )
        #expect(CompetePreviewSpotlight.route(for: entry, scope: .combo(Self.combo))
            == .fullComboRankings(combo: Self.combo, rankBy: "totalscore", page: 2, focusSelected: true))
    }
}
#endif
