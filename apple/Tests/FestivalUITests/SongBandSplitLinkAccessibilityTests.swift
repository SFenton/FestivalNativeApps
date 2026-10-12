#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Song Detail band links in a split (issue #367, backfilled by #492)

/// Song Detail's Duos, Trios and Quads "View Full Leaderboard" buttons and the selected
/// band's appended jump row are ``ListDetailLink``s (issue #367): where Song Detail can
/// split they open the band board in the trailing pane and stay selected while it is
/// open (`view-all-cta` R8, `split-panes`). The same SwiftUI runs in the iPad and iPhone
/// Duo `OnDemandSplit` and the Mac `MacListDetailStack`; these hosted checks run it in
/// the Mac stack over the keyless fixture service, with `fixture-player-1` selected
/// (`fixture-pulse` has Duos scores only; the player's Duos band is rank 29, appended
/// after the top rows):
///
/// - the Duos button is one button named "View Full Leaderboard, Duos", and only the
///   open board's link carries the selected state;
/// - with the Lead board open, pressing the Duos button (AXPress, as VoiceOver, Voice
///   Control and Switch Control do) replaces it in the trailing pane and moves the
///   selected state from Lead's button to Duos';
/// - the selected band's row is one named button whose hint names the jump, and pressing
///   it opens the board at the band's page in the pane and selects the row instead;
/// - Song Detail, with the links, reads before the trailing pane, whose first heading is
///   the band size; each link is at least 44 pt tall and sits in the leading pane.
///
/// On-device selection, target size, focus move and text growth at AX5 on iPad and the
/// iPhone Duo are `SongBandBoardSplitAccessibilityJourneyTests`; the pane's title is
/// `SplitBoardTitleAccessibilityTests.bandBoardTitleIsOneHeadingNamingTheBandSize`.
///
/// HIG Split views: "Persistently highlight the current selection in each pane leading to
/// a detail view." HIG Accessibility: "Convey state and function with shapes or icons in
/// addition to color"; iOS/iPadOS default control size 44×44 pt.
@MainActor
@Suite(.serialized)
struct SongBandSplitLinkAccessibilityTests {
    // MARK: - Fixture

    static let size = CGSize(width: 1280, height: 1600)
    static let paneID = "fst.split.trailing"
    static let titleID = "fst.song-band-leaderboard.board-title"
    static let soloTitleID = "fst.song-leaderboard.board-title"
    static let jumpRowID = "fst.song-detail.band-selected.Band_Duets"

    /// The button that opens `bandType`'s full board.
    static func ctaID(_ bandType: BandType) -> String {
        "fst.song-detail.band-leaderboard.\(bandType.rawValue)"
    }

    /// Holds the Mac list/detail stack's path so a press can change it.
    struct Harness: View {
        let session: FestivalSession
        @State var path: [AppRoute]

        var body: some View {
            MacListDetailStack(
                section: .songs, session: session, visibleInstruments: Set(Instrument.allCases),
                path: $path, isVisible: true, onSplitChange: { _ in }
            ) { _ in Text("Songs Root") }
        }
    }

    /// The links on Song Detail that open a board in the trailing pane.
    static let links = [ctaID(.duets), jumpRowID, "fst.song-detail.leaderboard.Solo_Guitar",
                        "fst.song-detail.leaderboard.Solo_Drums"]

    /// One hosted split over the keyless fixture service.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let storage: UserDefaults
        let suiteName: String
        let song: Song

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }
    }

    /// Host Song Detail for `fixture-pulse` with a board open beside it and
    /// `fixture-player-1` selected, and wait until the pane's title and the Duos links
    /// are reachable.
    ///
    /// - Parameter openBoard: The board in the trailing pane: the Duos board, else Lead's.
    /// - Returns: The settled split.
    /// - Throws: An unavailable fixture service or catalogue song, or a split that never
    ///   shows its links.
    static func hostSplit(openBoard: Bool = true) async throws -> Hosted {
        let client = try FestivalAPI(
            baseURL: try await RivalsMockService.shared.baseURL(), transport: URLSessionHTTPTransport()
        )
        let suiteName = "fst-band-split-link-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        let identity = ["accountId": "fixture-player-1", "displayName": "Fixture Player 1"]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
        let board: AppRoute = openBoard
            ? .songBandLeaderboard(song, bandType: "Band_Duets") : .songLeaderboard(song, .lead, 1)
        let host = nativeHostedView(
            AnyView(
                Harness(session: session, path: [.songDetail(song), board])
                    .frame(width: size.width, height: size.height)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        let hosted = Hosted(host: host, window: window, storage: storage, suiteName: suiteName, song: song)
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityElement(paneID, in: host) != nil
                && nativeHostedAccessibilityFrame(openBoard ? titleID : soloTitleID, in: host) != nil
        }
        // Song Detail builds its sections lazily: bring the band sections, which end
        // the page, into the leading pane. A cold run can reach the end before the band
        // previews load and grow the page, so scroll again until both links are built.
        func linksBuilt() -> Bool {
            nativeHostedAccessibilityFrame(jumpRowID, in: host) != nil
                && nativeHostedAccessibilityFrame(ctaID(.duets), in: host) != nil
        }
        for _ in 0..<6 where !linksBuilt() {
            try await scrollLeadingPaneToEnd(host)
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            while !linksBuilt(), ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(250))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
            }
        }
        _ = try await nativeHostedSettle(host, timeout: .seconds(30)) { linksBuilt() }
        macAccessibilityDump(macAccessibilityTree(host), name: "band-split-links-settled")
        return hosted
    }

    /// The leading pane's scroll view: the leftmost one whose content runs past its height.
    static func leadingScrollView(in host: NSView) -> NSScrollView? {
        var found: [NSScrollView] = []
        func walk(_ view: NSView) {
            if let scroll = view as? NSScrollView, let document = scroll.documentView,
               document.frame.height > scroll.contentView.bounds.height + 100 {
                found.append(scroll)
            }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found.min { lhs, rhs in
            lhs.convert(lhs.bounds, to: host).minX < rhs.convert(rhs.bounds, to: host).minX
        }
    }

    /// Scroll Song Detail, in the leading pane, to the end of its content, a screen at a
    /// time so each section is built on the way.
    static func scrollLeadingPaneToEnd(_ host: NSHostingView<NativeHostedRoot<AnyView>>) async throws {
        let scroll = try #require(leadingScrollView(in: host), "Song Detail scrolls")
        var previous = -1.0
        for _ in 0..<20 {
            let clip = scroll.contentView
            let document = try #require(scroll.documentView)
            let maximum = max(0, document.frame.height - clip.bounds.height)
            let next = min(clip.bounds.minY + scroll.contentInsets.top + clip.bounds.height * 0.8, maximum)
            clip.scroll(to: NSPoint(x: 0, y: next - scroll.contentInsets.top))
            scroll.reflectScrolledClipView(clip)
            _ = try await nativeHostedSettle(host, timeout: .seconds(10))
            if abs(next - previous) < 1 { break }
            previous = next
        }
    }

    /// The node with `identifier` that assistive technologies reach.
    static func element(_ identifier: String, in nodes: [MacAXNode]) throws -> MacAXNode {
        try #require(
            nodes.first { $0.identifier == identifier && $0.isElement },
            "\(identifier) in\n\(nodes.map(\.description).joined(separator: "\n"))"
        )
    }

    /// Press a control the way VoiceOver (VO-Space), Voice Control and Switch Control do:
    /// its AXPress action.
    static func press(_ identifier: String, in host: NSView) throws {
        try SongBandFooterAccessibilityTests.press(identifier, in: host)
    }

    /// The identifiers of Song Detail's board links that carry the selected state.
    static func selectedLinks(in nodes: [MacAXNode]) -> [String] {
        nodes.filter { $0.isElement && $0.selected && links.contains($0.identifier) }.map(\.identifier)
    }

    /// The trailing pane's title once it names `bandType`.
    static func waitForPane(_ bandType: BandType, in host: NSHostingView<NativeHostedRoot<AnyView>>) async throws {
        try await nativeHostedSettle(host, timeout: .seconds(30)) {
            guard nativeHostedAccessibilityFrame(titleID, in: host) != nil else { return false }
            return macAccessibilityTree(host).contains {
                $0.identifier == titleID && $0.isElement && $0.spokenName.hasPrefix(bandType.label)
            }
        }
    }

    // MARK: - Name, role and state

    /// The Duos button is one button named by its label and band size, and only the open
    /// Duos board's link is selected (not the jump row or the instrument boards'
    /// buttons); nothing in the split is unnamed.
    @Test func duosButtonIsNamedAndOnlyTheOpenBoardsLinkIsSelected() async throws {
        let hosted = try await Self.hostSplit()
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "band-split-links")
        let cta = try Self.element(Self.ctaID(.duets), in: nodes)
        #expect(cta.role == "AXButton", "the link is a button: \(cta)")
        #expect(cta.spokenName == "View Full Leaderboard, Duos", "named with its band size: \(cta)")
        #expect(Self.selectedLinks(in: nodes) == [Self.ctaID(.duets)],
                "only the open board's link is selected: \(Self.selectedLinks(in: nodes))")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// The selected band's appended row is one button that names the band's rank and
    /// hints the jump, and is not selected while the plain Duos board is open.
    @Test func selectedBandRowIsOneNamedJumpButton() async throws {
        let hosted = try await Self.hostSplit()
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        let row = try Self.element(Self.jumpRowID, in: nodes)
        #expect(row.role == "AXButton", "the row is a button: \(row)")
        #expect(row.spokenName.hasPrefix("Your band, Rank 29"), "names the band's rank: \(row)")
        #expect(row.help == "Jumps to your band's position in the full leaderboard", "hints the jump: \(row)")
        #expect(!row.selected, "the plain board's route is not the row's jump")
    }

    // MARK: - Activation

    /// With Lead's board beside Song Detail, pressing the Duos button replaces it with
    /// the Duos board in the trailing pane and moves the selected state from Lead's
    /// button to Duos'.
    @Test func pressingDuosReplacesTheOpenBoardAndMovesTheSelection() async throws {
        let hosted = try await Self.hostSplit(openBoard: false)
        defer { hosted.close() }
        #expect(Self.selectedLinks(in: macAccessibilityTree(hosted.host)) == ["fst.song-detail.leaderboard.Solo_Guitar"],
                "Lead's button is selected first")
        try Self.press(Self.ctaID(.duets), in: hosted.host)
        try await Self.waitForPane(.duets, in: hosted.host)
        let nodes = macAccessibilityTree(hosted.host)
        #expect(Self.selectedLinks(in: nodes) == [Self.ctaID(.duets)],
                "the selection follows the open board: \(Self.selectedLinks(in: nodes))")
        #expect(nodes.contains { $0.identifier == Self.paneID }, "the board opens in the trailing pane")
        #expect(!nodes.contains { $0.identifier == "fst.song-band-leaderboard.header" }, "no repeated song header")
    }

    /// Pressing the selected band's row opens the Duos board at the band's page in the
    /// pane and selects the row, not the plain Duos button.
    @Test func pressingTheBandRowOpensItsPageInThePaneAndSelectsIt() async throws {
        let hosted = try await Self.hostSplit()
        defer { hosted.close() }
        try Self.press(Self.jumpRowID, in: hosted.host)
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            Self.selectedLinks(in: macAccessibilityTree(hosted.host)) == [Self.jumpRowID]
        }
        let nodes = macAccessibilityTree(hosted.host)
        #expect(Self.selectedLinks(in: nodes) == [Self.jumpRowID])
        #expect(nodes.contains { $0.identifier == Self.paneID }, "the board stays in the trailing pane")
        #expect(nodes.contains {
            $0.isElement && $0.identifier.hasPrefix("fst.song-band-leaderboard.row.fixture-band-fixture-player-1")
        }, "the pane shows the band's own row")
    }

    // MARK: - Reading order and target size

    /// Song Detail's Duos section reads its heading, rows, the selected band's row, then
    /// the button, all before the trailing pane, whose first heading is the band size;
    /// both links are at least 44 pt targets in the leading pane, left of the trailing one.
    @Test func linksReadBeforeThePaneWithFullSizeTargets() async throws {
        let hosted = try await Self.hostSplit()
        defer { hosted.close() }
        let tree = macAccessibilityTree(hosted.host, navigationOrder: true)
        macAccessibilityDump(tree, name: "band-split-links-order")
        let pane = try #require(tree.firstIndex { $0.identifier == Self.paneID }, "the trailing pane")
        let paneEnd = tree[(pane + 1)...].firstIndex { $0.depth <= tree[pane].depth } ?? tree.endIndex
        let ids = ["fst.song-detail.band-header.Band_Duets", "fst.song-detail.band-row.Band_Duets.0",
                   Self.jumpRowID, Self.ctaID(.duets)]
        let order = try ids.map { id in
            try #require(tree.firstIndex { $0.identifier == id && $0.isElement }, "\(id) in the order")
        }
        #expect(order == order.sorted(), "heading, rows, the band's row, then the button: \(order)")
        #expect(order.allSatisfy { $0 < pane }, "Song Detail's links read before the trailing pane")
        let inPane = tree[(pane + 1)..<paneEnd].filter(\.isElement)
        #expect(inPane.first { $0.role == "AXHeading" }?.identifier == Self.titleID, "the pane's first heading")

        let paneFrame = try #require(nativeHostedAccessibilityFrame(Self.paneID, in: hosted.host))
        for id in [Self.jumpRowID, Self.ctaID(.duets)] {
            let frame = try #require(nativeHostedAccessibilityFrame(id, in: hosted.host), "\(id) frame")
            #expect(frame.height >= 44 - 0.5 && frame.width >= 44, "\(id) is at least a 44 pt target: \(frame)")
            #expect(frame.maxX <= paneFrame.minX + 0.5, "\(id) sits in the leading pane: \(frame) vs \(paneFrame)")
        }
    }
}
#endif
