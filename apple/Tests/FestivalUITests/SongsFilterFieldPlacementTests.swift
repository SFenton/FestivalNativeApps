import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

/// Issue #333: the Songs Filter field sits at the bottom on iPhone Duo, on the trailing
/// page across a vertical hinge, and keeps the system field everywhere else.
struct SongsFilterFieldPlacementTests {
    /// iPhone Duo inner display, landscape: the field row spans the safe area left of
    /// the trailing vertical bar.
    private let innerRow = CGRect(x: 0, y: 600, width: 867, height: 60)

    @Test func onlyIPhoneDuoMovesTheFieldToTheBottom() {
        #expect(SongsFilterFieldPlacement.resolve(pose: .standard) == .system)
        #expect(SongsFilterFieldPlacement.resolve(pose: .folded) == .bottom)
        #expect(SongsFilterFieldPlacement.resolve(pose: .unfolded) == .bottom)
        #expect(SongsFilterFieldPlacement.resolve(pose: .partiallyFolded) == .bottom)
    }

    @Test func noHingeKeepsStandardMargins() {
        // Folded (outer display), iPhone-sized rows.
        let padding = SongsFilterFieldPlacement.horizontalPadding(
            container: CGRect(x: 0, y: 600, width: 382, height: 60), hinge: nil
        )
        #expect(padding.leading == 16)
        #expect(padding.trailing == 16)
    }

    @Test func bookPoseFoldPutsTheFieldOnTheRightPage() {
        // A 24 pt active fold through the middle of the 951 pt window.
        let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)
        let padding = SongsFilterFieldPlacement.horizontalPadding(container: innerRow, hinge: fold)
        #expect(padding.leading == 487.5 + 16)
        #expect(padding.trailing == 16)
    }

    @Test func flatLandscapeMidlineHingeAlsoUsesTheRightPage() {
        // `DeviceLayout.splitHinge` with no reported region: a zero-width midline.
        let midline = CGRect(x: 475.5, y: 0, width: 0, height: 669)
        let padding = SongsFilterFieldPlacement.horizontalPadding(container: innerRow, hinge: midline)
        #expect(padding.leading == 475.5 + 16)
    }

    @Test func rightToLeftUsesTheTrailingLeftPage() {
        let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)
        let padding = SongsFilterFieldPlacement.horizontalPadding(
            container: innerRow, hinge: fold, layoutDirection: .rightToLeft
        )
        // Leading is the right side: it reaches past the fold's left edge.
        #expect(padding.leading == 867 - 463.5 + 16)
        #expect(padding.trailing == 16)
    }

    @Test func horizontalFoldKeepsTheFullWidth() {
        // Inner portrait (laptop pose): the fold runs across the window, not beside the field.
        let fold = CGRect(x: 0, y: 463.5, width: 669, height: 24)
        let padding = SongsFilterFieldPlacement.horizontalPadding(
            container: CGRect(x: 0, y: 860, width: 669, height: 60), hinge: fold
        )
        #expect(padding.leading == 16)
    }

    @Test func hingeOutsideTheRowOrTooNarrowAPageKeepsTheFullWidth() {
        let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)
        // A row entirely on one side of the hinge.
        let left = SongsFilterFieldPlacement.horizontalPadding(
            container: CGRect(x: 0, y: 600, width: 450, height: 60), hinge: fold
        )
        #expect(left.leading == 16)
        // The trailing page would leave the field under 200 pt.
        let narrow = SongsFilterFieldPlacement.horizontalPadding(
            container: CGRect(x: 0, y: 600, width: 700, height: 60), hinge: fold
        )
        #expect(narrow.leading == 16)
        // Not measured yet.
        let zero = SongsFilterFieldPlacement.horizontalPadding(container: .zero, hinge: fold)
        #expect(zero.leading == 16)
    }

    @Test func keyboardLiftClosesOnlyTheGapTheSystemLeaves() {
        // Duo outer display: the system lifted the row to 505 but the keyboard starts at
        // 433, so the field (ending 8 pt above the row, at 497) needs 72 pt more to clear it by 8.
        #expect(SongsFilterFieldPlacement.keyboardLift(rowBottom: 505, keyboardTop: 433) == 72)
        // Already clear, hidden, or a hardware keyboard's off-screen frame: no lift.
        #expect(SongsFilterFieldPlacement.keyboardLift(rowBottom: 425, keyboardTop: 433) == 0)
        #expect(SongsFilterFieldPlacement.keyboardLift(rowBottom: 644, keyboardTop: nil) == 0)
        #expect(SongsFilterFieldPlacement.keyboardLift(rowBottom: 644, keyboardTop: 685) == 0)
        // Fractional overlap rounds up, so the field never touches the keyboard.
        #expect(SongsFilterFieldPlacement.keyboardLift(rowBottom: 433.4, keyboardTop: 433) == 1)
    }
}

#if os(macOS)
// MARK: - Hosted

/// The field's real frame on the right page of a book-pose inner display.
@MainActor
@Test func songsBottomFilterFieldLiesOnTheRightPageClearOfTheFold() async throws {
    let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)
    let size = CGSize(width: 867, height: 669)
    let view = VStack(spacing: 0) {
        List(0..<40, id: \.self) { Text("Row \($0)") }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        SongsBottomFilterField(text: .constant(""), hinge: fold, space: "page") { _ in }
    }
    .coordinateSpace(.named("page"))
    .frame(width: size.width, height: size.height)
    .preferredColorScheme(.dark)
    let host = nativeHostedView(view, size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host) {
        (nativeHostedAccessibilityFrame("fst.songs.filter-field", in: host)?.minX ?? 0) > fold.maxX
    }
    _ = try nativeHostedPNG(image, filename: "songs-duo-filter-book.png", environment: "FST_SHELL_RENDER_OUT")
    let field = try #require(nativeHostedAccessibilityFrame("fst.songs.filter-field", in: host))
    #expect(field.minX >= fold.maxX + 16, "Field starts a margin past the fold")
    #expect(field.maxX <= size.width - 16, "Field stays inside the page margin")
    #expect(field.minY > size.height / 2, "Field sits at the bottom")
}
#endif
