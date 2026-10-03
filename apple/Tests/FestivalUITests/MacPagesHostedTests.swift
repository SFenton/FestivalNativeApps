#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// Public rankings over the shared `HostedRankingsTransport` (keyless, no selection).
@MainActor
private func macRankingsSession() -> FestivalSession {
    let client = try! FestivalAPI(baseURL: URL(string: "http://localhost")!, transport: HostedRankingsTransport())
    return FestivalSession(factory: { client })
}

/// Reduce Motion on: load-in fades never advance in an offscreen host.
private extension View {
    func macHostedStorage() -> some View {
        let defaults = UserDefaults(suiteName: "fst.tests.mac-pages.host")!
        defaults.set(true, forKey: "fst.accessibility.reduceMotion")
        return defaultAppStorage(defaults)
    }
}

/// Shows the width class a Mac column publishes to its pages.
private struct WidthClassProbe: View {
    @Environment(\.deviceLayout) private var layout
    var body: some View { Text(layout.widthClass == .regular ? "Regular Width" : "Compact Width") }
}

@MainActor
private final class MacPageRecorder {
    var path: [AppRoute] = []
}

private struct MacPageHost<Content: View>: View {
    @State var path: [AppRoute]
    let recorder: MacPageRecorder
    @ViewBuilder let content: (Binding<[AppRoute]>) -> Content

    var body: some View {
        content($path).onChange(of: path, initial: true) { _, new in recorder.path = new }
    }
}

// MARK: - Column width class

/// A Mac column publishes regular width from 720 pt and compact below, so pages pick
/// two card columns and readable widths from the column, not the window.
@MainActor
@Test func macColumnPublishesWidthClassFromItsWidth() async throws {
    let session = macRankingsSession()
    for (width, expected) in [(CGFloat(1060), "Regular Width"), (CGFloat(600), "Compact Width")] {
        let size = CGSize(width: width, height: 300)
        let host = nativeHostedView(
            MacStack(
                session: session, visibleInstruments: Set(Instrument.allCases),
                stackPath: .constant([]), fullPath: .constant([]), isVisible: true
            ) { WidthClassProbe() }
            .frame(width: size.width, height: size.height),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: [expected])
    }
}

// MARK: - Pages at Mac widths

/// Leaderboards at the default window's content width: instrument cards in two columns
/// (Lead beside Bass) with their top rows.
@MainActor
@Test func macLeaderboardsRendersTwoCardColumns() async throws {
    let size = CGSize(width: 1060, height: 760)
    let host = nativeHostedView(
        MacStack(
            session: macRankingsSession(), visibleInstruments: Set(Instrument.allCases),
            stackPath: .constant([]), fullPath: .constant([]), isVisible: true
        ) { LeaderboardsScreen(session: macRankingsSession()) }
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark)
        .macHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Lead", "Bass", "Fixture Rank 1", "View all rankings (3)"], timeout: .seconds(60)
    )
    _ = try nativeHostedPNG(image, filename: "mac-leaderboards.png", environment: "FST_SHELL_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Lead", "Bass", "Fixture Rank 1"])
}

/// Full Rankings beside the top-ranked player: the topmost row auto-selects into the
/// detail column (never an empty pane, never a lazily-built lower row).
@MainActor
@Test func macFullRankingsAutoSelectsTopRankedPlayer() async throws {
    let size = CGSize(width: 1060, height: 760)
    let session = macRankingsSession()
    let recorder = MacPageRecorder()
    let start = AppRoute.fullRankings(instrument: .lead, rankBy: "totalscore")
    let host = nativeHostedView(
        MacPageHost(path: [start], recorder: recorder) { binding in
            MacListDetailStack(
                section: .leaderboards, session: session, visibleInstruments: Set(Instrument.allCases),
                path: binding, isVisible: true, onSplitChange: { _ in }
            ) { _ in LeaderboardsScreen(session: session) }
        }
        // A loaded test host can take longer than 2.5 s to show the first row; the list
        // would then collapse to one column and never auto-select into the detail.
        .environment(\.macListCollapseDelay, .seconds(120))
        .frame(width: size.width, height: size.height)
        .preferredColorScheme(.dark)
        .macHostedStorage(),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, timeout: .seconds(60)) {
        recorder.path.count == 2
    }
    _ = try nativeHostedPNG(image, filename: "mac-full-rankings-split.png", environment: "FST_SHELL_RENDER_OUT")
    #expect(recorder.path == [start, .player(accountId: "fixture-rank-1", displayName: "Fixture Rank 1")])
}
/// The accessibility node with an identifier (selector-checked KVC, as
/// `nativeHostedAccessibility` does).
@MainActor
private func macAccessibilityNode(_ root: Any, identifier: String, depth: Int = 0) -> NSObject? {
    guard depth < 80, let object = root as? NSObject else { return nil }
    func read(_ key: String) -> Any? {
        object.responds(to: NSSelectorFromString(key)) ? object.value(forKey: key) : nil
    }
    if read("accessibilityIdentifier") as? String == identifier { return object }
    for child in (read("accessibilityChildren") as? [Any]) ?? [] {
        if let found = macAccessibilityNode(child, identifier: identifier, depth: depth + 1) { return found }
    }
    for subview in (object as? NSView)?.subviews ?? [] {
        if let found = macAccessibilityNode(subview, identifier: identifier, depth: depth + 1) { return found }
    }
    return nil
}

/// The list column follows a remembered divider width (clamped so the detail keeps its
/// minimum), else 38%; the divider is a slider to assistive technologies whose value is
/// the list width.
@MainActor
@Test func macListDetailDividerUsesRememberedWidth() async throws {
    let size = CGSize(width: 1060, height: 600)
    for (stored, expected) in [(0.0, 1060 * 0.38), (500.0, 500.0), (2000.0, 579.0)] {
        let defaults = UserDefaults(suiteName: "fst.tests.mac-divider.\(UUID().uuidString)")!
        defaults.set(true, forKey: "fst.accessibility.reduceMotion")
        defaults.set(stored, forKey: MacLayoutPolicy.listWidthKey)
        let session = macRankingsSession()
        let recorder = MacPageRecorder()
        let start = AppRoute.fullRankings(instrument: .lead, rankBy: "totalscore")
        let host = nativeHostedView(
            MacPageHost(path: [start], recorder: recorder) { binding in
                MacListDetailStack(
                    section: .leaderboards, session: session, visibleInstruments: Set(Instrument.allCases),
                    path: binding, isVisible: true, onSplitChange: { _ in }
                ) { _ in LeaderboardsScreen(session: session) }
            }
            // As above: a slow first row must not collapse the split being measured.
            .environment(\.macListCollapseDelay, .seconds(120))
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .defaultAppStorage(defaults),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        var value: Double?
        try await nativeHostedSettle(host, timeout: .seconds(60)) {
            let node = macAccessibilityNode(host, identifier: "fst.nav.column-divider")
            value = (node?.value(forKey: "accessibilityValue") as? NSNumber)?.doubleValue
            return node?.value(forKey: "accessibilityRole") as? String == "AXSlider" && value != nil
        }
        #expect(abs((value ?? 0) - expected) < 0.5, "stored \(stored): \(String(describing: value))")
    }
}
#endif
