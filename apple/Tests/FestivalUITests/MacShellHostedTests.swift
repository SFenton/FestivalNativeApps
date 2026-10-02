#if os(macOS)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// A session that never reaches the network (pages show their offline states).
@MainActor
private func offlineMacSession(player: Bool) -> FestivalSession {
    guard player else { return FestivalSession(factory: { throw FestivalAPIError.invalidResource }) }
    let suite = "fst.tests.mac-shell.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.set(
        Data(#"{"accountId":"fixture-1","displayName":"Fixture Player"}"#.utf8),
        forKey: SelectedPlayerIdentity.storageKey
    )
    return FestivalSession(factory: { throw FestivalAPIError.invalidResource }, selectionStorage: defaults)
}

/// Ink floor for whole-window shots: the sidebar's vibrant labels composite dark in a
/// never-shown offscreen window (only the footer paints white), so the default 0.2%
/// ink check reads the sidebar as blank. Text presence is asserted separately.
private let macWindowInk = 0.0003

/// Host the whole Mac window content (toolbar items are not hosted evidence).
@MainActor
private func hostMacRoot(
    player: Bool, initial: MacDestination, size: CGSize = MacWindowMetrics.defaultSize
) -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow, MacAppModel) {
    let model = MacAppModel(session: offlineMacSession(player: player), storage: nil, initial: initial)
    let host = nativeHostedView(
        MacRootView(model: model).frame(width: size.width, height: size.height), size: size
    )
    return (host, nativeHostedWindow(host, size: size), model)
}

// MARK: - Window

/// Anonymous window: Songs, Leaderboards and Item Shop in the sidebar and Select
/// Profile in its footer; no player-only rows.
@MainActor
@Test func macRootRendersAnonymousSidebar() async throws {
    let (host, window, model) = hostMacRoot(player: false, initial: .leaderboards)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Songs", "Leaderboards", "Item Shop", "Select Profile"])
    _ = try nativeHostedPNG(image, filename: "mac-root-anonymous.png", environment: "FST_SHELL_RENDER_OUT")
    assertRendersContent(
        host, image: image, minimumInkFraction: macWindowInk,
        containing: ["Songs", "Leaderboards", "Item Shop", "Select Profile"],
        notContaining: ["Statistics", "Deselect"]
    )
    #expect(model.navigation.selected == .leaderboards)
}

/// Selected player: every web sidebar row and the player with Deselect in the footer.
@MainActor
@Test func macRootRendersPlayerSidebarAndFooter() async throws {
    let (host, window, model) = hostMacRoot(player: true, initial: .shop)
    defer { window.orderOut(nil) }
    let rows = ["Suggestions", "Statistics", "Rivals", "Compete", "Leaderboards", "Item Shop"]
    let image = try await nativeHostedSettle(host, untilText: rows + ["Fixture Player", "Deselect"])
    _ = try nativeHostedPNG(image, filename: "mac-root-player.png", environment: "FST_SHELL_RENDER_OUT")
    assertRendersContent(
        host, image: image, minimumInkFraction: macWindowInk, containing: rows + ["Fixture Player", "Deselect"]
    )
    #expect(model.navigation.visible.count == 7)
}

/// Deselect in the footer removes the player-only rows and moves off Statistics.
@MainActor
@Test func macRootFooterDeselectAdaptsSidebar() async throws {
    let (host, window, model) = hostMacRoot(player: true, initial: .statistics)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["Fixture Player", "Deselect"])
    model.session.deselectPlayer()
    let image = try await nativeHostedSettle(host, untilText: ["Select Profile"], excluding: ["Deselect"])
    assertRendersContent(
        host, image: image, minimumInkFraction: macWindowInk,
        containing: ["Select Profile"], notContaining: ["Suggestions"]
    )
    #expect(model.navigation.selected == .songs)
}

/// The minimum window still shows the sidebar and one readable column.
@MainActor
@Test func macRootRendersAtMinimumSize() async throws {
    let (host, window, _) = hostMacRoot(player: false, initial: .shop, size: MacWindowMetrics.minimum)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Songs", "Item Shop", "Select Profile"])
    _ = try nativeHostedPNG(image, filename: "mac-root-minimum.png", environment: "FST_SHELL_RENDER_OUT")
    assertRendersContent(
        host, image: image, minimumInkFraction: macWindowInk, containing: ["Songs", "Item Shop", "Select Profile"]
    )
}

// MARK: - List/detail columns

@MainActor
private final class MacPathRecorder {
    var path: [AppRoute] = []
    var split: Bool?
}

private struct MacPathHost<Content: View>: View {
    @State var path: [AppRoute]
    let recorder: MacPathRecorder
    @ViewBuilder let content: (Binding<[AppRoute]>) -> Content

    var body: some View {
        content($path).onChange(of: path, initial: true) { _, new in recorder.path = new }
    }
}

private struct MacSelectModeProbe: View {
    @Environment(\.listDetailSelect) private var select
    var body: some View { Text(select == nil ? "Rows Push" : "Rows Select") }
}

private let macFixtureRival = AppRoute.rivalDetail(rivalId: "fixture-rival", name: "Fixture Rival", scope: nil)

@MainActor
private func hostMacListDetail(
    section: FestivalSection, path: [AppRoute], size: CGSize, row: AppRoute?, recorder: MacPathRecorder,
    collapseDelay: Duration = .milliseconds(2500)
) -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    let session = offlineMacSession(player: false)
    let view = MacPathHost(path: path, recorder: recorder) { binding in
        MacListDetailStack(
            section: section, session: session, visibleInstruments: Set(Instrument.allCases),
            path: binding, isVisible: true, onSplitChange: { recorder.split = $0 }
        ) { rootIsTop in
            List {
                Text("Fixture List Root")
                Text(rootIsTop ? "Root On Top" : "Root Covered")
                MacSelectModeProbe()
                if let row { ListDetailLink(value: row) { Text("Fixture Row") } }
            }
        }
    }
    .environment(\.macListCollapseDelay, collapseDelay)
    .frame(width: size.width, height: size.height)
    .preferredColorScheme(.dark)
    let host = nativeHostedView(view, size: size)
    return (host, nativeHostedWindow(host, size: size))
}

/// Wide content: two columns, and the first row fills the detail (never an empty pane).
@MainActor
@Test func macListDetailAutoSelectsFirstRow() async throws {
    let recorder = MacPathRecorder()
    let (host, window) = hostMacListDetail(
        section: .rivals, path: [], size: CGSize(width: 1060, height: 760), row: macFixtureRival, recorder: recorder,
        collapseDelay: .seconds(120)
    )
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture List Root", "Rows Select", "No Player Selected"], timeout: .seconds(60)
    )
    _ = try nativeHostedPNG(image, filename: "mac-list-detail.png", environment: "FST_SHELL_RENDER_OUT")
    #expect(recorder.path == [macFixtureRival])
    #expect(recorder.split == true)
}

/// Narrow content (minimum window): one column whose rows push; nothing auto-selected.
@MainActor
@Test func macListDetailOneColumnWhenNarrow() async throws {
    let recorder = MacPathRecorder()
    let (host, window) = hostMacListDetail(
        section: .rivals, path: [], size: CGSize(width: 560, height: 700), row: macFixtureRival, recorder: recorder
    )
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["Fixture List Root", "Rows Push", "Fixture Row"])
    #expect(recorder.path.isEmpty)
    #expect(recorder.split == false)
}

/// A list with no rows collapses to one column instead of a spinner beside it.
@MainActor
@Test func macListDetailEmptyListCollapses() async throws {
    let recorder = MacPathRecorder()
    let (host, window) = hostMacListDetail(
        section: .songs, path: [], size: CGSize(width: 1060, height: 760), row: nil, recorder: recorder
    )
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["Fixture List Root", "Rows Push"], excluding: ["Loading"])
    #expect(recorder.path.isEmpty)
}
#endif
