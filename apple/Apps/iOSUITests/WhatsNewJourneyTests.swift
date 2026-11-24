import UIKit
import XCTest

/// "What's New" launch sheet, its persisted dismissal and Settings replay, plus the Settings
/// Service Info card against the loopback fixture (`tools/mock_service.py --port 18791`).
///
/// Launch presentation is off by default in Debug (`FST_DEBUG_WHATS_NEW`); these journeys
/// opt in with `fresh` (forget the stored dismissal, then use the real gate) and `on` (real
/// gate only), so the relaunch assertion exercises the actual persisted `{version, hash}`.
final class WhatsNewJourneyTests: XCTestCase {
    private static let fixture = ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:18791"
    private static let releaseNote = "The first release of Festival Score Tracker for iPhone."

    @MainActor
    private func app(_ extra: [String: String]) -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.fixture,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ].merging(extra) { _, new in new })
    }

    /// The outer Duo sheet uses only the rail Close, and release notes wrap clear of that rail.
    @MainActor
    func testWhatsNewUsesOneCloseOnFoldedDuo() throws {
        try XCTSkipUnless((ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"))
        let app = app(["FST_DEBUG_WHATS_NEW": "force"])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        let matches = app.buttons.matching(identifier: "fst.whats-new.close")
        let close = matches.firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: FestivalApp.budget(15)))
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(abs(window.width - 466) < 1 && abs(window.height - 678) < 1, "Needs the outer portrait display")
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(close.label, "Close")
        XCTAssertTrue(close.isHittable)
        XCTAssertFalse(app.buttons["fst.whats-new.dismiss"].exists)
        XCTAssertTrue(app.staticTexts["Version 2610.01.01"].waitForExistence(timeout: FestivalApp.budget(10)))
        let note = app.staticTexts[Self.releaseNote]
        XCTAssertTrue(note.exists)
        XCTAssertGreaterThan(note.frame.height, 37, "The release note wraps before the vertical rail")
        XCTAssertLessThanOrEqual(note.frame.maxX, close.frame.minX - 20)
        assertPaintedReleaseNote(note, in: app)
        SongsUITestSupport.record(app, name: "whats-new-folded")
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: FestivalApp.budget(10)))
    }

    /// A fresh changelog presents once at launch; Dismiss closes it and a relaunch with the
    /// real gate does not present it again.
    @MainActor
    func testWhatsNewShowsOnceAndDismissPersistsAcrossLaunches() throws {
        continueAfterFailure = false
        let first = app(["FST_DEBUG_WHATS_NEW": "fresh"])
        first.launch()
        let dismiss = first.buttons["fst.whats-new.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 20), "What's New did not present at launch")
        // The checked-in WhatsNew.json placeholder; release builds regenerate it.
        XCTAssertTrue(first.staticTexts["Version 2610.01.01"].exists)
        SongsUITestSupport.record(first, name: "whats-new-launch")
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 10))
        first.terminate()

        let second = app(["FST_DEBUG_WHATS_NEW": "on"])
        second.launch()
        XCTAssertTrue(second.tabBars.buttons["Settings"].waitForExistence(timeout: 20))
        XCTAssertFalse(
            second.buttons["fst.whats-new.dismiss"].waitForExistence(timeout: 4),
            "Dismissed changelog presented again"
        )
    }

    /// Closing the stacked launch sheets restores the normal iPhone Songs filter above the list.
    @MainActor
    func testClosingLaunchSheetsRestoresTheInlineSongsFilter() throws {
        let device = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? UIDevice.current.name
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone && !device.contains("Duo"),
                          "Requires a non-folding iPhone")
        continueAfterFailure = false
        let app = app(["FST_DEBUG_FIRST_RUN": "force", "FST_DEBUG_WHATS_NEW": "fresh"])
        app.launch()
        let firstRun = app.buttons["fst.first-run.close"]
        XCTAssertTrue(firstRun.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertFalse(app.buttons["fst.whats-new.close"].exists)
        firstRun.tap()
        let dismiss = app.buttons["fst.whats-new.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: FestivalApp.budget(15)))
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: FestivalApp.budget(10)))

        let list = app.descendants(matching: .any)["fst.songs.list"]
        XCTAssertTrue(list.waitForExistence(timeout: FestivalApp.budget(10)))
        SongsUITestSupport.record(app, name: "songs-after-stacked-launch-sheets")
        let bottom = app.descendants(matching: .any).matching(identifier: "fst.songs.filter-field").firstMatch
        XCTAssertFalse(bottom.exists, "Only Duo uses the bottom Songs filter")
        let field = SongsUITestSupport.songsSearchField(in: app)
        XCTAssertTrue(field.isHittable)
        let row = try XCTUnwrap(SongsUITestSupport.songsRows(in: app, limit: 1).first)
        XCTAssertLessThanOrEqual(field.frame.maxY, row.frame.minY, "The filter precedes the song list")
    }

    /// The compact cover keeps whole release notes and the reference's default-size spacing.
    @MainActor
    func testWhatsNewKeepsWrappedNoteLeadingAndDismissHeight() throws {
        let app = app(["FST_DEBUG_WHATS_NEW": "force"])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        let note = app.staticTexts[Self.releaseNote]
        XCTAssertTrue(note.waitForExistence(timeout: FestivalApp.budget(15)))
        let width = app.windows.firstMatch.frame.width
        try XCTSkipUnless(abs(width - 402) < 1, "Needs the 402 pt iPhone viewport where the note wraps to two lines")
        let frame = note.frame
        XCTAssertGreaterThan(frame.height, 37, "Two subheadline lines keep their interline space")
        assertPaintedReleaseNote(note, in: app)

        let dismiss = app.buttons["fst.whats-new.dismiss"]
        XCTAssertTrue(dismiss.isHittable)
        XCTAssertEqual(dismiss.label, "Dismiss")
        XCTAssertGreaterThanOrEqual(dismiss.frame.height, 46, "The padded Dismiss control matches the cover")
        SongsUITestSupport.record(app, name: "whats-new-compact")
        dismiss.tap()
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: FestivalApp.budget(10)))
    }

    /// Checks the painted two-line note, including the short phrase that moves as a unit.
    @MainActor
    private func assertPaintedReleaseNote(_ note: XCUIElement, in app: XCUIApplication) {
        let frame = note.frame
        let lines = RecognizedText.lines(in: app.screenshot()).filter { frame.intersects($0.frame) }.map(\.text)
        XCTAssertTrue(RecognizedText.showsWhole(Self.releaseNote, in: lines.joined(separator: " ")))
        XCTAssertTrue(RecognizedText.showsWhole("for iPhone.", in: lines.last), "Release note line break: \(lines)")
    }

    /// Settings → Version → What's New "Show" replays the sheet; Close dismisses it.
    @MainActor
    func testSettingsReplaysWhatsNew() throws {
        continueAfterFailure = false
        let app = app(["FST_DEBUG_TAB": "settings"])
        app.launch()
        let row = app.buttons["fst.settings.whats-new"]
        // Settings is a LazyVStack: lower rows exist only once scrolled near.
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(row, in: app, scrollingUp: true)
        row.tap()
        let close = app.buttons["fst.whats-new.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["fst.whats-new.dismiss"].exists)
        close.tap()
        XCTAssertTrue(close.waitForNonExistence(timeout: 10))
    }

    /// Operator batch 6 (6.14): the full-height What's New closes when its list is pulled
    /// down past the top and released, and Dismiss is horizontally centred.
    @MainActor
    func testWhatsNewPullDownDismisses() throws {
        continueAfterFailure = false
        let app = app(["FST_DEBUG_TAB": "settings"])
        app.launch()
        let row = app.buttons["fst.settings.whats-new"]
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(row, in: app, scrollingUp: true)
        row.tap()
        let dismiss = app.buttons["fst.whats-new.dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 10))
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(dismiss.frame.midX, window.midX, accuracy: 2, "Dismiss is centred")
        SongsUITestSupport.record(app, name: "whats-new-settings-replay")
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        start.press(
            forDuration: 0.05,
            thenDragTo: app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
        )
        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 10), "Pulling down did not dismiss")
    }

    /// Service Info shows the fixture's idle worker and last publication; the First Run Guides
    /// rows follow the web order with "Score History".
    @MainActor
    func testServiceInfoAndFirstRunGuidesRender() throws {
        continueAfterFailure = false
        let app = app(["FST_DEBUG_TAB": "settings"])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        let state = app.descendants(matching: .any)
            .matching(identifier: "fst.settings.service-info.state").firstMatch
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 20))
        SongsUITestSupport.reveal(state, in: app, scrollingUp: true)
        let idle = NSPredicate(format: "value CONTAINS %@", "Idle")
        expectation(for: idle, evaluatedWith: state)
        waitForExpectations(timeout: 15)
        let published = app.descendants(matching: .any)
            .matching(identifier: "fst.settings.service-info.last-published").firstMatch
        SongsUITestSupport.reveal(published, in: app, scrollingUp: true)
        let window = app.windows.firstMatch
        if published.frame.maxY > window.frame.maxY - 122 {
            window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
                .press(forDuration: 0.05, thenDragTo: window.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)
                ))
        }
        let description = "Waiting for the Next Update"
        let title = "Last Successful Publication, "
        XCTAssertEqual(state.elementType, .staticText)
        XCTAssertEqual(state.label, "Leaderboard Service State, \(description)")
        XCTAssertTrue(published.label.hasPrefix(title) && published.label.contains("2026"), published.label)
        XCTAssertLessThanOrEqual(state.frame.maxY, published.frame.minY)
        SongsUITestSupport.record(app, name: "settings-service-info")
        XCTAssertTrue(RecognizedText.showsWhole(description, in: RecognizedText.recognizeLine(description, in: state).text))
        let stateFrame = state.frame
        if stateFrame.width >= 300 {
            let idle = try XCTUnwrap(RecognizedText.lines(in: app.screenshot()).first {
                stateFrame.intersects($0.frame) && $0.text == "Idle"
            })
            XCTAssertEqual(idle.frame.maxX, stateFrame.maxX, accuracy: 6, "Idle stays at the trailing edge when it fits")
        }
        let date = String(published.label.dropFirst(title.count))
        XCTAssertTrue(RecognizedText.showsWhole(date, in: RecognizedText.recognizeLine(date, in: published).text))
        XCTAssertEqual(published.elementType, .staticText)

        let history = app.buttons["fst.settings.first-run.playerhistory"]
        SongsUITestSupport.reveal(history, in: app, scrollingUp: true)
        XCTAssertTrue(history.label.contains("Score History"), history.label)
        SongsUITestSupport.record(app, name: "settings-first-run-guides")
    }
}
