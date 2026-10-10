import XCTest

/// First-run carousel journeys (operator batch 6 item 6.7, batch 7; Apple's onboarding layout
/// since issue #25): Next/Done at the bottom with Skip beneath it while pages remain, Back in
/// the navigation bar only after the first page (never disabled), 44 pt hit regions,
/// dismissal by swiping down or tapping outside, and "only pages actually seen count" across
/// a relaunch.
///
/// Hosted (macOS) snapshot coverage for individual carousel states lives in
/// `FirstRunHostedTests.swift`; the viewed-page bookkeeping is unit-tested in
/// `FestivalCoreTests/SettingsBatch6Tests.swift` (`FirstRunViewing`). Needs
/// `tools/mock_service.py --port 8765`.
final class FirstRunJourneyTests: XCTestCase {
    /// A Songs row, found by identifier regardless of accessibility role.
    ///
    /// - Parameters:
    ///   - app: The running application.
    ///   - songId: Fixture song id.
    /// - Returns: The row element, whatever its role.
    @MainActor
    private func songsRow(_ app: XCUIApplication, _ songId: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "fst.songs.row.\(songId)").firstMatch
    }

    /// The fixture app with the given first-run mode.
    ///
    /// - Parameter mode: `force` (every gate-passing slide, every launch) or `on` (real
    ///   seen-state).
    /// - Returns: An unlaunched app.
    @MainActor
    private func fixtureApp(mode: String = "force") -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": mode,
        ])
    }

    /// The carousel slide whose combined label starts with `title`.
    @MainActor
    private func slide(_ app: XCUIApplication, titled title: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "\(title). ")).firstMatch
    }

    /// Wait until the carousel has closed and Songs is interactive again.
    @MainActor
    private func assertCarouselClosed(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: app.buttons["fst.first-run.close"]
        )
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed, file: file, line: line)
        XCTAssertTrue(songsRow(app, "fixture-pulse").waitForExistence(timeout: 15), file: file, line: line)
    }

    /// The page dots' "n of m" value.
    @MainActor
    private func pageValue(_ app: XCUIApplication) -> String {
        app.descendants(matching: .any).matching(identifier: "fst.first-run.dots").firstMatch.value as? String ?? ""
    }

    /// Wait until the page dots read `value`.
    @MainActor
    private func waitForPage(
        _ app: XCUIApplication, _ value: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        let dots = app.descendants(matching: .any).matching(identifier: "fst.first-run.dots").firstMatch
        let shown = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: dots)
        XCTAssertEqual(XCTWaiter.wait(for: [shown], timeout: 5), .completed,
                       "Expected page \(value), saw \(pageValue(app))", file: file, line: line)
    }

    /// Issue #25 (Apple's onboarding layout): the first page offers Next with Skip beneath it
    /// and no Back; from page two Back sits at the leading edge of the guide's navigation
    /// bar, before the title and Close, and returns to the first page; Skip closes the guide.
    @MainActor
    func testNextFirstThenBackAppears() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        let skip = app.buttons["fst.first-run.skip"]
        XCTAssertTrue(skip.exists, "Skip while pages remain")
        XCTAssertGreaterThan(skip.frame.minY, next.frame.maxY - 1, "Skip sits beneath Next")
        XCTAssertFalse(app.buttons["fst.first-run.back"].exists, "No Back on the first page")
        XCTAssertTrue(app.otherElements["fst.first-run.dots"].exists || app.descendants(matching: .any)
            .matching(identifier: "fst.first-run.dots").firstMatch.exists)
        SongsUITestSupport.record(app, name: "first-run-first-page")
        let nextFrame = next.frame

        next.tap()
        let back = app.navigationBars.buttons["fst.first-run.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Back lives in the guide's navigation bar")
        XCTAssertTrue(back.isHittable)
        XCTAssertEqual(back.label, "Back")
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertLessThan(back.frame.maxX, close.frame.minX, "Back leads, Close trails")
        let bar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        let title = bar.staticTexts["Songs"]
        XCTAssertTrue(title.exists)
        XCTAssertLessThan(back.frame.maxX, title.frame.minX, "Back comes before the title")
        XCTAssertEqual(app.buttons["fst.first-run.next"].frame.minY, nextFrame.minY, accuracy: 1,
                       "Next stays in place when Back appears")
        SongsUITestSupport.record(app, name: "first-run-second-page")
        back.tap()
        let backGone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: back
        )
        XCTAssertEqual(XCTWaiter.wait(for: [backGone], timeout: 10), .completed)
        app.buttons["fst.first-run.skip"].tap()
        assertCarouselClosed(app)
    }

    /// Issue #25: on the last page Done replaces Next in the same place and Skip goes away
    /// (its row keeps its space); Done closes the guide.
    @MainActor
    func testLastPageShowsDoneInPlaceOfNext() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        let nextFrame = next.frame
        while app.buttons["fst.first-run.next"].exists {
            app.buttons["fst.first-run.next"].tap()
            _ = app.buttons["fst.first-run.done"].waitForExistence(timeout: 1)
        }
        let done = app.buttons["fst.first-run.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertEqual(done.frame.minY, nextFrame.minY, accuracy: 1, "Done takes Next's place")
        XCTAssertFalse(app.buttons["fst.first-run.skip"].exists, "No Skip on the last page")
        XCTAssertTrue(app.navigationBars.buttons["fst.first-run.back"].exists, "Back on the last page")
        SongsUITestSupport.record(app, name: "first-run-last-page")
        done.tap()
        assertCarouselClosed(app)
    }

    /// Issue #25: every control answers taps within a 44 × 44 pt square centred on it (HIG
    /// Buttons: "the hit region is at least 44x44 pt") and VoiceOver reads it as a button
    /// with its name. Next/Back are probed by the page they reach, Skip/Close by closing the
    /// guide (reopened from Settings between probes).
    @MainActor
    func testControlsAcceptNearMissesAndReadAsButtons() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let next = app.buttons["fst.first-run.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 15))
        XCTAssertEqual(next.label, "Next")
        XCTAssertGreaterThanOrEqual(next.frame.height, 44, "Next \(next.frame)")
        let skip = app.buttons["fst.first-run.skip"]
        XCTAssertEqual(skip.label, "Skip")
        XCTAssertGreaterThanOrEqual(skip.frame.height, 44, "Skip \(skip.frame)")
        XCTAssertGreaterThanOrEqual(skip.frame.width, 44, "Skip \(skip.frame)")
        XCTAssertEqual(app.navigationBars.buttons["fst.first-run.close"].label, "Close")

        let origin = app.coordinate(withNormalizedOffset: .zero)
        func tapNear(_ element: XCUIElement, _ offset: CGVector) {
            let frame = element.frame
            origin.withOffset(CGVector(dx: frame.midX + offset.dx, dy: frame.midY + offset.dy)).tap()
        }
        waitForPage(app, "1 of 6")
        for offset in Self.nearMisses {
            tapNear(app.buttons["fst.first-run.next"], offset)
            waitForPage(app, "2 of 6")
            let back = app.navigationBars.buttons["fst.first-run.back"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertEqual(back.label, "Back")
            tapNear(back, offset)
            waitForPage(app, "1 of 6")
        }

        // Skip and Close: each probe closes the guide; Settings reopens it.
        let probes: [(String, CGVector)] = Self.nearMisses.map { ("fst.first-run.skip", $0) }
            + Self.nearMisses.map { ("fst.first-run.close", $0) }
        for (index, probe) in probes.enumerated() {
            if index > 0 { reopenSongsGuide(app) }
            let control = app.buttons[probe.0]
            XCTAssertTrue(control.waitForExistence(timeout: 10), probe.0)
            tapNear(control, probe.1)
            let gone = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"), object: app.buttons["fst.first-run.close"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed,
                           "\(probe.0) ignored a tap at (\(Int(probe.1.dx)), \(Int(probe.1.dy))) pt from its centre")
        }
    }

    /// Offsets from a control's centre, all inside a 44 × 44 pt square (as in
    /// `NavButtonHitRegionJourneyTests`).
    private static let nearMisses: [CGVector] = [
        CGVector(dx: -20, dy: 0), CGVector(dx: 20, dy: 0),
        CGVector(dx: 0, dy: -20), CGVector(dx: 0, dy: 20),
        CGVector(dx: -15, dy: -15), CGVector(dx: 15, dy: 15),
    ]

    /// Open the Songs guide again from Settings → First Run Guides.
    @MainActor
    private func reopenSongsGuide(_ app: XCUIApplication) {
        let replay = app.buttons["fst.settings.first-run.songs"]
        if !replay.exists {
            SongsUITestSupport.rootControl("Settings", app: app).tap()
        }
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        replay.tap()
    }

    /// Issue #25: slides that show a real sheet (Sort Songs, Filter Songs) draw its header
    /// inside the demo. The guide's bar keeps its own title and its single Close on every
    /// page, and VoiceOver finds no second Close.
    @MainActor
    func testEmbeddedSheetDemosKeepOneCloseAndTheGuideTitle() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        XCTAssertTrue(app.buttons["fst.first-run.next"].waitForExistence(timeout: 15))
        var page = 1
        while true {
            let bar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
            XCTAssertTrue(bar.staticTexts["Songs"].exists, "Page \(page) keeps the guide title")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Close'")).count, 1,
                           "Page \(page) has exactly one Close")
            XCTAssertFalse(app.buttons["fst.songs.sort.done"].exists, "Page \(page): no Sort sheet Close")
            XCTAssertFalse(app.buttons["fst.songs.filter.done"].exists, "Page \(page): no Filter sheet Close")
            if page == 2 { SongsUITestSupport.record(app, name: "first-run-sort-demo") }
            let next = app.buttons["fst.first-run.next"]
            guard next.exists else { break }
            next.tap()
            page += 1
            waitForPage(app, "\(page) of 6")
        }
        XCTAssertEqual(page, 6)
        app.buttons["fst.first-run.done"].tap()
        assertCarouselClosed(app)
    }

    /// Issue #4: the carousel carries the same native toolbar "Close" as the Profile search
    /// sheet (a navigation-bar button labelled "Close", not a small ✕ glyph), and tapping
    /// it closes the guide.
    @MainActor
    func testCloseIsNativeToolbarButton() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15), "Close lives in the sheet's navigation bar")
        XCTAssertEqual(close.label, "Close")
        XCTAssertTrue(close.isHittable)
        SongsUITestSupport.record(app, name: "first-run-native-close")
        close.tap()
        assertCarouselClosed(app)
    }

    /// Issue #24: like the app's other modals, each guide names its page in an inline
    /// navigation title beside Close: the launch Songs guide and a Settings replay alike.
    @MainActor
    func testGuideShowsPageTitleInNavigationBar() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let sheetBar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        XCTAssertTrue(sheetBar.staticTexts["Songs"].exists, "The Songs guide is titled Songs")
        close.tap()
        assertCarouselClosed(app)

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let replay = app.buttons["fst.settings.first-run.playerhistory"]
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        replay.tap()
        let replayClose = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(replayClose.waitForExistence(timeout: 10))
        let replayBar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        let title = replayBar.staticTexts["Score History"]
        XCTAssertTrue(title.exists, "A Settings replay is titled with its page")
        XCTAssertTrue(replayClose.isHittable, "The title leaves Close reachable")
        XCTAssertFalse(title.frame.intersects(replayClose.frame), "The title does not overlap Close")
        XCTAssertTrue(app.buttons["fst.first-run.next"].isHittable)
        SongsUITestSupport.record(app, name: "first-run-replay-title")
        replayClose.tap()
    }

    /// Swiping the carousel down dismisses it, like any sheet.
    @MainActor
    func testSwipeDownDismissesCarousel() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        let window = app.windows.firstMatch
        // Start on the sheet's top edge (grabber / close row), not on the dimmed page.
        let top = close.frame.midY
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: top))
            .press(
                forDuration: 0.05,
                thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98))
            )
        assertCarouselClosed(app)
    }

    /// Tapping the dimmed page above the carousel dismisses it (the web's overlay click).
    @MainActor
    func testTapOutsideDismissesCarousel() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let close = app.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "first-run-outside-area")
        // Below the status bar (a status-bar tap is the system's scroll-to-top) and above the
        // sheet's top edge.
        let window = app.windows.firstMatch
        let sheetTop = close.frame.minY - 40
        let y = min(130, sheetTop - 10)
        window.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.frame.midX, dy: y)).tap()
        assertCarouselClosed(app)
    }

    /// Only viewed pages count as seen: a Settings replay closed after two pages leaves the
    /// rest unseen, so the next launch's Songs guide starts at the third slide.
    @MainActor
    func testOnlyViewedPagesAreMarkedSeen() throws {
        continueAfterFailure = false
        let app = fixtureApp(mode: "on")
        app.launch()
        // A previous run may have left Songs slides unseen; close whatever shows.
        let close = app.buttons["fst.first-run.close"]
        if close.waitForExistence(timeout: 6) { close.tap() }
        XCTAssertTrue(songsRow(app, "fixture-pulse").waitForExistence(timeout: 15))

        SongsUITestSupport.rootControl("Settings", app: app).tap()
        let replay = app.buttons["fst.settings.first-run.songs"]
        SongsUITestSupport.reveal(replay, in: app, scrollingUp: true)
        replay.tap()
        XCTAssertTrue(slide(app, titled: "Song List").waitForExistence(timeout: 10))
        app.buttons["fst.first-run.next"].tap()
        XCTAssertTrue(slide(app, titled: "Sort Songs").waitForExistence(timeout: 10))
        app.buttons["fst.first-run.close"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: close)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed)
        app.terminate()

        let relaunched = fixtureApp(mode: "on")
        relaunched.launch()
        let navigation = slide(relaunched, titled: "Navigation")
        XCTAssertTrue(navigation.waitForExistence(timeout: 15), "Unviewed pages must show next time")
        XCTAssertTrue(navigation.isHittable, "The guide resumes at the first unviewed page")
        XCTAssertFalse(slide(relaunched, titled: "Song List").isHittable, "Viewed pages stay seen")
        SongsUITestSupport.record(relaunched, name: "first-run-resumes-unseen")
        relaunched.buttons["fst.first-run.close"].tap()
    }

    // MARK: - Guide title (issue #24, accessibility backfill #429)

    /// Issue #24 gave each guide an inline navigation title naming its page, and left
    /// VoiceOver's first focus to the system so that title is read first. At the largest
    /// accessibility text size (AX5), on the launch Songs guide and the Leaderboards guide
    /// (the longest tab-root title): the title is a heading named exactly by its page, it sits
    /// wholly on screen in the guide's own navigation bar between the leading edge and Close,
    /// it reads before Close and before the slide (visual and element order), Close keeps its
    /// name, button role and a hittable target, and the audit finds no clipped text,
    /// small hit region or unnamed element in that bar. The title is navigation-bar chrome a
    /// macOS-hosted view cannot reproduce, so this journey is the evidence (`FirstRunGuideTitleTests`
    /// unit-tests every page's title; `FirstRunDemoSongsAccessibilityTests` the content order).
    /// HIG VoiceOver: "Use titles and headings to convey hierarchy"; HIG Accessibility: 44×44 pt
    /// default control size.
    @MainActor
    func testGuideTitleIsReadFirstAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        for (tab, title, firstSlide) in [
            ("songs", "Songs", "Song List"), ("leaderboards", "Leaderboards", "Global Rankings"),
        ] {
            let app = FestivalApp.makeApp([
                "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIRST_RUN_FIXTURE_URL"]
                    ?? "http://127.0.0.1:8765",
                "FST_UI_TEST_CLEAR_PROFILE": "1",
                "FST_DEBUG_FIRST_RUN": "force",
                "FST_DEBUG_TAB": tab,
            ])
            app.launchArguments += [
                "-UIPreferredContentSizeCategoryName",
                UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
            ]
            app.launch()
            try assertGuideTitle(app, title: title, firstSlide: firstSlide)
            app.terminate()
        }
    }

    /// The AX5 title rules of ``testGuideTitleIsReadFirstAtLargestText()`` on one open guide.
    ///
    /// - Parameters:
    ///   - app: The launched app showing a guide.
    ///   - title: The page title the guide must carry.
    ///   - firstSlide: Title of the guide's first slide.
    /// - Throws: An unreadable snapshot or a failed audit run.
    @MainActor
    private func assertGuideTitle(_ app: XCUIApplication, title: String, firstSlide: String) throws {
        let close = app.navigationBars.buttons["fst.first-run.close"]
        XCTAssertTrue(close.waitForExistence(timeout: FestivalApp.budget(20)), "\(title) guide opens")
        // Next, or Done for a one-slide guide (Leaderboards without a player).
        let next = app.buttons.matching(
            NSPredicate(format: "identifier IN %@", ["fst.first-run.next", "fst.first-run.done"])
        ).firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: FestivalApp.budget(10)), "\(title) guide shows Next or Done")
        let bar = app.navigationBars.containing(.button, identifier: "fst.first-run.close").firstMatch
        let heading = bar.staticTexts[title]
        XCTAssertTrue(heading.waitForExistence(timeout: FestivalApp.budget(5)), "\(title) guide is titled \(title)")
        let slide = slide(app, titled: firstSlide)
        XCTAssertTrue(slide.waitForExistence(timeout: FestivalApp.budget(10)), "\(firstSlide) slide")
        Thread.sleep(forTimeInterval: FestivalApp.budget(1))
        SongsUITestSupport.record(app, name: "first-run-title-\(title.lowercased())-ax5")

        // Name and role: the bar's only text is the page name, read as a heading.
        let snapshot = try bar.snapshot()
        var nodes: [XCUIElementSnapshot] = []
        func collect(_ node: XCUIElementSnapshot) {
            nodes.append(node)
            node.children.forEach(collect)
        }
        collect(snapshot)
        let texts = nodes.filter { $0.elementType == .staticText }
        XCTAssertEqual(texts.map(\.label), [title], "the guide's bar reads only its title")
        if let text = texts.first, let traits = Self.traits(text) {
            XCTAssertNotEqual(traits & UIAccessibilityTraits.header.rawValue, 0, "'\(title)' is a heading")
        }

        // Reading order: the title, then Close, then the slide below the bar.
        let readable = nodes.filter { $0.elementType == .staticText || $0.elementType == .button }
            .map { $0.identifier.isEmpty ? $0.label : $0.identifier }
        XCTAssertEqual(readable, [title, "fst.first-run.close"], "bar reads title then Close")
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(window.contains(heading.frame), "'\(title)' wholly on screen: \(heading.frame)")
        XCTAssertLessThanOrEqual(heading.frame.maxX, close.frame.minX, "'\(title)' ends before Close")
        XCTAssertFalse(heading.frame.intersects(close.frame), "'\(title)' does not overlap Close")
        XCTAssertLessThanOrEqual(heading.frame.maxY, slide.frame.minY + 0.5,
                                 "'\(title)' \(heading.frame) above the slide \(slide.frame)")
        XCTAssertLessThan(heading.frame.maxY, next.frame.minY, "'\(title)' above \(next.label)")

        // Close: a named, hittable button beside the enlarged title. Its frame reads about
        // 35 pt but the system expands its hit region (near-miss taps:
        // `testControlsAcceptNearMissesAndReadAsButtons`); the audit's hit-region check
        // below covers it at AX5.
        XCTAssertEqual(close.label, "Close")
        XCTAssertEqual(close.elementType, .button)
        XCTAssertTrue(close.isHittable, "Close is reachable at AX5")

        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.textClipped, .hitRegion, .sufficientElementDescription, .elementDetection],
            name: "\(title) guide bar", reset: { issues = [] }
        ) { issue in
            guard let element = issue.element else { return true }
            let frame = element.frame
            guard element.identifier == "fst.first-run.close" || element.label == title
                || frame.intersects(bar.frame) else { return true }
            issues.append("\(issue.compactDescription): #\(element.identifier) '\(element.label)' \(frame)")
            return true
        }
        XCTAssertEqual(issues, [], "Open audit issues in the \(title) guide's bar")
    }

    /// The snapshot's accessibility traits, when readable (as `WhatsNewAccessibilityJourneyTests`).
    @MainActor
    private static func traits(_ snapshot: XCUIElementSnapshot) -> UInt64? {
        let object = snapshot as AnyObject
        guard object.responds(to: NSSelectorFromString("traits")) else { return nil }
        return (object.value(forKey: "traits") as? NSNumber)?.uint64Value
    }

    // MARK: - Song demos (issue #26, accessibility backfill #401)

    /// Issue #26: the Songs list demo shows real catalogue songs (redacted placeholders while
    /// they load), as a decorative picture. At the largest accessibility text size (AX5) the
    /// slide is still one element named by its title and description only: no placeholder,
    /// song title or song row from the demo is reachable, the slide reads above the page dots,
    /// Next and Skip, both actions keep 44 pt targets on screen, and the system audit finds no
    /// clipped text, small hit regions or unnamed elements in the guide. HIG VoiceOver:
    /// "Exclude purely decorative images that convey no useful or actionable information".
    /// Hosted counterpart: `FirstRunDemoSongsAccessibilityTests` (every song demo, both states).
    @MainActor
    func testSongDemoSlideAccessibleAtLargestText() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIRST_RUN_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_FIRST_RUN": "force",
        ])
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue,
        ]
        app.launch()
        let title = "Song List"
        let description = "Browse and search the entire Festival library. Tap a song to see leaderboards and more details."
        let slide = slide(app, titled: title)
        XCTAssertTrue(slide.waitForExistence(timeout: FestivalApp.budget(20)), "Song List slide")
        // The catalogue answers within a moment on the loopback fixture; then the demo's rows
        // are real songs.
        let songRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'fst.songs.row.'")).firstMatch
        _ = songRow.waitForExistence(timeout: FestivalApp.budget(5))
        Thread.sleep(forTimeInterval: FestivalApp.budget(2))
        XCTAssertEqual(slide.label, "\(title). \(description)", "The slide reads its title and description only")
        SongsUITestSupport.record(app, name: "first-run-song-demo-ax5")

        // Nothing the guide exposes is a demo song or a placeholder.
        let window = app.windows.firstMatch.frame
        var reachable: [XCUIElementSnapshot] = []
        func collect(_ node: XCUIElementSnapshot) {
            reachable.append(node)
            node.children.forEach(collect)
        }
        collect(try app.snapshot())
        let sheetTop = slide.frame.minY
        let leaks = reachable.filter { node in
            node.label.localizedCaseInsensitiveContains("placeholder")
                || (node.identifier.hasPrefix("fst.songs.row.") && node.frame.minY >= sheetTop - 1
                    && window.intersects(node.frame))
        }.map { "\($0.elementType.rawValue) '\($0.label)' #\($0.identifier) \($0.frame)" }
        XCTAssertEqual(leaks, [], "Demo songs or placeholders reachable:\n\(app.debugDescription)")

        // Reading order follows the layout: slide, page dots, Next, Skip.
        let dots = app.descendants(matching: .any).matching(identifier: "fst.first-run.dots").firstMatch
        let next = app.buttons["fst.first-run.next"]
        let skip = app.buttons["fst.first-run.skip"]
        XCTAssertTrue(dots.exists && next.exists && skip.exists)
        XCTAssertEqual(dots.label, "Page")
        XCTAssertEqual(dots.value as? String, "1 of 6")
        XCTAssertLessThanOrEqual(slide.frame.minY, dots.frame.minY, "slide \(slide.frame) above dots \(dots.frame)")
        XCTAssertLessThan(dots.frame.minY, next.frame.minY, "dots above Next")
        XCTAssertLessThan(next.frame.minY, skip.frame.minY, "Next above Skip")

        // Targets: 44 pt and on screen at AX5 (the sheet draws about 0.96× scaled).
        for control in [next, skip] {
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 * 0.96, "\(control.identifier) \(control.frame)")
            XCTAssertTrue(window.contains(control.frame), "\(control.identifier) on screen: \(control.frame)")
            XCTAssertTrue(control.isHittable, control.identifier)
        }

        var issues: [String] = []
        try app.performAccessibilityAudit(for: [.textClipped, .hitRegion, .sufficientElementDescription, .elementDetection]) { issue in
            let element = issue.element
            issues.append("\(issue.compactDescription): #\(element?.identifier ?? "") '\(element?.label ?? "")' \(element?.frame ?? .zero)")
            return true
        }
        XCTAssertEqual(issues, [], "Open audit issues")
    }
}
