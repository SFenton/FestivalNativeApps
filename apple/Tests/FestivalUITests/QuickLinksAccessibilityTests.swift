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
// `QuickLinksAccessibilityTests` below (#389, for #6) pins the chooser and entry point
// on a flat section list.

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
        let menu = PageToolInlineMenu(title: controller.title, choices: QuickLinksMenu(controller: controller).choices())
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

// MARK: - Chooser and entry point (#389, for #6)

// MARK: - Fixtures

/// A page's Quick Links in page order: a top-level system section, an instrument, a
/// nested section with a fuller spoken name, and a last section.
private let quickLinksA11ySections = [
    QuickLinkSection(id: "app-settings", title: "App Settings", icon: .system("gearshape.fill")),
    QuickLinkSection(id: "instrument-Solo_Guitar", title: "Lead", icon: .instrument(.lead)),
    QuickLinkSection(
        id: "rank-history-Solo_Guitar", title: "Rank History", icon: .system("chart.line.uptrend.xyaxis"),
        depth: 1, spokenTitle: "Lead Rank History"
    ),
    QuickLinkSection(id: "reset", title: "Reset", icon: .system("trash")),
]

private let quickLinksItemPrefix = "fst.quick-links.item."

/// A controller offering `sections` with `active` as the current section.
@MainActor
private func quickLinksA11yController(
    _ sections: [QuickLinkSection] = quickLinksA11ySections, active: String? = nil
) -> QuickLinksController {
    let controller = QuickLinksController()
    controller.configure(title: "Quick Links", explicit: sections)
    if let active { controller.jump(to: active) }
    return controller
}

// MARK: - Tests

/// Accessibility of the Quick Links chooser (#389, for #6's fixed menu order).
///
/// #6 made the shared `QuickLinksMenu` list sections in page order wherever it opens
/// (`.menuOrder(.fixed)`); the simulator journeys (`QuickLinksOrderJourneyTests`,
/// `SettingsJourneyTests`, `QuickLinksAccessibilityJourneyTests`) check the system menu
/// and sheet on iPhone. These hosted tests run in `apple-ci` and pin the same contract
/// on the shared views every page uses: the iPhone tab-bar accessory's sheet
/// (`PageToolInlineMenuSheet` built from `QuickLinksMenu.choices()`) reads its rows in
/// page order with section names and the current section selected, and the entry point
/// announces the current section (pattern `quick-links` R2, R6).
@MainActor
@Suite struct QuickLinksAccessibilityTests {
    /// The sheet's choices follow the page's order, carry the row identifiers UI tests and
    /// VoiceOver users rely on, mark only the current section, and jump when picked.
    @Test func quickLinksChoicesKeepPageOrderAndMarkTheCurrentSection() {
        let controller = quickLinksA11yController(active: "instrument-Solo_Guitar")
        let choices = QuickLinksMenu(controller: controller).choices()
        #expect(choices.map(\.id) == quickLinksA11ySections.map { quickLinksItemPrefix + $0.id })
        #expect(choices.filter(\.isSelected).map(\.id) == [quickLinksItemPrefix + "instrument-Solo_Guitar"])
        choices.last?.action()
        #expect(controller.activeID == "reset")
    }

    /// VoiceOver reads the iPhone sheet's rows in page order, top to bottom as drawn; each
    /// row is a button named after its section (a nested row by its full spoken name, with
    /// no indent padding), only the current section is selected, and the decorative
    /// checkmark is hidden. Each row's button spans the row, so the whole row is the
    /// target (HIG Accessibility, Mobility: "Strive for the platform's recommended minimum
    /// control size", 44x44 pt on iOS; iOS list rows provide the height, the full-width
    /// content shape keeps it).
    @Test(arguments: [nil, "rank-history-Solo_Guitar"])
    func quickLinksSheetReadsRowsInPageOrderWithNamesAndState(_ active: String?) async throws {
        let controller = quickLinksA11yController(active: active)
        let menu = PageToolInlineMenu(title: controller.title, choices: QuickLinksMenu(controller: controller).choices())
        let size = CGSize(width: 402, height: 600)
        let host = nativeHostedView(
            PageToolInlineMenuSheet(menu: menu, registry: PageToolsRegistry()).preferredColorScheme(.dark), size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, until: {
            quickLinksA11ySections.allSatisfy {
                nativeHostedAccessibilityElement(quickLinksItemPrefix + $0.id, in: host) != nil
            }
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "quick-links-sheet-\(active ?? "none")")
        let rows = nodes.filter { $0.isElement && $0.identifier.hasPrefix(quickLinksItemPrefix) }

        #expect(rows.map(\.identifier) == quickLinksA11ySections.map { quickLinksItemPrefix + $0.id },
                "rows read in page order")
        #expect(rows.map(\.spokenName) == quickLinksA11ySections.map(\.accessibilityTitle), "rows are named by section")
        #expect(rows.allSatisfy { $0.role == "AXButton" }, "rows are buttons: \(rows)")
        // Before any scroll or jump the first section is current (`QuickLinks.naturalActive`).
        let current = quickLinksItemPrefix + (active ?? quickLinksA11ySections[0].id)
        #expect(rows.filter(\.selected).map(\.identifier) == [current], "only the current section is selected")
        #expect(!nodes.contains { $0.isElement && $0.role == "AXImage" }, "icons and the checkmark stay decorative")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")

        let frames = try quickLinksA11ySections.map {
            try #require(nativeHostedAccessibilityFrame(quickLinksItemPrefix + $0.id, in: host))
        }
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxY <= $1.minY + 0.5 },
                "reading order matches drawn order: \(frames)")
        #expect(frames.allSatisfy { $0.width >= size.width * 0.85 }, "each row's button spans the row: \(frames)")
    }

    /// The entry point is a menu button named "Quick Links" whose value is the current
    /// section and whose hint says what it does; the value follows a jump.
    @Test func quickLinksEntryAnnouncesTheCurrentSection() async throws {
        let controller = quickLinksA11yController(active: "instrument-Solo_Guitar")
        let size = CGSize(width: 200, height: 60)
        let host = nativeHostedView(QuickLinksMenu(controller: controller).preferredColorScheme(.dark), size: size)
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        func entry() -> MacAXNode? { macAccessibilityTree(host).first { $0.identifier == "fst.quick-links.open" } }
        try await nativeHostedSettle(host, until: { entry() != nil })
        var node = try #require(entry())
        #expect(node.role == "AXMenuButton")
        #expect(node.spokenName == "Quick Links")
        #expect(node.value == "Lead")
        #expect(node.help == "Jumps to a section of this page")

        controller.jump(to: "rank-history-Solo_Guitar")
        try await nativeHostedSettle(host, until: { entry()?.value == "Rank History" })
        node = try #require(entry())
        #expect(node.value == "Rank History")
    }

    /// With a single section the entry point is not offered at all, so VoiceOver never
    /// reaches an inert "Quick Links" button (pattern `quick-links` R3).
    @Test func quickLinksEntryIsAbsentWithOneSection() async throws {
        let controller = quickLinksA11yController(Array(quickLinksA11ySections.prefix(1)))
        let size = CGSize(width: 200, height: 60)
        let host = nativeHostedView(
            HStack { Text("Page"); QuickLinksMenu(controller: controller) }.preferredColorScheme(.dark), size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Page"])
        #expect(nativeHostedAccessibilityElement("fst.quick-links.open", in: host) == nil)
    }
}
#endif
