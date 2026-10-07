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

/// Records the section path a hosted `OnDemandSplitStack` writes.
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

/// Host one section's `OnDemandSplitStack` under an injected layout.
///
/// - Parameters:
///   - section: Section owning the path.
///   - path: The initial section path.
///   - layout: Injected `\.deviceLayout`.
///   - size: Host size in points.
///   - recorder: Receives the path as the stack writes it.
/// - Returns: The host and its offscreen window (retain both while asserting).
@MainActor
private func hostSplit(
    section: FestivalSection, path: [AppRoute], layout: DeviceLayout, size: CGSize,
    recorder: PathRecorder = PathRecorder()
) -> (NSHostingView<NativeHostedRoot<some View>>, NSWindow) {
    let session = offlineSession()
    let view = PathHost(path: path, recorder: recorder) { binding in
        OnDemandSplitStack(
            section: section, session: session, visibleInstruments: Set(Instrument.allCases),
            path: binding, isVisible: true
        ) { rootIsTop in
            List {
                Text("Fixture List Root")
                Text(rootIsTop ? "Root On Top" : "Root Covered")
                SelectModeProbe()
                ColumnWidthProbe()
                BackdropProbe()
            }
        }
    }
    .environment(\.deviceLayout, layout)
    .frame(width: size.width, height: size.height)
    .preferredColorScheme(.dark)
    let host = nativeHostedView(view, size: size)
    return (host, nativeHostedWindow(host, size: size))
}

private let splitBudget: Duration = .seconds(90)

private let fixtureRival = AppRoute.rivalDetail(rivalId: "fixture-rival", name: "Fixture Rival", scope: nil)

private let duoInnerPortrait = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 669, height: 951), widthClass: .regular, hinge: .fullyOpen
))

// MARK: - Starts full width

/// Landscape inner display, nothing open: the list page is full width (regular width
/// class, no trailing pane), and its rows would open the trailing pane.
@MainActor
@Test func splitStartsFullWidth() async throws {
    let size = CGSize(width: 951, height: 669)
    let recorder = PathRecorder()
    let (host, window) = hostSplit(section: .rivals, path: [], layout: duoInner, size: size, recorder: recorder)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host, untilText: ["Fixture List Root", "Root On Top", "Rows Select", "Width Regular", "Backdrop Shared"],
        excluding: ["Close", "No Player Selected"], timeout: splitBudget
    )
    _ = try nativeHostedPNG(image, filename: "split-rivals-full-width.png", environment: "FST_SHELL_RENDER_OUT")
    #expect(recorder.path.isEmpty, "Nothing is auto-selected (operator 2026-10-04)")
}

/// An open item fills the trailing half beside the list, which keeps its own top page
/// and now sees a compact pane width; the trailing root has a Close button.
@MainActor
@Test func splitOpenItemFillsTrailingHalf() async throws {
    let size = CGSize(width: 951, height: 669)
    let (host, window) = hostSplit(section: .rivals, path: [fixtureRival], layout: duoInner, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(
        host,
        untilText: ["Fixture List Root", "Root On Top", "No Player Selected", "Rows Select", "Width Compact", "Backdrop Shared"],
        timeout: splitBudget
    )
    _ = try nativeHostedPNG(image, filename: "split-rivals-open.png", environment: "FST_SHELL_RENDER_OUT")
}

/// Portrait inner display, folded and iPhone: one stack whose rows push.
@MainActor
@Test func splitPushesInPortraitAndCompact() async throws {
    for (layout, size) in [
        (duoInnerPortrait, CGSize(width: 669, height: 951)),
        (duoOuter, CGSize(width: 466, height: 678)),
        (DeviceLayout.standardPhone, CGSize(width: 466, height: 678)),
    ] {
        let recorder = PathRecorder()
        let (host, window) = hostSplit(section: .rivals, path: [], layout: layout, size: size, recorder: recorder)
        defer { window.orderOut(nil) }
        // One stack: the page draws its own backdrop copy.
        try await nativeHostedSettle(host, untilText: ["Fixture List Root", "Rows Push", "Backdrop Own"], timeout: splitBudget)
        #expect(recorder.path.isEmpty)
    }
}

/// Songs never splits; the Leaderboards overview does (cards open players).
@MainActor
@Test func splitPageClassificationHosted() async throws {
    let size = CGSize(width: 951, height: 669)
    let (songs, songsWindow) = hostSplit(section: .songs, path: [], layout: duoInner, size: size)
    defer { songsWindow.orderOut(nil) }
    try await nativeHostedSettle(songs, untilText: ["Fixture List Root", "Rows Push", "Width Regular"], timeout: splitBudget)
    let (boards, boardsWindow) = hostSplit(section: .leaderboards, path: [], layout: duoInner, size: size)
    defer { boardsWindow.orderOut(nil) }
    try await nativeHostedSettle(boards, untilText: ["Fixture List Root", "Rows Select"], timeout: splitBudget)
}

// MARK: - Fold and unfold

/// The Duo pose a hosted split sees: the inner display (landscape) or the outer one.
@MainActor @Observable
private final class FoldPose {
    var folded = false
}

/// Hosts the shell (`FestivalShellContent`) around a split whose window layout and size
/// follow ``FoldPose``, as folding moves the app between the Duo's displays: display size
/// and size class change in one update. The tab set stays compact in both poses (#337).
private struct FoldingSplitHost: View {
    let session: FestivalSession
    let pose: FoldPose
    @State var path: [AppRoute]
    let recorder: PathRecorder

    var body: some View {
        let size = pose.folded ? CGSize(width: 466, height: 678) : CGSize(width: 951, height: 669)
        FestivalShellContent(usesSidebarShell: false) { presentation, _ in
            OnDemandSplitStack(
                section: .rivals, session: session, visibleInstruments: Set(Instrument.allCases),
                path: $path, isVisible: true
            ) { rootIsTop in
                List {
                    Text("Fixture List Root")
                    Text(rootIsTop ? "Root On Top" : "Root Covered")
                    SelectModeProbe()
                }
            }
            .overlay(alignment: .bottom) {
                // The tab set the shell has applied, standing in for the tab bar.
                Text(presentation.usesRegularSectionSet ? "Tabs Regular" : "Tabs Compact")
                    .padding(4)
            }
        }
        .environment(\.deviceLayout, pose.folded ? duoOuter : duoInner)
        .frame(width: size.width, height: size.height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: path, initial: true) { _, new in recorder.path = new }
    }
}

/// Resume after every main-queue block already enqueued has run: the split and the shell
/// defer a window change with `DispatchQueue.main.async`, so this is the turn they apply.
@MainActor
private func mainQueueTurn() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}

/// Folding with an item open in the split never paints a blank frame: in the fold's own
/// update the split keeps its shape, and one main-queue turn later the open item is
/// pushed in one column. Unfolding mirrors it, and repeated fold/unfold keeps working and
/// keeps the path (#346). The phone tab set never changes across the fold (#337).
///
/// Each phase is captured synchronously, with no sleep, and must paint content. Applying
/// the split's new shape in the window's own update fails the pending-phase text checks.
@MainActor
@Test func foldingAnOpenSplitPushesTheItemAndUnfoldingSplitsAgain() async throws {
    let size = CGSize(width: 951, height: 678)
    let pose = FoldPose()
    let recorder = PathRecorder()
    let host = nativeHostedView(
        FoldingSplitHost(session: offlineSession(), pose: pose, path: [fixtureRival], recorder: recorder)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let split = ["Fixture List Root", "Root On Top", "No Player Selected", "Rows Select"]
    try await nativeHostedSettle(host, untilText: split + ["Tabs Compact"], timeout: splitBudget)

    /// Lay out and draw now (no run-loop turn), capturing only the display the pose
    /// shows, and require painted content and `texts` there.
    func renders(
        _ phase: String, _ texts: [String], without absent: [String] = [],
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let display = pose.folded ? CGSize(width: 466, height: 678) : CGSize(width: 951, height: 669)
        let image = try nativeHostedImage(host, in: CGRect(origin: .zero, size: display))
        if ProcessInfo.processInfo.environment["FST_SHELL_RENDER_OUT"] != nil {
            _ = try nativeHostedPNG(image, filename: "split-fold-\(phase).png", environment: "FST_SHELL_RENDER_OUT")
        }
        assertRendersContent(
            host, image: image, containing: texts, notContaining: absent, sourceLocation: sourceLocation
        )
    }

    for round in 1...2 {
        pose.folded = true
        // The fold's own update: the split keeps its shape (the list fills the outer
        // display); the tabs are the compact set throughout (#337).
        try renders("\(round)-fold-pending", split + ["Tabs Compact"], without: ["Tabs Regular"])
        await mainQueueTurn()
        // Applied: the open item pushed in one column, with the same compact tab set.
        try renders(
            "\(round)-folded", ["No Player Selected", "Tabs Compact"],
            without: ["Fixture List Root", "Rows Select", "Tabs Regular"]
        )
        #expect(recorder.path == [fixtureRival], "Folding keeps the open item")

        pose.folded = false
        // The unfold's own update: still one column with the item pushed.
        try renders("\(round)-unfold-pending", ["No Player Selected", "Tabs Compact"], without: ["Rows Select"])
        await mainQueueTurn()
        try renders("\(round)-unfolded", split + ["Tabs Compact"], without: ["Tabs Regular"])
        #expect(recorder.path == [fixtureRival], "Unfolding keeps the open item")
    }
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

// MARK: - One background per split

/// Owns whether the trailing probe page is shown, so it appears after the leading one.
private struct TwoPaneBackgroundHost: View {
    let session: FestivalSession
    @State private var showsTrailing = false

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                Text("Leading Probe")
                BackdropProbe()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .festivalBackground(.carousel, session: session)
            .splitPaneContext(SplitPaneContext(role: .leading))
            if showsTrailing {
                VStack {
                    Text("Trailing Probe")
                    BackdropProbe()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .festivalBackground(.song("trailing-art.png"), session: session)
                .splitPaneContext(SplitPaneContext(role: .trailing))
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            showsTrailing = true
        }
    }
}

/// One background per split (operator 2026-10-05): pages in both panes draw no backdrop
/// of their own (the split container draws one), and a trailing page that appears after
/// its parent, asking for a different artwork, never takes the shared background over.
@MainActor
@Test func splitPanesShareTheParentsBackground() async throws {
    let size = CGSize(width: 800, height: 400)
    let session = offlineSession()
    let host = nativeHostedView(
        TwoPaneBackgroundHost(session: session)
            .frame(width: size.width, height: size.height)
            .preferredColorScheme(.dark),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(
        host, untilText: ["Leading Probe", "Trailing Probe", "Backdrop Shared"],
        excluding: ["Backdrop Own"], timeout: splitBudget
    )
    let coordinator = session.backgroundCoordinator
    #expect(coordinator.topToken != nil, "The parent page registers")
    #expect(coordinator.resolvedMode == .carousel, "The trailing page's artwork never wins")
}

/// Shows whether the page draws its own backdrop or the split container draws one.
private struct BackdropProbe: View {
    @Environment(\.splitSharesBackdrop) private var shared
    var body: some View { Text(shared ? "Backdrop Shared" : "Backdrop Own") }
}

/// Shows whether list rows would open the trailing pane or push.
private struct SelectModeProbe: View {
    @Environment(\.listDetailSelect) private var select
    var body: some View { Text(select == nil ? "Rows Push" : "Rows Select") }
}

/// Shows the width class the page sees (its pane's, while a split is open).
private struct ColumnWidthProbe: View {
    @Environment(\.deviceLayout) private var layout
    var body: some View { Text(layout.widthClass == .regular ? "Width Regular" : "Width Compact") }
}
#endif
