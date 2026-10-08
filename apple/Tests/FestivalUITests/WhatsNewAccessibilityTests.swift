#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI
import FestivalDesign

// MARK: - What's New accessibility (issue #80, backfilled by #434)

/// Issue #80 grouped What's New bullets under category headings, gave TestFlight and
/// development installs their own tester list, and added a spinner while the install
/// channel is detected. These hosted checks pin what that sheet exposes to VoiceOver,
/// Voice Control and larger text on every Apple platform (``WhatsNewSheet`` is the same
/// SwiftUI on iPhone, iPad, iPhone Duo and Mac): headings and bullets in visual order for
/// store and tester installs, an announced pending state, a full-width Dismiss target
/// below the list, and notes that wrap instead of truncating.
///
/// HIG VoiceOver: "Use titles and headings to convey hierarchy … Use accurate section
/// headings"; HIG Accessibility: "Strive for the platform's recommended minimum control
/// size" (iOS/iPadOS 44×44 pt default, macOS 28×28 pt default); HIG Typography: "Keep text
/// truncation to a minimum as font size increases. … Avoid truncating text in scrollable
/// regions".
@MainActor
@Suite(.serialized)
struct WhatsNewAccessibilityTests {
    // MARK: - Fixture

    /// The built (unreleased) version with store groups and a tester list, over an older
    /// released version whose notes are uncategorized, as `versioning.py whats-new` writes.
    static let entries = [
        ChangelogEntry(
            version: "2610.01.02", released: false, heading: "Version 2610.01.02",
            sections: [
                ChangelogSection(title: "Songs", items: ["Rows load faster."]),
                ChangelogSection(title: "Other", items: ["Fixed a crash."]),
            ],
            testerHeading: "Changes since release 2610.01.01",
            testerSections: [
                ChangelogSection(title: "Songs", items: ["Rows load faster.", "The A–Z index lands on the letter you tap."]),
                ChangelogSection(title: "Rivals", items: ["Rivals refresh correctly."]),
                ChangelogSection(title: "Other", items: ["Fixed a crash."]),
            ]
        ),
        ChangelogEntry(version: "2610.01.01", heading: "Version 2610.01.01", sections: [
            ChangelogSection(title: "", items: ["The first release of Festival Score Tracker for iPhone."]),
        ]),
    ]

    /// What VoiceOver should read, in order, before Dismiss: (role, name).
    static let storeOrder: [(String, String)] = [
        ("AXHeading", "Version 2610.01.02"),
        ("AXHeading", "Songs"), ("AXStaticText", "Rows load faster."),
        ("AXHeading", "Other"), ("AXStaticText", "Fixed a crash."),
        ("AXHeading", "Version 2610.01.01"),
        ("AXStaticText", "The first release of Festival Score Tracker for iPhone."),
    ]

    /// The tester list replaces the built version's store notes; older versions stay.
    static let testerOrder: [(String, String)] = [
        ("AXHeading", "Changes Since Release 2610.01.01"),
        ("AXHeading", "Songs"), ("AXStaticText", "Rows load faster."),
        ("AXStaticText", "The A–Z index lands on the letter you tap."),
        ("AXHeading", "Rivals"), ("AXStaticText", "Rivals refresh correctly."),
        ("AXHeading", "Other"), ("AXStaticText", "Fixed a crash."),
        ("AXHeading", "Version 2610.01.01"),
        ("AXStaticText", "The first release of Festival Score Tracker for iPhone."),
    ]

    /// One hosted sheet.
    struct Hosted {
        let host: NSHostingView<NativeHostedRoot<AnyView>>
        let window: NSWindow

        func close() { window.orderOut(nil) }
    }

    /// Host the sheet on a phone-size page and wait for its notes (or Dismiss).
    ///
    /// - Parameters:
    ///   - entries: Display entries; nil for the channel-pending spinner.
    ///   - size: Page size in points.
    ///   - layout: Device layout (the Duo vertical bar drops Dismiss).
    ///   - ready: Texts that must be in the accessibility tree.
    /// - Returns: The settled host and its window.
    /// - Throws: An unavailable capture.
    static func host(
        _ entries: [ChangelogEntry]?, size: CGSize = CGSize(width: 402, height: 874),
        layout: DeviceLayout = .standardPhone, ready: [String]
    ) async throws -> Hosted {
        let host = nativeHostedView(
            AnyView(
                WhatsNewSheet(version: "2610.01.02", entries: entries) {}
                    .environment(\.deviceLayout, layout)
                    .frame(width: size.width, height: size.height)
                    .background(BrandTokens.cardBackground)
                    .preferredColorScheme(.dark)
            ),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host, untilText: ready)
        return Hosted(host: host, window: window)
    }

    /// Containers and the scroll view's own scroll bar, which a screen reader passes through.
    static let structural: Set<String> = ["AXGroup", "AXScrollArea", "AXScrollBar"]

    /// Elements a screen reader stops on, in tree order.
    static func readable(_ nodes: [MacAXNode]) -> [MacAXNode] {
        nodes.filter { $0.isElement && !structural.contains($0.role) }
    }

    // MARK: - Names, roles and reading order

    /// Store and tester installs read each version (or the tester list) heading, then every
    /// category as a heading followed by its bullets, in the generated page order, and
    /// Dismiss last. An uncategorized list has no heading; the "•" glyphs and empty
    /// headings stay out of the tree.
    @Test(arguments: [AppDistribution.appStore, .testFlight, .development])
    func notesReadAsHeadingsThenTheirBulletsThenDismiss(_ distribution: AppDistribution) async throws {
        let expected = distribution == .appStore ? Self.storeOrder : Self.testerOrder
        let hosted = try await Self.host(
            Changelog.displayEntries(Self.entries, distribution: distribution),
            ready: expected.map(\.1) + ["Dismiss"]
        )
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "whats-new-\(distribution.rawValue)")
        let order = Self.readable(nodes)
        let read = order.map { "\($0.role) '\($0.spokenName)'" }

        #expect(order.count == expected.count + 1, "only the notes and Dismiss are read: \(read)")
        for (index, (role, name)) in expected.enumerated() where index < order.count {
            #expect(order[index].role == role && order[index].spokenName == name,
                    "#\(index) reads \(role) '\(name)': \(read)")
        }
        let dismiss = try #require(order.last)
        #expect(dismiss.role == "AXButton" && dismiss.spokenName == "Dismiss"
                && dismiss.identifier == "fst.whats-new.dismiss", "Dismiss is read last: \(dismiss)")

        #expect(!nodes.contains { $0.isElement && $0.spokenName == "•" }, "bullet glyphs are decorative")
        #expect(!order.contains { $0.role == "AXHeading" && $0.spokenName.isEmpty }, "no empty heading")
        if distribution == .appStore {
            #expect(!order.contains { $0.spokenName.hasPrefix("Changes") }, "store installs never see the tester list")
        } else {
            #expect(!order.contains { $0.spokenName == "Version 2610.01.02" }, "the tester list replaces the built version")
        }
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// Heading frames run top to bottom in reading order and every bullet sits under the
    /// heading it is read after, so the spoken order is the visual order.
    @Test func readingOrderMatchesTheVisualOrder() async throws {
        let hosted = try await Self.host(
            Changelog.displayEntries(Self.entries, distribution: .testFlight),
            ready: Self.testerOrder.map(\.1) + ["Dismiss"]
        )
        defer { hosted.close() }
        let host = hosted.host
        var frames: [CGRect] = []
        for (_, name) in Self.testerOrder {
            let element = try #require(nativeHostedAccessibilityElement(in: host) { object in
                ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
                    .contains { nativeHostedAccessibilityString(object, $0) == name }
            }, "\(name) in the tree")
            frames.append(try #require(nativeHostedAccessibilityFrame(of: element, in: host), "\(name) frame"))
        }
        for index in frames.indices.dropFirst() {
            #expect(frames[index].minY >= frames[index - 1].maxY - 0.5,
                    "'\(Self.testerOrder[index].1)' is below '\(Self.testerOrder[index - 1].1)': \(frames)")
        }
        let dismiss = try #require(nativeHostedAccessibilityFrame("fst.whats-new.dismiss", in: host))
        #expect(frames.allSatisfy { $0.maxY <= dismiss.minY + 0.5 }, "every note is above Dismiss: \(dismiss)")
    }

    /// While the install channel is detected the sheet says so (a named busy indicator),
    /// shows no notes, and Dismiss stays available.
    @Test func pendingChannelIsAnnouncedAndDismissable() async throws {
        let hosted = try await Self.host(nil, size: CGSize(width: 402, height: 600), ready: ["Dismiss"])
        defer { hosted.close() }
        let nodes = macAccessibilityTree(hosted.host)
        macAccessibilityDump(nodes, name: "whats-new-pending")
        let order = Self.readable(nodes)
        let spinner = try #require(order.first)
        #expect(spinner.role == "AXBusyIndicator" && spinner.spokenName == "Getting notes for this install"
                && spinner.identifier == "fst.whats-new.pending", "the named spinner is read first: \(spinner)")
        // The walker also reaches the AppKit spinner SwiftUI hosts under the named element
        // (its value is the animation state); only the named element carries a label.
        #expect(order.filter { $0.role == "AXBusyIndicator" && !$0.label.isEmpty }.count == 1, "\(order)")
        #expect(order.allSatisfy { ["AXBusyIndicator", "AXButton"].contains($0.role) }, "no notes while pending: \(order)")
        #expect(order.last?.identifier == "fst.whats-new.dismiss" && order.last?.spokenName == "Dismiss", "\(order)")
        #expect(macAccessibilityFindings(nodes) == [])
    }

    /// Beside the iPhone Duo vertical bar (`/duo` M1) the sheet has no Dismiss bar: the
    /// notes read in the same order and nothing else is added.
    @Test func duoVerticalBarReadsTheSameNotesWithoutDismiss() async throws {
        let size = CGSize(width: 466, height: 678)
        let folded = DeviceLayout.resolve(LayoutSignals(
            size: size, widthClass: .compact,
            safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
            verticalBarEdge: .trailing, hinge: .closed
        ))
        let hosted = try await Self.host(
            Changelog.displayEntries(Self.entries, distribution: .testFlight), size: size, layout: folded,
            ready: Self.testerOrder.map(\.1)
        )
        defer { hosted.close() }
        let order = Self.readable(macAccessibilityTree(hosted.host))
        #expect(order.map(\.spokenName) == Self.testerOrder.map(\.1), "\(order)")
        #expect(order.map(\.role) == Self.testerOrder.map(\.0), "\(order)")
    }

    // MARK: - Target size

    /// Dismiss is a full-width bar pinned to the bottom edge, outside the scrolling list,
    /// and its visible button is at least the platform's default control height here
    /// (macOS 28 pt); the element VoiceOver and Voice Control target is at least 44 pt tall.
    @Test func dismissIsAFullWidthTargetPinnedBelowTheList() async throws {
        let long = (1...30).map { "Note \($0) about a change on this page." }
        let entries = [ChangelogEntry(version: "2610.01.02", heading: "Version 2610.01.02", sections: [
            ChangelogSection(title: "Songs", items: long),
        ])]
        let size = CGSize(width: 402, height: 600)
        let hosted = try await Self.host(entries, size: size, ready: ["Version 2610.01.02", "Dismiss"])
        defer { hosted.close() }
        let host = hosted.host
        let dismiss = try #require(nativeHostedAccessibilityFrame("fst.whats-new.dismiss", in: host))
        #expect(dismiss.height >= 44 - 0.5, "Dismiss element is ≥ 44 pt tall: \(dismiss)")
        #expect(dismiss.width >= size.width - 0.5, "Dismiss spans the sheet: \(dismiss)")
        #expect(abs(dismiss.maxY - size.height) < 0.5, "Dismiss is pinned to the bottom: \(dismiss)")

        let scroll = try #require(nativeHostedAccessibilityElement(in: host) {
            nativeHostedAccessibilityString($0, "accessibilityRole") == "AXScrollArea"
        })
        let list = try #require(nativeHostedAccessibilityFrame(of: scroll, in: host))
        #expect(list.maxY <= dismiss.minY + 0.5, "the list ends above Dismiss, never under it: \(list) vs \(dismiss)")

        // The visible button: pixels that differ from the bar's own background, below its
        // 1 pt top hairline. (An offscreen window is inactive, so macOS draws the prominent
        // fill in its inactive gray rather than the accent.)
        let image = try nativeHostedImage(host, in: dismiss)
        _ = try nativeHostedPNG(image, filename: "whats-new-dismiss.png", environment: "FST_MAC_AX_OUT")
        let pixels = NativeHostedPixels(image)
        let scale = CGFloat(pixels.width) / dismiss.width
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        pixels.withBytes { bytes in
            func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let offset = (y * pixels.width + x) * 4
                return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
            }
            let background = rgb(Int(scale * 4), pixels.height / 2)
            for y in Int((scale * 2).rounded(.up))..<pixels.height {
                for x in 0..<pixels.width {
                    let pixel = rgb(x, y)
                    let distance = abs(pixel.0 - background.0) + abs(pixel.1 - background.1) + abs(pixel.2 - background.2)
                    guard distance > 12 else { continue }
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        try #require(minX <= maxX, "the Dismiss button is drawn")
        let button = CGSize(width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        #expect(button.height >= 28 - 0.5, "visible Dismiss is ≥ 28 pt tall (macOS default): \(button)")
        #expect(button.width >= size.width - 2 * 20 - 2, "visible Dismiss spans the sheet's margins: \(button)")
    }

    // MARK: - Text scaling

    /// Headings and bullets wrap onto as many lines as they need instead of truncating
    /// (the mechanism that keeps them whole at larger text sizes; macOS hosting keeps the
    /// font size, so a narrow column stands in for AX5), and Dismiss stays reachable.
    @Test func longNotesWrapInsteadOfTruncating() async throws {
        let note = "Songs now keep your place when you return from Song Details, even after the catalogue refreshes in the background while you were away."
        let entries = [ChangelogEntry(
            version: "2610.01.02", released: false, heading: "Version 2610.01.02",
            sections: [ChangelogSection(title: "Songs", items: ["Short note.", note])],
            testerHeading: "Changes so far (no release yet)",
            testerSections: [ChangelogSection(title: "Songs", items: ["Short note.", note])]
        )]
        let size = CGSize(width: 240, height: 700)
        let hosted = try await Self.host(
            Changelog.displayEntries(entries, distribution: .development), size: size,
            ready: ["Changes So Far (No Release Yet)", "Short note.", "Dismiss"]
        )
        defer { hosted.close() }
        let host = hosted.host
        func frame(_ name: String) throws -> CGRect {
            let element = try #require(nativeHostedAccessibilityElement(in: host) { object in
                ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"]
                    .contains { nativeHostedAccessibilityString(object, $0) == name }
            }, "\(name) in the tree")
            return try #require(nativeHostedAccessibilityFrame(of: element, in: host))
        }
        let short = try frame("Short note.")
        let wrapped = try frame(note)
        let heading = try frame("Changes So Far (No Release Yet)")
        let section = try frame("Songs")
        #expect(wrapped.height > short.height * 3, "the long note wraps onto several lines: \(wrapped) vs \(short)")
        #expect(wrapped.maxX <= size.width + 0.5, "the long note stays inside the sheet: \(wrapped)")
        #expect(heading.height > section.height * 1.5, "the long heading wraps: \(heading) vs \(section)")
        #expect(heading.maxX <= size.width + 0.5, "the heading stays inside the sheet: \(heading)")
        let dismiss = try #require(nativeHostedAccessibilityFrame("fst.whats-new.dismiss", in: host))
        #expect(dismiss.maxY <= size.height + 0.5 && dismiss.minY >= wrapped.maxY - 0.5, "Dismiss stays reachable: \(dismiss)")
    }
}
#endif
