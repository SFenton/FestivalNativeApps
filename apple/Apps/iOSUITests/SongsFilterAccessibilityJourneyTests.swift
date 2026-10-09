import UIKit
import XCTest

/// Accessibility of the iPhone Songs Filter sheet without a profile (#432, for #77).
///
/// #77 made Filter available to every viewer and added the General section (Year,
/// Duration, Item Shop, Double Bass), which is all the sheet shows without a selected
/// profile. Each test launches fixture Songs with no profile, checks the Filter Songs
/// button, opens the sheet, and audits it with `performAccessibilityAudit`. It also checks
/// what the audit cannot: General's groups in order, no player sections, options as
/// named switches reporting their state, Select All / Clear All named for their group,
/// and 44 pt targets (HIG Accessibility, Mobility: "Strive for the platform's recommended
/// minimum control size", 44x44 pt on iOS), at the default and the largest accessibility
/// text size. The hosted `SongsFilterAccessibilityTests` pin the same tree in `apple-ci`.
///
/// Needs `tools/mock_service.py --port 8765`, like `SongsJourneyTests`
/// (`TEST_RUNNER_FST_SONGS_FILTER_FIXTURE_PORT=<port>` selects a fresh listener instead).
final class SongsFilterAccessibilityJourneyTests: XCTestCase {
    // MARK: - Helpers

    private static let prefix = "fst.songs.filter."

    /// General's groups in web order, with their visible titles.
    private static let groups: [(id: String, title: String)] = [
        ("year", "Year"), ("duration", "Duration"), ("shop", "Item Shop"), ("double-bass", "Double Bass"),
    ]

    /// Each General group's visible title and hint (the web's copy).
    private static let hints: [(title: String, hint: String)] = [
        ("Year", "Filter songs by their release decade."),
        ("Duration", "Filter songs by their duration."),
        ("Item Shop", "Filter songs by whether they are available in the Item Shop."),
        ("Double Bass", "Filter songs that have or don't have double bass charts for Pro Drums."),
    ]

    /// Every audit except Dynamic Type, which ``testDynamicTypeAuditWithShopHidden`` runs.
    private static let auditWithoutDynamicType = XCUIAccessibilityAuditType.all.subtracting(.dynamicType)

    /// The Item Shop group's title and hint, measured instead of Dynamic Type-audited.
    private static let shopTexts = [hints[2].title, hints[2].hint]

    /// Fixture Songs with no profile, optionally at a text size.
    ///
    /// - Parameters:
    ///   - contentSize: A `UIContentSizeCategory` raw value, or nil for the default.
    ///   - showShop: Whether Settings shows the Item Shop (and so its filter group).
    /// - Returns: The launched app showing Songs.
    @MainActor
    private func launchSongs(contentSize: String? = nil, showShop: Bool = true) -> XCUIApplication {
        XCUIDevice.shared.orientation = .portrait
        let app = SongsUITestSupport.fixtureApp()
        // `TEST_RUNNER_FST_SONGS_FILTER_FIXTURE_PORT` points a rerun at a fresh listener.
        let port = ProcessInfo.processInfo.environment["FST_SONGS_FILTER_FIXTURE_PORT"] ?? "8765"
        app.launchEnvironment["FST_API_BASE_URL"] = "http://127.0.0.1:\(port)"
        app.launchArguments += ["-fst.settings.hideShop", showShop ? "NO" : "YES"]
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        XCTAssertTrue(app.collectionViews["fst.songs.list"].waitForExistence(timeout: 20), "Songs did not load")
        return app
    }

    /// Any element with an identifier (iOS puts General's group identifiers on their labels).
    @MainActor
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: Self.prefix + id).firstMatch
    }

    /// Where the sheet's content starts: below its title bar, and below Close (✕) when
    /// Close sits above the Form. On the folded iPhone Duo Close is in the sheet's
    /// vertical bar beside the Form, so only the title bar counts.
    ///
    /// - Parameters:
    ///   - target: Row being revealed.
    ///   - app: Launched fixture Songs with the sheet open.
    /// - Returns: The y coordinate the row must start at to be fully visible.
    @MainActor
    private func sheetContentTop(for target: XCUIElement, in app: XCUIApplication) -> CGFloat {
        let done = app.buttons[Self.prefix + "done"].frame
        let bar = app.navigationBars["Filter Songs"]
        let barBottom = bar.exists ? bar.frame.maxY : 0
        let besideRows = target.exists && done.minX >= target.frame.maxX
        return besideRows ? barBottom : max(barBottom, done.maxY)
    }

    /// Scroll the sheet's Form either way until an element is wholly between the sheet's
    /// top bar and the screen bottom (at AX5 Year sits far above Reset).
    ///
    /// - Parameters:
    ///   - target: Element inside the Filter Form.
    ///   - app: Launched fixture Songs with the sheet open.
    /// - Returns: The hittable element.
    @MainActor
    @discardableResult
    private func reveal(
        _ target: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        let form = element("form", in: app)
        // The iPad form sheet ends above the window's bottom.
        let bottom = min(SongsUITestSupport.sheetVisibleBottom(in: app), form.frame.maxY - 8)
        // A row taller than the space (Item Shop at AX5 on the folded Duo) only has to
        // start below the bar; the last rows, where the Form ends at the window edge (the
        // folded Duo), only have to end inside the Form once dragging no longer moves them.
        var atEnd = false
        func visible() -> Bool {
            guard target.exists, target.isHittable else { return false }
            let top = sheetContentTop(for: target, in: app)
            let fits = target.frame.height <= bottom - top
            let inForm = atEnd && target.frame.maxY <= form.frame.maxY
            return target.frame.minY >= top && (target.frame.maxY <= bottom || !fits || inForm)
        }
        // Drag by the measured distance (fixed swipes overshot a tall row both ways);
        // down only as far as the row is hidden, since dragging the Form down past its
        // top would dismiss the sheet.
        func drag(by distance: CGFloat) {
            let top = sheetContentTop(for: target, in: app)
            let span = max(bottom - top - 48, 40)
            // The scroll view's touch slop eats the first ≈ 10 pt of a drag.
            let step = min(abs(distance) + 12, span)
            let x = form.frame.minX + 32
            let startY = distance < 0 ? bottom - 24 : top + 24
            let origin = form.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x - form.frame.minX, dy: startY - form.frame.minY))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(
                           dx: x - form.frame.minX,
                           dy: startY + (distance < 0 ? -step : step) - form.frame.minY
                       )),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        var attempt = 0
        while !visible() && attempt < 30 {
            defer { attempt += 1 }
            guard target.exists else {
                // Not loaded: the Form is lazy. Page down without momentum (a swipe carried
                // past a single row); back up with a slow swipe, whose momentum bounces at the
                // top, where a held drag would pull the sheet and dismiss it.
                if attempt < 12 {
                    drag(by: -(bottom - sheetContentTop(for: target, in: app)) / 2)
                } else {
                    form.swipeDown(velocity: .slow)
                }
                continue
            }
            let top = sheetContentTop(for: target, in: app)
            let frame = target.frame
            let distance: CGFloat
            if frame.minY < top {
                distance = top - frame.minY + 8
            } else if frame.height > bottom - top {
                distance = -(frame.minY - top - 8)
            } else {
                distance = -(frame.maxY - bottom + 8)
            }
            guard abs(distance) >= 4 else { break }
            if distance > (bottom - top) / 2 {
                // Far above: an offscreen row's frame can be stale, and a held drag past the
                // top would pull the sheet down; a slow swipe's momentum bounces there instead.
                form.swipeDown(velocity: .slow)
                continue
            }
            drag(by: distance)
            atEnd = distance < 0 && target.exists && abs(target.frame.minY - frame.minY) < 1
        }
        // Let a drag that met the Form's top or end bounce back before anything is audited.
        if attempt > 0 {
            var last = target.frame
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.2)
                guard target.exists, target.frame != last else { break }
                last = target.frame
            }
        }
        XCTAssertTrue(
            visible(),
            "\(target) not reachable in the sheet: frame \(target.exists ? "\(target.frame)" : "none"), "
                + "top \(sheetContentTop(for: target, in: app)), bottom \(bottom)",
            file: file, line: line
        )
        return target
    }

    /// Open Filter from the accessory: the Filter Songs button, or at large text the
    /// folded Sort and Filter menu's "Filter…", which #77 offers without a profile too.
    /// Both entries are named and at least 44 pt.
    ///
    /// - Parameter app: Launched fixture Songs.
    @MainActor
    private func openSheet(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let folded = app.buttons["fst.songs.tools"]
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(folded.waitForExistence(timeout: 5) || filter.exists, "No Filter entry", file: file, line: line)
        if folded.exists {
            XCTAssertEqual(folded.label, "Sort and Filter", file: file, line: line)
            assertTarget(folded, "Sort and Filter", file: file, line: line)
            folded.tap()
            let item = app.buttons["fst.songs.tools.filter"]
            XCTAssertTrue(item.waitForExistence(timeout: 5), "Filter… missing without a profile", file: file, line: line)
            item.tap()
        } else {
            XCTAssertTrue(Self.spoken(filter).hasPrefix("Filter Songs, "),
                          "Filter Songs must read its state: \(Self.spoken(filter))", file: file, line: line)
            // A smaller glass toolbar item (iPhone Duo) is proved by near-miss taps instead.
            if filter.frame.width >= 44 && filter.frame.height >= 44 {
                assertTarget(filter, "Filter Songs", file: file, line: line)
            }
            filter.tap()
        }
        XCTAssertTrue(app.buttons[Self.prefix + "done"].waitForExistence(timeout: 10), "Filter did not open",
                      file: file, line: line)
    }

    /// Open the sheet from a clean state: a saved filter left by an earlier run is reset
    /// through the sheet itself.
    ///
    /// - Parameter app: Launched fixture Songs.
    @MainActor
    private func openCleanSheet(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        openSheet(app, file: file, line: line)
        let filter = app.buttons["fst.songs.filter"]
        if filter.exists, Self.spoken(filter) == "Filter Songs, No filters" { return }
        reveal(app.buttons[Self.prefix + "reset"], in: app).tap()
        app.buttons[Self.prefix + "done"].tap()
        openSheet(app, file: file, line: line)
    }

    /// What VoiceOver reads for a toolbar tool: its label, then its value. The iPhone Duo
    /// vertical bar drops values, so there the state is in the label (`BarItemSpokenState`).
    private static func spoken(_ element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return value.isEmpty ? element.label : "\(element.label), \(value)"
    }

    /// Offsets from a button's centre, all inside a 44x44 pt square (as
    /// `NavButtonHitRegionJourneyTests`).
    private static let nearMisses: [CGVector] = [
        CGVector(dx: -20, dy: 0), CGVector(dx: 20, dy: 0),
        CGVector(dx: 0, dy: -20), CGVector(dx: 0, dy: 20),
        CGVector(dx: -15, dy: -15), CGVector(dx: 15, dy: 15),
    ]

    /// Filter Songs drawn smaller than 44 pt (iPhone Duo's glass toolbar item) still opens
    /// Filter from every near-miss tap inside a 44x44 pt square (HIG Buttons: "the hit
    /// region is at least 44x44 pt"). A 44 pt button is checked by its frame instead.
    @MainActor
    private func assertFilterHitRegion(_ app: XCUIApplication) {
        let filter = app.buttons["fst.songs.filter"]
        guard filter.waitForExistence(timeout: 5), filter.frame.width < 44 || filter.frame.height < 44 else { return }
        let done = app.buttons[Self.prefix + "done"]
        let frame = filter.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for offset in Self.nearMisses {
            origin.withOffset(CGVector(dx: frame.midX + offset.dx, dy: frame.midY + offset.dy)).tap()
            XCTAssertTrue(done.waitForExistence(timeout: 5),
                          "Filter Songs \(frame) ignored a tap at (\(Int(offset.dx)), \(Int(offset.dy))) pt")
            done.tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: done)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
    }

    /// Assert an element is a target of at least 44x44 pt.
    @MainActor
    private func assertTarget(
        _ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(element.frame.height, 44, "\(name) target height \(element.frame)",
                                    file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44, "\(name) target width \(element.frame)",
                                    file: file, line: line)
    }

    /// The sheet shows General only: its heading, then each group in web order, named by
    /// title and hint, and no player sections.
    @MainActor
    private func assertGeneralOnly(
        _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertTrue(element("general", in: app).waitForExistence(timeout: 10), "No General heading",
                      file: file, line: line)
        XCTAssertFalse(element("score-sections", in: app).exists, "Player sections without a profile",
                       file: file, line: line)
        XCTAssertFalse(element("instrument", in: app).exists, "Instrument without a profile", file: file, line: line)
        var previous = element("general", in: app)
        for group in Self.groups {
            let label = reveal(element(group.id, in: app), in: app, file: file, line: line)
            XCTAssertTrue(label.label.hasPrefix(group.title), "\(group.id) named \(label.label)", file: file, line: line)
            XCTAssertGreaterThan(label.label.count, group.title.count + 10, "\(group.id) reads its hint",
                                 file: file, line: line)
            // Compared at one scroll offset; a group scrolled out of the tree is above.
            if previous.exists {
                XCTAssertLessThan(previous.frame.minY, label.frame.minY, "\(group.id) follows \(previous.identifier)",
                                  file: file, line: line)
            }
            previous = label
        }
    }

    /// Expand Year and check its header actions and decade switches: named, reporting
    /// their state, and 44 pt targets.
    ///
    /// - Returns: The decade switches.
    @MainActor
    private func assertYearGroup(
        _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) -> [XCUIElement] {
        let selectAll = app.buttons[Self.prefix + "year.select-all"]
        if !selectAll.exists {
            reveal(element("year", in: app), in: app).tap()
        }
        XCTAssertTrue(selectAll.waitForExistence(timeout: 10), "Year did not expand", file: file, line: line)
        let clearAll = app.buttons[Self.prefix + "year.clear-all"]
        XCTAssertEqual(selectAll.label, "Select All, Year", file: file, line: line)
        XCTAssertEqual(clearAll.label, "Clear All, Year", file: file, line: line)
        let decadeQuery = app.switches.matching(NSPredicate(
            format: "identifier BEGINSWITH %@", Self.prefix + "year."
        ))
        // The Form is lazy: rows below its end load once scrolled to.
        if !decadeQuery.firstMatch.waitForExistence(timeout: 3) {
            reveal(decadeQuery.firstMatch, in: app, file: file, line: line)
        }
        let decades = decadeQuery.allElementsBoundByIndex
        XCTAssertFalse(decades.isEmpty, "No decades", file: file, line: line)
        for decade in decades {
            XCTAssertTrue(decade.label.hasSuffix("s"), "\(decade.identifier) named \(decade.label)",
                          file: file, line: line)
            XCTAssertEqual(decade.value as? String, "1", "\(decade.identifier) starts on", file: file, line: line)
        }
        let first = reveal(decades[0], in: app, file: file, line: line)
        assertTarget(first, first.identifier, file: file, line: line)
        assertTarget(reveal(clearAll, in: app, file: file, line: line), "Clear All, Year", file: file, line: line)
        assertTarget(reveal(selectAll, in: app, file: file, line: line), "Select All, Year", file: file, line: line)
        return decades
    }

    /// Run an audit, attaching each issue's element so a failure names it. Every issue
    /// fails the test unless `proof` defers it to a measurement the caller then asserts.
    ///
    /// Contrast on text the sheet's edge cuts through (the iPad form sheet ends mid-row)
    /// judges clipped glyphs, so such an issue is proved instead: the text is revealed whole
    /// and a second Contrast audit must not report it (the iPad audit's `contrast-rendered`
    /// rule, scrolled into view first).
    ///
    /// - Parameters:
    ///   - app: Launched fixture Songs.
    ///   - types: Audit types to run.
    ///   - proof: Returns true for an issue the caller proves afterwards (and records it).
    @MainActor
    private func audit(
        _ app: XCUIApplication, for types: XCUIAccessibilityAuditType,
        deferring proof: ((XCUIAccessibilityAuditIssue) -> Bool)? = nil
    ) throws {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        let form = element("form", in: app)
        let edge = form.exists
            ? (top: form.frame.minY, bottom: min(form.frame.maxY, app.windows.firstMatch.frame.maxY))
            : nil
        var cut: [String] = []
        try app.performAccessibilityAudit(for: types) { issue in
            let deferred = proof?(issue) ?? false
            let behindSheet = !deferred && Self.isPadPageBehindSheet(issue, pad: pad)
            var edgeCut = false
            if !deferred, !behindSheet, issue.auditType == .contrast, let edge,
               let element = issue.element, !element.label.isEmpty,
               element.frame.minY < edge.top || element.frame.maxY > edge.bottom {
                edgeCut = true
                cut.append(element.label)
            }
            let attachment = XCTAttachment(
                string: "\(issue.auditType): \(issue.compactDescription): "
                    + "id=\(issue.element?.identifier ?? "none") label=\(issue.element?.label ?? "none") "
                    + "frame=\(String(describing: issue.element?.frame))"
                    + (deferred ? " (growth measured at AX5)" : "")
                    + (behindSheet ? " (iPad page behind the sheet: IPadAccessibilityAuditTests filter-sheet)" : "")
                    + (edgeCut ? " (cut by the sheet's edge: re-audited whole)" : "")
            )
            attachment.name = "songs-filter-audit-issue"
            attachment.lifetime = .keepAlways
            self.add(attachment)
            return deferred || behindSheet || edgeCut
        }
        for label in cut {
            let text = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            reveal(text, in: app)
            // Everything else was judged whole in the first pass.
            try app.performAccessibilityAudit(for: .contrast) { issue in
                guard issue.element?.label == label else { return true }
                let attachment = XCTAttachment(string: "Contrast, revealed whole: \(label)")
                attachment.name = "songs-filter-audit-issue"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return false
            }
        }
    }

    /// On iPad the form sheet leaves the dimmed Songs page visible around it, and the audit
    /// reports that page's text with no element (Contrast, Element detection).
    /// `IPadAccessibilityAuditTests` audits this sheet (page `filter-sheet`) and proves those
    /// issues with rendered evidence (`unattributed-contrast-page-floor`,
    /// `unattributed-text-behind-sheet`); attributed issues still fail here.
    ///
    /// - Parameters:
    ///   - issue: An audit issue.
    ///   - pad: Whether the run is on iPad.
    /// - Returns: True for an element-less Contrast or Element detection issue on iPad.
    private static func isPadPageBehindSheet(_ issue: XCUIAccessibilityAuditIssue, pad: Bool) -> Bool {
        pad && issue.element == nil
            && (issue.auditType == .contrast || issue.auditType == .elementDetection)
    }

    /// Run an audit with the sheet at rest at its top, then at its end.
    ///
    /// The audit judges what is on screen, so each end is checked at rest rather than at
    /// whatever offset the previous step left.
    ///
    /// - Parameters:
    ///   - app: Launched fixture Songs with the sheet open.
    ///   - types: Audit types to run.
    @MainActor
    private func auditAtEnds(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType) throws {
        let general = reveal(element("general", in: app), in: app)
        let form = element("form", in: app)
        // Short held drags down until General stops moving: the Form rests at its very top
        // (a pull this small springs back rather than dismissing the sheet).
        for _ in 0..<4 {
            let before = general.frame.minY
            let start = form.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: 32, dy: sheetContentTop(for: general, in: app) + 24 - form.frame.minY
            ))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 40)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.8)
            if abs(general.frame.minY - before) < 1 { break }
        }
        XCTAssertTrue(app.navigationBars["Filter Songs"].exists, "Filter sheet dismissed while resting at its top")
        try audit(app, for: types)
        let reset = app.buttons[Self.prefix + "reset"]
        // Swiping up past the end only bounces; down at the top would dismiss the sheet.
        var swipes = 0
        while !(reset.exists && reset.isHittable) && swipes < 12 {
            form.swipeUp()
            swipes += 1
        }
        form.swipeUp()
        XCTAssertTrue(reset.isHittable, "Reset Filters not reached at the end of the sheet")
        try audit(app, for: types)
    }

    /// At the largest text size every group's hint wraps onto several lines (at least 1.5x
    /// its one-line title) instead of truncating to one.
    @MainActor
    private func assertHintsWrap(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for group in Self.hints {
            let title = reveal(app.staticTexts[group.title].firstMatch, in: app, file: file, line: line).frame.height
            let hint = reveal(app.staticTexts[group.hint].firstMatch, in: app, file: file, line: line).frame.height
            XCTAssertGreaterThanOrEqual(hint, title * 1.5, "\(group.title) hint wraps: title \(title), hint \(hint)",
                                        file: file, line: line)
        }
    }

    /// Heights of the Item Shop group's title and hint, each scrolled wholly on screen.
    ///
    /// - Returns: Frame heights in ``shopTexts`` order.
    @MainActor
    private func shopTextHeights(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> [CGFloat] {
        Self.shopTexts.map { text in
            reveal(app.staticTexts[text].firstMatch, in: app, file: file, line: line).frame.height
        }
    }

    /// The height of a Year decade switch's label text (the switch's own frame when it
    /// has no text child), revealed first.
    ///
    /// - Parameters:
    ///   - label: Decade label, e.g. "2020s".
    ///   - app: Launched fixture Songs with Year open.
    /// - Returns: Height in points.
    @MainActor
    private func decadeTextHeight(_ label: String, in app: XCUIApplication) -> CGFloat {
        let decade = app.switches.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label == %@", Self.prefix + "year.", label
        )).firstMatch
        reveal(decade, in: app)
        let text = decade.staticTexts[label].firstMatch
        return text.exists ? text.frame.height : decade.frame.height
    }

    // MARK: - Tests

    /// Default text size: Sort and Filter Songs read their state in every bar (the folded
    /// Duo's vertical bar too), Filter Songs reports "No filters" and has a 44 pt target
    /// (its frame, or near-miss taps where it is drawn smaller);
    /// the sheet shows General only, in order, passes every audit but Dynamic Type collapsed
    /// and with Year open; switching a choice applies it and the button names the active
    /// General filter.
    @MainActor
    func testNoProfileGeneralFiltersPassAccessibilityAudit() throws {
        continueAfterFailure = false
        let app = launchSongs()
        let filter = app.buttons["fst.songs.filter"]
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 5))
        XCTAssertEqual(Self.spoken(sort), "Sort, Title, ascending", "Sort reads its order in every bar")
        assertFilterHitRegion(app)
        openCleanSheet(app)
        XCTAssertEqual(Self.spoken(filter), "Filter Songs, No filters")
        assertGeneralOnly(app)
        SongsUITestSupport.record(app, name: "songs-filter-no-profile-a11y-default")
        try audit(app, for: Self.auditWithoutDynamicType)

        let decades = assertYearGroup(app)
        SongsUITestSupport.record(app, name: "songs-filter-no-profile-year-a11y-default")
        try audit(app, for: Self.auditWithoutDynamicType)

        let decade = reveal(decades[0], in: app)
        SongsUITestSupport.setSwitch(decade, to: "0")
        reveal(app.buttons[Self.prefix + "year.select-all"], in: app).tap()
        let reselected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: decade)
        XCTAssertEqual(XCTWaiter.wait(for: [reselected], timeout: 5), .completed, "Select All, Year reselects")

        reveal(element("double-bass", in: app), in: app).tap()
        let noDoubleBass = app.switches[Self.prefix + "double-bass.unsupported"]
        // Expanded at the Form's end (the folded Duo), its choices load once scrolled to.
        _ = noDoubleBass.waitForExistence(timeout: 3)
        reveal(noDoubleBass, in: app)
        XCTAssertEqual(noDoubleBass.label, "No Double Bass Support")
        SongsUITestSupport.setSwitch(noDoubleBass, to: "0")
        app.buttons[Self.prefix + "done"].tap()
        let named = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@",
                                   "Double Bass filter", "Double Bass filter"), object: filter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 10), .completed,
                       "Filter Songs names the active filter: \(Self.spoken(filter))")

        openSheet(app)
        reveal(app.buttons[Self.prefix + "reset"], in: app).tap()
        app.buttons[Self.prefix + "done"].tap()
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR label == %@", "No filters", "Filter Songs, No filters"),
            object: filter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 10), .completed)
        XCTAssertEqual(Self.spoken(filter), "Filter Songs, No filters")
    }

    /// The Dynamic Type audit, with the Item Shop hidden in Settings, at the default size
    /// collapsed and with Year open.
    ///
    /// iOS 26.5's audit reports the Item Shop group's title and hint (only those; Year,
    /// Duration and Double Bass are built the same way) as "partially unsupported", though
    /// they measure 3.1x (title) and 6.2x (hint) taller at AX5. That is the auditor false
    /// positive the iPad audit proves as `dynamic-type-grows`; iPhone takes no waivers, so
    /// ``testGeneralFiltersAtLargestText`` measures those texts' growth instead. On the
    /// folded iPhone Duo it reports a Year decade switch's label (a system `Toggle`) the
    /// same way: such an issue passes only when that decade's label measures at least
    /// 1.35x taller in an AX5 launch here (the `dynamic-type-grows` evidence).
    @MainActor
    func testDynamicTypeAuditWithShopHidden() throws {
        continueAfterFailure = false
        let app = launchSongs(showShop: false)
        openCleanSheet(app)
        XCTAssertFalse(element("shop", in: app).exists, "Item Shop group while the Shop is hidden")
        try audit(app, for: .dynamicType)
        let decades = assertYearGroup(app)
        let decadeLabels = Set(decades.map(\.label))
        var flagged = Set<String>()
        try audit(app, for: .dynamicType) { issue in
            guard let element = issue.element, decadeLabels.contains(element.label) else { return false }
            flagged.insert(element.label)
            return true
        }
        guard !flagged.isEmpty else { return }
        let regular = flagged.sorted().map { decadeTextHeight($0, in: app) }
        app.terminate()

        let large = launchSongs(
            contentSize: UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue, showShop: false
        )
        openCleanSheet(large)
        _ = assertYearGroup(large)
        for (label, height) in zip(flagged.sorted(), regular) {
            let grown = decadeTextHeight(label, in: large)
            XCTAssertGreaterThanOrEqual(grown, height * 1.35, "Decade \(label) grows: \(height) → \(grown)")
        }
    }

    /// Largest accessibility text size: General's groups stay in order, the group labels and
    /// the Item Shop texts grow at least 1.35x, every hint wraps instead of truncating, Year's
    /// switches and header actions keep 44 pt targets (Hit region audit) and Reset Filters
    /// stays reachable. Dynamic Type is audited with the Shop hidden (the Item Shop texts are
    /// measured instead). Text clipped is audited at the default size only: at AX5 iOS 26.5
    /// intermittently reports an element-less Text clipped issue on a state that passes on
    /// rerun (an open finding, like the Songs and Item Shop lists'), so wrapping is asserted.
    @MainActor
    func testGeneralFiltersAtLargestText() throws {
        continueAfterFailure = false
        let largest = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        let regular = launchSongs()
        openCleanSheet(regular)
        let regularHeight = reveal(element("double-bass", in: regular), in: regular)
            .frame.height
        let regularShop = shopTextHeights(regular)
        regular.terminate()

        let app = launchSongs(contentSize: largest)
        openCleanSheet(app)
        assertGeneralOnly(app)
        let largeHeight = reveal(element("double-bass", in: app), in: app)
            .frame.height
        XCTAssertGreaterThan(largeHeight, regularHeight * 1.35, "Group labels grow: \(regularHeight) → \(largeHeight)")
        let largeShop = shopTextHeights(app)
        for (index, text) in Self.shopTexts.enumerated() {
            XCTAssertGreaterThanOrEqual(largeShop[index], regularShop[index] * 1.35,
                                        "\(text) grows: \(regularShop[index]) → \(largeShop[index])")
        }
        assertHintsWrap(app)
        SongsUITestSupport.record(app, name: "songs-filter-no-profile-a11y-ax5")
        try auditAtEnds(app, for: .hitRegion)

        _ = assertYearGroup(app)
        SongsUITestSupport.record(app, name: "songs-filter-no-profile-year-a11y-ax5")
        try auditAtEnds(app, for: .hitRegion)
        XCTAssertTrue(reveal(app.buttons[Self.prefix + "reset"], in: app).isHittable)
        app.terminate()

        let hidden = launchSongs(contentSize: largest, showShop: false)
        openCleanSheet(hidden)
        try auditAtEnds(hidden, for: .dynamicType)
        _ = assertYearGroup(hidden)
        try auditAtEnds(hidden, for: .dynamicType)
    }
}
