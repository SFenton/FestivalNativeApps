#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Songs section push accessibility (#288, #452, #458)
//
// #288 made the Songs floating section title (`SongsSectionBar`, iOS/macOS 26) behave
// like native pinned headers: the next section's title rises with the scroll and pushes
// the pinned one out (section-headers R4). Mid-push the bar draws up to three titles:
// the leaving one, the pinned one and the incoming one. These tests read the hosted
// accessibility tree while scrolling across section boundaries in small steps and pin
// what an assistive technology gets (section-headers R6): one floating title, a heading
// naming the current section, never the hidden moving copies; the in-list titles stay
// named headings in list order, including mid-push; the title grows with text size; and
// with Reduce Motion and Reduce Transparency on, the push still tracks the scroll 1:1.
// After a long return to the top (#297), read in VoiceOver's order (navigation order,
// List rows by row index), the List reads as it first did and scrolling again names the
// first section, read before its rows.
// The same SwiftUI code serves iPhone, iPhone Duo, iPad and Mac; this runs on the
// `apple-ci` macOS host. The iPhone position journey is
// `SongsChromeJourneyTests.testRailFarJumpLandsOnTheLetterAndNamesIt`.

/// The floating title's accessibility identifier.
private let barID = "fst.songs.section-bar"

/// Section letters of the fixture catalogue, in list order.
private let pushLetters = ["A", "B", "C", "D", "E"]

/// The fixture List's element identifiers in list order: each section's title, then its
/// eight songs.
private let pushListOrder: [String] = pushLetters.enumerated().flatMap { index, letter in
    ["fst.songs.section.\(index)"] + (1...8).map { "fst.songs.row.push-\(letter)-\($0)" }
}

/// One accessibility element of the hosted Songs page.
private struct PushElement: CustomStringConvertible {
    let role: String
    let label: String
    let identifier: String
    /// Frame in the host's top-left points.
    let frame: CGRect

    var description: String { "\(role) '\(label)' #\(identifier) \(frame)" }

    /// Index of the in-list section title this element is, or nil.
    var inListSection: Int? {
        identifier.hasPrefix("fst.songs.section.")
            ? Int(identifier.dropFirst("fst.songs.section.".count)) : nil
    }
}

/// The Songs page's settings for one case.
struct SongsPushCase: CustomTestStringConvertible, Sendable {
    let name: String
    let typeSize: DynamicTypeSize
    let reduced: Bool

    var testDescription: String { name }
}

/// One scroll step's observations.
private struct PushStep {
    let offset: CGFloat
    let bar: PushElement?
    let titles: [PushElement]
}

// MARK: - Host

/// The real Songs page sorted A–Z over 5 × 8 artless songs, sized as an iPhone.
///
/// - Parameter pushCase: Text size and accessibility settings.
/// - Returns: Settled host, the window keeping it alive, and the List's scroll view.
/// - Throws: A failed render or missing List.
@MainActor
private func hostSongs(
    _ pushCase: SongsPushCase
) async throws -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow, NSScrollView) {
    var songs: [Song] = []
    for letter in pushLetters {
        for number in 1...8 {
            songs.append(Song(
                songId: "push-\(letter)-\(number)",
                title: "\(letter)\(letter.lowercased()) Track \(number)",
                artist: "Fixture Artist", album: nil, year: 2000 + number, durationSeconds: 200,
                albumArt: nil, difficulty: nil, pathArtifactGenerationId: nil, sig: nil,
                maxScores: nil, doubleBassSupported: nil
            ))
        }
    }
    let payload = CatalogPayload(
        catalog: SongsResponse(count: songs.count, currentSeason: 9, songs: songs),
        publicationId: 7, observedPublicationId: 7, isStale: false
    )
    let suite = "fst-songs-push-ax-\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    storage.set(true, forKey: "fst.settings.hideShop")
    storage.set(true, forKey: "fst.accessibility.moreContrast")
    storage.set(pushCase.reduced, forKey: "fst.accessibility.reduceMotion")
    storage.set(pushCase.reduced, forKey: "fst.accessibility.lessTransparency")
    storage.set(SongSortMode.title.rawValue, forKey: "fst.songs.sortMode")
    storage.set(true, forKey: "fst.songs.sortAscending")
    let size = CGSize(width: 402, height: 844)
    let host = nativeHostedView(
        NavigationStack {
            SongsScreen(
                session: FestivalSession(factory: { throw FestivalAPIError.invalidResource }),
                initialState: .loaded(payload), isVisible: false
            )
        }
        .defaultAppStorage(storage)
        .dynamicTypeSize(pushCase.typeSize)
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    _ = try await nativeHostedSettle(host, untilText: ["Aa Track 1"])
    func listScroll(_ view: NSView) -> NSScrollView? {
        for subview in view.subviews {
            if let found = listScroll(subview) { return found }
        }
        if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
        return nil
    }
    let scroll = try #require(listScroll(host))
    storage.removePersistentDomain(forName: suite)
    return (host, window, scroll)
}

/// Every accessibility element under `host`, in walk (VoiceOver) order.
@MainActor
private func pushElements(_ host: NSView) -> [PushElement] {
    var elements: [PushElement] = []
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func walk(_ node: Any, depth: Int) {
        guard depth < 90, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return }
        if (read(object, "isAccessibilityElement") as? Bool) == true {
            var frame = CGRect.null
            if let window = host.window,
               let screen = (read(object, "accessibilityFrame") as? NSValue)?.rectValue {
                let local = host.convert(window.convertFromScreen(screen), from: nil)
                frame = host.isFlipped ? local : CGRect(
                    x: local.minX, y: host.bounds.height - local.maxY,
                    width: local.width, height: local.height
                )
            }
            elements.append(PushElement(
                role: nativeHostedAccessibilityString(object, "accessibilityRole"),
                label: nativeHostedAccessibilityString(object, "accessibilityLabel"),
                identifier: nativeHostedAccessibilityString(object, "accessibilityIdentifier"),
                frame: frame
            ))
        }
        for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, depth: depth + 1)
        }
        if let view = object as? NSView {
            for subview in view.subviews { walk(subview, depth: depth + 1) }
        }
    }
    walk(host, depth: 0)
    return elements
}

/// Scroll the List to `offset` and let the scroll-driven titles settle.
///
/// - Returns: The section headings after the scroll, checked for hidden copies.
@MainActor
private func scrollSongs(
    _ scroll: NSScrollView, to offset: CGFloat, host: NSView,
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> PushStep {
    let clip = scroll.contentView
    clip.scroll(to: NSPoint(x: 0, y: offset - scroll.contentInsets.top))
    scroll.reflectScrolledClipView(clip)
    var previous = ""
    var elements: [PushElement] = []
    // Geometry callbacks update the bar a pass later: settle until two passes agree.
    for _ in 0..<12 {
        try await Task.sleep(for: .milliseconds(15))
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        elements = pushElements(host)
        let signature = elements.filter { $0.role == "AXHeading" }.map(\.description).joined()
        if signature == previous { break }
        previous = signature
    }
    let headings = elements.filter { pushLetters.contains($0.label) }
    // R6: the leaving and incoming copies the bar draws are hidden from VoiceOver. Every
    // element naming a section is the floating title or an in-list title.
    let strays = headings.filter { $0.identifier != barID && $0.inListSection == nil }
    #expect(strays.isEmpty, "Moving title copies exposed at \(offset): \(strays)",
            sourceLocation: sourceLocation)
    let bars = headings.filter { $0.identifier == barID }
    #expect(bars.count <= 1, "More than one floating title at \(offset): \(bars)",
            sourceLocation: sourceLocation)
    return PushStep(
        offset: offset, bar: bars.first,
        titles: headings.filter { $0.inListSection != nil }
    )
}

// MARK: - Tests

@Suite("Songs section push accessibility (#288)")
@MainActor
struct SongsSectionPushAccessibilityTests {
    /// Sweep down across the A→B and B→C pushes in small steps, then back up to the top.
    @Test(arguments: [
        SongsPushCase(name: "default", typeSize: .large, reduced: false),
        SongsPushCase(name: "AX5", typeSize: .accessibility5, reduced: false),
        SongsPushCase(name: "reduce motion and transparency", typeSize: .large, reduced: true),
    ])
    func pushKeepsOneNamedHeadingInSectionOrder(_ pushCase: SongsPushCase) async throws {
        guard SongsScreen.usesSectionBar else { return }
        let (host, window, scroll) = try await hostSongs(pushCase)
        defer { window.orderOut(nil) }
        let top = try await scrollSongs(scroll, to: 0, host: host)
        #expect(top.bar == nil, "A section title is pinned at the top: \(String(describing: top.bar))")
        let pinnedY = try #require(top.titles.first { $0.label == "A" }).frame.minY

        var steps: [PushStep] = []
        var offset: CGFloat = 0
        while offset < 6_000 {
            let step = try await scrollSongs(scroll, to: offset, host: host)
            steps.append(step)
            if step.bar?.label == "C" { break }
            // Fine steps while the next title nears the bar; coarse ones elsewhere.
            let barIndex = step.bar.flatMap { pushLetters.firstIndex(of: $0.label) } ?? 0
            let next = step.titles.first { $0.inListSection == barIndex + 1 }
            let near = next.map { $0.frame.minY - pinnedY < 4 * max($0.frame.height, 20) } ?? false
            offset += near ? 3 : 24
        }
        let last = try #require(steps.last)
        #expect(last.bar?.label == "C", "Never reached C: \(String(describing: last.bar))")
        // The bar shows once the List has scrolled away from the top, then stays.
        let shown = try #require(steps.firstIndex { $0.bar != nil }, "The floating title never showed")
        let barY = try #require(steps[shown].bar).frame.minY
        #expect(abs(barY - pinnedY) <= 1, "Floating A at \(barY), its in-list title at \(pinnedY)")
        for step in steps[shown...] {
            checkStep(step)
        }
        checkSequence(Array(steps[shown...]), pinnedY: barY, down: true)

        var back: [PushStep] = []
        offset = last.offset
        while offset > 0 {
            offset = max(0, offset - 3)
            back.append(try await scrollSongs(scroll, to: offset, host: host))
            // Until A has come back down and pinned again.
            if let bar = back.last?.bar, bar.label == "A", abs(bar.frame.minY - barY) <= 1 { break }
        }
        for step in back {
            checkStep(step)
        }
        checkSequence(back, pinnedY: barY, down: false)
        let home = try await scrollSongs(scroll, to: 0, host: host)
        #expect(home.bar == nil, "The floating title stayed at the top")
        withExtendedLifetime(window) {}
    }

    /// Issue #297 (accessibility, #458): back at the top after one long move from deep in
    /// the list (a status-bar tap), then scrolling again, the floating heading names the
    /// first section, not a section the List recycled before its title reported leaving
    /// the bar. Read in VoiceOver's order (navigation order, List rows by row index; AppKit
    /// recycles row views out of order): at the top the bar leaves the tree and the List
    /// reads exactly as it first did, the first section's heading and then its first song;
    /// scrolled again, the one bar heading is read before the rows, names A and then B, and
    /// the List follows in list order with no exposed moving copy.
    @Test(arguments: [
        SongsPushCase(name: "default", typeSize: .large, reduced: false),
        SongsPushCase(name: "AX5", typeSize: .accessibility5, reduced: false),
    ])
    func longReturnToTheTopThenScrollingNamesTheFirstSection(_ pushCase: SongsPushCase) async throws {
        guard SongsScreen.usesSectionBar else { return }
        let (host, window, scroll) = try await hostSongs(pushCase)
        defer { window.orderOut(nil) }
        let table = try #require(scroll.documentView as? NSTableView)
        let initial = try await scrollSongs(scroll, to: 0, host: host)
        let pinnedY = try #require(initial.titles.first { $0.label == "A" }).frame.minY
        let initialOrder = macListReadingOrder(host, table: table)
        macAccessibilityDump(initialOrder.all, name: "songs-push-long-return-initial-\(pushCase.name)")
        checkReadingOrder(initialOrder, bar: nil, state: "first render")
        #expect(initialOrder.rows.prefix(2).map(\.identifier) == ["fst.songs.section.0", "fst.songs.row.push-A-1"],
                "The List does not start with A's heading and first song: \(initialOrder.rows)")

        // Down the way a person scrolls (steps shorter than a title's passing band) until
        // D is current: A, B and C have reported passing the bar.
        var offset: CGFloat = 0
        var deep = initial
        while deep.bar?.label != "D", offset < 8_000 {
            offset += 24
            deep = try await scrollSongs(scroll, to: offset, host: host)
        }
        #expect(deep.bar?.label == "D", "Never reached D: \(String(describing: deep.bar))")
        #expect(!deep.titles.contains { $0.label == "B" }, "B is still built; the jump would not skip it")

        // One move to the top: the bar leaves and the List reads exactly as it first did.
        let top = try await scrollSongs(scroll, to: 0, host: host)
        #expect(top.bar == nil, "A section title is pinned at the top: \(String(describing: top.bar))")
        let topOrder = macListReadingOrder(host, table: table)
        macAccessibilityDump(topOrder.all, name: "songs-push-long-return-top-\(pushCase.name)")
        checkReadingOrder(topOrder, bar: nil, state: "back at the top")
        func spoken(_ order: MacListReadingOrder) -> [String] {
            order.all.map { "\($0.role) '\($0.spokenName)' #\($0.identifier)" }
        }
        #expect(spoken(topOrder) == spoken(initialOrder),
                "Reading order changed at the top: \(topOrder.all) vs \(initialOrder.all)")

        // Scrolling again, the bar first names A, then B once B pushes A out.
        var steps: [PushStep] = []
        var names: [String] = []
        offset = 0
        while offset < 6_000 {
            offset += 6
            let step = try await scrollSongs(scroll, to: offset, host: host)
            guard step.bar != nil || !steps.isEmpty else { continue }
            steps.append(step)
            checkStep(step, byRow: true)
            let order = macListReadingOrder(host, table: table)
            checkReadingOrder(order, bar: step.bar?.label, state: "scrolled again to \(offset)")
            if let name = order.before.first(where: { $0.identifier == barID })?.spokenName, names.last != name {
                names.append(name)
            }
            if step.bar?.label == "B" {
                macAccessibilityDump(order.all, name: "songs-push-long-return-b-\(pushCase.name)")
                break
            }
        }
        #expect(steps.first?.bar?.label == "A",
                "Scrolled again, the bar named \(String(describing: steps.first?.bar)) instead of A")
        let bar = try #require(steps.first?.bar)
        #expect(abs(bar.frame.minY - pinnedY) <= 1, "Floating A at \(bar.frame.minY), its in-list title at \(pinnedY)")
        #expect(steps.last?.bar?.label == "B", "Never reached B: \(String(describing: steps.last?.bar))")
        #expect(names == ["A", "B"], "VoiceOver heard the bar name \(names), expected A then B")
        withExtendedLifetime(window) {}
    }

    /// VoiceOver's reading order in one state (section-headers R6): the floating title is
    /// read once, as a heading naming `bar`, before every List row (or is absent when `bar`
    /// is nil); the List reads a contiguous run of the fixture in list order (each heading
    /// before its songs, sections in order); rows read before the List's first heading
    /// belong to the bar's section; and only the bar and the in-list titles name a section.
    private func checkReadingOrder(
        _ order: MacListReadingOrder, bar: String?, state: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        let bars = order.all.filter { $0.identifier == barID }
        if let bar {
            #expect(bars.count == 1, "\(state): \(bars.count) floating titles: \(order.all)",
                    sourceLocation: sourceLocation)
            let read = order.before.first { $0.identifier == barID }
            #expect(read?.role == "AXHeading" && read?.spokenName == bar,
                    "\(state): the bar heading for \(bar) is not read before the List: \(order.all)",
                    sourceLocation: sourceLocation)
        } else {
            #expect(bars.isEmpty, "\(state): a floating title is exposed: \(bars)", sourceLocation: sourceLocation)
        }
        let ids = order.rows.map(\.identifier)
        let first = ids.first.flatMap { pushListOrder.firstIndex(of: $0) }
        #expect(first != nil && pushListOrder.dropFirst(first ?? 0).prefix(ids.count).elementsEqual(ids),
                "\(state): the List does not read in list order: \(order.rows)", sourceLocation: sourceLocation)
        for title in order.rows where title.identifier.hasPrefix("fst.songs.section.") {
            #expect(title.role == "AXHeading", "\(state): in-list title is not a heading: \(title)",
                    sourceLocation: sourceLocation)
        }
        if let bar {
            let lead = ids.prefix { !$0.hasPrefix("fst.songs.section.") }
            #expect(lead.allSatisfy { $0.hasPrefix("fst.songs.row.push-\(bar)-") },
                    "\(state): rows read under the \(bar) bar belong to another section: \(lead)",
                    sourceLocation: sourceLocation)
        }
        let strays = order.all.filter {
            pushLetters.contains($0.spokenName) && $0.identifier != barID
                && !$0.identifier.hasPrefix("fst.songs.section.")
        }
        #expect(strays.isEmpty, "\(state): moving title copies exposed: \(strays)", sourceLocation: sourceLocation)
    }

    /// One scrolled step: the floating title is a heading naming a fixture section, it is
    /// as tall as the in-list titles (text scaling, no clipping), and the in-list titles
    /// stay named headings in list order (the one under the bar or mid-push too).
    ///
    /// - Parameters:
    ///   - step: The step to check.
    ///   - byRow: Take the in-list titles in row order rather than walk order. After a
    ///     long return AppKit recycles row views out of order, so the walk can list a
    ///     recycled first title last; callers passing true check VoiceOver's order with
    ///     ``checkReadingOrder(_:bar:state:sourceLocation:)``. Their frames must still
    ///     rise with the row order.
    private func checkStep(_ step: PushStep, byRow: Bool = false) {
        guard let bar = step.bar else {
            Issue.record("No floating title at \(step.offset)")
            return
        }
        #expect(bar.role == "AXHeading", "Floating title is not a heading: \(bar)")
        #expect(pushLetters.contains(bar.label), "Floating title names no section: \(bar)")
        #expect(!step.titles.isEmpty, "No in-list title at \(step.offset)")
        var previous: PushElement?
        let titles = byRow ? step.titles.sorted { ($0.inListSection ?? -1) < ($1.inListSection ?? -1) } : step.titles
        for title in titles {
            let index = title.inListSection ?? -1
            #expect(title.role == "AXHeading", "In-list title is not a heading: \(title)")
            #expect(pushLetters.indices.contains(index) && title.label == pushLetters[index],
                    "In-list title misnamed: \(title)")
            if let previous {
                #expect((previous.inListSection ?? 0) < index && previous.frame.minY < title.frame.minY,
                        "In-list titles out of order at \(step.offset): \(previous), \(title)")
            }
            #expect(abs(title.frame.height - bar.frame.height) <= 1,
                    "Floating title \(bar.frame) not sized like its in-list title \(title.frame)")
            previous = title
        }
    }

    /// The whole sweep: the floating title names one section after another in scroll
    /// order, a push really happened at each boundary with the incoming title still a
    /// heading, and the pushed title follows the scroll one-for-one (nothing animates
    /// on its own, so Reduce Motion needs no special case).
    private func checkSequence(_ steps: [PushStep], pinnedY: CGFloat, down: Bool) {
        var pushes = Set<String>()
        for (before, after) in zip(steps, steps.dropFirst()) {
            guard let from = before.bar, let to = after.bar,
                  let a = pushLetters.firstIndex(of: from.label),
                  let b = pushLetters.firstIndex(of: to.label) else { continue }
            let moved = abs(after.offset - before.offset)
            #expect(down ? (b == a || b == a + 1) : (b == a || b == a - 1),
                    "Floating title jumped \(from.label) → \(to.label) at \(after.offset)")
            guard a == b else { continue }
            // Pushed below its pin by the incoming title: moves with the rows, never more.
            #expect(abs(to.frame.minY - from.frame.minY) <= moved + 1,
                    "Floating \(to.label) moved \(abs(to.frame.minY - from.frame.minY)) for a \(moved) pt scroll")
            if to.frame.minY < pinnedY - 1 {
                let incoming = after.titles.first { $0.inListSection == a + 1 }
                #expect(incoming?.role == "AXHeading",
                        "Incoming title not a heading mid-push at \(after.offset)")
                pushes.insert(to.label)
            }
        }
        #expect(pushes == ["A", "B"], "Pushes seen for \(pushes.sorted()), expected A and B")
    }
}
#endif
