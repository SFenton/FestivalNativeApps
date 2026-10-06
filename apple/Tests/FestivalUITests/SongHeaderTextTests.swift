#if os(macOS)
import AppKit
import SwiftUI
import Testing
@testable import FestivalUI

/// The in-page song header's title fills the width beside the art on one line
/// (scrolling when it overflows) instead of wrapping beside empty space (issue #315),
/// and still wraps at accessibility text sizes.
@MainActor
struct SongHeaderTextTests {
    /// Width measured by the probe after layout.
    private final class Probe { var width: CGFloat = 0 }

    private let long = "Through the Fire and Flames and Several More Words"
    private let rowWidth: CGFloat = 320
    private let artWidth: CGFloat = 80
    private let spacing: CGFloat = 12

    /// Lay out a header row (art placeholder + text column) like Song Leaderboard's.
    ///
    /// - Parameters:
    ///   - title: Song title.
    ///   - size: Dynamic Type size.
    ///   - probe: Receives the text column's laid-out width.
    /// - Returns: The row's fitting height.
    private func layout(_ title: String, _ size: DynamicTypeSize = .large, probe: Probe = Probe()) -> CGFloat {
        let host = NSHostingView(rootView: HStack(spacing: spacing) {
            Color.clear.frame(width: artWidth, height: 1)
            SongHeaderText(title: title, artist: "DragonForce", titleFont: .title3.bold(), spacing: 4) {
                EmptyView()
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { probe.width = $0 }
        }
        .environment(\.dynamicTypeSize, size)
        .environment(\.marqueeAnimationEnabled, false)
        .frame(width: rowWidth))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        return host.fittingSize.height
    }

    @Test func longTitleStaysOnOneLine() {
        #expect(layout(long) == layout("One"), "a long title must not wrap at standard sizes")
    }

    @Test func columnFillsTheWidthBesideTheArt() {
        let probe = Probe()
        _ = layout("One", probe: probe)
        #expect(probe.width == rowWidth - artWidth - spacing)
    }

    @Test func wrapsAtAccessibilitySizes() {
        #expect(layout(long, .accessibility5) > layout("One", .accessibility5))
    }
}
#endif
