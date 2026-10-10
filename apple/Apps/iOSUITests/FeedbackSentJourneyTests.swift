import XCTest

/// Issue #565: a filed report closes its form, then "Report Sent" shows over Settings.
///
/// After Submit the service files the report (the fixture answers issue #1). The form
/// closes by itself; only then does the single-Done alert appear, over Settings, with no
/// Cancel, Close or Submit left behind it (pattern `modal-shell` R7: one presentation at
/// a time). Done dismisses only the alert and returns VoiceOver to the row that opened
/// the form, read through the Debug focus trace `fst.nav.a11y-focus`
/// (`FST_DEBUG_A11Y_FOCUS_TRACE=1`). A refused report or a failed filing keeps the form,
/// its input and "Couldn't Send".
///
/// HIG Sheets: a sheet presents "a scoped, context-related task people complete before
/// returning to the parent view"; HIG Modality: "Let people dismiss a modal before
/// presenting another"; HIG Alerts: "A single default-only button is Done".
///
/// Needs `tools/mock_service.py` (`apple-ci` serves it with `--large-catalogue` on the
/// default port 8765; `FST_FEEDBACK_FIXTURE_URL` points a local run at another port):
///
/// ```
/// python3 tools/mock_service.py --port 18565 &
/// TEST_RUNNER_FST_FEEDBACK_FIXTURE_URL=http://127.0.0.1:18565 \
///   python3 tools/ios_sim.py uitest --only FeedbackSentJourneyTests
/// ```
final class FeedbackSentJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_FEEDBACK_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    // MARK: - Journeys

    /// Report an Issue: the form closes itself, then "Report Sent" (issue #1) over
    /// Settings; Done returns focus to Report an Issue.
    @MainActor
    func testFiledReportClosesFormThenShowsSentAlert() throws {
        try fileAndExpectSentAlert(kind: "bug", title: "Report Sent")
    }

    /// Request a Feature: the same order with "Request Sent".
    @MainActor
    func testFiledRequestClosesFormThenShowsSentAlert() throws {
        try fileAndExpectSentAlert(kind: "feature", title: "Request Sent")
    }

    /// A refused report (503 `feedback_busy`) and a failed filing keep the form, its
    /// input and Submit, under "Couldn't Send".
    @MainActor
    func testRefusedOrFailedReportKeepsForm() throws {
        try requireFixture()
        let app = FeedbackJourney.fixtureApp(origin: Self.origin)
        app.launch()
        defer { app.terminate() }
        for marker in ["fixture-unavailable", "fixture-failed"] {
            FeedbackJourney.openForm(in: app)
            fill(in: app, description: "Journey \(marker)")
            app.buttons["fst.settings.feedback.submit"].tap()
            let failure = app.alerts["Couldn't Send"]
            XCTAssertTrue(failure.waitForExistence(timeout: FestivalApp.budget(30)),
                          "\(marker): no Couldn't Send alert")
            failure.buttons.firstMatch.tap()
            XCTAssertTrue(FeedbackJourney.waitUntil { !failure.exists }, "\(marker): the alert stayed")
            let description = app.textViews["fst.settings.feedback.field.description"]
            XCTAssertTrue(description.exists, "\(marker): the form closed after a failure")
            XCTAssertEqual(description.value as? String, "Journey \(marker)",
                           "\(marker): the input was not kept")
            XCTAssertTrue(app.buttons["fst.settings.feedback.submit"].isEnabled,
                          "\(marker): Submit is not available again")
            XCTAssertFalse(app.alerts["Report Sent"].exists)
            FeedbackJourney.cancelAndDiscard(in: app)
        }
    }

    // MARK: - Steps

    /// Open a form, file it against the fixture and check the sent sequence.
    ///
    /// - Parameters:
    ///   - kind: `bug` or `feature`.
    ///   - title: The alert's expected title.
    @MainActor
    private func fileAndExpectSentAlert(kind: String, title: String) throws {
        try requireFixture()
        let app = FeedbackJourney.fixtureApp(origin: Self.origin, ["FST_DEBUG_A11Y_FOCUS_TRACE": "1"])
        app.launch()
        defer { app.terminate() }
        FeedbackJourney.openForm(kind, in: app)
        fill(in: app, description: "Journey: the sent alert follows the closed form.")
        let submit = app.buttons["fst.settings.feedback.submit"]
        XCTAssertTrue(submit.isEnabled, "Submit is not enabled for a valid form")
        submit.tap()

        // The alert never sits on the form: when it shows, the form is gone.
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: FestivalApp.budget(30)), "No \(title) alert")
        for id in ["submit", "close", "field.title"] {
            XCTAssertFalse(app.descendants(matching: .any)["fst.settings.feedback.\(id)"].exists,
                           "The form's \(id) is still on screen under the alert")
        }
        XCTAssertTrue(alert.staticTexts["Thank you! It was filed as issue #1."].exists,
                      "The alert does not name issue #1")
        // iOS 26 alerts expose one SwiftUI action as a button nested in a
        // button with the same identifier, so compare distinct labels.
        let labels = Set(alert.buttons.allElementsBoundByIndex.map(\.label).filter { !$0.isEmpty })
        XCTAssertEqual(labels, ["Done"], "The sent alert offers more than Done: \(alert.debugDescription)")
        let done = alert.buttons["fst.settings.feedback.done"].firstMatch
        XCTAssertEqual(done.label, "Done")
        XCTAssertGreaterThanOrEqual(done.frame.height, 44, "Done is below the 44 pt target")
        // Audit the alert only; Settings behind it has its own journeys. The
        // system alert caps its title and message size (it scrolls instead),
        // which the audit reports as partial Dynamic Type: system chrome, as
        // the Songs accessory type cap.
        var alertIssues: [String] = []
        let alertFrame = alert.frame
        try app.performAccessibilityAudit(for: .all) { issue in
            guard let element = issue.element,
                  alertFrame.contains(CGPoint(x: element.frame.midX, y: element.frame.midY)) else { return true }
            if issue.auditType == .dynamicType, element.elementType == .staticText { return true }
            alertIssues.append("\(element.identifier) \(element.label): \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(alertIssues, [], "Sent alert accessibility audit issues")

        done.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { !alert.exists }, "Done left the alert")
        let row = FeedbackJourney.row(kind, in: app)
        XCTAssertTrue(row.isHittable, "Settings is not usable after Done")
        XCTAssertFalse(app.textFields["fst.settings.feedback.field.title"].exists,
                       "Done reopened the form")
        let trace = app.descendants(matching: .any)["fst.nav.a11y-focus"]
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: FestivalApp.budget(5)) {
            (trace.label as String).hasPrefix("fst.settings.feedback.\(kind):")
        }, "VoiceOver focus did not return to the row (trace: \(trace.label))")
    }

    /// Type a description (the title keeps its prefix and gets text after it).
    ///
    /// - Parameters:
    ///   - app: The app with the form open.
    ///   - description: Description text.
    @MainActor
    private func fill(in app: XCUIApplication, description: String) {
        let title = app.textFields["fst.settings.feedback.field.title"]
        title.tap()
        title.typeText("Sent journey")
        let box = app.textViews["fst.settings.feedback.field.description"]
        XCTAssertTrue(box.waitForExistence(timeout: FestivalApp.budget(5)))
        box.tap()
        box.typeText(description)
    }

    /// Skip unless the fixture service answers.
    @MainActor
    private func requireFixture() throws {
        try XCTSkipUnless(FeedbackJourney.fixtureReachable(origin: Self.origin),
                          "Start `mock_service.py` (default port 8765) from this revision")
    }
}
