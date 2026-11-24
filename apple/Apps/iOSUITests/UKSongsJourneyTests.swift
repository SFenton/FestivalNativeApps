import UIKit
import XCTest

// MARK: - Songs and Item Shop (UIKit port parity and accessibility)

/// Songs and Item Shop identifiers, labels, traits, 44 pt targets and AX5 growth, written
/// against what both front ends must expose, so the same file runs against the SwiftUI app and
/// the UIKit port (`python3 tools/ios_sim.py uitest --app uikit --only UKSongsJourneyTests`).
/// The port-specific rules (one combined row element, child stops only while VoiceOver is
/// off) are in `.agents/platforms/apple/uikit-port.md`. Loopback fixture only.
final class UKSongsJourneyTests: XCTestCase {
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue

    @MainActor
    private func fixtureApp(profile: Bool = false, size: String? = nil, route: String? = nil) -> XCUIApplication {
        var env = [
            "FST_API_BASE_URL": SongsUITestSupport.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_STILL_BACKGROUND": "1",
            "FST_UI_TEST_RESET_SONG_CARDS": "1",
        ]
        if profile { env["FST_DEBUG_PROFILE"] = "fixture-player-1:Fixture Player 1" }
        if let route { env["FST_DEBUG_ROUTE"] = route }
        let app = FestivalApp.makeApp(env)
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        return app
    }

    @MainActor
    private func assertTarget(_ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertGreaterThanOrEqual(element.frame.height, 43.5, "\(name) is shorter than 44 pt", file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width, 43.5, "\(name) is narrower than 44 pt", file: file, line: line)
    }

    // MARK: Songs

    /// Damaged preferences block the catalogue until Reset, which stays reachable at AX5.
    @MainActor
    func testSavedScoreFilterRecoveryCentresInTheSongsPane() throws {
        continueAfterFailure = false
        var standardHeights: [CGFloat] = []
        for size in [UIContentSizeCategory.large.rawValue, Self.ax5] {
            let app = fixtureApp(profile: true, size: size)
            app.launchEnvironment["FST_DEBUG_TAB"] = "songs"
            app.launchEnvironment["FST_DEBUG_FIRST_RUN"] = "off"
            app.launchEnvironment["FST_DEBUG_WHATS_NEW"] = "off"
            app.launchEnvironment["FST_UI_TEST_CORRUPT_SCORE_FILTER"] = "1"
            app.launch()
            defer { app.terminate() }

            let pane = app.scrollViews["fst.songs.filter-invalid"]
            let heading = pane.staticTexts["Saved song filters unavailable"]
            let detail = pane.staticTexts["The saved song filters could not be read. Reset them to continue."]
            let reset = pane.buttons["fst.songs.filter-reset-invalid"]
            let orbit = app.buttons["fst.songs.row.fixture-orbit"]
            XCTAssertTrue(heading.waitForExistence(timeout: FestivalApp.budget(15)))
            XCTAssertTrue(detail.exists)
            XCTAssertTrue(reset.exists)
            XCTAssertFalse(orbit.exists)
            XCTAssertEqual(reset.label, "Reset saved filters")
            XCTAssertTrue(reset.isEnabled)
            for element in [heading, detail, reset] {
                XCTAssertEqual(element.frame.midX, pane.frame.midX, accuracy: 1)
            }
            XCTAssertLessThan(heading.frame.maxY, detail.frame.minY)
            XCTAssertLessThan(detail.frame.maxY, reset.frame.minY)
            assertTarget(reset, "Reset saved filters")
            var heights: [CGFloat] = []
            for element in [heading, detail, reset] {
                for _ in 0..<3 where !pane.frame.insetBy(dx: -1, dy: -1).contains(element.frame) {
                    let visible = pane.frame
                    let distance = min(visible.height * 0.65, max(-visible.height * 0.65, element.frame.midY - visible.midY))
                    let centre = pane.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    let start = centre.withOffset(CGVector(dx: 0, dy: distance / 2))
                    let end = centre.withOffset(CGVector(dx: 0, dy: -distance / 2))
                    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.25)
                }
                XCTAssertTrue(pane.frame.insetBy(dx: -1, dy: -1).contains(element.frame),
                              "\(size): \(element.label) at \(element.frame) does not fit in \(pane.frame)")
                let reading = RecognizedText.recognize(element, label: element.label, frame: element.frame)
                XCTAssertTrue(RecognizedText.showsWhole(element.label, in: reading.text),
                              "\(size): \(element.label) paints as \(reading.text ?? "unreadable")")
                heights.append(try XCTUnwrap(reading.lineHeight))
            }
            if size == Self.ax5 {
                for (ax5, standard) in zip(heights, standardHeights) {
                    XCTAssertGreaterThan(ax5, standard * RecognizedText.minimumGrowth)
                }
            } else {
                standardHeights = heights
            }
            XCTAssertTrue(reset.isHittable)
            SongsUITestSupport.record(app, name: "saved-score-filter-recovery-\(size)")
            reset.tap()
            XCTAssertTrue(orbit.waitForExistence(timeout: FestivalApp.budget(15)))
            XCTAssertFalse(pane.exists)
        }
    }

    /// Opens Filter directly or through the folded Duo's native toolbar menu.
    @MainActor
    private func openFilter(in app: XCUIApplication) {
        let direct = app.buttons["fst.songs.filter"]
        if direct.isHittable {
            direct.tap()
        } else {
            let overflow = app.buttons["BottomOverflowBarButtonItem"]
            XCTAssertTrue(overflow.waitForExistence(timeout: 10))
            overflow.tap()
            let filter = app.buttons["Filter"]
            XCTAssertTrue(filter.waitForExistence(timeout: 10))
            filter.tap()
        }
        XCTAssertTrue(app.buttons["fst.songs.filter.done"].waitForExistence(timeout: 10))
    }

    /// Each catalogue song is one button named for the song, its artist and its year · length
    /// line; the Sort and Filter tools state their values.
    @MainActor
    func testSongsRowsAndToolsExposeNamesAndValues() throws {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        if !pulse.waitForExistence(timeout: FestivalApp.budget(20)) {
            let dump = app.debugDescription
            let all = dump.components(separatedBy: "\n")
            let start = all.firstIndex { $0.contains("CollectionView") } ?? 0
            XCTFail("Row missing. Hierarchy: \(all[start..<min(all.count, start + 14)].map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: " // "))")
            return
        }
        XCTAssertTrue(pulse.label.contains("Fixture Pulse"), "Row label: \(pulse.label)")
        XCTAssertTrue(pulse.label.contains(" · "), "Row label lacks the artist · year · length line: \(pulse.label)")
        XCTAssertTrue(pulse.isHittable)
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        XCTAssertEqual(sort.label, "Sort")
        XCTAssertEqual(sort.value as? String, "Title, ascending")
        let filter = app.buttons["fst.songs.filter"]
        XCTAssertTrue(filter.exists)
        XCTAssertEqual(filter.label, "Filter Songs")
        XCTAssertEqual(filter.value as? String, "No filters")
        assertTarget(sort, "Sort")
        assertTarget(filter, "Filter")
    }

    /// Songs keeps the shared title scrim across the window without obstructing its first row.
    @MainActor
    func testSongsTitleScrimKeepsFirstRowReachable() throws {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_DEBUG_FLAT_BACKDROP"] = "1"
        app.launchEnvironment["FST_DEBUG_FIRST_RUN"] = "off"
        app.launchEnvironment["FST_DEBUG_WHATS_NEW"] = "off"
        app.launchArguments += [
            "-fst.accessibility.reduceMotion", "YES",
            "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a phone or the Duo cover")
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(orbit.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(orbit.label.hasPrefix("Fixture Orbit"))
        XCTAssertTrue(orbit.isHittable && orbit.isEnabled)
        assertTarget(orbit, "Fixture Orbit")
        try SongsUITestSupport.assertPageScrim(in: app, window: window)

        orbit.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap()
        let intensity = app.descendants(matching: .any)["fst.song-detail.intensity"]
        XCTAssertTrue(intensity.waitForExistence(timeout: FestivalApp.budget(15)))
    }

    /// An empty selected-band index clears the in-flight status without leaving Songs.
    @MainActor
    func testSelectedBandLoadingClearsWhenItsEmptyIndexArrives() async throws {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_DEBUG_BAND"] =
            "Band_Duets/fixture-player-1:fixture-band-empty/Fixture Empty Band"
        app.launchArguments += ["-fst.accessibility.reduceMotion", "YES"]
        try await setEmptyBandIndexPhase("hold")
        app.launch()
        defer { app.terminate() }

        let rows = ["fixture-orbit", "fixture-pulse"].map { app.buttons["fst.songs.row.\($0)"] }
        let loadingText = "Loading Fixture Empty Band's scores"
        let pending = rows.map {
            XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", loadingText), object: $0)
        }
        XCTAssertEqual(XCTWaiter.wait(for: pending, timeout: FestivalApp.budget(12)), .completed)
        try await setEmptyBandIndexPhase("release")

        let settled = rows.map {
            XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == YES AND NOT (label CONTAINS %@)", loadingText),
                object: $0
            )
        }
        XCTAssertEqual(XCTWaiter.wait(for: settled, timeout: FestivalApp.budget(8)), .completed,
                       "The empty index must update existing rows without a reload or navigation")
        for (row, title) in zip(rows, ["Fixture Orbit", "Fixture Pulse"]) {
            XCTAssertTrue(row.label.hasPrefix(title), row.label)
            XCTAssertFalse(row.label.contains("Band scores unavailable"), row.label)
            XCTAssertFalse(row.label.contains("Band scores paused"), row.label)
            XCTAssertTrue(row.isHittable)
            assertTarget(row, title)
        }
        let children = app.descendants(matching: .any)
        for song in ["fixture-orbit", "fixture-pulse"] {
            XCTAssertFalse(children["fst.songs.band-summary.\(song)"].exists)
            XCTAssertFalse(children["fst.songs.metadata.score.\(song)"].exists)
        }
    }

    /// Arms or releases the empty synthetic index on the exact loopback fixture used by the app.
    @MainActor
    private func setEmptyBandIndexPhase(_ phase: String) async throws {
        struct Reply: Decodable { let phase: String }
        var control = try XCTUnwrap(URLComponents(string: SongsUITestSupport.fixtureURL))
        try XCTSkipUnless(control.scheme == "http" && control.host == "127.0.0.1" && control.port != nil,
                          "Band-index control requires an owned loopback fixture")
        control.path = "/__fixture__/hold-band-index"
        control.queryItems = [URLQueryItem(name: "phase", value: phase)]
        let (data, response) = try await URLSession.shared.data(from: XCTUnwrap(control.url))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode(Reply.self, from: data).phase, phase)
    }

    /// Resize the same Songs list from compact to flat, book and back without changing its selection.
    @MainActor
    func testWideSongsPutScoredBandInSeparateTrailingCard() throws {
        continueAfterFailure = false
        let app = wideBandApp(size: UIContentSizeCategory.large.rawValue, pose: "folded")
        app.launch()
        defer { app.terminate() }

        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(12)))
        try XCTSkipUnless(song.frame.width >= 600, "Requires an inner-display Duo canvas")
        let bandID = "fst.songs.profile-panel.fixture-pulse.band"
        let children = app.descendants(matching: .any)
        let card = app.staticTexts[bandID]
        let score = "Score 1,234,567"
        func expectInlineScore() {
            let inline = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", score), object: song
            )
            XCTAssertEqual(XCTWaiter.wait(for: [inline], timeout: FestivalApp.budget(8)), .completed)
            XCTAssertFalse(card.exists)
        }
        expectInlineScore()

        DuoWindowSwitch.post("unfolded-landscape")
        XCTAssertTrue(card.waitForExistence(timeout: FestivalApp.budget(8)),
                      "Wide Songs should show the band score in a separate trailing card. Row: \(song.label)")
        XCTAssertEqual(card.label, "Fixture Band, Duos band: Score 1,234,567, Full combo, accuracy 97 percent")
        XCTAssertFalse(song.label.contains(score))
        XCTAssertGreaterThan(card.frame.minX, song.frame.midX)
        XCTAssertLessThanOrEqual(card.frame.maxX, song.frame.maxX)
        let order = children.allElementsBoundByIndex.map(\.identifier)
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: song.identifier)),
                          try XCTUnwrap(order.firstIndex(of: bandID)))
        XCTAssertFalse(children["fst.songs.profile-panel.fixture-orbit.band"].exists)
        XCTAssertFalse(children["fst.songs.metadata.score.fixture-orbit"].exists)
        assertTarget(song, "Fixture Pulse")
        SongsUITestSupport.record(app, name: "wide-songs-band-profile-card")
        let flatFrame = card.frame

        DuoWindowSwitch.post("book")
        let readout = children.matching(identifier: "fst.shell.debug.duo-window").firstMatch
        let book = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH 'book ' AND label CONTAINS 'fold='"), object: readout
        )
        XCTAssertEqual(XCTWaiter.wait(for: [book], timeout: FestivalApp.budget(8)), .completed)
        let fold = try XCTUnwrap(readout.label.components(separatedBy: "fold=").last?.split(separator: " ").first)
        let hingeX = try XCTUnwrap(Double(fold))
        let clearsHinge = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            // Debug book reserves 24 pt; the readout rounds its centre to whole points.
            card.exists && card.frame.minX >= hingeX + 11 && abs(card.frame.maxX - flatFrame.maxX) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [clearsHinge], timeout: FestivalApp.budget(8)), .completed,
                       "Score card \(card.frame) did not clear the book hinge at x=\(hingeX)")
        XCTAssertEqual(card.label, "Fixture Band, Duos band: Score 1,234,567, Full combo, accuracy 97 percent")
        SongsUITestSupport.record(app, name: "book-songs-band-profile-card")

        DuoWindowSwitch.post("unfolded-landscape")
        let returnsToFlat = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            card.exists && abs(card.frame.minX - flatFrame.minX) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [returnsToFlat], timeout: FestivalApp.budget(8)), .completed)

        DuoWindowSwitch.post("folded")
        expectInlineScore()
    }

    /// An inner-display book pose must not replace the readable stacked row at AX5.
    @MainActor
    func testWideSongsKeepBandScoreInlineAtAX5() throws {
        continueAfterFailure = false
        let app = wideBandApp(size: Self.ax5, pose: "book")
        app.launch()
        defer { app.terminate() }

        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(12)))
        try XCTSkipUnless(song.frame.width >= 600, "Requires an inner-display Duo canvas")
        let readout = app.descendants(matching: .any).matching(identifier: "fst.shell.debug.duo-window").firstMatch
        XCTAssertTrue(readout.label.hasPrefix("book ") && readout.label.contains("fold="))
        let inline = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
                                   "Score 1,234,567", "Full combo, accuracy 97 percent"), object: song
        )
        XCTAssertEqual(XCTWaiter.wait(for: [inline], timeout: FestivalApp.budget(8)), .completed)
        XCTAssertFalse(app.staticTexts["fst.songs.profile-panel.fixture-pulse.band"].exists)
        assertTarget(song, "Fixture Pulse")
        SongsUITestSupport.record(app, name: "book-songs-band-inline-ax5")
    }

    /// Each drawn player card is immediately reachable in the book pose, including the first row.
    @MainActor
    func testBookSongsExposeBothPlayerScoreCardsInRowOrder() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true, size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_DEBUG_DUO_WINDOW"] = "book"
        app.launchEnvironment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
        app.launchArguments += [
            "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
            "-fst.accessibility.reduceMotion", "YES", "-fst.settings.showInstrumentIcons", "YES",
            "-fst.settings.metadataScore", "YES", "-fst.settings.metadataPercentage", "YES",
            "-fst.settings.metadataPercentile", "NO", "-fst.settings.metadataStars", "NO",
            "-fst.settings.metadataSeason", "NO", "-fst.settings.filterInvalidScores", "NO",
        ]
        app.launch()
        defer { app.terminate() }
        try XCTSkipUnless(app.windows.firstMatch.frame.width > 720, "Requires the wide Duo inner display")

        let children = app.descendants(matching: .any)
        let readout = children["fst.shell.debug.duo-window"]
        XCTAssertTrue(readout.waitForExistence(timeout: FestivalApp.budget(8)))
        XCTAssertTrue(readout.label.hasPrefix("book "))
        let hinge = try XCTUnwrap(readout.label.components(separatedBy: " fold=").last.flatMap(Double.init))
        var ids: [String] = []
        for id in ["fixture-orbit", "fixture-pulse"] {
            let song = app.buttons["fst.songs.row.\(id)"]
            let card = app.staticTexts["fst.songs.profile-panel.\(id).Solo_Guitar"]
            XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(12)))
            XCTAssertTrue(card.waitForExistence(timeout: FestivalApp.budget(12)), "No Lead score stop for \(id)")
            XCTAssertEqual(card.label, "Lead: Score 99,900, Accuracy 97.9 percent")
            XCTAssertGreaterThanOrEqual(card.frame.minX, hinge + 11)
            XCTAssertGreaterThanOrEqual(card.frame.minY, song.frame.minY)
            XCTAssertLessThanOrEqual(card.frame.maxY, song.frame.maxY)
            #if FST_UIKIT_PORT
            let chips = children["fst.songs.instrument-status.\(id)"]
            let bag = children["fst.songs.shop-bag.\(id)"]
            XCTAssertTrue(chips.exists && bag.exists)
            XCTAssertEqual(bag.frame.minX - chips.frame.maxX, 28, accuracy: 1,
                           "Reserve the spacer and both stack gaps before the Shop group")
            #endif
            ids += [song.identifier, card.identifier]
        }
        let order = children.allElementsBoundByIndex.map(\.identifier).filter { ids.contains($0) }
        #if FST_UIKIT_PORT
        XCTAssertEqual(order, ids)
        #else
        // SwiftUI publishes the card anchors outside the List, after its row buttons.
        for index in stride(from: 0, to: ids.count, by: 2) {
            XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: ids[index])),
                              try XCTUnwrap(order.firstIndex(of: ids[index + 1])))
        }
        #endif
        SongsUITestSupport.record(app, name: "book-songs-player-profile-cards")
    }

    @MainActor
    private func wideBandApp(size: String, pose: String) -> XCUIApplication {
        let app = fixtureApp(size: size)
        app.launchEnvironment["FST_DEBUG_BAND"] = "Band_Duets/fixture-player-1:fixture-player-2/Fixture Band"
        app.launchEnvironment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
        app.launchEnvironment["FST_DEBUG_DUO_WINDOW"] = pose
        app.launchArguments += [
            "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
            "-fst.accessibility.reduceMotion", "YES", "-fst.settings.metadataScore", "YES",
            "-fst.settings.metadataPercentage", "YES", "-fst.settings.metadataPercentile", "NO",
            "-fst.settings.metadataStars", "NO", "-fst.settings.metadataSeason", "NO",
        ]
        return app
    }

    /// A compact selected-player row keeps the Shop marker centred beside the taller chip column.
    @MainActor
    func testCompactSelectedSongCentersItsShopMarker() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true, size: UIContentSizeCategory.large.rawValue)
        app.launchArguments += [
            "-fst.settings.hideShop", "NO", "-fst.settings.disableShopHighlighting", "NO",
            "-fst.settings.showInstrumentIcons", "YES",
            "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        defer { app.terminate() }
        let song = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(20)))
        let children = app.descendants(matching: .any)
        let charts = children["fst.songs.instrument-status.fixture-orbit"]
        let bag = children["fst.songs.shop-bag.fixture-orbit"]
        let clock = children["fst.songs.shop-badge.fixture-orbit"]
        XCTAssertTrue(charts.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(bag.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(clock.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertEqual(bag.label, "In the Item Shop")
        XCTAssertEqual(clock.label, "Item Shop: Leaving Tomorrow")
        let chartLabel = try XCTUnwrap(song.label.range(of: "Lead, scored"))
        let bagLabel = try XCTUnwrap(song.label.range(of: bag.label))
        let clockLabel = try XCTUnwrap(song.label.range(of: clock.label))
        XCTAssertLessThan(chartLabel.lowerBound, bagLabel.lowerBound)
        XCTAssertLessThan(bagLabel.lowerBound, clockLabel.lowerBound)
        assertTarget(song, "Selected song")
        XCTAssertEqual(bag.frame.midY, song.frame.midY, accuracy: 1)
        XCTAssertLessThan(charts.frame.maxX, bag.frame.minX)
        // SwiftUI reports the glyph's ink frame; UIKit reports the image frame.
        // Their centers match even though the bounding boxes differ.
        XCTAssertEqual(clock.frame.minX - bag.frame.midX, 14.5, accuracy: 0.6)
    }

    #if FST_UIKIT_PORT
    /// The folded AX5 clock tracks its symbol rather than a padded text-line height.
    @MainActor
    func testCompactShopClockAtAX5KeepsChipsClearOfBottomField() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true, size: Self.ax5)
        app.launchArguments += [
            "-fst.settings.hideShop", "NO", "-fst.settings.disableShopHighlighting", "NO",
            "-fst.settings.showInstrumentIcons", "YES",
            "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        defer { app.terminate() }
        try XCTSkipUnless(app.windows.firstMatch.frame.size == CGSize(width: 466, height: 678),
                          "Requires the Duo cover display")
        let elements = app.descendants(matching: .any)
        let bag = elements["fst.songs.shop-bag.fixture-orbit"]
        let clock = elements["fst.songs.shop-badge.fixture-orbit"]
        let chips = elements["fst.songs.instrument-status.fixture-orbit"]
        XCTAssertTrue(chips.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(clock.waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(bag.exists)
        XCTAssertEqual(clock.label, "Item Shop: Leaving Tomorrow")
        XCTAssertEqual(clock.frame.height, 56, accuracy: 2)
        XCTAssertEqual(clock.frame.width, clock.frame.height, accuracy: 0.5)
        XCTAssertEqual(clock.frame.minX - bag.frame.maxX, 6, accuracy: 0.6)
        XCTAssertEqual(chips.frame.minY - clock.frame.maxY, 12, accuracy: 1)
        XCTAssertLessThan(chips.frame.maxY, elements["fst.songs.filter-field"].frame.minY)
    }
    #endif

    /// The compact chip strip keeps its placement and spoken chart order when
    /// there is no Shop accessory.
    @MainActor
    func testCompactSelectedSongWithoutShopAccessory() {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-2:Fixture Player 2"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-empty"
        app.launch()
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(20)))
        let scores = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Drums, scored"), object: song
        )
        XCTAssertEqual(XCTWaiter.wait(for: [scores], timeout: FestivalApp.budget(15)), .completed)
        XCTAssertTrue(song.isHittable)
        assertTarget(song, "Selected song")
        let chips = SongsUITestSupport.chipEntries(for: "fixture-pulse", in: app)
        XCTAssertEqual(chips.count, 9)
        XCTAssertTrue(chips.first?.hasSuffix("Lead, full combo") == true)
        XCTAssertTrue(song.label.hasPrefix("Fixture Pulse, "))
        XCTAssertTrue(song.label.hasSuffix((["Lead, full combo"] + Array(chips.dropFirst())).joined(separator: "; ")))
        XCTAssertFalse(app.descendants(matching: .any)["fst.songs.shop-bag.fixture-pulse"].exists)
        let viewport = app.windows.firstMatch.frame.size
        if viewport == CGSize(width: 402, height: 874) || viewport == CGSize(width: 466, height: 678) {
            let first = app.buttons["fst.songs.row.fixture-orbit"]
            XCTAssertTrue(first.isHittable)
            XCTAssertEqual(song.frame.minY - first.frame.minY, 142 + 1.0 / 3, accuracy: 0.2)
        }
        SongsUITestSupport.record(app, name: "songs-compact-chips-no-accessory")
    }

    /// The index fits above the folded Filter field, stays put on a jump and
    /// remains a named, operable control when its labels condense at AX5.
    @MainActor
    func testSongsIndexFitsAndJumpsAtDefaultAndLargestText() throws {
        continueAfterFailure = false
        guard let origin = ProcessInfo.processInfo.environment["FST_SONGS_SCROLL_FIXTURE_URL"] else {
            throw XCTSkip("Set the loopback origin of mock_service.py --large-catalogue.")
        }
        var defaultWidth: CGFloat = 0
        for size in [UIContentSizeCategory.large.rawValue, Self.ax5] {
            let app = fixtureApp(size: size)
            app.launchEnvironment["FST_API_BASE_URL"] = origin
            app.launch()
            defer { app.terminate() }
            let elements = app.descendants(matching: .any)
            let rail = elements["fst.songs.section-index"]
            XCTAssertTrue(rail.waitForExistence(timeout: FestivalApp.budget(20)))
            let named = elements["fst.songs.section-index.adjustable"]
            let adjustable = named.exists ? named : rail
            XCTAssertEqual(adjustable.label, "Jump to section")
            XCTAssertEqual(adjustable.value as? String, "#")
            let before = rail.frame
            XCTAssertGreaterThanOrEqual(before.height, 44)
            let window = app.windows.firstMatch.frame
            let folded = window.size == CGSize(width: 466, height: 678)
            let field = folded ? elements["fst.songs.filter-field"] : SongsUITestSupport.songsSearchEntry(in: app)
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            if size == Self.ax5 {
                XCTAssertGreaterThanOrEqual(before.width, defaultWidth * 2)
                if !folded { XCTAssertGreaterThanOrEqual(before.minY, field.frame.maxY) }
            } else {
                defaultWidth = before.width
                if folded {
                    let center = (window.minY + 52 + field.frame.minY - 16) / 2
                    XCTAssertEqual(before.midY, center, accuracy: 2)
                }
                if window.width == 402 || folded {
                    XCTAssertEqual(before.height, 398, accuracy: 2)
                }
            }
            if folded { XCTAssertLessThanOrEqual(before.maxY, field.frame.minY - 8) }

            let last = rail.staticTexts["Z"]
            XCTAssertTrue(last.exists)
            last.tap()
            let landed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'Z'"), object: adjustable)
            XCTAssertEqual(XCTWaiter.wait(for: [landed], timeout: FestivalApp.budget(8)), .completed)
            XCTAssertEqual(rail.frame.midY, before.midY, accuracy: 2)
            SongsUITestSupport.record(app, name: "songs-index-\(size == Self.ax5 ? "ax5" : "default")")
        }
    }

    /// Sort opens expanded with Reset in reach; the mode, direction and trigger survive relaunch.
    @MainActor
    func testSortSheetAppliesAndResets() throws {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launch()
        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: FestivalApp.budget(20)))
        sort.tap()
        let reset = app.buttons["fst.songs.sort.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        XCTAssertTrue(reset.isHittable, "Reset is reachable without expanding or scrolling the default sheet")
        XCTAssertEqual(reset.label, "Reset to Title A–Z")
        assertTarget(reset, "Reset")
        let artist = app.buttons.matching(identifier: "fst.songs.sort.mode").matching(
            NSPredicate(format: "label == %@", "Artist")
        ).firstMatch
        XCTAssertTrue(artist.waitForExistence(timeout: 5))
        assertTarget(artist, "Artist sort mode")
        let title = app.buttons.matching(identifier: "fst.songs.sort.mode").matching(
            NSPredicate(format: "label == %@", "Title")
        ).firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertEqual(artist.frame.midY - title.frame.midY, 52, accuracy: 0.5,
                       "The separator belongs inside the native-height form row")
        let window = app.windows.firstMatch.frame
        let done = app.buttons["fst.songs.sort.done"]
        XCTAssertTrue(done.exists)
        if [window.width.rounded(), window.height.rounded()] == [466, 678] {
            XCTAssertLessThanOrEqual(artist.frame.maxX, done.frame.minX, "Sort mode extends under the folded Duo rail")
        }
        artist.tap()
        XCTAssertTrue(artist.isSelected, "The Artist radio row must expose its selected state")
        let descending = app.buttons["fst.songs.sort.direction.descending"]
        XCTAssertTrue(descending.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(descending.frame.width, 40, "Descending is narrower than its 44 pt control")
        XCTAssertGreaterThanOrEqual(descending.frame.height, 34, "Descending is shorter than its 36 pt control")
        XCTAssertEqual(descending.frame.midY - title.frame.midY, 328, accuracy: 1,
                       "The direction group must follow the native picker and heading spacing")
        XCTAssertEqual(reset.frame.midY - descending.frame.midY, 97, accuracy: 1.5,
                       "Keep the untitled Reset group below the direction pill")
        if [window.width.rounded(), window.height.rounded()] == [466, 678] {
            XCTAssertEqual(done.frame.minX - descending.frame.maxX, 40, accuracy: 1,
                           "The grouped form must keep the native rail-safe gutter without a second margin")
        }
        descending.tap()
        XCTAssertTrue(descending.isSelected, "The direction stays a named, selected control")
        done.tap()
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        assertSortState(sort, "Artist, descending")
        try assertSortTint(sort) { r, g, b in r >= 175 && g >= 140 && g - b >= 65 }
        app.terminate()
        app.launch()
        XCTAssertTrue(sort.waitForExistence(timeout: FestivalApp.budget(20)))
        assertSortState(sort, "Artist, descending")
        sort.tap()
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        XCTAssertTrue(artist.isSelected)
        XCTAssertTrue(descending.isSelected)
        reset.tap()
        XCTAssertFalse(artist.isSelected)
        XCTAssertTrue(title.isSelected)
        XCTAssertTrue(app.buttons["fst.songs.sort.direction.ascending"].isSelected)
        app.buttons["fst.songs.sort.done"].tap()
        XCTAssertTrue(sort.waitForExistence(timeout: 10))
        assertSortState(sort, "Title, ascending")
        try assertSortTint(sort, matching: ButtonFillPixels.accentBlue)
    }

    /// The native SwiftUI toolbar speaks the value as part of the label, not a second field.
    @MainActor
    private func assertSortState(_ sort: XCUIElement, _ state: String, file: StaticString = #filePath, line: UInt = #line) {
        if sort.label == "Sort" {
            XCTAssertEqual(sort.value as? String, state, file: file, line: line)
        } else {
            XCTAssertEqual(sort.label, "Sort, \(state)", file: file, line: line)
            XCTAssertTrue((sort.value as? String ?? "").isEmpty, file: file, line: line)
        }
    }

    /// Verify the symbol, not the glass rim or the page behind the control.
    @MainActor
    private func assertSortTint(_ sort: XCUIElement, matching: ButtonFillPixels.Classifier) throws {
        let frame = CGRect(origin: .zero, size: sort.frame.size)
        let symbol = frame.insetBy(dx: (frame.width - 22) / 2, dy: (frame.height - 22) / 2)
        let image = try XCTUnwrap(sort.screenshot().image.cgImage)
        let pixels = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: frame.width))
        let fraction = try XCTUnwrap(pixels.fraction(in: symbol, matching: matching))
        XCTAssertGreaterThan(fraction, 0.04, "Sort's symbol does not reflect its spoken state: \(String(describing: sort.value))")
    }

    #if FST_UIKIT_PORT
    /// Sort choices and the wrapping Reset gain the native row height at AX5 without losing their targets.
    @MainActor
    func testSortChoiceRowsKeepNativeSpacingAtLargestText() throws {
        continueAfterFailure = false
        let app = fixtureApp(size: Self.ax5)
        app.launchArguments += ["-fst.songs.sortMode", "title"]
        app.launch()
        defer { app.terminate() }

        let sort = app.buttons["fst.songs.sort"]
        XCTAssertTrue(sort.waitForExistence(timeout: FestivalApp.budget(20)))
        sort.tap()
        let choices = app.buttons.matching(identifier: "fst.songs.sort.mode")
        let title = choices.matching(NSPredicate(format: "label == %@", "Title")).firstMatch
        let artist = choices.matching(NSPredicate(format: "label == %@", "Artist")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(title.isHittable && artist.isHittable)
        XCTAssertTrue(title.isSelected)
        XCTAssertFalse(artist.isSelected)
        assertTarget(artist, "Artist sort mode at AX5")
        XCTAssertEqual(artist.frame.midY - title.frame.midY, 93.33, accuracy: 1)

        let resetID = "fst.songs.sort.reset"
        let reset = app.buttons[resetID]
        let form = app.collectionViews.containing(.button, identifier: resetID).firstMatch
        for _ in 0..<3 { form.swipeUp() }
        XCTAssertTrue(reset.isHittable)
        XCTAssertEqual(reset.label, "Reset to Title A–Z")
        assertTarget(reset, "Reset sort at AX5")
        XCTAssertEqual(reset.frame.height, 147.33, accuracy: 2, "Leave the native text padding around both lines")
        XCTAssertEqual(app.windows.firstMatch.frame.maxY - reset.frame.maxY, 58, accuracy: 2,
                       "The final row should settle 20 pt above the bottom safe area, plus its 4 pt row padding")
        let ascending = app.buttons["fst.songs.sort.direction.ascending"]
        let descending = app.buttons["fst.songs.sort.direction.descending"]
        XCTAssertTrue(ascending.isHittable && descending.isHittable)
        XCTAssertTrue(ascending.isSelected)
        XCTAssertFalse(descending.isSelected)
        let label = form.staticTexts["Ascending"]
        let detail = form.staticTexts["A–Z, low to high"]
        XCTAssertTrue(label.exists && detail.exists)
        XCTAssertLessThan(label.frame.maxY, detail.frame.minY)
        XCTAssertGreaterThanOrEqual(ascending.frame.minX - label.frame.maxX, 30)
        let window = app.windows.firstMatch
        let image = try XCTUnwrap(window.screenshot().image.cgImage)
        let pixels = try XCTUnwrap(ButtonFillPixels(image: image, pointWidth: window.frame.width))
        let resetFoot = CGRect(x: reset.frame.minX - window.frame.minX + 1,
                               y: reset.frame.maxY - window.frame.minY - 27.5, width: 4, height: 3)
        let red = try XCTUnwrap(pixels.fraction(in: resetFoot, matching: ButtonFillPixels.destructiveRed))
        XCTAssertGreaterThan(red, 0.4, "The lower leading stroke of the wrapped Reset title must paint")
        let arrowTip = CGRect(x: ascending.frame.midX - window.frame.minX - 8,
                              y: ascending.frame.minY - window.frame.minY - 5, width: 16, height: 4)
        let white = try XCTUnwrap(pixels.fraction(in: arrowTip) { r, g, b in min(r, g, b) > 215 })
        XCTAssertGreaterThan(white, 0.05, "The scaled arrow must paint above the fixed-height capsule at AX5")
        descending.tap()
        XCTAssertTrue(descending.isSelected)
        XCTAssertFalse(ascending.isSelected)
        XCTAssertTrue(form.staticTexts["Z–A, high to low"].exists)
    }

    /// A failed Shop feed disables its sort mode and leaves the explanation in the same group.
    @MainActor
    func testUnavailableShopSortExplainsTheDisabledModeInItsGroup() {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: FestivalApp.budget(20)))
        ShellUITestSupport.tapToolbarItem("fst.songs.sort", overflowLabels: ["Sort", "Sort By"], in: app)
        let shop = app.buttons.matching(identifier: "fst.songs.sort.mode")
            .matching(NSPredicate(format: "label == %@", "Item Shop")).firstMatch
        let explanation = app.staticTexts["Item Shop sorting requires matching public Songs and Shop data."]
        XCTAssertTrue(explanation.waitForExistence(timeout: 10))
        XCTAssertTrue(shop.exists)
        XCTAssertFalse(shop.isEnabled)
        let form = app.collectionViews.containing(.staticText, identifier: explanation.label).firstMatch
        if !explanation.isHittable { form.swipeUp() }
        XCTAssertTrue(explanation.isHittable)
        XCTAssertEqual(explanation.frame.minX, shop.frame.minX, accuracy: 1, "Keep the note inside the mode card")
        XCTAssertGreaterThan(explanation.frame.minY, shop.frame.midY)
        if app.windows.firstMatch.frame.width <= 466 {
            let direction = app.buttons["fst.songs.sort.direction.ascending"]
            XCTAssertEqual(direction.frame.midY - shop.frame.midY, 184, accuracy: 2,
                           "Allow the wrapped note its native row height")
        }
        app.buttons["fst.songs.sort.done"].tap()
    }

    /// The retained catalogue follows the named paused and failed-read notices and Retry.
    @MainActor
    func testPausedShopSortKeepsNoticesAndRetryInListOrder() {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        let sortArguments = [
            "-fst.songs.sortMode", "shop", "-fst.songs.sortAscending", "YES", "-fst.settings.hideShop", "NO",
        ]
        app.launchArguments += sortArguments
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launch()
        defer { app.terminate() }

        let list = app.collectionViews["fst.songs.list"]
        let paused = list.staticTexts["fst.songs.sort-paused"]
        let error = list.staticTexts["fst.songs.shop-error"]
        let retry = list.buttons["fst.songs.shop-retry"]
        let firstSong = list.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(firstSong.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertTrue(paused.waitForExistence(timeout: 10))
        XCTAssertTrue(error.waitForExistence(timeout: FestivalApp.budget(15)))
        if abs(app.windows.firstMatch.frame.width - 466) < 1 {
            XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 5) { abs(error.frame.height - 104) < 2 },
                          "The cover banner needs all three lines of its message, got \(error.frame)")
        }
        XCTAssertTrue(retry.isHittable)
        assertTarget(retry, "Retry Item Shop status")
        XCTAssertEqual(retry.label, "Retry Item Shop status")
        let identifiers = list.descendants(matching: .any).allElementsBoundByIndex.map(\.identifier)
        let expected = [paused.identifier, error.identifier, retry.identifier]
        XCTAssertEqual(identifiers.filter { expected.contains($0) }, expected)
        XCTAssertGreaterThanOrEqual(error.frame.minY - paused.frame.maxY, 29)
        XCTAssertGreaterThanOrEqual(retry.frame.minY - error.frame.maxY, 29)
        XCTAssertEqual(firstSong.frame.minY - retry.frame.maxY, 17, accuracy: 2)
        XCTAssertLessThan(firstSong.frame.minY, list.buttons["fst.songs.row.fixture-pulse"].frame.minY)
        let standardHeight = paused.frame.height

        app.terminate()
        let large = fixtureApp(size: Self.ax5)
        large.launchArguments += sortArguments
        large.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        large.launch()
        defer { large.terminate() }
        let largeList = large.collectionViews["fst.songs.list"]
        let largePaused = largeList.staticTexts["fst.songs.sort-paused"]
        let largeRetry = largeList.buttons["fst.songs.shop-retry"]
        XCTAssertTrue(largePaused.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertGreaterThan(largePaused.frame.height, standardHeight * 2)
        for _ in 0..<8 where !largeRetry.isHittable { largeList.swipeUp() }
        XCTAssertTrue(largeRetry.isHittable)
        assertTarget(largeRetry, "Retry Item Shop status at AX5")
    }

    /// AX5 list notices fit on the starting side of the book fold and expand again when flat.
    @MainActor
    func testPausedShopSortNoticesStayClearOfBookFoldAtAX5() throws {
        continueAfterFailure = false
        let app = fixtureApp(size: Self.ax5)
        app.launchEnvironment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
        app.launchEnvironment["FST_DEBUG_DUO_WINDOW"] = "book"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        app.launchArguments += [
            "-fst.songs.sortMode", "shop", "-fst.songs.sortAscending", "YES",
            "-fst.settings.hideShop", "NO", "-fst.accessibility.reduceMotion", "YES",
        ]
        app.launch()
        defer { app.terminate() }
        let viewport = app.windows.firstMatch.frame
        try XCTSkipUnless(viewport.width > 850 && viewport.width > viewport.height, "Needs the Duo inner landscape display")

        let list = app.collectionViews["fst.songs.list"]
        let readout = app.staticTexts["fst.shell.debug.duo-window"]
        let paused = list.staticTexts["fst.songs.sort-paused"]
        let error = list.staticTexts["fst.songs.shop-error"]
        let retry = list.buttons["fst.songs.shop-retry"]
        let orbit = list.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(paused.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertTrue(readout.label.hasPrefix("book width=regular"))
        let fold = try XCTUnwrap(readout.label.components(separatedBy: " fold=").last.flatMap(Double.init))
        let foldStart = viewport.minX + CGFloat(fold) - 12
        let bookFrame = paused.frame
        XCTAssertLessThanOrEqual(bookFrame.maxX, foldStart)
        XCTAssertEqual(paused.label, "Item Shop sort paused until public Shop data loads. Showing title order; retry Item Shop status if unavailable.")

        func paintedNotice() -> String {
            let shot = app.screenshot()
            guard let bitmap = shot.image.cgImage else { return "" }
            let rotated = bitmap.width < bitmap.height
            let imageWidth = rotated ? shot.image.size.height : shot.image.size.width
            let foldX = (foldStart - viewport.minX) / viewport.width * imageWidth
            return RecognizedText.lines(in: shot, orientation: rotated ? .right : .up)
                .filter { $0.frame.midX < foldX }
                .map(\.text).joined(separator: " ")
        }

        let startText = "Item Shop sort paused until public Shop data loads. Showing title order; retry"
        let top = paintedNotice()
        XCTAssertTrue(RecognizedText.showsWhole(startText, in: top), top)
        SongsUITestSupport.record(app, name: "songs-paused-notices-book-AX5")

        DuoWindowSwitch.post("unfolded-landscape")
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 10) {
            readout.label.hasPrefix("unfolded-landscape") && paused.frame.maxX > foldStart + 24
        })
        XCTAssertLessThan(paused.frame.height, bookFrame.height)
        SongsUITestSupport.record(app, name: "songs-paused-notices-unfolded-AX5")
        DuoWindowSwitch.post("book")
        XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 10) {
            readout.label.hasPrefix("book") && abs(paused.frame.maxX - bookFrame.maxX) < 1
        })
        XCTAssertEqual(paused.frame.height, bookFrame.height, accuracy: 1)

        func scrollNotices() {
            let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.69))
            let end = list.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.38))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        // The tall cell is clipped by the viewport, so read overlapping parts from the app capture.
        let endText = "Showing title order; retry Item Shop status if unavailable."
        var end = ""
        for _ in 0..<3 {
            scrollNotices()
            end = paintedNotice()
            if RecognizedText.showsWhole(endText, in: end) { break }
        }
        XCTAssertTrue(RecognizedText.showsWhole(endText, in: end), end)
        SongsUITestSupport.record(app, name: "songs-paused-notices-book-scrolled-AX5")
        for _ in 0..<5 where !error.isHittable { scrollNotices() }
        XCTAssertTrue(error.isHittable)
        XCTAssertLessThanOrEqual(error.frame.maxX, foldStart)
        for _ in 0..<5 where !retry.isHittable { scrollNotices() }
        XCTAssertTrue(retry.isHittable)
        assertTarget(retry, "Retry Item Shop status at AX5")
        XCTAssertEqual(retry.label, "Retry Item Shop status")
        XCTAssertLessThanOrEqual(retry.frame.maxX, foldStart)
        if error.exists { XCTAssertLessThan(error.frame.minY, retry.frame.minY) }
        for _ in 0..<5 where !orbit.isHittable { scrollNotices() }
        XCTAssertTrue(orbit.isHittable, "The retained Songs results still follow the notices")
    }

    // The Xcode 27.1 CI SDK doesn't declare XCUIHinge.
    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    /// A live paused list reflows onto the cover and restores its inner layout without a relaunch.
    @MainActor
    func testPausedShopSortReflowsAcrossDuoDisplays() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["FST_DUO_SONGS_HINGE_TEST"] == "1"
                && (environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Opt in on a dedicated iPhone Duo with the loopback fixture"
        )
        guard #available(iOS 27.3, *) else { throw XCTSkip("Needs the iOS 27.3 hinge runtime") }
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let hinge = try XCTUnwrap(device.hinge, "The Duo simulator has no XCUIHinge")
        let originalAngle = hinge.angle
        let originalOrientation = device.orientation
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launchArguments += [
            "-fst.songs.sortMode", "shop", "-fst.songs.sortAscending", "YES", "-fst.settings.hideShop", "NO",
        ]
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-error"
        defer {
            app.terminate()
            device.orientation = originalOrientation
            hinge.angle = originalAngle
        }

        device.orientation = .portrait
        hinge.angle = .pi
        app.launch()
        let window = app.windows.firstMatch
        let list = app.collectionViews["fst.songs.list"]
        let paused = list.staticTexts["fst.songs.sort-paused"]
        let error = list.staticTexts["fst.songs.shop-error"]
        let retry = list.buttons["fst.songs.shop-retry"]
        let orbit = list.buttons["fst.songs.row.fixture-orbit"]

        func checkDisplay(_ phase: String, angle: CGFloat, size: CGSize) -> CGFloat {
            XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 15) {
                abs(hinge.angle - angle) < 0.05 && abs(window.frame.width - size.width) < 1
                    && abs(window.frame.height - size.height) < 1
            }, "\(phase): hinge \(hinge.angle), window \(window.frame)")
            let fits = FeedbackJourney.waitUntil(timeout: 15) {
                paused.exists && error.exists && retry.isHittable && orbit.exists
                    && (angle != 0 || (paused.frame.width < size.width - 80 && abs(error.frame.height - 104) < 2))
                    && orbit.frame.minY > retry.frame.maxY
            }
            let capture = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            capture.name = "songs-paused-\(phase)"
            capture.lifetime = .keepAlways
            add(capture)
            XCTAssertTrue(fits, "\(phase): notice \(paused.frame), error \(error.frame), Retry \(retry.frame), first song \(orbit.frame)")
            XCTAssertEqual(retry.label, "Retry Item Shop status")
            assertTarget(retry, phase)
            return paused.frame.width
        }

        let inner = CGSize(width: 951, height: 669)
        let cover = CGSize(width: 466, height: 678)
        let innerWidth = checkDisplay("inner", angle: .pi, size: inner)
        hinge.angle = 0
        let coverWidth = checkDisplay("cover", angle: 0, size: cover)
        XCTAssertLessThan(coverWidth, innerWidth)
        hinge.angle = .pi
        let restoredWidth = checkDisplay("inner-return", angle: .pi, size: inner)
        XCTAssertEqual(restoredWidth, innerWidth, accuracy: 1)
    }
    #endif
    #endif

    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    /// A genuine empty catalogue follows the physical fold and recenters without a relaunch.
    @MainActor
    func testEmptyCatalogueReflowsAcrossDuoHinge() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(
            environment["FST_DUO_SONGS_HINGE_TEST"] == "1"
                && (environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Opt in on a dedicated iPhone Duo with the loopback fixture"
        )
        guard #available(iOS 27.3, *) else { throw XCTSkip("Needs the iOS 27.3 hinge runtime") }
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let hinge = try XCTUnwrap(device.hinge, "The Duo simulator has no XCUIHinge")
        let originalAngle = hinge.angle
        let originalOrientation = device.orientation
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "empty"
        defer {
            app.terminate()
            device.orientation = originalOrientation
            hinge.angle = originalAngle
        }

        device.orientation = .portrait
        hinge.angle = .pi
        app.launch()
        let window = app.windows.firstMatch
        let title = app.staticTexts["No Results"]
        let subtitle = app.staticTexts["No songs are available yet."]
        let field = app.descendants(matching: .any)["fst.songs.filter-field"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertTrue(title.exists)

        func check(_ phase: String, angle: CGFloat, inBookPose: Bool) {
            let fits = FeedbackJourney.waitUntil(timeout: 15) {
                let frame = window.frame
                guard abs(hinge.angle - angle) < 0.05, frame.size == CGSize(width: 951, height: 669),
                      title.exists, subtitle.exists, field.exists else { return false }
                if inBookPose {
                    return field.frame.minX > frame.midX && title.frame.maxX <= frame.midX
                        && subtitle.frame.maxX <= frame.midX
                }
                return field.frame.minX < frame.midX && title.frame.minX < frame.midX && title.frame.maxX > frame.midX
            }
            XCTAssertTrue(fits, "\(phase): hinge \(hinge.angle); window \(window.frame); title \(title.frame); field \(field.frame)")
            var paint = "No inner framebuffer"
            let captureSettled = FeedbackJourney.waitUntil(timeout: 8) {
                let shot = app.screenshot()
                guard let bitmap = shot.image.cgImage else { return false }
                guard max(bitmap.width, bitmap.height) == 2852, min(bitmap.width, bitmap.height) == 2006 else {
                    paint = "\(bitmap.width) × \(bitmap.height) pixels"
                    return false
                }
                let rotated = bitmap.width < bitmap.height
                let lines = RecognizedText.lines(in: shot, orientation: rotated ? .right : .up)
                paint = "\(lines.map(\.text)); AX center \(title.frame.midX)"
                guard let drawnTitle = lines.first(where: { $0.text == "No Results" }),
                      lines.contains(where: { $0.text == "No songs are available yet." }) else { return false }
                let imageWidth = rotated ? shot.image.size.height : shot.image.size.width
                let drawnCenter = window.frame.minX + drawnTitle.frame.midX / imageWidth * window.frame.width
                paint += "; drawn center \(drawnCenter)"
                guard abs(drawnCenter - title.frame.midX) < 4 else { return false }
                let attachment = XCTAttachment(screenshot: shot)
                attachment.name = "empty-catalogue-\(phase)"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return true
            }
            XCTAssertTrue(captureSettled, "\(phase) missing the expected inner-display paint: \(paint)")
        }

        check("flat", angle: .pi, inBookPose: false)
        let flatCenter = title.frame.midX
        hinge.angle = .pi / 2
        check("book", angle: .pi / 2, inBookPose: true)
        hinge.angle = .pi
        check("flat-return", angle: .pi, inBookPose: false)
        XCTAssertEqual(title.frame.midX, flatCenter, accuracy: 1)
    }
    #endif

    /// The Filter sheet's General groups disclose their switches; a change shows on the tool.
    @MainActor
    func testFilterSheetGroupsAndApply() throws {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: FestivalApp.budget(20)))
        openFilter(in: app)
        let bass = app.buttons["fst.songs.filter.double-bass"]
        XCTAssertTrue(bass.waitForExistence(timeout: 10))
        XCTAssertEqual(bass.value as? String, "Collapsed")
        let supportedID = "fst.songs.filter.double-bass.supported"
        XCTAssertFalse(app.switches[supportedID].isHittable)
        SongsUITestSupport.revealFilterOption(bass, in: app).tap()
        let supported = app.switches[supportedID]
        XCTAssertTrue(supported.waitForExistence(timeout: 5))
        XCTAssertEqual(bass.value as? String, "Expanded")
        XCTAssertEqual(supported.label, "Double Bass Support")
        XCTAssertEqual(supported.value as? String, "1")
        assertTarget(supported, "Double Bass Support")
        _ = SongsUITestSupport.revealFilterOption(supported, in: app)
        SongsUITestSupport.waitUntilFrameSettles(supported)
        let form = app.collectionViews["fst.songs.filter.form"]
        let title = form.staticTexts["Double Bass"].firstMatch
        let hint = form.staticTexts["Filter songs that have or don't have double bass charts for Pro Drums."].firstMatch
        let choiceTitle = form.staticTexts["Double Bass Support"].firstMatch
        XCTAssertTrue(title.exists, "The disclosure title is present")
        XCTAssertTrue(hint.exists, "The disclosure hint is present")
        XCTAssertTrue(choiceTitle.exists, "The first choice label is present")
        XCTAssertEqual(choiceTitle.frame.minX - title.frame.minX, 20, accuracy: 1, "Nested choice indentation")
        XCTAssertGreaterThan(choiceTitle.frame.minY, hint.frame.maxY, "Read the hint before the choice")
        if app.windows.firstMatch.frame.width <= 466 {
            XCTAssertEqual(hint.frame.height, 33.67, accuracy: 1, "Native two-line footnote height")
            XCTAssertEqual(choiceTitle.frame.minY - title.frame.minY, 86.84, accuracy: 1.5,
                           "The first nested choice follows the padded, wrapped disclosure header")
        }
        supported.tap()
        XCTAssertEqual(supported.value as? String, "0")
        app.buttons["fst.songs.filter.done"].tap()
        let after = app.buttons["fst.songs.filter"]
        XCTAssertTrue(after.waitForExistence(timeout: 15), "Filter tool missing after closing the sheet")
        XCTAssertTrue(after.label.contains("Double Bass filter")
                      || (after.value as? String)?.contains("Double Bass filter") == true,
                      "Filter state: \(after.label), \(String(describing: after.value))")
    }

    /// A chart check is independent of the global switch, survives reopening, and clears on Reset.
    @MainActor
    func testPlayerScoreSectionsKeepChartChecksUntilReset() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: FestivalApp.budget(20)))
        openFilter(in: app)
        let score = app.buttons["fst.songs.filter.score-sections"]
        revealFilterControl(score, in: app)
        XCTAssertEqual(score.label, "Player Score and FC Filters")
        XCTAssertEqual(score.value as? String, "Collapsed")
        let global = app.switches["fst.songs.filter.score.global.hasScores"]
        XCTAssertFalse(global.isHittable)
        expandFilterDisclosure(score)
        revealFilterControl(global, in: app)
        XCTAssertEqual(global.label, "Has Scores")
        XCTAssertTrue(global.isEnabled)
        XCTAssertEqual(global.value as? String, "0")
        assertTarget(global, "Global Has Scores")
        setFilterSwitch(global, to: "1")
        setFilterSwitch(global, to: "0")

        let lead = app.descendants(matching: .any)["fst.songs.filter.score.instrument.Solo_Guitar"].firstMatch
        revealFilterControl(lead, in: app)
        lead.tap()
        let check = app.switches["fst.songs.filter.score.chart.Solo_Guitar.hasScores"]
        revealFilterControl(check, in: app)
        XCTAssertEqual(check.label, "Has Lead Scores")
        XCTAssertEqual(check.value as? String, "0")
        assertTarget(check, "Lead Has Scores")
        setFilterSwitch(check, to: "1")
        XCTAssertEqual(global.value as? String, "0")

        let done = app.buttons["fst.songs.filter.done"]
        done.tap()
        openFilter(in: app)
        revealFilterControl(score, in: app)
        XCTAssertEqual(score.value as? String, "Expanded")
        revealFilterControl(lead, in: app)
        lead.tap()
        revealFilterControl(check, in: app)
        XCTAssertEqual(check.value as? String, "1")
        SongsUITestSupport.revealFilterReset(in: app).tap()
        done.tap()
        openFilter(in: app)
        revealFilterControl(score, in: app)
        XCTAssertEqual(score.value as? String, "Collapsed")
    }

    /// Reach a Filter row with short Form drags, keeping its center clear of the cover's
    /// scroll-to-top area. Disabled switches must be visible rather than hittable.
    @MainActor
    private func revealFilterControl(_ control: XCUIElement, in app: XCUIApplication, requiresHit: Bool = true) {
        let form = app.collectionViews["fst.songs.filter.form"].firstMatch
        XCTAssertTrue(form.exists)
        let viewport = form.frame
        let top = viewport.minY + 44
        let bottom = min(SongsUITestSupport.sheetVisibleBottom(in: app), viewport.maxY)
        #if FST_UIKIT_PORT
        // Start in the form's 16 pt gutter, outside the switch rows.
        let dragX = 8 / viewport.width
        #else
        let dragX: CGFloat = 0.38
        #endif
        for _ in 0..<12 {
            let frame = control.exists ? control.frame : .zero
            if !frame.isEmpty, frame.minY >= top, frame.maxY <= bottom, !requiresHit || control.isHittable {
                return
            }
            let above = !frame.isEmpty && frame.minY < top
            let upper = form.coordinate(withNormalizedOffset: CGVector(dx: dragX, dy: 0.40))
            let lower = form.coordinate(withNormalizedOffset: CGVector(dx: dragX, dy: 0.66))
            (above ? upper : lower).press(
                forDuration: 0.05, thenDragTo: above ? lower : upper, withVelocity: .slow, thenHoldForDuration: 0.3
            )
        }
        XCTFail("\(control.identifier) did not clear the Filter edges: \(control.frame) vs \(top)...\(bottom)")
    }

    /// Tap a settled disclosure and wait for its requested state, not its body animation.
    @MainActor
    private func expandFilterDisclosure(_ disclosure: XCUIElement) {
        SongsUITestSupport.waitUntilFrameSettles(disclosure)
        disclosure.tap()
        let expanded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Expanded"), object: disclosure
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: FestivalApp.budget(5)), .completed)
    }

    /// Activate the row in UIKit or the native switch track in SwiftUI.
    @MainActor
    private func setFilterSwitch(_ element: XCUIElement, to value: String) {
        #if FST_UIKIT_PORT
        SongsUITestSupport.waitUntilFrameSettles(element)
        element.tap()
        XCTAssertEqual(element.value as? String, value)
        #else
        SongsUITestSupport.setSwitch(element, to: value)
        #endif
    }

    /// Retry occupies the notice's safe width, stays separate from its explanation, and grows
    /// at AX5 without clipping its title or requiring a scroll for the syncing state.
    @MainActor
    func testPlayerScoreRetryUsesAReadableListRow() async throws {
        continueAfterFailure = false
        let label = "Retry Player Scores"
        var standardInk: CGFloat = 0
        for size in [UIContentSizeCategory.large.rawValue, Self.ax5] {
            let app = fixtureApp(size: size)
            app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-syncing:Syncing Player"
            app.launchArguments += ["-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES"]
            app.launch()
            defer { app.terminate() }
            let status = app.staticTexts["fst.songs.profile-status"]
            let retry = app.buttons["fst.songs.profile-retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: FestivalApp.budget(20)))
            SongsUITestSupport.waitUntilFrameSettles(retry)
            XCTAssertEqual(status.label, "Player scores are syncing. No published score cards yet.")
            XCTAssertEqual(retry.label, label)
            XCTAssertTrue(retry.isEnabled)
            XCTAssertTrue(retry.isHittable, "The syncing Retry is reachable on arrival, including at AX5")
            XCTAssertEqual(retry.frame.width, status.frame.width, accuracy: 1)
            XCTAssertGreaterThanOrEqual(retry.frame.minY, status.frame.maxY)
            assertTarget(retry, label)
            let reading = RecognizedText.recognize(retry, label: label, frame: retry.frame)
            XCTAssertTrue(RecognizedText.showsWhole(label, in: reading.text), "Painted Retry: \(reading.text ?? "unreadable")")
            let ink = try XCTUnwrap(reading.lineHeight)
            if size == Self.ax5 {
                XCTAssertGreaterThan(ink, standardInk * RecognizedText.minimumGrowth)
            } else {
                standardInk = ink
            }
            SongsUITestSupport.record(app, name: "songs-player-retry-\(size == Self.ax5 ? "ax5" : "default")")
            let readsBefore = try await Self.syncingProfileReads()
            XCTAssertGreaterThan(readsBefore, 0)
            retry.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let deadline = ContinuousClock.now + .seconds(5)
            var readsAfter = try await Self.syncingProfileReads()
            while readsAfter <= readsBefore && ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(200))
                readsAfter = try await Self.syncingProfileReads()
            }
            XCTAssertGreaterThan(readsAfter, readsBefore, "Tapping the action's padded area must reread the player")
            XCTAssertTrue(status.waitForExistence(timeout: FestivalApp.budget(10)))
            XCTAssertTrue(retry.waitForExistence(timeout: FestivalApp.budget(10)))
        }
    }

    /// Reads only the test listener's count for the synthetic syncing profile.
    private static func syncingProfileReads() async throws -> Int {
        var origin = try XCTUnwrap(URLComponents(string: SongsUITestSupport.fixtureURL))
        guard origin.scheme == "http", origin.host == "127.0.0.1" || origin.host == "localhost" else {
            throw XCTSkip("Retry verification requires a loopback fixture")
        }
        origin.path = "/__fixture__/syncing-profile-reads"
        let request = URLRequest(url: try XCTUnwrap(origin.url), timeoutInterval: 2)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONDecoder().decode([String: Int].self, from: data)["reads"])
    }

    /// A syncing player can use public Shop filters but cannot select score predicates.
    @MainActor
    func testSyncingPlayerScoreChecksStayDisabled() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-syncing:Syncing Player"
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launchArguments += ["-fst.settings.hideShop", "NO"]
        app.launch()
        defer { app.terminate() }
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: FestivalApp.budget(20)) && orbit.exists)
        let syncing = app.descendants(matching: .any).matching(identifier: "fst.songs.profile-status")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Player scores are syncing")).firstMatch
        XCTAssertTrue(syncing.waitForExistence(timeout: FestivalApp.budget(10)))
        openFilter(in: app)
        let score = app.buttons["fst.songs.filter.score-sections"]
        revealFilterControl(score, in: app)
        expandFilterDisclosure(score)
        let status = app.staticTexts["Score filters need published player scores from the current Songs catalogue."]
        revealFilterControl(status, in: app)
        let global = app.switches["fst.songs.filter.score.global.hasScores"]
        revealFilterControl(global, in: app, requiresHit: false)
        XCTAssertTrue(global.exists)
        XCTAssertEqual(global.label, "Has Scores")
        XCTAssertFalse(global.isEnabled)
        XCTAssertEqual(global.value as? String, "0")
        SongsUITestSupport.waitUntilFrameSettles(global)
        let shot = global.screenshot()
        let label = try XCTUnwrap(RecognizedText.lines(in: shot).first {
            RecognizedText.showsWhole("Has Scores", in: $0.text)
        }, "Has Scores must be visibly readable")
        let image = shot.image
        let pixels = try XCTUnwrap(ButtonFillPixels(image: try XCTUnwrap(image.cgImage), pointWidth: image.size.width))
        let brightInk = try XCTUnwrap(pixels.fraction(in: label.frame) { r, g, b in min(r, g, b) >= 220 })
        XCTAssertGreaterThan(brightInk, 0.04, "Disable the switch, not the contrast of its label")
        SongsUITestSupport.record(app, name: "songs-syncing-score-predicates-disabled")

        let done = app.buttons["fst.songs.filter.done"]
        done.tap()
        SongsUITestSupport.openSongsFilter(in: app)
        let unavailable = app.switches["fst.songs.filter.shop-unavailable"]
        XCTAssertTrue(unavailable.isEnabled, "Public Shop filtering must not wait for player scores")
        XCTAssertEqual(unavailable.label, "Not Available in Item Shop")
        SongsUITestSupport.setSwitch(unavailable, to: "0")
        done.tap()
        XCTAssertTrue(pulse.waitForExistence(timeout: 10))
        XCTAssertTrue(orbit.waitForNonExistence(timeout: 10))
        XCTAssertTrue(syncing.exists, "The syncing notice must remain with the filtered Shop rows")
        XCTAssertFalse(app.descendants(matching: .any)["fst.songs.filter-paused"].exists)
        SongsUITestSupport.record(app, name: "songs-syncing-public-shop-filter-applied")
    }

    #if FST_UIKIT_PORT
    /// Both secondary pills are addressable on first paint, without scrolling to relayout the cell.
    @MainActor
    func testFirstScoredSongExposesItsPaintedMetadata() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true, size: UIContentSizeCategory.large.rawValue)
        app.launchArguments += [
            "-fst.settings.showInstrumentIcons", "NO", "-fst.settings.filterInvalidScores", "NO",
            "-fst.settings.showLead", "YES", "-fst.settings.hideShop", "NO", "-fst.settings.metadataScore", "YES",
            "-fst.settings.metadataPercentage", "YES", "-fst.settings.metadataPercentile", "YES",
            "-fst.settings.metadataSeason", "NO", "-fst.settings.metadataStars", "NO",
            "-fst.settings.metadataIntensity", "NO", "-fst.settings.metadataDifficulty", "NO",
            "-fst.settings.metadataLastPlayed", "NO", "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        defer { app.terminate() }
        let row = app.buttons["fst.songs.row.fixture-orbit"]
        let score = app.staticTexts["fst.songs.metadata.score.fixture-orbit"]
        XCTAssertTrue(score.waitForExistence(timeout: FestivalApp.budget(20)))
        let accuracy = app.staticTexts["fst.songs.metadata.accuracy.fixture-orbit"]
        let percentile = app.staticTexts["fst.songs.metadata.percentile.fixture-orbit"]
        XCTAssertTrue(accuracy.exists, "The first card paints accuracy before it is scrolled")
        XCTAssertTrue(percentile.exists, "The first card paints percentile before it is scrolled")
        XCTAssertEqual(accuracy.label, "Accuracy 97.9 percent")
        XCTAssertEqual(percentile.label, "Top 4%")
        assertTarget(row, "Scored song")
        let accuracyOrder = try XCTUnwrap(row.label.range(of: accuracy.label))
        let percentileOrder = try XCTUnwrap(row.label.range(of: percentile.label))
        XCTAssertLessThan(accuracyOrder.lowerBound, percentileOrder.lowerBound)
        XCTAssertTrue(row.frame.contains(accuracy.frame) && row.frame.contains(percentile.frame))
        XCTAssertLessThan(accuracy.frame.maxX, percentile.frame.minX)
        for (element, text) in [(accuracy, "97.9%"), (percentile, "Top 4%")] {
            let reading = RecognizedText.recognize(element, label: text, frame: element.frame)
            XCTAssertTrue(RecognizedText.showsWhole(text, in: reading.text), reading.text ?? "Pill not painted")
        }
        XCTAssertEqual(
            try goldStrokeLean(in: percentile.screenshot().image, width: percentile.frame.width),
            0, accuracy: 0.5, "Top 4% stays upright"
        )
    }
    #endif

    /// Top 1% uses the skewed outline even at AX5, without changing the row's accessible meaning.
    @MainActor
    func testTopOnePercentilePaintsSkewAndScalesWithoutClipping() throws {
        continueAfterFailure = false
        var standardHeight: CGFloat = 0
        for size in [UIContentSizeCategory.large.rawValue, Self.ax5] {
            let app = fixtureApp(size: size)
            app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-song-top-one:Fixture Song Top One"
            app.launchArguments += [
                "-fst.settings.showInstrumentIcons", "NO", "-fst.settings.filterInvalidScores", "NO",
                "-fst.settings.showLead", "YES", "-fst.settings.metadataScore", "YES",
                "-fst.settings.metadataPercentage", "NO", "-fst.settings.metadataPercentile", "YES",
                "-fst.settings.metadataSeason", "NO", "-fst.settings.metadataStars", "NO",
                "-fst.settings.metadataIntensity", "NO", "-fst.settings.metadataDifficulty", "NO",
                "-fst.settings.metadataLastPlayed", "NO", "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "NO",
            ]
            app.launch()
            defer { app.terminate() }
            let row = app.buttons["fst.songs.row.fixture-pulse"]
            let pill = app.descendants(matching: .any)["fst.songs.metadata.percentile.fixture-pulse"]
            XCTAssertTrue(pill.waitForExistence(timeout: FestivalApp.budget(20)))
            let viewport = app.frame
            let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.44))
            let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.67))
            for _ in 0..<4 where pill.frame.maxY > viewport.maxY - 144 {
                lower.press(forDuration: 0.05, thenDragTo: upper, withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            XCTAssertEqual(pill.label, "Top 1%")
            XCTAssertEqual(row.label.components(separatedBy: pill.label).count, 2, row.label)
            assertTarget(row, "Scored song")
            XCTAssertTrue(row.frame.contains(pill.frame))
            XCTAssertGreaterThan(pill.frame.minY, viewport.minY + 120)
            XCTAssertLessThanOrEqual(pill.frame.maxY, viewport.maxY - 144)
            let screenshot = pill.screenshot()
            let attachment = XCTAttachment(screenshot: screenshot)
            attachment.name = "Top 1% at \(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertGreaterThan(
                try goldStrokeLean(in: screenshot.image, width: pill.frame.width),
                0.6, "The upper stroke should lean right"
            )
            let reading = RecognizedText.recognize(pill, label: pill.label, frame: pill.frame)
            XCTAssertTrue(RecognizedText.showsWhole(pill.label, in: reading.text), reading.text ?? "Pill not painted")
            if size == Self.ax5 {
                XCTAssertGreaterThan(pill.frame.height, standardHeight)
            } else {
                standardHeight = pill.frame.height
            }
        }
    }

    /// Measures the signed horizontal displacement of the painted left stroke between two scanlines.
    @MainActor
    private func goldStrokeLean(in image: UIImage, width: CGFloat) throws -> CGFloat {
        let bitmap = try XCTUnwrap(ButtonFillPixels(image: XCTUnwrap(image.cgImage), pointWidth: width))
        func strokeX(at fraction: Double) throws -> CGFloat {
            let y = Int(Double(bitmap.height) * fraction)
            let columns = 0..<(bitmap.width / 5)
            func isGold(_ x: Int) -> Bool {
                let i = (y * bitmap.width + x) * 4
                return (189...225).contains(bitmap.pixels[i]) && (147...183).contains(bitmap.pixels[i + 1])
                    && bitmap.pixels[i + 2] <= 28
            }
            let first = try XCTUnwrap(columns.first(where: isGold), "No gold stroke at \(fraction) of the badge height")
            // Stop at the first gap so large text cannot be counted as part of the border.
            let end = (first..<columns.upperBound).first { !isGold($0) } ?? columns.upperBound
            return CGFloat(first + end - 1) / (2 * bitmap.scale)
        }
        return try strokeX(at: 0.35) - strokeX(at: 0.65)
    }

    #if FST_UIKIT_PORT
    /// The decorative bag takes only its symbol width, so the uncharted status wraps only when needed.
    @MainActor
    func testUnchartedSongSummaryFitsBesideShopBadges() throws {
        continueAfterFailure = false
        let app = fixtureApp(profile: true, size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-player-2:Fixture Player 2"
        app.launchArguments += [
            "-fst.settings.showInstrumentIcons", "NO", "-fst.settings.showLead", "NO",
            "-fst.settings.showBass", "NO", "-fst.settings.showDrums", "YES",
            "-fst.settings.hideShop", "NO", "-fst.settings.disableShopHighlighting", "NO",
            "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
        ]
        app.launch()
        defer { app.terminate() }
        let row = app.buttons["fst.songs.row.fixture-orbit"]
        let summary = app.staticTexts["fst.songs.profile-summary.fixture-orbit"]
        let bag = app.images["fst.songs.shop-bag.fixture-orbit"]
        let message = "Drums is not charted for this song"
        XCTAssertTrue(summary.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertEqual(summary.label, message)
        XCTAssertTrue(bag.exists)
        assertTarget(row, "Uncharted song")
        let messageOrder = try XCTUnwrap(row.label.range(of: message))
        let bagOrder = try XCTUnwrap(row.label.range(of: "In the Item Shop"))
        XCTAssertLessThan(messageOrder.lowerBound, bagOrder.lowerBound)
        XCTAssertLessThan(summary.frame.maxX, bag.frame.minX)
        let folded = (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo")
        if folded {
            XCTAssertGreaterThan(summary.frame.height, 26, "The cover needs two lines at Large")
        } else {
            XCTAssertLessThan(summary.frame.height, 20, "The phone fits the complete message on one line")
        }
        let reading = RecognizedText.recognize(summary, label: message, frame: summary.frame)
        XCTAssertTrue(RecognizedText.showsWhole(message, in: reading.text), reading.text ?? "Status not painted")
    }

    /// The syncing line matches the compact Label at Large and wraps clear of Shop at AX5.
    @MainActor
    func testSyncingSongStatusKeepsItsLabelReadableBesideShop() throws {
        continueAfterFailure = false
        let label = "Player scores are syncing"
        var standardInk: CGFloat = 0
        for size in [UIContentSizeCategory.large.rawValue, Self.ax5] {
            let app = fixtureApp(size: size)
            app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-syncing:Syncing Player"
            app.launchArguments += [
                "-fst.settings.hideShop", "NO", "-fst.settings.disableShopHighlighting", "NO",
                "-fst.songs.sortMode", "title", "-fst.songs.sortAscending", "YES",
            ]
            app.launch()
            defer { app.terminate() }
            XCTAssertTrue(app.buttons["fst.songs.profile-retry"].waitForExistence(timeout: FestivalApp.budget(20)))
            let row = app.buttons["fst.songs.row.fixture-orbit"]
            let status = app.staticTexts["fst.songs.profile-summary.fixture-orbit"]
            let bag = app.descendants(matching: .any)["fst.songs.shop-bag.fixture-orbit"]
            XCTAssertTrue(bag.waitForExistence(timeout: FestivalApp.budget(15)), "The public Shop badge must settle first")
            let viewport = app.frame
            for _ in 0..<5 {
                if status.exists && status.frame.minY >= viewport.minY + 132
                    && status.frame.maxY <= viewport.maxY - 132 { break }
                let upper = app.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.38))
                let lower = app.coordinate(withNormalizedOffset: CGVector(dx: 0.31, dy: 0.65))
                let above = status.exists && status.frame.minY < viewport.minY + 132
                (above ? upper : lower).press(forDuration: 0.05, thenDragTo: above ? lower : upper,
                                              withVelocity: .slow, thenHoldForDuration: 0.3)
            }
            XCTAssertTrue(status.exists)
            XCTAssertEqual(status.label, label)
            XCTAssertTrue(bag.exists)
            XCTAssertEqual(bag.label, "In the Item Shop")
            XCTAssertEqual(row.label.components(separatedBy: label).count, 2, row.label)
            let statusOrder = try XCTUnwrap(row.label.range(of: label))
            let bagOrder = try XCTUnwrap(row.label.range(of: bag.label))
            XCTAssertLessThan(statusOrder.lowerBound, bagOrder.lowerBound)
            assertTarget(row, "Syncing song")
            SongsUITestSupport.waitUntilFrameSettles(status)
            let reading = RecognizedText.recognize(status, label: label, frame: status.frame)
            XCTAssertTrue(RecognizedText.showsWhole(label, in: reading.text), reading.text ?? "Status not painted")
            let ink = try XCTUnwrap(reading.lineHeight)
            if size == Self.ax5 {
                XCTAssertGreaterThan(ink, standardInk * RecognizedText.minimumGrowth)
                XCTAssertGreaterThan(status.frame.width, row.frame.width * 0.7)
                XCTAssertGreaterThan(status.frame.minY, bag.frame.maxY)
            } else {
                standardInk = ink
                XCTAssertEqual(status.frame.minX - row.frame.minX, 108, accuracy: 1,
                               "The compact label has its own text column after the symbol")
                XCTAssertLessThanOrEqual(status.frame.maxX, bag.frame.minX)
                let nextSong = app.buttons["fst.songs.row.fixture-pulse"]
                XCTAssertTrue(nextSong.isHittable)
                let wrapped = (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo")
                XCTAssertEqual(nextSong.frame.minY - row.frame.minY, wrapped ? 104 : 86, accuracy: 1.5,
                               "Match the native compact row pitch, including the status wrap on the Duo cover")
            }
            SongsUITestSupport.record(app, name: "songs-compact-syncing-\(size == Self.ax5 ? "ax5" : "default")")
        }
    }

    /// An instrument change updates both the drawn row and its spoken summary even when
    /// the same update removes other songs from the collection.
    @MainActor
    func testChangingInstrumentUpdatesRetainedSongs() {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { app.terminate() }
        let pulseID = "fst.songs.row.fixture-pulse"
        let pulse = app.buttons[pulseID]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(orbit.waitForExistence(timeout: FestivalApp.budget(20)))
        let scored = app.buttons.matching(identifier: pulseID).matching(
            NSPredicate(format: "label CONTAINS %@", "Lead, scored")
        ).firstMatch
        XCTAssertTrue(scored.waitForExistence(timeout: FestivalApp.budget(15)))
        let chips = app.descendants(matching: .any)["fst.songs.instrument-status.fixture-pulse"]
        XCTAssertTrue(chips.exists)
        openFilter(in: app)
        let instruments = app.buttons.matching(identifier: "fst.songs.filter.instrument")
        let bass = instruments.matching(NSPredicate(format: "label == %@", "Bass")).firstMatch
        SongsUITestSupport.revealFilterOption(bass, in: app).tap()
        XCTAssertTrue(bass.isSelected)
        let done = app.buttons["fst.songs.filter.done"]
        done.tap()
        XCTAssertTrue(orbit.waitForNonExistence(timeout: FestivalApp.budget(10)))
        let summary = app.descendants(matching: .any)["fst.songs.profile-summary.fixture-pulse"]
        XCTAssertTrue(summary.waitForExistence(timeout: FestivalApp.budget(10)), "A retained row still describes all charts")
        XCTAssertTrue(pulse.isHittable)
        XCTAssertFalse(chips.exists)
        XCTAssertFalse(pulse.label.contains("Lead, scored"), pulse.label)
        XCTAssertTrue(pulse.label.contains(summary.label), pulse.label)
        assertTarget(pulse, "Retained Bass song")

        openFilter(in: app)
        let all = instruments.matching(NSPredicate(format: "label == %@", "All Instruments")).firstMatch
        SongsUITestSupport.revealFilterOption(all, in: app).tap()
        done.tap()
        XCTAssertTrue(orbit.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertTrue(scored.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertTrue(chips.exists)
        XCTAssertFalse(summary.exists)
    }
    #endif

    /// Year exposes the bulk actions before its disclosure and hides them again on collapse.
    @MainActor
    func testYearFilterBulkActionsFollowTheDisclosure() {
        continueAfterFailure = false
        let app = fixtureApp()
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: FestivalApp.budget(20)))
        openFilter(in: app)
        assertBucketActions("year", title: "Year", choice: "2020", in: app)
        assertResetFollows("fst.songs.filter.double-bass", in: app)
    }

    #if FST_UIKIT_PORT
    /// A visible bulk header uses the titled gap without shrinking either 44 pt action.
    @MainActor
    func testDurationFilterUsesTitledSpacingWhileExpanded() {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: FestivalApp.budget(20)))
        openFilter(in: app)
        let year = app.buttons["fst.songs.filter.year"]
        let duration = app.buttons["fst.songs.filter.duration"]
        let select = app.buttons["fst.songs.filter.duration.select-all"]
        XCTAssertTrue(year.exists && duration.isHittable)
        XCTAssertEqual(duration.frame.minY - year.frame.maxY, 35, accuracy: 1)
        duration.tap()
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        assertTarget(select, "Select All, Duration")
        XCTAssertEqual(select.frame.minY - year.frame.maxY, 28, accuracy: 1)
        duration.tap()
        XCTAssertTrue(select.waitForNonExistence(timeout: 5))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(duration.frame.minY - year.frame.maxY - 35) <= 1
        }, object: duration)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }
    #endif

    /// Single-chart Stars exposes the same header actions as a General bucket.
    @MainActor
    func testStarsFilterBulkActionsFollowTheInstrument() {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-pulse"].waitForExistence(timeout: FestivalApp.budget(20)))
        openFilter(in: app)
        XCTAssertFalse(app.buttons["fst.songs.filter.stars"].exists)
        let lead = app.buttons.matching(identifier: "fst.songs.filter.instrument").matching(
            NSPredicate(format: "label == %@", "Lead")
        ).firstMatch
        SongsUITestSupport.revealFilterOption(lead, in: app).tap()
        assertBucketActions("stars", title: "Stars", choice: "6", in: app)
        assertResetFollows("fst.songs.filter.intensity", in: app)

        let allInstruments = app.buttons.matching(identifier: "fst.songs.filter.instrument").matching(
            NSPredicate(format: "label == %@", "All Instruments")
        ).firstMatch
        let form = app.collectionViews["fst.songs.filter.form"]
        for _ in 0..<6 where !allInstruments.isHittable { form.swipeDown() }
        XCTAssertTrue(allInstruments.isHittable)
        allInstruments.tap()
        XCTAssertTrue(app.buttons["fst.songs.filter.intensity"].waitForNonExistence(timeout: 5))
        assertResetFollows("Filtering to a single instrument enables more filters.", in: app, isFootnote: true)
    }

    /// Excluding the fixture's five-star Lead bucket filters both songs and survives reopening.
    @MainActor
    func testStarsFilterChangesSongsAndSurvivesReopening() {
        continueAfterFailure = false
        let app = fixtureApp(profile: true, size: UIContentSizeCategory.large.rawValue)
        app.launch()
        defer { app.terminate() }
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertTrue(orbit.exists)

        let done = app.buttons["fst.songs.filter.done"]
        let stars = app.buttons["fst.songs.filter.stars"]
        let lead = app.buttons.matching(identifier: "fst.songs.filter.instrument").matching(
            NSPredicate(format: "label == %@", "Lead")
        ).firstMatch
        openFilter(in: app)
        revealFilterControl(lead, in: app)
        lead.tap()
        done.tap()
        XCTAssertTrue(pulse.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertTrue(orbit.exists, "Selecting the Lead chart alone must retain both fixture songs")

        openFilter(in: app)
        revealFilterControl(stars, in: app)
        expandFilterDisclosure(stars)
        let five = app.switches["fst.songs.filter.stars.5"]
        revealFilterControl(five, in: app)
        XCTAssertEqual(five.label, "5 stars")
        XCTAssertTrue(five.isEnabled)
        XCTAssertEqual(five.value as? String, "1")
        assertTarget(five, "5 stars")
        setFilterSwitch(five, to: "0")
        done.tap()

        let empty = app.staticTexts["No songs match your filters."]
        XCTAssertTrue(empty.waitForExistence(timeout: FestivalApp.budget(10)))
        let title = app.staticTexts["No Results"]
        XCTAssertTrue(title.exists)
        XCTAssertFalse(pulse.exists)
        XCTAssertFalse(orbit.exists)
        SongsUITestSupport.record(app, name: "stars-filter-no-results")
        if app.windows.firstMatch.frame.size == CGSize(width: 466, height: 678) {
            XCTAssertEqual(title.frame.midX, 191, accuracy: 2, "The status must center clear of the cover rail")
            XCTAssertEqual(title.frame.midY, 350, accuracy: 4, "The status must center above the bottom Filter Songs field")
        }

        openFilter(in: app)
        let score = app.buttons["fst.songs.filter.score-sections"]
        revealFilterControl(score, in: app)
        if score.value as? String == "Expanded" { score.tap() }
        revealFilterControl(stars, in: app)
        XCTAssertEqual(stars.value as? String, "Expanded")
        revealFilterControl(five, in: app)
        XCTAssertEqual(five.value as? String, "0")
        SongsUITestSupport.record(app, name: "stars-filter-reopened")

        let reset = app.buttons["fst.songs.filter.reset"]
        revealFilterControl(reset, in: app)
        reset.tap()
        XCTAssertTrue(stars.waitForNonExistence(timeout: FestivalApp.budget(5)))
        done.tap()
        XCTAssertTrue(pulse.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertTrue(orbit.exists)
        XCTAssertFalse(empty.exists)
        SongsUITestSupport.record(app, name: "stars-filter-reset")
    }

    /// A Lead intensity exclusion removes Pulse but keeps Orbit, which is in another bucket.
    @MainActor
    func testIntensityFilterKeepsSongsInOtherBuckets() {
        continueAfterFailure = false
        let app = fixtureApp(profile: true)
        app.launch()
        defer { app.terminate() }
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        XCTAssertTrue(pulse.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertTrue(orbit.exists)

        openFilter(in: app)
        let lead = app.buttons.matching(identifier: "fst.songs.filter.instrument").matching(
            NSPredicate(format: "label == %@", "Lead")
        ).firstMatch
        revealFilterControl(lead, in: app)
        lead.tap()
        let intensity = app.buttons["fst.songs.filter.intensity"]
        revealFilterControl(intensity, in: app)
        expandFilterDisclosure(intensity)
        let pulseBucket = app.switches["fst.songs.filter.intensity.3"]
        revealFilterControl(pulseBucket, in: app)
        XCTAssertEqual(pulseBucket.label, "Intensity 3 of 7")
        XCTAssertTrue(pulseBucket.isEnabled)
        XCTAssertEqual(pulseBucket.value as? String, "1")
        assertTarget(pulseBucket, "Intensity 3 of 7")
        setFilterSwitch(pulseBucket, to: "0")
        SongsUITestSupport.record(app, name: "intensity-filter-three-off")

        app.buttons["fst.songs.filter.done"].tap()
        XCTAssertTrue(orbit.waitForExistence(timeout: FestivalApp.budget(10)))
        XCTAssertTrue(pulse.waitForNonExistence(timeout: FestivalApp.budget(10)))
        XCTAssertTrue(orbit.isHittable)
        SongsUITestSupport.record(app, name: "intensity-filter-only-orbit")
    }

    /// The Stars No Score bucket includes a scored chart with no published star count.
    @MainActor
    func testStarsFilterDistinguishesGoldFromOmittedStars() {
        continueAfterFailure = false
        let app = launchDistinctScoreFilterFixture()
        defer { app.terminate() }
        openFilter(in: app)
        selectLead(in: app)
        revealLeadScoreBucket("stars", in: app)

        setScoreFilterChoice("stars.0", label: "No Score", to: "0", in: app)
        closeScoreFilter(in: app)
        assertScoreFilterSongs(pulse: true, orbit: false, capture: "stars-exclude-omitted", in: app)

        openFilter(in: app)
        revealLeadScoreBucket("stars", in: app)
        setScoreFilterChoice("stars.6", label: "5 gold stars", to: "0", in: app)
        setScoreFilterChoice("stars.0", label: "No Score", to: "1", in: app)
        closeScoreFilter(in: app)
        assertScoreFilterSongs(pulse: false, orbit: true, capture: "stars-exclude-gold", in: app)
    }

    /// Season and percentile each read the selected chart's metadata, not another chart's scores.
    @MainActor
    func testSeasonAndPercentileFiltersUseLeadMetadata() {
        continueAfterFailure = false
        let app = launchDistinctScoreFilterFixture()
        defer { app.terminate() }
        openFilter(in: app)
        selectLead(in: app)
        revealLeadScoreBucket("season", in: app)
        setScoreFilterChoice("season.8", label: "Season 8", to: "0", in: app)
        closeScoreFilter(in: app)
        assertScoreFilterSongs(pulse: true, orbit: false, capture: "season-exclude-eight", in: app)

        openFilter(in: app)
        revealLeadScoreBucket("season", in: app)
        setScoreFilterChoice("season.8", label: "Season 8", to: "1", in: app)
        revealLeadScoreBucket("percentile", in: app)
        setScoreFilterChoice("percentile.4", label: "Top 4%", to: "0", in: app)
        closeScoreFilter(in: app)
        assertScoreFilterSongs(pulse: false, orbit: true, capture: "percentile-exclude-top-four", in: app)
    }

    /// One Lead chart unlocks the three player sorts. Applying Score changes the rows;
    /// clearing the chart removes those choices and restores Title A–Z.
    @MainActor
    func testLeadScoreSortReordersSongsAndClearsWithChart() {
        continueAfterFailure = false
        let app = launchDistinctScoreFilterFixture(additionalArguments: ["-fst.settings.hideShop", "YES"])
        defer { app.terminate() }

        let done = app.buttons["fst.songs.sort.done"]
        func openSort() {
            ShellUITestSupport.tapToolbarItem("fst.songs.sort", overflowLabels: ["Sort"], in: app)
            XCTAssertTrue(done.waitForExistence(timeout: 10))
        }
        func mode(_ label: String) -> XCUIElement {
            app.buttons.matching(identifier: "fst.songs.sort.player-mode").matching(
                NSPredicate(format: "label == %@", label)
            ).firstMatch
        }
        func assertOrder(_ first: String, _ second: String) {
            let rows = [first, second].map { app.buttons["fst.songs.row.fixture-\($0)"] }
            for row in rows {
                XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(10)))
                XCTAssertTrue(row.isHittable && row.isEnabled)
            }
            XCTAssertLessThan(rows[0].frame.midY, rows[1].frame.midY)
        }

        openSort()
        let reset = app.buttons["fst.songs.sort.reset"]
        XCTAssertTrue(reset.isHittable)
        XCTAssertFalse(mode("Score").exists)
        reset.tap()
        done.tap()
        assertOrder("orbit", "pulse")

        openFilter(in: app)
        selectLead(in: app)
        closeScoreFilter(in: app)
        openSort()
        let score = mode("Score")
        for label in ["Score", "Percentile", "Stars"] {
            let choice = mode(label)
            SongsUITestSupport.revealSortControl(choice, in: app)
            XCTAssertTrue(choice.isEnabled)
            assertTarget(choice, label)
        }
        XCTAssertLessThan(score.frame.midY, mode("Percentile").frame.midY)
        XCTAssertLessThan(mode("Percentile").frame.midY, mode("Stars").frame.midY)
        score.tap()
        XCTAssertTrue(score.isSelected, "The chart-specific choice must expose its selected state")
        SongsUITestSupport.record(app, name: "songs-sort-lead-score-selected")
        let descending = app.buttons["fst.songs.sort.direction.descending"]
        SongsUITestSupport.revealSortControl(descending, in: app)
        descending.tap()
        XCTAssertTrue(descending.isSelected)
        done.tap()
        assertOrder("pulse", "orbit")
        SongsUITestSupport.record(app, name: "songs-sort-lead-score-descending")

        openFilter(in: app)
        let allCharts = app.buttons.matching(identifier: "fst.songs.filter.instrument").matching(
            NSPredicate(format: "label == %@", "All Instruments")
        ).firstMatch
        revealFilterControl(allCharts, in: app)
        allCharts.tap()
        closeScoreFilter(in: app)
        assertOrder("orbit", "pulse")
        openSort()
        XCTAssertTrue(reset.isHittable)
        XCTAssertFalse(mode("Score").exists)
        done.tap()
    }

    /// An enabled, named Item Shop choice below the initial Sort viewport changes the
    /// order, and Reset restores the title order.
    @MainActor
    func testAnonymousShopSortChoiceReordersSongs() {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_FIXTURE_SCENARIO"] = "shop-single"
        app.launchArguments += ["-fst.settings.hideShop", "NO"]
        app.launch()
        defer { app.terminate() }

        let done = app.buttons["fst.songs.sort.done"]
        func openSort() {
            ShellUITestSupport.tapToolbarItem("fst.songs.sort", overflowLabels: ["Sort"], in: app)
            XCTAssertTrue(done.waitForExistence(timeout: 10))
        }
        let orbit = app.buttons["fst.songs.row.fixture-orbit"]
        let pulse = app.buttons["fst.songs.row.fixture-pulse"]
        func assertOrder(_ first: XCUIElement, _ second: XCUIElement) {
            let order = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                first.exists && second.exists && first.frame.midY < second.frame.midY
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [order], timeout: 10), .completed)
        }
        XCTAssertTrue(orbit.waitForExistence(timeout: 15))

        openSort()
        SongsUITestSupport.revealSortReset(in: app).tap()
        done.tap()
        assertOrder(orbit, pulse)
        openSort()
        let shop = SongsUITestSupport.revealShopSort(in: app)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: shop)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        assertTarget(shop, "Item Shop")
        shop.tap()
        XCTAssertTrue(shop.isSelected)
        SongsUITestSupport.record(app, name: "songs-sort-item-shop-selected")
        done.tap()
        assertOrder(pulse, orbit)
        SongsUITestSupport.record(app, name: "songs-sort-item-shop-ascending")

        openSort()
        SongsUITestSupport.revealSortReset(in: app).tap()
        done.tap()
        assertOrder(orbit, pulse)
    }

    /// Checks intersect within Lead but a matching Pro Lead score can still pass independently.
    @MainActor
    func testScoreAndFCChecksIntersectWithinChartAndMatchAcrossCharts() {
        continueAfterFailure = false
        let app = launchDistinctScoreFilterFixture()
        defer { app.terminate() }
        openFilter(in: app)
        let score = app.buttons["fst.songs.filter.score-sections"]
        revealFilterControl(score, in: app)
        expandFilterDisclosure(score)
        openScoreChart("Solo_Guitar", in: app)
        setScoreFilterChoice("score.chart.Solo_Guitar.hasFCs", label: "Has Lead FCs", to: "1", in: app)
        closeScoreFilter(in: app)
        assertScoreFilterSongs(pulse: true, orbit: false, capture: "score-lead-full-combo", in: app)

        openFilter(in: app)
        openScoreChart("Solo_Guitar", in: app)
        setScoreFilterChoice("score.chart.Solo_Guitar.missingScores", label: "Missing Lead Scores", to: "1", in: app)
        closeScoreFilter(in: app)
        XCTAssertTrue(app.staticTexts["No songs match your filters."].waitForExistence(timeout: FestivalApp.budget(10)))
        assertScoreFilterSongs(pulse: false, orbit: false, capture: "score-contradictory-lead-checks", in: app)

        openFilter(in: app)
        openScoreChart("Solo_PeripheralGuitar", in: app)
        setScoreFilterChoice("score.chart.Solo_PeripheralGuitar.hasScores", label: "Has Pro Lead Scores", to: "1", in: app)
        closeScoreFilter(in: app)
        assertScoreFilterSongs(pulse: false, orbit: true, capture: "score-matched-pro-lead", in: app)
    }

    @MainActor
    private func launchDistinctScoreFilterFixture(additionalArguments: [String] = []) -> XCUIApplication {
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue)
        app.launchEnvironment["FST_DEBUG_PROFILE"] = "fixture-song-filters:Fixture Song Filters"
        app.launchArguments += ["-fst.settings.showInstrumentIcons", "YES", "-fst.settings.filterInvalidScores", "NO"]
            + additionalArguments
        app.launch()
        for (song, chartStatus) in [("pulse", "Lead, full combo"), ("orbit", "Pro Lead, scored")] {
            let scored = app.buttons.matching(identifier: "fst.songs.row.fixture-\(song)").matching(
                NSPredicate(format: "label CONTAINS %@", chartStatus)
            ).firstMatch
            XCTAssertTrue(scored.waitForExistence(timeout: FestivalApp.budget(20)), "Missing \(song) with \(chartStatus)")
        }
        XCTAssertTrue(app.buttons["fst.songs.row.fixture-orbit"].label.contains("Lead, scored"))
        return app
    }

    @MainActor
    private func selectLead(in app: XCUIApplication) {
        let lead = app.buttons.matching(identifier: "fst.songs.filter.instrument").matching(
            NSPredicate(format: "label == %@", "Lead")
        ).firstMatch
        revealFilterControl(lead, in: app)
        lead.tap()
    }

    @MainActor
    private func revealLeadScoreBucket(_ kind: String, in app: XCUIApplication) {
        let score = app.buttons["fst.songs.filter.score-sections"]
        if score.exists, score.value as? String == "Expanded" {
            revealFilterControl(score, in: app)
            score.tap()
        }
        let bucket = app.buttons["fst.songs.filter.\(kind)"]
        revealFilterControl(bucket, in: app)
        if bucket.value as? String != "Expanded" { expandFilterDisclosure(bucket) }
    }

    @MainActor
    private func openScoreChart(_ chart: String, in app: XCUIApplication) {
        let disclosure = app.descendants(matching: .any)["fst.songs.filter.score.instrument.\(chart)"].firstMatch
        revealFilterControl(disclosure, in: app)
        disclosure.tap()
    }

    @MainActor
    private func setScoreFilterChoice(_ suffix: String, label: String, to value: String, in app: XCUIApplication) {
        let control = app.switches["fst.songs.filter.\(suffix)"]
        revealFilterControl(control, in: app)
        XCTAssertEqual(control.label, label)
        XCTAssertTrue(control.isEnabled)
        XCTAssertEqual(control.value as? String, value == "0" ? "1" : "0")
        assertTarget(control, label)
        setFilterSwitch(control, to: value)
    }

    @MainActor
    private func closeScoreFilter(in app: XCUIApplication) {
        let done = app.buttons["fst.songs.filter.done"]
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: FestivalApp.budget(10)))
    }

    @MainActor
    private func assertScoreFilterSongs(pulse: Bool, orbit: Bool, capture: String, in app: XCUIApplication) {
        for (name, expected) in [("pulse", pulse), ("orbit", orbit)] {
            let song = app.buttons["fst.songs.row.fixture-\(name)"]
            if expected {
                XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(10)))
                XCTAssertTrue(song.isHittable, "\(capture): \(name) should be reachable")
            } else {
                XCTAssertTrue(song.waitForNonExistence(timeout: FestivalApp.budget(10)), "\(capture): \(name) was not filtered out")
            }
        }
        SongsUITestSupport.record(app, name: capture)
    }

    @MainActor
    private func assertResetFollows(_ predecessor: String, in app: XCUIApplication, isFootnote: Bool = false) {
        let reset = SongsUITestSupport.revealFilterReset(in: app)
        let prior = isFootnote ? app.staticTexts[predecessor] : app.buttons[predecessor]
        XCTAssertTrue(prior.exists)
        XCTAssertGreaterThan(reset.frame.minY, prior.frame.maxY)
        XCTAssertLessThanOrEqual(reset.frame.minY - prior.frame.maxY, 48, "A hidden section left a blank row before Reset")
    }

    @MainActor
    private func assertBucketActions(_ bucket: String, title: String, choice: String, in app: XCUIApplication) {
        let id = "fst.songs.filter.\(bucket)"
        let group = app.buttons[id]
        let select = app.buttons["\(id).select-all"]
        let clear = app.buttons["\(id).clear-all"]
        XCTAssertFalse(select.exists)
        XCTAssertFalse(clear.exists)
        SongsUITestSupport.revealFilterOption(group, in: app).tap()
        XCTAssertTrue(select.waitForExistence(timeout: 5))
        XCTAssertTrue(clear.exists)
        XCTAssertEqual(group.value as? String, "Expanded")
        XCTAssertEqual(select.label, "Select All, \(title)")
        XCTAssertEqual(clear.label, "Clear All, \(title)")
        assertTarget(select, "Select All, \(title)")
        assertTarget(clear, "Clear All, \(title)")
        XCTAssertLessThanOrEqual(max(select.frame.maxY, clear.frame.maxY), group.frame.minY)
        let option = app.switches["\(id).\(choice)"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        XCTAssertEqual(option.value as? String, "1")
        clear.tap()
        XCTAssertEqual(option.value as? String, "0")
        select.tap()
        XCTAssertEqual(option.value as? String, "1")
        group.tap()
        XCTAssertEqual(group.value as? String, "Collapsed")
        XCTAssertTrue(select.waitForNonExistence(timeout: 5))
        XCTAssertFalse(clear.exists)
    }

    /// At the largest text size rows wrap and grow, stay buttons and the tools keep 44 pt targets.
    @MainActor
    func testSongsAtLargestTextGrowAndStayReachable() throws {
        continueAfterFailure = false
        let normal = fixtureApp()
        normal.launch()
        let row = normal.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(row.waitForExistence(timeout: FestivalApp.budget(20)))
        let normalHeight = row.frame.height
        normal.terminate()

        let large = fixtureApp(size: Self.ax5)
        large.launch()
        let grown = large.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(grown.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertGreaterThan(grown.frame.height, normalHeight, "The row did not grow at AX5")
        XCTAssertLessThanOrEqual(grown.frame.width, large.windows.firstMatch.frame.width)
        let tools = large.buttons["fst.songs.tools"]
        XCTAssertTrue(tools.waitForExistence(timeout: 10) || large.buttons["fst.songs.sort"].exists)
    }

    // MARK: Item Shop

    /// The animated Shop decoration is not a separate accessibility stop or tap target.
    @MainActor
    func testFloatingSongDetailShopLinkKeepsItsStatusAndTargetAtAX5() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = fixtureApp(size: Self.ax5)
        app.launchArguments += ["-fst.settings.hideShop", "NO", "-fst.settings.disableShopHighlighting", "NO"]
        app.launch()
        defer { app.terminate() }
        if (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
           app.windows.firstMatch.frame.width < 500 {
            throw XCTSkip("The Duo cover uses system bar items, not floating page tools")
        }
        let song = app.buttons["fst.songs.row.fixture-pulse"]
        XCTAssertTrue(song.waitForExistence(timeout: FestivalApp.budget(20)))
        song.tap()
        let tools = app.descendants(matching: .any)["fst.page-tools"].firstMatch
        XCTAssertTrue(tools.waitForExistence(timeout: 10))
        let shop = tools.links["fst.song-detail.shop"]
        XCTAssertTrue(shop.waitForExistence(timeout: 10))
        XCTAssertEqual(shop.label, "Item Shop, New in the Item Shop")
        XCTAssertTrue(shop.isHittable)
        assertTarget(shop, "Item Shop")
        XCTAssertEqual(tools.descendants(matching: .any).matching(identifier: "fst.song-detail.shop").count, 1)
        SongsUITestSupport.record(app, name: "song-detail-floating-shop-ax5")
    }

    /// The Item Shop lists each public offer with its official Shop link.
    @MainActor
    func testShopOffersExposeOfficialLinks() throws {
        continueAfterFailure = false
        let app = fixtureApp(route: "shop")
        app.launch()
        let link = app.links["fst.shop.external.fixture-pulse"]
        XCTAssertTrue(link.waitForExistence(timeout: FestivalApp.budget(25)))
        XCTAssertTrue(link.label.contains("Open Official Item Shop"), "Link label: \(link.label)")
        let sort = app.buttons["fst.shop.sort"]
        XCTAssertTrue(sort.exists)
        XCTAssertEqual(sort.label, "Sort Item Shop")
        XCTAssertEqual(sort.value as? String, "Title, ascending")
        let filter = app.buttons["fst.shop.filter"]
        XCTAssertTrue(filter.exists)
        XCTAssertEqual(filter.label, "Filter Item Shop")
        XCTAssertEqual(filter.value as? String, "No filters")
    }

    /// A wide Shop can switch layouts without keeping the old cell's actions.
    @MainActor
    func testShopLayoutSwitchReplacesOfferActions() throws {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue, route: "shop")
        app.launch()
        defer { app.terminate() }
        guard app.windows.firstMatch.frame.width > 600 else {
            throw XCTSkip("The Shop layout switch requires a wide display")
        }
        let toggle = app.buttons["fst.shop.view-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: FestivalApp.budget(20)))
        let initialGrid = toggle.label == "List View"
        let detail = app.buttons["fst.shop.song.fixture-pulse"]
        let link = app.links["fst.shop.external.fixture-pulse"]

        let stages = [initialGrid, !initialGrid, initialGrid]
        for (index, grid) in stages.enumerated() {
            let label = grid ? "Fixture Pulse, Synthetic Quartet, New, Open Official Item Shop"
                : "Fixture Pulse, Open Official Item Shop"
            let match = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hittable == YES AND label == %@", label), object: link
            )
            XCTAssertEqual(XCTWaiter.wait(for: [match], timeout: FestivalApp.budget(15)), .completed)
            XCTAssertEqual(detail.exists, !grid)
            XCTAssertEqual(toggle.label, grid ? "List View" : "Grid View")
            if grid {
                XCTAssertGreaterThan(link.frame.height, 44)
            } else {
                XCTAssertTrue(detail.isHittable)
                XCTAssertGreaterThanOrEqual(link.frame.height, 44)
            }
            if index < stages.count - 1 { toggle.tap() }
        }
    }

    /// Bending a wide App Shop layout reflows the same links around the fold without leaving Shop.
    @MainActor
    func testShopWideOffersReflowAroundBookFold() throws {
        continueAfterFailure = false
        for grid in [false, true] {
            let app = fixtureApp(size: UIContentSizeCategory.large.rawValue, route: "shop")
            app.launchEnvironment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            app.launchEnvironment["FST_DEBUG_DUO_WINDOW"] = "unfolded-landscape"
            app.launchArguments += ["-fst.shop.viewMode", grid ? "grid" : "list", "-fst.accessibility.reduceMotion", "YES"]
            app.launch()
            defer { app.terminate() }

            let viewport = app.windows.firstMatch.frame
            guard viewport.width > 850, viewport.width > viewport.height else {
                throw XCTSkip("The Shop book journey needs a landscape inner display")
            }
            let orbitLink = app.links["fst.shop.external.fixture-orbit"]
            let pulseLink = app.links["fst.shop.external.fixture-pulse"]
            let orbit = grid ? orbitLink : app.buttons["fst.shop.song.fixture-orbit"]
            let pulse = grid ? pulseLink : app.buttons["fst.shop.song.fixture-pulse"]
            XCTAssertTrue(orbit.waitForExistence(timeout: FestivalApp.budget(20)))
            XCTAssertTrue(pulse.isHittable)
            let flatOrbit = orbit.frame
            let flatPulse = pulse.frame
            let readout = app.descendants(matching: .any)["fst.shell.debug.duo-window"].firstMatch

            DuoWindowSwitch.post("book")
            let book = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", " fold="), object: readout)
            XCTAssertEqual(XCTWaiter.wait(for: [book], timeout: 10), .completed)
            let foldValue = try XCTUnwrap(readout.label.components(separatedBy: " fold=").last.flatMap(Double.init))
            let foldX = viewport.minX + CGFloat(foldValue)
            XCTAssertTrue(orbit.isHittable && pulse.isHittable)
            XCTAssertEqual(orbit.frame.minY, pulse.frame.minY, accuracy: 1)
            XCTAssertLessThanOrEqual(orbit.frame.maxX, foldX - 11)
            if grid {
                XCTAssertEqual(pulse.frame.maxX, foldX - 12, accuracy: 1)
                XCTAssertEqual(pulse.frame.width, pulse.frame.height, accuracy: 1)
                XCTAssertFalse(app.buttons["fst.shop.song.fixture-pulse"].exists)
            } else {
                XCTAssertEqual(pulse.frame.minX, foldX + 12, accuracy: 1)
                XCTAssertTrue(orbitLink.isHittable && pulseLink.isHittable)
                assertTarget(pulseLink, "Fixture Pulse official Shop link")
            }

            DuoWindowSwitch.post("unfolded-landscape")
            let flat = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@", "unfolded-landscape"), object: readout)
            XCTAssertEqual(XCTWaiter.wait(for: [flat], timeout: 10), .completed)
            XCTAssertEqual(orbit.frame.width, flatOrbit.width, accuracy: 1)
            XCTAssertEqual(pulse.frame.minX, flatPulse.minX, accuracy: 1)
        }
    }

    /// The held Shop exposes one busy indicator centred clear of the tab bar or folded rail.
    @MainActor
    func testShopLoadingUsesTheVisibleResultRegion() async throws {
        try await Self.setShopHold("hold")
        addTeardownBlock { try await Self.setShopHold("release") }
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue, route: "shop")
        app.launch()
        defer { app.terminate() }

        let loading = app.activityIndicators.matching(NSPredicate(format: "label == %@", "Loading Item Shop"))
        let spinner = loading.firstMatch
        XCTAssertTrue(spinner.waitForExistence(timeout: FestivalApp.budget(10)))
        let frame = try spinner.snapshot().frame
        XCTAssertEqual(loading.count, 1)
        XCTAssertEqual(frame.width, 48, accuracy: 1)
        let window = app.windows.firstMatch.frame
        switch window.size {
        case CGSize(width: 402, height: 874):
            XCTAssertEqual(frame.midX, window.midX, accuracy: 1)
            XCTAssertEqual(frame.midY, window.minY + 424, accuracy: 4)
        case CGSize(width: 466, height: 678):
            let filter = app.buttons["fst.shop.filter"]
            XCTAssertTrue(filter.isHittable)
            XCTAssertLessThan(frame.maxX, filter.frame.minX)
            XCTAssertEqual(frame.midX, window.minX + 191, accuracy: 2)
            XCTAssertEqual(frame.midY, window.minY + 363, accuracy: 4)
        default:
            XCTAssertTrue(window.contains(frame))
        }
        XCTAssertFalse(app.links["fst.shop.external.fixture-pulse"].exists)
        try await Self.setShopHold("release")
        let first = app.buttons["fst.shop.song.fixture-orbit"]
        let second = app.buttons["fst.shop.song.fixture-pulse"]
        let link = app.links["fst.shop.external.fixture-pulse"]
        XCTAssertTrue(link.waitForExistence(timeout: FestivalApp.budget(20)))
        XCTAssertFalse(spinner.exists)
        XCTAssertTrue(first.isHittable && second.isHittable && link.isHittable)
        XCTAssertLessThan(first.frame.midY, second.frame.midY)
        XCTAssertEqual(link.label, "Fixture Pulse, Open Official Item Shop")
    }

    /// The filtered empty state uses the usable page width and draws readable text at AX5.
    @MainActor
    func testShopFilteredEmptyTextFitsSafeAreaAndScalesWithoutClipping() throws {
        continueAfterFailure = false
        let expected = "No Item Shop songs match your filters"
        let expectedSubtitle = "Try changing your filters to see more songs."
        let normal = fixtureApp(size: UIContentSizeCategory.large.rawValue, route: "shop")
        normal.launch()
        defer { normal.terminate() }
        resetShopFilters(in: normal)
        for id in ["new", "leavingTomorrow"] {
            SongsUITestSupport.setSwitch(normal.switches["fst.shop.filter.\(id)"], to: "0")
        }
        normal.buttons["fst.shop.filter.done"].tap()
        let defaultHeight = try shopEmptyTitleHeight(expected, in: normal)
        let normalSubtitle = normal.staticTexts[expectedSubtitle]
        XCTAssertTrue(normalSubtitle.isHittable)
        if normal.windows.firstMatch.frame.size == CGSize(width: 466, height: 678) {
            let railFilter = normal.buttons["fst.shop.filter"]
            XCTAssertTrue(railFilter.isHittable)
            XCTAssertLessThanOrEqual(normal.staticTexts[expected].frame.maxX, railFilter.frame.minX)
            XCTAssertLessThanOrEqual(normalSubtitle.frame.maxX, railFilter.frame.minX)
        }
        XCTAssertNotNil(
            RecognizedText.recognizeLine(expectedSubtitle, in: normalSubtitle).lineHeight,
            "The subtitle fits on one line at default text size"
        )
        normal.terminate()

        let large = fixtureApp(size: Self.ax5, route: "shop")
        large.launch()
        defer { large.terminate() }
        let largeHeight = try shopEmptyTitleHeight(expected, in: large)
        XCTAssertGreaterThanOrEqual(largeHeight, defaultHeight * RecognizedText.minimumGrowth)
        let largeSubtitle = large.staticTexts[expectedSubtitle]
        XCTAssertTrue(largeSubtitle.isHittable)
        XCTAssertLessThan(large.staticTexts[expected].frame.maxY, largeSubtitle.frame.minY)
        let scroll = large.scrollViews.containing(.staticText, identifier: expectedSubtitle).firstMatch
        XCTAssertTrue(scroll.exists)
        if !scroll.frame.contains(largeSubtitle.frame) {
            scroll.swipeUp()
        }
        SongsUITestSupport.record(large, name: "shop-filter-empty-ax5")
        let renderedSubtitle = RecognizedText.recognize(largeSubtitle, label: expectedSubtitle, frame: largeSubtitle.frame)
        XCTAssertTrue(
            RecognizedText.showsWhole(expectedSubtitle, in: renderedSubtitle.text),
            "Rendered subtitle after revealing it: \(renderedSubtitle.text ?? "none")"
        )
        large.terminate()

        normal.launch()
        resetShopFilters(in: normal)
        normal.buttons["fst.shop.filter.done"].tap()
    }

    @MainActor
    private func resetShopFilters(in app: XCUIApplication) {
        let filter = app.buttons["fst.shop.filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: FestivalApp.budget(25)))
        filter.tap()
        let reset = app.buttons["fst.shop.filter.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: 10))
        reset.tap()
    }

    #if FST_UIKIT_PORT
    /// The Shop footer wraps on the same leading edge as its choices and leaves Reset in reach.
    @MainActor
    func testShopFilterFooterFollowsItsChoicesAndPrecedesReset() {
        continueAfterFailure = false
        let app = fixtureApp(size: UIContentSizeCategory.large.rawValue, route: "shop")
        app.launch()
        defer { app.terminate() }
        resetShopFilters(in: app)
        let form = app.collectionViews["fst.shop.filter.form"]
        let heading = form.staticTexts["Availability"]
        let leaving = form.staticTexts["Leaving Tomorrow"].firstMatch
        let footer = form.staticTexts["Turn a switch off to hide those offers. With every switch on, every offer shows."]
        let reset = form.buttons["fst.shop.filter.reset"]
        XCTAssertTrue(heading.exists && leaving.exists && footer.isHittable && reset.isHittable)
        XCTAssertEqual(footer.frame.minX, heading.frame.minX, accuracy: 1)
        XCTAssertEqual(footer.frame.minX, leaving.frame.minX, accuracy: 1)
        XCTAssertLessThan(heading.frame.maxY, leaving.frame.minY)
        XCTAssertLessThan(leaving.frame.maxY, footer.frame.minY)
        XCTAssertLessThan(footer.frame.maxY, reset.frame.minY)
        assertTarget(reset, "Reset Filters")
        if app.windows.firstMatch.frame.width <= 466 {
            XCTAssertEqual(reset.frame.midY - footer.frame.maxY, 49, accuracy: 2)
        }
        app.buttons["fst.shop.filter.done"].tap()
    }
    #endif

    @MainActor
    private func shopEmptyTitleHeight(_ expected: String, in app: XCUIApplication) throws -> CGFloat {
        let title = app.staticTexts[expected]
        XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(25)))
        let reading = RecognizedText.recognize(title, label: expected, frame: title.frame)
        XCTAssertTrue(RecognizedText.showsWhole(expected, in: reading.text), "Rendered title: \(reading.text ?? "none")")
        return try XCTUnwrap(reading.lineHeight)
    }

    private static func setShopHold(_ phase: String) async throws {
        var url = try XCTUnwrap(URLComponents(string: SongsUITestSupport.fixtureURL))
        guard url.scheme == "http", url.host == "127.0.0.1" || url.host == "localhost" else {
            throw XCTSkip("The Shop hold requires a loopback fixture")
        }
        url.path = "/__fixture__/hold-shop"
        url.queryItems = [URLQueryItem(name: "phase", value: phase)]
        let (data, response) = try await URLSession.shared.data(from: XCTUnwrap(url.url))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try JSONDecoder().decode([String: String].self, from: data)["phase"], phase)
    }
}
