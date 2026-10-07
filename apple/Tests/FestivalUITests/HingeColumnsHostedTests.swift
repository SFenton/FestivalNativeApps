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

// MARK: - Song Detail instrument cards (accessibility sizes)

/// Song Detail's card grid at a Dynamic Type size, with tall unequal cards like its
/// instrument cards, laid out in the same content area as ``HingeFixture``.
private struct SongDetailCardFixture: View {
    @ObservedObject var box: LayoutBox
    let typeSize: DynamicTypeSize

    var body: some View {
        SongDetailCardGrid(instruments: [.lead, .bass, .drums]) { index, _ in
            Color.orange.frame(height: CGFloat(120 + 40 * index))
                .accessibilityElement()
                .accessibilityLabel("Card \(index)")
                .accessibilityIdentifier("fixture.card.\(index)")
        }
        .padding(16)
        .padding(.trailing, 84)
        .frame(width: hostSize.width, height: hostSize.height, alignment: .topLeading)
        .environment(\.deviceLayout, box.layout)
        .dynamicTypeSize(typeSize)
        .preferredColorScheme(.dark)
    }
}

private let cardIds = ["fixture.card.0", "fixture.card.1", "fixture.card.2"]

/// Song Detail's cards at `typeSize`: in book pose the two-card row meets at the fold and
/// the third card starts a new row under the first; unfolding the same view restores equal
/// columns.
@MainActor
private func assertSongDetailCardsSplitAtTheFold(_ typeSize: DynamicTypeSize) async throws {
    let box = LayoutBox(bookPose)
    let host = nativeHostedView(SongDetailCardFixture(box: box, typeSize: typeSize), size: hostSize)
    let window = nativeHostedWindow(host, size: hostSize)
    defer { withExtendedLifetime(window) {} }

    _ = try await frames(host, cardIds)
    var folded = try await frames(host, cardIds)
    for _ in 0..<20 where (folded["fixture.card.0"]?.maxX ?? 0) > bookFold.minX + pixelTolerance {
        folded = try await frames(host, cardIds)
    }
    let card0 = try #require(folded["fixture.card.0"])
    let card1 = try #require(folded["fixture.card.1"])
    let card2 = try #require(folded["fixture.card.2"])
    // The gutter is the fold even though the 356 pt trailing side is under the 360 pt minimum.
    #expect(abs(card0.maxX - bookFold.minX) < pixelTolerance)
    #expect(abs(card1.minX - bookFold.maxX) < pixelTolerance)
    // One row: the eager grid top-aligns it, the lazy grid centres it.
    #expect(card1.minY < card0.maxY && card0.minY < card1.maxY)
    #expect(abs(card2.minX - card0.minX) < pixelTolerance)
    #expect(card2.minY >= card1.maxY - pixelTolerance)

    box.layout = flat
    var open = try await frames(host, cardIds)
    for _ in 0..<20 where abs((open["fixture.card.0"]?.width ?? 0) - (open["fixture.card.1"]?.width ?? -1)) >= pixelTolerance {
        open = try await frames(host, cardIds)
    }
    let flat0 = try #require(open["fixture.card.0"])
    let flat1 = try #require(open["fixture.card.1"])
    #expect(abs(flat0.width - flat1.width) < pixelTolerance)
    #expect(abs(flat1.minX - flat0.maxX - SongDetailCardColumns.spacing) < pixelTolerance)
    #expect(flat0.maxX < bookFold.minX - SongDetailCardColumns.spacing)
}

@MainActor @Test func songDetailCardsSplitAtTheFoldAtAccessibilitySizes() async throws {
    try await assertSongDetailCardsSplitAtTheFold(.accessibility3)
}

@MainActor @Test func songDetailCardsSplitAtTheFoldAtStandardSizes() async throws {
    try await assertSongDetailCardsSplitAtTheFold(.large)
}
// MARK: - Page hinge (issue #350, pattern `wide-columns` R3)

/// Flat inner display with no reported hinge: the page hinge is the window's middle.
private let flatUnreported = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 951, height: 669), widthClass: .regular,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
    verticalBarEdge: .trailing, hinge: .fullyOpen
))

/// Wide-landscape page rows (Search results, Songs grid) beside a fold-only row.
private struct PageHingeFixture: View {
    @ObservedObject var box: LayoutBox

    var body: some View {
        VStack(spacing: 12) {
            HingeRow(spacing: WideColumns.spacing, hinge: .page) {
                ForEach(0..<2, id: \.self) { index in
                    Color.green.frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel("Page \(index)")
                        .accessibilityIdentifier("fixture.page.\(index)")
                }
            }
            HingeRow(spacing: WideColumns.spacing) {
                ForEach(0..<2, id: \.self) { index in
                    Color.blue.frame(height: 40)
                        .frame(maxWidth: .infinity)
                        .accessibilityElement()
                        .accessibilityLabel("Fold \(index)")
                        .accessibilityIdentifier("fixture.fold.\(index)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .padding(.trailing, 84)
        .frame(width: hostSize.width, height: hostSize.height, alignment: .topLeading)
        .environment(\.deviceLayout, box.layout)
        .preferredColorScheme(.dark)
    }
}

private let pageIds = ["fixture.page.0", "fixture.page.1", "fixture.fold.0", "fixture.fold.1"]

/// Page rows meet at the hinge flat and folded (the reported hinge, else the window's
/// middle); fold-only rows keep equal cells while flat. Changing pose reflows in place.
@MainActor @Test func pageHingeRowsMeetAtTheHingeFlatAndFolded() async throws {
    let box = LayoutBox(flat)
    let host = nativeHostedView(PageHingeFixture(box: box), size: hostSize)
    let window = nativeHostedWindow(host, size: hostSize)
    defer { withExtendedLifetime(window) {} }

    /// Frames once the page row's leading cell ends at `edge`.
    func settled(at edge: CGFloat) async throws -> [String: CGRect] {
        var result = try await frames(host, pageIds)
        for _ in 0..<20 where abs((result["fixture.page.0"]?.maxX ?? 0) - edge) >= pixelTolerance {
            result = try await frames(host, pageIds)
        }
        return result
    }

    // Flat with a reported hinge: the page row's gutter is the hinge; the fold row is equal.
    var open = try await settled(at: bookFold.minX)
    #expect(abs(try #require(open["fixture.page.0"]).maxX - bookFold.minX) < pixelTolerance)
    #expect(abs(try #require(open["fixture.page.1"]).minX - bookFold.maxX) < pixelTolerance)
    let fold0 = try #require(open["fixture.fold.0"])
    let fold1 = try #require(open["fixture.fold.1"])
    #expect(abs(fold0.width - fold1.width) < pixelTolerance)

    // Book pose: both rows straddle the fold.
    box.layout = bookPose
    let folded = try await settled(at: bookFold.minX)
    #expect(abs(try #require(folded["fixture.page.1"]).minX - bookFold.maxX) < pixelTolerance)

    // Flat, no reported hinge: the gutter is centred on the window's middle.
    box.layout = flatUnreported
    let middle = hostSize.width / 2
    open = try await settled(at: middle - WideColumns.spacing / 2)
    let page0 = try #require(open["fixture.page.0"])
    let page1 = try #require(open["fixture.page.1"])
    #expect(abs((page0.maxX + page1.minX) / 2 - middle) < pixelTolerance)
}
#endif
