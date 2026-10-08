#if os(macOS)
import AppKit
import CoreGraphics
import SwiftUI
import Testing
@testable import FestivalUI

// MARK: - Feedback form and photo library panes (issue #373, patterns `modal-shell` R11, `hinge-columns`)

/// The vertical fold of the iPhone Duo inner display in book pose (window coordinates).
private let bookFold = CGRect(x: 455, y: 0, width: 40, height: 669)

/// A page-sized sheet on the inner display, partially folded (book pose).
private let bookPose = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 951, height: 669), widthClass: .regular,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
    verticalBarEdge: .trailing, hinge: .partiallyOpen, divisions: [bookFold], hinges: [bookFold]
))

/// The same window fully open: the hinge is inactive, so there is no fold.
private let flat = DeviceLayout.resolve(LayoutSignals(
    size: CGSize(width: 951, height: 669), widthClass: .regular,
    safeAreaInsets: EdgeInsets(top: 0, leading: 0, bottom: 20, trailing: 84),
    verticalBarEdge: .trailing, hinge: .fullyOpen, hinges: [bookFold]
))

private let hostSize = CGSize(width: 951, height: 669)
/// The sheet's leading and trailing edges in the window: off-centre, so a split at the
/// sheet's own midpoint (x 435.5) is distinguishable from one on the fold (x 455–495).
private let sheetInsets = (leading: CGFloat(40), trailing: CGFloat(80))
private let pixelTolerance: CGFloat = 1.5
private let ids = ["fixture.form", "fixture.library"]

/// Stand-ins for the form and the library, so the test measures the panes, not a picker.
private struct PanesFixture: View {
    @ObservedObject var box: PanesBox

    var body: some View {
        FeedbackFormPanes(showsLibrary: box.showsLibrary) {
            Color.blue
                .accessibilityElement()
                .accessibilityLabel("Form")
                .accessibilityIdentifier("fixture.form")
        } library: {
            Color.green
                .accessibilityElement()
                .accessibilityLabel("Library")
                .accessibilityIdentifier("fixture.library")
        }
        .padding(.leading, sheetInsets.leading)
        .padding(.trailing, sheetInsets.trailing)
        .frame(width: hostSize.width, height: hostSize.height)
        .environment(\.deviceLayout, box.layout)
        .preferredColorScheme(.dark)
    }
}

/// Owns the injected layout and the open library as state, so a test changes them in place.
@MainActor
private final class PanesBox: ObservableObject {
    @Published var layout: DeviceLayout
    @Published var showsLibrary: Bool
    init(_ layout: DeviceLayout, showsLibrary: Bool) {
        self.layout = layout
        self.showsLibrary = showsLibrary
    }
}

/// Frames once measurement has settled and `done` holds (or after ~2 s).
@MainActor
private func frames(
    _ host: NSView, until done: ([String: CGRect]) -> Bool = { _ in true }
) async throws -> [String: CGRect] {
    var result: [String: CGRect] = [:]
    for _ in 0..<40 {
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        result = ids.reduce(into: [:]) { partial, id in
            partial[id] = nativeHostedAccessibilityFrame(id, in: host)
        }
        if done(result) { break }
    }
    return result
}

// MARK: - Tests

/// Book pose: the form ends at the fold and the library starts after it, both the sheet's
/// full height. Unfolding the same panes divides the sheet at its own midpoint (R7), and
/// hiding the library gives the form the whole sheet.
@MainActor @Test func feedbackPanesMeetAtTheFoldThenSplitTheSheetFlat() async throws {
    let box = PanesBox(bookPose, showsLibrary: true)
    let host = nativeHostedView(PanesFixture(box: box), size: hostSize)
    let window = nativeHostedWindow(host, size: hostSize)
    defer { withExtendedLifetime(window) {} }

    let folded = try await frames(host) {
        abs(($0["fixture.form"]?.maxX ?? 0) - bookFold.minX) < pixelTolerance
    }
    let form = try #require(folded["fixture.form"])
    let library = try #require(folded["fixture.library"])
    #expect(abs(form.minX - sheetInsets.leading) < pixelTolerance)
    #expect(abs(form.maxX - bookFold.minX) < pixelTolerance)
    #expect(abs(library.minX - bookFold.maxX) < pixelTolerance)
    #expect(abs(library.maxX - (hostSize.width - sheetInsets.trailing)) < pixelTolerance)
    // Panes, not cards: each takes the sheet's whole height.
    #expect(abs(form.height - hostSize.height) < pixelTolerance)
    #expect(abs(library.height - hostSize.height) < pixelTolerance)

    box.layout = flat
    let open = try await frames(host) {
        abs(($0["fixture.form"]?.width ?? 0) - ($0["fixture.library"]?.width ?? -1)) < pixelTolerance
    }
    let flatForm = try #require(open["fixture.form"])
    let flatLibrary = try #require(open["fixture.library"])
    let sheetMid = (sheetInsets.leading + hostSize.width - sheetInsets.trailing) / 2
    #expect(abs(flatForm.width - flatLibrary.width) < pixelTolerance)
    #expect(abs(flatForm.maxX - sheetMid) < pixelTolerance)
    #expect(abs(flatLibrary.minX - sheetMid) < pixelTolerance)

    // Hiding animates the library out; the form then spans the sheet again.
    box.showsLibrary = false
    let sheetWidth = hostSize.width - sheetInsets.leading - sheetInsets.trailing
    let hidden = try await frames(host) {
        $0["fixture.library"] == nil && abs(($0["fixture.form"]?.width ?? 0) - sheetWidth) < pixelTolerance
    }
    #expect(hidden["fixture.library"] == nil)
    let alone = try #require(hidden["fixture.form"])
    #expect(abs(alone.width - sheetWidth) < pixelTolerance)
    #expect(abs(alone.height - hostSize.height) < pixelTolerance)
}

/// Opening the library in book pose splits at the fold straight away.
@MainActor @Test func feedbackLibraryOpenedInBookPoseStartsAfterTheFold() async throws {
    let box = PanesBox(bookPose, showsLibrary: false)
    let host = nativeHostedView(PanesFixture(box: box), size: hostSize)
    let window = nativeHostedWindow(host, size: hostSize)
    defer { withExtendedLifetime(window) {} }

    let alone = try await frames(host) { $0["fixture.form"] != nil }
    #expect(alone["fixture.library"] == nil)
    // One pane never splits at the fold: it spans the sheet.
    let form = try #require(alone["fixture.form"])
    #expect(form.maxX > bookFold.maxX)

    box.showsLibrary = true
    let opened = try await frames(host) {
        abs(($0["fixture.library"]?.minX ?? 0) - bookFold.maxX) < pixelTolerance
    }
    #expect(abs(try #require(opened["fixture.form"]).maxX - bookFold.minX) < pixelTolerance)
    #expect(abs(try #require(opened["fixture.library"]).minX - bookFold.maxX) < pixelTolerance)
}
#endif
