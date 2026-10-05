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

/// Full Rankings starts full width (nothing auto-selected); with a player open it sits
/// beside the player's profile in the trailing half.
@MainActor
@Test func macFullRankingsSplitsOnDemand() async throws {
    let size = CGSize(width: 1060, height: 760)
    let session = macRankingsSession()
    let start = AppRoute.fullRankings(instrument: .lead, rankBy: "totalscore")
    let opened = AppRoute.player(accountId: "fixture-rank-1", displayName: "Fixture Rank 1")
    for (path, name) in [([start], "full-width"), ([start, opened], "open")] {
        let recorder = MacPageRecorder()
        let host = nativeHostedView(
            MacPageHost(path: path, recorder: recorder) { binding in
                MacListDetailStack(
                    section: .leaderboards, session: session, visibleInstruments: Set(Instrument.allCases),
                    path: binding, isVisible: true, onSplitChange: { _ in }
                ) { _ in LeaderboardsScreen(session: session) }
            }
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark)
            .macHostedStorage(),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(host, untilText: ["Fixture Rank 1"], timeout: .seconds(60))
        _ = try nativeHostedPNG(image, filename: "mac-full-rankings-\(name).png", environment: "FST_SHELL_RENDER_OUT")
        #expect(recorder.path == path, "Nothing is auto-selected")
    }
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

#endif
