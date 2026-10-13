#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Song band leaderboard header accessibility (issue #317, backfilled by #465)

/// The Duos/Trios/Quads song leaderboard leads with the solo board's song header
/// (``SongHeaderRow`` with the band size as its board line), pins the song and band size
/// to the bar once that header scrolls away (``SongBarTitle``) and sits over the song's
/// static album art instead of the moving carousel (issue #317, patterns `song-header`
/// and `song-leaderboard-header`). These hosted checks pin what that region exposes on
/// every Apple platform (the same SwiftUI runs on iPhone, iPad, iPhone Duo and Mac): one
/// heading naming the song, artist and band size in visual order, read before the band
/// rows and the pager; a name that follows the chosen band size; decorative art hidden;
/// growth instead of clipping at the largest accessibility size; and no motion behind
/// the board. The iPhone bar, Band Size tool and system audit are covered on device by
/// `SongBandLeaderboardAccessibilityJourneyTests`.
///
/// HIG VoiceOver: "Use titles and headings to convey hierarchy"; "Exclude purely
/// decorative images". HIG Typography: "Keep text truncation to a minimum as font size
/// increases." HIG Accessibility (motion): "When Reduce Motion is on, reduce automatic
/// and repetitive animation."
@MainActor
@Suite(.serialized)
struct SongBandLeaderboardHeaderAccessibilityTests {
    // MARK: - Fixture

    static let headerID = "fst.song-band-leaderboard.header"
    static let rowPrefix = "fst.song-band-leaderboard.row."
    static let pagerIDs = ["first", "previous", "next", "last"].map { "fst.song-band-leaderboard.page-\($0)" }
        + ["fst.song-band-leaderboard.page-info"]
    static let size = CGSize(width: 402, height: 900)

    /// One hosted band board over the keyless fixture service.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let session: FestivalSession
        let song: Song

        func close() {
            window.orderOut(nil)
        }
    }

    /// The band size a hosted board shows, switched by a test in place of the Band Size
    /// tool.
    @MainActor @Observable
    final class BandSizeSelection {
        var size: BandType

        init(_ size: BandType) {
            self.size = size
        }
    }

    /// Hosts the band board on a band size the test owns.
    struct BandSizeHarness: View {
        let session: FestivalSession
        let song: Song
        @Bindable var selection: BandSizeSelection

        var body: some View {
            SongBandLeaderboardContent(session: session, song: song, bandType: $selection.size)
        }
    }

    /// Host the `fixture-pulse` band board at a phone width with no selected player, and
    /// wait until its header names `bandType` with that board's loaded entry total.
    ///
    /// - Parameters:
    ///   - selection: The band size to show; the test may switch it later.
    ///   - typeSize: Dynamic Type size for the whole page.
    ///   - long: Give the song a title and artist far wider than the page.
    /// - Returns: The settled host, its window and session.
    /// - Throws: An unavailable fixture service, catalogue song or a header that never loads.
    static func hostBoard(
        _ selection: BandSizeSelection, typeSize: DynamicTypeSize = .large, long: Bool = false
    ) async throws -> Hosted {
        nativeHostedEnableAccessibility()
        let client = try FestivalAPI(
            baseURL: try await RivalsMockService.shared.baseURL(), transport: URLSessionHTTPTransport()
        )
        let session = FestivalSession(factory: { client })
        let fixture = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
        let song = long ? longSong(fixture) : fixture
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    BandSizeHarness(session: session, song: song, selection: selection)
                }
                .frame(width: size.width, height: size.height)
                .preferredColorScheme(.dark)
                .environment(\.horizontalSizeClass, .compact)
                .environment(\.dynamicTypeSize, typeSize)
                .environment(\.marqueeAnimationEnabled, false)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let hosted = Hosted(host: host, window: window, session: session, song: song)
        try await settleHeader(hosted, naming: selection.size)
        return hosted
    }

    /// Wait until the header names `bandType` with its entry total (its board answered).
    ///
    /// - Parameters:
    ///   - hosted: The hosted board.
    ///   - bandType: The band size the header must name.
    /// - Throws: A header that never names the band size's loaded total.
    static func settleHeader(_ hosted: Hosted, naming bandType: BandType) async throws {
        _ = try await nativeHostedSettle(hosted.host, timeout: .seconds(60)) {
            guard headerLabel(in: hosted.host).contains("\(bandType.label) · ") else { return false }
            return nativeHostedAccessibilityFrame("fst.song-band-leaderboard.page-info", in: hosted.host) != nil
                || nativeHostedAccessibilityFrame("fst.song-band-leaderboard.empty", in: hosted.host) != nil
        }
    }

    /// The header's spoken label, or "" before it exists.
    static func headerLabel(in host: NSView) -> String {
        nativeHostedAccessibilityElement(headerID, in: host)
            .map { nativeHostedAccessibilityString($0, "accessibilityLabel") } ?? ""
    }

    /// The header node assistive technologies reach.
    static func header(in nodes: [MacAXNode]) throws -> MacAXNode {
        try #require(
            nodes.first { $0.identifier == headerID && $0.isElement },
            "\(headerID) in\n\(nodes.map(\.description).joined(separator: "\n"))"
        )
    }

    /// The position of each part in a label, asserting each occurs exactly once.
    ///
    /// - Parameters:
    ///   - parts: Texts expected in reading order.
    ///   - label: The spoken label.
    /// - Returns: Whether every part occurs once and in the given order.
    static func readsOnceInOrder(_ parts: [String], in label: String) -> Bool {
        var cursor = label.startIndex
        for part in parts {
            guard label.components(separatedBy: part).count == 2,
                  let range = label.range(of: part, range: cursor..<label.endIndex) else { return false }
            cursor = range.upperBound
        }
        return true
    }

    // MARK: - Name, role and state

    /// For every band size the header is one heading that reads the song title, the
    /// artist, then the band size with its entry total, each once; the 80 pt art is
    /// hidden, the old "<Band> Scores" title is gone, the other sizes are not named and
    /// nothing on the page is unnamed.
    @Test(arguments: BandType.allCases)
    func headerIsOneHeadingNamingSongArtistThenBandSize(bandType: BandType) async throws {
        let hosted = try await Self.hostBoard(BandSizeSelection(bandType))
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "song-band-header-\(bandType.rawValue)")
        let header = try Self.header(in: nodes)
        #expect(header.role == "AXHeading", "the header is a heading: \(header)")
        let label = header.spokenName
        #expect(
            Self.readsOnceInOrder([hosted.song.title, hosted.song.artist, "\(bandType.label) · "], in: label),
            "title, artist, then the band size, once each: \(label)"
        )
        #expect(label.contains(" entries"), "the board's entry total joins the band size: \(label)")
        for other in BandType.allCases where other != bandType {
            #expect(!label.contains(other.label), "only \(bandType.label) is named: \(label)")
        }
        #expect(!nodes.contains { $0.isElement && $0.spokenName.contains("Scores") }, "no '<Band> Scores' title")
        // The song title is read once on the page: in the header, not a second title.
        #expect(nodes.filter { $0.isElement && $0.spokenName.contains(hosted.song.title) }.count == 1,
                "one element names the song")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// Picking another band size renames the heading at once (the state VoiceOver reads
    /// follows the Band Size tool), and the new board's total joins only once it answers.
    @Test func headerNameFollowsTheChosenBandSize() async throws {
        let selection = BandSizeSelection(.duets)
        let hosted = try await Self.hostBoard(selection)
        defer { hosted.close() }
        #expect(Self.headerLabel(in: hosted.host).contains("Duos · "))
        selection.size = .trios
        try await Self.settleHeader(hosted, naming: .trios)
        let label = try Self.header(in: macAccessibilityTree(hosted.host)).spokenName
        #expect(Self.readsOnceInOrder([hosted.song.title, hosted.song.artist, "Trios · "], in: label), "\(label)")
        #expect(!label.contains("Duos"), "the previous size is no longer named: \(label)")
    }

    // MARK: - Reading order

    /// The header is the page's first heading and reads before every band row and the
    /// pager, matching the layout top to bottom, and sits above the first row on screen.
    @Test func headerReadsFirstBeforeRowsAndPager() async throws {
        let hosted = try await Self.hostBoard(BandSizeSelection(.duets))
        defer { hosted.close() }
        let host = hosted.host
        let tree = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(tree, name: "song-band-header-order")
        let order = tree.filter(\.isElement)
        let header = try #require(order.firstIndex { $0.identifier == Self.headerID }, "header in the reading order")
        let firstHeading = try #require(order.firstIndex { $0.role == "AXHeading" })
        #expect(firstHeading == header, "the song header is the first heading: \(order[firstHeading])")
        let rows = order.indices.filter { order[$0].identifier.hasPrefix(Self.rowPrefix) }
        let pager = Self.pagerIDs.compactMap { id in order.firstIndex { $0.identifier == id } }
        #expect(!rows.isEmpty, "band rows in the reading order")
        #expect(rows.allSatisfy { $0 > header }, "the header reads before the rows: \(header) vs \(rows)")
        #expect(pager.count == Self.pagerIDs.count, "every pager control in the reading order: \(pager)")
        #expect(pager.allSatisfy { $0 > header }, "the header reads before the pager: \(header) vs \(pager)")

        let headerFrame = try #require(nativeHostedAccessibilityFrame(Self.headerID, in: host))
        let firstRow = try #require(order.first { $0.identifier.hasPrefix(Self.rowPrefix) })
        let rowFrame = try #require(nativeHostedAccessibilityFrame(firstRow.identifier, in: host))
        #expect(headerFrame.maxY <= rowFrame.minY + 0.5, "the header sits above the rows: \(headerFrame) over \(rowFrame)")
    }

    // MARK: - Text scaling

    /// A title and artist far wider than the phone, on the `fixture-pulse` board.
    static func longSong(_ base: Song) -> Song {
        Song(
            songId: base.songId,
            title: "\(base.title): An Extraordinarily Long Synthetic Encore Title That Keeps Going",
            artist: "\(base.artist) and the Several Guest Performers Featured on This Recording",
            album: base.album, year: base.year, durationSeconds: base.durationSeconds, albumArt: base.albumArt,
            difficulty: base.difficulty, pathArtifactGenerationId: base.pathArtifactGenerationId, sig: base.sig,
            maxScores: base.maxScores, doubleBassSupported: base.doubleBassSupported
        )
    }

    /// At the largest accessibility size a long title and artist wrap onto as many lines
    /// as they need instead of scrolling on one line, so the header grows rather than
    /// clipping (``MarqueeText`` `wrapsAtAccessibilitySizes`); it keeps its whole label,
    /// stays inside the page's width and leaves the first band row reachable below it.
    ///
    /// The Mac host does not enlarge fonts for `dynamicTypeSize`, so this pins the
    /// accessibility-size layout; the glyphs' growth on device is
    /// `SongBandLeaderboardAccessibilityJourneyTests.testBandBoardHeaderGrowsAtAX5`.
    @Test func headerWrapsLongNamesAndKeepsItsNameAtAccessibilitySizes() async throws {
        let standard = try await Self.hostBoard(BandSizeSelection(.duets), long: true)
        defer { standard.close() }
        let standardLabel = Self.headerLabel(in: standard.host)
        let standardFrame = try #require(nativeHostedAccessibilityFrame(Self.headerID, in: standard.host))

        let hosted = try await Self.hostBoard(BandSizeSelection(.duets), typeSize: .accessibility5, long: true)
        defer { hosted.close() }
        let host = hosted.host
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "song-band-header-ax5")
        _ = try nativeHostedPNG(
            try nativeHostedImage(host), filename: "song-band-header-ax5.png", environment: "FST_BANDS_RENDER_OUT"
        )
        let header = try Self.header(in: nodes)
        #expect(header.role == "AXHeading")
        #expect(header.spokenName == standardLabel, "the same whole label at AX5: \(header.spokenName)")
        #expect(Self.readsOnceInOrder([hosted.song.title, hosted.song.artist, "Duos · "], in: header.spokenName))
        let frame = try #require(nativeHostedAccessibilityFrame(Self.headerID, in: host))
        #expect(frame.height > standardFrame.height * 1.3,
                "the long names wrap at AX5: \(standardFrame.height) → \(frame.height)")
        #expect(frame.minX >= -0.5 && frame.maxX <= Self.size.width + 0.5, "the header stays inside the page: \(frame)")
        #expect(frame.minY >= -0.5 && frame.maxY < Self.size.height, "the header stays on screen: \(frame)")
        #expect(nodes.contains { $0.isElement && $0.identifier.hasPrefix(Self.rowPrefix) },
                "band rows stay reachable below the header at AX5")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    // MARK: - Pinned bar title

    /// Once the header scrolls away, the bar's title reads as one heading naming the song
    /// and the band size once each, at the standard and the largest accessibility size;
    /// a band size has no instrument icon to hide or repeat.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func pinnedBarTitleIsOneHeadingNamingSongAndBandSize(typeSize: DynamicTypeSize) throws {
        nativeHostedEnableAccessibility()
        let client = try FestivalAPI(baseURL: try #require(URL(string: "http://127.0.0.1:9")))
        let session = FestivalSession(factory: { client })
        let song = Song(
            songId: "fixture-song", title: "Through the Fire and Flames", artist: "DragonForce", album: nil,
            year: 2006, durationSeconds: 441, albumArt: nil, difficulty: nil,
            pathArtifactGenerationId: nil, sig: nil, maxScores: nil, doubleBassSupported: nil
        )
        let size = CGSize(width: 320, height: 120)
        let host = nativeHostedView(
            SongBarTitle(song: song, session: session, caption: BandType.trios.label, captionInstrument: nil)
                .accessibilityIdentifier("fst.test.band-bar-title")
                .environment(\.marqueeAnimationEnabled, false)
                .environment(\.dynamicTypeSize, typeSize),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()
        let nodes = macAccessibilityTree(host)
        let title = try #require(nodes.first { $0.identifier == "fst.test.band-bar-title" && $0.isElement },
                                 "\(nodes.map(\.description))")
        #expect(title.role == "AXHeading", "the bar title is a heading: \(title)")
        #expect(Self.readsOnceInOrder([song.title, "Trios"], in: title.spokenName), "\(title.spokenName)")
        // Only the hosting view's own container besides the title: no separate icon or text.
        #expect(nodes.filter { $0.isElement && $0.role != "AXGroup" }.count == 1,
                "one element: \(nodes.map(\.description))")
    }

    // MARK: - Motion

    /// The board shows the song's static album art behind it, never the moving carousel,
    /// so nothing animates behind the rows whatever the Reduce Motion setting; the
    /// backdrop is decorative and adds nothing to the accessibility tree.
    @Test func boardShowsStaticSongArtBehindIt() async throws {
        let hosted = try await Self.hostBoard(BandSizeSelection(.duets))
        defer { hosted.close() }
        #expect(hosted.session.backgroundCoordinator.resolvedMode == .song(hosted.song.albumArt))
        #expect(hosted.session.backgroundCoordinator.resolvedMode != .carousel)
        let nodes = macAccessibilityTree(hosted.host)
        #expect(!nodes.contains { $0.isElement && $0.role == "AXImage" }, "no backdrop or art image is exposed")
    }
}
#endif
