#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - Fixtures

/// Answers nothing: the hosted Songs list starts loaded, so any request is unexpected.
private actor ScrollAwayRejectingTransport: HTTPTransport {
    private var paths: [String] = []

    /// Record and refuse every request.
    ///
    /// - Parameter request: Any request the screen tries to send.
    /// - Returns: Never.
    /// - Throws: Always `FestivalAPIError.unavailable`.
    func send(_ request: URLRequest) async throws -> HTTPResult {
        paths.append("\(request.httpMethod ?? "?") \(request.url?.path ?? "")")
        throw FestivalAPIError.unavailable(retryAfter: nil)
    }

    /// Every request the screen tried to send.
    func recordedRequests() -> [String] { paths }
}

/// The words `tools/mock_service.py --large-catalogue` builds its titles from.
private let scrollAwayWords = [
    "Anthem", "Ballad", "Cascade", "Drift", "Echo", "Flare", "Glow", "Horizon", "Ignite",
    "Jubilee", "Kinetic", "Lumen", "Mirage", "Nova", "Orbit", "Prism", "Quartz", "Rhythm",
    "Signal", "Tempo", "Uplift", "Vortex", "Wave", "Xenon", "Yonder", "Zenith",
]

/// An artless catalogue spread over #, A–Z like the mock service's large catalogue, so
/// the Songs list scrolls and shows A–Z section titles.
///
/// - Returns: A validated catalogue observed under publication seven.
/// - Throws: A catalogue the decoder or validation rejects.
private func scrollAwayCatalogue() throws -> CatalogPayload {
    var titles = zip([1, 7, 24, 99], ["Beat", "Nights", "Hours", "Lights"]).map { "\($0) \($1)" }
    for word in scrollAwayWords {
        titles += ["Theory", "Run", "Signal", "Garden"].map { "\(word) \($0)" }
    }
    let songs: [[String: Any]] = titles.enumerated().map { offset, title in
        let index = offset + 1
        return [
            "songId": "fixture-song-\(index)", "title": title,
            "artist": "Synthetic Artist \(index % 17 + 1)", "year": 2000 + index % 27,
            "pathArtifactGenerationId": "fixture-path-generation",
            "difficulty": [
                "guitar": index % 7, "bass": (index + 2) % 7,
                "drums": (index + 4) % 7, "vocals": (index + 1) % 7,
            ],
        ]
    }
    let body: [String: Any] = ["count": songs.count, "currentSeason": 9, "songs": songs]
    let decoded = try JSONDecoder().decode(
        SongsResponse.self, from: JSONSerialization.data(withJSONObject: body)
    )
    try decoded.validate()
    return CatalogPayload(catalog: decoded, publicationId: 7, observedPublicationId: 7, isStale: false)
}

// MARK: - Host

/// The real Songs list over the large catalogue, hosted in an offscreen window.
@MainActor
private struct ScrollAwayHost {
    let host: NSHostingView<NativeHostedRoot<AnyView>>
    let window: NSWindow
    let scroll: NSScrollView
    let transport: ScrollAwayRejectingTransport
    let storage: UserDefaults
    let storageName: String

    /// Host Songs sorted by title (A–Z sections) at a phone-like width.
    ///
    /// Text scaling is covered on iPhone (`SongsChromeJourneyTests`): macOS has no
    /// Dynamic Type, and the hosted List ignores `dynamicTypeSize`.
    ///
    /// - Throws: A failed render or a List that does not scroll.
    init() async throws {
        let storageName = "fst-songs-scroll-away-ax-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: storageName))
        storage.set(true, forKey: "fst.settings.hideShop")
        storage.set(true, forKey: "fst.accessibility.moreContrast")
        storage.set(true, forKey: "fst.accessibility.reduceMotion")
        storage.set(SongSortMode.title.rawValue, forKey: "fst.songs.sortMode")
        storage.set(true, forKey: "fst.songs.sortAscending")
        let transport = ScrollAwayRejectingTransport()
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let size = CGSize(width: 420, height: 760)
        let catalogue = try scrollAwayCatalogue()
        let host = nativeHostedView(
            AnyView(
                NavigationStack {
                    SongsScreen(
                        session: session, initialState: .loaded(catalogue),
                        isVisible: false
                    )
                }
                .defaultAppStorage(storage)
                .preferredColorScheme(.dark)
                .tint(BrandTokens.accentBlue)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityElement("fst.songs.row.fixture-song-1", in: host) != nil
        }
        self.host = host
        self.window = window
        self.scroll = try #require(scrollAwayListScrollView(in: host))
        self.transport = transport
        self.storage = storage
        self.storageName = storageName
    }

    /// Move the List so `offset` points of content sit above its collapsed top, and wait
    /// for the scroll-driven chrome to settle (a feedback loop never settles: issue #5).
    ///
    /// - Parameters:
    ///   - offset: Distance scrolled past the list's top.
    ///   - ready: The state to wait for.
    func scroll(to offset: CGFloat, until ready: @MainActor () -> Bool = { true }) async throws {
        let clip = scroll.contentView
        clip.scroll(to: NSPoint(x: 0, y: offset - scroll.contentInsets.top))
        scroll.reflectScrolledClipView(clip)
        _ = try await nativeHostedSettle(host, timeout: .seconds(60), until: ready)
    }

    /// The accessibility tree in walk (VoiceOver) order.
    func tree(_ name: String) -> [MacAXNode] {
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "songs-scroll-away-\(name)")
        return nodes
    }

    /// Whether the floating section bar is in the accessibility tree.
    var showsSectionBar: Bool {
        nativeHostedAccessibilityElement("fst.songs.section-bar", in: host) != nil
    }

    /// Close the window and drop the test's settings suite.
    func tearDown() {
        window.orderOut(nil)
        storage.removePersistentDomain(forName: storageName)
    }
}

/// The Songs List's scroll view: the deepest one whose content runs well past its height.
@MainActor
private func scrollAwayListScrollView(in view: NSView) -> NSScrollView? {
    for subview in view.subviews {
        if let found = scrollAwayListScrollView(in: subview) { return found }
    }
    if let scroll = view as? NSScrollView, let document = scroll.documentView,
       document.frame.height > scroll.contentView.bounds.height + 400 {
        return scroll
    }
    return nil
}

// MARK: - Tree reading

/// The parts of a Songs tree the scroll-away chrome changes.
private struct ScrollAwayTree {
    let nodes: [MacAXNode]

    /// Elements outside the List (`fst.songs.list`), in walk (VoiceOver) order.
    var outsideList: [MacAXNode] {
        guard let list = nodes.firstIndex(where: { $0.identifier == "fst.songs.list" }) else {
            return nodes.filter(\.isElement)
        }
        let depth = nodes[list].depth
        let end = nodes[(list + 1)...].firstIndex { $0.depth <= depth } ?? nodes.endIndex
        return (nodes[..<list] + nodes[end...]).filter(\.isElement)
    }

    /// Elements inside the List, in walk order.
    var insideList: [MacAXNode] {
        guard let list = nodes.firstIndex(where: { $0.identifier == "fst.songs.list" }) else { return [] }
        let depth = nodes[list].depth
        let end = nodes[(list + 1)...].firstIndex { $0.depth <= depth } ?? nodes.endIndex
        // Unnamed hosting-view groups wrap every cell; VoiceOver reads the content inside.
        return nodes[(list + 1)..<end].filter { $0.isElement && !$0.identifier.isEmpty }
    }

    /// The floating section bar's nodes (exactly one while scrolled, none at the top).
    var sectionBar: [MacAXNode] { nodes.filter { $0.identifier == "fst.songs.section-bar" } }

    /// Index of the first element inside the List, in walk order.
    var firstListElement: Int? {
        guard let list = nodes.firstIndex(where: { $0.identifier == "fst.songs.list" }) else { return nil }
        return nodes[(list + 1)...].firstIndex(where: \.isElement)
    }

    /// Role, name and identifier of every List element, for comparing reading order.
    var listSignature: [String] { insideList.map { "\($0.role) '\($0.spokenName)' #\($0.identifier)" } }

    var dump: String { nodes.map(\.description).joined(separator: "\n") }
}

/// The section whose in-list title has reached the floating bar.
///
/// That is the last title whose top has reached the bar's bottom edge. When every title
/// still in the tree is below the bar, the List has recycled the passed ones, so it is
/// the section before the first title left.
///
/// - Parameters:
///   - host: The hosted Songs list.
///   - labels: Section labels in list order.
///   - barBottom: The bar's bottom edge, in host points.
/// - Returns: The label VoiceOver should hear from the bar.
@MainActor
private func scrollAwayCurrentSection(
    in host: NSView, labels: [String], barBottom: CGFloat
) -> String? {
    var passed: String?
    var firstInTree: Int?
    for (index, label) in labels.enumerated() {
        guard let frame = nativeHostedAccessibilityFrame("fst.songs.section.\(index)", in: host) else {
            continue
        }
        firstInTree = firstInTree ?? index
        if frame.minY <= barBottom { passed = label }
    }
    if let passed { return passed }
    guard let firstInTree, firstInTree > 0 else { return nil }
    return labels[firstInTree - 1]
}

// MARK: - Tests

/// Issue #5 (accessibility, #388): the floating section bar is the scroll-away decision
/// VoiceOver can perceive. It enters the tree as one heading once the List leaves its
/// top (> 24 pt), stays through small drags back towards the top (hysteresis down to
/// 8 pt, so VoiceOver never sees it flicker), and leaves at the top, where the List reads
/// exactly as it did before scrolling. A feedback loop between the chrome and the
/// decision never settles, so every step here would time out instead.
@MainActor
@Test func songsSectionBarHeadingFollowsTheScrollAwayDecision() async throws {
    guard SongsScreen.usesSectionBar else { return }
    let songs = try await ScrollAwayHost()
    defer { songs.tearDown() }
    let initial = ScrollAwayTree(nodes: songs.tree("top"))
    #expect(initial.sectionBar.isEmpty, "bar shown at the top:\n\(initial.dump)")
    let first = try #require(initial.insideList.first, "\(initial.dump)")
    #expect(first.role == "AXHeading" && first.spokenName == "#" && first.identifier == "fst.songs.section.0")
    #expect(initial.insideList.dropFirst().first?.identifier == "fst.songs.row.fixture-song-1")
    #expect(macAccessibilityFindings(initial.nodes).isEmpty, "\(macAccessibilityFindings(initial.nodes))")

    // Offsets past the List's top, and whether the bar should be in the tree after each.
    let path: [(offset: CGFloat, scrolled: Bool)] = [
        (30, true), (6, false), (26, true), (10, true), (20, true), (4, false), (12, false), (0, false),
    ]
    for step in path {
        try await songs.scroll(to: step.offset) { songs.showsSectionBar == step.scrolled }
        let tree = ScrollAwayTree(nodes: songs.tree("offset-\(Int(step.offset))"))
        let bar = tree.sectionBar
        #expect(bar.count == (step.scrolled ? 1 : 0), "offset \(step.offset):\n\(tree.dump)")
        if step.scrolled, let heading = bar.first {
            #expect(heading.role == "AXHeading" && heading.isElement, "\(heading)")
            #expect(heading.spokenName == "#", "offset \(step.offset): \(heading)")
        }
    }
    let restored = ScrollAwayTree(nodes: songs.tree("restored"))
    #expect(restored.sectionBar.isEmpty)
    #expect(restored.listSignature == initial.listSignature, "reading order changed:\n\(restored.dump)")
    #expect(await songs.transport.recordedRequests().isEmpty)
}

/// Issue #5 (accessibility, #388): scrolled away, VoiceOver meets the current section
/// once as a heading before the rows (the floating bar), the outgoing and incoming copies
/// the bar animates stay hidden, each in-list title keeps its heading in place, and the
/// rows under the bar remain named buttons at least 44 pt tall (HIG Accessibility).
@MainActor
@Test func songsSectionBarNamesTheCurrentSectionOnceBeforeTheRows() async throws {
    guard SongsScreen.usesSectionBar else { return }
    let songs = try await ScrollAwayHost()
    defer { songs.tearDown() }
    let labels = ["#"] + scrollAwayWords.map { String($0.prefix(1)) }
    var offset: CGFloat = 0
    for target: CGFloat in [600, 1200] {
        // Scroll the way a person does, in steps shorter than a title's passing band
        // (title height plus the bar): a jump past a title the List recycles before it
        // reports passing leaves the bar a section behind (issue #297), which only the
        // rail and Quick Links correct.
        while offset < target {
            offset = min(offset + 20, target)
            try await songs.scroll(to: offset) { offset <= 24 || songs.showsSectionBar }
        }
        let tree = ScrollAwayTree(nodes: songs.tree("scrolled-\(Int(target))"))
        let bar = try #require(tree.sectionBar.first, "\(tree.dump)")
        let barFrame = try #require(nativeHostedAccessibilityFrame("fst.songs.section-bar", in: songs.host))
        let current = scrollAwayCurrentSection(in: songs.host, labels: labels, barBottom: barFrame.maxY)
        #expect(tree.sectionBar.count == 1)
        #expect(bar.role == "AXHeading" && bar.isElement && bar.spokenName == current, "\(bar) vs \(String(describing: current))")
        // One heading outside the List: the bar's leaving and incoming copies are hidden.
        let outside = tree.outsideList.filter { $0.role == "AXHeading" }
        #expect(outside.map(\.identifier) == ["fst.songs.section-bar"], "\(tree.dump)")
        // Read before the rows.
        let barIndex = try #require(tree.nodes.firstIndex { $0.identifier == "fst.songs.section-bar" })
        #expect(barIndex < (tree.firstListElement ?? .max), "bar read after the rows:\n\(tree.dump)")
        // The in-list title the bar repeats is still a heading where it starts its rows.
        let inList = tree.insideList.filter { $0.role == "AXHeading" }
        #expect(inList.contains { $0.spokenName == current }, "in-list \(String(describing: current)) lost")
        #expect(inList.allSatisfy { $0.identifier.hasPrefix("fst.songs.section.") && !$0.spokenName.isEmpty })
        // Rows in view stay named buttons with a full-size target.
        let visible = tree.insideList.filter { $0.identifier.hasPrefix("fst.songs.row.") }.compactMap { row in
            nativeHostedAccessibilityFrame(row.identifier, in: songs.host).map { (row, $0) }
        }.filter { $0.1.maxY > barFrame.maxY && $0.1.minY < songs.host.bounds.height }
        #expect(visible.count >= 5, "\(visible.count) rows in view")
        for (row, frame) in visible {
            #expect(row.role == "AXButton" && !row.spokenName.isEmpty, "\(row)")
            #expect(frame.height >= 44, "\(row.identifier) is \(frame.height) pt tall")
        }
        #expect(macAccessibilityFindings(tree.nodes).isEmpty, "\(macAccessibilityFindings(tree.nodes))")
    }
}
#endif
