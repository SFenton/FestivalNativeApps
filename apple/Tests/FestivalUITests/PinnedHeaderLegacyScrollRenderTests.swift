#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Harness

/// A sheet-style List with pinned "New"/"Older" headers using the canonical pinned-header
/// fade, the same modifiers as the Notifications sheet.
private struct PinnedHeaderHarness: View {
    let state: PinnedHeaderEdgeFadeState

    var body: some View {
        List {
            Section {
                ForEach(0..<8, id: \.self) { index in
                    row(index).pinnedHeaderEdgeFadeRow(state, first: index == 0)
                }
            } header: {
                Text("New").pinnedHeaderEdgeFadeHeader(state, first: true)
            }
            Section {
                ForEach(8..<40, id: \.self) { index in
                    row(index).pinnedHeaderEdgeFadeRow(state)
                }
            } header: {
                Text("Older").pinnedHeaderEdgeFadeHeader(state, first: false)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .pinnedHeaderEdgeFadeList(state, showsHeaders: true)
        // Hosts such as GitHub's macOS runner report Reduce Transparency on (issue #122),
        // which correctly turns the ramp into a hard edge; pin it off to see the ramp.
        .environment(\._accessibilityReduceTransparency, false)
        .environment(\._colorSchemeContrast, .standard)
    }

    private func row(_ index: Int) -> some View {
        Text("Row \(index)").frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
}

/// The List's own scroll view: the deepest scroll view whose document is a table.
@MainActor
private func harnessScrollView(in view: NSView) -> NSScrollView? {
    for subview in view.subviews {
        if let found = harnessScrollView(in: subview) { return found }
    }
    if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
    return nil
}

/// Scroll the hosted List `offset` points from its resting top and let it settle.
@MainActor
private func scroll<Content: View>(
    _ scrollView: NSScrollView, to offset: CGFloat, host: NSHostingView<Content>
) async throws {
    let clip = scrollView.contentView
    clip.scroll(to: NSPoint(x: 0, y: offset - scrollView.contentInsets.top))
    scrollView.reflectScrolledClipView(clip)
    try await nativeHostedSettle(host)
}

// MARK: - iOS 17 / macOS 14 path (issue #308)

/// Design review of #308: before iOS 18 / macOS 15 the sheet-list fade never read a
/// scroll offset, so its depth stayed 0 and rows were hard-cut even with normal
/// transparency settings. Forced onto that path (``ListScrollOffsetObserver``), the
/// fade must be absent at rest, grow 1:1 with scrolling and stop at the shared 40 pt
/// ramp, exactly like the `onScrollGeometryChange` path.
@MainActor
@Test(arguments: [true, false])
func pinnedHeaderFadeGrowsTheSharedRampOnEveryScrollPath(legacy: Bool) async throws {
    let state = PinnedHeaderEdgeFadeState(legacyScrollTracking: legacy)
    #expect(state.legacyScrollTracking == legacy)
    let size = CGSize(width: 420, height: 640)
    let host = nativeHostedView(
        PinnedHeaderHarness(state: state).frame(width: size.width, height: size.height),
        size: size
    )
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    try await nativeHostedSettle(host) { state.headerHeight > 0 }
    let scrollView = try #require(harnessScrollView(in: host))

    // At rest nothing is dimmed (R4).
    #expect(state.depth == 0)
    #expect(state.pinLine == scrollView.contentInsets.top)

    try await scroll(scrollView, to: 15, host: host)
    #expect(abs(state.depth - 15) <= 0.5)

    try await scroll(scrollView, to: 400, host: host)
    #expect(state.depth == PinnedHeaderEdgeFade.height)
    #expect(state.depth == 40)

    try await scroll(scrollView, to: 0, host: host)
    #expect(state.depth == 0)
}

/// The legacy and `onScrollGeometryChange` paths read the same pin line, header band and
/// edge, so rows clear the pinned header at the same place on every system.
@MainActor
@Test func pinnedHeaderLegacyPathMatchesTheScrollGeometryPath() async throws {
    let size = CGSize(width: 420, height: 640)
    var readings: [(pinLine: CGFloat, edge: CGFloat, layout: PinnedHeaderEdgeFade.HeaderLayout)] = []
    for legacy in [false, true] {
        let state = PinnedHeaderEdgeFadeState(legacyScrollTracking: legacy)
        let host = nativeHostedView(
            PinnedHeaderHarness(state: state).frame(width: size.width, height: size.height),
            size: size
        )
        let window = nativeHostedWindow(host, size: size)
        try await nativeHostedSettle(host) { state.headerHeight > 0 }
        readings.append((state.pinLine, state.edge, state.headerLayout))
        window.orderOut(nil)
    }
    #expect(readings[0].pinLine == readings[1].pinLine)
    #expect(readings[0].edge == readings[1].edge)
    #expect(readings[0].layout == readings[1].layout)
}
#endif
