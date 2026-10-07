import CoreGraphics
import FestivalCore
import SwiftUI
import Testing
@testable import FestivalUI

/// Issues #333 and #349: the iPhone Duo bottom search fields (Songs' Filter field, the
/// Search tab's field and scope bar) span the full width when flat, move to the
/// trailing page across a book-pose fold, and keep the system field everywhere else.
struct BottomSearchFieldPlacementTests {
    /// iPhone Duo inner display, landscape: the field row spans the safe area left of
    /// the trailing vertical bar.
    private let innerRow = CGRect(x: 0, y: 600, width: 867, height: 60)

    @Test func onlyIPhoneDuoMovesTheFieldToTheBottom() {
        #expect(SongsFilterFieldPlacement.resolve(pose: .standard) == .system)
        #expect(SongsFilterFieldPlacement.resolve(pose: .folded) == .bottom)
        #expect(SongsFilterFieldPlacement.resolve(pose: .unfolded) == .bottom)
        #expect(SongsFilterFieldPlacement.resolve(pose: .partiallyFolded) == .bottom)
    }

    @Test func searchUsesTheBottomFieldOnlyOnTheDuoInnerDisplay() {
        #expect(GlobalSearchFieldPlacement.resolve(pose: .unfolded, asTab: true) == .bottom)
        #expect(GlobalSearchFieldPlacement.resolve(pose: .partiallyFolded, asTab: true) == .bottom)
        // The folded outer display's system field already spans its bottom.
        #expect(GlobalSearchFieldPlacement.resolve(pose: .folded, asTab: true) == .system)
        #expect(GlobalSearchFieldPlacement.resolve(pose: .standard, asTab: true) == .system)
        // The iPad sidebar's Search page keeps the system field.
        #expect(GlobalSearchFieldPlacement.resolve(pose: .unfolded, asTab: false) == .system)
    }

    @Test func onlyABookFoldMovesTheColumnToTheTrailingPage() {
        let fold = CGRect(x: 455, y: 0, width: 41, height: 669)
        let book = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 951, height: 669), widthClass: .regular, verticalBarEdge: .trailing,
            hinge: .partiallyOpen, divisions: [fold]
        ))
        #expect(BottomSearchFieldPlacement.pageHinge(for: book) == fold)
        // Owner (#349): fully unfolded, the field takes the full bottom width, even
        // though the split hinge reports the flat display's midline.
        let flat = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 951, height: 669), widthClass: .regular,
            verticalBarEdge: .trailing, hinge: .fullyOpen
        ))
        #expect(flat.splitHinge != nil)
        #expect(BottomSearchFieldPlacement.pageHinge(for: flat) == nil)
        let folded = DeviceLayout.resolve(LayoutSignals(
            size: CGSize(width: 466, height: 678), widthClass: .compact,
            verticalBarEdge: .trailing, hinge: .closed
        ))
        #expect(BottomSearchFieldPlacement.pageHinge(for: folded) == nil)
        #expect(BottomSearchFieldPlacement.pageHinge(for: .standardPhone) == nil)
    }

    @Test func flatInnerLandscapeKeepsTheFullWidth() {
        let padding = BottomSearchFieldPlacement.horizontalPadding(container: innerRow, hinge: nil)
        #expect(padding.leading == 16)
        #expect(padding.trailing == 16)
    }

    @Test func noHingeKeepsStandardMargins() {
        // Folded (outer display), iPhone-sized rows.
        let padding = BottomSearchFieldPlacement.horizontalPadding(
            container: CGRect(x: 0, y: 600, width: 382, height: 60), hinge: nil
        )
        #expect(padding.leading == 16)
        #expect(padding.trailing == 16)
    }

    @Test func bookPoseFoldPutsTheFieldOnTheRightPage() {
        // A 24 pt active fold through the middle of the 951 pt window.
        let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)
        let padding = BottomSearchFieldPlacement.horizontalPadding(container: innerRow, hinge: fold)
        #expect(padding.leading == 487.5 + 16)
        #expect(padding.trailing == 16)
    }

    @Test func bookPoseWithoutAReportedRegionUsesTheMidline() {
        // `DeviceLayout.splitHinge` while partially folded with no division: a zero-width midline.
        let midline = CGRect(x: 475.5, y: 0, width: 0, height: 669)
        let padding = BottomSearchFieldPlacement.horizontalPadding(container: innerRow, hinge: midline)
        #expect(padding.leading == 475.5 + 16)
    }

    @Test func rightToLeftUsesTheTrailingLeftPage() {
        let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)
        let padding = BottomSearchFieldPlacement.horizontalPadding(
            container: innerRow, hinge: fold, layoutDirection: .rightToLeft
        )
        // Leading is the right side: it reaches past the fold's left edge.
        #expect(padding.leading == 867 - 463.5 + 16)
        #expect(padding.trailing == 16)
    }

    @Test func horizontalFoldKeepsTheFullWidth() {
        // Inner portrait (laptop pose): the fold runs across the window, not beside the field.
        let fold = CGRect(x: 0, y: 463.5, width: 669, height: 24)
        let padding = BottomSearchFieldPlacement.horizontalPadding(
            container: CGRect(x: 0, y: 860, width: 669, height: 60), hinge: fold
        )
        #expect(padding.leading == 16)
    }

    @Test func hingeOutsideTheRowOrTooNarrowAPageKeepsTheFullWidth() {
        let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)
        // A row entirely on one side of the hinge.
        let left = BottomSearchFieldPlacement.horizontalPadding(
            container: CGRect(x: 0, y: 600, width: 450, height: 60), hinge: fold
        )
        #expect(left.leading == 16)
        // The trailing page would leave the field under 200 pt.
        let narrow = BottomSearchFieldPlacement.horizontalPadding(
            container: CGRect(x: 0, y: 600, width: 700, height: 60), hinge: fold
        )
        #expect(narrow.leading == 16)
        // Not measured yet.
        let zero = BottomSearchFieldPlacement.horizontalPadding(container: .zero, hinge: fold)
        #expect(zero.leading == 16)
    }

    @Test func keyboardLiftClosesOnlyTheGapTheSystemLeaves() {
        // Duo outer display: the system lifted the row to 505 but the keyboard starts at
        // 433, so the field (ending 8 pt above the row, at 497) needs 72 pt more to clear it by 8.
        #expect(BottomSearchFieldPlacement.keyboardLift(rowBottom: 505, keyboardTop: 433) == 72)
        // Already clear, hidden, or a hardware keyboard's off-screen frame: no lift.
        #expect(BottomSearchFieldPlacement.keyboardLift(rowBottom: 425, keyboardTop: 433) == 0)
        #expect(BottomSearchFieldPlacement.keyboardLift(rowBottom: 644, keyboardTop: nil) == 0)
        #expect(BottomSearchFieldPlacement.keyboardLift(rowBottom: 644, keyboardTop: 685) == 0)
        // Fractional overlap rounds up, so the field never touches the keyboard.
        #expect(BottomSearchFieldPlacement.keyboardLift(rowBottom: 433.4, keyboardTop: 433) == 1)
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
        BottomSearchField(
            text: .constant(""), prompt: "Filter Songs", accessibilityLabel: "Filter Songs",
            identifier: "fst.songs.filter-field", clearIdentifier: "fst.songs.filter-clear",
            hinge: fold, space: "page"
        )
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

/// Issue #349: the Search scope bar and bottom field share one column, the full width
/// when flat and the right page, clear of the fold, in book pose.
@MainActor
@Test(arguments: [false, true])
func searchScopeBarAndBottomFieldShareOneColumn(bookPose: Bool) async throws {
    let fold = CGRect(x: 463.5, y: 0, width: 24, height: 669)
    let hinge = bookPose ? fold : nil
    let size = CGSize(width: 867, height: 669)
    let view = VStack(spacing: 10) {
        Picker("Search Scope", selection: .constant(GlobalSearchScope.all)) {
            ForEach(GlobalSearchScope.allCases) { scope in Text(scope.title).tag(scope) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .bottomSearchFieldColumn(hinge: hinge)
        .accessibilityIdentifier("fst.global-search.scope")
        List(0..<40, id: \.self) { Text("Result \($0)") }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
        BottomSearchField(
            text: .constant(""), prompt: "Search songs, players, or bands",
            accessibilityLabel: "Search songs, players and bands",
            identifier: "fst.global-search.field", clearIdentifier: "fst.global-search.clear",
            hinge: hinge
        )
    }
    .frame(width: size.width, height: size.height)
    .preferredColorScheme(.dark)
    let host = nativeHostedView(view, size: size)
    let window = nativeHostedWindow(host, size: size)
    defer { window.orderOut(nil) }
    let image = try await nativeHostedSettle(host) {
        let field = nativeHostedAccessibilityFrame("fst.global-search.field", in: host)
        return (field?.width ?? 0) > 0 && (!bookPose || (field?.minX ?? 0) > fold.maxX)
    }
    _ = try nativeHostedPNG(
        image, filename: bookPose ? "search-duo-book.png" : "search-duo-flat.png",
        environment: "FST_SHELL_RENDER_OUT"
    )
    let scope = try #require(nativeHostedAccessibilityFrame("fst.global-search.scope", in: host))
    let field = try #require(nativeHostedAccessibilityFrame("fst.global-search.field", in: host))
    // One column: 16 pt margins when flat, a margin past the fold in book pose.
    let column = (minX: bookPose ? fold.maxX + 16 : 16, maxX: size.width - 16)
    // The segmented control fills the column on iOS; AppKit's keeps its intrinsic
    // width, centred in it. Either way it is centred in the field's column.
    #expect(abs(scope.midX - (column.minX + column.maxX) / 2) <= 1, "Scope bar centred in the column")
    #expect(scope.minX >= column.minX - 1 && scope.maxX <= column.maxX + 1, "Scope bar inside the column")
    // The text field sits inside the capsule's 12 pt padding, after the magnifier.
    #expect(field.minX >= column.minX && field.minX <= column.minX + 60, "Field starts at the column")
    #expect(field.maxX <= column.maxX && field.maxX >= column.maxX - 14, "Field ends at the column")
    #expect(field.minY > size.height / 2, "Field sits at the bottom")
}
#endif
