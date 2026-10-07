import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

/// Issues #333, #334: the Songs Filter field sits at the bottom on iPhone Duo, full width
/// except on the trailing page across a book-pose fold, and keeps the system field
/// everywhere else.
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

    @Test func bookPoseWithoutAReportedFoldUsesTheMidline() {
        // `DeviceLayout.splitHinge` with no reported region: a zero-width midline.
        let midline = CGRect(x: 475.5, y: 0, width: 0, height: 669)
        let padding = SongsFilterFieldPlacement.horizontalPadding(container: innerRow, hinge: midline)
        #expect(padding.leading == 475.5 + 16)
    }

    // MARK: Fold per pose (#334)

    /// Inner landscape: the hinge runs down the middle of the 951 × 669 pt window.
    static let verticalHinge = CGRect(x: 463.5, y: 0, width: 24, height: 669)
    /// Inner portrait: the hinge runs across the middle of the 669 × 951 pt window.
    static let horizontalHinge = CGRect(x: 0, y: 463.5, width: 669, height: 24)

    /// A Duo window layout, as `DeviceLayoutPublisher` resolves it.
    ///
    /// - Parameters:
    ///   - hinge: Hinge status (`.closed` is the outer display).
    ///   - size: Window size in points.
    ///   - fold: The active division, while partially open.
    ///   - hinges: Every division, active or not (the hinge while flat).
    /// - Returns: The resolved layout.
    static func duo(
        _ hinge: HingeState?, size: CGSize, fold: CGRect? = nil, hinges: [CGRect] = []
    ) -> DeviceLayout {
        DeviceLayout.resolve(LayoutSignals(
            size: size, widthClass: hinge == .closed ? .compact : .regular,
            heightClass: hinge == .closed && size.width > size.height ? .compact : .regular,
            verticalBarEdge: .trailing, hinge: hinge,
            divisions: fold.map { [$0] } ?? [], hinges: hinges
        ), dualSource: false)
    }

    @Test func onlyABookPoseFoldMovesTheField() {
        let landscape = CGSize(width: 951, height: 669)
        let portrait = CGSize(width: 669, height: 951)
        // The bug: lying flat, the inactive hinge put the field on the right half.
        let flat = Self.duo(.fullyOpen, size: landscape, hinges: [Self.verticalHinge])
        #expect(flat.splitHinge == Self.verticalHinge)
        #expect(SongsFilterFieldPlacement.fold(in: flat) == nil)
        // Flat with no reported region (midline fallback) also keeps the full width.
        #expect(SongsFilterFieldPlacement.fold(in: Self.duo(.fullyOpen, size: landscape)) == nil)
        #expect(SongsFilterFieldPlacement.fold(
            in: Self.duo(.fullyOpen, size: portrait, hinges: [Self.horizontalHinge])
        ) == nil)
        // Folded, either orientation, even if a stale division were reported.
        #expect(SongsFilterFieldPlacement.fold(
            in: Self.duo(.closed, size: CGSize(width: 382, height: 678))
        ) == nil)
        #expect(SongsFilterFieldPlacement.fold(
            in: Self.duo(.closed, size: CGSize(width: 678, height: 466), hinges: [Self.verticalHinge])
        ) == nil)
        // iPhone, iPad, Mac.
        #expect(SongsFilterFieldPlacement.fold(in: .standardPhone) == nil)
        // Book pose: the active fold, or the midline when no division is reported.
        let book = Self.duo(.partiallyOpen, size: landscape, fold: Self.verticalHinge)
        #expect(SongsFilterFieldPlacement.fold(in: book) == Self.verticalHinge)
        let unreported = Self.duo(.partiallyOpen, size: landscape)
        #expect(SongsFilterFieldPlacement.fold(in: unreported) == CGRect(x: 475.5, y: 0, width: 0, height: 669))
    }

    /// One pose after another, as the device folds, unfolds and rotates: the field
    /// spans its row except on the right page of a book-pose landscape.
    @Test func everyPoseInSequenceSpansTheAvailableWidth() {
        let landscape = CGSize(width: 951, height: 669)
        let portrait = CGSize(width: 669, height: 951)
        let outer = CGSize(width: 382, height: 678)
        let outerLandscape = CGSize(width: 678, height: 466)
        let steps: [(name: String, layout: DeviceLayout, rightPage: Bool)] = [
            ("folded", Self.duo(.closed, size: outer), false),
            ("unfolded flat landscape", Self.duo(.fullyOpen, size: landscape, hinges: [Self.verticalHinge]), false),
            ("book landscape", Self.duo(.partiallyOpen, size: landscape, fold: Self.verticalHinge), true),
            ("flat again", Self.duo(.fullyOpen, size: landscape, hinges: [Self.verticalHinge]), false),
            ("rotated flat portrait", Self.duo(.fullyOpen, size: portrait, hinges: [Self.horizontalHinge]), false),
            ("book portrait", Self.duo(.partiallyOpen, size: portrait, fold: Self.horizontalHinge), false),
            ("rotated book landscape", Self.duo(.partiallyOpen, size: landscape, fold: Self.verticalHinge), true),
            ("folded landscape", Self.duo(.closed, size: outerLandscape), false),
            ("folded portrait", Self.duo(.closed, size: outer), false),
        ]
        for step in steps {
            let size = step.layout.size
            let row = CGRect(x: 0, y: size.height - 60, width: size.width, height: 60)
            let padding = SongsFilterFieldPlacement.horizontalPadding(
                container: row, hinge: SongsFilterFieldPlacement.fold(in: step.layout)
            )
            let expectedLeading = step.rightPage ? Self.verticalHinge.maxX + 16 : 16
            #expect(padding.leading == expectedLeading, "\(step.name)")
            #expect(padding.trailing == 16, "\(step.name)")
        }
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

/// Drives one hosted field through a fold/unfold/rotate sequence (issue #334).
@MainActor @Observable
private final class SongsFilterPoseDriver {
    var layout: DeviceLayout

    init(_ layout: DeviceLayout) { self.layout = layout }
}

/// The page-sized row the hosted sequence lays out at the window's top-left.
private struct SongsFilterPoseHost: View {
    let driver: SongsFilterPoseDriver

    var body: some View {
        let size = driver.layout.size
        Color.clear
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SongsBottomFilterField(
                    text: .constant(""), hinge: SongsFilterFieldPlacement.fold(in: driver.layout),
                    space: "page"
                ) { _ in }
            }
            .coordinateSpace(.named("page"))
            .frame(width: size.width, height: size.height)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The same field instance, re-laid out pose after pose: it never keeps a previous
/// pose's width, and spans its row except on the right page of a book-pose fold.
@MainActor
@Test func songsBottomFilterFieldSpansTheWidthThroughFoldUnfoldAndRotate() async throws {
    typealias Poses = SongsFilterFieldPlacementTests
    let landscape = CGSize(width: 951, height: 669)
    let portrait = CGSize(width: 669, height: 951)
    let steps: [(name: String, layout: DeviceLayout, rightPage: Bool)] = [
        ("folded", Poses.duo(.closed, size: CGSize(width: 382, height: 678)), false),
        ("unfolded flat landscape", Poses.duo(.fullyOpen, size: landscape, hinges: [Poses.verticalHinge]), false),
        ("book landscape", Poses.duo(.partiallyOpen, size: landscape, fold: Poses.verticalHinge), true),
        ("flat again", Poses.duo(.fullyOpen, size: landscape, hinges: [Poses.verticalHinge]), false),
        ("rotated flat portrait", Poses.duo(.fullyOpen, size: portrait, hinges: [Poses.horizontalHinge]), false),
        ("book portrait", Poses.duo(.partiallyOpen, size: portrait, fold: Poses.horizontalHinge), false),
        ("rotated book landscape", Poses.duo(.partiallyOpen, size: landscape, fold: Poses.verticalHinge), true),
        ("folded landscape", Poses.duo(.closed, size: CGSize(width: 678, height: 466)), false),
    ]
    let window = CGSize(width: 951, height: 951)
    let driver = SongsFilterPoseDriver(steps[0].layout)
    let host = nativeHostedView(SongsFilterPoseHost(driver: driver), size: window)
    let hostWindow = nativeHostedWindow(host, size: window)
    defer { hostWindow.orderOut(nil) }
    // The identifier is on the text, inside the capsule: 12 pt padding, then the
    // magnifier and an 8 pt gap before it (no clear button while empty).
    let textInset = (leading: 35.5, trailing: 12.0)
    for step in steps {
        driver.layout = step.layout
        let width = step.layout.size.width
        let minX = (step.rightPage ? Poses.verticalHinge.maxX + 16 : 16) + textInset.leading
        let maxX = width - 16 - textInset.trailing
        func placed() -> Bool {
            guard let field = nativeHostedAccessibilityFrame("fst.songs.filter-field", in: host) else {
                return false
            }
            return abs(field.minX - minX) < 1.5 && abs(field.maxX - maxX) < 1.5
        }
        let image = try await nativeHostedSettle(host) { placed() }
        if step.name == "unfolded flat landscape" {
            _ = try nativeHostedPNG(image, filename: "songs-duo-filter-flat.png", environment: "FST_SHELL_RENDER_OUT")
        }
        let field = try #require(nativeHostedAccessibilityFrame("fst.songs.filter-field", in: host))
        #expect(abs(field.minX - minX) < 1.5, "\(step.name): field starts at \(field.minX), expected \(minX)")
        #expect(abs(field.maxX - maxX) < 1.5, "\(step.name): field ends at \(field.maxX), expected \(maxX)")
    }
}
#endif
