import UIKit
import XCTest

// MARK: - What's New at AX5 (issue #80, backfilled by #434)

/// The What's New cover at the largest accessibility text size (AX5) on iPhone and iPad, in
/// portrait and landscape, with the grouped tester notes #80 added.
///
/// The app loads `tools/windows/fixtures/whats-new-grouped.json` through the Debug hook
/// `FST_DEBUG_WHATS_NEW_FILE` (the same document Windows' journeys load) on a development
/// install, so the cover lists "Changes Since Release 2610.08.01" with six category headings,
/// then two older versions. Each launch is measured twice, at the default size and at AX5:
/// every heading and bullet must be read in page order (headings with the header trait), grow
/// by more than 1.35× (recognized line height), come wholly into view between the navigation
/// bar and the Dismiss bar and read back untruncated from the capture; Close and Dismiss stay
/// hittable and Dismiss closes the cover. A scoped audit covers Dynamic Type, clipped text,
/// hit regions and descriptions on the cover's own elements. macOS hosting cannot scale text,
/// so this journey is the AX5 evidence; `FestivalUITests/WhatsNewAccessibilityTests` covers
/// names, order and target size in `apple-ci`.
///
/// Needs `tools/mock_service.py` (the page behind the cover; `apple-ci` serves it with
/// `--large-catalogue` on the default port 8765, and `FST_WHATS_NEW_FIXTURE_URL` points a local
/// run at another port). `apple-ci` runs the portrait journey on its iPhone simulator and both
/// journeys on its iPad simulator (`testing/apple/xcuitest.md#ci-journeys`); locally it also runs
/// in the iPad product through `project.yml`. Waits use `FestivalApp.budget(_:)` for the runner.
///
/// HIG Typography: "Keep text truncation to a minimum as font size increases. … Avoid
/// truncating text in scrollable regions"; HIG Accessibility: "offer text enlargement of at
/// least 200%" and a 44×44 pt default control size.
final class WhatsNewAccessibilityJourneyTests: XCTestCase {
    private static let fixtureService = ProcessInfo.processInfo.environment["FST_WHATS_NEW_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    /// The grouped changelog fixture, read by the app from the host file system.
    private static var notesFile: String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tools/windows/fixtures/whats-new-grouped.json").path
    }

    /// One line VoiceOver reads: its text and whether it is a heading.
    private struct Note: Equatable {
        let text: String
        let heading: Bool
    }

    /// The tester list a development install reads, then the older versions, in order.
    private static let readingOrder: [Note] = [
        Note(text: "Changes Since Release 2610.08.01", heading: true),
        Note(text: "Songs", heading: true),
        Note(text: "Fixture tester note one is new in this build.", heading: false),
        Note(text: "Fixture tester note two shares the Songs heading.", heading: false),
        Note(text: "Song Details", heading: true),
        Note(text: "Fixture tester note three follows Songs.", heading: false),
        Note(text: "Rivals", heading: true),
        Note(text: "Fixture tester note four follows Song Details.", heading: false),
        Note(text: "Navigation", heading: true),
        Note(text: "Fixture tester note five follows Rivals.", heading: false),
        Note(text: "General", heading: true),
        Note(text: "Fixture tester note six is the last category.", heading: false),
        Note(text: "Other", heading: true),
        Note(text: "Fixture tester note seven has no category and comes last.", heading: false),
        Note(text: "Version 2610.08.01", heading: true),
        Note(text: "Leaderboards", heading: true),
        Note(text: "Fixture released note.", heading: false),
        Note(text: "Other", heading: true),
        Note(text: "Fixture released note without a category.", heading: false),
        Note(text: "Version 2610.07.01", heading: true),
        Note(text: "Fixture note from a document without groups.", heading: false),
    ]

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    // MARK: - Journeys

    /// Portrait: notes grow, stay whole and in order at AX5; Close and Dismiss stay reachable.
    @MainActor
    func testWhatsNewIsReadableAtAX5Portrait() throws {
        try assertReadableAtAX5(.portrait, name: "portrait")
    }

    /// Landscape (iPad): the same, with the shorter list region between the bars. iPhone is
    /// portrait-only (`UISupportedInterfaceOrientations`), so it has no landscape form.
    @MainActor
    func testWhatsNewIsReadableAtAX5Landscape() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .phone, "iPhone runs portrait only")
        try assertReadableAtAX5(.landscapeLeft, name: "landscape")
    }

    // MARK: - Assertions

    /// Measure the cover at the default size, then assert the AX5 rules against it.
    ///
    /// - Parameters:
    ///   - orientation: Device orientation for both launches.
    ///   - name: Attachment name suffix.
    /// - Throws: A failed requirement.
    @MainActor
    private func assertReadableAtAX5(_ orientation: UIDeviceOrientation, name: String) throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation

        let standard = launch(contentSize: UIContentSizeCategory.large.rawValue)
        assertReadingOrder(standard, size: "default")
        let standardRegion = listRegion(standard)
        var baseline: [CGFloat] = []
        for index in Self.readingOrder.indices {
            let note = Self.readingOrder[index]
            let (element, frame) = reveal(index, in: standard, region: standardRegion)
            let reading = RecognizedText.recognize(element, label: note.text, frame: frame)
            XCTAssertTrue(RecognizedText.showsWhole(note.text, in: reading.text),
                          "'\(note.text)' reads back whole at the default size: '\(reading.text ?? "nil")'")
            let height = try XCTUnwrap(reading.lineHeight, "'\(note.text)' recognized at the default size")
            XCTAssertGreaterThan(height, 4, "'\(note.text)' has a measurable line height")
            baseline.append(height)
        }
        record(standard, name: "whats-new-default-\(name)")
        standard.terminate()

        let app = launch(contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue)
        record(app, name: "whats-new-ax5-\(name)")
        assertReadingOrder(app, size: "AX5")
        let window = app.windows.firstMatch.frame
        let region = listRegion(app)
        var growth: [String] = []
        for (index, note) in Self.readingOrder.enumerated() {
            let (element, frame) = reveal(index, in: app, region: region)
            XCTAssertGreaterThanOrEqual(frame.minY, region.minY - 0.5, "'\(note.text)' under the navigation bar: \(frame) vs \(region)")
            XCTAssertLessThanOrEqual(frame.maxY, region.maxY + 0.5, "'\(note.text)' under the Dismiss bar: \(frame) vs \(region)")
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "'\(note.text)' cut off at the leading edge: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "'\(note.text)' cut off at the trailing edge: \(frame)")
            let reading = RecognizedText.recognize(element, label: note.text, frame: frame)
            XCTAssertTrue(RecognizedText.showsWhole(note.text, in: reading.text),
                          "'\(note.text)' reads back whole at AX5: '\(reading.text ?? "nil")'")
            let height = try XCTUnwrap(reading.lineHeight, "'\(note.text)' recognized at AX5")
            let ratio = height / baseline[index]
            growth.append(String(format: "%@ %.2f", note.text, ratio))
            XCTAssertGreaterThan(ratio, RecognizedText.minimumGrowth,
                                 "'\(note.text)' glyphs grow at AX5: \(height) vs \(baseline[index]) pt")
        }
        attach("whats-new-ax5-\(name)-growth", growth.joined(separator: "\n"))
        record(app, name: "whats-new-ax5-\(name)-end")

        let close = app.buttons["fst.whats-new.close"]
        XCTAssertTrue(close.isHittable, "Close is reachable at AX5")
        let dismiss = app.buttons["fst.whats-new.dismiss"]
        XCTAssertTrue(dismiss.isHittable, "Dismiss is reachable at AX5")
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 44, "Dismiss is at least 44 pt tall: \(dismiss.frame)")
        // The bar's frame may round a fraction of a point past the window edge.
        XCTAssertTrue(window.insetBy(dx: -1, dy: -1).contains(dismiss.frame),
                      "Dismiss is wholly on screen: \(dismiss.frame) in \(window)")
        XCTAssertEqual(dismiss.label, "Dismiss")

        var issues: [String] = []
        let names = Set(Self.readingOrder.map(\.text))
        try app.performAccessibilityAudit(
            for: [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription]
        ) { issue in
            let id = issue.element?.identifier ?? ""
            let label = issue.element?.label ?? ""
            guard id.hasPrefix("fst.whats-new.") || names.contains(label) else { return true }
            issues.append("\(id) '\(label)': \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "What's New audit issues at AX5 (\(name))")

        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: FestivalApp.budget(10)), "Dismiss closes the cover at AX5")
    }

    /// The cover's texts read in page order, each heading with the header trait.
    ///
    /// - Parameters:
    ///   - app: The launched app showing the cover.
    ///   - size: Label for failure messages.
    @MainActor
    private func assertReadingOrder(_ app: XCUIApplication, size: String) {
        guard let snapshot = try? app.snapshot(), let list = Self.list(in: snapshot) else {
            XCTFail("What's New list in the snapshot (\(size))")
            return
        }
        let wanted = Set(Self.readingOrder.map(\.text))
        let read = Self.texts(in: list).filter { wanted.contains($0.label) }
        XCTAssertEqual(read.map(\.label), Self.readingOrder.map(\.text), "reading order at \(size)")
        let headings = read.map { Self.isHeader($0) }
        if read.contains(where: { Self.traits($0) != nil }) {
            XCTAssertEqual(headings, Self.readingOrder.map(\.heading), "header traits at \(size)")
        }
        XCTAssertFalse(Self.texts(in: list).contains { $0.label == "•" }, "bullet glyphs are hidden (\(size))")
    }

    // MARK: - Launch and scrolling

    /// Launch with the grouped notes presented at `contentSize`.
    ///
    /// - Parameter contentSize: `UIContentSizeCategory` raw value.
    /// - Returns: The app with the cover's Dismiss on screen.
    @MainActor
    private func launch(contentSize: String) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixtureService,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_WHATS_NEW": "force",
            "FST_DEBUG_WHATS_NEW_FILE": Self.notesFile,
            "FST_DEBUG_DISTRIBUTION": "development",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        app.launch()
        XCTAssertTrue(app.buttons["fst.whats-new.dismiss"].waitForExistence(timeout: FestivalApp.budget(30)), "What's New presented")
        XCTAssertTrue(app.staticTexts[Self.readingOrder[0].text].waitForExistence(timeout: FestivalApp.budget(15)),
                      "grouped fixture notes loaded from \(Self.notesFile)")
        return app
    }

    /// The scrolling list's visible region: below the navigation bar, above the Dismiss bar
    /// (its button sits 12 pt below the bar's top hairline). Both bars stay put while the list
    /// scrolls (`FestivalModal`'s inline title), so a launch measures it once: every query
    /// snapshots the whole app, page behind the cover included, which a slow runner pays for.
    @MainActor
    private func listRegion(_ app: XCUIApplication) -> CGRect {
        let bar = app.navigationBars.containing(.button, identifier: "fst.whats-new.close").firstMatch.frame
        let dismiss = app.buttons["fst.whats-new.dismiss"].frame
        let window = app.windows.firstMatch.frame
        return CGRect(x: window.minX, y: bar.maxY, width: window.width, height: dismiss.minY - 12 - bar.maxY)
    }

    /// Scroll the note at `index` wholly into the list region with slow, held drags (no fling,
    /// never past the top, where pulling down dismisses).
    ///
    /// - Parameters:
    ///   - index: Position in ``readingOrder``.
    ///   - app: The launched app.
    ///   - region: The launch's ``listRegion(_:)``.
    /// - Returns: The note's element and its frame once revealed (or after the last drag).
    @MainActor
    private func reveal(_ index: Int, in app: XCUIApplication, region: CGRect) -> (XCUIElement, CGRect) {
        let note = Self.readingOrder[index]
        let occurrence = Self.readingOrder[..<index].filter { $0.text == note.text }.count
        let element = app.staticTexts.matching(NSPredicate(format: "label == %@", note.text)).element(boundBy: occurrence)
        // `assertReadingOrder` already found every note in the list, so resolve it once here.
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        var frame = element.frame
        for _ in 0..<16 {
            if frame.minY >= region.minY - 0.5, frame.maxY <= region.maxY + 0.5 { break }
            let step = region.height * 0.6
            let delta = frame.maxY > region.maxY
                ? -min(frame.maxY - region.maxY + 16, step)
                : min(region.minY - frame.minY + 16, step)
            let startY = delta < 0 ? region.maxY - 16 : region.minY + 16
            let start = origin.withOffset(CGVector(dx: region.midX, dy: startY))
            let end = origin.withOffset(CGVector(dx: region.midX, dy: startY + delta))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: FestivalApp.budget(0.3))
            frame = element.frame
        }
        return (element, frame)
    }

    // MARK: - Snapshot helpers

    /// The scroll view holding the notes.
    @MainActor
    private static func list(in root: XCUIElementSnapshot) -> XCUIElementSnapshot? {
        if root.elementType == .scrollView,
           texts(in: root).contains(where: { $0.label == readingOrder[0].text }) {
            return root
        }
        for child in root.children {
            if let found = list(in: child) { return found }
        }
        return nil
    }

    /// Static texts under `root` in tree order.
    @MainActor
    private static func texts(in root: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        (root.elementType == .staticText ? [root] : []) + root.children.flatMap { texts(in: $0) }
    }

    /// The snapshot's accessibility traits, when readable.
    @MainActor
    private static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
    }

    /// True for a heading.
    @MainActor
    private static func isHeader(_ snapshot: XCUIElementSnapshot) -> Bool {
        (traits(snapshot) ?? 0) & UIAccessibilityTraits.header.rawValue != 0
    }

    // MARK: - Evidence

    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attach(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
