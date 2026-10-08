#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

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
