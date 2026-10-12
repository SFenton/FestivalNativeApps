#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// Notices #359 removed from a Songs page without a player, and the paused notices that
/// share their place above the rows.
private let deselectPausedNoticeIDs = [
    "fst.songs.score-filter-paused", "fst.songs.score-filter-hidden",
    "fst.songs.sort-paused", "fst.songs.filter-paused",
]

/// Box for the root-owned Songs instrument, so a test can read what the page was left on.
@MainActor
private final class DeselectInstrumentBox {
    var instrument: Instrument?
}

/// The roots' Songs instrument wiring (`FestivalRootView` and `MacRootView` own the
/// instrument as `@State` and clear it on `songSettingsResetRevision`, issue #359) around
/// the shared ``SongsScreen``, with the box reporting the instrument the page uses.
private struct DeselectResetHarness: View {
    let session: FestivalSession
    let payload: CatalogPayload
    let box: DeselectInstrumentBox
    let storage: UserDefaults
    @State var instrument: Instrument?

    var body: some View {
        NavigationStack {
            SongsScreen(
                session: session, initialState: .loaded(payload),
                selectedInstrument: $instrument, isVisible: true, openShop: {}
            )
        }
        .onChange(of: session.songSettingsResetRevision) { _, _ in
            instrument = nil
        }
        .onChange(of: instrument, initial: true) { _, current in
            box.instrument = current
        }
        .defaultAppStorage(storage)
        .preferredColorScheme(.dark)
    }
}

/// Fixture Player 2's compact profile envelope (Lead scores on both fixture songs, Drums
/// on Pulse only).
///
/// - Returns: The checked-in synthetic player bytes.
/// - Throws: A missing or malformed fixture.
private func deselectFixturePlayer() throws -> Data {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    let data = try Data(contentsOf: root.appendingPathComponent("contracts/fixtures/player-demo.json"))
    guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let profiles = envelope["profiles"] as? [String: Any],
          let player = profiles["fixture-player-2"] as? [String: Any] else {
        throw FestivalAPIError.invalidPlayerProfile
    }
    return try JSONSerialization.data(withJSONObject: player)
}

/// The element with `identifier` in `nodes`, if it is realized: the innermost one, so a
/// toolbar control reads as its button rather than AppKit's toolbar-item wrapper (which
/// carries the item's short label, "Filter").
private func deselectTool(_ identifier: String, in nodes: [MacAXNode]) -> MacAXNode? {
    nodes.last { $0.identifier == identifier && $0.isElement }
}


/// A hosted Songs page with Fixture Player 2 selected and every kind of saved choice
/// #359 resets: an Item Shop filter, a Drums score check, the Lead instrument and a
/// descending Score sort.
@MainActor
private struct DeselectResetPage {
    let session: FestivalSession
    let storage: UserDefaults
    let suiteName: String
    let host: NSHostingView<NativeHostedRoot<DeselectResetHarness>>
    let window: NSWindow
    let box: DeselectInstrumentBox

    /// Host the page and wait until its tools read the selected player's choices.
    ///
    /// - Parameter size: Window size in points.
    /// - Throws: A failed fixture read or a page that never settles.
    init(size: CGSize = CGSize(width: 900, height: 820)) async throws {
        suiteName = "fst-songs-deselect-a11y-\(UUID().uuidString)"
        storage = try #require(UserDefaults(suiteName: suiteName))
        storage.set(true, forKey: "fst.accessibility.lessTransparency")
        storage.set(false, forKey: "fst.settings.hideShop")
        storage.set(SongSortMode.score.rawValue, forKey: SongsPresetStore.sortModeKey)
        storage.set(false, forKey: SongsPresetStore.sortAscendingKey)
        storage.set(try SongGeneralFilter(shop: .availableOnly).encoded(), forKey: SongGeneralFilter.storageKey)
        storage.set(try SongPlayerScoreFilter(hasScores: [.drums]).encoded(), forKey: SongPlayerScoreFilter.storageKey)

        let fixtures = try shopFixtureBytes()
        let transport = HostedShopTransport(
            scenario: .populated, offers: fixtures.offers, catalogue: fixtures.catalogue,
            player: try deselectFixturePlayer()
        )
        let client = try FestivalAPI(transport: transport)
        // The session writes the reset into the same store the page's `@AppStorage` reads.
        session = FestivalSession(factory: { client }, selectionStorage: storage)
        _ = try await session.shop()
        let payload = try await session.catalog()
        let selection = try JSONDecoder().decode(PlayerSearchResult.self, from: Data("""
        {"accountId":"fixture-player-2","displayName":"Fixture Player 2"}
        """.utf8))
        try session.selectPlayer(selection, from: try await session.viewPlayer(selection))
        #expect(session.playerLoadState == .available)

        box = DeselectInstrumentBox()
        host = nativeHostedView(
            DeselectResetHarness(
                session: session, payload: payload, box: box, storage: storage, instrument: .lead
            ),
            size: size
        )
        // A titled window, so the page's toolbar (Sort, Filter Songs) is realized.
        window = NSWindow(
            contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderOut(nil)
        let (host, window) = (host, window)
        let tool = { (id: String) in deselectTool(id, in: macAccessibilityTree(window.contentView?.superview ?? host)) }
        _ = try await nativeHostedSettle(host) {
            tool("fst.songs.sort")?.value == "Score, descending"
                && tool("fst.songs.filter")?.value == "Item Shop filter, 1 player score check"
        }
        #expect(tool("fst.songs.sort")?.value == "Score, descending")
        #expect(tool("fst.songs.filter")?.value == "Item Shop filter, 1 player score check")
    }

    /// Every node of the window: its toolbar (Sort, Filter Songs) and the page.
    var nodes: [MacAXNode] {
        macAccessibilityTree(window.contentView?.superview ?? host)
    }

    /// The elements VoiceOver lands on, in reading order.
    var elements: [MacAXNode] {
        nodes.filter { $0.isElement && $0.role != "AXGroup" }
    }

    /// The element with `identifier`, if it is realized.
    func tool(_ identifier: String) -> MacAXNode? {
        deselectTool(identifier, in: nodes)
    }

    /// Wait for a condition on the hosted page.
    ///
    /// - Parameters:
    ///   - what: What the page should reach, for the failure message.
    ///   - ready: The condition.
    /// - Throws: A page that never reaches it.
    func settle(_ what: String, until ready: @escaping @MainActor () -> Bool) async throws {
        _ = try await nativeHostedSettle(host, until: ready)
        #expect(ready(), "Songs never showed \(what): \(nodes.filter(\.isElement))")
    }

    /// Release the window and the suite.
    func close() {
        window.orderOut(nil)
        storage.removePersistentDomain(forName: suiteName)
    }
}

// MARK: - Tests

/// Accessibility of Songs after deselecting a player (#487, for #359).
///
/// #359 made a deselect (or a player/band switch) reset Songs' filters, instrument and
/// player-chart sort like the web's `resetSongSettingsForDeselect`, so the "Player score
/// filters paused until a player is selected" and "Score sort paused until a player is
/// selected" cards no longer appear. These hosted tests run in `apple-ci` on the shared
/// ``SongsScreen`` (iPhone, iPhone Duo, iPad and Mac) and read its accessibility tree:
/// Sort and Filter Songs speak their reset state (HIG VoiceOver: "Update labels when UI
/// changes."), no paused card or text
/// is left in the reading order, the rows follow the tools directly, and Filter Songs
/// still opens by an accessibility press. iPhone targets, the audit and the largest text
/// size are checked on device by `SongsDeselectAccessibilityJourneyTests`.
@MainActor
@Suite struct SongsDeselectResetAccessibilityTests {
    /// Before a deselect the tools speak the player's choices; after it they speak the
    /// defaults (Sort "Title, ascending", Filter Songs "No filters", nothing "paused"),
    /// keep their names and button role, and the page is back on every instrument.
    @Test func deselectReadsResetToolsWithoutPausedState() async throws {
        let page = try await DeselectResetPage()
        defer { page.close() }
        #expect(page.box.instrument == .lead)

        page.session.deselectPlayer()
        try await page.settle("the reset tools") {
            page.tool("fst.songs.sort")?.value == "Title, ascending"
                && page.tool("fst.songs.filter")?.value == "No filters"
        }
        macAccessibilityDump(page.nodes, name: "songs-deselect-reset")
        let sort = try #require(page.tool("fst.songs.sort"))
        let filter = try #require(page.tool("fst.songs.filter"))
        #expect(sort.role == "AXButton" && sort.spokenName == "Sort", "\(sort)")
        #expect(filter.role == "AXButton" && filter.spokenName == "Filter Songs", "\(filter)")
        #expect(sort.isEnabled && filter.isEnabled)
        for id in ["fst.songs.sort", "fst.songs.filter"] {
            let values = page.nodes.filter { $0.identifier == id && $0.isElement }.map(\.value)
            #expect(!values.contains { $0.localizedCaseInsensitiveContains("paused") }, "\(id): \(values)")
        }
        #expect(page.box.instrument == nil, "Songs returns to every instrument")
        // The region #359 changed: the page and its Sort and Filter Songs tools.
        let region = macAccessibilityTree(page.host)
            + page.nodes.filter { ["fst.songs.sort", "fst.songs.filter"].contains($0.identifier) }
        let findings = macAccessibilityFindings(region)
        #expect(findings.isEmpty, "\(findings)")
    }

    /// After a deselect no paused card (or any text naming a pause or a missing player)
    /// is left for VoiceOver: the page reads the song rows first, in the reset Title
    /// order, top to bottom.
    @Test func deselectLeavesNoPausedNoticeInReadingOrder() async throws {
        let page = try await DeselectResetPage()
        defer { page.close() }
        page.session.deselectPlayer()
        try await page.settle("both rows in Title order") {
            page.tool("fst.songs.sort")?.value == "Title, ascending"
                && page.tool("fst.songs.row.fixture-pulse") != nil && page.tool("fst.songs.row.fixture-orbit") != nil
        }
        for id in deselectPausedNoticeIDs {
            #expect(!page.nodes.contains { $0.identifier == id }, "\(id) after deselect")
        }
        let spoken = page.elements.map { "\($0.spokenName) \($0.value)" }
        #expect(!spoken.contains { $0.localizedCaseInsensitiveContains("paused") }, "\(spoken)")
        #expect(!spoken.contains { $0.localizedCaseInsensitiveContains("until a player is selected") }, "\(spoken)")

        // The page itself, in VoiceOver's navigation order (the toolbar is the window's).
        let content = macAccessibilityTree(page.host, navigationOrder: true).filter {
            $0.isElement && (!$0.spokenName.isEmpty || !$0.identifier.isEmpty)
                && !["AXScrollArea", "AXOutline", "AXScrollBar"].contains($0.role)
        }
        let rows = ["fst.songs.row.fixture-orbit", "fst.songs.row.fixture-pulse"]
        #expect(Array(content.prefix(2).map(\.identifier)) == rows, "rows first, A to Z: \(content)")
        let frames = try rows.map { try #require(nativeHostedAccessibilityFrame($0, in: page.host), "\($0)") }
        #expect(frames[0].minY < frames[1].minY, "reading order matches the drawn order: \(frames)")
    }

    /// After a deselect, pressing Filter Songs the way VoiceOver, Voice Control or Full
    /// Keyboard Access does opens the sheet with only General's groups, each collapsed
    /// (nothing restricted), and Reset Filters last.
    @Test func filterSongsOpensAResetGeneralSheetByAccessibilityPress() async throws {
        let page = try await DeselectResetPage()
        defer { page.close() }
        page.session.deselectPlayer()
        try await page.settle("the reset Filter Songs") { page.tool("fst.songs.filter")?.value == "No filters" }
        let before = Set(NSApp.windows.map(ObjectIdentifier.init))
        let root = page.window.contentView?.superview ?? page.host
        let filter = try #require(nativeHostedAccessibilityElement("fst.songs.filter", in: root))
        let press = NSSelectorFromString("accessibilityPerformPress")
        #expect(filter.responds(to: press), "Filter Songs is pressable")
        _ = filter.perform(press)

        var budget = NativeHostedPollBudget(.seconds(20))
        var sheetNodes: [MacAXNode] = []
        while !budget.isExhausted {
            let candidates = NSApp.windows.filter { !before.contains(ObjectIdentifier($0)) } + [page.window]
            sheetNodes = candidates.flatMap { window -> [MacAXNode] in
                guard let view = window.contentView?.superview ?? window.contentView else { return [] }
                let nodes = macAccessibilityTree(view)
                return nodes.contains { $0.identifier == "fst.songs.filter.reset" } ? nodes : []
            }
            if !sheetNodes.isEmpty { break }
            try await budget.sleep(for: .milliseconds(100))
        }
        defer {
            for window in NSApp.windows where !before.contains(ObjectIdentifier(window)) { window.orderOut(nil) }
        }
        macAccessibilityDump(sheetNodes, name: "songs-deselect-reset-filter-sheet")
        let ids = sheetNodes.filter(\.isElement).map(\.identifier).filter { $0.hasPrefix("fst.songs.filter.") }
        #expect(!ids.isEmpty, "the Filter sheet opened")
        let groups = ["year", "duration", "shop", "double-bass"].map { "fst.songs.filter.\($0)" }
        #expect(ids.filter { groups.contains($0) } == groups, "\(ids)")
        for id in groups {
            #expect(sheetNodes.first { $0.identifier == id && $0.isElement }?.value == "0", "\(id) collapsed")
        }
        #expect(!ids.contains { $0.contains(".score") || $0 == "fst.songs.filter.instrument" },
                "no player section after a deselect: \(ids)")
        #expect(ids.last(where: { $0 != "fst.songs.filter.done" && $0 != "fst.songs.filter.form" })
                    == "fst.songs.filter.reset", "\(ids)")
    }
}
#endif
