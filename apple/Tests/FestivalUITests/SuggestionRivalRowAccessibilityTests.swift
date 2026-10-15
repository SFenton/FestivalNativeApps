#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Suggestions rival row accessibility (issue #29, backfilled by #404)

/// Single-rival Suggestions cards ("Rival Spotlight: {name}", "Close the Gap vs {name}",
/// "Climb Past {name}" since #656, …)
/// drop the per-row rival name badge beside the rank difference, because the card title
/// already names the rival (issue #29, `SuggestionRowLayout.showsRivalName`). These hosted
/// checks pin what those rows expose to VoiceOver, Voice Control and Dynamic Type on every
/// Apple platform (the card is the same SwiftUI on iPhone, iPad, iPhone Duo and Mac): each
/// row is one button that still says which rival and which way the rank moved, the name
/// is spoken once rather than repeated, mixed-rival cards keep their badge, the card reads
/// header first then rows in visual order, rows are at least 44 pt tall, and at the largest
/// accessibility size the metadata wraps under the song instead of clipping. HIG
/// Accessibility: "Provide VoiceOver descriptions for all interface elements"; "Never rely
/// on color alone" (the green/red delta is spoken as ahead/behind); iOS/iPadOS default
/// control size 44×44 pt; HIG Typography: "Keep text truncation to a minimum as font size
/// increases".
@MainActor
@Suite(.serialized)
struct SuggestionRivalRowAccessibilityTests {
    // MARK: - Fixture

    static let rival = "Fixture Rival"
    /// Longer than the badge's 12-character truncation ("Battlegroun…"), which VoiceOver
    /// must still read in full.
    static let otherRival = "Battleground Champion"

    /// A catalogue song with only the fields the row reads.
    static func song(_ id: String, _ title: String) throws -> Song {
        try JSONDecoder().decode(Song.self, from: Data("""
        {"songId":"\(id)","title":"\(title)","artist":"Synthetic Quartet","album":null,"year":2024,
         "durationSeconds":null,"albumArt":null,"difficulty":null,
         "pathArtifactGenerationId":null,"sig":null,"maxScores":null}
        """.utf8))
    }

    /// A rival card of two Lead rows: the player leads the first by 3 ranks and trails
    /// the second by 1.
    ///
    /// - Parameters:
    ///   - key: Category key (single-rival or mixed-rival family).
    ///   - title: Card title.
    ///   - names: Rival name per row.
    /// - Returns: The category.
    static func category(key: String, title: String, names: [String]) throws -> SuggestionCategory {
        let songs = try [song("fixture-pulse", "Fixture Pulse"), song("fixture-orbit", "Fixture Orbit")]
        return SuggestionCategory(
            key: key, title: title, description: "Fixture rivalry mix.",
            type: .songRivals, instrument: nil,
            songs: zip(songs, names).enumerated().map { index, pair in
                SuggestionSongItem(
                    song: pair.0, instrument: .lead, rivalName: pair.1,
                    rivalAccountId: "fixture-rival-\(index)", rivalRankDelta: index == 0 ? 3 : -1
                )
            }
        )
    }

    static func spotlight() throws -> SuggestionCategory {
        try category(
            key: "song_rival_spotlight_fixture-rival-0", title: "Rival Spotlight: \(rival)",
            names: [rival, rival]
        )
    }

    /// One hosted card on a phone-width page.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let category: SuggestionCategory

        func rowID(_ index: Int) -> String { "fst.suggestions.row.\(category.songs[index].id)" }
        func close() { window.orderOut(nil) }
    }

    /// Host one card inside a navigation stack (rows are navigation links) and wait for
    /// both rows to appear in the accessibility tree.
    ///
    /// - Parameters:
    ///   - category: The card.
    ///   - typeSize: Dynamic Type size for the card.
    ///   - regular: A regular-width (iPad, Mac) page instead of a compact phone page.
    /// - Returns: The settled host.
    /// - Throws: An unavailable capture.
    static func host(
        _ category: SuggestionCategory, _ typeSize: DynamicTypeSize = .large, regular: Bool = false
    ) async throws -> Hosted {
        let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
        let size = CGSize(width: regular ? 700 : 390, height: 900)
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    ScrollView {
                        SuggestionCategoryCardView(category: category, session: session)
                            .padding(.horizontal, 16)
                    }
                }
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, regular ? .regular : .compact)
                .environment(\.dynamicTypeSize, typeSize)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let hosted = Hosted(host: host, window: window, category: category)
        try await nativeHostedSettle(host) {
            (0..<2).allSatisfy { nativeHostedAccessibilityFrame(hosted.rowID($0), in: host) != nil }
        }
        return hosted
    }

    /// Occurrences of `needle` in `haystack`.
    static func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    // MARK: - Names, roles and state

    /// Each spotlight row is one button named by its song, artist, the rank change in
    /// words naming the rival (the badge that used to say who is gone) and the
    /// instrument; the rival is spoken once, never as a separate badge element, and the
    /// signed digits are not read as a bare "+3".
    @Test func spotlightRowsNameTheRivalOnceInTheRankChange() async throws {
        let hosted = try await Self.host(try Self.spotlight())
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "suggestions-rival-spotlight-large")
        func row(_ index: Int) throws -> MacAXNode {
            try #require(nodes.first { $0.identifier == hosted.rowID(index) && $0.isElement },
                         "row \(index) in\n\(nodes.map(\.description).joined(separator: "\n"))")
        }

        let expectations = [
            (try row(0), "Fixture Pulse", "3 ranks ahead of \(Self.rival)"),
            (try row(1), "Fixture Orbit", "1 rank behind \(Self.rival)"),
        ]
        for (node, title, change) in expectations {
            #expect(node.role == "AXButton", "\(title) row opens Song Detail: \(node)")
            let name = node.spokenName
            #expect(name.contains(title) && name.contains("Synthetic Quartet"), "\(node)")
            #expect(name.contains(change), "rank change names the rival: \(node)")
            #expect(Self.count(Self.rival, in: name) == 1, "rival spoken once, not badge + delta: \(node)")
            #expect(name.contains(Instrument.lead.label), "instrument spoken: \(node)")
            #expect(!name.contains("+3") && !name.contains("-1"), "signed digits replaced by words: \(node)")
        }

        // The title is the only other place the rival appears; no stray badge element.
        let mentions = nodes.filter { $0.isElement && $0.spokenName.contains(Self.rival) }
        #expect(mentions.count == 3, "header + two rows: \(mentions)")
        let header = try #require(nodes.first { $0.isElement && $0.spokenName == "Rival Spotlight: \(Self.rival)" },
                                  "card title")
        #expect(header.role == "AXHeading", "card title is a heading: \(header)")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// Mixed-rival cards keep the visible badge, and the delta does not repeat its name:
    /// the row says the rival's full name once (not the badge's truncated text, #404),
    /// then "N ranks ahead/behind".
    @Test func battlegroundRowsKeepTheirBadgeWithoutRepeatingTheName() async throws {
        let battleground = try Self.category(
            key: "song_rival_battleground", title: "Battleground Songs", names: [Self.otherRival, Self.rival]
        )
        #expect(SuggestionRowLayout.showsRivalName(categoryKey: battleground.key))
        let hosted = try await Self.host(battleground)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "suggestions-rival-battleground-large")
        let rows = try (0..<2).map { index in
            try #require(nodes.first { $0.identifier == hosted.rowID(index) && $0.isElement }, "row \(index)")
        }
        #expect(rows.allSatisfy { $0.role == "AXButton" }, "\(rows)")
        // The badge draws "Battlegroun…" but VoiceOver hears the whole name.
        #expect(rows[0].spokenName.contains(Self.otherRival), "full badge name spoken: \(rows[0])")
        #expect(!rows[0].spokenName.contains("\u{2026}"), "no truncated name spoken: \(rows[0])")
        #expect(rows[0].spokenName.contains("3 ranks ahead") && !rows[0].spokenName.contains("ahead of"), "\(rows[0])")
        #expect(rows[1].spokenName.contains(Self.rival), "badge spoken: \(rows[1])")
        #expect(Self.count(Self.rival, in: rows[1].spokenName) == 1, "\(rows[1])")
        #expect(rows[1].spokenName.contains("1 rank behind") && !rows[1].spokenName.contains("behind \(Self.rival)"),
                "\(rows[1])")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// "Climb Past {name}" (and its sibling named cross-pollination cards) lists only the
    /// rival it names since #656, so it reads like a single-rival card: heading first, then
    /// one ≥ 44 pt button per row whose rank change names the rival once, with no badge.
    @Test func climbPastRowsNameTheRivalOnceAfterTheHeading() async throws {
        let climb = try Self.category(
            key: "song_rival_pct_push", title: "Climb Past \(Self.rival)", names: [Self.rival, Self.rival]
        )
        #expect(!SuggestionRowLayout.showsRivalName(categoryKey: climb.key))
        let hosted = try await Self.host(climb)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "suggestions-rival-climb-past-large")
        let order = nodes.filter(\.isElement)
        let heading = try #require(order.firstIndex { $0.spokenName == "Climb Past \(Self.rival)" }, "heading")
        #expect(order[heading].role == "AXHeading", "card title is a heading: \(order[heading])")
        let rows = try (0..<2).map { index in
            try #require(order.firstIndex { $0.identifier == hosted.rowID(index) }, "row \(index)")
        }
        #expect(heading < rows[0] && rows[0] < rows[1], "heading, row 0, row 1: \(heading) \(rows)")
        for (index, change) in ["3 ranks ahead of \(Self.rival)", "1 rank behind \(Self.rival)"].enumerated() {
            let row = order[rows[index]]
            #expect(row.role == "AXButton" && row.spokenName.contains(change), "\(row)")
            #expect(Self.count(Self.rival, in: row.spokenName) == 1, "rival spoken once, not badge + delta: \(row)")
            let frame = try #require(nativeHostedAccessibilityFrame(hosted.rowID(index), in: hosted.host))
            #expect(frame.height >= 44 - 0.5, "row is a 44 pt target: \(frame)")
        }
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Reading order and target size

    /// The card reads its heading, then rows top to bottom; each row is one ≥ 44 pt
    /// target spanning the card, with nothing in it focusable on its own.
    @Test func spotlightCardReadsHeadingThenRowsWithFullSizeTargets() async throws {
        let hosted = try await Self.host(try Self.spotlight())
        defer { hosted.close() }
        let host = hosted.host
        let order = macAccessibilityTree(host).filter(\.isElement)
        let heading = try #require(order.firstIndex { $0.spokenName == "Rival Spotlight: \(Self.rival)" }, "heading")
        let first = try #require(order.firstIndex { $0.identifier == hosted.rowID(0) }, "row 0")
        let second = try #require(order.firstIndex { $0.identifier == hosted.rowID(1) }, "row 1")
        #expect(heading < first && first < second, "heading, row 0, row 1: \(heading) \(first) \(second)")
        // A combined row: its delta, badge or instrument icon is not a separate stop.
        let inside = order[(first + 1)..<second].filter { $0.role != "AXGroup" }
        #expect(inside.isEmpty, "no separate stops inside a row: \(inside)")

        let frames = try (0..<2).map { try #require(nativeHostedAccessibilityFrame(hosted.rowID($0), in: host)) }
        for frame in frames {
            #expect(frame.height >= 44 - 0.5, "row is a 44 pt target: \(frame)")
            #expect(frame.width >= 300, "row spans the card: \(frame)")
        }
        #expect(frames[0].maxY <= frames[1].minY + 0.5, "rows stack in reading order: \(frames)")
    }

    // MARK: - Text scaling

    /// At the largest accessibility size the rank change wraps under the song even on a
    /// regular-width (iPad, Mac) card, where standard sizes keep it on the song's line,
    /// so the row grows instead of squeezing the title; rows keep their full spoken
    /// names and stay in order without overlapping (web `twoRow`). Compact phone cards
    /// already stack at every size. Font growth itself is the system's (Dynamic Type on
    /// iOS), which a macOS host does not apply.
    @Test func spotlightRowsRestackAndKeepTheirNamesAtAccessibilitySizes() async throws {
        let standard = try await Self.host(try Self.spotlight(), regular: true)
        let standardFrame = try #require(nativeHostedAccessibilityFrame(standard.rowID(0), in: standard.host))
        standard.close()

        let hosted = try await Self.host(try Self.spotlight(), .accessibility5, regular: true)
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "suggestions-rival-spotlight-ax5")
        let frames = try (0..<2).map { try #require(nativeHostedAccessibilityFrame(hosted.rowID($0), in: hosted.host)) }
        #expect(frames[0].height > standardFrame.height + 10, "AX5 row restacks: \(frames[0]) vs \(standardFrame)")
        #expect(frames[0].maxY <= frames[1].minY + 0.5, "rows don't overlap: \(frames)")
        for (index, change) in ["3 ranks ahead of \(Self.rival)", "1 rank behind \(Self.rival)"].enumerated() {
            let row = try #require(nodes.first { $0.identifier == hosted.rowID(index) && $0.isElement }, "row \(index)")
            #expect(row.role == "AXButton" && row.spokenName.contains(change), "\(row)")
            #expect(Self.count(Self.rival, in: row.spokenName) == 1, "\(row)")
        }
        #expect(macAccessibilityFindings(nodes) == [])
    }
}
#endif
