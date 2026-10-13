#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Song Detail card rows (issue #365, backfilled by #490)

/// #365 made Song Detail's instrument cards that share a row start at the row's top edge
/// (``HingeGrid`` top-aligns its columns; the accessibility-size ``HingeEagerGrid``
/// already did), where a shorter card used to sink to the middle of its row. These hosted
/// checks pin what VoiceOver, Voice Control and touch exploration get from that row, with
/// the real ``SongScorePreview`` cards of `fixture-pulse`'s first row: a tall Lead card
/// (three top scores and View Full Leaderboard) beside a short, empty Bass card.
///
/// - **Name, role:** each card's header is one heading named by its instrument, then its
///   subtitle; rows and View Full Leaderboard are named buttons.
/// - **Row geometry:** both headings start on one top edge, side by side and inside their
///   own column (on iPhone Duo in book pose, on their own side of the fold), so the
///   VoiceOver cursor and touch exploration meet them on one line.
/// - **Reading order:** card by card, as the web reads its DOM: Lead's heading, its rows,
///   its View Full Leaderboard, then Bass's heading and its empty-state text. Each card is
///   one container (`fst.song-detail.card.*`): without it the grid ordered the cards'
///   elements by position, so the row read "Lead", "Bass", then Lead's and Bass's rows
///   alternately (#490).
/// - **Target size:** rows and View Full Leaderboard are at least 44 pt tall and stay in
///   their card's column.
/// - **Text scaling:** at AX5 (the eager grid) the same name, order, top edge and targets
///   hold while the top-score rows restack, which makes the cards even more unequal. The
///   Mac host renders no Dynamic Type (HIG Typography: "macOS doesn't support Dynamic
///   Type"), so real glyph growth is the iPad journey
///   `SongDetailCardRowAccessibilityJourneyTests`.
///
/// iPad portrait, iPhone Duo (flat and book pose) and a Mac window run the same SwiftUI.
/// HIG Layout: "Align related elements"; HIG VoiceOver: "Specify how elements are grouped,
/// ordered or linked where relationships are only visual, like proximity or alignment"
/// (should); HIG Accessibility: iOS/iPadOS default control size 44×44 pt.
@MainActor
@Suite(.serialized)
struct SongDetailCardRowAccessibilityTests {
    // MARK: - Fixtures

    static let song = Song(
        songId: "fixture-pulse", title: "Fixture Pulse", artist: "The Fixtures", album: nil,
        year: 2024, durationSeconds: 180, albumArt: nil, difficulty: nil,
        pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
    )

    /// A first-row chart preview: `count` top scores (none for an empty chart).
    ///
    /// - Parameters:
    ///   - instrument: The card's instrument.
    ///   - count: Number of top-score rows.
    /// - Returns: A validated, offline preview payload.
    /// - Throws: Malformed fixture JSON or leaderboard shape.
    static func preview(_ instrument: Instrument, count: Int) throws -> LeaderboardPayload {
        let entries = (0..<count).map { index in
            """
            {"accountId":"p\(index + 1)","displayName":"Player \(index + 1)","score":\(99_800 - index * 1_100),
             "rank":\(index + 1),"accuracy":\(980_000 - index * 10_000),"isFullCombo":false,"stars":5}
            """
        }
        let data = Data("""
        {"songId":"fixture-pulse","instrument":"\(instrument.rawValue)","count":\(count),
         "localEntries":\(count == 0 ? 0 : 26),"totalEntries":\(count == 0 ? 0 : 26),
         "showLeaderboardEntryTotals":true,"entries":[\(entries.joined(separator: ","))]}
        """.utf8)
        let result = try JSONDecoder().decode(LeaderboardResponse.self, from: data)
        try result.validate(songId: "fixture-pulse", instrument: instrument)
        return LeaderboardPayload(
            page: 1, leaderboard: result, publicationId: 7, observedPublicationId: 7, isStale: false
        )
    }

    /// The vertical fold of the iPhone Duo inner display in book pose (window coordinates).
    nonisolated static let bookFold = CGRect(x: 455, y: 0, width: 40, height: 669)

    /// One window #365's row appears in.
    struct Scenario: CustomTestStringConvertible, Sendable {
        let name: String
        let size: CGSize
        /// The vertical bar the Duo windows keep on the trailing edge.
        let trailingBar: CGFloat
        let layout: DeviceLayout
        /// The book pose's fold, which the two cards must straddle.
        let fold: CGRect?

        var testDescription: String { name }
    }

    nonisolated static let scenarios: [Scenario] = {
        let duoInsets = EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84)
        let duoSize = CGSize(width: 951, height: 669)
        return [
            Scenario(
                name: "ipad-portrait", size: CGSize(width: 834, height: 1194), trailingBar: 0,
                layout: DeviceLayout.resolve(LayoutSignals(size: CGSize(width: 834, height: 1194), widthClass: .regular)),
                fold: nil
            ),
            Scenario(
                name: "duo-flat", size: duoSize, trailingBar: 84,
                layout: DeviceLayout.resolve(LayoutSignals(
                    size: duoSize, widthClass: .regular, safeAreaInsets: duoInsets,
                    verticalBarEdge: .trailing, hinge: .fullyOpen, hinges: [bookFold]
                )),
                fold: nil
            ),
            Scenario(
                name: "duo-book", size: duoSize, trailingBar: 84,
                layout: DeviceLayout.resolve(LayoutSignals(
                    size: duoSize, widthClass: .regular, safeAreaInsets: duoInsets,
                    verticalBarEdge: .trailing, hinge: .partiallyOpen, divisions: [bookFold], hinges: [bookFold]
                )),
                fold: bookFold
            ),
            Scenario(
                name: "mac-window", size: CGSize(width: 1100, height: 900), trailingBar: 0,
                layout: DeviceLayout.resolve(LayoutSignals(size: CGSize(width: 1100, height: 900), widthClass: .regular)),
                fold: nil
            ),
        ]
    }()

    static let leadHeader = "fst.song-detail.card-header.Solo_Guitar"
    static let bassHeader = "fst.song-detail.card-header.Solo_Bass"
    static let leadRows = ["p1", "p2", "p3"].map { "fst.song-detail.preview-row.Solo_Guitar.\($0)" }
    static let leadViewFull = "fst.song-detail.leaderboard.Solo_Guitar"
    static let bassEmptyText = "When scores are submitted for Bass"

    /// One hosted row, its window and storage.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        func frame(_ identifier: String) throws -> CGRect {
            try #require(nativeHostedAccessibilityFrame(identifier, in: host), "\(identifier) frame")
        }

        /// The Bass card's empty-state text, found by its words (it has no identifier).
        func bassEmptyFrame() throws -> CGRect {
            let element = try #require(nativeHostedAccessibilityElement(in: host) {
                nativeHostedAccessibilityString($0, "accessibilityLabel").hasPrefix(SongDetailCardRowAccessibilityTests.bassEmptyText)
                    || nativeHostedAccessibilityString($0, "accessibilityValue").hasPrefix(SongDetailCardRowAccessibilityTests.bassEmptyText)
            }, "Bass empty-state text")
            return try #require(nativeHostedAccessibilityFrame(of: element, in: host))
        }
    }

    /// Host Song Detail's card grid with the Lead and Bass cards, as the page lays it out.
    ///
    /// - Parameters:
    ///   - scenario: The window and device layout.
    ///   - typeSize: Dynamic Type size (accessibility sizes use the eager grid).
    /// - Returns: The settled host.
    /// - Throws: Fixture errors or a host that never settles.
    static func host(_ scenario: Scenario, typeSize: DynamicTypeSize) async throws -> Hosted {
        let suiteName = "fst-card-row-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let previews: [Instrument: LeaderboardPayload] = [
            .lead: try preview(.lead, count: 3), .bass: try preview(.bass, count: 0),
        ]
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    ScrollView {
                        SongDetailCardGrid(items: [Instrument.lead, .bass]) { _, instrument in
                            SongScorePreview(
                                song: song, instrument: instrument, session: session,
                                initialState: previews[instrument].map { .loaded($0) }
                            )
                        }
                        .padding(16)
                    }
                    .padding(.trailing, scenario.trailingBar)
                }
                .frame(width: scenario.size.width, height: scenario.size.height)
                .environment(\.deviceLayout, scenario.layout)
                .defaultAppStorage(storage)
                .background(BrandTokens.appBackground)
                .environment(\.dynamicTypeSize, typeSize)
                .preferredColorScheme(.dark)
            ),
            size: scenario.size
        )
        let window = nativeHostedWindow(host, size: scenario.size)
        let ready = [leadHeader, bassHeader, leadViewFull] + leadRows
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            guard ready.allSatisfy({ nativeHostedAccessibilityFrame($0, in: host) != nil }) else { return false }
            // In book pose the grid's measured span arrives a layout pass later.
            guard let fold = scenario.fold,
                  let lead = nativeHostedAccessibilityFrame(leadHeader, in: host) else { return true }
            return lead.maxX <= fold.minX + 1.5
        }
        return Hosted(host: host, window: window, storage: storage, suiteName: suiteName)
    }

    // MARK: - Checks

    /// One top edge, side by side; card-by-card order; named headings and 44 pt targets.
    ///
    /// - Returns: The first Lead row's height, for the AX5 restack comparison.
    @discardableResult
    static func expectRow(
        _ hosted: Hosted, _ scenario: Scenario, _ phase: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws -> CGFloat {
        let nodes = macAccessibilityTree(hosted.host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "song-detail-card-row-\(scenario.name)-\(phase)")
        let order = nodes.filter(\.isElement)
        let tree = "\(scenario.name) \(phase)\n\(order.map(\.description).joined(separator: "\n"))"

        // Name and role: one heading per card, named by its instrument, then its subtitle.
        for (id, name, subtitle) in [(leadHeader, "Lead", "26 entries"), (bassHeader, "Bass", "No scores recorded yet")] {
            let headings = order.filter { $0.identifier == id }
            #expect(headings.count == 1, "\(id) is read once: \(tree)", sourceLocation: sourceLocation)
            if let heading = headings.first {
                #expect(heading.role == "AXHeading", "\(id) is a heading: \(heading)", sourceLocation: sourceLocation)
                #expect(heading.spokenName.hasPrefix(name) && heading.spokenName.contains(subtitle),
                        "\(id) reads its instrument, then its subtitle: \(heading)", sourceLocation: sourceLocation)
            }
        }
        for id in leadRows + [leadViewFull] {
            let node = order.first { $0.identifier == id }
            #expect(node?.role == "AXButton", "\(id) is a button: \(tree)", sourceLocation: sourceLocation)
        }
        #expect(order.first { $0.identifier == leadViewFull }?.spokenName.contains("Lead") == true,
                "View Full Leaderboard names its card: \(tree)", sourceLocation: sourceLocation)
        #expect(macAccessibilityFindings(nodes) == [], "\(scenario.name) \(phase)", sourceLocation: sourceLocation)

        // Reading order: each card is one container, read whole: Lead's heading, rows and
        // View Full Leaderboard, then Bass.
        for id in ["fst.song-detail.card.Solo_Guitar", "fst.song-detail.card.Solo_Bass"] {
            #expect(nodes.contains { $0.identifier == id && $0.role == "AXGroup" },
                    "\(id) groups its card: \(tree)", sourceLocation: sourceLocation)
        }
        let readOrder = try ([leadHeader] + leadRows + [leadViewFull, bassHeader]).map { id in
            try #require(order.firstIndex { $0.identifier == id }, "\(id) is read: \(tree)")
        }
        let empty = try #require(order.firstIndex { $0.spokenName.hasPrefix(bassEmptyText) }, "Bass empty state is read: \(tree)")
        #expect(readOrder + [empty] == (readOrder + [empty]).sorted(),
                "the row reads card by card, heading first: \(readOrder + [empty])\n\(tree)", sourceLocation: sourceLocation)

        // Geometry (#365): both headings on one top edge, side by side in their columns.
        let lead = try hosted.frame(leadHeader)
        let bass = try hosted.frame(bassHeader)
        let tolerance: CGFloat = 1.5
        #expect(abs(bass.minY - lead.minY) < tolerance,
                "the cards sharing a row start on one top edge: Lead \(lead), Bass \(bass)", sourceLocation: sourceLocation)
        #expect(bass.minX >= lead.maxX + SongDetailCardColumns.spacing - tolerance,
                "Bass sits beside Lead: \(lead), \(bass)", sourceLocation: sourceLocation)
        if let fold = scenario.fold {
            #expect(lead.maxX <= fold.minX + tolerance && bass.minX >= fold.maxX - tolerance,
                    "each heading stays on its side of the fold \(fold): \(lead), \(bass)", sourceLocation: sourceLocation)
        }
        // The cards are unequal, so a centred row would put the headings on different lines.
        let viewFull = try hosted.frame(leadViewFull)
        let bassEmpty = try hosted.bassEmptyFrame()
        #expect(viewFull.maxY > bassEmpty.maxY + 40,
                "the fixture's Lead card is taller than Bass: \(viewFull) vs \(bassEmpty)", sourceLocation: sourceLocation)
        #expect(bassEmpty.minX >= bass.minX - tolerance, "Bass's text stays in its column: \(bassEmpty)", sourceLocation: sourceLocation)

        // Target size: rows and View Full Leaderboard are 44 pt targets inside Lead's column.
        for id in leadRows + [leadViewFull] {
            let target = try hosted.frame(id)
            #expect(target.height >= 44 - 0.5, "\(id) is a 44 pt target: \(target)", sourceLocation: sourceLocation)
            #expect(target.minX >= lead.minX - tolerance && target.maxX <= bass.minX - SongDetailCardColumns.spacing + tolerance,
                    "\(id) stays in Lead's column: \(target)", sourceLocation: sourceLocation)
        }
        return try hosted.frame(leadRows[0]).height
    }

    // MARK: - Tests

    /// At the default size and at AX5, the row's headings share a top edge, read card by
    /// card and keep their names and targets; at AX5 the rows restack.
    @Test(arguments: scenarios)
    func instrumentCardsInOneRowReadCardByCardFromOneTopEdge(_ scenario: Scenario) async throws {
        let standard = try await Self.host(scenario, typeSize: .large)
        let standardRow = try Self.expectRow(standard, scenario, "default")
        standard.close()

        let largest = try await Self.host(scenario, typeSize: .accessibility5)
        defer { largest.close() }
        let restacked = try Self.expectRow(largest, scenario, "ax5")
        #expect(restacked > standardRow + 10, "\(scenario.name): Lead's rows restack at AX5: \(standardRow) → \(restacked)")
    }
}
#endif
