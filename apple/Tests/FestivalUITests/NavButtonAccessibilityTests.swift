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

/// Host the real floating page-tools row at its reserved height (issue #632).
///
/// `.borderless` is the Mac host's equivalent of iOS's bezel-less glass buttons, so each
/// button's frame is its label's 44 pt circle.
@MainActor
private func hostNavA11yBar(
    _ registry: PageToolsRegistry, width: CGFloat, typeSize: DynamicTypeSize, player: Bool = true
) -> (NSHostingView<NativeHostedRoot<AnyView>>, NSWindow) {
    let size = CGSize(width: width, height: FloatingPageToolsFit.reservedHeight)
    let host = nativeHostedView(AnyView(
        FloatingPageToolsBar(registry: registry)
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
/// (#395), as floating Liquid Glass buttons since #632.
///
/// #15 made the page tools' icon label fill its whole slot (now
/// ``FloatingPageToolLabelStyle``'s fixed 44 pt circles in the iPhone floating page tools,
/// ``FloatingPageToolsBar``) and the selected player's monogram a standard bar button
/// (``MonogramLabel`` in ``RootProfileButton``). Its near-miss taps are simulator journeys
/// (`NavButtonHitRegionJourneyTests`), which `apple-ci` does not run. These hosted tests
/// run there and pin the same region's accessibility on the real views: each control's
/// name, role, value and hint; left-to-right reading order; 44 × 44 pt circles that never
/// overlap (HIG Buttons: "Minimum hit region: 44x44 pt"); the same circles and names at the
/// largest text size, where the fixed-size row stops text at
/// ``FloatingPageToolsBar/maxTypeSize`` and long-press shows the Large Content Viewer
/// instead; no Notifications bell (it is in the header's account pill, #632); and nothing
/// for VoiceOver while a sheet covers the row (pattern `page-tools-and-nav-chrome` R3, R8).
@MainActor
@Suite struct NavButtonAccessibilityTests {
    /// Songs' tools in reading order.
    static let songsIDs = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open"]

    /// Songs' floating tools read Sort, Filter Songs, Quick Links, left to right as drawn:
    /// each a named button carrying its state (Sort's order, Quick Links' current section),
    /// each a whole 44 pt circle 10 pt from its neighbour, trailing-aligned 16 pt from the
    /// edge. Holds on 402 pt and 320 pt windows, at the default and largest accessibility
    /// text sizes.
    @Test(arguments: [
        (CGFloat(402), DynamicTypeSize.large), (402, .accessibility5), (320, .large), (320, .accessibility5),
    ])
    func songsToolsReadInOrderAsNamedFullSlotButtons(_ width: CGFloat, _ typeSize: DynamicTypeSize) async throws {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let (host, window) = hostNavA11yBar(navA11ySongsRegistry(controller), width: width, typeSize: typeSize)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, until: {
            Self.songsIDs.allSatisfy { nativeHostedAccessibilityElement($0, in: host) != nil }
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "nav-buttons-floating-\(Int(width))-\(typeSize)")
        let container = try #require(nodes.first { $0.identifier == "fst.page-tools" })
        #expect(container.spokenName == "Page Tools")
        let elements = navA11yControls(nodes)
        #expect(elements.map(\.identifier) == Self.songsIDs, "reads left to right, nothing else: \(elements)")
        #expect(elements.map(\.spokenName) == ["Sort", "Filter Songs", "Quick Links"])
        // A floating Quick Links is a button that opens its choices, so its whole circle answers.
        #expect(elements.allSatisfy { $0.role == "AXButton" }, "\(elements)")
        #expect(elements[0].value == "Title, ascending")
        #expect(elements[2].value == "2024")
        #expect(elements[2].help == "Jumps to a section of this page")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")

        let frames = try Self.songsIDs.map { try #require(nativeHostedAccessibilityFrame($0, in: host)) }
        for (id, frame) in zip(Self.songsIDs, frames) {
            // A fixed circle: it neither grows with the text nor shares out the width.
            #expect(abs(frame.width - FloatingPageToolsFit.slot) <= 0.5, "\(id) \(frame)")
            #expect(abs(frame.height - FloatingPageToolsFit.slot) <= 0.5, "\(id) \(frame)")
        }
        for (left, right) in zip(frames, frames.dropFirst()) {
            #expect(abs(right.minX - left.maxX - FloatingPageToolsFit.spacing) <= 0.5,
                    "separate circles \(FloatingPageToolsFit.spacing) pt apart: \(frames)")
        }
        #expect(abs(frames[2].maxX - (width - FloatingPageToolsFit.margin)) <= 0.5,
                "Quick Links keeps the trailing edge: \(frames[2])")
    }

    /// Activating the floating Quick Links (VoiceOver, Voice Control or a tap anywhere in
    /// its circle) opens its choices as a sheet in page order with the current section
    /// checked, the row hides while that sheet covers it, and its spoken value follows a jump.
    @Test func floatingQuickLinksPressOpensItsChoices() async throws {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let registry = navA11ySongsRegistry(controller)
        let (host, window) = hostNavA11yBar(registry, width: 402, typeSize: .large)
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

    /// The floating row never holds the Notifications bell (it is in the header's account
    /// pill, #632): with a profile, Songs reads only its three tools, and a page without
    /// tools gives VoiceOver nothing to land on.
    @Test func floatingRowReadsOnlyThePagesTools() async throws {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let (songs, songsWindow) = hostNavA11yBar(navA11ySongsRegistry(controller), width: 402, typeSize: .large)
        defer { songsWindow.orderOut(nil) }
        try await nativeHostedSettle(songs, until: {
            nativeHostedAccessibilityElement("fst.quick-links.open", in: songs) != nil
        })
        let nodes = macAccessibilityTree(songs)
        #expect(navA11yControls(nodes).map(\.identifier) == Self.songsIDs)
        #expect(!nodes.contains { $0.identifier == "fst.shell.notifications" })

        let empty = PageToolsRegistry()
        empty.pageAppeared(UUID())
        let (none, noneWindow) = hostNavA11yBar(empty, width: 402, typeSize: .accessibility5)
        defer { noneWindow.orderOut(nil) }
        try await nativeHostedSettle(none, until: { true })
        #expect(navA11yControls(macAccessibilityTree(none)).isEmpty)
    }

    /// While Notifications or another sheet covers the page the row hides from VoiceOver
    /// too, and it comes back with the same tools when the sheet closes (web hides its
    /// floating buttons while Notifications is open).
    @Test func coveredRowIsHiddenFromVoiceOver() async throws {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let registry = navA11ySongsRegistry(controller)
        let (host, window) = hostNavA11yBar(registry, width: 402, typeSize: .large)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, until: {
            nativeHostedAccessibilityElement("fst.songs.sort", in: host) != nil
        })
        registry.setCovered(true)
        try await nativeHostedSettle(host, until: {
            nativeHostedAccessibilityElement("fst.songs.sort", in: host) == nil
        })
        #expect(navA11yControls(macAccessibilityTree(host)).isEmpty)
        registry.setCovered(false)
        try await nativeHostedSettle(host, until: {
            Self.songsIDs.allSatisfy { nativeHostedAccessibilityElement($0, in: host) != nil }
        })
    }

    /// Issue #442 (for #89): on a page whose only tool is Quick Links (Leaderboards, Song
    /// Details' sections, the profile), it is one round icon-only button, never the
    /// full-width text capsule #89 reported. It reads as one "Quick Links" button with its
    /// current section and hint, in a fixed 44 × 44 pt circle on the trailing edge however
    /// wide the window is, at the default and largest accessibility text sizes.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func quickLinksAloneIsOneIconSlot(_ typeSize: DynamicTypeSize) async throws {
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let registry = PageToolsRegistry()
        let scope = UUID()
        registry.pageAppeared(scope)
        registry.upsert(id: UUID(), scope: scope, order: PageToolOrder.quickLinks, content: AnyView(
            QuickLinksMenu(controller: controller)
        ))
        let width: CGFloat = 402
        let (host, window) = hostNavA11yBar(registry, width: width, typeSize: typeSize)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, until: {
            nativeHostedAccessibilityElement("fst.quick-links.open", in: host) != nil
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "nav-buttons-quick-links-alone-\(typeSize)")
        let elements = navA11yControls(nodes)
        #expect(elements.map(\.identifier) == ["fst.quick-links.open"], "\(elements)")
        let quickLinks = try #require(elements.first)
        #expect(quickLinks.role == "AXButton")
        #expect(quickLinks.spokenName == "Quick Links")
        #expect(quickLinks.value == "2024")
        #expect(quickLinks.help == "Jumps to a section of this page")
        #expect(!nodes.contains { $0.role == "AXStaticText" && $0.spokenName == "Quick Links" },
                "the title is the button's name, not drawn text: \(nodes)")
        #expect(macAccessibilityFindings(nodes).isEmpty, "\(macAccessibilityFindings(nodes))")

        let frame = try #require(nativeHostedAccessibilityFrame("fst.quick-links.open", in: host))
        // Within a point: the Mac host rounds a lone circle's frame to whole pixels.
        #expect(frame.width >= FloatingPageToolsFit.slot - 0.5, "\(frame)")
        #expect(abs(frame.width - FloatingPageToolsFit.slot) <= 1, "one icon circle, not the row's width: \(frame)")
        #expect(abs(frame.height - FloatingPageToolsFit.slot) <= 1, "\(frame)")
        #expect(abs(frame.maxX - (width - FloatingPageToolsFit.margin)) <= 1, "on the trailing edge: \(frame)")
    }

    /// The fixed-size circles never lay out accessibility text sizes (they would clip);
    /// those sizes use the Large Content Viewer instead, and Songs keeps all three tools.
    @Test func floatingRowCapsTextBelowAccessibilitySizes() {
        #expect(!FloatingPageToolsBar.maxTypeSize.isAccessibilitySize)
        #expect(!FloatingPageToolsFit.folds(windowWidth: 402, pageTools: 3))
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
        #expect(RootProfileButton.MonogramMetrics.resolve(liquidGlassBar: true, inAccountPill: true).diameter == 30)
    }

    // MARK: iPhone Duo inner portrait (#633)

    /// iPhone Duo's inner display in portrait floats page tools above its tab bar (issue
    /// #633). Songs' bottom Filter Songs field stacks 8 pt above the floating row instead
    /// of covering it; VoiceOver reads the field, then Sort, Filter Songs and Quick Links;
    /// and each tool stays a whole 44 × 44 pt circle (HIG Buttons: "Minimum hit region:
    /// 44x44 pt"), at the default and largest accessibility text sizes.
    @Test(arguments: [DynamicTypeSize.large, .accessibility5])
    func duoInnerPortraitFieldStacksAboveFloatingTools(_ typeSize: DynamicTypeSize) async throws {
        let layout = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
        ), dualSource: false)
        #expect(FloatingPageToolsHost.floatsPageTools(in: layout))
        let controller = QuickLinksController()
        controller.configure(title: "Quick Links", explicit: navA11ySections)
        let registry = navA11ySongsRegistry(controller)
        let size = CGSize(width: 669, height: 951)
        let host = nativeHostedView(AnyView(
            NavigationStack {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<4, id: \.self) { index in
                            Text("Song \(index + 1)")
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        BottomSearchField(
                            text: .constant(""), prompt: "Filter Songs", accessibilityLabel: "Filter Songs",
                            identifier: "fst.songs.filter-field", clearIdentifier: "fst.songs.filter-clear",
                            hinge: nil, space: "page"
                        )
                    }
                    .coordinateSpace(.named("page"))
            }
            .floatingPageTools(isSelected: true)
            .environment(\.pageToolsRegistry, registry)
            .environment(\.deviceLayout, layout)
            .environment(\.festivalSession, navA11ySession(player: true))
            .environment(\.dynamicTypeSize, typeSize)
            .buttonStyle(.borderless)
            .preferredColorScheme(.dark)
        ), size: size)
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let ids = ["fst.songs.filter-field"] + Self.songsIDs
        try await nativeHostedSettle(host, until: {
            ids.allSatisfy { nativeHostedAccessibilityElement($0, in: host) != nil }
                && registry.floatingRowTop != nil
        })
        // The clearance applies on the next layout pass.
        try await nativeHostedSettle(host, until: {
            guard let field = nativeHostedAccessibilityFrame("fst.songs.filter-field", in: host),
                  let sort = nativeHostedAccessibilityFrame("fst.songs.sort", in: host) else { return false }
            return field.maxY < sort.minY
        })
        let nodes = macAccessibilityTree(host)
        macAccessibilityDump(nodes, name: "nav-buttons-duo-inner-portrait-\(typeSize)")
        let order = navA11yControls(nodes).map(\.identifier).filter { ids.contains($0) }
        #expect(order == ids, "field, then the tools left to right: \(order)")

        let field = try #require(nativeHostedAccessibilityFrame("fst.songs.filter-field", in: host))
        let rowTop = try #require(registry.floatingRowTop)
        let tools = try Self.songsIDs.map { try #require(nativeHostedAccessibilityFrame($0, in: host)) }
        for (id, frame) in zip(Self.songsIDs, tools) {
            #expect(abs(frame.width - FloatingPageToolsFit.slot) <= 0.5, "\(id) \(frame)")
            #expect(abs(frame.height - FloatingPageToolsFit.slot) <= 0.5, "\(id) \(frame)")
            #expect(!frame.intersects(field), "\(id) \(frame) clear of the field \(field)")
        }
        // The field's row ends 8 pt above the floating row (its glass may draw past the
        // text element by a point or two).
        #expect(field.maxY <= rowTop - BottomSearchFieldPlacement.rowPadding + 2, "\(field) row top \(rowTop)")
    }
}
#endif
