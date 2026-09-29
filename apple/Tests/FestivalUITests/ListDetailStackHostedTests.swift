#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalCore
@testable import FestivalUI

// MARK: - Fixtures

/// iPhone Duo inner display, landscape (regular width, vertical bar, fully open).
private let duoInner = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 951, height: 669), widthClass: .regular,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
    verticalBarEdge: .trailing, hinge: .fullyOpen
))

/// iPhone Duo outer display, portrait (compact width, folded).
private let duoOuter = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 466, height: 678), widthClass: .compact,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 34, trailing: 84),
    verticalBarEdge: .trailing, hinge: .closed
))

/// A session that never reaches the network.
@MainActor
private func offlineSession() -> FestivalSession {
    FestivalSession(factory: { throw FestivalAPIError.invalidResource })
}

/// Host one section's `ListDetailStack` under an injected layout.
///
/// The root is a deliberately sparse synthetic list, so page assertions use lower
/// ink thresholds than full-page snapshots.
///
/// - Parameters:
///   - section: Section owning the path.
///   - path: The section path.
///   - layout: Injected `\.deviceLayout`.
///   - size: Host size in points.
/// - Returns: The host and its offscreen window (retain both while asserting).
@MainActor
private func hostListDetail(
    section: FestivalSection, path: [AppRoute], layout: DeviceLayout, size: CGSize
) -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    let session = offlineSession()
    let view = ListDetailStack(
        section: section, session: session, visibleInstruments: Set(Instrument.allCases),
        path: .constant(path), isVisible: true
    ) { rootIsTop in
        List {
            Text("Fixture List Root")
            Text(rootIsTop ? "Root On Top" : "Root Covered")
            SelectModeProbe()
        }
    }
    .environment(\.deviceLayout, layout)
    .frame(width: size.width, height: size.height)
    .preferredColorScheme(.dark)
    let host = nativeHostedView(view, size: size)
    return (host, nativeHostedWindow(host, size: size))
}

// MARK: - Split vs stack

/// Unfolded with nothing selected, Songs is the list alone at full width (no empty
/// "Select a Song" pane), and its rows select into the detail column.
@MainActor
@Test func listDetailUnselectedShowsFullWidthList() async throws {
    let size = CGSize(width: 951, height: 669)
    let (host, window) = hostListDetail(section: .songs, path: [], layout: duoInner, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host, untilText: ["Fixture List Root", "Rows Select"])
    _ = try nativeHostedPNG(image, filename: "list-detail-songs-unselected.png", environment: "FST_SHELL_RENDER_OUT")
    assertRendersContent(
        host, image: image, minimumNonBackgroundFraction: 0.002, minimumInkFraction: 0.0005,
        containing: ["Fixture List Root", "Root On Top", "Rows Select"],
        notContaining: ["Select a Song"]
    )
}

/// Folded (and on iPhone), the same section is one stack whose rows push.
@MainActor
@Test func listDetailStackOnCompactLayouts() async throws {
    let size = CGSize(width: 466, height: 678)
    for layout in [duoOuter, DeviceLayout.standardPhone] {
        let (host, window) = hostListDetail(section: .songs, path: [], layout: layout, size: size)
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(host, untilText: ["Fixture List Root", "Rows Push"])
        assertRendersContent(
            host, image: image, minimumNonBackgroundFraction: 0.002, minimumInkFraction: 0.0005,
            containing: ["Fixture List Root", "Root On Top"],
            notContaining: ["Select a Song", "Rows Select"]
        )
    }
}

/// Rivals unselected is also the list alone; the Leaderboards overview (a dashboard,
/// not a list page) stays one stack whose cards push.
@MainActor
@Test func listDetailUnselectedPerListPage() async throws {
    let size = CGSize(width: 951, height: 669)
    let (rivalsHost, rivalsWindow) = hostListDetail(section: .rivals, path: [], layout: duoInner, size: size)
    defer { rivalsWindow.orderOut(nil) }
    try await nativeHostedSettle(rivalsHost, untilText: ["Fixture List Root", "Rows Select"], excluding: ["Select a Rival"])

    let (overviewHost, overviewWindow) = hostListDetail(
        section: .leaderboards, path: [], layout: duoInner, size: size
    )
    defer { overviewWindow.orderOut(nil) }
    try await nativeHostedSettle(overviewHost, untilText: ["Fixture List Root", "Rows Push"])
}

/// A selected detail fills the detail column while the list root
/// stays on top of its own column. Offline and anonymous, Rival Detail shows its own
/// "No Player Selected" state, which is enough to prove the column hosts the route.
@MainActor
@Test func listDetailSelectedDetailReplacesPlaceholder() async throws {
    let size = CGSize(width: 951, height: 669)
    let rival = AppRoute.rivalDetail(rivalId: "fixture-rival", name: "Fixture Rival", scope: nil)
    let (host, window) = hostListDetail(section: .rivals, path: [rival], layout: duoInner, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture List Root", "Root On Top", "No Player Selected"],
        excluding: ["Select a Rival"]
    )
    _ = try nativeHostedPNG(image, filename: "list-detail-rivals-selected.png", environment: "FST_SHELL_RENDER_OUT")
    assertRendersContent(host, image: image, containing: ["Rows Select"], notContaining: ["Select a Rival"])
}

// MARK: - Selected row

/// A row whose route is the current selection gets the selected treatment; others do not.
@MainActor
@Test func listDetailSelectableHighlightsOnlyTheSelectedRow() async throws {
    let size = CGSize(width: 320, height: 120)
    let selected = AppRoute.player(accountId: "a", displayName: "A")
    func render(selection: AppRoute?) async throws -> CGImage {
        let host = nativeHostedView(
            VStack(spacing: 0) {
                Text("Row A").frame(maxWidth: .infinity, minHeight: 60).listDetailSelectable(selected)
                Text("Row B").frame(maxWidth: .infinity, minHeight: 60)
                    .listDetailSelectable(.player(accountId: "b", displayName: "B"))
            }
            .background(Color.black)
            .environment(\.listDetailSelection, selection)
            .frame(width: size.width, height: size.height),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        defer { window.orderOut(nil) }
        return try await nativeHostedSettle(host, untilText: ["Row A", "Row B"])
    }
    let plain = try await render(selection: nil)
    let highlighted = try await render(selection: selected)
    #expect(nativeHostedSignature(plain) != nativeHostedSignature(highlighted))
    // Selecting a route no row shows leaves every row plain.
    let other = try await render(selection: .player(accountId: "z", displayName: nil))
    #expect(nativeHostedSignature(plain) == nativeHostedSignature(other))
}

/// Shows whether list rows would select into the detail column or push.
private struct SelectModeProbe: View {
    @Environment(\.listDetailSelect) private var select
    var body: some View { Text(select == nil ? "Rows Push" : "Rows Select") }
}
#endif
