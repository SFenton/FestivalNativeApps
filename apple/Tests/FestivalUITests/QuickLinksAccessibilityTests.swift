#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// Accessibility of Quick Links' page order (#11, tests backfilled by #392).
//
// #11 made every chooser list sections in the page's top-to-bottom order and kept
// nested sections (Profile's per-instrument Rank History and Percentiles) after their
// parent. VoiceOver reaches the same list two ways: the page's "Quick Links" rotor and
// the chooser's rows. These hosted tests read both from the real accessibility tree:
// rotor names in page order, nested rows spoken with their instrument,
// the active row's selected state, the entry point's name and value, and rows that wrap
// rather than clip at large text. iPhone sheet hit size and AX5 rows on device:
// `QuickLinksOrderJourneyTests.testQuickLinksSheetIsAccessible*` (simulator).

// MARK: - Helpers

/// The spoken names of the first custom rotor named `title` under `host`, stepping it
/// forward the way VoiceOver does. (The hosted rotor resolves its target elements
/// lazily, so only the names are readable here.)
///
/// - Parameters:
///   - title: The rotor's name ("Quick Links").
///   - host: The hosting view (call `nativeHostedEnableAccessibility()` first).
/// - Returns: The entries' names in rotor order; empty when no such rotor exists.
@MainActor
func hostedRotorEntries(named title: String, in host: NSView) -> [String] {
    var seen = Set<ObjectIdentifier>()
    func read(_ object: NSObject, _ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    func find(_ node: Any, depth: Int) -> NSAccessibilityCustomRotor? {
        guard depth < 80, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return nil }
        if let rotor = (read(object, "accessibilityCustomRotors") as? [NSAccessibilityCustomRotor])?
            .first(where: { $0.label == title }) {
            return rotor
        }
        for child in (read(object, "accessibilityChildren") as? [Any]) ?? [] {
            if let rotor = find(child, depth: depth + 1) { return rotor }
        }
        if let view = object as? NSView {
            for subview in view.subviews {
                if let rotor = find(subview, depth: depth + 1) { return rotor }
            }
        }
        return nil
    }
    guard let rotor = find(host, depth: 0), let search = rotor.itemSearchDelegate else { return [] }
    var entries: [String] = []
    var current: NSAccessibilityCustomRotor.ItemResult?
    for _ in 0..<64 {
        let parameters = NSAccessibilityCustomRotor.SearchParameters()
        parameters.currentItem = current
        parameters.searchDirection = .next
        guard let next = search.rotor(rotor, resultFor: parameters) else { break }
        let target = next.targetElement as? NSObject
        let label = next.customLabel.flatMap { $0.isEmpty ? nil : $0 }
            ?? (target.flatMap { read($0, "accessibilityLabel") } as? String) ?? ""
        entries.append(label)
        current = next
    }
    return entries
}

/// Wait until the page's "Quick Links" rotor lists `expected` (spoken names), then
/// return what it lists.
///
/// - Parameters:
///   - host: The page's hosting view.
///   - expected: Spoken section names in page order.
///   - sourceLocation: Where a timeout is reported.
/// - Returns: The rotor's spoken names once they match, or the last read after a timeout.
@MainActor
private func settledRotor<Content: View>(
    _ host: NSHostingView<Content>, expecting expected: [String],
    sourceLocation: SourceLocation = #_sourceLocation
) async throws -> [String] {
    var entries: [String] = []
    try await nativeHostedSettle(host, timeout: .seconds(60), sourceLocation: sourceLocation) {
        entries = hostedRotorEntries(named: "Quick Links", in: host)
        return entries == expected
    }
    return entries
}

/// A Profile-shaped page: Global Statistics, Lead containing its Rank History and
/// Percentiles (spoken with the instrument, as `PlayerProfileCharts` and
/// `PlayerPercentileTable` declare them), Bass, then Bands.
private struct NestedQuickLinksPage: View {
    let controller: QuickLinksController

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                block("Global").quickLinkSection(id: "global", title: "Global Statistics", symbol: "chart.bar.fill")
                VStack(spacing: 24) {
                    block("Lead")
                    block("Lead rank history").quickLinkSection(QuickLinkSection(
                        id: "rank-history:Solo_Guitar", title: "Rank History",
                        icon: .system("chart.line.uptrend.xyaxis"), depth: 1, spokenTitle: "Lead Rank History"
                    ))
                    block("Lead percentiles").quickLinkSection(QuickLinkSection(
                        id: "percentiles:Solo_Guitar", title: "Percentiles",
                        icon: .system("chart.bar.xaxis"), depth: 1, spokenTitle: "Lead Percentiles"
                    ))
                }
                .quickLinkSection(QuickLinkSection(
                    id: "instrument:Solo_Guitar", title: "Lead", icon: .instrument(.lead)
                ))
                block("Bass").quickLinkSection(QuickLinkSection(
                    id: "instrument:Solo_Bass", title: "Bass", icon: .instrument(.bass)
                ))
                block("Bands").quickLinkSection(id: "bands", title: "Bands", symbol: "person.3.fill")
            }
        }
        .quickLinks(controller, title: "Quick Links")
    }

    private func block(_ text: String) -> some View {
        Text(text).frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }
}

private let nestedIDs = [
    "global", "instrument:Solo_Guitar", "rank-history:Solo_Guitar", "percentiles:Solo_Guitar",
    "instrument:Solo_Bass", "bands",
]
private let nestedSpoken = [
    "Global Statistics", "Lead", "Lead Rank History", "Lead Percentiles", "Bass", "Bands",
]

/// Host ``NestedQuickLinksPage`` and wait for its sections to be discovered.
@MainActor
private func hostNestedPage(_ controller: QuickLinksController)
    async throws -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    let size = CGSize(width: 402, height: 1200)
    let host = nativeHostedView(NestedQuickLinksPage(controller: controller).preferredColorScheme(.dark), size: size)
    let window = nativeHostedWindow(host, size: size)
    try await nativeHostedSettle(host) { controller.sections.count == nestedIDs.count }
    return (host, window)
}

// MARK: - Rotor: nested sections in page order

/// VoiceOver's "Quick Links" rotor steps through the sections top to bottom, nested
/// sections right after their parent and spoken with it (#11: a plain `.preference`
/// dropped the nested entries).
@MainActor
@Test func quickLinksRotorReadsNestedSectionsInPageOrder() async throws {
    let controller = QuickLinksController()
    let (host, window) = try await hostNestedPage(controller)
    defer { window.orderOut(nil) }
    #expect(controller.sections.map(\.id) == nestedIDs)
    #expect(try await settledRotor(host, expecting: nestedSpoken) == nestedSpoken)
}

// MARK: - Chooser: names, order and selected state

/// The iPhone accessory sheet lists the same sections in the same order. Each row is a
/// button named by its spoken title (no indent figure spaces, nested rows say their
/// instrument), and only the active section's row is selected, following a jump into
/// a nested section.
@MainActor
@Test func quickLinksSheetRowsAreNamedOrderedAndMarkTheActiveSection() async throws {
    let controller = QuickLinksController()
    let (page, pageWindow) = try await hostNestedPage(controller)
    defer { pageWindow.orderOut(nil) }
    _ = page

    func sheetRows() async throws -> [MacAXNode] {
        let menu = PageToolInlineMenu(title: controller.title, choices: QuickLinksMenu.choices(for: controller))
        let size = CGSize(width: 402, height: 700)
        let host = nativeHostedView(
            PageToolInlineMenuSheet(menu: menu, registry: PageToolsRegistry()).preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host) {
            macAccessibilityTree(host).filter { $0.identifier.hasPrefix("fst.quick-links.item.") }.count
                == nestedIDs.count
        }
        return macAccessibilityTree(host).filter { $0.identifier.hasPrefix("fst.quick-links.item.") && $0.isElement }
    }

    let rows = try await sheetRows()
    #expect(rows.map(\.identifier) == nestedIDs.map { "fst.quick-links.item.\($0)" })
    #expect(rows.map(\.spokenName) == nestedSpoken, "\(rows)")
    #expect(rows.allSatisfy { $0.role == "AXButton" }, "\(rows)")
    #expect(!rows.contains { $0.spokenName.contains("\u{2007}") }, "indent leaks into VoiceOver")
    // Nothing scrolled yet: the first section is active (`QuickLinks.naturalActive`).
    #expect(rows.filter(\.selected).map(\.identifier) == ["fst.quick-links.item.global"])

    controller.jump(to: "rank-history:Solo_Guitar")
    let jumped = try await sheetRows()
    #expect(jumped.filter(\.selected).map(\.identifier) == ["fst.quick-links.item.rank-history:Solo_Guitar"])
}

/// The entry point is named "Quick Links", hints what it does and reports the active
/// section, including a nested one, as its value.
@MainActor
@Test func quickLinksEntryNamesItselfAndReportsTheActiveSection() async throws {
    let controller = QuickLinksController()
    let (page, pageWindow) = try await hostNestedPage(controller)
    defer { pageWindow.orderOut(nil) }
    _ = page
    let size = CGSize(width: 120, height: 60)
    let host = nativeHostedView(QuickLinksMenu(controller: controller).preferredColorScheme(.dark), size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }

    func entry() async throws -> MacAXNode? {
        var found: MacAXNode?
        try await nativeHostedSettle(host) {
            found = macAccessibilityTree(host).first { $0.identifier == "fst.quick-links.open" && $0.isElement }
            return found != nil
        }
        return found
    }
    let initial = try #require(try await entry())
    // A macOS `Menu` is an AXMenuButton named by its title; iOS reads the label.
    #expect(initial.role == "AXMenuButton")
    #expect(initial.spokenName == "Quick Links")
    #expect(initial.value == "Global Statistics")
    #expect(initial.help == "Jumps to a section of this page")

    controller.jump(to: "percentiles:Solo_Guitar")
    var value = ""
    try await nativeHostedSettle(host) {
        value = macAccessibilityTree(host).first { $0.identifier == "fst.quick-links.open" }?.value ?? ""
        return value == "Percentiles"
    }
    #expect(value == "Percentiles")
}

// MARK: - Text scaling

/// A nested row's label wraps rather than clipping when it does not fit on one line.
/// macOS does not scale fonts with Dynamic Type, so a column narrower than one line
/// stands in for the iPhone sheet at AX5 (same approach as
/// `rankingsRowsFitANarrowColumnAtAccessibilitySizes`); the device check is
/// `QuickLinksOrderJourneyTests.testQuickLinksSheetIsAccessibleAtAX5`.
@MainActor
@Test(arguments: [DynamicTypeSize.large, .accessibility5])
func quickLinksNestedRowLabelWrapsInsteadOfClipping(_ size: DynamicTypeSize) {
    let section = QuickLinkSection(
        id: "rank-history:Solo_PeripheralCymbals", title: "Rank History",
        icon: .system("chart.line.uptrend.xyaxis"), depth: 1, spokenTitle: "Pro Cymbals Rank History"
    )
    let host = NSHostingController(
        rootView: QuickLinkLabel(section: section, presentation: .list)
            .environment(\.dynamicTypeSize, size)
            .preferredColorScheme(.dark)
    )
    let oneLine = host.sizeThatFits(in: CGSize(width: 10_000, height: 10_000))
    let width = oneLine.width * 0.6
    let narrow = host.sizeThatFits(in: CGSize(width: width, height: 10_000))
    #expect(narrow.width <= width + 0.5)
    #expect(narrow.height > oneLine.height * 1.5, "one line \(oneLine), narrow \(narrow)")
}

// MARK: - Real pages (#11: Song Detail, Compete, Profile)

private let realPageInstrumentKeys = [
    "fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums",
    "fst.settings.showVocals", "fst.settings.showProLead", "fst.settings.showProBass",
    "fst.settings.showKaraoke", "fst.settings.showProCymbals", "fst.settings.showProDrums",
]

/// A session over the loopback fixture service with `accountId` selected and only
/// `visible` instruments shown.
@MainActor
private func quickLinksFixtureSession(
    accountId: String, displayName: String, visible: Set<String>
) async throws -> (session: FestivalSession, storage: UserDefaults, suite: String) {
    let baseURL = try await RivalsMockService.shared.baseURL()
    let client = try FestivalAPI(baseURL: baseURL, transport: URLSessionHTTPTransport())
    let suite = "fst.tests.quick-links-a11y.\(UUID().uuidString)"
    let storage = try #require(UserDefaults(suiteName: suite))
    let identity: [String: String] = ["accountId": accountId, "displayName": displayName]
    storage.set(try JSONSerialization.data(withJSONObject: identity), forKey: SelectedPlayerIdentity.storageKey)
    for key in realPageInstrumentKeys { storage.set(visible.contains(key), forKey: key) }
    return (FestivalSession(factory: { client }, selectionStorage: storage), storage, suite)
}

/// Host a real page in a `NavigationStack` with the session's settings.
@MainActor
private func hostRealPage<Page: View>(
    _ page: Page, storage: UserDefaults, height: CGFloat
) -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    let size = CGSize(width: 402, height: height)
    let host = nativeHostedView(
        NavigationStack { page }.defaultAppStorage(storage).preferredColorScheme(.dark), size: size
    )
    return (host, nativeHostedWindow(host, size: size))
}

/// Compete's rotor: Leaderboards, then Rivals (one of the pages #11 reported).
@MainActor
@Test func competeQuickLinksRotorReadsSectionsInPageOrder() async throws {
    let (session, storage, suite) = try await quickLinksFixtureSession(
        accountId: "fixture-riv", displayName: "Fixture Riv", visible: ["fst.settings.showLead"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let (host, window) = hostRealPage(CompeteScreen(session: session), storage: storage, height: 1800)
    defer { window.orderOut(nil) }
    #expect(try await settledRotor(host, expecting: ["Leaderboards", "Rivals"]) == ["Leaderboards", "Rivals"])
}

/// Song Detail's rotor with a selected player's history: Intensity, Score History,
/// each visible charted instrument, then the band sizes (one of the pages #11 reported;
/// #11 also made Score History appear exactly when the page draws it).
@MainActor
@Test func songDetailQuickLinksRotorReadsSectionsInPageOrder() async throws {
    let (session, storage, suite) = try await quickLinksFixtureSession(
        accountId: "fixture-player-1", displayName: "Fixture Player 1",
        visible: ["fst.settings.showLead", "fst.settings.showBass", "fst.settings.showDrums", "fst.settings.showVocals"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let song = try #require(try await session.catalog().catalog.songs.first { $0.songId == "fixture-pulse" })
    let (host, window) = hostRealPage(SongDetailScreen(song: song, session: session), storage: storage, height: 1400)
    defer { window.orderOut(nil) }
    let expected = ["Intensity", "Score History"]
        + [Instrument.lead, .bass, .drums, .vocals].map(\.label)
        + BandType.allCases.map(\.label)
    #expect(try await settledRotor(host, expecting: expected) == expected)
}

/// Profile's rotor: Global Statistics, Lead followed by its nested Rank History and
/// Percentiles (spoken with the instrument), the other visible instrument, then Bands:
/// the nested entries #11 restored.
@MainActor
@Test func playerProfileQuickLinksRotorKeepsNestedSectionsAfterTheirInstrument() async throws {
    let (session, storage, suite) = try await quickLinksFixtureSession(
        accountId: "fixture-player-1", displayName: "Fixture Player 1",
        visible: ["fst.settings.showLead", "fst.settings.showBass"]
    )
    defer { storage.removePersistentDomain(forName: suite) }
    let (host, window) = hostRealPage(
        PlayerProfileContent(session: session, accountId: "fixture-player-1", routeDisplayName: nil),
        storage: storage, height: 1800
    )
    defer { window.orderOut(nil) }
    let expected = ["Global Statistics", "Lead", "Lead Rank History", "Lead Percentiles", "Bass", "Bands"]
    #expect(try await settledRotor(host, expecting: expected) == expected)
}
#endif
