#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Rival row accessibility (issue #40, backfilled by #411)

/// The shared rival row (``RivalRowContent``) lost its trailing "N shared" count in #40.
/// These hosted checks pin what the row exposes to VoiceOver, Voice Control and Dynamic Type
/// on every Apple platform (the same SwiftUI draws it on iPhone, iPad, iPhone Duo and Mac, in
/// Rivals, All Rivals, Compete and the first-run demo). They cover one name and the button role
/// per row, with no "shared" count and no pill, dot or chevron read on its own. They also
/// cover reading order (the section heading, rivals ahead then behind, then View All Rivals),
/// a full-width row target at least 44 pt tall, and the accessibility-size restack: the pills
/// go from side by side to a column (#411). macOS hosting doesn't scale fonts, so
/// `RivalsAccessibilityJourneyTests` is the iPhone AX5 evidence.
///
/// HIG Accessibility: "Provide VoiceOver descriptions for all interface elements" and the
/// 44×44 pt default control size; HIG Typography: "Keep text truncation to a minimum as
/// font size increases".
@MainActor
@Suite(.serialized)
struct RivalRowAccessibilityTests {
    // MARK: - Fixture

    /// The checked-in live capture (`GET /api/player/{id}/rivals/Solo_Guitar`, anonymized):
    /// three rivals ahead (Golf, Echo, Alpha), three behind (Charlie, Bravo, Foxtrot).
    ///
    /// - Returns: The decoded list.
    /// - Throws: A missing or malformed fixture.
    static func response() throws -> RivalsListResponse {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let data = try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/rivals-list-demo.json"))
        return try JSONDecoder().decode(RivalsListResponse.self, from: data)
    }

    /// The preview rows in page order: up to three ahead, then up to three behind.
    static func rows(_ response: RivalsListResponse) -> [RivalSummary] {
        Array(response.above.prefix(3)) + Array(response.below.prefix(3))
    }

    /// What VoiceOver reads for a row: its name, then the two pills ("ahead" shows the
    /// rival's `behindCount`, as on the web), and never the shared-song count.
    static func spokenName(_ rival: RivalSummary) -> String {
        "\(rival.displayName ?? "Unknown Player"), \(rival.behindCount) songs ahead, \(rival.aheadCount) songs behind"
    }

    static func rowID(_ rival: RivalSummary) -> String { "fst.rivals.row.\(rival.accountId)" }

    /// One hosted Lead rivals card.
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

    /// Host the Lead rivals card (as Rivals and Compete draw it) on a phone-width page at a
    /// Dynamic Type size and wait for its six rows.
    ///
    /// - Parameter typeSize: Dynamic Type size for the whole page.
    /// - Returns: The settled host, its window and storage.
    /// - Throws: A missing fixture.
    static func hostCard(_ typeSize: DynamicTypeSize) async throws -> Hosted {
        let response = try response()
        let suiteName = "fst-rival-row-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let size = CGSize(width: 402, height: 1400)
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    ScrollView {
                        RivalInstrumentSongCard(instrument: .lead, state: .loaded(response)) {}
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
        let ids = rows(response).map(rowID)
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            ids.allSatisfy { nativeHostedAccessibilityFrame($0, in: host) != nil }
        }
        return Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
    }

    /// The row element (the link carrying the row's identifier) in a tree walk.
    static func row(_ rival: RivalSummary, in nodes: [MacAXNode]) throws -> MacAXNode {
        try #require(
            nodes.first { $0.identifier == rowID(rival) && $0.isElement },
            "\(rowID(rival)) in\n\(nodes.map(\.description).joined(separator: "\n"))"
        )
    }

    // MARK: - Names, roles and state

    /// Each row is one button named by the rival and both pills, with no "shared" count
    /// (#40). Nothing reads the count, a pill, the status dot or the chevron on its own.
    @Test func rivalRowsNameTheRivalAndPillsWithoutTheSharedCount() async throws {
        let hosted = try await Self.hostCard(.large)
        defer { hosted.close() }
        let response = try Self.response()
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "rival-rows-large")

        for rival in Self.rows(response) {
            let row = try Self.row(rival, in: nodes)
            #expect(row.role == "AXButton", "a rival row opens Rival Detail: \(row)")
            #expect(row.spokenName == Self.spokenName(rival), "\(row)")
        }
        // The fixture's first rival, spelled out, so the expectation can't drift with the helper.
        #expect(try Self.row(response.above[0], in: nodes).spokenName
            == "Fixture Rival Golf, 128 songs ahead, 243 songs behind")

        let elements = nodes.filter(\.isElement)
        #expect(!elements.contains { $0.spokenName.localizedCaseInsensitiveContains("shared") },
                "no element reads a shared count")
        let sharedCounts = Set(Self.rows(response).map { "\($0.sharedSongCount)" })
        #expect(!elements.contains { sharedCounts.contains($0.spokenName) }, "no bare shared count")
        let pills = Set(Self.rows(response).flatMap { ["\($0.behindCount) ahead", "\($0.aheadCount) behind"] })
        #expect(!elements.contains { pills.contains($0.spokenName) }, "pills are read with their row only")
        let decorations: Set<String> = ["chevron.forward", "Forward", "circle", "circle.fill"]
        #expect(!elements.contains { decorations.contains($0.spokenName) }, "dot and chevron stay hidden")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Reading order and target size

    /// The heading reads first, then rivals ahead and behind in fixture order, then View All
    /// Rivals; rows stack top to bottom as full-width targets at least 44 pt tall.
    @Test func rivalRowsReadInVisualOrderAsFullWidthTargets() async throws {
        let hosted = try await Self.hostCard(.large)
        defer { hosted.close() }
        let host = hosted.host
        let rivals = try Self.rows(Self.response())
        let order = macAccessibilityTree(host, navigationOrder: true).filter(\.isElement)
        func index(_ match: (MacAXNode) -> Bool, _ what: String) throws -> Int {
            let found = order.firstIndex(where: match)
            return try #require(found, "\(what) in the reading order")
        }
        var sequence = [try index({ $0.spokenName == "Lead Rivals" }, "Lead Rivals heading")]
        for rival in rivals {
            sequence.append(try index({ $0.identifier == Self.rowID(rival) }, rival.displayName ?? rival.accountId))
        }
        sequence.append(try index({ $0.identifier == "fst.rivals.song.Solo_Guitar.view-all" }, "View All Rivals"))
        #expect(sequence == sequence.sorted() && Set(sequence).count == sequence.count,
                "heading, six rows, View All in reading order: \(sequence)")

        let frames = try rivals.map { try #require(nativeHostedAccessibilityFrame(Self.rowID($0), in: host)) }
        for (frame, rival) in zip(frames, rivals) {
            #expect(frame.height >= 44 - 0.5, "\(rival.displayName ?? "") row is at least 44 pt tall: \(frame)")
            #expect(frame.width >= 402 * 0.75, "\(rival.displayName ?? "") row spans the card: \(frame)")
        }
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            #expect(upper.maxY <= lower.minY + 0.5, "rows stack in reading order: \(upper) above \(lower)")
        }
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the pills stack instead of sharing one line (#411:
    /// side by side on iPhone they split "ahead" as "ahea/d"), so every row grows by at least
    /// a pill's height, and the rows keep their names, roles and order.
    @Test func rivalRowsStackTheirPillsAtAccessibilitySizes() async throws {
        let rivals = try Self.rows(Self.response())
        let standard = try await Self.hostCard(.large)
        let standardHeights = try rivals.map {
            try #require(nativeHostedAccessibilityFrame(Self.rowID($0), in: standard.host)).height
        }
        standard.close()

        let hosted = try await Self.hostCard(.accessibility5)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "rival-rows-ax5")
        var previousMaxY = -CGFloat.infinity
        for (rival, standardHeight) in zip(rivals, standardHeights) {
            let frame = try #require(nativeHostedAccessibilityFrame(Self.rowID(rival), in: hosted.host))
            // A caption pill is about 19 pt tall plus 6 pt spacing.
            #expect(frame.height > standardHeight + 12,
                    "\(rival.displayName ?? "") pills stack at AX5: \(frame.height) vs \(standardHeight)")
            #expect(frame.minY >= previousMaxY - 0.5, "rows still stack at AX5: \(frame)")
            previousMaxY = frame.maxY
            let row = try Self.row(rival, in: nodes)
            #expect(row.role == "AXButton" && row.spokenName == Self.spokenName(rival), "\(row)")
        }
        #expect(!nodes.contains { $0.isElement && $0.spokenName.localizedCaseInsensitiveContains("shared") })
        #expect(macAccessibilityFindings(nodes) == [])
    }
}
#endif
