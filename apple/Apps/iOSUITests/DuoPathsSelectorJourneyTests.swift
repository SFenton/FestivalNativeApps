import CoreGraphics
import UIKit
import XCTest

/// The Paths sheet's instrument selector on folded iPhone Duo (owner, issue #360;
/// pattern modal-shell R2 variant): folded, the selector shows only the instrument icon
/// and the sheet title reads "Paths · <instrument>", updating on each switch, while
/// VoiceOver still reads "Instrument, <name>". Every other pose keeps the icon + name
/// selector and the plain "Paths" title.
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
/// "Icon only" is checked in pixels: XCUITest exposes the menu as one element labelled
/// "Instrument", so the selector's content width (icon, name and chevron against the
/// capsule) is measured from its screenshot.
final class DuoPathsSelectorJourneyTests: XCTestCase {
    /// Loopback fixture service.
    private static let origin = "http://127.0.0.1:18360"
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
        }

        DuoWindowSwitch.post("folded")
        XCTAssertTrue(title("Paths · Bass", in: app).waitForExistence(timeout: 10),
                      "Folding again lost the named title: \(titles(in: app))")
        let refolded = try contentWidth(of: instrument, name: "refolded-bass")
        XCTAssertLessThanOrEqual(refolded, Self.iconOnlyMaxWidth)
    }

    /// Opened on the unfolded inner display (owner, issue #368), Paths covers the window
    /// and its View menu offers Image, Text and Side by Side; Side by Side shows the
    /// image and the table at once. Folding again keeps the open viewer (latched) and
    /// falls back to the Settings default view.
    @MainActor
    func testUnfoldedOffersSideBySideAndFoldingFallsBack() throws {
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

        DuoWindowSwitch.post("folded")
        XCTAssertTrue(view.waitForExistence(timeout: 10), "Folding closed the viewer")
        let folded = NSPredicate(format: "value == %@", "Image")
        expectation(for: folded, evaluatedWith: view)
        waitForExpectations(timeout: 10)
    }

    /// The device's own pose (an ordinary iPhone, no simulated window) keeps the plain
    /// title and the icon + name selector. Skipped on the iPhone Duo, whose real pose the
    /// folded journey covers.
    @MainActor
    func testStandardPhoneKeepsNamedSelectorAndPlainTitle() throws {
        continueAfterFailure = false
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "iPhone only")
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? ""
        try XCTSkipIf(device.contains("Duo"), "The Duo's own pose is covered by the folded journey")
        try requireFixture()
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ])
        app.launch()
        defer { app.terminate() }
        let instrument = openPaths(in: app)

        XCTAssertTrue(title("Paths", in: app).waitForExistence(timeout: 10), "Titles: \(titles(in: app))")
        XCTAssertFalse(title("Paths · Lead", in: app).exists)
        assertAccessible("Lead", instrument)
        let lead = try contentWidth(of: instrument, name: "standard-lead")
        XCTAssertGreaterThan(lead, Self.iconOnlyMaxWidth, "Standard selector (\(lead) pt) shows no name")
        choose("Bass", in: instrument, app: app)
        XCTAssertTrue(app.staticTexts["Path unavailable"].waitForExistence(timeout: 10))
        XCTAssertTrue(title("Paths", in: app).exists, "Titles: \(titles(in: app))")
        assertAccessible("Bass", instrument)
    }

    // MARK: - Helpers

    /// Skip unless the fixture service answers.
    @MainActor
    private func requireFixture() throws {
        let probe = expectation(description: "fixture probe")
        nonisolated(unsafe) var reachable = false
        URLSession.shared.dataTask(with: URL(string: "\(Self.origin)/api/features")!) { _, response, _ in
            reachable = (response as? HTTPURLResponse)?.statusCode == 200
            probe.fulfill()
        }.resume()
        wait(for: [probe], timeout: 5)
        try XCTSkipUnless(reachable, "Start `mock_service.py --port 18360` from this revision")
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
        let warning = app.alerts["Some Instruments Unavailable"]
        if warning.waitForExistence(timeout: 2) { warning.buttons["OK"].tap() }
        // Text view: a steady backdrop for the pixel measurement.
        choose("Text", in: menu("fst.paths.display", in: app), app: app)
        let instrument = menu("fst.paths.instrument", in: app)
        XCTAssertTrue(instrument.waitForExistence(timeout: 10))
        return instrument
    }

    /// VoiceOver reads the selector as "Instrument, <name>" in every pose.
    @MainActor
    private func assertAccessible(_ name: String, _ instrument: XCUIElement,
                                  file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(instrument.label, "Instrument", file: file, line: line)
        XCTAssertEqual(instrument.value as? String, name, file: file, line: line)
        XCTAssertGreaterThanOrEqual(instrument.frame.height, 44, file: file, line: line)
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
    ///   - selector: The instrument menu.
    ///   - name: Attachment name.
    /// - Returns: Content width in points.
    @MainActor
    private func contentWidth(of selector: XCUIElement, name: String) throws -> CGFloat {
        // Let the label's layout change settle before the capture.
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let shot = selector.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "paths-instrument-\(name)"
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
