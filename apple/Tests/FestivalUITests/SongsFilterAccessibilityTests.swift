#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// Release decades and minute buckets the hosted catalogue offers.
private let filterA11yDecades = [1990, 2000, 2010, 2020]
private let filterA11yDurations = [2, 3, 10]

/// The General groups' spoken names: title, then the web's hint (one combined label).
private let filterA11yGroupNames = [
    "year": "Year, Filter songs by their release decade.",
    "duration": "Duration, Filter songs by their duration.",
    "shop": "Item Shop, Filter songs by whether they are available in the Item Shop.",
    "double-bass": "Double Bass, Filter songs that have or don't have double bass charts for Pro Drums.",
]

/// A General filter with every group restricted: 1990s and 10+ minutes off, Item Shop
/// available only, and no songs without Double Bass.
private let filterA11yRestricted = SongGeneralFilter(
    excludedDecades: [1990], excludedDurations: [10], shop: .availableOnly, doubleBassUnsupported: false
)

/// Records what the sheet commits on each change.
@MainActor
private final class FilterA11yApplied {
    var general: SongGeneralFilter?
    var count = 0
}

/// One element VoiceOver lands on: role, spoken name, value and identifier.
private struct FilterA11yRead: Equatable, CustomStringConvertible {
    let role: String
    let name: String
    let value: String
    let id: String

    init(_ role: String, _ name: String, _ value: String = "", id: String = "") {
        self.role = role
        self.name = name
        self.value = value
        self.id = id
    }

    var description: String { "\(role) '\(name)'\(value.isEmpty ? "" : "=\(value)") #\(id)" }
}

/// Host the real Filter sheet tall enough that every row is realized.
///
/// - Parameters:
///   - filter: Saved General filter.
///   - showShop: Whether Settings shows the Item Shop (offers the Item Shop group).
///   - shopAvailable: Whether a Shop feed matches the current Songs.
///   - player: Whether a profile is selected.
///   - width: Sheet width in points.
///   - applied: Receives each committed General filter.
/// - Returns: The settled host and its window (keep it alive while reading).
@MainActor
private func hostFilterA11ySheet(
    _ filter: SongGeneralFilter = SongGeneralFilter(), showShop: Bool = true, shopAvailable: Bool = true,
    player: Bool = false, width: CGFloat = 390, applied: FilterA11yApplied = FilterA11yApplied()
) async throws -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    let size = CGSize(width: width, height: 2400)
    let host = nativeHostedView(
        SongsFilterSheet(
            appliedGeneral: filter, showShop: showShop, shopAvailable: shopAvailable,
            availableDecades: filterA11yDecades, availableDurations: filterA11yDurations,
            selectedPlayer: player, scoreAvailable: player,
            onApply: { general, _, _ in
                applied.general = general
                applied.count += 1
            }
        )
        .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    try await nativeHostedSettle(host, until: {
        nativeHostedAccessibilityElement("fst.songs.filter.reset", in: host) != nil
    })
    return (host, window)
}

/// The elements VoiceOver lands on, in reading order (no grouping containers).
@MainActor
private func filterA11yElements(_ host: NSView) -> [MacAXNode] {
    macAccessibilityTree(host).filter { $0.isElement && $0.role != "AXGroup" }
}

/// ``filterA11yElements(_:)`` as comparable reads (static text's value only repeats its text).
@MainActor
private func filterA11yReads(_ host: NSView) -> [FilterA11yRead] {
    filterA11yElements(host).map {
        FilterA11yRead($0.role, $0.spokenName, $0.role == "AXStaticText" ? "" : $0.value, id: $0.identifier)
    }
}

/// Press an element the way VoiceOver, Voice Control or Full Keyboard Access does.
///
/// - Parameters:
///   - identifier: The element's accessibility identifier.
///   - host: The sheet's hosting view.
@MainActor
private func filterA11yPress(_ identifier: String, in host: NSView) throws {
    let element = try #require(nativeHostedAccessibilityElement(identifier, in: host), "\(identifier)")
    let press = NSSelectorFromString("accessibilityPerformPress")
    #expect(element.responds(to: press), "\(identifier) is pressable")
    _ = element.perform(press)
}

/// The value (0 or 1) of the element with `identifier`, or nil when it is not realized.
@MainActor
private func filterA11yValue(_ identifier: String, in host: NSView) -> String? {
    macAccessibilityTree(host).first { $0.identifier == identifier && $0.isElement }?.value
}

// MARK: - Tests

/// Accessibility of the Songs Filter sheet's General section without a profile (#432,
/// for #77).
///
/// #77 offered Filter to every viewer and added a General section (Year, Duration, Item
/// Shop, Double Bass) that is all the sheet shows without a selected profile. These
/// hosted tests run in `apple-ci` on the shared ``SongsFilterSheet`` (iPhone, iPhone
/// Duo, iPad and Mac) and read its accessibility tree. They check
/// the General heading, then each group as a disclosure control named with its hint
/// and reporting whether it is open (HIG Disclosure controls: "Provide a descriptive
/// label indicating what is disclosed or hidden"); each option as a toggle named for its
/// choice with its on/off state (HIG Toggles: "Accurately reflect state"); reading order
/// matching drawn order; Select All / Clear All named for their group (HIG Accessibility:
/// "Label elements appropriately for Voice Control"); activation through the
/// accessibility press; and hints that wrap rather than clip. iPhone 44 pt targets, the
/// audit and the largest text size are checked on device by
/// `SongsFilterAccessibilityJourneyTests`.
@MainActor
@Suite struct SongsFilterAccessibilityTests {
    /// Without a profile the sheet reads only General: its heading and hint, the groups
    /// in web order (Item Shop only while the Shop is shown), then Reset Filters. Groups
    /// start collapsed when nothing is restricted, and no player section is reachable.
    @Test(arguments: [true, false])
    func noProfileSheetReadsOnlyGeneralInOrder(_ showShop: Bool) async throws {
        let (host, window) = try await hostFilterA11ySheet(showShop: showShop)
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "songs-filter-no-profile-\(showShop ? "shop" : "no-shop")")
        let groups = showShop ? ["year", "duration", "shop", "double-bass"] : ["year", "duration", "double-bass"]
        let expected = [
            FilterA11yRead("AXHeading", "General", id: "fst.songs.filter.general"),
            FilterA11yRead("AXStaticText", "General filters that apply to all songs."),
        ] + groups.map {
            FilterA11yRead("AXDisclosureTriangle", filterA11yGroupNames[$0]!, "0", id: "fst.songs.filter.\($0)")
        } + [FilterA11yRead("AXButton", "Reset Filters", id: "fst.songs.filter.reset")]
        #expect(filterA11yReads(host) == expected)
        #expect(!nodes.contains { $0.identifier.contains(".score") || $0.identifier.contains(".instrument") },
                "no player section without a profile")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
    }

    /// Restricted groups open by themselves. Each reads its Select All / Clear All (named
    /// for the group), the group (expanded), then its options as toggles with their state;
    /// the Item Shop note follows its options. Reading order is drawn order, and no two
    /// actions share a name (#432: every open group's pair was "Select All", "Clear All").
    @Test func restrictedGroupsReadNamedOptionsWithStateInDrawnOrder() async throws {
        let (host, window) = try await hostFilterA11ySheet(filterA11yRestricted, shopAvailable: false)
        defer { window.orderOut(nil) }
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "songs-filter-no-profile-restricted")
        let prefix = "fst.songs.filter."
        func group(_ id: String) -> FilterA11yRead {
            FilterA11yRead("AXDisclosureTriangle", filterA11yGroupNames[id]!, "1", id: prefix + id)
        }
        func option(_ name: String, _ on: Bool, _ id: String) -> FilterA11yRead {
            FilterA11yRead("AXCheckBox", name, on ? "1" : "0", id: prefix + id)
        }
        func bulk(_ title: String, _ id: String) -> [FilterA11yRead] {
            [
                FilterA11yRead("AXButton", "Select All, \(title)", id: prefix + id + ".select-all"),
                FilterA11yRead("AXButton", "Clear All, \(title)", id: prefix + id + ".clear-all"),
            ]
        }
        let expected = [
            FilterA11yRead("AXHeading", "General", id: prefix + "general"),
            FilterA11yRead("AXStaticText", "General filters that apply to all songs."),
        ] + bulk("Year", "year") + [
            group("year"), option("1990s", false, "year.1990"), option("2000s", true, "year.2000"),
            option("2010s", true, "year.2010"), option("2020s", true, "year.2020"),
        ] + bulk("Duration", "duration") + [
            group("duration"), option("2-3 Minutes", true, "duration.2"),
            option("3-4 Minutes", true, "duration.3"), option("10+ Minutes", false, "duration.10"),
            group("shop"), option("Available in Item Shop", true, "shop-available"),
            option("Not Available in Item Shop", false, "shop-unavailable"),
            FilterA11yRead("AXStaticText", "Item Shop filters need matching public Songs and Shop data."),
            group("double-bass"), option("Double Bass Support", true, "double-bass.supported"),
            option("No Double Bass Support", false, "double-bass.unsupported"),
            FilterA11yRead("AXButton", "Reset Filters", id: prefix + "reset"),
        ]
        let reads = filterA11yReads(host)
        #expect(reads == expected)

        let actionable = reads.filter { ["AXButton", "AXCheckBox", "AXDisclosureTriangle"].contains($0.role) }
        #expect(Set(actionable.map(\.name)).count == actionable.count, "each action has its own name: \(actionable)")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")

        // Reading order is drawn order: top to bottom, and left to right within a row.
        let frames = try reads.filter { !$0.id.isEmpty }.map {
            ($0.id, try #require(nativeHostedAccessibilityFrame($0.id, in: host), "\($0.id)"))
        }
        for (previous, next) in zip(frames, frames.dropFirst()) {
            let sameRow = abs(previous.1.midY - next.1.midY) < 2
            #expect(sameRow ? previous.1.maxX <= next.1.minX + 0.5 : previous.1.minY < next.1.minY,
                    "\(previous.0) \(previous.1) reads before \(next.0) \(next.1)")
            #expect(previous.1.width > 0 && previous.1.height > 0, "\(previous.0) has a frame")
        }
    }

    /// Opening a group and changing an option through the accessibility press (VoiceOver,
    /// Voice Control, Full Keyboard Access) applies it at once and the toggle reports its
    /// new state; Select All / Clear All and Reset Filters apply too.
    @Test func pressingGroupsAndOptionsAppliesAndReportsState() async throws {
        let applied = FilterA11yApplied()
        let (host, window) = try await hostFilterA11ySheet(applied: applied)
        defer { window.orderOut(nil) }
        let prefix = "fst.songs.filter."

        try filterA11yPress(prefix + "double-bass", in: host)
        try await nativeHostedSettle(host, until: { filterA11yValue(prefix + "double-bass", in: host) == "1" })
        #expect(filterA11yValue(prefix + "double-bass.unsupported", in: host) == "1")
        try filterA11yPress(prefix + "double-bass.unsupported", in: host)
        try await nativeHostedSettle(host, until: {
            filterA11yValue(prefix + "double-bass.unsupported", in: host) == "0"
        })
        #expect(applied.general?.doubleBassUnsupported == false)
        #expect(applied.general?.doubleBassSupported == true)

        try filterA11yPress(prefix + "year", in: host)
        try await nativeHostedSettle(host, until: {
            nativeHostedAccessibilityElement(prefix + "year.clear-all", in: host) != nil
        })
        try filterA11yPress(prefix + "year.clear-all", in: host)
        try await nativeHostedSettle(host, until: {
            filterA11yDecades.allSatisfy { filterA11yValue(prefix + "year.\($0)", in: host) == "0" }
        })
        #expect(applied.general?.excludedDecades == Set(filterA11yDecades))
        try filterA11yPress(prefix + "year.select-all", in: host)
        try await nativeHostedSettle(host, until: {
            filterA11yDecades.allSatisfy { filterA11yValue(prefix + "year.\($0)", in: host) == "1" }
        })
        #expect(applied.general?.excludedDecades.isEmpty == true)

        try filterA11yPress(prefix + "reset", in: host)
        try await nativeHostedSettle(host, until: { applied.general == SongGeneralFilter() })
        #expect(filterA11yValue(prefix + "double-bass.unsupported", in: host) == "1")
    }

    /// With a profile, General still reads first and keeps the same names; the player
    /// sections follow it and Reset Filters stays last.
    @Test func withAProfileGeneralReadsBeforePlayerSections() async throws {
        let (host, window) = try await hostFilterA11ySheet(player: true)
        defer { window.orderOut(nil) }
        let ids = filterA11yElements(host).map(\.identifier).filter { !$0.isEmpty }
        let general = ["general", "year", "duration", "shop", "double-bass"].map { "fst.songs.filter.\($0)" }
        #expect(Array(ids.prefix(general.count)) == general, "\(ids)")
        let score = try #require(ids.firstIndex(of: "fst.songs.filter.score-sections"), "\(ids)")
        #expect(score == general.count)
        #expect(ids.last == "fst.songs.filter.reset")
    }

    /// The longest group name (Double Bass's hint) wraps in a narrow sheet rather than
    /// clipping, and stays inside the sheet. macOS does not scale fonts with Dynamic Type,
    /// so a narrow column stands in for large text (as in
    /// `quickLinksNestedRowLabelWrapsInsteadOfClipping`); the device check is
    /// `SongsFilterAccessibilityJourneyTests.testGeneralFiltersAtLargestText`.
    @Test func longGroupHintsWrapInsteadOfClipping() async throws {
        let (wide, wideWindow) = try await hostFilterA11ySheet(width: 600)
        defer { wideWindow.orderOut(nil) }
        let (narrow, narrowWindow) = try await hostFilterA11ySheet(width: 260)
        defer { narrowWindow.orderOut(nil) }
        let id = "fst.songs.filter.double-bass"
        let wideFrame = try #require(nativeHostedAccessibilityFrame(id, in: wide))
        let narrowFrame = try #require(nativeHostedAccessibilityFrame(id, in: narrow))
        #expect(narrowFrame.height > wideFrame.height * 1.3, "wide \(wideFrame), narrow \(narrowFrame)")
        #expect(narrowFrame.maxX <= 260 + 0.5, "\(narrowFrame)")
        #expect(filterA11yElements(narrow).first { $0.identifier == id }?.spokenName == filterA11yGroupNames["double-bass"])
    }
    /// The Item Shop and Suggestions filter sheets' Forms keep their rows' identifiers on
    /// the Mac too (`festivalFormIdentifier`): before #432 the Form's identifier replaced
    /// every row's, so no row could be told apart by identifier.
    @Test func siblingFilterFormsKeepTheirRowIdentifiers() async throws {
        let size = CGSize(width: 390, height: 900)
        let shop = nativeHostedView(
            ShopFilterSheet(applied: ShopOfferFilter()) { _ in }.preferredColorScheme(.dark), size: size
        )
        let shopWindow = nativeHostedWindow(shop, size: size)
        defer { shopWindow.orderOut(nil) }
        let suggestions = nativeHostedView(
            SuggestionsFilterSheet(applied: .defaults(), visibleInstruments: [.lead], onChange: { _ in })
                .preferredColorScheme(.dark),
            size: size
        )
        let suggestionsWindow = nativeHostedWindow(suggestions, size: size)
        defer { suggestionsWindow.orderOut(nil) }
        try await nativeHostedSettle(shop, until: {
            nativeHostedAccessibilityElement("fst.shop.filter.reset", in: shop) != nil
        })
        try await nativeHostedSettle(suggestions, until: {
            nativeHostedAccessibilityElement("fst.suggestions.filter.reset", in: suggestions) != nil
        })
        for (host, prefix) in [(shop as NSView, "fst.shop.filter."), (suggestions as NSView, "fst.suggestions.filter.")] {
            let ids = macAccessibilityTree(host).map(\.identifier).filter { $0.hasPrefix(prefix) }
            #expect(ids.filter { $0 == prefix + "form" }.count == 1, "\(ids)")
            #expect(Set(ids).count > 3, "rows keep their own identifiers: \(ids)")
        }
        #expect(nativeHostedAccessibilityElement("fst.shop.filter." + ShopAvailability.allCases[0].rawValue, in: shop) != nil)
    }
}
#endif
