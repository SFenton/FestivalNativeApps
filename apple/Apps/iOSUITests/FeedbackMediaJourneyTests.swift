import UIKit
import XCTest

/// Feedback accepts photos through the system picker and from a drag (#373).
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
/// - The upload journey uses either picker layout and a photo in the simulator library.
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
    private static let origin = ProcessInfo.processInfo.environment["FST_FEEDBACK_FIXTURE_URL"]
        ?? "http://127.0.0.1:18373"
    /// The Photos app, the drag source.
    private static let photosBundle = "com.apple.mobileslideshow"
    /// Keep the runner's actual Duo inner portrait instead of applying the cover orientation.
    private static let expectsInnerPortrait = ProcessInfo.processInfo.environment["FST_FEEDBACK_INNER_PORTRAIT"] == "1"

    override func setUpWithError() throws {
        continueAfterFailure = false
        if !Self.expectsInnerPortrait { XCUIDevice.shared.orientation = .portrait }
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
        assertRequestedViewport(in: app)
        if isPad { WindowResize.fill(app) }
        // Both orientations of the Duo inner display are regular; the 466 pt cover is compact.
        let isUnfoldedDuo = isDuo && WindowResize.windowWidth(app) >= 600
        FeedbackJourney.openForm(in: app)
        let library = app.descendants(matching: .any)["fst.settings.feedback.library"]
        openPhotoLibrary(in: app)

        guard isPad || isUnfoldedDuo else {
            XCTAssertFalse(library.waitForExistence(timeout: 4),
                           "A compact iPhone window opened the photo library beside the form")
            // This branch checks placement only; the upload journey confirms the selection.
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
        let formPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.35))
        for _ in 0..<4 where !title.isHittable {
            formPoint.press(forDuration: 0.05, thenDragTo: formPoint.withOffset(CGVector(dx: 0, dy: 220)))
        }
        XCTAssertTrue(title.isHittable, "The form is not usable beside the library")
        let attach = app.buttons["fst.settings.feedback.attach"]
        revealMedia(attach, from: formPoint)

        let photos = library.images.matching(identifier: "PXGGridLayout-Info")
        XCTAssertTrue(photos.element(boundBy: 1).waitForExistence(timeout: 15), "The library shows no photos")
        let first = photos.element(boundBy: 0)
        tapPhoto(first, in: library, app: app)
        XCTAssertTrue(attachment(1, in: app).waitForExistence(timeout: 15), "Ticking a photo did not attach it")
        tapPhoto(photos.element(boundBy: 1), in: library, app: app)
        XCTAssertTrue(attachment(2, in: app).waitForExistence(timeout: 15), "Ticking a second photo did not attach it")
        assertStripControlsAccessible(count: 2, in: app)

        // Removing the first attachment unticks its photo; the other one moves up.
        let remove = app.buttons["fst.settings.feedback.attachment.1.remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        remove.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { !self.attachment(2, in: app).exists }, "Removing an attachment kept two")
        XCTAssertTrue(attachment(1, in: app).exists, "Removing one attachment dropped both")
        XCTAssertTrue(FeedbackJourney.waitUntil { !first.isSelected }, "Removing the attachment left its photo ticked")

        let hide = app.buttons["fst.settings.feedback.library.hide"]
        XCTAssertTrue(hide.exists)
        XCTAssertEqual(hide.label, "Hide Photo Library")
        XCTAssertGreaterThanOrEqual(hide.frame.width, 43.5)
        XCTAssertGreaterThanOrEqual(hide.frame.height, 43.5)
        hide.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { !library.exists }, "Hide left the library open")
        XCTAssertTrue(FeedbackJourney.scrollTo(attach, in: app), "Attach Media did not return in the full-width form")
        XCTAssertTrue(attachment(1, in: app).exists, "Hiding the library dropped the attachment")
        for _ in 0..<4 where !title.isHittable {
            formPoint.press(forDuration: 0.05, thenDragTo: formPoint.withOffset(CGVector(dx: 0, dy: 220)))
        }
        XCTAssertTrue(FeedbackJourney.waitUntil { title.frame.width > besideWidth + 100 },
                      "The form did not take the sheet back (\(title.frame.width) ≤ \(besideWidth))")

        FeedbackJourney.cancelAndDiscard(in: app)
    }

    // The Xcode 27.1 CI SDK doesn't declare XCUIHinge.
    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    /// The same draft and photo survive a return to the half-open inner display.
    @MainActor
    func testDuoFeedbackAttachmentSurvivesHalfOpenReturn() throws {
        try assertDuoFeedbackAttachmentSurvives(returnAngle: .pi / 2)
    }

    /// The same draft and photo survive a return to the fully open inner display.
    @MainActor
    func testDuoFeedbackAttachmentSurvivesFullyOpenReturn() throws {
        try assertDuoFeedbackAttachmentSurvives(returnAngle: .pi)
    }

    /// Tick one seeded photo, then move the same form from inner to cover and back.
    ///
    /// - Parameter returnAngle: The inner display's target hinge angle in radians.
    @MainActor
    private func assertDuoFeedbackAttachmentSurvives(returnAngle: CGFloat) throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["FST_FEEDBACK_HINGE_TEST"] == "1"
                && (environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Opt in on a dedicated Duo with a synthetic photo seeded in Photos"
        )
        guard #available(iOS 27.3, *) else { throw XCTSkip("Needs the iOS 27.3 hinge runtime") }
        try requireFixture()
        let hinge = try XCTUnwrap(XCUIDevice.shared.hinge, "The Duo simulator has no XCUIHinge")
        let initialAngle = hinge.angle
        let app = fixtureApp(["FST_UI_TEST_FEEDBACK_HINGE_TRACE": "1"])
        defer {
            app.terminate()
            hinge.angle = initialAngle
        }

        hinge.angle = .pi
        app.launch()
        verifyDuoDisplay(in: app, hinge: hinge, angle: .pi, phase: "inner-initial")
        FeedbackJourney.openForm("feature", in: app)
        openPhotoLibrary(in: app)
        let library = app.descendants(matching: .any)["fst.settings.feedback.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 10))
        let photo = library.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 15), "Seed a synthetic photo before running this journey")
        let attach = app.buttons["fst.settings.feedback.attach"]
        let remove = app.buttons["fst.settings.feedback.attachment.1.remove"]
        let formPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.35))
        revealMedia(attach, from: formPoint)
        tapPhoto(photo, in: library, app: app)
        XCTAssertTrue(remove.waitForExistence(timeout: 15), "Ticking the photo did not attach it")
        let photoLabel = remove.label
        XCTAssertTrue(photoLabel.hasPrefix("Remove "), photoLabel)
        XCTAssertFalse(attachment(2, in: app).exists, "Expected exactly one attachment")
        verifyDuoDisplay(in: app, hinge: hinge, angle: .pi, phase: "inner-with-photo")

        hinge.angle = 0
        verifyDuoDisplay(in: app, hinge: hinge, angle: 0, phase: "cover")
        XCTAssertTrue(FeedbackJourney.waitUntil { !library.exists }, "The cover must not show the inline library")
        XCTAssertTrue(FeedbackJourney.scrollTo(remove, in: app), "The attachment was not reachable on the cover")
        XCTAssertEqual(remove.label, photoLabel)

        hinge.angle = returnAngle
        verifyDuoDisplay(in: app, hinge: hinge, angle: returnAngle, phase: "inner-return-before-scroll")
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "inner-return-before-scroll-accessibility"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTAssertTrue(app.buttons["fst.settings.feedback.close"].exists, "The open draft was dismissed")
        XCTAssertFalse(library.exists, "Reopening must not reopen the inline library automatically")
        if !remove.isHittable {
            if attach.isHittable {
                // The strip neighbours Attach Media. Don't sweep the entire form looking for
                // a tile when the fresh tree and adjacent validation already show it is absent.
                formPoint.press(forDuration: 0.05, thenDragTo: formPoint.withOffset(CGVector(dx: 0, dy: -110)))
            } else {
                revealMedia(attach, from: formPoint)
            }
        }
        let retained = remove.exists && remove.isHittable
        verifyDuoDisplay(in: app, hinge: hinge, angle: returnAngle, phase: "inner-return-after-scroll")
        if retained {
            XCTAssertEqual(remove.label, photoLabel, "The returned attachment is not the picked photo")
            XCTAssertGreaterThanOrEqual(min(remove.frame.width, remove.frame.height), 43.5)
        }

        // We entered no text. Cancel confirms only if the draft still owns an attachment,
        // independently of whether the strip or remove button was realized on screen.
        app.buttons["fst.settings.feedback.close"].tap()
        let discard = app.buttons["fst.settings.feedback.discard.confirm"].firstMatch
        let hasMedia = discard.waitForExistence(timeout: 5)
        if hasMedia { discard.tap() }
        XCTAssertTrue(FeedbackJourney.waitUntil {
            !app.textFields["fst.settings.feedback.field.title"].exists
        }, "Cancel did not close the form after the discard check")
        XCTAssertTrue(retained && hasMedia,
                      "After reopening: remove button \(retained ? "reachable" : "missing"); model \(hasMedia ? "kept media" : "empty")")
    }

    /// Record the physical pose, live app window and active screen captures before interacting.
    ///
    /// - Parameters:
    ///   - app: The app running on the same simulator throughout the journey.
    ///   - hinge: The simulator's hardware hinge.
    ///   - angle: The requested hinge angle in radians.
    ///   - phase: A label for the result bundle's attachments.
    @MainActor
    private func verifyDuoDisplay(in app: XCUIApplication, hinge: XCUIHinge, angle: CGFloat, phase: String) {
        let closed = angle == 0
        let window = app.windows.firstMatch
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 15) {
            let size = window.frame.size
            let short = min(size.width, size.height), long = max(size.width, size.height)
            return abs(hinge.angle - angle) < 0.05 && abs(short - (closed ? 466 : 669)) < 1
                && abs(long - (closed ? 678 : 951)) < 1
        }, "\(phase): hinge \(hinge.angle), expected \(angle); window \(window.frame)")
        let trace = app.descendants(matching: .any)["fst.settings.feedback.hinge-draft"].firstMatch
        let model = trace.exists ? "\n\(trace.value as? String ?? "Missing draft value")" : ""
        let pose = XCTAttachment(string: "angle=\(hinge.angle); window=\(window.frame)\(model)")
        pose.name = "\(phase)-pose"
        pose.lifetime = .keepAlways
        add(pose)
        // XCTest enumerates both panels, but the inactive panel cannot take a screenshot.
        let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        capture.name = "\(phase)-\(closed ? "cover" : "inner")-framebuffer"
        capture.lifetime = .keepAlways
        add(capture)
    }
    #endif

    /// Adding and removing a photo inserts and removes a native Form row on compact screens.
    @MainActor
    func testPresentedMediaRowsRestoreAfterRemoval() throws {
        try assertPresentedMediaRowsRestoreAfterRemoval(at: .large)
    }

    /// The same row transition must keep both controls readable and reachable at the largest size.
    @MainActor
    func testPresentedMediaRowsRestoreAfterRemovalAtLargestText() throws {
        try assertPresentedMediaRowsRestoreAfterRemoval(at: .accessibilityExtraExtraExtraLarge)
    }

    /// Verifies compact media row layout and accessibility across a round trip through Photos.
    ///
    /// - Parameter size: The preferred Dynamic Type size for the form.
    @MainActor
    private func assertPresentedMediaRowsRestoreAfterRemoval(at size: UIContentSizeCategory) throws {
        try requireFixture()
        let app = fixtureApp(["FST_DEBUG_FLAT_BACKDROP": "1"])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", size.rawValue]
        app.launch()
        defer { app.terminate() }
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone && WindowResize.windowWidth(app) < 600,
                          "Requires a compact phone with a synthetic photo seeded in Photos")
        FeedbackJourney.openForm("feature", in: app, maximumSwipes: size.isAccessibilityCategory ? 24 : 12)
        let heading = app.staticTexts["Media"]
        let attach = app.buttons["fst.settings.feedback.attach"]
        let strip = app.scrollViews["fst.settings.feedback.attachments"]
        let remove = app.buttons["fst.settings.feedback.attachment.1.remove"]
        XCTAssertTrue(FeedbackJourney.scrollTo(attach, in: app))
        XCTAssertTrue(heading.exists)
        XCTAssertFalse(strip.exists)
        XCTAssertEqual(attach.label, "Attach Media")
        XCTAssertGreaterThanOrEqual(attach.frame.height, 43.5)
        let emptyGap = attach.frame.minY - heading.frame.minY
        SongsUITestSupport.record(app, name: "feedback-media-empty-row")

        attach.tap()
        let photoLibrary = app.buttons["fst.settings.feedback.attach.media"]
        XCTAssertTrue(photoLibrary.waitForExistence(timeout: 5))
        photoLibrary.tap()
        pickPresentedPhoto(in: app)
        XCTAssertTrue(remove.waitForExistence(timeout: 15))
        XCTAssertTrue(FeedbackJourney.scrollTo(attach, in: app))
        assertStripControlsAccessible(count: 1, in: app)
        XCTAssertTrue(try SendingStatusSnapshot(app).readsInOrder(["attachment.1", "attachment.1.remove", "attach"]))
        XCTAssertGreaterThanOrEqual(attach.frame.height, 43.5)
        XCTAssertGreaterThanOrEqual(attach.frame.minY - strip.frame.maxY, 14,
                                    "The attachment needs the grouped row's bottom inset")
        SongsUITestSupport.record(app, name: "feedback-media-two-rows")

        remove.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { !remove.exists && !strip.exists })
        XCTAssertTrue(FeedbackJourney.scrollTo(attach, in: app))
        XCTAssertEqual(attach.frame.minY - heading.frame.minY, emptyGap, accuracy: 1,
                       "Removing the last photo must not leave an empty row or divider")
        XCTAssertTrue(attach.isEnabled)
        SongsUITestSupport.record(app, name: "feedback-media-empty-row-restored")
    }

    /// Pick a photo on either layout, then verify that uploading transitions to filing
    /// without a jump or a second spinner. The fixture never sends an actual report.
    @MainActor
    func testAttachedPhotoShowsUploadThenFiling() throws {
        let fixture = URLComponents(string: Self.origin)
        try XCTSkipUnless(fixture?.scheme == "http" && fixture?.host == "127.0.0.1" && fixture?.port != nil,
                          "Feedback submission must use a loopback fixture")
        try requireFixture()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        let app = fixtureApp(["FST_DEBUG_FLAT_BACKDROP": "1"])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        defer { app.terminate() }
        assertRequestedViewport(in: app)
        if isPad { WindowResize.fill(app) }
        FeedbackJourney.openForm("feature", in: app)
        openPhotoLibrary(in: app)
        let library = app.descendants(matching: .any)["fst.settings.feedback.library"]
        let formPoint = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.35))
        let attach = app.buttons["fst.settings.feedback.attach"]
        if isPad || WindowResize.windowWidth(app) >= 600 {
            XCTAssertTrue(library.waitForExistence(timeout: 10))
            let photo = library.images.matching(identifier: "PXGGridLayout-Info").firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 15))
            revealMedia(attach, from: formPoint)
            tapPhoto(photo, in: library, app: app)
        } else {
            pickPresentedPhoto(in: app)
            XCTAssertFalse(library.exists)
            XCTAssertTrue(FeedbackJourney.scrollTo(attach, in: app))
        }
        XCTAssertTrue(attachment(1, in: app).waitForExistence(timeout: 15))
        assertStripControlsAccessible(count: 1, in: app)
        XCTAssertTrue(try SendingStatusSnapshot(app).readsInOrder(["attachment.1", "attachment.1.remove"]))
        SongsUITestSupport.record(app, name: "feedback-photo-attached")

        let title = app.textFields["fst.settings.feedback.field.title"]
        for _ in 0..<4 where !title.isHittable {
            formPoint.press(forDuration: 0.05, thenDragTo: formPoint.withOffset(CGVector(dx: 0, dy: 220)))
        }
        XCTAssertTrue(title.isHittable, "The form is not usable after picking a photo")
        title.tap()
        title.typeText("Photo upload journey")
        let description = app.textViews["fst.settings.feedback.field.description"]
        XCTAssertTrue(FeedbackJourney.waitUntil { description.isHittable })
        description.tap()
        description.typeText("fixture-slow-media: verify the upload then filing status.")
        let submit = app.buttons["fst.settings.feedback.submit"]
        XCTAssertTrue(FeedbackJourney.waitUntil { submit.isHittable && submit.isEnabled })
        submit.tap()

        let stage = app.staticTexts["Uploading Media"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 3), "The upload status never appeared")
        let upload = try SendingStatusSnapshot(app)
        SongsUITestSupport.record(app, name: "feedback-uploading-media")
        XCTAssertEqual(upload.label("status.title"), "Uploading Media")
        XCTAssertEqual(upload.count("busy", .activityIndicator), 1)
        XCTAssertEqual(upload.count("progress", .progressIndicator), 1)
        XCTAssertEqual(upload.label("progress", .progressIndicator), "Upload progress")
        XCTAssertEqual(upload.label("stop", .button), "Stop Sending")
        try assertStopSendingAccessible(in: app)
        XCTAssertTrue(upload.readsInOrder(["busy", "status.title", "progress", "stop"]))
        XCTAssertEqual(upload.count("library"), 0)
        XCTAssertEqual(upload.count("field.title"), 0)

        XCTAssertTrue(app.staticTexts["Filing Request"].firstMatch.waitForExistence(timeout: 10))
        let filing = try SendingStatusSnapshot(app)
        SongsUITestSupport.record(app, name: "feedback-filing-with-media")
        XCTAssertEqual(filing.label("status.title"), "Filing Request")
        XCTAssertEqual(filing.count("busy", .activityIndicator), 1)
        XCTAssertEqual(filing.count("progress"), 0)
        XCTAssertEqual(filing.count("stop"), 0)
        XCTAssertTrue(filing.readsInOrder(["busy", "status.title", "status.subtitle"]))
        let before = try XCTUnwrap(upload.frame("busy", .activityIndicator))
        let after = try XCTUnwrap(filing.frame("busy", .activityIndicator))
        XCTAssertEqual(before.midX, after.midX, accuracy: 1)
        XCTAssertEqual(before.midY, after.midY, accuracy: 1)
        let sent = app.alerts["Request Sent"]
        XCTAssertTrue(sent.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertFalse(app.descendants(matching: .any)["fst.settings.feedback.status.title"].exists)
    }

    /// Check the usable hit region and painted label on the actual sheet.
    ///
    /// - Parameter app: The app showing Uploading Media.
    /// - Throws: A missing or unreadable screenshot.
    @MainActor
    private func assertStopSendingAccessible(in app: XCUIApplication) throws {
        let stop = app.buttons["fst.settings.feedback.stop"].firstMatch
        XCTAssertTrue(stop.isHittable && stop.isEnabled)
        let frame = stop.frame
        XCTAssertGreaterThanOrEqual(min(frame.width, frame.height), 43.5, "Stop Sending hit target: \(frame)")
        let image = try XCTUnwrap(stop.screenshot().image.cgImage)
        let contrast = try SongsUITestSupport.measuredTextContrast(in: SongsUITestSupport.bitmapPixels(image))
        XCTAssertGreaterThan(contrast.brightPixels, 100, "Stop Sending has no readable text")
        XCTAssertGreaterThanOrEqual(contrast.ratio, 4.5, "Stop Sending rendered contrast")
        XCTContext.runActivity(named: "Stop Sending contrast \(contrast.ratio):1") { _ in }
    }

    /// Check a requested inner-portrait run against the actual window, not the pose command.
    ///
    /// - Parameter app: The launched app in its physical simulator posture.
    @MainActor
    private func assertRequestedViewport(in app: XCUIApplication) {
        guard Self.expectsInnerPortrait else { return }
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.width >= 600 && window.height > window.width,
                      "Requires Duo inner portrait, not \(window.size)")
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
        let introduction = photosApp.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "New in Photos")).firstMatch
        if introduction.waitForExistence(timeout: 3) {
            let proceed = photosApp.buttons["Continue"].firstMatch
            XCTAssertTrue(proceed.isHittable, "Photos onboarding covers the drag source")
            proceed.tap()
            XCTAssertTrue(FeedbackJourney.waitUntil { !introduction.exists })
        }
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
        XCTAssertTrue(photo.isHittable, "The photo is obscured or offscreen")
        let screen = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            .coordinate(withNormalizedOffset: .zero)
        let target = description.frame
        photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(
            forDuration: 1.0,
            thenDragTo: screen.withOffset(CGVector(dx: target.midX, dy: target.midY)),
            withVelocity: .slow, thenHoldForDuration: 1.0)

        let attached = attachment(1, in: app).waitForExistence(timeout: 20)
        let shown = Int(marker.value as? String ?? "") ?? 0
        let notice = app.staticTexts["fst.settings.feedback.attachments.notice"]
        XCTAssertTrue(attached, "The dropped photo was not attached; highlights: \(shown); notice: \(notice.exists ? notice.label : "none")")
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
                          "Start `mock_service.py` for \(Self.origin) from this revision")
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

    /// Selects one photo in the compact system picker and confirms the selection.
    ///
    /// - Parameter app: The app presenting the picker.
    @MainActor
    private func pickPresentedPhoto(in app: XCUIApplication) {
        let photo = app.images.matching(identifier: "PXGGridLayout-Info").firstMatch
        let grid = app.scrollViews["photosView_content_scroll_view"].firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "The presented Photos picker did not open")
        // At AX5 the system privacy explanation can occupy the entire first viewport.
        for _ in 0..<4 where !(photo.exists && photo.isHittable) {
            let start = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.82))
            let end = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.32))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertTrue(photo.exists && photo.isHittable, "No reachable seeded photo in the presented picker:\n\(app.debugDescription)")
        photo.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 3) { photo.isSelected }, "The picker did not select the photo")
        // The system button keeps this identifier when its visible label is Done.
        let add = app.buttons.matching(identifier: "Add").firstMatch
        XCTAssertTrue(FeedbackJourney.waitUntil { add.isHittable && add.isEnabled }, app.debugDescription)
        add.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { !photo.exists }, "The photo picker did not close")
    }

    /// Reveal the media in the form's pane without scrolling the system picker.
    @MainActor
    private func revealMedia(_ attach: XCUIElement, from point: XCUICoordinate) {
        for _ in 0..<4 where !attach.isHittable {
            let start = point.withOffset(CGVector(dx: 0, dy: 220))
            start.press(forDuration: 0.05, thenDragTo: point)
        }
        XCTAssertTrue(attach.isHittable, "The media group is not reachable in the form")
    }

    /// The attachment thumbnail at a 1-based position.
    @MainActor
    private func attachment(_ position: Int, in app: XCUIApplication) -> XCUIElement {
        app.buttons["fst.settings.feedback.attachment.\(position)"]
    }

    /// The attachment strip on iOS/iPadOS (#486, `scroll-indicators` R3: its indicator is
    /// hidden): each thumbnail is a named button followed by its named remove button, and
    /// every target is at least 44 pt and wholly inside the strip, which clips (the remove
    /// targets once started 6 pt above it). The hosted
    /// `FeedbackAttachmentStripAccessibilityTests` cover order, state and activation.
    ///
    /// - Parameters:
    ///   - count: Attachments shown.
    ///   - app: The app with the form open.
    @MainActor
    private func assertStripControlsAccessible(count: Int, in app: XCUIApplication) {
        let strip = app.scrollViews["fst.settings.feedback.attachments"]
        XCTAssertTrue(strip.waitForExistence(timeout: 5), "The attachment strip is not a scroll view")
        let bounds = strip.frame
        for position in 1...count {
            let open = attachment(position, in: app)
            let remove = app.buttons["fst.settings.feedback.attachment.\(position).remove"]
            XCTAssertTrue(remove.exists, "Attachment \(position) has no remove button")
            XCTAssertTrue(open.label.hasPrefix("Photo \(position), "), "Thumbnail label: \(open.label)")
            XCTAssertTrue(remove.label.hasPrefix("Remove "), "Remove label: \(remove.label)")
            XCTAssertTrue(remove.isHittable, "Remove \(position) is not hittable")
            for (name, frame) in [("thumbnail", open.frame), ("remove", remove.frame)] {
                // One pixel of tolerance: a fixed 44 pt control can land off the pixel grid.
                XCTAssertGreaterThanOrEqual(min(frame.width, frame.height), 43.5, "\(name) \(position) \(frame)")
                XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY - 0.5,
                                            "\(name) \(position) \(frame) is clipped by the strip \(bounds)")
                XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY + 0.5,
                                         "\(name) \(position) \(frame) is clipped by the strip \(bounds)")
            }
        }
    }

    /// Tap a remote photo from the main window's coordinate space. On Duo the UIKit
    /// picker's cell can report its centre relative to the picker instead of the window.
    @MainActor
    private func tapPhoto(_ photo: XCUIElement, in library: XCUIElement, app: XCUIApplication) {
        let pane = library.frame
        let top = app.buttons["fst.settings.feedback.library.hide"].frame.maxY
        let viewport = CGRect(x: pane.minX, y: top, width: pane.width, height: pane.maxY - top)
        let frame = photo.frame
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let position = viewport.contains(center)
            ? center : CGPoint(x: viewport.minX + center.x, y: viewport.minY + center.y)
        let window = app.windows.firstMatch
        let bounds = window.frame
        XCTAssertTrue(!viewport.isEmpty && viewport.contains(position) && bounds.contains(position),
                      "The photo \(frame) is outside the picker \(viewport) in \(bounds)")
        window.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: position.x - bounds.minX, dy: position.y - bounds.minY)).tap()
        XCTAssertTrue(library.exists, "Tapping a photo dismissed the form")
    }
}
