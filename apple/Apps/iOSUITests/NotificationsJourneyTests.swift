import UIKit
import XCTest

/// Notifications bell/sheet journeys against `tools/mock_service.py`'s
/// `/api/player/{id}/notifications` fixture (`fixture-player-1` seeds two rows,
/// both unread on first load).
///
/// Hosted (macOS) snapshot coverage for the sheet's loaded/empty/no-profile
/// states lives in `PlayerHistoryNotificationsRenderTests.swift`; this file
/// covers the bell's live unread badge, sheet presentation, seen-state after
/// dismissal, and a row opening its page in the main app (issue #75).
final class NotificationsJourneyTests: XCTestCase {
    private static let origin = ProcessInfo.processInfo.environment["FST_NOTIFICATIONS_FIXTURE_URL"]
        ?? "http://127.0.0.1:8765"

    @MainActor
    private func fixtureApp(profile: String = "fixture-player-1:Fixture Player 1") -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": Self.origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": profile,
        ])
    }

    /// The bell shows the unread count and opens the sheet; a row with a song destination
    /// dismisses the sheet and opens Song Detail on the main app's current tab (issue #75),
    /// and Back returns to the page that was showing before the sheet opened.
    @MainActor
    func testBellOpensSheetAndRowOpensSongDetailInMainApp() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        XCTAssertEqual(
            bell.label, "Notifications, 2 unread",
            "Two unseen fixture notifications must be announced with their count"
        )
        let songsRow = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(songsRow.waitForExistence(timeout: 15), "Songs is the page under the sheet")
        bell.tap()
        let sheetBar = app.navigationBars["Notifications"]
        XCTAssertTrue(sheetBar.waitForExistence(timeout: 15))
        let rankRow = app.buttons["fst.notifications.row.fixture-notif-1"]
        XCTAssertTrue(rankRow.waitForExistence(timeout: 15))
        rankRow.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "fst.song-detail.intensity").firstMatch
                .waitForExistence(timeout: 15)
        )
        XCTAssertTrue(sheetBar.waitForNonExistence(timeout: 10), "The sheet closes before Song Detail shows")
        XCTAssertFalse(app.buttons["fst.notifications.close"].exists, "Song Detail is not inside the sheet")

        let system = app.buttons["BackButton"]
        let back = system.waitForExistence(timeout: 5) ? system : app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Song Detail sits on the tab's own stack")
        back.tap()
        XCTAssertTrue(songsRow.waitForExistence(timeout: 10), "Back returns to Songs")
        XCTAssertFalse(app.navigationBars["Notifications"].exists, "Back does not reopen the sheet")
        XCTAssertEqual(bell.label, "Notifications", "Opening a row and closing the sheet marks rows seen")
    }

    /// Dismissal marks the rows seen. Reopening an entirely read feed still shows both
    /// rows, without a redundant "Older" heading.
    @MainActor
    func testDismissingSheetClearsUnreadBadge() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let bell = app.buttons["fst.shell.notifications"]
        XCTAssertTrue(bell.waitForExistence(timeout: 15))
        XCTAssertEqual(bell.label, "Notifications, 2 unread")
        // Empty, or on iOS 27 only the system badge's own phrase for this count (#678).
        XCTAssertTrue(
            FestivalApp.isAllowedBellValue(bell.value, label: bell.label),
            "The system badge's count must not be read twice (label already has it): '\(String(describing: bell.value))'"
        )
        bell.tap()
        XCTAssertTrue(app.navigationBars["Notifications"].waitForExistence(timeout: 15))
        app.buttons["fst.notifications.close"].tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        XCTAssertEqual(bell.label, "Notifications", "Viewing the sheet must mark rows seen")
        XCTAssertEqual(
            bell.value as? String ?? "", "",
            "A cleared badge must not leave a stale count for VoiceOver"
        )
        bell.tap()
        let first = app.buttons["fst.notifications.row.fixture-notif-1"]
        let second = app.buttons["fst.notifications.row.fixture-notif-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(second.isHittable)
        XCTAssertGreaterThan(second.frame.minY, first.frame.minY)
        XCTAssertFalse(app.staticTexts["New"].exists)
        XCTAssertFalse(app.staticTexts["Older"].exists)
    }

    /// An unread notification without a destination is still a button. It moves to
    /// Older when activated and keeps the sheet open.
    @MainActor
    func testAggregateNotificationCanBeMarkedReadWithoutNavigating() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: "fixture-notify-aggregate:Notifications Fixture")
        app.launch()
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        let aggregate = app.buttons["fst.notifications.row.fixture-notif-2"]
        XCTAssertTrue(aggregate.waitForExistence(timeout: 15))
        XCTAssertTrue(aggregate.label.contains("total score increased to 1,500 points"), aggregate.label)
        XCTAssertGreaterThanOrEqual(aggregate.frame.height, 44)
        XCTAssertFalse(app.staticTexts["Older"].exists)
        aggregate.tap()
        let older = app.staticTexts["Older"].firstMatch
        XCTAssertTrue(older.waitForExistence(timeout: 10), "Activating the aggregate marks it read")
        XCTAssertTrue(app.buttons["fst.notifications.close"].isHittable, "The sheet remains open")
        XCTAssertTrue(app.staticTexts["New"].firstMatch.exists, "The other notification remains unread")
        XCTAssertGreaterThanOrEqual(aggregate.frame.minY, older.frame.maxY - 0.5)
    }

    /// A multi-chart message wraps and grows without losing any of its four paragraphs
    /// or breaking them into separate accessibility stops.
    @MainActor
    func testMultiChartMessageScalesAndStaysOneButton() {
        continueAfterFailure = false
        let app = fixtureApp(profile: "fixture-notify-multi:Notifications Fixture")
        let rowID = "fst.notifications.row.fixture-notify-multi-1"
        func openRow() -> XCUIElement {
            app.launch()
            ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
            let row = app.buttons[rowID]
            XCTAssertTrue(row.waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts["New"].exists)
            XCTAssertEqual(app.buttons.matching(identifier: rowID).count, 1)
            XCTAssertTrue(row.isHittable)
            XCTAssertEqual(row.label.components(separatedBy: "\n\n").count, 4)
            for phrase in ["Lead, your first play", "Bass, your first play", "Drums, your first play",
                           "Tap Vocals, your first play", "Tap Vocals: First Play, Full Combo, Gold Stars"] {
                XCTAssertTrue(row.label.contains(phrase), row.label)
            }
            return row
        }

        let small = openRow()
        let smallHeight = small.frame.height
        let label = small.label
        app.terminate()
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        let large = openRow()
        XCTAssertGreaterThanOrEqual(large.frame.height, smallHeight * 1.35)
        XCTAssertEqual(large.label, label)
    }

    /// The two default-size row buttons keep the native List's height and remain
    /// contiguous, so fractional row heights don't accumulate drift down the feed.
    @MainActor
    func testDefaultRowsKeepNativeListSpacing() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        defer { app.terminate() }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        let first = app.buttons["fst.notifications.row.fixture-notif-1"]
        let second = app.buttons["fst.notifications.row.fixture-notif-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 15))
        XCTAssertTrue(second.waitForExistence(timeout: 15))
        SongsUITestSupport.waitUntilFrameSettles(first)
        for row in [first, second] {
            XCTAssertEqual(app.buttons.matching(identifier: row.identifier).count, 1)
            XCTAssertTrue(row.isHittable)
            XCTAssertTrue(row.label.hasPrefix("Fixture Pulse · Lead."))
            XCTAssertEqual(row.frame.height, 130 + 2.0 / 3, accuracy: 0.5)
        }
        XCTAssertTrue(first.label.hasSuffix("Rank Up."))
        XCTAssertTrue(second.label.hasSuffix("Full Combo."))
        XCTAssertEqual(second.frame.minY, first.frame.maxY, accuracy: 0.5)

        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "notifications-default-row-spacing"
        capture.lifetime = .keepAlways
        add(capture)
    }

    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    /// Measure the whole folded multi-chart row using a second row beyond the visible edge.
    @MainActor
    func testFoldedMultiChartRowKeepsItsFullExtent() throws {
        guard #available(iOS 27.3, *), let hinge = XCUIDevice.shared.hinge, hinge.angle < 0.05 else {
            throw XCTSkip("Requires the folded Duo cover")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp(profile: "fixture-notify-multi-followed:Notifications Fixture")
        defer { app.terminate() }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        let window = app.windows.firstMatch
        XCTAssertEqual(window.frame.size, CGSize(width: 466, height: 678), "Expected the cover viewport")
        let full = app.buttons["fst.notifications.row.fixture-notify-multi-1"]
        let next = app.buttons["fst.notifications.row.fixture-notify-multi-tail"]
        XCTAssertTrue(full.waitForExistence(timeout: 15))
        SongsUITestSupport.waitUntilFrameSettles(full)
        XCTAssertFalse(next.isHittable, "The following row should begin below the display")
        let restingTop = full.frame.minY
        let fullLabel = full.label
        XCTAssertEqual(fullLabel.components(separatedBy: "\n\n").count, 4)
        func capture(_ step: String) -> [(text: String, frame: CGRect)] {
            let shot = app.screenshot()
            let attachment = XCTAttachment(screenshot: shot)
            attachment.name = "notifications-cover-multi-\(step)"
            attachment.lifetime = .keepAlways
            add(attachment)
            return RecognizedText.lines(in: shot)
        }
        func landmark(_ lines: [(text: String, frame: CGRect)]) throws -> CGFloat {
            try XCTUnwrap(lines.first { RecognizedText.showsWhole("For Drums, your first play scored", in: $0.text) }).frame.midY
        }
        let before = try landmark(capture("top"))
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.49, dy: 0.82))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)),
                    withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(next.waitForExistence(timeout: FestivalApp.budget(10)))
        SongsUITestSupport.waitUntilFrameSettles(next)
        XCTAssertTrue(next.isHittable)
        XCTAssertTrue(next.label.hasSuffix("Full Combo."))
        XCTAssertEqual(app.buttons.matching(identifier: full.identifier).count, 1)
        XCTAssertEqual(full.label, fullLabel)
        XCTAssertTrue(full.isHittable)
        let after = capture("bottom")
        let end = try landmark(after)
        let lastGold = try XCTUnwrap(after.last { $0.text == "Gold Stars" }).frame
        let nextTop = next.frame.minY
        XCTAssertEqual(after.filter { $0.text == "Gold Stars" }.count, 4)
        XCTAssertLessThan(lastGold.maxY, nextTop, "The fourth chart's flags draw above the following row")
        XCTAssertGreaterThan(before - end, 100, "Use painted content to measure the actual scroll displacement")
        // The first row's reported height can be clipped. Undo the measured scroll on the
        // next row's top, then subtract the first row's original top.
        let height = nextTop + before - end - restingTop
        XCTAssertEqual(height, 654.5, accuracy: 1, "Full row height from the reference cover captures")
    }

    /// A bold instrument name fits the first message line on the real folded cover.
    @MainActor
    func testFoldedRankMessageKeepsInstrumentOnFirstLine() throws {
        guard #available(iOS 27.3, *), let hinge = XCUIDevice.shared.hinge, hinge.angle < 0.05 else {
            throw XCTSkip("Requires the folded Duo cover")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        defer { app.terminate() }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        let row = app.buttons["fst.notifications.row.fixture-notif-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(row.isHittable)
        XCTAssertEqual(row.label, "Fixture Pulse · Lead. You climbed from #9 to #4 on Lead for Fixture Pulse. Rank Up.")
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        let shot = row.screenshot()
        let lines = RecognizedText.lines(in: shot).map(\.text)
        let capture = XCTAttachment(screenshot: shot)
        capture.name = "notifications-cover-rank-message"
        capture.lifetime = .keepAlways
        add(capture)
        XCTAssertTrue(lines.contains { RecognizedText.showsWhole("You climbed from #9 to #4 on Lead", in: $0) }, "\(lines)")
        XCTAssertTrue(lines.contains { RecognizedText.showsWhole("for Fixture Pulse.", in: $0) }, "\(lines)")
    }

    /// The AX5 rank message keeps the reference's visible line pitch on the Duo cover.
    @MainActor
    func testFoldedRankMessageKeepsAX5LinePitch() throws {
        guard #available(iOS 27.3, *), let hinge = XCUIDevice.shared.hinge, hinge.angle < 0.05 else {
            throw XCTSkip("Requires the folded Duo cover")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        defer { app.terminate() }
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        let row = app.buttons["fst.notifications.row.fixture-notif-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons.matching(identifier: row.identifier).count, 1)
        XCTAssertTrue(row.label.hasSuffix("You climbed from #9 to #4 on Lead for Fixture Pulse. Rank Up."))
        SongsUITestSupport.waitUntilFrameSettles(row)
        let shot = XCUIScreen.main.screenshot()
        let capture = XCTAttachment(screenshot: shot)
        capture.name = "notifications-cover-ax5-rank-message"
        capture.lifetime = .keepAlways
        add(capture)
        let lines = RecognizedText.lines(in: shot)
        let first = try XCTUnwrap(lines.first { $0.text == "You" })
        let last = try XCTUnwrap(lines.first { RecognizedText.showsWhole("for Fixture", in: $0.text) })
        let between = lines.filter { first.frame.minY < $0.frame.minY && $0.frame.minY < last.frame.minY }
        XCTAssertEqual(between.count, 3)
        XCTAssertEqual((last.frame.minY - first.frame.minY) / 4, 58, accuracy: 1.5)
    }
    #endif

    /// The visible Rank Up chip has a 2 pt inside outline and the row's button names the flag.
    @MainActor
    func testRankChipOutlineAndSpokenLabel() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp()
        defer { app.terminate() }
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        app.launch()
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        let row = app.buttons["fst.notifications.row.fixture-notif-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(row.isHittable)
        XCTAssertEqual(app.buttons.matching(identifier: row.identifier).count, 1)
        XCTAssertTrue(row.label.hasSuffix("Rank Up."))
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)

        let shot = row.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "notifications-rank-chip"
        attachment.lifetime = .keepAlways
        add(attachment)
        let chipLabel = try XCTUnwrap(RecognizedText.lines(in: shot).first {
            RecognizedText.showsWhole("Rank Up", in: $0.text)
        })
        let image = shot.image
        let bitmap = try XCTUnwrap(ButtonFillPixels(image: try XCTUnwrap(image.cgImage), pointWidth: image.size.width))
        let x = Int(chipLabel.frame.midX * bitmap.scale)
        let labelTop = Int(chipLabel.frame.minY * bitmap.scale)
        let pixelsPerPoint = CGFloat(bitmap.height) / row.frame.height
        XCTAssertTrue(0..<bitmap.width ~= x && 0..<bitmap.height ~= labelTop)
        let aboveLabel = max(0, labelTop - Int(10 * pixelsPerPoint))..<labelTop
        let outlinePixels = aboveLabel.count { y in
            let i = (y * bitmap.width + x) * 4
            let (r, g, b) = (bitmap.pixels[i], bitmap.pixels[i + 1], bitmap.pixels[i + 2])
            return (60...80).contains(r) && (100...120).contains(g) && b >= 215
        }
        XCTAssertEqual(CGFloat(outlinePixels) / pixelsPerPoint, 2, accuracy: 0.4)
    }

    /// Generated-empty and never-generated feeds carry different readable explanations.
    @MainActor
    func testEmptyNotificationsExplainWhetherDetectionRan() {
        continueAfterFailure = false
        let cases = [
            ("fixture-notify-empty-generated", "when new high scores are set"),
            ("fixture-empty", "after the next leaderboard update"),
        ]
        for (account, phrase) in cases {
            let app = fixtureApp(profile: "\(account):Notifications Fixture")
            app.launch()
            ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
            let explanation = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", phrase)).firstMatch
            XCTAssertTrue(explanation.waitForExistence(timeout: 15))
            let empty = app.descendants(matching: .any)["fst.notifications.empty"].firstMatch
            let title = empty.staticTexts["No notifications available"]
            XCTAssertTrue(title.exists)
            XCTAssertTrue(explanation.isHittable)
            XCTAssertLessThan(title.frame.maxY, explanation.frame.minY)
            let close = app.buttons["fst.notifications.close"]
            XCTAssertTrue(close.isHittable)
            XCTAssertFalse(app.buttons["fst.service-status.retry"].exists)
            let header = app.navigationBars["Notifications"].frame
            let window = app.windows.firstMatch.frame
            let rawBodyCenter = (header.maxY + window.maxY) / 2
            XCTAssertGreaterThanOrEqual(empty.frame.minY, header.maxY)
            XCTAssertLessThanOrEqual(empty.frame.maxY, window.maxY)
            XCTAssertEqual(empty.frame.midY, rawBodyCenter, accuracy: 24,
                           "Center below the header, allowing for the bottom safe-area inset")
            if close.frame.minY >= header.maxY {
                if close.frame.midX > window.midX {
                    XCTAssertLessThanOrEqual(empty.frame.maxX, close.frame.minX, "Empty state clears the trailing rail")
                } else {
                    XCTAssertGreaterThanOrEqual(empty.frame.minX, close.frame.maxX, "Empty state clears the leading rail")
                }
            }
            app.terminate()
        }
    }

    /// A Total Score rank notification opens Lead rankings on the original tab.
    @MainActor
    func testRankNotificationOpensFullRankings() {
        continueAfterFailure = false
        let app = fixtureApp(profile: "fixture-notify-rankings:Notifications Fixture")
        app.launch()
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        let row = app.buttons["fst.notifications.row.fixture-notify-rankings-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        XCTAssertTrue(row.label.contains("Total Score Rank"), row.label)
        XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        row.tap()
        XCTAssertTrue(app.buttons["fst.notifications.close"].waitForNonExistence(timeout: 10))
        let rankedCount = app.descendants(matching: .any)["fst.full-rankings.ranked-count"].firstMatch
        XCTAssertTrue(rankedCount.waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] %@", "Lead")).firstMatch.exists)
        let back = app.buttons["BackButton"].exists ? app.buttons["BackButton"] : app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.isHittable)
        back.tap()
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: 15))
    }

    /// A held feed shows the spinner, a failed read exposes Retry, and a held retry
    /// shows the spinner again before displaying the recovered row.
    @MainActor
    func testRetryNotificationsRestartsTheLoad() async throws {
        continueAfterFailure = false
        try await setNotificationFixturePhase("hold")
        let app = fixtureApp(profile: "fixture-notify-retry:Notifications Fixture")
        app.launch()
        ShellUITestSupport.tapToolbarItem("fst.shell.notifications", overflowLabels: ["Notifications"], in: app)
        let loading = app.descendants(matching: .any)["Loading Notifications"].firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 10))
        try await setNotificationFixturePhase("fail")
        let retry = app.buttons["fst.service-status.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 10))
        XCTAssertTrue(retry.isHittable)
        XCTAssertGreaterThanOrEqual(retry.frame.height, 44)
        XCTAssertFalse(app.descendants(matching: .any)["fst.notifications.empty"].exists)
        try await setNotificationFixturePhase("hold")
        retry.tap()
        XCTAssertTrue(loading.waitForExistence(timeout: 10))
        try await setNotificationFixturePhase("recover")
        let row = app.buttons["fst.notifications.row.fixture-notify-retry-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        XCTAssertTrue(row.isHittable)
        XCTAssertFalse(retry.exists)
    }

    /// Control the exact loopback fixture used by this journey, not the app's public origin.
    @MainActor
    private func setNotificationFixturePhase(_ phase: String) async throws {
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:8765/__fixture__/notification-retry?phase=\(phase)"))
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: data)["phase"], phase)
    }
}
