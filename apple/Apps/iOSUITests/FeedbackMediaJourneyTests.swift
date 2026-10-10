import UIKit
import XCTest

/// Issue #373: the Report an Issue form takes photos beside it and from a drag.
///
/// - The inline photo library (pattern `modal-shell` R11): at regular width (iPad, the
///   unfolded iPhone Duo) Attach Media › Photo Library opens the system picker in a pane
///   beside the form, laid out by `HingeRow`. Ticking a photo attaches it, removing the
///   attachment unticks it, Hide closes the pane and keeps the attachments, and Cancel
///   still asks before discarding. On an ordinary iPhone the pane never appears (the
///   picker stays presented over the form, as before).
/// - The cross-app drop (iPad): with the app and Photos side by side, a photo dragged
///   from Photos onto the Description box shows the drop highlight and attaches. The
///   Form's collection view claims drags over its rows, so this fails without the UIKit
///   drop proxy (`FeedbackSheetDropInteraction`). XCUITest's long-press drag blocks
///   until the drop, so the Debug marker `fst.settings.feedback.drop.shown`
///   (`FST_UI_TEST_DROP_MARKER=1`) counts the highlights shown.
///
/// Run against a fixture service started from this revision (each test skips without it;
/// the fixture reports `feedback: true` and nothing is submitted):
///
/// ```
/// python3 tools/mock_service.py --port 18373 &
/// python3 tools/ios_sim.py uitest --device ipad --only FeedbackMediaJourneyTests
/// python3 tools/ios_sim.py uitest --device duo --pose unfolded --set-pose --only FeedbackMediaJourneyTests
/// python3 tools/ios_sim.py uitest --device duo --only FeedbackMediaJourneyTests   # folded
/// python3 tools/ios_sim.py uitest --device iphone --only FeedbackMediaJourneyTests
/// ```
final class FeedbackMediaJourneyTests: XCTestCase {
    /// Loopback fixture service.
    private static let origin = "http://127.0.0.1:18373"
    /// The Photos app, the drag source.
    private static let photosBundle = "com.apple.mobileslideshow"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Journeys

    /// Regular width: the library opens beside the form, ticks attach, removing an
    /// attachment unticks it, Hide keeps the attachments, Cancel confirms the discard.
    /// iPhone and the folded Duo: the library never opens beside the form; the system
    /// picker is presented over it instead.
    @MainActor
    func testInlineLibraryOpensBesideFormAndAttaches() throws {
        try requireFixture()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let isDuo = (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo")
        let app = fixtureApp()
        app.launch()
        defer { app.terminate() }
        if isPad { WindowResize.fill(app) }
        // The Duo's inner display is 951 pt wide; folded (466 pt) it is a compact iPhone.
        let isUnfoldedDuo = isDuo && WindowResize.windowWidth(app) >= 900
        FeedbackJourney.openForm(in: app)
        let library = app.descendants(matching: .any)["fst.settings.feedback.library"]
        openPhotoLibrary(in: app)

        guard isPad || isUnfoldedDuo else {
            XCTAssertFalse(library.waitForExistence(timeout: 4),
                           "A compact iPhone window opened the photo library beside the form")
            // The system picker is presented over the form (iPhone unchanged). It runs out of
            // process, so its own Close button is not in this app's tree: the app ends here.
            XCTAssertTrue(FeedbackJourney.waitUntil { !app.buttons["fst.settings.feedback.close"].isHittable },
                          "The photo library was not presented over the compact form")
            return
        }

        XCTAssertTrue(library.waitForExistence(timeout: 10), "The library did not open beside the form")
        let title = app.textFields["fst.settings.feedback.field.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let besideWidth = title.frame.width
        XCTAssertGreaterThanOrEqual(library.frame.minX, title.frame.maxX - 1,
                                    "The library \(library.frame) covers the form's title \(title.frame)")
        XCTAssertTrue(title.isHittable, "The form is not usable beside the library")

        let photos = library.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.element(boundBy: 1).waitForExistence(timeout: 15), "The library shows no photos")
        // The out-of-process grid's cells report not hittable: tap their centres.
        let first = photos.element(boundBy: 0)
        tapCentre(of: first)
        XCTAssertTrue(attachment(1, in: app).waitForExistence(timeout: 15), "Ticking a photo did not attach it")
        tapCentre(of: photos.element(boundBy: 1))
        XCTAssertTrue(attachment(2, in: app).waitForExistence(timeout: 15), "Ticking a second photo did not attach it")

        // Removing the first attachment unticks its photo; the other one moves up.
        let remove = app.buttons["fst.settings.feedback.attachment.1.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { !self.attachment(2, in: app).exists }, "Removing an attachment kept two")
        XCTAssertTrue(attachment(1, in: app).exists, "Removing one attachment dropped both")
        XCTAssertTrue(FeedbackJourney.waitUntil { !first.isSelected }, "Removing the attachment left its photo ticked")

        let hide = app.buttons["fst.settings.feedback.library.hide"]
        XCTAssertTrue(hide.exists)
        hide.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { !library.exists }, "Hide left the library open")
        XCTAssertTrue(attachment(1, in: app).exists, "Hiding the library dropped the attachment")
        XCTAssertTrue(FeedbackJourney.waitUntil { title.frame.width > besideWidth + 100 },
                      "The form did not take the sheet back (\(title.frame.width) ≤ \(besideWidth))")

        FeedbackJourney.cancelAndDiscard(in: app)
    }

    /// iPad: a photo dragged from Photos onto the Description box shows the drop
    /// highlight and attaches.
    @MainActor
    func testDropFromPhotosShowsHighlightAndAttaches() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Cross-app drag needs iPad windows")
        try requireFixture()
        let app = fixtureApp(["FST_UI_TEST_DROP_MARKER": "1"])
        app.launch()
        let photosApp = XCUIApplication(bundleIdentifier: Self.photosBundle)
        defer {
            // iPadOS remembers each app's window size: give both their full width back.
            app.activate()
            WindowResize.fill(app)
            photosApp.activate()
            WindowResize.fill(photosApp)
            photosApp.terminate()
            app.terminate()
        }
        XCTAssertTrue(WindowResize.tile(app, .left), "Could not tile the app to the left")
        photosApp.activate()
        Thread.sleep(forTimeInterval: 2)
        // iPadOS usually opens Photos in the free half; otherwise arrange the two front
        // windows. (The window-controls query matches the first window's controls, so
        // tiling Photos itself can move this app instead.)
        if !sideBySide(app, photosApp) {
            app.activate()
            WindowResize.tile(app, .leftAndRight)
        }
        XCTAssertTrue(sideBySide(app, photosApp),
                      "App \(app.windows.firstMatch.frame) and Photos \(photosApp.windows.firstMatch.frame) are not side by side")
        app.activate()
        FeedbackJourney.openForm(in: app)

        let marker = app.descendants(matching: .any)["fst.settings.feedback.drop.shown"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10), "Drop marker missing (Debug build?)")
        XCTAssertEqual(marker.value as? String, "0")
        let description = app.textViews["fst.settings.feedback.field.description"]
        XCTAssertTrue(description.waitForExistence(timeout: 10))
        XCTAssertFalse(attachment(1, in: app).exists)

        let photo = photosApp.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "Photos shows no photo to drag")
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .coordinate(withNormalizedOffset: .zero)
        let target = description.frame
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 1.0,
            thenDragTo: screen.withOffset(CGVector(dx: target.midX, dy: target.midY)),
            withVelocity: .slow, thenHoldForDuration: 1.0)

        XCTAssertTrue(attachment(1, in: app).waitForExistence(timeout: 20),
                      "The dropped photo was not attached")
        let shown = Int(marker.value as? String ?? "") ?? 0
        XCTAssertGreaterThanOrEqual(shown, 1, "No drop highlight showed during the drag")
        FeedbackJourney.cancelAndDiscard(in: app)
    }

    // MARK: - Helpers

    /// Whether two apps' windows sit side by side without overlapping.
    @MainActor
    private func sideBySide(_ first: XCUIApplication, _ second: XCUIApplication) -> Bool {
        let a = first.windows.firstMatch.frame, b = second.windows.firstMatch.frame
        guard a.width > 0, b.width > 0 else { return false }
        return a.maxX <= b.minX + 1 || b.maxX <= a.minX + 1
    }

    /// Skip unless the fixture service answers.
    @MainActor
    private func requireFixture() throws {
        try XCTSkipUnless(FeedbackJourney.fixtureReachable(origin: Self.origin),
                          "Start `mock_service.py --port 18373` from this revision")
    }

    /// The fixture app on the Settings tab.
    @MainActor
    private func fixtureApp(_ extra: [String: String] = [:]) -> XCUIApplication {
        FeedbackJourney.fixtureApp(origin: Self.origin, extra)
    }

    /// Attach Media › Photo Library.
    ///
    /// - Parameter app: The app with the form open.
    @MainActor
    private func openPhotoLibrary(in app: XCUIApplication) {
        let attach = app.buttons["fst.settings.feedback.attach"]
        XCTAssertTrue(FeedbackJourney.scrollTo(attach, in: app), "Attach Media missing")
        attach.tap()
        let media = app.buttons["fst.settings.feedback.attach.media"]
        XCTAssertTrue(media.waitForExistence(timeout: 5), "Attach Media has no Photo Library item")
        media.tap()
    }

    /// The attachment thumbnail at a 1-based position.
    @MainActor
    private func attachment(_ position: Int, in app: XCUIApplication) -> XCUIElement {
        app.buttons["fst.settings.feedback.attachment.\(position)"]
    }

    /// Tap the centre of an element XCUITest reports as not hittable.
    @MainActor
    private func tapCentre(of element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    }
}
