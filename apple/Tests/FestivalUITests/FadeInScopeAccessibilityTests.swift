#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Page fade window accessibility (issue #30, backfilled by #405)

// #30 gave every lazily built Apple page one first-load fade window,
// ``FestivalFadeInScope`` (`Common/FadeInOnLoad.swift`): only what is on screen at load
// fades in, a scroll during that entrance rushes it, and once it is over cards built by
// scrolling appear at once (pattern `load-transition` R5, R6). Song Detail's instrument
// and band cards were the reported case. These hosted checks (macOS host, `apple-ci`)
// pin what the window exposes to VoiceOver, Voice Control and Dynamic Type on every
// Apple platform, since it is the same SwiftUI on iPhone, iPad, iPhone Duo and Mac:
// content still waiting for its fade stays out of the tree, a scroll releases it, the
// shown page reads heading first and cards in visual order as named 44 pt buttons,
// cards scrolled into view are named, pressable and drawn at once (never hidden behind
// a replayed fade), Reduce Motion (system or in-app) shows everything at once, and AX5
// text grows whole on faded and scrolled-in cards alike.

// MARK: - Fixture

/// Presses the fixture's cards record, in order.
@MainActor
final class FadeScopeA11yPresses {
    private(set) var cards: [Int] = []

    func press(_ card: Int) { cards.append(card) }
}

/// The item-fade curve below a hosted page (``SwiftUICore/EnvironmentValues/festivalFadeInItemCurve``).
///
/// The load plays the web curve; before a scroll the test swaps in ``slow``, so any
/// fade a scroll replays stays nearly transparent through a normal settle and the
/// rendered card proves no fade started, independent of when the capture lands.
@MainActor @Observable
final class FadeScopeA11yCurve {
    /// A fade too slow to pass the ink threshold within the test (60 s, linear).
    static let slow: Animation = .linear(duration: 60)

    var curve: Animation?
}

/// Applies a ``FadeScopeA11yCurve`` to its content.
struct FadeScopeA11yCurveHost<Content: View>: View {
    let curve: FadeScopeA11yCurve
    @ViewBuilder let content: Content

    var body: some View {
        content.environment(\.festivalFadeInItemCurve, curve.curve)
    }
}

/// A page shaped like Song Detail: a hero heading, one section and a lazy two-column
/// grid of tall card buttons running well past the first screen, every block fading
/// with the page's stagger inside one page scope (Song Detail's `loadedScroll`).
struct FadeScopeA11yPage: View {
    let scope: FestivalFadeInScope
    let presses: FadeScopeA11yPresses

    static let cardCount = 40
    static let cardHeight: CGFloat = 160
    static let heading = "Fixture Song With A Long Encore Title"
    static let headingID = "fst.fade-a11y.heading"
    static let sectionID = "fst.fade-a11y.section"
    /// HIG Accessibility: iOS, iPadOS default control size 44×44 pt.
    static let minimumTarget: CGFloat = 44

    /// The identifier of card `index`.
    static func cardID(_ index: Int) -> String { "fst.fade-a11y.card.\(index)" }

    /// The spoken name of card `index`.
    static func cardName(_ index: Int) -> String { "Card \(index + 1) leaderboard" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ReloadGateA11yText(text: Self.heading, style: .title2)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(Self.headingID)
                    .festivalFadeIn(isLoaded: true, index: 0)
                ReloadGateA11yText(text: "Intensity", style: .body)
                    .foregroundStyle(.white)
                    .accessibilityIdentifier(Self.sectionID)
                    .festivalFadeIn(isLoaded: true, index: 1)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(0..<Self.cardCount, id: \.self) { index in
                        Button { presses.press(index) } label: {
                            ReloadGateA11yText(text: Self.cardName(index), style: .body)
                                .foregroundStyle(.white)
                                .padding(12)
                                .frame(maxWidth: .infinity, minHeight: Self.cardHeight, alignment: .topLeading)
                                .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier(Self.cardID(index))
                        // Song Detail's card stagger: after the hero, Intensity and Score History.
                        .festivalFadeIn(isLoaded: true, index: index + 3)
                    }
                }
            }
            .padding(16)
            .modifier(FestivalFadeInScopeModifier(provided: scope, resetKey: nil))
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Tests

/// Accessibility of the page fade window #30 added (``FestivalFadeInScope``).
///
/// HIG VoiceOver: "be sure to keep labels current as interface and content change" and
/// "Use titles and headings to convey hierarchy"; HIG Motion: "Make motion optional:
/// never make it the only way to communicate important information"; HIG
/// Accessibility: "When Reduce Motion is on, reduce automatic and repetitive
/// animation", controls at least 44×44 pt, and text enlargement "of at least 200%".
@MainActor
@Suite(.serialized)
struct FadeInScopeAccessibilityTests {
    typealias Motion = ReloadGateAccessibilityTests.Motion

    /// One hosted page.
    @MainActor
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow
        let scope: FestivalFadeInScope
        let presses: FadeScopeA11yPresses
        let curve: FadeScopeA11yCurve
        let storage: UserDefaults
        let suiteName: String

        func close() {
            window.orderOut(nil)
            storage.removePersistentDomain(forName: suiteName)
        }

        /// What VoiceOver reaches now, after one layout pass (no waiting, so no timed
        /// step runs).
        func reachable() -> [MacAXNode] {
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            return ReloadGateAccessibilityTests.reachable(host)
        }
    }

    /// Host the fixture page on a phone-sized window.
    ///
    /// - Parameters:
    ///   - typeSize: Dynamic Type size for the page.
    ///   - motion: Fade and Reduce Motion settings.
    /// - Returns: The host, its window and the page's scope; the first load is running.
    static func host(typeSize: DynamicTypeSize = .large, motion: Motion = .animated) throws -> Hosted {
        let suiteName = "fst-fade-scope-a11y-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(motion == .appReduceMotion, forKey: "fst.accessibility.reduceMotion")
        let scope = FestivalFadeInScope()
        let presses = FadeScopeA11yPresses()
        let curve = FadeScopeA11yCurve()
        let size = CGSize(width: 390, height: 700)
        let host = nativeHostedView(
            AnyView(
                FadeScopeA11yCurveHost(curve: curve) { FadeScopeA11yPage(scope: scope, presses: presses) }
                    .environment(\.festivalFadeInEnabled, motion != .instant)
                    .environment(\._accessibilityReduceMotion, motion == .systemReduceMotion)
                    .environment(\.dynamicTypeSize, typeSize)
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        return Hosted(
            host: host, window: nativeHostedWindow(host, size: size), scope: scope, presses: presses,
            curve: curve, storage: storage, suiteName: suiteName
        )
    }

    /// The fixture's own elements in `nodes` (heading, section, cards), in reading order.
    static func elements(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.identifier.hasPrefix("fst.fade-a11y.") }
    }

    /// The card indexes in `nodes`, in reading order.
    static func cards(_ nodes: [MacAXNode]) -> [Int] {
        nodes.compactMap { node in
            node.identifier.hasPrefix("fst.fade-a11y.card.")
                ? Int(node.identifier.dropFirst("fst.fade-a11y.card.".count)) : nil
        }
    }

    static func dump(_ nodes: [MacAXNode]) -> String {
        nodes.map(\.description).joined(separator: "\n")
    }

    /// The page's scroll view: the deepest one whose content runs past its height.
    static func scrollView(in view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let found = scrollView(in: subview) { return found }
        }
        if let scroll = view as? NSScrollView, let document = scroll.documentView,
           document.frame.height > scroll.contentView.bounds.height + 100 {
            return scroll
        }
        return nil
    }

    /// Scroll `host`'s page so `offset` points of content sit above its top (clamped to
    /// the content), then lay it out once: no timed step runs.
    static func scroll(_ host: NSView, to offset: CGFloat, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let scroll = try #require(scrollView(in: host), "the page scrolls", sourceLocation: sourceLocation)
        let clip = scroll.contentView
        let document = try #require(scroll.documentView, sourceLocation: sourceLocation)
        let maximum = max(0, document.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: min(max(offset, 0), maximum) - scroll.contentInsets.top))
        scroll.reflectScrolledClipView(clip)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
    }

    /// Wait until the first screen has been revealed (heading, section and every card
    /// built so far in the tree), then until every fade the load scheduled has ended,
    /// so the next scroll closes the window rather than rushing it.
    static func settleLoad(_ hosted: Hosted, sourceLocation: SourceLocation = #_sourceLocation) async throws {
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30), sourceLocation: sourceLocation) {
            let ids = Set(elements(macAccessibilityTree(hosted.host)).map(\.identifier))
            return ids.contains(FadeScopeA11yPage.headingID) && ids.contains(FadeScopeA11yPage.cardID(5))
        }
        // The stagger tail (8 × 125 ms) plus one fade: the clock the scope schedules by.
        try await Task.sleep(for: .seconds(FestivalFadeIn.completionDelay(itemCount: FestivalFadeIn.maxStaggeredItems) + 0.3))
        _ = try await nativeHostedSettle(hosted.host, timeout: .seconds(30), sourceLocation: sourceLocation)
    }

    /// Expect card `index` to be a named button VoiceOver reaches now, a 44×44 pt target
    /// wholly on the page, and pressable through accessibility.
    static func expectReadyCard(
        _ hosted: Hosted, _ index: Int, in nodes: [MacAXNode], _ context: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let id = FadeScopeA11yPage.cardID(index)
        guard let node = nodes.first(where: { $0.identifier == id }) else {
            Issue.record("\(context): card \(index) is not in the tree:\n\(dump(elements(nodes)))", sourceLocation: sourceLocation)
            return
        }
        #expect(node.role == "AXButton", "\(context): \(node)", sourceLocation: sourceLocation)
        #expect(node.spokenName == FadeScopeA11yPage.cardName(index), "\(context): \(node)", sourceLocation: sourceLocation)
        let frame = try #require(nativeHostedAccessibilityFrame(id, in: hosted.host), sourceLocation: sourceLocation)
        let minimum = FadeScopeA11yPage.minimumTarget - 0.5
        #expect(frame.width >= minimum && frame.height >= minimum,
                "\(context): card \(index) is a 44×44 pt target: \(frame)", sourceLocation: sourceLocation)
        #expect(hosted.host.bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame),
                "\(context): card \(index) lies wholly on the page: \(frame)", sourceLocation: sourceLocation)
        let element = try #require(nativeHostedAccessibilityElement(id, in: hosted.host), sourceLocation: sourceLocation)
        let press = NSSelectorFromString("accessibilityPerformPress")
        #expect(element.responds(to: press), "\(context): card \(index) is pressable", sourceLocation: sourceLocation)
        let before = hosted.presses.cards.count
        _ = element.perform(press)
        #expect(hosted.presses.cards.dropFirst(before) == [index],
                "\(context): pressing card \(index) through accessibility activates it", sourceLocation: sourceLocation)
    }

    /// Expect the element `id` to be drawn opaque once the page has settled under
    /// ``FadeScopeA11yCurve/slow``: a fade started after the swap would still be almost
    /// transparent, so ink proves none did.
    static func expectDrawnWithoutAFade(
        _ host: NSHostingView<some View>, _ id: String, _ context: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws {
        let ink = try await drawnInk(host, id, context, sourceLocation: sourceLocation)
        #expect(ink >= 8, "\(context): \(id) is drawn without a replayed fade: \(ink) pt of ink",
                sourceLocation: sourceLocation)
    }

    /// The rendered ink height (points) of element `id` once `host` has settled.
    static func drawnInk(
        _ host: NSHostingView<some View>, _ id: String, _ context: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async throws -> CGFloat {
        _ = try await nativeHostedSettle(host, timeout: .seconds(30), sourceLocation: sourceLocation)
        let frame = try #require(nativeHostedAccessibilityFrame(id, in: host), "\(context): \(id) has a frame",
                                 sourceLocation: sourceLocation)
        return try ReloadGateAccessibilityTests.inkHeight(host, in: frame.intersection(host.bounds))
    }

    /// The nodes VoiceOver reads as page content: everything outside AppKit's scroll
    /// bars, whose parts (value indicator, page buttons) belong to the system.
    static func content(_ nodes: [MacAXNode]) -> [MacAXNode] {
        var result: [MacAXNode] = []
        var barDepth: Int?
        for node in nodes {
            if let depth = barDepth, node.depth > depth { continue }
            barDepth = node.role == "AXScrollBar" ? node.depth : nil
            if barDepth == nil { result.append(node) }
        }
        return result
    }

    // MARK: First load

    /// While the load fade runs, content still waiting for its turn is out of the tree
    /// (VoiceOver can't land on an invisible card) and nothing unnamed is exposed. Once
    /// shown, the page reads heading first, then the section, then the cards in visual
    /// order (left to right, top to bottom), each a named button and a 44×44 pt target.
    /// Same at the largest accessibility text size.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func loadFadeKeepsWaitingContentOutOfTheTreeThenReadsInOrder(_ typeSize: DynamicTypeSize) async throws {
        let hosted = try Self.host(typeSize: typeSize)
        defer { hosted.close() }

        // The first update: every block waits for its stagger (≥ 125 ms), so none is
        // reachable yet, and no unnamed stand-in takes its place.
        let waiting = hosted.reachable()
        #expect(Self.elements(waiting).isEmpty, "nothing still waiting to fade is reachable:\n\(Self.dump(waiting))")
        let containers: Set<String> = ["AXGroup", "AXScrollArea", "AXOpaqueProviderGroup"]
        #expect(Self.content(waiting).allSatisfy { !$0.spokenName.isEmpty || containers.contains($0.role) },
                "nothing unnamed:\n\(Self.dump(waiting))")

        try await Self.settleLoad(hosted)
        let shown = Self.elements(hosted.reachable())
        let ids = shown.map(\.identifier)
        #expect(Array(ids.prefix(2)) == [FadeScopeA11yPage.headingID, FadeScopeA11yPage.sectionID],
                "heading, then the section:\n\(Self.dump(shown))")
        let heading = try #require(shown.first)
        #expect(heading.role == "AXHeading" && heading.spokenName == FadeScopeA11yPage.heading, "\(heading)")
        let cards = Self.cards(shown)
        #expect(cards.count >= 2 && cards == Array(0..<cards.count), "cards in page order:\n\(Self.dump(shown))")
        let frames = try cards.map { try #require(nativeHostedAccessibilityFrame(FadeScopeA11yPage.cardID($0), in: hosted.host)) }
        // One row: a card still rising into place sits up to the fade's rise lower.
        let row = FestivalFadeIn.riseDistance + 1
        let visual = frames.indices.sorted { a, b in
            abs(frames[a].minY - frames[b].minY) > row ? frames[a].minY < frames[b].minY : frames[a].minX < frames[b].minX
        }
        #expect(visual == Array(frames.indices), "reading order follows the grid's visual order: \(frames)")
        for card in cards where frames[card].maxY <= hosted.host.bounds.maxY {
            try Self.expectReadyCard(hosted, card, in: shown, "\(typeSize) shown")
        }
    }

    /// A scroll while the load fade runs (a VoiceOver three-finger swipe, a Quick Links
    /// jump) rushes it: the content still waiting joins the tree at once, in order, rather
    /// than finishing its stagger first.
    @Test func aScrollDuringTheLoadFadeReleasesWaitingContent() async throws {
        let hosted = try Self.host()
        defer { hosted.close() }
        #expect(Self.elements(hosted.reachable()).isEmpty)

        try Self.scroll(hosted.host, to: 120)
        #expect(hosted.scope.isRushed, "the scroll rushed the page's entrance")
        try await nativeHostedSettle(hosted.host, timeout: .seconds(30)) {
            Set(Self.cards(macAccessibilityTree(hosted.host))).isSuperset(of: 0...5)
        }
        let shown = Self.elements(hosted.reachable())
        #expect(shown.first?.identifier == FadeScopeA11yPage.headingID, "\(Self.dump(shown))")
        let cards = Self.cards(shown)
        #expect(cards == Array(0..<cards.count), "cards in page order:\n\(Self.dump(shown))")
    }

    // MARK: Scrolling after the load (the #30 change)

    /// Once the load fade is over, cards scrolled into view are named, pressable 44 pt
    /// buttons in the scroll's own update and are drawn without a fade, and so are the
    /// first cards on the way back: the window has closed, so nothing replays a fade that would
    /// hide a card from VoiceOver or Voice Control while it shows. Same with system or
    /// in-app Reduce Motion, and at AX5, where the cards' text still grows whole.
    @Test(arguments: [
        (Motion.animated, DynamicTypeSize.large), (.animated, .accessibility5),
        (.systemReduceMotion, .large), (.appReduceMotion, .large),
    ])
    func cardsScrolledIntoViewAreReadyAtOnce(_ motion: Motion, _ typeSize: DynamicTypeSize) async throws {
        let hosted = try Self.host(typeSize: typeSize, motion: motion)
        defer { hosted.close() }
        if motion != .animated {
            // Reduce Motion: the first screen is in the tree in the very first update.
            let first = Self.elements(hosted.reachable()).map(\.identifier)
            #expect(Array(first.prefix(3)) == [FadeScopeA11yPage.headingID, FadeScopeA11yPage.sectionID, FadeScopeA11yPage.cardID(0)],
                    "\(motion) shows the page at once: \(first)")
        }
        try await Self.settleLoad(hosted)
        hosted.curve.curve = FadeScopeA11yCurve.slow

        let last = FadeScopeA11yPage.cardCount - 1
        let built = Self.cards(macAccessibilityTree(hosted.host))
        #expect(!built.contains(last - 1) && !built.contains(last),
                "the last cards are built by the scroll, not the load: \(built)")
        try Self.scroll(hosted.host, to: .greatestFiniteMagnitude)
        #expect(!hosted.scope.isOpen, "\(motion): a scroll after the load closes the window")
        // The scroll's own update: VoiceOver and Voice Control reach the new cards now.
        let bottom = hosted.reachable()
        for card in [last - 1, last] {
            try Self.expectReadyCard(hosted, card, in: bottom, "\(motion) \(typeSize) scrolled down")
        }
        let cards = Self.cards(bottom)
        #expect(cards == cards.sorted(), "cards stay in page order: \(cards)")
        for card in [last - 1, last] {
            try await Self.expectDrawnWithoutAFade(hosted.host, FadeScopeA11yPage.cardID(card), "\(motion) \(typeSize) scrolled down")
        }
        if typeSize.isAccessibilitySize {
            for card in [last - 1, last] {
                let frame = try #require(nativeHostedAccessibilityFrame(FadeScopeA11yPage.cardID(card), in: hosted.host))
                let needed = ReloadGateAccessibilityTests.idealSize(
                    FadeScopeA11yPage.cardName(card), .body, typeSize, width: frame.width - 24
                )
                #expect(frame.height >= needed.height + 24 - 0.5, "card \(card) shows its AX5 text whole: \(frame) for \(needed)")
                let ink = try ReloadGateAccessibilityTests.inkHeight(hosted.host, in: frame)
                let largeLine = ReloadGateA11yText.points(.body, .large)
                #expect(ink > largeLine * 1.35, "card \(card)'s text grows at AX5: \(ink) pt of ink")
            }
        }

        try Self.scroll(hosted.host, to: 0)
        let top = hosted.reachable()
        #expect(Self.elements(top).first?.identifier == FadeScopeA11yPage.headingID, "\(Self.dump(Self.elements(top)))")
        try Self.expectReadyCard(hosted, 0, in: top, "\(motion) \(typeSize) scrolled back")
        try await Self.expectDrawnWithoutAFade(hosted.host, FadeScopeA11yPage.cardID(0), "\(motion) \(typeSize) scrolled back")
    }

    // MARK: A real page

    /// Song Detail (the page #30 reported) over the loopback fixture: once its load
    /// fade is over, scrolling to the end puts the Duos, Trios and Quads headings in the
    /// tree in the scroll's own update and draws them without a replayed fade, with the
    /// hero title still the page's first heading and every heading in page order.
    @Test func songDetailCardsScrolledIntoViewAreReadyAtOnce() async throws {
        let baseURL = try await RivalsMockService.shared.baseURL()
        let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
        let suiteName = "fst.tests.fade-scope-a11y.\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: suiteName))
        defer { storage.removePersistentDomain(forName: suiteName) }
        let identity = ["accountId": "fixture-player-1", "displayName": "Fixture Player 1"]
        storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
        let visible: [Instrument] = [.lead, .bass, .drums, .vocals]
        for name in ["Lead", "Bass", "Drums", "Vocals", "ProLead", "ProBass", "Karaoke", "ProCymbals", "ProDrums"] {
            storage.set(["Lead", "Bass", "Drums", "Vocals"].contains(name), forKey: "fst.settings.show\(name)")
        }
        let session = FestivalSession(factory: { client }, selectionStorage: storage)
        let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
        let size = CGSize(width: 402, height: 700)
        let curve = FadeScopeA11yCurve()
        let host = nativeHostedView(
            AnyView(
                FadeScopeA11yCurveHost(curve: curve) { NavigationStack { SongDetailScreen(song: song, session: session) } }
                    .defaultAppStorage(storage)
                    .preferredColorScheme(.dark)
                    .environment(\.festivalFadeInEnabled, true)
                    .environment(\._accessibilityReduceMotion, false)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }

        let leadHeader = "fst.song-detail.card-header.\(Instrument.lead.rawValue)"
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            let ids = Set(macAccessibilityTree(host).map(\.identifier))
            return ids.contains("fst.song-detail.hero-title") && ids.contains(leadHeader)
        }
        // The page's own scope is out of reach, so the wait for its load fade to end is
        // timed: on a host starved past that (the parallel bundle) the scroll may still
        // rush the load, which fades rows on purpose. `apple-ci` reruns this alone.
        var load = NativeHostedEvidenceDeadline(limit: .seconds(60))
        try await load.awaitResponsiveMainActor()
        try await load.sleep(for: .seconds(FestivalFadeIn.completionDelay(itemCount: FestivalFadeIn.maxStaggeredItems) + 0.3))
        _ = try await nativeHostedSettle(host, timeout: .seconds(30))
        try await load.awaitResponsiveMainActor()

        curve.curve = FadeScopeA11yCurve.slow
        try Self.scroll(host, to: .greatestFiniteMagnitude)
        let nodes = ReloadGateAccessibilityTests.reachable(host)
        for band in BandType.allCases {
            let header = nodes.first { $0.identifier == "fst.song-detail.band-header.\(band.rawValue)" }
            #expect(header?.role == "AXHeading" && header?.spokenName.contains(band.label) == true,
                    "\(band.label)'s heading is reachable at once: \(String(describing: header))\n\(Self.dump(nodes))")
        }
        let onPage = BandType.allCases.map { "fst.song-detail.band-header.\($0.rawValue)" }.filter { id in
            nativeHostedAccessibilityFrame(id, in: host).map(host.bounds.contains) == true
        }
        #expect(!onPage.isEmpty, "the scroll brings a band heading onto the page")
        for id in onPage {
            let ink = try await Self.drawnInk(host, id, "Song Detail scrolled down")
            let expectDrawn = { #expect(ink >= 8, "\(id) is drawn without a replayed fade: \(ink) pt of ink") }
            if let starved = load.starved {
                withKnownIssue("Starved host (\(starved)): the scroll may have rushed the load", isIntermittent: true) {
                    expectDrawn()
                }
            } else {
                expectDrawn()
            }
        }
        let headings = nodes.filter { $0.role == "AXHeading" }.map(\.identifier)
        #expect(headings.first == "fst.song-detail.hero-title", "the hero title is the first heading: \(headings)")
        let expected = ["fst.song-detail.hero-title"]
            + visible.map { "fst.song-detail.card-header.\($0.rawValue)" }
            + BandType.allCases.map { "fst.song-detail.band-header.\($0.rawValue)" }
        #expect(headings.filter(expected.contains) == expected, "headings in page order: \(headings)")
    }
}
#endif
