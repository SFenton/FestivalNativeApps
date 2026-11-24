import CoreGraphics
import UIKit
import XCTest

/// The Paths sheet's Instrument and View selectors (pattern modal-shell R2 variants).
///
/// - Folded iPhone Duo (owner, issue #360): the instrument selector shows only its icon and
///   the sheet title reads "Paths · <instrument>", updating on each switch; the View menu
///   shows only its Image/Text symbol too (issue #612).
/// - iPhone in portrait (owner, issue #612, like the web's mobile Paths modal): the
///   Instrument and View menus show only their icon, Difficulty fills the rest of the row,
///   and the title stays "Paths". At accessibility text sizes the stacked menus name
///   their values again.
/// - The unfolded Duo keeps icon + name selectors and the plain title.
///
/// VoiceOver reads "Instrument, <name>" and "View, <mode>" everywhere.
///
/// The folded journey simulates the Duo window with the Debug `FST_DEBUG_DUO_WINDOW_REMOTE`
/// switch (`DebugDuoWindow`), so it unfolds and folds again while the sheet stays open.
/// Run it on the real folded Duo (and on an ordinary iPhone for the standard pose) against
/// a fixture service started from this revision (each test skips without it):
///
/// ```
/// python3 tools/mock_service.py --port 18360 &
/// python3 tools/ios_sim.py uitest --device duo --pose folded --only DuoPathsSelectorJourneyTests
/// python3 tools/ios_sim.py uitest --device iphone --only DuoPathsSelectorJourneyTests
/// ```
///
/// "Icon only" is checked in pixels: XCUITest exposes each menu as one element labelled
/// "Instrument" or "View", so the selector's content width (icon, name and chevron against
/// the capsule) is measured from its screenshot.
final class DuoPathsSelectorJourneyTests: XCTestCase {
    /// Loopback fixture service.
    private static let origin = ProcessInfo.processInfo.environment["FST_PATHS_FIXTURE_URL"]
        ?? "http://127.0.0.1:18360"
    /// Widest content an icon-only selector may draw (24 pt icon, 6 pt gap, chevron).
    private static let iconOnlyMaxWidth: CGFloat = 56
    /// How much wider the named selector must draw than the icon-only one ("Lead"/"Bass").
    private static let nameMinExtraWidth: CGFloat = 20

    /// Folded: icon-only selector, "Paths · Lead" → "Paths · Bass" on a switch, the
    /// accessible "Instrument, <name>" kept. Unfolding restores the named selector and the
    /// plain title; folding again brings the variant back.
    @MainActor
    func testFoldedSelectorShowsIconOnlyAndTitleNamesInstrument() throws {
        continueAfterFailure = false
        try requireFixture()
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_DUO_WINDOW_REMOTE": "1",
            "FST_DEBUG_DUO_WINDOW": "folded",
        ])
        app.launch()
        defer { app.terminate() }
        let instrument = openPaths(in: app)

        XCTAssertTrue(title("Paths · Lead", in: app).waitForExistence(timeout: 10),
                      "Folded title does not name Lead: \(titles(in: app))")
        assertAccessible("Lead", instrument)
        let foldedLead = try contentWidth(of: instrument, name: "folded-lead")
        XCTAssertLessThanOrEqual(foldedLead, Self.iconOnlyMaxWidth,
                                 "Folded selector draws \(foldedLead) pt: more than the icon")
        let view = menu("fst.paths.display", in: app)
        assertAccessible("View", "Text", view)
        let foldedView = try contentWidth(of: view, name: "folded-view-text")
        XCTAssertLessThanOrEqual(foldedView, Self.iconOnlyMaxWidth,
                                 "Folded View menu draws \(foldedView) pt: more than the icon")

        choose("Bass", in: instrument, app: app)
        XCTAssertTrue(title("Paths · Bass", in: app).waitForExistence(timeout: 10),
                      "Folded title did not follow the switch to Bass: \(titles(in: app))")
        XCTAssertFalse(title("Paths · Lead", in: app).exists)
        assertAccessible("Bass", instrument)
        let foldedBass = try contentWidth(of: instrument, name: "folded-bass")
        XCTAssertLessThanOrEqual(foldedBass, Self.iconOnlyMaxWidth,
                                 "Folded selector draws \(foldedBass) pt: more than the icon")

        for window in ["unfolded-landscape", "unfolded-portrait"] {
            DuoWindowSwitch.post(window)
            XCTAssertTrue(title("Paths", in: app).waitForExistence(timeout: 10),
                          "\(window) kept a named title: \(titles(in: app))")
            XCTAssertFalse(title("Paths · Bass", in: app).exists)
            assertAccessible("Bass", instrument)
            let named = try contentWidth(of: instrument, name: "\(window)-bass")
            XCTAssertGreaterThanOrEqual(named, foldedBass + Self.nameMinExtraWidth,
                                        "\(window) selector (\(named) pt) shows no name beside the icon (\(foldedBass) pt)")
            let namedView = try contentWidth(of: view, name: "\(window)-view-text")
            XCTAssertGreaterThanOrEqual(namedView, foldedView + Self.nameMinExtraWidth,
                                        "\(window) View menu (\(namedView) pt) shows no name beside the icon (\(foldedView) pt)")
        }

        DuoWindowSwitch.post("folded")
        XCTAssertTrue(title("Paths · Bass", in: app).waitForExistence(timeout: 10),
                      "Folding again lost the named title: \(titles(in: app))")
        let refolded = try contentWidth(of: instrument, name: "refolded-bass")
        XCTAssertLessThanOrEqual(refolded, Self.iconOnlyMaxWidth)
    }

    /// Opened on the unfolded inner display (owner, issue #368), Paths covers the window
    /// and its View menu offers Image, Text and Side by Side; Side by Side shows the
    /// image and the table at once. Bending into book pose (hinge-columns R10) removes
    /// the View menu and keeps the open viewer with the image and the table on either
    /// side of the hinge. Closing onto the outer display keeps the viewer (latched), and
    /// its View menu returns with Image and Text, showing the Settings default view.
    @MainActor
    func testUnfoldedOffersSideBySideBookPoseSplitsAtHingeAndFoldingFallsBack() throws {
        continueAfterFailure = false
        try requireFixture()
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
            "FST_DEBUG_DUO_WINDOW_REMOTE": "1",
            "FST_DEBUG_DUO_WINDOW": "unfolded-landscape",
        ])
        app.launch()
        defer { app.terminate() }
        // Where the simulated book-pose fold lies, read while the shell's Debug readout is
        // visible (the full-window viewer covers it).
        let hinge = try foldX(in: app)
        _ = openPaths(in: app)
        let view = menu("fst.paths.display", in: app)
        XCTAssertEqual(view.value as? String, "Text")
        view.tap()
        for option in ["Image", "Text", "Side by Side"] {
            let item = app.buttons.matching(
                NSPredicate(format: "label == %@ AND identifier != %@", option, view.identifier)
            ).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "View option \(option) missing")
        }
        app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "Side by Side", view.identifier)
        ).firstMatch.tap()

        let image = app.descendants(matching: .any).matching(identifier: "fst.paths.image").firstMatch
        let text = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fst.paths.text.")
        ).firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10), "Side by Side shows no image")
        XCTAssertTrue(text.waitForExistence(timeout: 10), "Side by Side shows no table")
        XCTAssertLessThan(image.frame.midX, text.frame.midX, "Image is not before the table")
        XCTAssertEqual(view.value as? String, "Side by Side")

        // Book pose: Side by Side is the only mode, so the View menu goes, and the panes
        // sit on either side of the fold (`DebugDuoWindow.book` runs it down the middle of
        // the real window's free span; the readout reports its x).
        DuoWindowSwitch.post("book")
        XCTAssertTrue(view.waitForNonExistence(timeout: 10), "Book pose kept the View menu")
        let close = app.buttons["fst.paths.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "Book pose dismissed the viewer")
        XCTAssertTrue(menu("fst.paths.instrument", in: app).exists, "Book pose lost the instrument menu")
        let viewport = menu("fst.paths.image-viewport", in: app)
        XCTAssertTrue(viewport.waitForExistence(timeout: 10), "Book pose shows no image")
        XCTAssertTrue(text.waitForExistence(timeout: 10), "Book pose shows no table")
        let settled = NSPredicate { _, _ in
            viewport.frame.maxX <= hinge && text.frame.minX >= hinge
        }
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 10)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "paths-book-pose"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertLessThanOrEqual(viewport.frame.maxX, hinge,
                                 "Image (\(viewport.frame)) crosses the hinge at x=\(hinge)")
        XCTAssertGreaterThanOrEqual(text.frame.minX, hinge,
                                    "Table (\(text.frame)) crosses the hinge at x=\(hinge)")

        // Closed onto the outer display: the viewer stays open; Side by Side doesn't fit,
        // so the View menu returns showing the Settings default (Image).
        DuoWindowSwitch.post("folded")
        XCTAssertTrue(view.waitForExistence(timeout: 10), "Folding closed the viewer")
        XCTAssertTrue(close.exists, "Folding dismissed the viewer")
        let folded = NSPredicate(format: "value == %@", "Image")
        expectation(for: folded, evaluatedWith: view)
        waitForExpectations(timeout: 10)
    }

    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    /// On a dedicated Duo, verify the same Paths session follows the real hinge from
    /// flat to book to cover and back, restoring the selected Side by Side mode.
    @MainActor
    func testPathsFollowsPhysicalHingeWithoutReopening() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["FST_PATHS_HINGE_TEST"] == "1"
                && (environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Opt in on a dedicated iPhone Duo simulator"
        )
        guard #available(iOS 27.3, *) else { throw XCTSkip("Needs the iOS 27.3 hinge runtime") }
        try requireFixture()
        let device = XCUIDevice.shared
        let hinge = try XCTUnwrap(device.hinge, "The Duo simulator has no XCUIHinge")
        let initialAngle = hinge.angle
        let initialOrientation = device.orientation
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        app.launchArguments += ["-fst.settings.pathDefaultView", "image"]
        defer {
            app.terminate()
            hinge.angle = initialAngle
            device.orientation = initialOrientation
        }

        hinge.angle = .pi
        // Portrait is the Duo's hardware orientation for a wide inner window.
        device.orientation = .portrait
        app.launch()
        let window = app.windows.firstMatch
        let inner = CGSize(width: 951, height: 669)
        let cover = CGSize(width: 466, height: 678)
        waitForDisplay(inner, hinge: hinge, angle: .pi, window: window)
        _ = openPaths(in: app)
        let view = menu("fst.paths.display", in: app)
        let close = app.buttons["fst.paths.close"]
        let image = menu("fst.paths.image", in: app)
        let viewport = menu("fst.paths.image-viewport", in: app)
        let text = menu("fst.paths.text.Solo_Guitar.expert", in: app)
        choose("Side by Side", in: view, app: app)
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertEqual(view.value as? String, "Side by Side")
        XCTAssertLessThan(image.frame.midX, text.frame.midX)
        assertEqualFlatSelectorWidths(in: app)
        try recordPhysicalPaths("flat", in: app, angle: hinge.angle)

        hinge.angle = .pi / 2
        waitForDisplay(inner, hinge: hinge, angle: .pi / 2, window: window)
        XCTAssertTrue(view.waitForNonExistence(timeout: 10), "Book pose kept the View menu")
        try recordPhysicalPaths("book", in: app, angle: hinge.angle)
        XCTAssertTrue(close.isHittable, "Book pose lost Close")
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(viewport.frame.maxX, window.frame.midX + 1)
        XCTAssertGreaterThanOrEqual(text.frame.minX, window.frame.midX - 1)

        hinge.angle = 0
        waitForDisplay(cover, hinge: hinge, angle: 0, window: window)
        let imageMode = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Image"), object: view)
        XCTAssertEqual(XCTWaiter().wait(for: [imageMode], timeout: 10), .completed)
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertTrue(close.isHittable, "Folding dismissed the viewer")
        XCTAssertFalse(text.exists)
        try recordPhysicalPaths("cover", in: app, angle: hinge.angle)

        hinge.angle = .pi
        waitForDisplay(inner, hinge: hinge, angle: .pi, window: window)
        let sideBySide = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Side by Side"), object: view)
        XCTAssertEqual(XCTWaiter().wait(for: [sideBySide], timeout: 10), .completed)
        XCTAssertTrue(image.waitForExistence(timeout: 10))
        XCTAssertTrue(text.waitForExistence(timeout: 10))
        XCTAssertTrue(close.isHittable, "Unfolding dismissed the viewer")
        assertEqualFlatSelectorWidths(in: app)
        try recordPhysicalPaths("flat-return", in: app, angle: hinge.angle)
    }

    /// Each named selector gets an equal, reachable third of the flat inner row.
    @MainActor
    private func assertEqualFlatSelectorWidths(in app: XCUIApplication) {
        let instrument = menu("fst.paths.instrument", in: app)
        let difficulty = menu("fst.paths.difficulty", in: app)
        let display = menu("fst.paths.display", in: app)
        for control in [instrument, difficulty, display] {
            XCTAssertTrue(control.isHittable, "\(control.identifier) is reachable on the inner display")
            XCTAssertGreaterThanOrEqual(control.frame.height, 43.67)
            XCTAssertEqual(control.frame.width, instrument.frame.width, accuracy: 1)
        }
    }

    /// Wait for the requested hinge angle and the measured live window, not a debug pose.
    @available(iOS 27.3, *)
    @MainActor
    private func waitForDisplay(_ size: CGSize, hinge: XCUIHinge, angle: CGFloat, window: XCUIElement) {
        let settled = NSPredicate { _, _ in
            let actual = window.frame.size
            return abs(hinge.angle - angle) < 0.05
                && abs(actual.width - size.width) < 1 && abs(actual.height - size.height) < 1
        }
        let result = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: settled, object: nil)], timeout: 15)
        XCTAssertEqual(result, .completed, "Expected \(angle) rad and \(size); got \(hinge.angle) rad and \(window.frame)")
    }

    /// Save the lit screen and fresh accessibility tree with the physical pose.
    @MainActor
    private func recordPhysicalPaths(_ phase: String, in app: XCUIApplication, angle: CGFloat) throws {
        let frame = app.windows.firstMatch.frame
        let capture = XCUIScreen.main.screenshot()
        let bitmap = try XCTUnwrap(capture.image.cgImage)
        let pixels = [bitmap.width, bitmap.height].sorted()
        let expected = [frame.width, frame.height].sorted().map { Int(($0 * 3).rounded()) }
        for (actual, target) in zip(pixels, expected) {
            XCTAssertEqual(Double(actual), Double(target), accuracy: 2, "Wrong lit screen in \(phase)")
        }
        let screen = XCTAttachment(screenshot: capture)
        screen.name = "paths-\(phase)-framebuffer"
        screen.lifetime = .keepAlways
        add(screen)
        let tree = XCTAttachment(string: "angle=\(angle); window=\(frame); pixels=\(pixels)\n\(app.debugDescription)")
        tree.name = "paths-\(phase)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }
    #endif

    /// An ordinary iPhone in portrait (owner, issue #612; web mobile Paths modal): the
    /// Instrument and View menus show only their icon, at least 44 pt square, Difficulty
    /// fills the rest of the row between them, the title stays "Paths", and VoiceOver
    /// still reads "Instrument, <name>" and "View, <mode>". The View menu lists Image and
    /// Text. Skipped on the iPhone Duo, whose real pose the folded journey covers.
    @MainActor
    func testStandardPhoneShowsIconOnlySelectorsAndPlainTitle() throws {
        continueAfterFailure = false
        try requireStandardPhone()
        try requireFixture()
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        app.launch()
        defer { app.terminate() }
        let instrument = openPaths(in: app)
        let difficulty = menu("fst.paths.difficulty", in: app)
        let view = menu("fst.paths.display", in: app)

        XCTAssertTrue(title("Paths", in: app).waitForExistence(timeout: 10), "Titles: \(titles(in: app))")
        XCTAssertFalse(title("Paths · Lead", in: app).exists)
        assertAccessible("Lead", instrument)
        assertAccessible("View", "Text", view)
        XCTAssertEqual(difficulty.label, "Difficulty")
        for selector in [instrument, view] {
            XCTAssertGreaterThanOrEqual(selector.frame.width, 44, "\(selector.label) narrower than 44 pt")
        }
        // Reading order and the row: Instrument, Difficulty (filling), View.
        XCTAssertLessThan(instrument.frame.maxX, difficulty.frame.minX)
        XCTAssertLessThan(difficulty.frame.maxX, view.frame.minX)
        XCTAssertGreaterThan(difficulty.frame.width, instrument.frame.width + view.frame.width,
                             "Difficulty (\(difficulty.frame.width) pt) does not take the spare width")
        let lead = try contentWidth(of: instrument, name: "standard-lead")
        XCTAssertLessThanOrEqual(lead, Self.iconOnlyMaxWidth, "Instrument draws \(lead) pt: more than the icon")
        let text = try contentWidth(of: view, name: "standard-view-text")
        XCTAssertLessThanOrEqual(text, Self.iconOnlyMaxWidth, "View draws \(text) pt: more than the icon")

        view.tap()
        for option in ["Image", "Text"] {
            let item = app.buttons.matching(
                NSPredicate(format: "label == %@ AND identifier != %@", option, view.identifier)
            ).firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "View option \(option) missing")
        }
        XCTAssertFalse(app.buttons.matching(
            NSPredicate(format: "label == %@", "Side by Side")
        ).firstMatch.exists, "The iPhone sheet offers Side by Side")
        app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", "Image", view.identifier)
        ).firstMatch.tap()
        assertAccessible("View", "Image", view)
        let image = try contentWidth(of: view, name: "standard-view-image")
        XCTAssertLessThanOrEqual(image, Self.iconOnlyMaxWidth, "View draws \(image) pt: more than the icon")

        choose("Bass", in: instrument, app: app)
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(title("Paths", in: app).exists, "Titles: \(titles(in: app))")
        assertAccessible("Bass", instrument)
        let bass = try contentWidth(of: instrument, name: "standard-bass")
        XCTAssertLessThanOrEqual(bass, Self.iconOnlyMaxWidth)
    }

    /// At an accessibility text size the iPhone's selectors stack, each the full width,
    /// and the Instrument and View menus name their values again (issue #612). Their text
    /// scales, is not clipped and keeps 44 pt targets (XCUITest Dynamic Type, text clipped
    /// and hit region audits on the selector row).
    @MainActor
    func testStandardPhoneStackedSelectorsNameValuesAtLargeText() throws {
        continueAfterFailure = false
        try requireStandardPhone()
        try requireFixture()
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityLarge.rawValue,
        ]
        app.launch()
        defer { app.terminate() }
        let instrument = openPaths(in: app)
        let difficulty = menu("fst.paths.difficulty", in: app)
        let view = menu("fst.paths.display", in: app)

        assertAccessible("Lead", instrument)
        assertAccessible("View", "Text", view)
        // Stacked in reading order.
        XCTAssertLessThan(instrument.frame.midY, difficulty.frame.midY)
        XCTAssertLessThan(difficulty.frame.midY, view.frame.midY)
        let lead = try contentWidth(of: instrument, name: "large-text-lead")
        XCTAssertGreaterThan(lead, Self.iconOnlyMaxWidth, "Stacked Instrument (\(lead) pt) shows no name")
        let text = try contentWidth(of: view, name: "large-text-view")
        XCTAssertGreaterThan(text, Self.iconOnlyMaxWidth, "Stacked View (\(text) pt) shows no name")

        let selectors = ["fst.paths.instrument", "fst.paths.difficulty", "fst.paths.display"]
        try app.performAccessibilityAudit(for: [.dynamicType, .textClipped, .hitRegion]) { issue in
            guard let element = issue.element, selectors.contains(element.identifier) else { return true }
            XCTFail("Paths selector audit: \(issue.compactDescription); element=\(element.identifier)")
            return true
        }
    }

    // MARK: - Helpers

    /// Skip unless an ordinary iPhone runs the test (the Duo's own pose is folded).
    private func requireStandardPhone() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone only")
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipIf(device.contains("Duo"), "The Duo's own pose is covered by the folded journey")
    }

    /// Skip unless the fixture service answers.
    @MainActor
    private func requireFixture() throws {
        let url = try XCTUnwrap(URL(string: "\(Self.origin)/api/features"))
        try XCTSkipUnless(url.scheme == "http" && url.host == "127.0.0.1" && url.port != nil,
                          "Paths journeys require a loopback fixture")
        let probe = expectation(description: "fixture probe")
        nonisolated(unsafe) var reachable = false
        URLSession.shared.dataTask(with: url) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 5)
        try XCTSkipUnless(reachable, "Start a mock_service.py fixture from this revision at \(Self.origin)")
    }

    /// Open the fixture song's Paths sheet (dismissing the Karaoke notice) in Text view.
    ///
    /// - Parameter app: The launched fixture app on Songs.
    /// - Returns: The instrument menu (`fst.paths.instrument`).
    @MainActor
    private func openPaths(in app: XCUIApplication) -> XCUIElement {
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: 15))
        song.tap()
        let open = app.buttons["fst.song-detail.paths"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        PathsUITestSupport.dismissKaraokeNotice(in: app)
        // Text view: a steady backdrop for the pixel measurement.
        choose("Text", in: menu("fst.paths.display", in: app), app: app)
        let instrument = menu("fst.paths.instrument", in: app)
        XCTAssertTrue(instrument.waitForExistence(timeout: 10))
        return instrument
    }

    /// The simulated book-pose fold's centre x (window points): bends the running app into
    /// the `book` window, reads `fold=<x>` from the Debug readout
    /// (`fst.shell.debug.duo-window`) and flattens it back to `unfolded-landscape`.
    @MainActor
    private func foldX(in app: XCUIApplication) throws -> CGFloat {
        let readout = app.descendants(matching: .any)["fst.shell.debug.duo-window"]
        XCTAssertTrue(readout.waitForExistence(timeout: 15), "No Debug Duo window readout")
        DuoWindowSwitch.post("book")
        let reported = NSPredicate(format: "label CONTAINS %@", " fold=")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: reported, object: readout)], timeout: 10)
        let label = readout.label
        DuoWindowSwitch.post("unfolded-landscape")
        let flat = NSPredicate(format: "NOT (label CONTAINS %@)", " fold=")
        _ = XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: flat, object: readout)], timeout: 10)
        let value = try XCTUnwrap(label.components(separatedBy: " fold=").dropFirst().first
            .flatMap { Double($0.prefix { $0.isNumber }) }, "No fold in the readout: \(label)")
        return CGFloat(value)
    }

    /// VoiceOver reads the selector as "Instrument, <name>" in every pose.
    @MainActor
    private func assertAccessible(_ name: String, _ instrument: XCUIElement,
                                  file: StaticString = #filePath, line: UInt = #line) {
        assertAccessible("Instrument", name, instrument, file: file, line: line)
    }

    /// VoiceOver reads a selector as "<title>, <value>", on a target at least 44 pt tall.
    @MainActor
    private func assertAccessible(_ title: String, _ value: String, _ selector: XCUIElement,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(selector.label, title, file: file, line: line)
        XCTAssertEqual(selector.value as? String, value, file: file, line: line)
        XCTAssertGreaterThanOrEqual(selector.frame.height, 44, file: file, line: line)
    }

    /// A navigation title text with exactly this label.
    @MainActor
    private func title(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.navigationBars.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }

    /// Every navigation-bar text, for failure messages.
    @MainActor
    private func titles(in app: XCUIApplication) -> [String] {
        app.navigationBars.staticTexts.allElementsBoundByIndex.map(\.label)
    }

    /// The Paths sheet's bottom-row menu with this identifier.
    @MainActor
    private func menu(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Open a menu and pick an option.
    @MainActor
    private func choose(_ option: String, in menu: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(menu.waitForExistence(timeout: 10))
        menu.tap()
        let item = app.buttons.matching(
            NSPredicate(format: "label == %@ AND identifier != %@", option, menu.identifier)
        ).firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Menu option \(option) missing")
        item.tap()
    }

    /// Width in points of what the selector draws on its capsule (icon, name, chevron),
    /// measured from its screenshot, which is attached to the report.
    ///
    /// - Parameters:
    ///   - selector: The instrument or View menu.
    ///   - name: Attachment name.
    /// - Returns: Content width in points.
    @MainActor
    private func contentWidth(of selector: XCUIElement, name: String) throws -> CGFloat {
        // Let the label's layout change settle before the capture.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let shot = selector.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "paths-selector-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(shot.image.cgImage)
        let bitmap = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: selector.frame.width))
        return Self.contentWidth(in: bitmap)
    }

    /// Horizontal extent (points) of the columns that differ from the capsule fill in the
    /// bitmap's middle band, inside a 10 pt inset that skips the capsule's rim.
    ///
    /// - Parameter bitmap: The selector's screenshot.
    /// - Returns: Content width in points, 0 when nothing is drawn.
    static func contentWidth(in bitmap: ButtonFillPixels) -> CGFloat {
        let inset = Int((10 * bitmap.scale).rounded())
        let top = bitmap.height / 4, bottom = bitmap.height * 3 / 4
        guard bitmap.width > inset * 2 + 2, bottom > top else { return 0 }
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let index = (y * bitmap.width + x) * 4
            return (Int(bitmap.pixels[index]), Int(bitmap.pixels[index + 1]), Int(bitmap.pixels[index + 2]))
        }
        // The fill: the median of the inset's two edge columns, which no content reaches.
        var edge: [(Int, Int, Int)] = []
        for y in top..<bottom { edge.append(pixel(inset, y)); edge.append(pixel(bitmap.width - 1 - inset, y)) }
        func median(_ values: [Int]) -> Int { values.sorted()[values.count / 2] }
        let fill = (median(edge.map(\.0)), median(edge.map(\.1)), median(edge.map(\.2)))
        var first: Int?, last: Int?
        for x in inset..<(bitmap.width - inset) {
            var inked = 0
            for y in top..<bottom {
                let (red, green, blue) = pixel(x, y)
                if max(abs(red - fill.0), abs(green - fill.1), abs(blue - fill.2)) > 48 { inked += 1 }
            }
            if inked >= 2 {
                if first == nil { first = x }
                last = x
            }
        }
        guard let first, let last else { return 0 }
        return CGFloat(last - first + 1) / bitmap.scale
    }
}
