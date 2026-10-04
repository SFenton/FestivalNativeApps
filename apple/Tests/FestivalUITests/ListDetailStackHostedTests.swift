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

/// Records the section path a hosted `ListDetailStack` writes.
@MainActor
private final class PathRecorder {
    var path: [AppRoute] = []
}

/// Owns the path as real state so selection writes land (a `.constant` would drop them).
private struct PathHost<Content: View>: View {
    @State var path: [AppRoute]
    let recorder: PathRecorder
    @ViewBuilder let content: (Binding<[AppRoute]>) -> Content

    var body: some View {
        content($path).onChange(of: path, initial: true) { _, new in recorder.path = new }
    }
}

/// Host one section's `ListDetailStack` under an injected layout.
///
/// The root is a sparse synthetic list; when `row` is set it contains one
/// `ListDetailLink` to that route (the row auto-select can pick).
///
/// - Parameters:
///   - section: Section owning the path.
///   - path: The initial section path.
///   - layout: Injected `\.deviceLayout`.
///   - size: Host size in points.
///   - row: Detail route of the fixture row, if any.
///   - recorder: Receives the path as the stack writes it.
/// - Returns: The host and its offscreen window (retain both while asserting).
@MainActor
private func hostListDetail(
    section: FestivalSection, path: [AppRoute], layout: DeviceLayout, size: CGSize,
    row: AppRoute? = nil, recorder: PathRecorder = PathRecorder()
) -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    let session = offlineSession()
    let view = PathHost(path: path, recorder: recorder) { binding in
        ListDetailStack(
            section: section, session: session, visibleInstruments: Set(Instrument.allCases),
            path: binding, isVisible: true
        ) { rootIsTop in
            List {
                Text("Fixture List Root")
                Text(rootIsTop ? "Root On Top" : "Root Covered")
                SelectModeProbe()
                ColumnWidthProbe()
                if let row {
                    ListDetailLink(value: row) { Text("Fixture Row") }
                }
            }
        }
    }
    .environment(\.deviceLayout, layout)
    .frame(width: size.width, height: size.height)
    .preferredColorScheme(.dark)
    let host = nativeHostedView(view, size: size)
    return (host, nativeHostedWindow(host, size: size))
}

/// Readiness budget for split/auto-select waits: under a loaded parallel suite the
/// 120 ms auto-select window and the first loads outlasted the default 20 s (they pass
/// in under a second alone).
private let listDetailBudget: Duration = .seconds(90)

private let fixtureRival = AppRoute.rivalDetail(rivalId: "fixture-rival", name: "Fixture Rival", scope: nil)

// MARK: - Two populated columns

/// Unfolded landscape, Rivals splits and auto-selects the first row that appears:
/// the detail column is populated (never an empty "Select a Rival" pane).
@MainActor
@Test func listDetailAutoSelectsFirstRow() async throws {
    let size = CGSize(width: 951, height: 669)
    let recorder = PathRecorder()
    let (host, window) = hostListDetail(
        section: .rivals, path: [], layout: duoInner, size: size, row: fixtureRival, recorder: recorder
    )
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture List Root", "Rows Select", "No Player Selected"], excluding: ["Select a Rival"],
        timeout: listDetailBudget
    )
    _ = try nativeHostedPNG(image, filename: "list-detail-rivals-autoselected.png", environment: "FST_SHELL_RENDER_OUT")
    #expect(recorder.path == [fixtureRival])
}

/// A list page that shows no row collapses to one full-width stack instead of an
/// empty detail column; its rows would still select once one appears.
@MainActor
@Test func listDetailEmptyListCollapsesToFullWidth() async throws {
    let size = CGSize(width: 951, height: 669)
    let recorder = PathRecorder()
    let (host, window) = hostListDetail(section: .songs, path: [], layout: duoInner, size: size, recorder: recorder)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(
        host, untilText: ["Fixture List Root", "Root On Top", "Rows Select"], excluding: ["Loading"],
        timeout: listDetailBudget
    )
    #expect(recorder.path.isEmpty)
}

/// Inner display in portrait, flat or half-open (`/duo` D1, operator 2026-10-02: HIG
/// alignment): two columns side by side, the detail auto-selected and populated.
@MainActor
@Test func listDetailSplitsInInnerPortrait() async throws {
    let size = CGSize(width: 669, height: 951)
    let flat = DeviceLayout.resolve(LayoutSignals(size: size, widthClass: .regular, hinge: .fullyOpen))
    let half = DeviceLayout.resolve(LayoutSignals(
        size: size, widthClass: .regular, hinge: .partiallyOpen,
        divisions: [CGRect(x: 0, y: 455, width: 669, height: 41)]
    ))
    for (layout, name) in [(flat, "flat"), (half, "half")] {
        let recorder = PathRecorder()
        let (host, window) = hostListDetail(
            section: .rivals, path: [], layout: layout, size: size, row: fixtureRival, recorder: recorder
        )
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(
            host, untilText: ["Fixture List Root", "Rows Select", "No Player Selected"], excluding: ["Select a Rival"],
            timeout: listDetailBudget
        )
        _ = try nativeHostedPNG(
            image, filename: "list-detail-inner-portrait-\(name).png", environment: "FST_SHELL_RENDER_OUT"
        )
        #expect(recorder.path == [fixtureRival])
    }
}

/// `/duo` J3: in an inner-display split the list column's pages see a compact width
/// class (one dashboard column), while a full-width overview keeps regular.
@MainActor
@Test func duoSplitColumnsSeeCompactWidth() async throws {
    let portraitSize = CGSize(width: 669, height: 951)
    let portrait = DeviceLayout.resolve(LayoutSignals(size: portraitSize, widthClass: .regular, hinge: .fullyOpen))
    for (layout, size, name) in [
        (portrait, portraitSize, "portrait"), (duoInner, CGSize(width: 951, height: 669), "landscape"),
    ] {
        let (host, window) = hostListDetail(
            section: .rivals, path: [fixtureRival], layout: layout, size: size
        )
        defer { window.orderOut(nil) }
        let image = try await nativeHostedSettle(
            host, untilText: ["Fixture List Root", "Rows Select", "Width Compact", "No Player Selected"],
            excluding: ["Width Regular"]
        )
        _ = try nativeHostedPNG(
            image, filename: "duo-j3-split-\(name).png", environment: "FST_SHELL_RENDER_OUT"
        )
    }
    let (host, window) = hostListDetail(
        section: .leaderboards, path: [], layout: duoInner, size: CGSize(width: 951, height: 669)
    )
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["Fixture List Root", "Rows Push", "Width Regular"])
}

/// Folded and iPhone: one stack whose rows push; nothing is auto-selected.
@MainActor
@Test func listDetailStackOnNarrowLayouts() async throws {
    for (layout, size) in [
        (duoOuter, CGSize(width: 466, height: 678)), (DeviceLayout.standardPhone, CGSize(width: 466, height: 678)),
    ] {
        let recorder = PathRecorder()
        let (host, window) = hostListDetail(
            section: .rivals, path: [], layout: layout, size: size, row: fixtureRival, recorder: recorder
        )
        defer { window.orderOut(nil) }
        try await nativeHostedSettle(host, untilText: ["Fixture List Root", "Rows Push", "Fixture Row"])
        #expect(recorder.path.isEmpty)
    }
}

/// The Leaderboards overview (a dashboard, not a list page) stays one stack whose
/// cards push, even unfolded.
@MainActor
@Test func listDetailOverviewNeverSplits() async throws {
    let size = CGSize(width: 951, height: 669)
    let (host, window) = hostListDetail(section: .leaderboards, path: [], layout: duoInner, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host, untilText: ["Fixture List Root", "Rows Push"])
}

/// A selected detail fills the detail column while the list root stays on top of its
/// own column. Offline and anonymous, Rival Detail shows its own "No Player Selected"
/// state, which is enough to prove the column hosts the route.
@MainActor
@Test func listDetailSelectedDetailFillsColumn() async throws {
    let size = CGSize(width: 951, height: 669)
    let (host, window) = hostListDetail(section: .rivals, path: [fixtureRival], layout: duoInner, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture List Root", "Root On Top", "No Player Selected", "Rows Select"]
    )
    _ = try nativeHostedPNG(image, filename: "list-detail-rivals-selected.png", environment: "FST_SHELL_RENDER_OUT")
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

/// Shows the width class the page sees (`/duo` J3).
private struct ColumnWidthProbe: View {
    @Environment(\.deviceLayout) private var layout
    var body: some View { Text(layout.widthClass == .regular ? "Width Regular" : "Width Compact") }
}
#endif
