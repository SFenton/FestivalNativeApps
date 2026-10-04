import Foundation
import SwiftUI
import Testing
@testable import FestivalUI
#if os(macOS)
import AppKit
#endif

/// Issue #286: a `List` centres custom scroll anchors, so jumps scroll `.top` and the
/// nudger moves the List's platform scroll view onto the landing line.
@MainActor
struct ListScrollNudgerTests {
    @Test func offsetMovesTheContentAndClampsToItsEnds() {
        // Moving content down 30 pt lowers the offset by 30.
        #expect(ListScrollNudger.offset(from: 2_000, moving: 30, lowest: -176, highest: 9_000) == 1_970)
        #expect(ListScrollNudger.offset(from: 2_000, moving: -244, lowest: -176, highest: 9_000) == 2_244)
        // Already at the top of the content: stays there.
        #expect(ListScrollNudger.offset(from: -176, moving: 30, lowest: -176, highest: 9_000) == -176)
        // Near the end: stops at the bottom.
        #expect(ListScrollNudger.offset(from: 8_990, moving: -100, lowest: -176, highest: 9_000) == 9_000)
        // Content shorter than the viewport stays at the top.
        #expect(ListScrollNudger.offset(from: -176, moving: -50, lowest: -176, highest: -300) == -176)
    }

    @Test func nothingMovesBeforeAScrollViewIsLocated() {
        let nudger = ListScrollNudger()
        #expect(!nudger.moveContent(by: 30))
        #expect(!nudger.moveContent(by: .nan))
    }

    @Test func scrimStopsByTheLandingLineUnderShortBars() {
        // iPhone portrait (status bar + collapsed bar): the full 150 pt.
        #expect(TopEdgeScrim.height(topInset: 116) == 148)
        #expect(TopEdgeScrim.height(topInset: 176) == 150)
        // iPad / landscape / iPhone Duo bars end higher, so the gradient does too.
        #expect(TopEdgeScrim.height(topInset: 74) == 106)
        // Unmeasured or missing insets keep the original height.
        #expect(TopEdgeScrim.height(topInset: nil) == 150)
        #expect(TopEdgeScrim.height(topInset: 0) == 150)
        #expect(TopEdgeScrim.height(topInset: .nan) == 150)
    }

    #if os(macOS)
    /// A real SwiftUI `List` in a window: the locator finds its `NSScrollView` and the
    /// nudger moves the content by the requested distance, clamped at the top.
    @Test func locatorFindsAListsScrollViewAndTheNudgerMovesIt() async throws {
        let nudger = ListScrollNudger()
        let size = CGSize(width: 400, height: 500)
        let list = List {
            Text("Row 0").background(ListScrollViewLocator(nudger: nudger))
            ForEach(1..<200, id: \.self) { Text("Row \($0)") }
        }
        let host = NSHostingView(rootView: list)
        host.frame = CGRect(origin: .zero, size: size)
        let window = nativeHostedWindow(host, size: size)
        for _ in 0..<50 where nudger.scrollView == nil {
            host.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        let scrollView = try #require(nudger.scrollView)
        let clip = scrollView.contentView
        #expect(clip.isFlipped)
        let start = clip.bounds.origin.y

        // Up 300 (later rows come into view), then down 120.
        #expect(nudger.moveContent(by: -300))
        #expect(abs(clip.bounds.origin.y - (start + 300)) < 0.5)
        #expect(nudger.moveContent(by: 120))
        #expect(abs(clip.bounds.origin.y - (start + 180)) < 0.5)
        // Sub-point moves are rounding; past the top clamps, then nothing moves.
        #expect(!nudger.moveContent(by: 0.2))
        #expect(nudger.moveContent(by: 10_000))
        #expect(!nudger.moveContent(by: 10))
        withExtendedLifetime(window) {}
    }
    #endif
}
