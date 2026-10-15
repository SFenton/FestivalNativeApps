import XCTest

/// Issue #15: page buttons accept near-miss taps. Since issue #632 the page tools are
/// individual floating glass buttons above the tab bar (`fst.page-tools`), and
/// Notifications and Profile share one pill at the navigation bar's trailing end,
/// Profile trailing-most (they were in the tab-bar accessory from #92 to #632).
///
/// Each button is tapped 20 pt off-centre in every direction and 15 pt diagonally, all
/// inside a 44 × 44 pt square centred on it (HIG Buttons: "the hit region is at least
/// 44x44 pt"), and must open its own sheet or menu. Neighbours are probed the same way,
/// so a tap that opened the wrong one (overlapping hit regions) fails too.
///
/// Before the fix the Quick Links menu answered only ~12 pt either side of its glyph
/// and nowhere above or below it, and the selected-profile monogram only inside its
/// 36 pt-tall capsule. Runs against `tools/mock_service.py --large-catalogue`,
/// exported as `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL`; Quick Links checks skip on
/// the two-song fixture, which has a single Year section.
final class NavButtonHitRegionJourneyTests: XCTestCase {
    /// Offsets from a button's centre, all inside a 44 × 44 pt square.
    private static let nearMisses: [CGVector] = [
        CGVector(dx: -20, dy: 0), CGVector(dx: 20, dy: 0),
        CGVector(dx: 0, dy: -20), CGVector(dx: 0, dy: 20),
        CGVector(dx: -15, dy: -15), CGVector(dx: 15, dy: 15),
    ]

    @MainActor
    private func fixtureApp(profile: Bool, tab: String? = nil, route: String? = nil) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ]
        if profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        if let tab { env["FST_DEBUG_TAB"] = tab }
        if let route { env["FST_DEBUG_ROUTE"] = route }
        return FestivalApp.makeApp(env)
    }

    // MARK: - Journeys

    /// Songs' floating page tools accept 44 pt near-miss taps.
    @MainActor
    func testSongsPageToolsAcceptNearMisses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { resetSort(in: app) }
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15))
        try chooseYearSort(in: app)
        // Each floating tool fills its 44 pt circle, so the reported frame is the hit region.
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open"]
        let frames = ids.map { app.buttons[$0].frame }
        for (id, frame) in zip(ids, frames) {
            XCTAssertGreaterThanOrEqual(frame.height, 44, "\(id) \(frame)")
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(id) \(frame)")
        }
        for index in frames.indices.dropLast() {
            XCTAssertLessThanOrEqual(frames[index].maxX, frames[index + 1].minX, "\(ids[index]) overlaps its neighbour")
        }

        assertNearMissesOpen(app, "fst.songs.filter", opens: app.buttons["fst.songs.filter.done"]) {
            app.buttons["fst.songs.filter.done"].tap()
        }
        assertNearMissesOpen(app, "fst.songs.sort", opens: app.buttons["fst.songs.sort.done"]) {
            app.buttons["fst.songs.sort.done"].tap()
        }
        assertNearMissesOpen(app, "fst.quick-links.open", opens: quickLinksRow(in: app)) {
            Self.closeQuickLinks(in: app)
        }
    }

    /// Issue #632: Songs' page tools are individual 44 pt floating buttons, left to right
    /// at the trailing edge between the navigation bar and the tab bar; none of them is in
    /// the navigation bar. Notifications is no page tool: it sits in the navigation bar
    /// right before Profile, the trailing-most button, and the two do not overlap.
    @MainActor
    func testSongsFloatingToolsOrderAndHitRegions() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        let tools = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 15), "Floating page tools missing")
        XCTAssertEqual(tools.label, "Page Tools")
        let ids = Self.songsTools(in: app)
        let controls = ids.map { tools.buttons[$0] }
        XCTAssertFalse(app.buttons["fst.songs.tools"].exists, "iPhone 17 Pro should not fold Sort and Filter")
        let bar = app.navigationBars.firstMatch
        let tabBar = app.tabBars.firstMatch
        for (id, control) in zip(ids, controls) {
            XCTAssertTrue(control.waitForExistence(timeout: 15), "\(id) missing from the floating row")
            XCTAssertTrue(control.isHittable, "\(id) not hittable")
            XCTAssertGreaterThanOrEqual(control.frame.height, 44, "\(id) hit region \(control.frame)")
            XCTAssertGreaterThanOrEqual(control.frame.width, 44, "\(id) hit region \(control.frame)")
            XCTAssertFalse(app.navigationBars.buttons[id].exists, "\(id) is still in the navigation bar")
            XCTAssertGreaterThan(control.frame.minY, bar.frame.maxY)
            if tabBar.exists { XCTAssertLessThanOrEqual(control.frame.maxY, tabBar.frame.minY + 0.5, "\(id) over the tab bar") }
        }
        for index in controls.indices.dropLast() {
            XCTAssertLessThanOrEqual(
                controls[index].frame.maxX, controls[index + 1].frame.minX,
                "\(ids[index]) is not before \(ids[index + 1])"
            )
        }
        XCTAssertEqual(controls[controls.count - 1].frame.maxX, app.frame.maxX - 16, accuracy: 1,
                       "the last tool is not 16 pt from the trailing edge")
        XCTAssertFalse(tools.buttons["fst.shell.notifications"].exists, "Notifications is still a page tool")
        let bell = bar.buttons["fst.shell.notifications"]
        let profile = bar.buttons["fst.shell.profile"]
        XCTAssertTrue(bell.exists, "Notifications is not in the navigation bar")
        XCTAssertTrue(profile.exists, "Profile is not in the navigation bar")
        XCTAssertFalse(tools.buttons["fst.shell.profile"].exists, "Profile is a page tool")
        XCTAssertTrue(bell.isHittable, "Notifications not hittable")
        XCTAssertTrue(profile.isHittable, "Profile not hittable")
        XCTAssertLessThanOrEqual(bell.frame.maxX, profile.frame.minX + 0.5, "Notifications is not before Profile")
        let trailing = bar.buttons.allElementsBoundByIndex
            .filter { $0.frame.minY < bar.frame.minY + 50 }
            .map(\.frame.maxX).max() ?? 0
        XCTAssertEqual(profile.frame.maxX, trailing, accuracy: 0.5, "Profile is not the rightmost header button")
    }

    /// The drawer, the bell and the selected-profile monogram (all in the navigation bar).
    @MainActor
    func testHeaderButtonsAcceptNearMisses() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        XCTAssertTrue(app.buttons["fst.shell.profile"].waitForExistence(timeout: 15))
        assertNearMissesOpen(app, "fst.shell.drawer.open", opens: app.buttons["fst.shell.drawer.close"]) {
            app.buttons["fst.shell.drawer.close"].tap()
        }
        assertNearMissesOpen(app, "fst.shell.notifications", opens: app.buttons["fst.notifications.close"]) {
            app.buttons["fst.notifications.close"].tap()
        }
        // With a player selected the avatar opens their Statistics page (issue #290).
        assertNearMissesOpen(app, "fst.shell.profile", opens: SongsUITestSupport.playerPage(in: app)) {
            let back = app.navigationBars.buttons["BackButton"]
            (back.exists ? back : app.navigationBars.buttons.element(boundBy: 0)).tap()
        }
    }

    /// Choose Profile (anonymous, navigation bar) and Suggestions' floating Filter.
    @MainActor
    func testChooseProfileAndSuggestionsFilterAcceptNearMisses() throws {
        continueAfterFailure = false
        let anonymous = fixtureApp(profile: false)
        anonymous.launch()
        XCTAssertTrue(anonymous.buttons["fst.shell.profile"].waitForExistence(timeout: 15))
        assertNearMissesOpen(anonymous, "fst.shell.profile", opens: anonymous.buttons["fst.profile.close"]) {
            anonymous.buttons["fst.profile.close"].tap()
        }
        anonymous.terminate()

        let app = fixtureApp(profile: true, tab: "suggestions")
        app.launch()
        assertNearMissesOpen(
            app, "fst.suggestions.filter-button", opens: app.buttons["fst.suggestions.filter.done"]
        ) {
            app.buttons["fst.suggestions.filter.done"].tap()
        }
    }

    /// Issue #632: scrolling minimizes the tab bar, but the floating tools stay put (no
    /// inline morph): the same items (Sort, Filter, Quick Links), each a 44 pt circle in
    /// the same place without overlap, still accept near-miss taps; Quick Links opens its
    /// choices as a sheet.
    @MainActor
    func testSongsFloatingToolsStayPutWhileScrolled() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { resetSort(in: app) }
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: 15))
        try chooseYearSort(in: app)
        let field = app.searchFields["Filter Songs"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let ids = ["fst.songs.sort", "fst.songs.filter", "fst.quick-links.open"]
        for _ in 0..<100 {
            if ids.allSatisfy({ app.buttons[$0].exists && app.buttons[$0].isHittable }) { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        guard ids.allSatisfy({ app.buttons[$0].exists }) else {
            throw XCTSkip("Catalogue too short to scroll; use mock_service.py --large-catalogue.")
        }
        let before = ids.map { app.buttons[$0].frame }
        app.swipeUp()
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1)))
        XCTAssertFalse(app.buttons["fst.songs.tools"].exists, "Sort and Filter folded while scrolled")
        XCTAssertTrue(field.exists, "Filter Songs field disappeared while scrolled")
        let frames = ids.map { app.buttons[$0].frame }
        for (id, (frame, start)) in zip(ids, zip(frames, before)) {
            XCTAssertGreaterThanOrEqual(frame.width, 44, "\(id) \(frame)")
            XCTAssertGreaterThan(frame.minY, app.navigationBars.firstMatch.frame.maxY, "\(id) in the header")
            XCTAssertEqual(frame.minX, start.minX, accuracy: 0.5, "\(id) moved sideways while scrolled")
            XCTAssertEqual(frame.minY, start.minY, accuracy: 0.5, "\(id) moved while the tab bar minimized")
        }
        for index in frames.indices.dropLast() {
            XCTAssertLessThanOrEqual(frames[index].maxX, frames[index + 1].minX, "\(ids[index]) overlaps its neighbour")
        }
        assertNearMissesOpen(app, "fst.songs.filter", opens: app.buttons["fst.songs.filter.done"]) {
            app.buttons["fst.songs.filter.done"].tap()
        }
        assertNearMissesOpen(app, "fst.quick-links.open", opens: quickLinksRow(in: app)) {
            Self.closeQuickLinks(in: app)
        }
    }

    /// Issues #300, #632: at an accessibility text size Sort and Filter stay two fixed
    /// 44 pt floating circles (they no longer fold: the circles do not grow with text,
    /// and long-press shows the Large Content Viewer), the item set never changes while
    /// the tab bar minimizes, and each still accepts near-miss taps.
    @MainActor
    func testAccessibilityTextKeepsTheFloatingToolsWhileScrolled() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        let sort = app.buttons["fst.songs.sort"]
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(sort.waitForExistence(timeout: 15), "Sort missing at AX text size")
        XCTAssertTrue(filter.exists, "Filter missing at AX text size")
        XCTAssertFalse(app.buttons["fst.songs.tools"].exists, "Sort and Filter folded at AX text size")
        let field = app.searchFields["Filter Songs"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let before = [sort.frame, filter.frame]
        app.swipeUp()
        for _ in 0..<30 {
            XCTAssertTrue(sort.exists && filter.exists, "a tool left while scrolling")
            XCTAssertFalse(app.buttons["fst.songs.tools"].exists, "Sort and Filter folded while scrolling")
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        for (frame, start) in zip([sort.frame, filter.frame], before) {
            XCTAssertEqual(frame.width, 44, accuracy: 1, "\(frame)")
            XCTAssertEqual(frame.height, 44, accuracy: 1, "\(frame)")
            XCTAssertEqual(frame.minY, start.minY, accuracy: 0.5, "a tool moved while the tab bar minimized")
        }
        assertNearMissesOpen(app, "fst.songs.filter", opens: app.buttons["fst.songs.filter.done"]) {
            app.buttons["fst.songs.filter.done"].tap()
        }
    }

    /// Issue #394 (for #14): at the largest accessibility text size the bell and Profile
    /// (one shared pill in the navigation bar since #632) stay two separate, labelled buttons with
    /// 44 pt hit regions; each still opens its own destination, and an accessibility
    /// audit of hit region, description, Dynamic Type and clipping reports nothing on
    /// either. Bar buttons keep their size at large text (Profile offers the Large
    /// Content Viewer). The production reading order (bell, then Profile) holds at this
    /// size too.
    @MainActor
    func testAccountButtonsStaySeparateAndLabelledAtLargestTextSize() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        let bell = app.buttons["fst.shell.notifications"]
        let profile = app.navigationBars.buttons["fst.shell.profile"]
        XCTAssertTrue(bell.waitForExistence(timeout: FestivalApp.budget(15)), "Notifications missing at AX text size")
        XCTAssertTrue(profile.waitForExistence(timeout: FestivalApp.budget(10)), "Profile missing at AX text size")
        XCTAssertTrue(bell.label.hasPrefix("Notifications"), "bell label '\(bell.label)'")
        XCTAssertEqual(profile.label, "Profile: Fixture Player 1")
        for (id, button) in [("bell", bell), ("profile", profile)] {
            XCTAssertTrue(button.isHittable, "\(id) not hittable")
            XCTAssertGreaterThanOrEqual(button.frame.height, 30, "\(id) \(button.frame)")
        }
        // Both are system bar items whose elements are their glass item (36 pt, the
        // monogram 30 pt); the bar extends each hit region past its element, so the 44 pt
        // regions are proven by the near-miss taps and the `.hitRegion` audit below.
        XCTAssertFalse(bell.frame.intersects(profile.frame), "bell \(bell.frame) overlaps profile \(profile.frame)")
        SongsUITestSupport.record(app, name: "account-buttons-ax-xxxl")
        try assertAccountReadingOrder(in: app, profileLabel: "Profile: Fixture Player 1", expectsBell: true)

        let account: Set<String> = ["fst.shell.notifications", "fst.shell.profile"]
        try app.performAccessibilityAudit(
            for: [.hitRegion, .sufficientElementDescription, .dynamicType, .textClipped]
        ) { issue in
            // Audit only the account group; other regions have their own journeys.
            guard let element = issue.element, account.contains(element.identifier) else { return true }
            return false
        }

        assertNearMissesOpen(app, "fst.shell.notifications", opens: app.buttons["fst.notifications.close"]) {
            app.buttons["fst.notifications.close"].tap()
        }
        assertNearMissesOpen(app, "fst.shell.profile", opens: SongsUITestSupport.playerPage(in: app)) {
            let back = app.navigationBars.buttons["BackButton"]
            (back.exists ? back : app.navigationBars.buttons.element(boundBy: 0)).tap()
        }
    }

    // MARK: - Account reading order (issue #394, for #14)

    /// Issue #394 (for #14), re-measured for #632: in the production iPhone chrome the
    /// bell and Profile are two separate buttons in the navigation bar's account pill, read
    /// in screen order after the drawer and the title: bell, then Profile (the bar's last
    /// button); the page's floating tools follow the page, before the tab bar. Measured
    /// from the app's accessibility hierarchy, the order VoiceOver swipes through.
    @MainActor
    func testAccountButtonsReadInProductionChromeOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        XCTAssertTrue(app.buttons["fst.shell.notifications"].waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(app.navigationBars.buttons["fst.shell.profile"].waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertTrue(app.buttons["fst.songs.filter"].waitForExistence(timeout: FestivalApp.budget(10)))
        let order = try assertAccountReadingOrder(in: app, profileLabel: "Profile: Fixture Player 1", expectsBell: true)
        // Songs: drawer → bell → Profile in the bar; Sort → Filter (→ Quick Links) floating.
        XCTAssertEqual(
            order.navigationBar, ["fst.shell.drawer.open", "fst.shell.notifications", "fst.shell.profile"],
            "navigation bar buttons \(order)"
        )
        XCTAssertEqual(order.tools, Self.songsTools(in: app), "floating tools \(order)")
    }

    /// Songs' floating tools in reading order: Sort, Filter and, once the catalogue has
    /// sections to jump to (the `--large-catalogue` fixture), Quick Links.
    ///
    /// - Parameter app: The running app on the Songs root.
    /// - Returns: The tools' identifiers, leading to trailing.
    @MainActor
    private static func songsTools(in app: XCUIApplication) -> [String] {
        let quickLinks = app.buttons["fst.quick-links.open"].waitForExistence(timeout: FestivalApp.budget(3))
        return ["fst.songs.sort", "fst.songs.filter"] + (quickLinks ? ["fst.quick-links.open"] : [])
    }

    /// The same order on a pushed page (`PageTrailingItems`): Back, the bell, then Profile
    /// in the navigation bar; the page's tools float after the page.
    @MainActor
    func testAccountButtonsReadInProductionChromeOrderOnPushedPage() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true, route: "fullRankings:Solo_Guitar")
        app.launch()
        XCTAssertTrue(app.buttons["fst.shell.notifications"].waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(app.navigationBars.buttons["fst.shell.profile"].waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertFalse(app.navigationBars.buttons["fst.shell.drawer.open"].exists, "a pushed page shows the drawer")
        let order = try assertAccountReadingOrder(in: app, profileLabel: "Profile: Fixture Player 1", expectsBell: true)
        XCTAssertGreaterThanOrEqual(order.navigationBar.count, 3, "no Back before the bell and Profile \(order)")
    }

    /// Anonymous: no bell anywhere, and Choose Profile is the navigation bar's last button.
    @MainActor
    func testChooseProfileReadsAloneInProductionChrome() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: false)
        app.launch()
        XCTAssertTrue(app.navigationBars.buttons["fst.shell.profile"].waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: FestivalApp.budget(10)))
        try assertAccountReadingOrder(in: app, profileLabel: "Choose Profile", expectsBell: false)
    }

    // MARK: - Pushed-page Profile (issue #437, for #85)

    /// Issue #437 (for #85): on Song Details, the page #85 was reported on, Profile is one
    /// labelled button and the navigation bar's last, rightmost button, read after the
    /// bell and before the page's own floating actions (Paths, Item Shop, Quick Links); it keeps a 44 pt
    /// tall hit region. Going back to Songs leaves exactly one Profile, still last.
    @MainActor
    func testProfileStaysTheLastBarButtonOnSongDetail() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        try openSongDetail(in: app)
        let order = try assertAccountReadingOrder(in: app, profileLabel: "Profile: Fixture Player 1", expectsBell: true)
        XCTAssertFalse(order.navigationBar.contains("fst.shell.drawer.open"), "a pushed page shows the drawer \(order)")
        // #85's case: the page has its own actions, and none of them follows Profile.
        let actions = ["fst.song-detail.paths", "fst.song-detail.shop", "fst.quick-links.open"]
        XCTAssertEqual(order.navigationBar.last, "fst.shell.profile", "\(order)")
        XCTAssertTrue(
            actions.contains { app.buttons[$0].exists }, "Song Details shows none of its page actions \(order)"
        )
        assertProfileTarget(in: app, monogram: true)
        SongsUITestSupport.record(app, name: "pushed-profile-song-detail")
        try assertSelectedProfileHitRegion(
            in: app, beside: actions, returnsTo: app.descendants(matching: .any)["fst.song-detail.hero-title"]
        )

        let back = app.navigationBars.buttons["BackButton"]
        (back.exists ? back : app.navigationBars.buttons.element(boundBy: 0)).tap()
        XCTAssertTrue(app.buttons["fst.songs.sort"].waitForExistence(timeout: FestivalApp.budget(10)))
        let songs = try assertAccountReadingOrder(in: app, profileLabel: "Profile: Fixture Player 1", expectsBell: true)
        XCTAssertEqual(
            songs.navigationBar, ["fst.shell.drawer.open", "fst.shell.notifications", "fst.shell.profile"],
            "after Back \(songs)"
        )
    }

    /// Issue #437 (for #85): pushed pages with their own page actions (Item Shop's Sort,
    /// Filter and List/Grid; the player page's profile action) keep Profile as one
    /// labelled button and the navigation bar's last, rightmost button. On Item Shop,
    /// whose actions crowd Profile most, the selected monogram also keeps a 44 × 44 pt
    /// hit region (`assertSelectedProfileHitRegion`). The player page is skipped there:
    /// Profile would open the page already shown, so a tap that missed it could pass.
    @MainActor
    func testProfileStaysTheLastBarButtonOnPushedPagesWithActions() throws {
        continueAfterFailure = false
        let pages: [(route: String, ready: String, actions: [String])] = [
            ("shop", "fst.shop.sort", ["fst.shop.sort", "fst.shop.filter", "fst.shop.view-toggle", "fst.quick-links.open"]),
            ("player:fixture-player-1", "fst.shell.notifications", []),
        ]
        for page in pages {
            let app = fixtureApp(profile: true, route: page.route)
            app.launch()
            XCTAssertTrue(
                app.buttons[page.ready].waitForExistence(timeout: FestivalApp.budget(15)), "\(page.route) not ready"
            )
            XCTAssertTrue(app.navigationBars.buttons["fst.shell.profile"].waitForExistence(timeout: FestivalApp.budget(10)))
            let order = try assertAccountReadingOrder(
                in: app, profileLabel: "Profile: Fixture Player 1", expectsBell: true
            )
            XCTAssertFalse(order.navigationBar.contains("fst.shell.drawer.open"), "\(page.route) shows the drawer \(order)")
            assertProfileTarget(in: app, monogram: true)
            SongsUITestSupport.record(app, name: "pushed-profile-\(page.route.split(separator: ":")[0])")
            if !page.actions.isEmpty {
                try assertSelectedProfileHitRegion(in: app, beside: page.actions, returnsTo: app.buttons[page.ready])
            }
            app.terminate()
        }
    }

    /// Issue #437 (for #85): anonymous, at the largest accessibility text size, Song
    /// Details' Choose Profile is the navigation bar's one, last, rightmost Profile button
    /// with no bell; it stays hittable with a 44 pt hit region (near-miss taps 20 pt off its
    /// centre open profile selection) and a scoped accessibility audit of hit region, description, Dynamic Type
    /// and clipping reports nothing on it. Bar buttons keep their size at large text and
    /// offer the Large Content Viewer.
    @MainActor
    func testChooseProfileStaysLastOnSongDetailAtLargestTextSize() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: false)
        app.launchArguments += [
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
        ]
        app.launch()
        try openSongDetail(in: app)
        let order = try assertAccountReadingOrder(in: app, profileLabel: "Choose Profile", expectsBell: false)
        XCTAssertEqual(order.navigationBar.last, "fst.shell.profile", "\(order)")
        assertProfileTarget(in: app, monogram: false)
        SongsUITestSupport.record(app, name: "pushed-choose-profile-song-detail-ax-xxxl")

        try app.performAccessibilityAudit(
            for: [.hitRegion, .sufficientElementDescription, .dynamicType, .textClipped]
        ) { issue in
            // Audit only Profile; Song Details has its own audit journeys.
            issue.element?.identifier != "fst.shell.profile"
        }
        assertNearMissesOpen(app, "fst.shell.profile", opens: app.buttons["fst.profile.close"]) {
            app.buttons["fst.profile.close"].tap()
        }
        let after = try assertAccountReadingOrder(in: app, profileLabel: "Choose Profile", expectsBell: false)
        XCTAssertEqual(after.navigationBar.last, "fst.shell.profile", "after the sheet \(after)")
    }

    /// Open the first fully visible Songs row's Song Details and wait for its Profile.
    @MainActor
    private func openSongDetail(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: FestivalApp.budget(15)), "no Songs rows",
                      file: file, line: line)
        let row = try XCTUnwrap(
            rows.allElementsBoundByIndex.prefix(12).first { $0.isHittable && $0.frame.midY > app.frame.height * 0.3 },
            "no hittable Songs row", file: file, line: line
        )
        row.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["fst.song-detail.hero-title"].waitForExistence(timeout: FestivalApp.budget(10)),
            "Song Details did not open", file: file, line: line
        )
        XCTAssertTrue(
            app.navigationBars.buttons["fst.shell.profile"].waitForExistence(timeout: FestivalApp.budget(10)),
            "Song Details has no Profile", file: file, line: line
        )
        // Let the push and the page's toolbar items settle before reading the tree.
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1)))
    }

    /// Require Profile to be hittable and the bar's trailing-most element on screen.
    ///
    /// Since #632 the selected-profile monogram is a 30 pt avatar inside the account
    /// pill's shared glass (`MonogramMetrics.pillDiameter`), and Choose Profile a system
    /// bar button whose element is its Liquid Glass circle; the bar extends both hit
    /// regions, so their 44 pt regions are proven by near-miss taps and the `.hitRegion`
    /// audit (`testChooseProfileAndSuggestionsFilterAcceptNearMisses`).
    ///
    /// - Parameters:
    ///   - app: The running app, settled on a page.
    ///   - monogram: Whether a profile is selected, so Profile draws the pill monogram.
    @MainActor
    private func assertProfileTarget(
        in app: XCUIApplication, monogram: Bool, file: StaticString = #filePath, line: UInt = #line
    ) {
        let profile = app.navigationBars.buttons["fst.shell.profile"]
        XCTAssertTrue(profile.isHittable, "Profile not hittable", file: file, line: line)
        if monogram {
            XCTAssertGreaterThanOrEqual(profile.frame.height, 30, "Profile \(profile.frame)", file: file, line: line)
        }
        for button in app.navigationBars.buttons.allElementsBoundByIndex
        where button.identifier != "fst.shell.profile" && button.frame.width > 0 {
            XCTAssertLessThanOrEqual(button.frame.maxX, profile.frame.minX + 0.5,
                                     "'\(button.identifier)' \(button.frame) is right of Profile \(profile.frame)",
                                     file: file, line: line)
        }
    }

    /// Require the selected-profile monogram on a pushed page to keep a 44 × 44 pt hit
    /// region that its page actions do not take over.
    ///
    /// The monogram's element is the 30 pt pill avatar (#632), so its frame cannot
    /// prove the 44 pt region. Instead,
    /// no shown page action may overlap Profile (`assertProfileTarget` already keeps every
    /// bar button left of it); a scoped `.hitRegion`
    /// audit must report nothing on Profile; and taps 20 pt off its centre in every
    /// direction (15 pt diagonally) must open the selected player's page. That page is
    /// what only Profile opens here, so a tap that a neighbouring action took fails.
    ///
    /// - Parameters:
    ///   - app: The running app, settled on a pushed page with a profile selected.
    ///   - actions: Identifiers of the page's own actions, wherever they are placed.
    ///   - returnsTo: An element of the page under test, awaited after each Back.
    @MainActor
    private func assertSelectedProfileHitRegion(
        in app: XCUIApplication, beside actions: [String], returnsTo page: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let profile = app.navigationBars.buttons["fst.shell.profile"]
        XCTAssertEqual(profile.label, "Profile: Fixture Player 1", file: file, line: line)
        let shown = actions.map { app.buttons.matching(identifier: $0).firstMatch }
            .filter { $0.exists && $0.frame.width > 0 }
        XCTAssertFalse(shown.isEmpty, "none of the page actions \(actions) shows", file: file, line: line)
        for action in shown {
            XCTAssertFalse(action.frame.intersects(profile.frame),
                           "'\(action.identifier)' \(action.frame) overlaps Profile \(profile.frame)",
                           file: file, line: line)
        }
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription]) { issue in
            // Audit only Profile; each page has its own audit journeys.
            issue.element?.identifier != "fst.shell.profile"
        }
        assertNearMissesOpen(
            app, "fst.shell.profile", opens: SongsUITestSupport.playerPage(in: app),
            close: {
                let back = app.navigationBars.buttons["BackButton"]
                (back.exists ? back : app.navigationBars.buttons.element(boundBy: 0)).tap()
                XCTAssertTrue(page.waitForExistence(timeout: FestivalApp.budget(10)), "Back did not return",
                              file: file, line: line)
            },
            file: file, line: line
        )
    }

    /// Account buttons as read from the app's accessibility hierarchy.
    private struct AccountReadingOrder: CustomStringConvertible {
        /// Identifiers (or labels) of the navigation bar's buttons, in reading order.
        var navigationBar: [String]
        /// Identifiers (or labels) of the floating page tools (`fst.page-tools`), in reading order.
        var tools: [String]

        var description: String { "bar \(navigationBar), tools \(tools)" }
    }

    /// One node of a depth-first walk of the app's accessibility snapshot.
    private struct AXEntry {
        let node: XCUIElementSnapshot
        /// Index one past this node's last descendant.
        var end: Int
    }

    /// The app's accessibility hierarchy in depth-first order: the order the system
    /// exposes elements to assistive technologies, which VoiceOver swipes through.
    @MainActor
    private func accessibilityWalk(_ app: XCUIApplication) throws -> [AXEntry] {
        var entries: [AXEntry] = []
        func walk(_ node: XCUIElementSnapshot) {
            let index = entries.count
            entries.append(AXEntry(node: node, end: index + 1))
            node.children.forEach(walk)
            entries[index].end = entries.count
        }
        walk(try app.snapshot())
        return entries
    }

    /// Require Profile and (with `expectsBell`) the bell to be separate, labelled buttons
    /// in the navigation bar, read bell → Profile in screen order (issue #632).
    ///
    /// Profile must be the navigation bar's last button and the bell the one right before
    /// it; the floating page tools (`fst.page-tools`), when shown, are read after the bar
    /// and before the tab bar and hold neither; the bell's badge digit and glyph belong to
    /// the bell, not to a separate element. XCUITest cannot read VoiceOver's cursor, so
    /// the order is the hierarchy's depth-first order.
    ///
    /// - Parameters:
    ///   - app: The running app, settled on a page.
    ///   - profileLabel: The expected Profile label.
    ///   - expectsBell: Whether a profile is selected, so the bell shows.
    /// - Returns: The bar's buttons and the floating tools in reading order.
    @MainActor
    @discardableResult
    private func assertAccountReadingOrder(
        in app: XCUIApplication, profileLabel: String, expectsBell: Bool,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> AccountReadingOrder {
        let entries = try accessibilityWalk(app)
        func ancestors(of index: Int) -> [Int] {
            entries.indices.filter { $0 < index && index < entries[$0].end }
        }
        /// Buttons inside `container` not nested in another button, in reading order.
        func buttons(in container: Int) -> [Int] {
            (container + 1..<entries[container].end).filter { index in
                entries[index].node.elementType == .button
                    && !ancestors(of: index).contains { $0 > container && entries[$0].node.elementType == .button }
            }
        }
        func name(_ index: Int) -> String {
            let node = entries[index].node
            return node.identifier.isEmpty ? node.label : node.identifier
        }
        let dump = entries.indices.filter { index in
            ([.navigationBar, .tabBar, .button] as [XCUIElement.ElementType]).contains(entries[index].node.elementType)
                || entries[index].node.identifier == "fst.page-tools"
        }.map { "\($0) \(entries[$0].node.elementType.rawValue) '\(name($0))' '\(entries[$0].node.label)'" }
        let attachment = XCTAttachment(string: dump.joined(separator: "\n"))
        attachment.name = "account-reading-order"
        attachment.lifetime = .keepAlways
        add(attachment)

        let profiles = entries.indices.filter { entries[$0].node.identifier == "fst.shell.profile" }
        XCTAssertEqual(profiles.count, 1, "Profile elements: \(profiles)", file: file, line: line)
        let profile = try XCTUnwrap(profiles.first, file: file, line: line)
        XCTAssertEqual(entries[profile].node.elementType, .button, "Profile role", file: file, line: line)
        XCTAssertEqual(entries[profile].node.label, profileLabel, file: file, line: line)
        let bar = try XCTUnwrap(
            ancestors(of: profile).last { entries[$0].node.elementType == .navigationBar },
            "Profile is not in a navigation bar", file: file, line: line
        )
        let barButtons = buttons(in: bar)
        XCTAssertEqual(barButtons.last, profile, "Profile is not the bar's last button: \(barButtons.map(name))",
                       file: file, line: line)
        for other in barButtons.dropLast() where entries[other].node.frame.width > 0 {
            XCTAssertLessThanOrEqual(entries[other].node.frame.maxX, entries[profile].node.frame.minX + 0.5,
                                     "\(name(other)) is right of Profile", file: file, line: line)
        }
        XCTAssertGreaterThanOrEqual(barButtons.count, 2, "no drawer or Back before Profile", file: file, line: line)
        let tabBar = try XCTUnwrap(
            entries.indices.first { entries[$0].node.elementType == .tabBar }, "no tab bar", file: file, line: line
        )
        XCTAssertLessThan(profile, tabBar, "Profile is read after the tab bar", file: file, line: line)

        let floating = entries.indices.first { entries[$0].node.identifier == "fst.page-tools" }
        let toolButtons = floating.map(buttons(in:)) ?? []
        XCTAssertFalse(toolButtons.contains(profile), "Profile is a floating page tool", file: file, line: line)
        if let floating, !toolButtons.isEmpty {
            // Screen order: navigation bar → page → floating tools → tab bar.
            XCTAssertLessThanOrEqual(entries[bar].end, floating, "the tools are read inside the bar",
                                     file: file, line: line)
            XCTAssertLessThan(floating, tabBar, "the tools are read after the tab bar", file: file, line: line)
            for tool in toolButtons {
                XCTAssertGreaterThanOrEqual(entries[tool].node.frame.minY, entries[profile].node.frame.maxY,
                                            "\(name(tool)) is above the header", file: file, line: line)
            }
        }

        let bells = entries.indices.filter { entries[$0].node.identifier == "fst.shell.notifications" }
        guard expectsBell else {
            XCTAssertTrue(bells.isEmpty, "a bell shows without a profile", file: file, line: line)
            return AccountReadingOrder(navigationBar: barButtons.map(name), tools: toolButtons.map(name))
        }
        XCTAssertEqual(bells.count, 1, "bell elements: \(bells)", file: file, line: line)
        let bell = try XCTUnwrap(bells.first, file: file, line: line)
        let node = entries[bell].node
        XCTAssertEqual(node.elementType, .button, "bell role", file: file, line: line)
        XCTAssertNotNil(
            node.label.range(of: #"^Notifications(, [0-9]+ unread)?$"#, options: .regularExpression),
            "bell label '\(node.label)'", file: file, line: line
        )
        XCTAssertTrue(((node.value as? String) ?? "").isEmpty, "bell value '\(String(describing: node.value))'",
                      file: file, line: line)
        XCTAssertTrue(ancestors(of: bell).contains(bar), "the bell is not in the navigation bar", file: file, line: line)
        XCTAssertFalse(toolButtons.contains(bell), "the bell is a floating page tool", file: file, line: line)
        // The account pill: the bell right before Profile, in the tree and on screen.
        // VoiceOver follows the tree, which does not reflect `accessibilitySortPriority`
        // (measured), so neither button may set one.
        XCTAssertEqual(barButtons.dropLast().last, bell, "the bell is not right before Profile: \(barButtons.map(name))",
                       file: file, line: line)
        XCTAssertLessThanOrEqual(node.frame.maxX, entries[profile].node.frame.minX + 0.5, "the bell is right of Profile",
                                 file: file, line: line)
        // The glyph and any badge digit belong to the bell, never a sibling button or label
        // elsewhere. In the navigation bar (#632) the iOS 26 system toolbar-item badge
        // publishes its digit as UIKit's own static text on the bell's top-trailing
        // corner (as on iPad); that one system element is allowed, nothing else.
        let corner = node.frame.insetBy(dx: -12, dy: -12)
        let strays = (bar + 1..<entries[bar].end).filter { index in
            let item = entries[index].node
            let digit = item.label.range(of: #"^[0-9]+\+?$"#, options: .regularExpression) != nil
            let badgeLike = item.label == "Notifications" || digit
            let systemBadge = digit && item.elementType == .staticText && index == bell + 1
                && corner.contains(CGPoint(x: item.frame.midX, y: item.frame.midY))
            return badgeLike && index != bell && !systemBadge && !ancestors(of: index).contains(bell)
        }
        XCTAssertTrue(strays.isEmpty, "badge parts outside the bell: \(strays.map(name))", file: file, line: line)
        return AccountReadingOrder(navigationBar: barButtons.map(name), tools: toolButtons.map(name))
    }

    // MARK: - Helpers

    /// Tap each near miss around button `id`, expect `opens` to appear, then close it.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - id: Accessibility identifier of the button under test.
    ///   - opens: An element only that button's sheet or menu shows.
    ///   - close: Dismisses the sheet or menu again.
    @MainActor
    private func assertNearMissesOpen(
        _ app: XCUIApplication, _ id: String, opens: XCUIElement, close: () -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let button = app.buttons.matching(identifier: id).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: FestivalApp.budget(10)), "\(id) missing", file: file, line: line)
        // A closing sheet briefly leaves the floating tools without a frame.
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: button)
        XCTAssertEqual(
            XCTWaiter.wait(for: [hittable], timeout: FestivalApp.budget(5)), .completed, "\(id) not hittable",
            file: file, line: line
        )
        // A `Menu` ignores taps while a sheet is still animating away.
        RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(1)))
        let frame = button.frame
        let origin = app.coordinate(withNormalizedOffset: .zero)
        for offset in Self.nearMisses {
            origin.withOffset(CGVector(dx: frame.midX + offset.dx, dy: frame.midY + offset.dy)).tap()
            XCTAssertTrue(
                opens.waitForExistence(timeout: FestivalApp.budget(3)),
                "\(id) \(frame) ignored a tap at (\(Int(offset.dx)), \(Int(offset.dy))) pt from its centre",
                file: file, line: line
            )
            close()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: opens)
            XCTAssertEqual(
                XCTWaiter.wait(for: [gone], timeout: FestivalApp.budget(5)), .completed,
                "\(id) destination stayed open", file: file, line: line
            )
            RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(0.6)))
        }
    }

    /// Any row of the open Quick Links menu.
    @MainActor
    private func quickLinksRow(in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fst.quick-links.item.'")).firstMatch
    }

    /// Close the Quick Links menu by tapping away from it; the dismissing tap is
    /// consumed. A legacy sheet, or a floating tool's choices sheet, closes with its close
    /// button.
    @MainActor
    private static func closeQuickLinks(in app: XCUIApplication) {
        let close = app.buttons["fst.quick-links.close"]
        let inlineClose = app.buttons["fst.page-tools.menu.close"]
        if close.exists {
            close.tap()
        } else if inlineClose.exists {
            inlineClose.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).tap()
        }
    }

    /// Switch Songs to the Year sort, whose sections bring Quick Links.
    @MainActor
    private func chooseYearSort(in app: XCUIApplication) throws {
        app.buttons["fst.songs.sort"].tap()
        let year = app.buttons.matching(identifier: "fst.songs.sort.mode")
            .matching(NSPredicate(format: "label == %@", "Year")).firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 10))
        year.tap()
        app.buttons["fst.songs.sort.done"].tap()
        guard app.buttons["fst.quick-links.open"].waitForExistence(timeout: 5) else {
            throw XCTSkip("Fixture catalogue has one Year section; Quick Links stays hidden.")
        }
    }

    /// Restore the default sort for later journeys sharing the simulator.
    @MainActor
    private func resetSort(in app: XCUIApplication) {
        guard app.state == .runningForeground else { return }
        let sort = app.buttons["fst.songs.sort"]
        guard sort.waitForExistence(timeout: 3) else { return }
        sort.tap()
        let reset = app.buttons["fst.songs.sort.reset"]
        if reset.waitForExistence(timeout: 5) { reset.tap() }
        app.buttons["fst.songs.sort.done"].tap()
    }
}
