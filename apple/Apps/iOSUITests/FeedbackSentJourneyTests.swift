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

    /// Issue #634: Submit swaps the form for the sending status, centred in the sheet. A
    /// report without media reads as filing from Submit (`modal-shell` R16, as on Android
    /// and Windows): "Filing Issue" with the owner's sentence, no bar and no Stop Sending.
    /// The `fixture-slow` job answers its upload after 2 s and files after four more status
    /// reads, so the status stays through both phases: the fields leave the screen and the
    /// tree, the text never changes, one named busy indicator stays put, and the filed form
    /// still closes before "Report Sent" (#565). The Uploading Media stage (bar, Stop
    /// Sending, the hand-off) is covered by the hosted `FeedbackSendingStatusAccessibilityTests`.
    @MainActor
    func testSubmitSwapsFormForCentredSendingStatus() throws {
        try requireFixture()
        let app = FeedbackJourney.fixtureApp(origin: Self.origin)
        app.launch()
        defer { app.terminate() }
        FeedbackJourney.openForm(in: app)
        fill(in: app, description: "Journey fixture-slow: the sending status replaces the form.")
        app.buttons["fst.settings.feedback.submit"].tap()

        let title = app.descendants(matching: .any)["fst.settings.feedback.status.title"]
        let sentence = "We\u{2019}re filing your issue. Please wait while we upload it."
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: FestivalApp.budget(2)) {
            title.exists && title.label == "Filing Issue"
        }, "No Filing Issue status while sending (title: \(title.exists ? title.label : "missing"))")
        // Each stage is read from one snapshot: on the slow CI runner a dozen live queries
        // outlasted the fixture's filing, and the sheet had closed under them (#662).
        let sending = try SendingStatusSnapshot(app)
        XCTAssertEqual(sending.label("status.title"), "Filing Issue")
        XCTAssertEqual(sending.label("status.subtitle"), sentence)
        XCTAssertEqual(sending.count("progress", .progressIndicator), 0, "An upload bar shows with no media")
        XCTAssertEqual(sending.count("stop", .button), 0, "Stop Sending shows with no media")
        XCTAssertEqual(sending.count("busy", .activityIndicator), 1, "No single busy indicator while sending")
        XCTAssertEqual(sending.label("busy", .activityIndicator), "Sending your issue")
        for id in ["field.title", "field.description", "attach"] {
            XCTAssertEqual(sending.count(id), 0, "The form's \(id) is still reachable behind the status")
        }
        // Across the sheet (page-sized on iPad), whose bar spans its width; down the window.
        let sheet = try XCTUnwrap(sending.sheetBar, "No sheet bar holds Cancel/Close")
        let window = sending.window
        let sendingSpinner = try XCTUnwrap(sending.frame("busy", .activityIndicator))
        let titleFrame = try XCTUnwrap(sending.frame("status.title"))
        XCTAssertEqual(sendingSpinner.midX, sheet.midX, accuracy: 2, "The spinner is not centred across")
        XCTAssertEqual(titleFrame.midX, sheet.midX, accuracy: 2, "The title is not centred across")
        XCTAssertTrue((window.minY + window.height * 0.3...window.minY + window.height * 0.7)
            .contains(sendingSpinner.midY),
                      "The status is not centred down the sheet: \(sendingSpinner) in \(window)")

        // The upload answers after 2 s; the job then files after FEEDBACK_SLOW_READS status reads.
        let close = app.buttons["fst.settings.feedback.close"]
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: FestivalApp.budget(6)) {
            close.exists && close.label == "Close"
        }, "The sheet never reached filing (Close)")
        let filing = try SendingStatusSnapshot(app)
        XCTAssertEqual(filing.label("status.title"), "Filing Issue", "The status text changed while filing")
        XCTAssertEqual(filing.label("status.subtitle"), sentence)
        XCTAssertEqual(filing.count("busy", .activityIndicator), 1)
        XCTAssertEqual(filing.label("busy", .activityIndicator), "Sending your issue",
                       "The spinner was renamed between phases")
        let filingSpinner = try XCTUnwrap(filing.frame("busy", .activityIndicator))
        XCTAssertEqual(filingSpinner.midX, sendingSpinner.midX, accuracy: 1, "The spinner moved between phases")
        XCTAssertEqual(filingSpinner.midY, sendingSpinner.midY, accuracy: 1, "The spinner moved between phases")

        let alert = app.alerts["Report Sent"]
        XCTAssertTrue(alert.waitForExistence(timeout: FestivalApp.budget(15)), "No Report Sent alert")
        XCTAssertFalse(title.exists, "The status is still on screen under the alert")
        alert.buttons.firstMatch.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { FeedbackJourney.row("bug", in: app).isHittable },
                      "Settings is not usable after Done")
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

// MARK: - Sending status snapshot

/// The feedback sheet's nodes, bar and window from one accessibility snapshot, so a stage's
/// labels and frames are read at one instant rather than over a dozen live queries (#662).
private struct SendingStatusSnapshot {
    /// Every `fst.settings.feedback.*` node, in depth-first order.
    let nodes: [XCUIElementSnapshot]
    /// The navigation bar that holds Cancel/Close: the sheet's width (page-sized on iPad).
    let sheetBar: CGRect?
    /// The app's first window.
    let window: CGRect

    /// Snapshot the app.
    ///
    /// - Parameter app: The app with the feedback sheet open.
    /// - Throws: A snapshot XCTest cannot take.
    @MainActor
    init(_ app: XCUIApplication) throws {
        let root = try app.snapshot()
        var nodes: [XCUIElementSnapshot] = []
        var bars: [XCUIElementSnapshot] = []
        var windows: [XCUIElementSnapshot] = []
        func walk(_ node: XCUIElementSnapshot) {
            if node.identifier.hasPrefix("fst.settings.feedback.") { nodes.append(node) }
            if node.elementType == .navigationBar { bars.append(node) }
            if node.elementType == .window { windows.append(node) }
            node.children.forEach(walk)
        }
        walk(root)
        // By identifier alone: iOS 27 can type the close control, which carries a
        // confirmation dialog, as a disclosure triangle rather than a button.
        func holdsClose(_ node: XCUIElementSnapshot) -> Bool {
            node.identifier == "fst.settings.feedback.close" || node.children.contains(where: holdsClose)
        }
        self.nodes = nodes
        sheetBar = bars.first(where: holdsClose)?.frame
        window = windows.first?.frame ?? root.frame
    }

    /// The nodes with an identifier, optionally of one type.
    private func matching(_ id: String, _ type: XCUIElement.ElementType?) -> [XCUIElementSnapshot] {
        nodes.filter { $0.identifier == "fst.settings.feedback.\(id)" && (type == nil || $0.elementType == type) }
    }

    /// How many nodes carry `fst.settings.feedback.<id>` (of `type`, when given).
    func count(_ id: String, _ type: XCUIElement.ElementType? = nil) -> Int { matching(id, type).count }

    /// The first such node's label, or nil when there is none.
    func label(_ id: String, _ type: XCUIElement.ElementType? = nil) -> String? { matching(id, type).first?.label }

    /// The first such node's frame, or nil when there is none.
    func frame(_ id: String, _ type: XCUIElement.ElementType? = nil) -> CGRect? { matching(id, type).first?.frame }
}
