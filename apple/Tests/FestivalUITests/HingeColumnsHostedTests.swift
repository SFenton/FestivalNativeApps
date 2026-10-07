#if os(macOS)
import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Fixtures (issue #343, pattern `hinge-columns`)

/// The vertical fold of the iPhone Duo inner display in book pose (window coordinates).
private let bookFold = CGRect(x: 455, y: 0, width: 40, height: 669)

/// iPhone Duo inner display, landscape, partially folded (book pose).
private let bookPose = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 951, height: 669), widthClass: .regular,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
    verticalBarEdge: .trailing, hinge: .partiallyOpen, divisions: [bookFold], hinges: [bookFold]
))

/// The same window fully open: the division is inactive, so there is no fold.
private let flat = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 951, height: 669), widthClass: .regular,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
    verticalBarEdge: .trailing, hinge: .fullyOpen, hinges: [bookFold]
))

private let hostSize = CGSize(width: 951, height: 669)

/// Frame tolerance: on a 1x display (headless CI) SwiftUI snaps half-point edges to whole
/// pixels, so the equal 407.5 pt flat columns measure 407 and 408 pt.
private let pixelTolerance: CGFloat = 1.5

/// Grid content: the window less the 84 pt vertical bar, inset 16 pt like the pages.
private struct HingeFixture: View {
    let layout: DeviceLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // `FestivalSectionHeader`'s subtitle, identified on the text itself.
            Text("A quick look at SFentonX's overall Festival statistics per instrument, long enough to cross the fold.")
                .font(.subheadline)
                .accessibilityIdentifier("fixture.header")
                .staysOnHingeSide()
            HingeGrid(
                columns: [GridItem(.flexible(), spacing: 20, alignment: .top),
                          GridItem(.flexible(), spacing: 20, alignment: .top)],
                alignment: .leading, spacing: 20
            ) {
                ForEach(0..<2, id: \.self) { index in
                    Color.blue.frame(height: 40)
                        .accessibilityElement()
                        .accessibilityLabel("Cell \(index)")
                        .accessibilityIdentifier("fixture.grid.\(index)")
                }
            }
            HingeRow(spacing: 12) {
                ForEach(0..<2, id: \.self) { index in
                    Color.green.frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel("Row \(index)")
                        .accessibilityIdentifier("fixture.row.\(index)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .padding(.trailing, 84)
        .frame(width: hostSize.width, height: hostSize.height, alignment: .topLeading)
        .environment(\.deviceLayout, layout)
        .preferredColorScheme(.dark)
    }
}

/// Owns the injected layout as state so a test can unfold the same view in place.
@MainActor
private final class LayoutBox: ObservableObject {
    @Published var layout: DeviceLayout
    init(_ layout: DeviceLayout) { self.layout = layout }
}

private struct UnfoldHost: View {
    @ObservedObject var box: LayoutBox
    var body: some View { HingeFixture(layout: box.layout) }
}

/// Frames of the fixture's elements once measurement has settled.
@MainActor
private func frames(_ host: NSView, _ ids: [String]) async throws -> [String: CGRect] {
    var result: [String: CGRect] = [:]
    for _ in 0..<40 {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        result = ids.reduce(into: [:]) { $0[$1] = nativeHostedAccessibilityFrame($1, in: host) }
        if result.count == ids.count { break }
    }
    return result
}

private let ids = ["fixture.header", "fixture.grid.0", "fixture.grid.1", "fixture.row.0", "fixture.row.1"]

// MARK: - Tests

@MainActor @Test func bookPoseSplitsGridsAtTheFoldAndUnfoldingReflowsInPlace() async throws {
    let box = LayoutBox(bookPose)
    let host = nativeHostedView(UnfoldHost(box: box), size: hostSize)
    let window = nativeHostedWindow(host, size: hostSize)
    // Keep the never-shown window alive; closing it would over-release it (`isReleasedWhenClosed`).
    defer { withExtendedLifetime(window) {} }

    // Let the measured spans arrive (one extra layout pass), then read the frames.
    _ = try await frames(host, ids)
    var folded = try await frames(host, ids)
    for _ in 0..<20 where (folded["fixture.grid.0"]?.maxX ?? 0) > bookFold.minX + pixelTolerance {
        folded = try await frames(host, ids)
    }
    let header = try #require(folded["fixture.header"])
    let grid0 = try #require(folded["fixture.grid.0"])
    let grid1 = try #require(folded["fixture.grid.1"])
    let row0 = try #require(folded["fixture.row.0"])
    let row1 = try #require(folded["fixture.row.1"])
    // The centre gutter is the fold: leading cells end at its leading edge, trailing ones
    // start at its trailing edge.
    #expect(abs(grid0.maxX - bookFold.minX) < pixelTolerance)
    #expect(abs(grid1.minX - bookFold.maxX) < pixelTolerance)
    #expect(abs(row0.maxX - bookFold.minX) < pixelTolerance)
    #expect(abs(row1.minX - bookFold.maxX) < pixelTolerance)
    // The title wraps on its own side.
    #expect(header.maxX <= bookFold.midX - HingeColumns.titleClearance + pixelTolerance)

    // Unfold the same view: flat equal columns, the title spans the content again.
    box.layout = flat
    var open = try await frames(host, ids)
    for _ in 0..<20 where abs((open["fixture.grid.0"]?.width ?? 0) - (open["fixture.grid.1"]?.width ?? -1)) >= pixelTolerance {
        open = try await frames(host, ids)
    }
    let flat0 = try #require(open["fixture.grid.0"])
    let flat1 = try #require(open["fixture.grid.1"])
    let flatRow0 = try #require(open["fixture.row.0"])
    let flatRow1 = try #require(open["fixture.row.1"])
    #expect(abs(flat0.width - flat1.width) < pixelTolerance)
    #expect(abs(flatRow0.width - flatRow1.width) < pixelTolerance)
    #expect(abs(flat1.minX - flat0.maxX - 20) < pixelTolerance)
    #expect(flat0.maxX < bookFold.minX - 20)
    // The title spans the content again.
    #expect(try #require(open["fixture.header"]).maxX > bookFold.maxX)
}
#endif
