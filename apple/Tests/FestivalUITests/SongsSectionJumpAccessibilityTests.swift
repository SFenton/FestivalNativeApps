#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// Issue #451 (accessibility for #286): a jump from the A–Z index or Quick Links on the
// Songs `List` lands with the section's heading and first rows in view, below the
// floating section bar, and VoiceOver hears where it landed. #286 made the List jumps
// land through `ListScrollNudger` and measured Quick Links' activation line from the
// List's top inset; `QuickLinksLandingAccessibilityTests` covers the `ScrollView`
// pages. Text scaling is covered on iPhone and iPad
// (`SongsChromeJourneyTests/testSectionJumpIsAccessibleAtLargestText`): macOS has no
// Dynamic Type, and the hosted List ignores `dynamicTypeSize`.

// MARK: - Host

/// Accessibility settings a jump case runs under.
struct SongsJumpCase: CustomTestStringConvertible, Sendable {
    let name: String
    /// System and app Reduce Motion, system and app Reduce Transparency, and the app's
    /// Increase Contrast together.
    let reduced: Bool

    var testDescription: String { name }

    static let all = [
        SongsJumpCase(name: "default", reduced: false),
        SongsJumpCase(name: "reduce motion, transparency and more contrast", reduced: true),
    ]
}

/// The real Songs screen, loaded from a synthetic catalogue, above the iPhone floating
/// page tools that host its tools (Quick Links; issue #92).
@MainActor
private struct SongsJumpHost {
    let host: NSHostingView<NativeHostedRoot<AnyView>>
    let window: NSWindow
    let registry: PageToolsRegistry
    let transport: ScrollAwayRejectingTransport
    let storage: UserDefaults
    let storageName: String

    /// Host Songs at a phone-like width.
    ///
    /// - Parameters:
    ///   - sort: The saved sort: Title shows the A–Z index, Year shows decade Quick Links.
    ///   - jumpCase: The accessibility settings.
    /// - Throws: A failed render.
    init(sort: SongSortMode, _ jumpCase: SongsJumpCase) async throws {
        let storageName = "fst-songs-jump-ax-\(UUID().uuidString)"
        let storage = try #require(UserDefaults(suiteName: storageName))
        storage.set(true, forKey: "fst.settings.hideShop")
        storage.set(sort.rawValue, forKey: "fst.songs.sortMode")
        storage.set(true, forKey: "fst.songs.sortAscending")
        for key in ["reduceMotion", "lessTransparency", "moreContrast"] {
            storage.set(jumpCase.reduced, forKey: "fst.accessibility.\(key)")
        }
        let transport = ScrollAwayRejectingTransport()
        let client = try FestivalAPI(transport: transport)
        let session = FestivalSession(factory: { client })
        let registry = PageToolsRegistry()
        let size = CGSize(width: 420, height: 760)
        let catalogue = try scrollAwayCatalogue()
        let host = nativeHostedView(AnyView(
            VStack(spacing: 0) {
                NavigationStack {
                    SongsScreen(session: session, initialState: .loaded(catalogue), isVisible: false)
                        .pageToolsScope(inSelectedTab: true)
                }
                FloatingPageToolsBar(registry: registry)
                    .frame(height: FloatingPageToolsFit.reservedHeight)
                    .buttonStyle(.borderless)
            }
            .environment(\.pageToolsRegistry, registry)
            .environment(\.festivalSession, session)
            // The GitHub macOS runner reports Reduce Transparency on; pin both.
            .environment(\._accessibilityReduceMotion, jumpCase.reduced)
            .environment(\._accessibilityReduceTransparency, jumpCase.reduced)
            .defaultAppStorage(storage)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .tint(BrandTokens.accentBlue)
        ), size: size)
        let window = nativeHostedWindow(host, size: size)
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            nativeHostedAccessibilityElement("fst.songs.row.fixture-song-1", in: host) != nil
        }
        self.host = host
        self.window = window
        self.registry = registry
        self.transport = transport
        self.storage = storage
        self.storageName = storageName
    }

    /// The accessibility tree in VoiceOver's navigation order.
    func tree(_ name: String) -> [MacAXNode] {
        let nodes = macAccessibilityTree(host, navigationOrder: true)
        macAccessibilityDump(nodes, name: "songs-jump-\(name)")
        return nodes
    }

    /// The node with an identifier, if it is in the tree.
    func node(_ identifier: String) -> MacAXNode? {
        macAccessibilityTree(host).first { $0.identifier == identifier }
    }

    /// Wait for the jump to settle on a section.
    ///
    /// - Parameters:
    ///   - label: The landed section's spoken label.
    ///   - heading: The landed section's in-list heading identifier.
    func settle(on label: String, heading: String) async throws {
        _ = try await nativeHostedSettle(host, timeout: .seconds(60)) {
            node("fst.songs.section-bar")?.spokenName == label
                && nativeHostedAccessibilityFrame(heading, in: host) != nil
        }
    }

    /// Close the window and drop the test's settings suite.
    func tearDown() {
        window.orderOut(nil)
        storage.removePersistentDomain(forName: storageName)
    }
}

// MARK: - Landing checks

/// Expect a settled jump to read as landed on a section: one floating section-bar heading
/// naming it, read before the List; the section's own heading in view at the bar's line;
/// and its first row the first element below the bar, a named button at least 44 pt tall
/// and not under the bar (the #286 symptom). Every row in view is a named, full-size button.
///
/// - Parameters:
///   - songs: The host.
///   - label: The landed section's spoken label.
///   - heading: The landed section's in-list heading identifier.
///   - firstRow: Whether a row's spoken name belongs to the landed section.
///   - step: Name for the tree dump.
@MainActor
private func expectLanded(
    _ songs: SongsJumpHost, on label: String, heading: String,
    firstRow: (String) -> Bool, step: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let nodes = songs.tree(step)
    let dump = nodes.map(\.description).joined(separator: "\n")
    let bars = nodes.filter { $0.identifier == "fst.songs.section-bar" }
    #expect(bars.count == 1, "\(step): one section bar\n\(dump)", sourceLocation: sourceLocation)
    let bar = try #require(bars.first, sourceLocation: sourceLocation)
    #expect(bar.role == "AXHeading" && bar.isElement && bar.spokenName == label,
            "\(step): bar \(bar)", sourceLocation: sourceLocation)
    let barIndex = try #require(nodes.firstIndex { $0.identifier == "fst.songs.section-bar" })
    let listIndex = try #require(nodes.firstIndex { $0.identifier == "fst.songs.list" })
    #expect(barIndex < listIndex, "\(step): bar read after the rows\n\(dump)", sourceLocation: sourceLocation)

    let barFrame = try #require(nativeHostedAccessibilityFrame("fst.songs.section-bar", in: songs.host))
    let listFrame = try #require(nativeHostedAccessibilityFrame("fst.songs.list", in: songs.host))
    let landed = try #require(nodes.first { $0.identifier == heading }, "\(step): \(heading)\n\(dump)",
                              sourceLocation: sourceLocation)
    let landedFrame = try #require(nativeHostedAccessibilityFrame(heading, in: songs.host))
    #expect(landed.role == "AXHeading" && landed.spokenName == label, "\(step): \(landed)",
            sourceLocation: sourceLocation)
    // Lands flush where it pins (#298 superseded #286's 30 pt offset): the bar repeats it.
    #expect(abs(landedFrame.minY - barFrame.minY) <= 2, "\(step): heading \(landedFrame) bar \(barFrame)",
            sourceLocation: sourceLocation)

    // Elements below the bar, in reading (top-to-bottom) order. The List's cell order in
    // the tree follows recycling, not position, after a far jump.
    let inView = nodes.filter { $0.isElement && $0.identifier.hasPrefix("fst.songs.") }
        .compactMap { node in nativeHostedAccessibilityFrame(node.identifier, in: songs.host).map { (node, $0) } }
        .filter { $0.1.minY >= barFrame.maxY - 0.5 && $0.1.minY < listFrame.maxY
            && $0.0.identifier != "fst.songs.section-index" }
        .sorted { $0.1.minY < $1.1.minY }
    let first = try #require(inView.first, "\(step): nothing below the bar\n\(dump)", sourceLocation: sourceLocation)
    #expect(first.0.role == "AXButton" && firstRow(first.0.spokenName),
            "\(step): first below the bar is \(first.0)", sourceLocation: sourceLocation)
    #expect(first.1.minY - barFrame.maxY < 16, "\(step): gap above the first row \(first.1) bar \(barFrame)",
            sourceLocation: sourceLocation)
    let rows = inView.filter { $0.0.identifier.hasPrefix("fst.songs.row.") && $0.1.maxY <= listFrame.maxY }
    #expect(rows.count >= 5, "\(step): \(rows.count) whole rows in view", sourceLocation: sourceLocation)
    for (row, frame) in rows {
        #expect(row.role == "AXButton" && !row.spokenName.isEmpty, "\(row)", sourceLocation: sourceLocation)
        #expect(frame.height >= 44, "\(row.identifier) is \(frame.height) pt tall", sourceLocation: sourceLocation)
    }
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(step): \(macAccessibilityFindings(nodes))",
            sourceLocation: sourceLocation)
}

/// Expect the last section, too short to reach the bar's line once the List bottoms out,
/// to be fully in view below the bar: its heading, then all of its rows.
///
/// - Parameters:
///   - songs: The host.
///   - index: The A–Z index element.
///   - label: The last section's label.
///   - heading: Its in-list heading identifier.
@MainActor
private func expectEndLanded(
    _ songs: SongsJumpHost, index: NSObject, label: String, heading: String,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws {
    try await nativeHostedSettle(songs.host, timeout: .seconds(60)) {
        sectionIndexValue(index) == label && nativeHostedAccessibilityFrame(heading, in: songs.host) != nil
    }
    let nodes = songs.tree("az-end-\(label)")
    let dump = nodes.map(\.description).joined(separator: "\n")
    let barFrame = try #require(nativeHostedAccessibilityFrame("fst.songs.section-bar", in: songs.host))
    let listFrame = try #require(nativeHostedAccessibilityFrame("fst.songs.list", in: songs.host))
    let headingFrame = try #require(nativeHostedAccessibilityFrame(heading, in: songs.host))
    #expect(nodes.first { $0.identifier == heading }?.role == "AXHeading", "\(dump)", sourceLocation: sourceLocation)
    #expect(headingFrame.minY >= barFrame.maxY && headingFrame.maxY <= listFrame.maxY,
            "\(label) heading \(headingFrame) bar \(barFrame) list \(listFrame)", sourceLocation: sourceLocation)
    let rows = nodes.filter { $0.identifier.hasPrefix("fst.songs.row.") && $0.spokenName.hasPrefix(label) }
        .compactMap { nativeHostedAccessibilityFrame($0.identifier, in: songs.host) }
    #expect(rows.count == 4, "\(label) rows \(rows)\n\(dump)", sourceLocation: sourceLocation)
    #expect(rows.allSatisfy { $0.minY >= headingFrame.maxY && $0.maxY <= listFrame.maxY + 0.5 && $0.height >= 44 },
            "\(label) rows in view \(rows) list \(listFrame)", sourceLocation: sourceLocation)
    #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))", sourceLocation: sourceLocation)
}

/// The A–Z index's accessibility element.
@MainActor
private func sectionIndex(_ songs: SongsJumpHost) throws -> NSObject {
    try #require(nativeHostedAccessibilityElement("fst.songs.section-index", in: songs.host))
}

/// What VoiceOver hears as the index's value: the section label.
@MainActor
private func sectionIndexValue(_ index: NSObject) -> String {
    nativeHostedAccessibilityString(index, "accessibilityValueDescription")
}

// MARK: - Tests

@MainActor
@Suite struct SongsSectionJumpAccessibilityTests {
    /// The A–Z index is one adjustable control VoiceOver presents as a slider on the Mac
    /// (a role-less `AXUnknown` before #451), named "Jump to section", valued with the
    /// current letter, with a full-height target beside the rows. Stepping it far
    /// forward and back lands each letter's heading and first row in view below the bar.
    @Test(arguments: SongsJumpCase.all)
    func azIndexJumpsLandTheSectionInView(_ jumpCase: SongsJumpCase) async throws {
        guard SongsScreen.usesSectionBar else { return }
        let songs = try await SongsJumpHost(sort: .title, jumpCase)
        defer { songs.tearDown() }
        let labels = ["#"] + scrollAwayWords.map { String($0.prefix(1)) }
        let index = try sectionIndex(songs)
        let node = try #require(songs.node("fst.songs.section-index"))
        #expect(node.role == "AXSlider" && node.isElement, "\(node)")
        #expect(node.spokenName == "Jump to section")
        #expect(sectionIndexValue(index) == "#")
        let frame = try #require(nativeHostedAccessibilityFrame("fst.songs.section-index", in: songs.host))
        #expect(frame.width >= 20 && frame.height >= 300, "index target \(frame)")

        // Far forward (# → L), back (L → E), to W, to the last letter and back to the first.
        var current = 0
        let last = labels.count - 1
        for target in [12, 5, last - 3, last, 0] {
            let selector = NSSelectorFromString(
                target > current ? "accessibilityPerformIncrement" : "accessibilityPerformDecrement"
            )
            for _ in 0..<abs(target - current) { _ = index.perform(selector) }
            current = target
            let label = labels[target]
            if target == 0 {
                // Back at the top the bar leaves and the List reads as it did at load.
                try await nativeHostedSettle(songs.host, timeout: .seconds(60)) { songs.node("fst.songs.section-bar") == nil }
                let top = try #require(songs.node("fst.songs.section.0"))
                #expect(top.role == "AXHeading" && top.spokenName == "#")
                #expect(sectionIndexValue(index) == "#")
                continue
            }
            if target == last {
                try await expectEndLanded(songs, index: index, label: label, heading: "fst.songs.section.\(target)")
                continue
            }
            try await songs.settle(on: label, heading: "fst.songs.section.\(target)")
            #expect(sectionIndexValue(index) == label, "index value after \(label)")
            try expectLanded(
                songs, on: label, heading: "fst.songs.section.\(target)",
                firstRow: { $0.hasPrefix(label) }, step: "az-\(label)-\(jumpCase.reduced)"
            )
        }
        #expect(await songs.transport.recordedRequests().isEmpty)
    }

    /// Quick Links on the grouped Songs List (Year): its entry names the section the
    /// jump landed on (the activation line #286 measures from the List's top inset), the
    /// bar repeats it as a heading, and the section's first row is in view below the bar.
    @Test(arguments: SongsJumpCase.all)
    func quickLinksJumpsLandTheSectionInView(_ jumpCase: SongsJumpCase) async throws {
        guard SongsScreen.usesSectionBar else { return }
        let songs = try await SongsJumpHost(sort: .year, jumpCase)
        defer { songs.tearDown() }
        let entry = try #require(songs.node("fst.quick-links.open"))
        #expect(entry.role == "AXButton" && entry.spokenName == "Quick Links" && entry.value == "2000s", "\(entry)")
        let entryFrame = try #require(nativeHostedAccessibilityFrame("fst.quick-links.open", in: songs.host))
        #expect(entryFrame.width >= 44 && entryFrame.height >= 44, "Quick Links target \(entryFrame)")

        for decade in [2020, 2010, 2000] {
            let element = try #require(nativeHostedAccessibilityElement("fst.quick-links.open", in: songs.host))
            _ = element.perform(NSSelectorFromString("accessibilityPerformPress"))
            let menu = try #require(songs.registry.inlineMenu, "the press opens Quick Links' choices")
            #expect(menu.choices.map(\.id) == [2000, 2010, 2020].map { "fst.quick-links.item.year:\($0)" })
            let choice = try #require(menu.choices.first { $0.id == "fst.quick-links.item.year:\(decade)" })
            songs.registry.choose(choice)
            songs.registry.inlineMenuDismissed()
            let label = "\(decade)s"
            let heading = "fst.songs.year-section.\(decade)"
            if decade == 2000 {
                try await nativeHostedSettle(songs.host, timeout: .seconds(60)) {
                    songs.node("fst.songs.section-bar") == nil && songs.node("fst.quick-links.open")?.value == label
                }
                #expect(songs.node("fst.songs.section-bar") == nil, "first section lands at the top")
                #expect(songs.node(heading)?.spokenName == label)
                continue
            }
            try await songs.settle(on: label, heading: heading)
            try await nativeHostedSettle(songs.host, timeout: .seconds(60)) { songs.node("fst.quick-links.open")?.value == label }
            #expect(songs.node("fst.quick-links.open")?.value == label, "Quick Links names \(label)")
            try expectLanded(
                songs, on: label, heading: heading,
                firstRow: { $0.hasSuffix("· \(decade)") }, step: "quick-links-\(decade)-\(jumpCase.reduced)"
            )
        }
        #expect(await songs.transport.recordedRequests().isEmpty)
    }
}

#endif
