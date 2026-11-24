import UIKit
import XCTest

// MARK: - PlayerProfileLinksJourneyTests

/// Player-page push stability and stat-tile links (Lane AP3) against the loopback
/// fixture (`tools/mock_service.py` on `127.0.0.1:8765`).
///
/// Fixture facts used: the catalogue has `fixture-pulse` and `fixture-orbit`;
/// `fixture-player-2` has Lead full combos on both and one non-FC Drums score on
/// `fixture-pulse` (so Drums Songs Played filters Songs down to that one row).
final class PlayerProfileLinksJourneyTests: XCTestCase {
    // MARK: Launch

    /// Anonymous fixture app on the Leaderboards tab.
    @MainActor
    private func anonymousApp() -> XCUIApplication {
        FestivalApp.launch([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "leaderboards",
        ])
    }

    /// Fixture app with `fixture-player-2` selected, starting on Songs.
    @MainActor
    private func selectedApp() -> XCUIApplication {
        FestivalApp.launch([
            "FST_API_BASE_URL": "http://127.0.0.1:8765",
            "FST_DEBUG_PROFILE": "fixture-player-2:Fixture Player 2",
            "FST_DEBUG_TAB": "songs",
        ])
    }

    // MARK: Helpers

    /// Element by accessibility identifier, of any type.
    @MainActor
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Push a player page from the Lead card of the Leaderboards overview.
    @MainActor
    private func pushPlayer(_ accountId: String, in app: XCUIApplication) {
        XCTAssertTrue(app.navigationBars["Leaderboards"].waitForExistence(timeout: 15))
        let card = element("fst.leaderboards.card.Solo_Guitar", in: app)
        let row = card.buttons["fst.rankings.row.\(accountId)"]
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
    }

    /// Scroll the page in short, momentum-free drags until a tile sits clear of the
    /// navigation and tab bars, then tap it (fast swipes overshoot a whole card).
    @MainActor
    private func tapTile(_ identifier: String, in app: XCUIApplication) {
        let tile = element(identifier, in: app)
        XCTAssertTrue(tile.waitForExistence(timeout: 15), "\(identifier) never appeared")
        let window = app.windows.firstMatch.frame
        func clear() -> Bool {
            tile.isHittable && tile.frame.minY > window.minY + 140 && tile.frame.maxY < window.maxY - 140
        }
        var attempts = 0
        while !clear() && attempts < 20 {
            let below = tile.frame.midY > window.midY
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.7 : 0.4))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: below ? 0.45 : 0.65))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            attempts += 1
        }
        XCTAssertTrue(clear(), "\(identifier) never scrolled into view: \(tile.frame)")
        tile.tap()
    }

    /// Return to a root tab if needed, then open Statistics from the drawer on phone.
    ///
    /// - Parameter app: Running fixture app with a selected player.
    @MainActor
    private func reopenStatistics(in app: XCUIApplication) {
        let songs = SongsUITestSupport.rootControl("Songs", app: app)
        if songs.waitForExistence(timeout: 3), songs.isHittable { songs.tap() }
        SongsUITestSupport.openStatistics(in: app)
    }

    // MARK: Push stability

    /// The push lands on a page whose toolbar and tiles do not move once shown: the
    /// identity button is in the bar from the start, and the late global-rank and
    /// rank-history reads fill reserved space instead of growing cards.
    @MainActor
    func testPushToProfileKeepsFramesStableAfterSettle() throws {
        continueAfterFailure = false
        let app = anonymousApp()
        pushPlayer("fixture-player-1", in: app)

        let select = app.buttons["fst.player.select"]
        let pending = app.buttons["fst.player.select.pending"]
        XCTAssertTrue(
            select.waitForExistence(timeout: 5) || pending.exists,
            "The identity button was not in the toolbar during the push"
        )

        let watched = [
            "fst.player.stat.overview.songs-played",
            "fst.player.stat.Solo_Guitar.songs-played",
            "fst.player.stat.Solo_Guitar.global-rank",
            "fst.player.stat.Solo_Guitar.percentile",
        ]
        for identifier in watched {
            XCTAssertTrue(element(identifier, in: app).waitForExistence(timeout: 15), "\(identifier) missing")
        }
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        // Past the staggered fade-ins (≤ ~0.8 s for these sections).
        Thread.sleep(forTimeInterval: 1.5)
        let settled = watched.map { element($0, in: app).frame } + [select.frame]
        Thread.sleep(forTimeInterval: 2.5)
        let later = watched.map { element($0, in: app).frame } + [select.frame]
        XCTAssertEqual(settled, later, "Player page elements moved after settling")
        XCTAssertTrue(select.isEnabled)
    }

    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    /// The same viewed player covers the rankings while the Duo folds and rotates.
    /// Instrument sections stack on the cover, pair flat and clear the hinge in book
    /// pose. Back restores the original book split; Close clears only the board selection.
    @MainActor
    func testDuoProfileKeepsCoveredRankingsThroughFoldAndRotation() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["FST_DUO_SPLIT_TEST"] == "1"
            && (environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Opt in on a dedicated iPhone Duo with the loopback fixture")
        guard #available(iOS 27.3, *) else { throw XCTSkip("Needs the iOS 27.3 hinge runtime") }
        let origin = SongsUITestSupport.fixtureURL
        let url = URLComponents(string: origin)
        try XCTSkipUnless(url?.scheme == "http" && url?.host == "127.0.0.1" && url?.port != nil,
                          "This journey requires a loopback fixture")
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let hinge = try XCTUnwrap(device.hinge)
        let originalAngle = hinge.angle
        let originalOrientation = device.orientation
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": origin,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "leaderboards",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", UIContentSizeCategory.large.rawValue]
        defer {
            app.terminate()
            device.orientation = originalOrientation
            hinge.angle = originalAngle
        }

        device.orientation = .portrait
        hinge.angle = .pi
        app.launch()
        let window = app.windows.firstMatch
        let landscape = CGSize(width: 951, height: 669)
        func waitForPose(_ phase: String, _ angle: CGFloat, _ size: CGSize) {
            XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 15) {
                abs(hinge.angle - angle) < 0.05 && window.frame.size == size
            }, "\(phase): expected \(angle) and \(size); got \(hinge.angle) and \(window.frame)")
        }
        waitForPose("flat", .pi, landscape)
        hinge.angle = .pi / 2
        waitForPose("book", .pi / 2, landscape)

        let selectionID = "fst.leaderboards.card.Solo_Guitar.view-all"
        let selections = app.buttons.matching(identifier: selectionID)
        let selection = selections.firstMatch
        XCTAssertTrue(selection.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertTrue(selection.isHittable && !selection.isSelected)
        selection.tap()
        let close = app.buttons[SplitBandUITestSupport.closeID]
        XCTAssertTrue(SplitBandUITestSupport.waitForPane(app, open: true))
        let bookPane = try XCTUnwrap(SplitBandUITestSupport.trailingPane(app))
        XCTAssertGreaterThan(bookPane.minX, window.frame.midX)
        XCTAssertTrue(FeedbackJourney.waitUntil { selection.exists && selection.isSelected })
        let rows = app.buttons.matching(identifier: "fst.rankings.row.fixture-player-1")
        func row(in pane: CGRect) -> XCUIElement? {
            rows.allElementsBoundByIndex.first { pane.contains($0.frame) && $0.isHittable }
        }
        XCTAssertTrue(FeedbackJourney.waitUntil { row(in: bookPane) != nil })
        let boardRow = try XCTUnwrap(row(in: bookPane))
        XCTAssertTrue(boardRow.isHittable)
        XCTAssertGreaterThanOrEqual(boardRow.frame.height, 43.5)
        XCTAssertTrue(boardRow.label.contains("Fixture Player 1"))
        let originalRowFrame = boardRow.frame
        let originalRowLabel = boardRow.label
        boardRow.tap()

        let stat = element("fst.player.stat.overview.songs-played", in: app)
        let select = app.buttons.matching(NSPredicate(
            format: "identifier IN %@", ["fst.player.select", "fst.player.select.rail"]
        ))
        let lead = app.descendants(matching: .any).matching(identifier: "fst.player.instrument.Solo_Guitar")
        let bass = app.descendants(matching: .any).matching(identifier: "fst.player.instrument.Solo_Bass")
        let subtitleText = "A quick look at Fixture Player 1's overall Festival statistics per instrument."
        let subtitles = app.staticTexts.matching(NSPredicate(format: "label == %@", subtitleText))
        func checkProfile(_ phase: String, angle: CGFloat, size: CGSize) {
            waitForPose(phase, angle, size)
            XCTAssertTrue(stat.waitForExistence(timeout: FestivalApp.budget(15)), "\(phase): no profile content")
            XCTAssertTrue(select.firstMatch.waitForExistence(timeout: FestivalApp.budget(10)),
                          "\(phase): no viewed-player action")
            XCTAssertEqual(select.count, 1)
            XCTAssertTrue(select.firstMatch.isEnabled)
            var instrumentFrames = ""
            XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 8) {
                guard lead.count == 1, bass.count == 1 else { return false }
                let first = lead.firstMatch.frame
                let second = bass.firstMatch.frame
                instrumentFrames = "Lead \(first), Bass \(second)"
                guard first.width > 0, second.width > 0 else { return false }
                if angle == 0 {
                    return abs(first.minX - second.minX) <= 1 && abs(first.width - second.width) <= 1
                        && first.width > size.width * 0.65 && second.minY > first.maxY
                }
                guard abs(first.minY - second.minY) <= 1, second.minX > first.maxX else { return false }
                if angle < .pi {
                    return first.maxX <= window.frame.midX - 10 && second.minX >= window.frame.midX + 10
                }
                return abs(first.width - second.width) <= 1
            }, "\(phase): unexpected instrument section layout; \(instrumentFrames)")
            let book = angle > 0 && angle < .pi
            let wraps = book || angle == 0
            var subtitleFrame = CGRect.zero
            XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 8) {
                guard subtitles.count == 1 else { return false }
                subtitleFrame = subtitles.firstMatch.frame
                return subtitleFrame.height > 0 && (subtitleFrame.height >= 35) == wraps
                    && (!book || subtitleFrame.maxX <= window.frame.midX - 10)
                    && abs(lead.firstMatch.frame.minY - subtitleFrame.maxY - 20) <= 1
            }, "\(phase): unexpected Instrument Statistics subtitle frame \(subtitleFrame)")
            let panel = angle == 0 ? (short: 1398, long: 2034) : (short: 2006, long: 2852)
            var observed = ""
            XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 8) {
                let shot = XCUIScreen.main.screenshot()
                guard let bitmap = shot.image.cgImage else { return false }
                observed = "\(bitmap.width)×\(bitmap.height)"
                guard min(bitmap.width, bitmap.height) == panel.short,
                      max(bitmap.width, bitmap.height) == panel.long else { return false }
                let rotated = (bitmap.width > bitmap.height) != (size.width > size.height)
                let orientation: CGImagePropertyOrientation = rotated ? .right : .up
                let lines = RecognizedText.lines(in: shot, orientation: orientation)
                observed += ": \(lines.map(\.text))"
                guard lines.contains(where: { RecognizedText.showsWhole("Fixture Player 1", in: $0.text) }),
                      lines.contains(where: { RecognizedText.showsWhole("Songs Played", in: $0.text) }) else { return false }
                let imageSize = shot.image.size
                let scaleX = (rotated ? imageSize.height : imageSize.width) / size.width
                let scaleY = (rotated ? imageSize.width : imageSize.height) / size.height
                let subtitleLines = lines.filter {
                    $0.frame.midY / scaleY >= subtitleFrame.minY && $0.frame.midY / scaleY <= subtitleFrame.maxY
                }
                let painted = subtitleLines.map(\.text).joined(separator: " ")
                guard subtitleLines.count == (wraps ? 2 : 1),
                      RecognizedText.showsWhole(subtitleText, in: painted),
                      RecognizedText.showsWhole("per instrument", in: painted),
                      !book || subtitleLines.allSatisfy({ $0.frame.maxX / scaleX < size.width / 2 })
                else { return false }
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = "duo-profile-\(phase)-framebuffer"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return true
            }, "\(phase): expected the viewed player and complete subtitle painted on the active panel; saw \(observed)")
            let pane = SplitBandUITestSupport.trailingPane(app)
            let behind = (selections.allElementsBoundByIndex + rows.allElementsBoundByIndex)
                .map { (id: $0.identifier, frame: $0.frame, hittable: $0.isHittable) }
            let tree = XCTAttachment(string: "angle=\(hinge.angle); window=\(window.frame); pane=\(String(describing: pane))"
                + "\n\(instrumentFrames)"
                + "\nbehind=\(behind)\n" + app.debugDescription)
            tree.name = "duo-profile-\(phase)-accessibility"
            tree.lifetime = .keepAlways
            add(tree)
            XCTAssertFalse(behind.contains { $0.hittable }, "\(phase): rankings can be tapped through the profile")
            XCTAssertFalse(close.exists && close.isHittable, "\(phase): a pushed profile has Back, not Close")
            if size == landscape {
                XCTAssertTrue(pane?.contains(CGPoint(x: window.frame.midX, y: window.frame.midY)) == true,
                              "\(phase): the profile must cover the split")
            } else {
                XCTAssertNil(pane, "\(phase): the profile must be pushed in a single stack")
            }
        }

        checkProfile("book", angle: .pi / 2, size: landscape)
        hinge.angle = 0
        checkProfile("cover", angle: 0, size: CGSize(width: 466, height: 678))
        device.orientation = .landscapeLeft
        hinge.angle = .pi
        checkProfile("inner-portrait", angle: .pi, size: CGSize(width: 669, height: 951))
        device.orientation = .portrait
        checkProfile("inner-landscape-flat", angle: .pi, size: landscape)
        hinge.angle = .pi / 2
        checkProfile("book-return", angle: .pi / 2, size: landscape)

        let railBack = app.buttons["BackButton"].firstMatch
        let back = railBack.exists && railBack.isHittable ? railBack : app.navigationBars.buttons.firstMatch
        XCTAssertTrue(back.exists && back.isHittable, "The viewed player needs a native Back")
        back.tap()
        XCTAssertTrue(FeedbackJourney.waitUntil { selection.exists && selection.isSelected },
                      "Back must restore the selected rankings")
        XCTAssertTrue(selection.isHittable)
        XCTAssertFalse(stat.exists)
        let restoredPane = try XCTUnwrap(SplitBandUITestSupport.trailingPane(app))
        XCTAssertEqual(restoredPane.minX, bookPane.minX, accuracy: 1)
        XCTAssertTrue(FeedbackJourney.waitUntil { row(in: restoredPane) != nil })
        let restoredRow = try XCTUnwrap(row(in: restoredPane))
        XCTAssertTrue(restoredRow.isHittable)
        XCTAssertEqual(restoredRow.label, originalRowLabel)
        XCTAssertEqual(restoredRow.frame.minX, originalRowFrame.minX, accuracy: 1)
        XCTAssertEqual(restoredRow.frame.minY, originalRowFrame.minY, accuracy: 1)
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(close.label, "Close")
        close.tap()
        XCTAssertTrue(SplitBandUITestSupport.waitForPane(app, open: false))
        XCTAssertTrue(selection.isHittable && !selection.isSelected)
    }
    #endif

    // MARK: Viewed player: select first

    /// A viewed (unselected) player's Songs tile selects that player first (web
    /// `withProfileSwitch`), then shows Songs filtered to the chart.
    @MainActor
    func testViewedPlayerSongsTileSelectsThenFiltersSongs() throws {
        continueAfterFailure = false
        let app = anonymousApp()
        pushPlayer("fixture-player-2", in: app)
        XCTAssertTrue(app.buttons["fst.player.select"].waitForExistence(timeout: 15))

        tapTile("fst.player.stat.Solo_Drums.songs-played", in: app)
        XCTAssertTrue(element("fst.songs.row.fixture-pulse", in: app).waitForExistence(timeout: 15))
        XCTAssertFalse(element("fst.songs.row.fixture-orbit", in: app).exists, "Drums filter kept an unplayed song")
        app.buttons["fst.shell.drawer.open"].tap()
        XCTAssertTrue(
            app.buttons["fst.shell.drawer.statistics"].waitForExistence(timeout: 10),
            "The viewed player was not selected before filtering"
        )
        app.buttons["fst.shell.drawer.close"].tap()
    }

    // MARK: Selected player: every link

    /// A long Full Combos value keeps the first Statistics row at the height of the
    /// second row at Large; at AX5 the grid grows without losing the spoken value.
    @MainActor
    func testLongFullComboStatFitsAndScales() {
        continueAfterFailure = false
        var largeHeight: CGFloat = 0
        for size in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let app = FestivalApp.makeApp([
                "FST_API_BASE_URL": SongsUITestSupport.fixtureURL,
                "FST_DEBUG_PROFILE": "fixture-stat-width:Fixture Stat Width",
                "FST_DEBUG_TAB": "statistics",
            ])
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", size.rawValue]
            app.launch()
            let played = app.buttons["fst.player.stat.overview.songs-played"]
            let combos = app.buttons["fst.player.stat.overview.full-combos"]
            XCTAssertTrue(combos.waitForExistence(timeout: FestivalApp.budget(20)))
            XCTAssertEqual(combos.label, "Full Combos")
            XCTAssertEqual(combos.value as? String, "2,468 (95.2%)")
            XCTAssertTrue(combos.isHittable)
            XCTAssertGreaterThanOrEqual(combos.frame.height, 44)
            XCTAssertGreaterThanOrEqual(combos.frame.width, 44)
            if size == .large {
                let gold = element("fst.player.stat.overview.gold-stars", in: app)
                XCTAssertTrue(gold.exists)
                XCTAssertEqual(combos.frame.minY, played.frame.minY, accuracy: 1)
                XCTAssertGreaterThan(combos.frame.minX, played.frame.minX)
                XCTAssertEqual(combos.frame.height, gold.frame.height, accuracy: 2)
                largeHeight = combos.frame.height
            } else {
                XCTAssertGreaterThan(combos.frame.minY, played.frame.minY)
                XCTAssertGreaterThan(combos.frame.height, largeHeight + 12)
            }
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = "Statistics Full Combos \(size.rawValue)"
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
    }

    /// On the selected player's Statistics page each linked tile lands on its target:
    /// Full Combos → Songs, Lead Global Rank → Lead Rankings, Drums Best Rank → Song
    /// Detail. Plain tiles are not buttons.
    @MainActor
    func testSelectedPlayerStatLinksReachTheirPages() throws {
        continueAfterFailure = false
        let app = selectedApp()
        SongsUITestSupport.openStatistics(in: app)

        let goldStars = element("fst.player.stat.overview.gold-stars", in: app)
        XCTAssertTrue(goldStars.waitForExistence(timeout: 20))
        XCTAssertNotEqual(goldStars.elementType, .button, "Gold Stars has no web link")

        tapTile("fst.player.stat.overview.full-combos", in: app)
        XCTAssertTrue(element("fst.songs.row.fixture-pulse", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("fst.songs.row.fixture-orbit", in: app).exists)

        reopenStatistics(in: app)
        tapTile("fst.player.stat.Solo_Guitar.global-rank", in: app)
        XCTAssertTrue(app.navigationBars["Lead Rankings"].waitForExistence(timeout: 15))

        reopenStatistics(in: app)
        tapTile("fst.player.stat.Solo_Drums.best-rank", in: app)
        XCTAssertTrue(element("fst.song-detail.intensity", in: app).waitForExistence(timeout: 15))
    }

    // MARK: Percentile table

    /// A percentile table row opens Songs filtered to that band (web
    /// `instPercentileBucketUpdater`); the row is a button with the band's identifier.
    @MainActor
    func testPercentileRowOpensSongsFilteredToItsBand() throws {
        continueAfterFailure = false
        let app = selectedApp()
        SongsUITestSupport.openStatistics(in: app)
        let row = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "fst.player.percentile-row.Solo_Guitar.")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20), "No Lead percentile row")
        tapTile(row.identifier, in: app)
        let songRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row.")).firstMatch
        XCTAssertTrue(songRow.waitForExistence(timeout: 15), "Songs did not open filtered")
        XCTAssertTrue(SongsUITestSupport.rootControl("Songs", app: app).isSelected, "Songs is not the selected tab")
    }
}
