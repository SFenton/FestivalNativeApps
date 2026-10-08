#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// A session that never reaches the network, optionally with a selected player.
@MainActor
private func navA11ySession(player: Bool) -> FestivalSession {
    guard player else { return FestivalSession(factory: { throw FestivalAPIError.invalidResource }) }
    let defaults = UserDefaults(suiteName: "fst.tests.nav-a11y.\(UUID().uuidString)")!
    defaults.set(
        Data(#"{"accountId":"fixture-1","displayName":"Fixture Player"}"#.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    return FestivalSession(factory: { throw FestivalAPIError.invalidResource }, selectionStorage: defaults)
}

/// Songs' Year sections, which bring Quick Links.
private let navA11ySections = [
    QuickLinkSection(id: "year-2024", title: "2024", icon: .system("calendar")),
    QuickLinkSection(id: "year-2023", title: "2023", icon: .system("calendar")),
]

/// A front page registering Songs' tools as `SongsScreen` does: Sort, Filter (labelled
/// "Filter Songs"), then Quick Links.
@MainActor
private func navA11ySongsRegistry(_ controller: QuickLinksController) -> PageToolsRegistry {
    let registry = PageToolsRegistry()
    let scope = UUID()
    registry.pageAppeared(scope)
    registry.upsert(id: UUID(), scope: scope, order: PageToolOrder.primary, content: AnyView(
        Button {} label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            .accessibilityValue("Title, ascending")
            .accessibilityIdentifier("fst.songs.sort")
    ))
    registry.upsert(id: UUID(), scope: scope, order: PageToolOrder.secondary, content: AnyView(
        Button {} label: { Label("Filter", systemImage: "line.3.horizontal.decrease") }
            .accessibilityLabel("Filter Songs")
            .accessibilityIdentifier("fst.songs.filter")
    ))
    registry.upsert(id: UUID(), scope: scope, order: PageToolOrder.quickLinks, content: AnyView(
        QuickLinksMenu(controller: controller)
    ))
    return registry
}

/// Host the real tab-bar accessory bar at an accessory's size.
///
/// iOS draws the accessory's buttons without a bezel; `.borderless` is the Mac host's
/// equivalent, so each button's frame is its label's (the macOS push-button bezel would
/// add padding the iPhone does not have).
@MainActor
private func hostNavA11yBar(
    _ registry: PageToolsRegistry, player: Bool, width: CGFloat, typeSize: DynamicTypeSize
) -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow) {
    let size = CGSize(width: width, height: NavButtonAccessibilityTests.accessoryHeight)
    let host = nativeHostedView(AnyView(
        PageToolsAccessoryBar(registry: registry)
            .environment(\.pageToolsRegistry, registry)
            .environment(\.festivalSession, navA11ySession(player: player))
            .environment(\.dynamicTypeSize, typeSize)
            .buttonStyle(.borderless)
            .preferredColorScheme(.dark)
    ), size: size)
    return (host, nativeHostedWindow(host, size: size))
}

/// The elements VoiceOver lands on, leaving out the host view and grouping containers.
private func navA11yControls(_ nodes: [MacAXNode]) -> [MacAXNode] {
    nodes.filter { $0.isElement && $0.role != "AXGroup" }
}

// MARK: - Tests

/// Accessibility of the navigation and page-tool buttons whose tap areas #15 widened
/// (#395).
///
/// #15 made the page tools' icon label fill its whole slot (now
/// ``PageToolsAccessoryLabelStyle``'s fixed 44 pt slots in the iPhone tab-bar
/// accessory, ``PageToolsAccessoryBar``) and the selected player's monogram a standard
/// bar button (``MonogramLabel`` in ``RootProfileButton``). Its near-miss taps are
/// simulator journeys (`NavButtonHitRegionJourneyTests`), which `apple-ci` does not run.
/// These hosted tests run there and pin the same region's accessibility on the real
/// views: each control's name, role, value and hint; left-to-right reading order;
/// 44 × 44 pt slots that never overlap (HIG Accessibility: "Strive for the platform's
/// recommended minimum control size", iOS 44×44 pt; HIG Buttons: "the hit region is at
/// least 44x44 pt"); and the same slots and names at the largest text size, where
/// the fixed-height accessory stops text at ``PageToolsAccessoryBar/maxTypeSize`` and
/// long-press shows the Large Content Viewer instead (pattern
/// `page-tools-and-nav-chrome` R3, R8).
@MainActor
@Suite struct NavButtonAccessibilityTests {
    /// Height of the expanded tab-bar accessory's content on iPhone (iOS 26.5).
    static let accessoryHeight: CGFloat = 48
    /// Songs' tools, then the bell, in reading order.
    static let songsIDs = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open", "fst.shell.notifications"]

    /// Songs' accessory reads Sort, Filter Songs, Quick Links, Notifications, left to right
    /// as drawn: each a named button carrying its state (Sort's order, Quick Links' current
    /// section), each a whole 44 pt slot that no neighbour overlaps, the bell on the
    /// trailing edge and the divider hidden. Holds expanded (348 pt) and inline (222 pt)
    /// on a 402 pt iPhone, and at the default and largest accessibility text sizes.
    @Test(arguments: [
        (CGFloat(348), DynamicTypeSize.large), (348, .accessibility5), (222, .large), (222, .accessibility5),
    ])
    func songsToolsReadInOrderAsNamedFullSlotButtons(_ width: CGFloat, _ typeSize: DynamicTypeSize) async throws {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let (host, window) = hostNavA11yBar(
            navA11ySongsRegistry(controller), player: true, width: width, typeSize: typeSize
        )
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, until: {
            Self.songsIDs.allSatisfy { nativeHostedAccessibilityElement($0, in: host) != nil }
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "nav-buttons-accessory-\(Int(width))-\(typeSize)")
        let container = try #require(nodes.first { $0.identifier == "fst.page-tools" })
        #expect(container.spokenName == "Page Tools")
        let elements = navA11yControls(nodes)
        #expect(elements.map(\.identifier) == Self.songsIDs, "reads left to right, nothing else: \(elements)")
        #expect(elements.map(\.spokenName) == ["Sort", "Filter Songs", "Quick Links", "Notifications"])
        // In the accessory Quick Links is a button that opens its choices (iOS 26 does not
        // open a `Menu` there), so its whole slot answers.
        #expect(elements.allSatisfy { $0.role == "AXButton" }, "\(elements)")
        #expect(elements[0].value == "Title, ascending")
        #expect(elements[2].value == "2024")
        #expect(elements[2].help == "Jumps to a section of this page")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")

        let frames = try Self.songsIDs.map { try #require(nativeHostedAccessibilityFrame($0, in: host)) }
        for (id, frame) in zip(Self.songsIDs, frames) {
            #expect(frame.width >= PageToolsAccessoryFit.slot - 0.5, "\(id) \(frame)")
            #expect(frame.height >= PageToolsAccessoryFit.slot - 0.5, "\(id) \(frame)")
            // A fixed slot: it neither grows with the text nor shares out the width.
            #expect(abs(frame.width - PageToolsAccessoryFit.slot) <= 0.5, "\(id) \(frame)")
        }
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxX <= $1.minX + 0.5 },
                "slots read in drawn order without overlapping: \(frames)")
        #expect(abs(frames[3].maxX - (width - PageToolsAccessoryFit.padding / 2)) <= 0.5,
                "Notifications keeps the trailing edge: \(frames[3])")
    }

    /// Activating Quick Links in the accessory (VoiceOver, Voice Control or a tap
    /// anywhere in its slot) opens its choices as a sheet in page order with the current
    /// section checked, and its spoken value follows a jump.
    @Test func accessoryQuickLinksPressOpensItsChoices() async throws {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let registry = navA11ySongsRegistry(controller)
        let (host, window) = hostNavA11yBar(registry, player: true, width: 348, typeSize: .large)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, until: {
            nativeHostedAccessibilityElement("fst.quick-links.open", in: host) != nil
        })
        let entry = try #require(nativeHostedAccessibilityElement("fst.quick-links.open", in: host))
        let press = NSSelectorFromString("accessibilityPerformPress")
        #expect(entry.responds(to: press))
        _ = entry.perform(press)
        let menu = try #require(registry.inlineMenu, "the press opens Quick Links' choices")
        #expect(menu.title == "Quick Links")
        #expect(menu.choices.map(\.id) == navA11ySections.map { "fst.quick-links.item.\($0.id)" })
        #expect(menu.choices.filter(\.isSelected).map(\.id) == ["fst.quick-links.item.year-2024"])

        registry.inlineMenuDismissed()
        controller.jump(to: "year-2023")
        try await nativeHostedSettle(host, until: {
            macAccessibilityTree(host).first { $0.identifier == "fst.quick-links.open" }?.value == "2023"
        })
    }

    /// Without a profile the accessory shows only the page's tools: no bell and no
    /// divider for VoiceOver to land on. With a profile and a page without tools it
    /// reads only Notifications, still a full slot on the trailing edge.
    @Test func accessoryReadsOnlyWhatItShows() async throws {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let (anonymous, anonymousWindow) = hostNavA11yBar(
            navA11ySongsRegistry(controller), player: false, width: 348, typeSize: .large
        )
        defer { anonymousWindow.orderOut(nil) }
        try await nativeHostedSettle(anonymous, until: {
            nativeHostedAccessibilityElement("fst.quick-links.open", in: anonymous) != nil
        })
        #expect(navA11yControls(macAccessibilityTree(anonymous)).map(\.identifier) == Array(Self.songsIDs.prefix(3)))

        let empty = PageToolsRegistry()
        empty.pageAppeared(UUID())
        let (bellOnly, bellWindow) = hostNavA11yBar(empty, player: true, width: 348, typeSize: .accessibility5)
        defer { bellWindow.orderOut(nil) }
        try await nativeHostedSettle(bellOnly, until: {
            nativeHostedAccessibilityElement("fst.shell.notifications", in: bellOnly) != nil
        })
        let elements = navA11yControls(macAccessibilityTree(bellOnly))
        #expect(elements.map(\.spokenName) == ["Notifications"])
        #expect(elements.first?.role == "AXButton")
        let bell = try #require(nativeHostedAccessibilityFrame("fst.shell.notifications", in: bellOnly))
        #expect(bell.width >= PageToolsAccessoryFit.slot - 0.5 && bell.height >= PageToolsAccessoryFit.slot - 0.5,
                "\(bell)")
        #expect(abs(bell.maxX - (348 - PageToolsAccessoryFit.padding / 2)) <= 0.5, "\(bell)")
    }

    /// The fixed-height accessory never lays out accessibility text sizes (they would clip
    /// in its fixed 44 pt slots); those sizes use the Large Content Viewer instead, and
    /// Songs folds Sort and Filter there so the slots still fit.
    @Test func accessoryCapsTextBelowAccessibilitySizes() {
        #expect(!PageToolsAccessoryBar.maxTypeSize.isAccessibilitySize)
        #expect(PageToolsAccessoryFit.folds(
            windowWidth: 402, pageTools: 3, showsBell: true, dynamicTypeSize: .accessibility1
        ))
    }

    /// The header's drawer and profile buttons are single named buttons at every text
    /// size: "Open Navigation" (not the "Menu" glyph title), "Choose Profile" or "Profile:
    /// <name>" with a hint naming where it goes. The monogram is drawing, never a separate
    /// image or a spoken initial, and on iOS it fills the bar item's 44 pt circle.
    @Test(arguments: [(false, DynamicTypeSize.large), (true, .large), (false, .accessibility5), (true, .accessibility5)])
    func headerButtonsAreNamedButtonsWithHints(_ player: Bool, _ typeSize: DynamicTypeSize) async throws {
        let size = CGSize(width: 240, height: 60)
        let host = nativeHostedView(
            HStack {
                DrawerButton(action: {})
                RootProfileButton(session: navA11ySession(player: player), action: {})
            }
            .environment(\.dynamicTypeSize, typeSize)
            .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, until: {
            nativeHostedAccessibilityElement("fst.shell.profile", in: host) != nil
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "nav-buttons-header-\(player)-\(typeSize)")
        let elements = navA11yControls(nodes)
        #expect(elements.map(\.identifier) == ["fst.shell.drawer.open", "fst.shell.profile"], "\(elements)")
        #expect(elements.allSatisfy { $0.role == "AXButton" }, "\(elements)")
        #expect(elements.map(\.spokenName) == ["Open Navigation", player ? "Profile: Fixture Player" : "Choose Profile"])
        #expect(elements[1].help == RootProfileButton.accessibilityHint(hasPlayer: player))
        #expect(!nodes.contains { $0.isElement && ($0.role == "AXImage" || $0.spokenName == "F") },
                "the monogram stays decorative: \(nodes)")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")
        #expect(RootProfileButton.MonogramMetrics.resolve(liquidGlassBar: true).diameter >= 44)
    }
}
#endif
