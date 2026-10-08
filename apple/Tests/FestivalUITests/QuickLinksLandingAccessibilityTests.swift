#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Quick Links landing accessibility (#12, #393)
//
// #12 moved every Quick Links jump from flush with the top edge (under the iOS 26
// navigation bar's scroll-edge blur) to `QuickLinks.defaultActivationOffset` (32 pt)
// below it. These tests pin that from an assistive technology's side, on the
// `apple-ci` macOS host: the section a reader picks starts with a heading VoiceOver
// can reach by the Quick Links rotor or the headings rotor, in the menu's order; the
// jump leaves that heading fully visible below the top edge, with or without Reduce
// Motion and when larger text makes a section taller than the screen; and the Quick
// Links control speaks the section it landed on, also after quick successive jumps
// (a held ⌥⌘↓ Next Section, #393). The iPhone counterpart on the real
// navigation bar is `SettingsJourneyTests.testQuickLinksLandingIsAccessibleAtLargestText`.

/// Settings' Quick Links in page order: id, menu title and the element that starts the
/// section (`AXHeading` with that name, or the row's `AXButton`).
private let settingsQuickLinks: [(id: String, title: String, role: String, name: String)] = [
    ("app-settings", "App Settings", "AXHeading", "App Settings"),
    ("accessibility", "Accessibility", "AXHeading", "Accessibility"),
    ("item-shop", "Item Shop", "AXHeading", "Item Shop"),
    ("show-instruments", "Show Instruments", "AXHeading", "Show Instruments"),
    ("show-metadata", "Show Instrument Metadata", "AXHeading", "Show Instrument Metadata"),
    ("version", "Festival Score Tracker Version", "AXHeading", "Festival Score Tracker Version"),
    ("service-info", ServiceInfoText.title, "AXHeading", ServiceInfoText.title),
    ("first-run", "First Run Guides", "AXHeading", "First Run Guides"),
    ("licenses", "Licenses", "AXButton", "View Licenses"),
    ("privacy-policy", "Privacy Policy", "AXButton", "Privacy Policy"),
    ("reset", "Reset Settings", "AXHeading", "Reset Settings"),
]

/// The real Settings page, hosted as the iPhone and iPad show it (one column).
///
/// - Returns: The settled host and the window keeping it alive.
@MainActor
private func hostSettings() async throws -> (NSView, NSWindow) {
    let storage = UserDefaults(suiteName: "fst.tests.quick-links-a11y.\(UUID().uuidString)")!
    let session = FestivalSession(factory: { throw FestivalAPIError.invalidResource })
    let size = CGSize(width: 402, height: 844)
    let host = nativeHostedView(
        NavigationStack { SettingsScreen(session: session) }
            .defaultAppStorage(storage)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    _ = try await nativeHostedSettle(host, untilText: ["App Settings", "Reset Settings"])
    return (host, window)
}

// MARK: - Accessibility tree helpers

/// The accessibility objects under `root` in reading order (accessibility children,
/// then AppKit subviews), each visited once.
@MainActor
private func accessibilityObjects(_ root: NSView) -> [NSObject] {
    var objects: [NSObject] = []
    var seen = Set<ObjectIdentifier>()
    func walk(_ node: Any, depth: Int) {
        guard depth < 90, let object = node as? NSObject,
              seen.insert(ObjectIdentifier(object)).inserted else { return }
        objects.append(object)
        for child in (axRead(object, "accessibilityChildren") as? [Any]) ?? [] {
            walk(child, depth: depth + 1)
        }
        if let view = object as? NSView {
            for subview in view.subviews { walk(subview, depth: depth + 1) }
        }
    }
    walk(root, depth: 0)
    return objects
}

/// An accessibility attribute, or nil when the object does not answer it.
private func axRead(_ object: NSObject, _ key: String) -> Any? {
    object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
}

/// An accessibility attribute as text.
private func axString(_ object: NSObject, _ key: String) -> String {
    switch axRead(object, key) {
    case let text as String: text
    case let attributed as NSAttributedString: attributed.string
    default: ""
    }
}

/// Frame of the heading named `title`, in `host`'s top-left points.
///
/// - Parameters:
///   - title: The heading's accessibility label.
///   - host: The window's hosting view.
/// - Returns: The frame, or nil while no such heading is realized.
@MainActor
private func headingFrame(_ title: String, in host: NSView) -> CGRect? {
    guard let window = host.window, let heading = accessibilityObjects(host).first(where: {
        axString($0, "accessibilityRole") == "AXHeading" && axString($0, "accessibilityLabel") == title
    }), let screen = (axRead(heading, "accessibilityFrame") as? NSValue)?.rectValue else { return nil }
    let local = host.convert(window.convertFromScreen(screen), from: nil)
    return host.isFlipped ? local : CGRect(
        x: local.minX, y: host.bounds.height - local.maxY, width: local.width, height: local.height
    )
}

// MARK: - Settings: what a Quick Link lands on

@Suite("Quick Links landing accessibility (#12)")
@MainActor
struct QuickLinksLandingAccessibilityTests {
    /// Every Settings Quick Link starts its section with a named heading (or the row's
    /// named button), and they read in the menu's order, so after a jump VoiceOver's
    /// next swipe or headings rotor lands on the section the reader picked (HIG
    /// VoiceOver: "Use accurate section headings").
    @Test func settingsQuickLinkTargetsAreNamedHeadingsInMenuOrder() async throws {
        let (host, window) = try await hostSettings()
        defer { window.orderOut(nil) }
        let elements = accessibilityObjects(host).filter {
            (axRead($0, "isAccessibilityElement") as? Bool) == true
        }
        var previous = -1
        for link in settingsQuickLinks {
            let index = try #require(
                elements.firstIndex {
                    axString($0, "accessibilityRole") == link.role
                        && axString($0, "accessibilityLabel") == link.name
                },
                "\(link.title) does not start with a \(link.role) named '\(link.name)'"
            )
            #expect(index > previous, "\(link.title) reads before the section above it")
            previous = index
        }
    }

    /// The page's VoiceOver "Quick Links" rotor offers the same sections, named as in
    /// the menu, in page order (HIG VoiceOver: "Support the VoiceOver rotor").
    @Test func settingsQuickLinksRotorListsSectionsInPageOrder() async throws {
        let (host, window) = try await hostSettings()
        defer { window.orderOut(nil) }
        let rotor = try #require(
            accessibilityObjects(host).lazy
                .compactMap { axRead($0, "accessibilityCustomRotors") as? [NSAccessibilityCustomRotor] }
                .joined()
                .first { $0.label == "Quick Links" },
            "Settings has no Quick Links rotor"
        )
        let delegate = try #require(rotor.itemSearchDelegate)
        var labels: [String] = []
        var current: NSAccessibilityCustomRotor.ItemResult?
        for _ in 0..<(settingsQuickLinks.count + 2) {
            let parameters = NSAccessibilityCustomRotor.SearchParameters()
            parameters.currentItem = current
            parameters.searchDirection = .next
            guard let next = delegate.rotor(rotor, resultFor: parameters) else { break }
            labels.append(next.customLabel ?? "")
            current = next
        }
        #expect(labels == settingsQuickLinks.map(\.title))
    }
}

// MARK: - The shared container: where a jump lands the heading

/// One hosted landing case: how the page differs from the default.
struct QuickLinksLandingCase: CustomTestStringConvertible, Sendable {
    let name: String
    /// The system Reduce Motion setting.
    let reduceMotion: Bool
    /// Rows grown as at the largest accessibility text size, so one section is
    /// taller than the screen (the anchor then goes negative).
    let largestText: Bool
    var testDescription: String { name }
}

/// A Settings-shaped page on the canonical container: `FestivalSectionHeader` cards
/// in an eager stack, the Quick Links control above it, as the page tools show it.
private struct LandingFixturePage: View {
    let controller: QuickLinksController
    let largestText: Bool

    /// (id, title, row count): short and long sections, one longer than the screen
    /// at the largest text size.
    static let sections: [(id: String, title: String, rows: Int)] = [
        ("first", "App Settings", 7), ("second", "Accessibility", 4), ("third", "Item Shop", 2),
        ("fourth", "Show Instruments", 9), ("fifth", "Show Instrument Metadata", 8),
        ("sixth", "Service Info", 2), ("seventh", "First Run Guides", 9), ("eighth", "Reset Settings", 1),
    ]

    var body: some View {
        VStack(spacing: 0) {
            QuickLinksMenu(controller: controller)
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(Self.sections, id: \.id) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            FestivalSectionHeader(section.title, subtitle: "What \(section.title) changes.")
                            ForEach(0..<section.rows, id: \.self) { row in
                                Text("\(section.title) option \(row + 1)")
                                    .frame(maxWidth: .infinity, minHeight: largestText ? 132 : 44, alignment: .leading)
                            }
                        }
                        .quickLinkSection(id: section.id, title: section.title)
                    }
                }
                .padding(16)
            }
            .quickLinks(controller, title: "Quick Links")
        }
        .dynamicTypeSize(largestText ? .accessibility5 : .large)
    }
}

extension QuickLinksLandingAccessibilityTests {
    /// Each jump leaves the target's heading whole and readable 32 pt below the scroll
    /// view's top edge, clear of where the iOS 26 navigation bar blurs content (#12),
    /// and the Quick Links control's VoiceOver value names it. Holds with Reduce Motion
    /// (jumps are instant either way) and when the largest text sizes make a section
    /// taller than the screen. The last section cannot scroll that far, so it only has
    /// to be fully visible below the line (HIG Layout: system bars must not "cover
    /// controls/content"; HIG Typography: "Make sure your layout adapts to all font sizes").
    @Test(arguments: [
        QuickLinksLandingCase(name: "default", reduceMotion: false, largestText: false),
        QuickLinksLandingCase(name: "reduce motion", reduceMotion: true, largestText: false),
        QuickLinksLandingCase(name: "largest text", reduceMotion: false, largestText: true),
        QuickLinksLandingCase(name: "largest text, reduce motion", reduceMotion: true, largestText: true),
    ])
    func jumpsLandTheHeadingWholeBelowTheTopEdge(_ landing: QuickLinksLandingCase) async throws {
        let controller = QuickLinksController()
        let size = CGSize(width: 402, height: 700)
        let host = nativeHostedView(
            LandingFixturePage(controller: controller, largestText: landing.largestText)
                .environment(\._accessibilityReduceMotion, landing.reduceMotion)
                .preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host, untilText: ["App Settings"], timeout: .seconds(60))
        let sections = LandingFixturePage.sections
        #expect(controller.sections.map(\.title) == sections.map(\.title))

        let scrollView = try #require(scrollViewFrame(in: host))
        let line = QuickLinks.defaultActivationOffset
        if landing.largestText {
            let tallest = try #require(controller.currentFrame(for: "fourth"))
            #expect(tallest.maxY - tallest.minY > scrollView.height, "no section outgrows the screen")
        }
        // Down, back up, a section taller than the screen at the largest sizes, the end.
        for id in ["third", "second", "fourth", "sixth", "eighth"] {
            let title = try #require(sections.first { $0.id == id }?.title)
            let isLast = id == sections.last?.id
            controller.jump(to: id)
            var budget = NativeHostedPollBudget(.seconds(60))
            var heading: CGRect?
            var stable = 0
            while !budget.isExhausted {
                try await budget.sleep(for: .milliseconds(30))
                let frame = headingFrame(title, in: host).map { $0.offsetBy(dx: 0, dy: -scrollView.minY) }
                stable = frame != nil && frame == heading ? stable + 1 : 0
                heading = frame
                guard let frame, stable >= 2, controller.activeID == id else { continue }
                if isLast || abs(frame.minY - line) <= 1.5 { break }
            }
            let landed = try #require(heading, "\(title)'s heading is not realized after the jump")
            if isLast {
                #expect(landed.minY >= line - 1.5, "\(title) landed \(landed.minY) pt from the top, under the bar")
            } else {
                #expect(abs(landed.minY - line) <= 1.5, "\(title) landed \(landed.minY) pt from the top; expected \(line)")
            }
            #expect(landed.maxY <= scrollView.height, "\(title)'s heading is cut off at the bottom")
            #expect(controller.activeSection?.title == title)
            let menu = try #require(
                accessibilityObjects(host).first { axString($0, "accessibilityIdentifier") == "fst.quick-links.open" },
                "the Quick Links control is not exposed"
            )
            // AppKit names a menu button by AXTitle; UIKit (XCUITest) by its label.
            let label = axString(menu, "accessibilityLabel")
            #expect((label.isEmpty ? axString(menu, "accessibilityTitle") : label) == "Quick Links")
            #expect(axString(menu, "accessibilityHelp") == "Jumps to a section of this page")
            #expect(axString(menu, "accessibilityValue") == title, "Quick Links does not speak the landed section")
        }
    }

    /// Jumps in quick succession, as a held ⌥⌘↓ Next Section or a quick rotor flick
    /// makes them, end on the last one: an earlier jump's corrective pass must not
    /// scroll back to its own target or settle the newer jump, which left Quick Links
    /// naming another section than the one on screen (#393).
    @Test func quickSuccessiveJumpsEndOnTheLastSection() async throws {
        let controller = QuickLinksController()
        let size = CGSize(width: 402, height: 700)
        let host = nativeHostedView(
            LandingFixturePage(controller: controller, largestText: false).preferredColorScheme(.dark),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        _ = try await nativeHostedSettle(host, untilText: ["App Settings"], timeout: .seconds(60))
        let scrollView = try #require(scrollViewFrame(in: host))
        let line = QuickLinks.defaultActivationOffset
        let sections = LandingFixturePage.sections
        func headingTop(_ title: String) -> CGFloat? {
            headingFrame(title, in: host).map { $0.minY - scrollView.minY }
        }

        // Each next jump starts as soon as the previous one reaches its line, while
        // that jump's corrective pass is still polling.
        for id in ["second", "third", "fourth", "fifth"] {
            let title = try #require(sections.first { $0.id == id }?.title)
            controller.jump(to: id)
            var budget = NativeHostedPollBudget(.seconds(60))
            while !budget.isExhausted, headingTop(title).map({ abs($0 - line) > 1.5 }) ?? true {
                try await budget.sleep(for: .milliseconds(10))
            }
        }
        controller.jump(to: "sixth")
        var budget = NativeHostedPollBudget(.seconds(60))
        while !budget.isExhausted, headingTop("Service Info").map({ abs($0 - line) > 1.5 }) ?? true {
            try await budget.sleep(for: .milliseconds(10))
        }
        // Then watch past the corrective passes' 3 s deadline: nothing may move.
        let until = ContinuousClock.now + .seconds(4)
        var drift: [String] = []
        while ContinuousClock.now < until {
            try await Task.sleep(for: .milliseconds(50))
            let top = headingTop("Service Info")
            if controller.activeID != "sixth" || top.map({ abs($0 - line) > 1.5 }) ?? true {
                drift.append("\(controller.activeID ?? "nil")@\(top.map { "\(Int($0))" } ?? "off")")
            }
        }
        #expect(drift.isEmpty, "The page or the active section moved after the last jump: \(drift.prefix(6))")
        #expect(controller.activeSection?.title == "Service Info")
        let menu = try #require(
            accessibilityObjects(host).first { axString($0, "accessibilityIdentifier") == "fst.quick-links.open" }
        )
        #expect(axString(menu, "accessibilityValue") == "Service Info", "Quick Links names another section")
    }

    /// The hosted scroll view's frame in `host`'s top-left points.
    private func scrollViewFrame(in host: NSView) -> CGRect? {
        func find(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.lazy.compactMap(find).first
        }
        guard let scroll = find(host) else { return nil }
        let local = host.convert(scroll.bounds, from: scroll)
        return host.isFlipped ? local : CGRect(
            x: local.minX, y: host.bounds.height - local.maxY, width: local.width, height: local.height
        )
    }
}
#endif
