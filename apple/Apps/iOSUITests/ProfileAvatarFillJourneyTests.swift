import XCTest

/// Issue #311: on iOS/iPadOS 26 the selected player's avatar fills its whole top-bar
/// circle, with no Liquid Glass ring or outline around it.
///
/// Each step screenshots the app and measures the avatar with ``ProfileAvatarPixels``:
/// the blue-to-purple disc must be the 44 pt circle of a bar glass item (round, not
/// clipped), centred in the profile button where the system glass circle sat, and the
/// band just outside it must be no lighter than the bar farther out. The pre-#311
/// rendering (a 30 pt outlined disc in a 44 pt glass circle) measures 30 pt with a ~16
/// lift, so it fails both checks; hiding the glass without the overhang leaves the disc
/// 10 pt too far from the trailing edge.
///
/// iPhone (`FestivalMobileUITests`): Songs (tab root), Item Shop pushed from the drawer,
/// the Search tab (which by design has no account items, so no avatar and no ring) and
/// the page shown again after closing Search. iPad (`FestivalMobileIPadUITests`): Songs,
/// Item Shop and the Search page, chosen from the flyout. Runs against the loopback
/// fixture (`tools/mock_service.py`; `TEST_RUNNER_FST_SONGS_SCROLL_FIXTURE_URL` or
/// `127.0.0.1:8765`) on a flat backdrop, so no artwork shows through the bar.
final class ProfileAvatarFillJourneyTests: XCTestCase {
    /// Accepted avatar diameter in points: the 44 pt bar glass item, ±2 pt antialiasing.
    private static let diameter: ClosedRange<CGFloat> = 42...46
    /// Largest median brightening of the band just outside the disc (0–255); the pre-#311
    /// glass ring measured 15.8 on iPhone 17 Pro, the borderless avatar −2…2.
    private static let maximumRimLift = 8.0

    /// The disc's trailing gap to the window edge, where the glass circle sat: 16 pt on
    /// iPhone 17 Pro and 10 pt on iPad Pro 11 (iOS 26.5). Hidden glass without the
    /// overhang adds 10 pt.
    @MainActor
    private static var trailingGap: ClosedRange<CGFloat> {
        UIDevice.current.userInterfaceIdiom == .pad ? 6...14 : 12...20
    }

    override func setUpWithError() throws {
        guard #available(iOS 26.0, *) else {
            throw XCTSkip("Bar items have no Liquid Glass circle before iOS 26.")
        }
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func fixtureApp() -> XCUIApplication {
        FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"]
                ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "fixture-player-1:Fixture Player 1",
            "FST_DEBUG_FLAT_BACKDROP": "1",
        ])
    }

    // MARK: - Journey

    /// The avatar fills its circle on a tab root, Item Shop and Search (iPad), and the
    /// iPhone Search tab shows no avatar.
    @MainActor
    func testSelectedAvatarFillsItsCircleWithoutGlassRing() throws {
        let app = fixtureApp()
        app.launch()
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { WindowResize.fill(app) }
        XCTAssertTrue(
            app.descendants(matching: .any)["fst.songs.list"].waitForExistence(timeout: 20)
                || app.buttons["fst.songs.sort"].waitForExistence(timeout: 5),
            "Songs did not load"
        )
        try assertAvatarFillsCircle(in: app, "Songs (tab root)")

        chooseInDrawer(app, "shop")
        XCTAssertTrue(app.navigationBars["Item Shop"].waitForExistence(timeout: 15), "Item Shop did not open")
        try assertAvatarFillsCircle(in: app, isPad ? "Item Shop" : "Item Shop (pushed)")

        if isPad {
            chooseInDrawer(app, "search")
            XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 10), "Search did not open")
            try assertAvatarFillsCircle(in: app, "Search")
            return
        }
        let search = app.tabBars.buttons.matching(NSPredicate(format: "label == %@", "Search")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10), "Search tab missing")
        search.tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 10), "Search tab did not open")
        // The transient phone Search tab has no account items (`GlobalSearchTab`), so
        // there is no avatar, and so no ring, to show.
        XCTAssertFalse(
            app.navigationBars["Search"].buttons["fst.shell.profile"].exists,
            "The Search tab gained a profile item: measure it here"
        )
        let close = app.buttons.matching(NSPredicate(format: "label == %@", "Close")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Search Close missing")
        close.tap()
        XCTAssertTrue(app.navigationBars["Item Shop"].waitForExistence(timeout: 10), "Closing Search lost Item Shop")
        try assertAvatarFillsCircle(in: app, "Item Shop after Search")
    }

    // MARK: - Helpers

    /// Open the drawer (iPhone) or flyout (iPad) and choose a destination.
    ///
    /// - Parameters:
    ///   - app: The running app.
    ///   - id: Drawer row suffix, e.g. `shop` or `search`.
    @MainActor
    private func chooseInDrawer(_ app: XCUIApplication, _ id: String) {
        let open = app.buttons["fst.shell.drawer.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Drawer button missing")
        open.tap()
        let row = app.buttons["fst.shell.drawer.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Drawer row \(id) missing")
        row.tap()
    }

    /// Screenshot the app and require the avatar to fill its 44 pt circle with no rim.
    ///
    /// - Parameters:
    ///   - app: The running app with a selected player.
    ///   - place: Page name for failure messages and the screenshot attachment.
    /// - Throws: A missing screenshot bitmap or avatar.
    @MainActor
    private func assertAvatarFillsCircle(
        in app: XCUIApplication, _ place: String, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let profile = app.navigationBars.buttons.matching(identifier: "fst.shell.profile").firstMatch
        XCTAssertTrue(profile.waitForExistence(timeout: 10), "\(place): profile missing", file: file, line: line)
        XCTAssertEqual(profile.label, "Profile: Fixture Player 1", file: file, line: line)
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: profile)
        XCTAssertEqual(
            XCTWaiter.wait(for: [hittable], timeout: 5), .completed, "\(place): profile not hittable",
            file: file, line: line
        )
        // Let a push, tab switch or flyout close finish morphing the bar items.
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let frame = profile.frame
        let window = app.frame
        let shot = app.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = "#311 avatar – \(place)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(shot.image.cgImage, file: file, line: line)
        let pixels = try XCTUnwrap(ProfileAvatarPixels(image: image, pointWidth: window.width), file: file, line: line)
        let avatar = try XCTUnwrap(
            pixels.measure(around: frame.offsetBy(dx: -window.minX, dy: -window.minY)),
            "\(place): no avatar pixels near \(frame)", file: file, line: line
        )
        let center = CGPoint(x: avatar.center.x + window.minX, y: avatar.center.y + window.minY)
        XCTAssertTrue(
            Self.diameter.contains(avatar.width) && Self.diameter.contains(avatar.height),
            "\(place): avatar is \(avatar.width)×\(avatar.height) pt, not the 44 pt bar circle",
            file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            abs(avatar.width - avatar.height), 2, "\(place): avatar is clipped or not round", file: file, line: line
        )
        XCTAssertLessThanOrEqual(
            avatar.rimLift, Self.maximumRimLift,
            "\(place): a lighter ring (\(avatar.rimLift)) surrounds the avatar: exposed glass or outline",
            file: file, line: line
        )
        XCTAssertTrue(
            frame.insetBy(dx: -2, dy: -2).contains(center),
            "\(place): avatar centre \(center) is outside its button \(frame)", file: file, line: line
        )
        // Where page tools or the toolbar search field follow the avatar (iPad Item
        // Shop as a flyout root, the iPad Search page), the glass circle's position
        // is not the window edge.
        let followers = app.navigationBars.buttons.allElementsBoundByIndex
            + app.searchFields.allElementsBoundByIndex
            + app.textFields.allElementsBoundByIndex
        let trailing = followers.contains {
            $0.frame.minX >= frame.maxX && abs($0.frame.midY - frame.midY) < 22
        }
        guard !trailing else { return }
        let gap = window.maxX - (center.x + avatar.width / 2)
        XCTAssertTrue(
            Self.trailingGap.contains(gap),
            "\(place): avatar sits \(gap) pt from the trailing edge, not where the glass circle was",
            file: file, line: line
        )
    }
}
