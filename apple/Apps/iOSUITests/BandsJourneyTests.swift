import UIKit
import XCTest

/// Fixture-backed native journeys for Bands: a Band Rankings row pushing into Band
/// Detail and then into a catalog-linked song, and Player Bands paging past the
/// first page. Both rely on `tools/mock_service.py` fixture data this lane added
/// (`_band_ranking_entry`/`_band_detail`/`_player_band_entry`/
/// `_song_band_leaderboard_entry` — see `.agents/testing/fixtures.md`).
final class BandsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp(
        route: String, contentSize: UIContentSizeCategory? = nil, experimentalRanks: Bool = false
    ) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:18790",
            "FST_DEBUG_ROUTE": route,
        ])
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        }
        // Settings › Experimental Ranks (`ExperimentalRanks.storageKey`), explicit either way.
        app.launchArguments += ["-fst.settings.experimentalRanks", experimentalRanks ? "YES" : "NO"]
        return app
    }

    /// Band Rankings (rank 1, `fixture-team-1`) → Band Detail → its catalog-linked
    /// "fixture-pulse" Best song → Song Detail.
    @MainActor
    func testBandRankingsRowOpensBandDetailThenSong() throws {
        continueAfterFailure = false
        let app = fixtureApp(route: "bandRankings:Band_Duets")
        app.launch()

        let row = app.descendants(matching: .any)
            .matching(identifier: "fst.band-rankings.row.fixture-team-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "band-rankings-loaded")
        row.tap()

        let membersSection = app.descendants(matching: .any)
            .matching(identifier: "fst.band.members-section").firstMatch
        XCTAssertTrue(
            membersSection.waitForExistence(timeout: 15),
            "Band Detail never loaded: \(app.staticTexts.allElementsBoundByIndex.prefix(12).map(\.label))"
        )
        SongsUITestSupport.record(app, name: "band-detail-loaded")

        let songRow = app.descendants(matching: .any)
            .matching(identifier: "fst.band.song-row.fixture-pulse").firstMatch
        for _ in 0..<8 {
            if songRow.exists && songRow.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(songRow.exists, "Catalog-linked Best song row is missing")
        XCTAssertTrue(songRow.isHittable, "Best song row is not reachable by scrolling")
        songRow.tap()

        let intensity = app.descendants(matching: .any).matching(identifier: "fst.song-detail.intensity").firstMatch
        XCTAssertTrue(
            intensity.waitForExistence(timeout: 15),
            "Tapping the band's Best song never reached Song Detail"
        )
        SongsUITestSupport.record(app, name: "band-song-opened-song-detail")
    }

    /// The pushed page's scrim darkens both edges without taking focus or member taps.
    @MainActor
    func testBandDetailScrimExtendsUnderBothEdges() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Requires a phone or the Duo cover")
        continueAfterFailure = false
        let app = openBandDetail(contentSize: .large, flatBackdrop: true)
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        try XCTSkipUnless(window.width < 500 && window.height > window.width, "Requires a portrait phone viewport")
        try SongsUITestSupport.assertPageScrim(in: app, window: window)

        let members = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.band.member."))
        XCTAssertEqual(members.allElementsBoundByIndex.map(\.label), [
            "View Band 1 Member A, Lead", "View Band 1 Member B, Bass",
        ])
        let member = members.firstMatch
        XCTAssertTrue(member.isHittable && member.isEnabled)
        XCTAssertGreaterThanOrEqual(member.frame.height, 44)
        XCTAssertFalse(app.buttons["fst.player.select"].exists)
        member.tap()
        XCTAssertTrue(app.scrollViews["fst.player.available"].waitForExistence(timeout: FestivalApp.budget(15)))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Select Profile")).firstMatch.isEnabled)
    }

    /// An unresolvable link stays readable in the content lane, not under Duo's rail.
    @MainActor
    func testUnresolvedBandOccupiesTheVisiblePageAtDefaultAndLargestTextSizes() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Requires an iPhone or the Duo cover")
        continueAfterFailure = false
        var defaultTitleHeight: CGFloat = 0
        for size in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let app = fixtureApp(route: "band:fixture-unresolved", contentSize: size)
            app.launchEnvironment["FST_DEBUG_TAB"] = "settings"
            app.launch()
            defer { app.terminate() }

            let window = app.windows.firstMatch
            let isDuo = (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo")
            let railOnCover = abs(window.frame.width - 466) < 1 && abs(window.frame.height - 678) < 1
            try XCTSkipIf(isDuo && !railOnCover, "Requires the upright Duo cover")
            let state = app.descendants(matching: .any)["fst.band.unresolved"].firstMatch
            XCTAssertTrue(state.waitForExistence(timeout: FestivalApp.budget(15)))
            let search = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "label == %@", "Search"))
                .allElementsBoundByIndex.first(where: \.isHittable))
            let title = state.staticTexts["Band Not Available"].firstMatch
            let subtitle = state.staticTexts[
                "Open this band from Player Bands, Band Rankings or a song's Band Scores to see its details."
            ].firstMatch
            XCTAssertTrue(title.exists && title.isHittable)
            XCTAssertTrue(subtitle.exists)
            XCTAssertLessThan(title.frame.maxY, subtitle.frame.minY, "The heading must come before its explanation")
            XCTAssertEqual(state.staticTexts.allElementsBoundByIndex.map(\.label), [title.label, subtitle.label])
            XCTAssertFalse(app.buttons["fst.quick-links.open"].exists)
            XCTAssertFalse(app.buttons["fst.service-status.retry"].exists)
            let profile = app.buttons["fst.shell.profile"].firstMatch
            XCTAssertTrue(profile.exists && profile.isHittable)
            XCTAssertEqual(profile.label, "Choose Profile")
            XCTAssertFalse(app.buttons["fst.shell.notifications"].exists)

            if railOnCover {
                XCTAssertLessThanOrEqual(subtitle.frame.maxX, search.frame.minX - 24)
                XCTAssertEqual(subtitle.frame.midX, window.frame.minX + 191, accuracy: 2)
            } else {
                XCTAssertEqual(subtitle.frame.midX, window.frame.midX, accuracy: 2)
            }

            if size == .large {
                defaultTitleHeight = title.frame.height
                XCTAssertTrue(subtitle.isHittable)
            } else {
                XCTAssertGreaterThan(title.frame.height, defaultTitleHeight * 1.35)
                let viewportBottom = railOnCover ? window.frame.maxY : search.frame.minY
                let drag = window.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.74))
                for _ in 0..<3 where subtitle.frame.maxY > viewportBottom - 8 {
                    drag.press(forDuration: 0.05, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: -180)))
                }
                XCTAssertTrue(subtitle.isHittable)
                XCTAssertLessThanOrEqual(subtitle.frame.maxY, viewportBottom - 8)
            }
            SongsUITestSupport.record(app, name: "band-unresolved-\(size.rawValue)")
            if size == .large {
                // The system's actual hit region is wider than its reported symbol frame.
                profile.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .withOffset(CGVector(dx: 20, dy: 0)).tap()
                XCTAssertTrue(app.buttons["fst.profile.close"].waitForExistence(timeout: FestivalApp.budget(10)))
            }
        }
    }

    #if FST_UIKIT_PORT
    /// The empty history note keeps the content row's minimum before padding and can grow at AX5.
    @MainActor
    func testEmptyBandRankHistoryKeepsItsPaddedNote() throws {
        continueAfterFailure = false
        var defaultInkHeight: CGFloat = 0
        let subtitleCopy = "Any-combo ranking progression over the past 30 days."
        for size in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let app = fixtureApp(route: "bandRankings:Band_Duets", contentSize: size)
            app.launchArguments += ["-fst.accessibility.reduceMotion", "YES"]
            app.launch()
            defer { app.terminate() }

            let band = app.buttons["fst.band-rankings.row.fixture-team-2"]
            XCTAssertTrue(band.waitForExistence(timeout: FestivalApp.budget(15)))
            for _ in 0..<4 where !band.isHittable { app.swipeUp() }
            band.tap()

            let section = app.descendants(matching: .any)["fst.band.history-section"]
            XCTAssertTrue(section.waitForExistence(timeout: FestivalApp.budget(15)))
            let notes = section.staticTexts.matching(identifier: "fst.band.history-empty")
            let note = notes.firstMatch
            let window = app.windows.firstMatch
            let visible = window.frame.insetBy(dx: 0, dy: 95)
            let drag = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
            for _ in 0..<16 where !note.exists || !visible.contains(note.frame) {
                let delta = note.exists ? visible.midY - note.frame.midY : -230
                drag.press(forDuration: 0.05, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: max(-230, min(230, delta)))))
            }
            XCTAssertEqual(notes.count, 1)
            XCTAssertEqual(note.label, "No band rank history yet.")
            XCTAssertTrue(visible.contains(note.frame), "History note \(note.frame) is outside \(visible)")
            XCTAssertGreaterThanOrEqual(note.frame.height, 43.5)
            XCTAssertEqual(section.frame.maxY - note.frame.maxY, 6, accuracy: 0.7)
            XCTAssertTrue(section.buttons.allElementsBoundByIndex.isEmpty, "The empty note has no action")
            XCTAssertEqual(section.staticTexts.allElementsBoundByIndex.map(\.label),
                           ["Band Rank History", subtitleCopy, note.label])

            let lines = RecognizedText.lines(in: note.screenshot())
            XCTAssertTrue(
                RecognizedText.showsWhole(note.label, in: lines.map(\.text).joined(separator: " ")),
                "The whole empty note should be painted: \(lines)"
            )
            let inkHeight = try XCTUnwrap(lines.map(\.frame.height).max())
            if size == .large {
                defaultInkHeight = inkHeight
                XCTAssertEqual(note.frame.height, 44, accuracy: 0.7)
                let subtitle = section.staticTexts[subtitleCopy]
                XCTAssertTrue(visible.contains(subtitle.frame))
                let viewport = window.frame.size
                if viewport == CGSize(width: 402, height: 874) || viewport == CGSize(width: 466, height: 678) {
                    XCTAssertEqual(subtitle.frame.height, 38, accuracy: 0.7, "Keep the wrapped subtitle leading")
                }
                let subtitleLines = RecognizedText.lines(in: subtitle.screenshot()).map(\.text)
                XCTAssertTrue(RecognizedText.showsWhole(subtitleCopy, in: subtitleLines.joined(separator: " ")))
            } else {
                XCTAssertGreaterThan(inkHeight, defaultInkHeight * RecognizedText.minimumGrowth)
            }
            SongsUITestSupport.record(app, name: "band-empty-history-\(size == .large ? "large" : "ax5")")
        }
    }

    /// Empty song cards stay readable in order below the native edge, including AX5 with Less Transparency.
    @MainActor
    func testEmptyBandSongCardsKeepWrappedCopyAndReadingOrder() throws {
        continueAfterFailure = false
        var defaultInkHeight: [String: CGFloat] = [:]
        for size in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let app = openBandDetail(
                contentSize: size, teamKey: "fixture-team-2", lessTransparency: size != .large
            )
            defer { app.terminate() }
            let window = app.windows.firstMatch
            let isDuo = (ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo")
            let isCover = abs(window.frame.width - 466) < 1 && abs(window.frame.height - 678) < 1
            try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone && (!isDuo || isCover),
                              "Requires an iPhone or upright Duo cover")

            let page = app.descendants(matching: .any)["fst.band.songs-section"].firstMatch
            XCTAssertTrue(page.waitForExistence(timeout: FestivalApp.budget(15)))
            let bar = app.navigationBars["Band 2 Member A + Band 2 Member B"]
            XCTAssertTrue(bar.exists)
            let visible = window.frame.inset(by: UIEdgeInsets(
                top: 116, left: 0, bottom: isCover ? 20 : 92, right: isCover ? 84 : 0
            ))
            for (id, heading, title, rank) in [
                ("best", "Five Best Songs", "No ranked band songs yet.", "highest"),
                ("worst", "Five Worst Songs", "No additional ranked band songs yet.", "lowest"),
            ] {
                let section = page.descendants(matching: .any)["fst.band.\(id)-songs"].firstMatch
                let messages = section.staticTexts.matching(identifier: "fst.band.\(id)-songs-empty")
                let message = messages.firstMatch
                let lines = try readEmptySongMessage(message, in: window, visible: visible)
                XCTAssertLessThanOrEqual(bar.frame.maxY, visible.minY + 1, "The scrolled bar must clear the reading region")
                XCTAssertEqual(messages.count, 1, "Each card is one static text element")
                XCTAssertTrue(section.buttons.allElementsBoundByIndex.isEmpty)
                let labels = section.staticTexts.allElementsBoundByIndex.map(\.label)
                XCTAssertEqual(labels.first, heading)
                XCTAssertEqual(labels.last, message.label)
                XCTAssertEqual(message.label, "\(title), Band 2 Member A + Band 2 Member B's \(rank)-ranked band songs, sorted by percentile.")

                XCTAssertTrue(
                    RecognizedText.showsWhole(message.label, in: lines.map(\.text).joined(separator: " ")),
                    "\(id): Incomplete rendered copy in \(lines)"
                )
                let inkHeight = try XCTUnwrap(lines.map(\.frame.height).max())
                if size == .large {
                    if isCover || window.frame.size == CGSize(width: 402, height: 874) {
                        XCTAssertEqual(message.frame.height, 58, accuracy: 0.8, "\(id): keep wrapped footnote leading")
                    }
                    defaultInkHeight[id] = inkHeight
                } else {
                    let normalInkHeight = try XCTUnwrap(defaultInkHeight[id])
                    XCTAssertGreaterThan(inkHeight, normalInkHeight * RecognizedText.minimumGrowth)
                }
            }
            let cards = page.staticTexts.matching(NSPredicate(format: "identifier IN %@", [
                "fst.band.best-songs-empty", "fst.band.worst-songs-empty",
            ]))
            XCTAssertEqual(cards.allElementsBoundByIndex.map(\.identifier),
                           ["fst.band.best-songs-empty", "fst.band.worst-songs-empty"])
        }
    }

    /// Read the painted message, following it down the viewport when it is taller than the Duo cover.
    ///
    /// - Parameters:
    ///   - message: The combined static text element.
    ///   - window: The upright app window.
    ///   - visible: The window's content region, clear of navigation and the cover rail.
    /// - Returns: Rendered text lines in message-relative order.
    @MainActor
    private func readEmptySongMessage(
        _ message: XCUIElement, in window: XCUIElement, visible: CGRect
    ) throws -> [(text: String, frame: CGRect)] {
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.32, dy: 0.55))
        func drag(_ distance: CGFloat, holding: Bool) {
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)),
                        withVelocity: holding ? .slow : .fast, thenHoldForDuration: holding ? 0.3 : 0)
        }
        for _ in 0..<14 {
            guard message.exists else { drag(-225, holding: false); continue }
            let frame = try XCTUnwrap(message.exists ? message.frame : nil, "Missing \(message.identifier)")
            let tall = frame.height > visible.height
            if visible.contains(frame) || (tall && visible.contains(CGPoint(x: frame.midX, y: frame.minY))) {
                break
            }
            let distance = tall ? visible.minY + 24 - frame.minY : visible.midY - frame.midY
            drag(max(-225, min(225, distance)), holding: abs(distance) < visible.height)
        }
        let frame = message.frame
        if visible.contains(frame) { return RecognizedText.lines(in: message.screenshot()) }
        XCTAssertTrue(visible.contains(CGPoint(x: frame.midX, y: frame.minY)), "Start of \(message.identifier) is not reachable")
        var lines: [(text: String, frame: CGRect)] = []
        for part in 0..<4 {
            let frame = message.frame
            let origin = window.frame.origin
            let region = visible.intersection(frame.insetBy(dx: -4, dy: 0))
                .offsetBy(dx: -origin.x, dy: -origin.y)
            let capture = window.screenshot()
            let attachment = XCTAttachment(screenshot: capture)
            attachment.name = "\(message.identifier)-part-\(part)"
            attachment.lifetime = .keepAlways
            add(attachment)
            for line in RecognizedText.lines(in: capture, region: region) {
                let painted = line.frame.offsetBy(dx: origin.x, dy: origin.y)
                guard region.insetBy(dx: -1, dy: -1).contains(line.frame) else { continue }
                let local = painted.offsetBy(dx: -frame.minX, dy: -frame.minY)
                // A line clipped by the viewport can return again at its full height after scrolling.
                if let earlier = lines.firstIndex(where: {
                    $0.frame.intersection(local).height > min($0.frame.height, local.height) / 2
                }) {
                    if lines[earlier].frame.height < local.height { lines[earlier] = (line.text, local) }
                } else {
                    lines.append((line.text, local))
                }
            }
            if frame.maxY <= visible.maxY { break }
            drag(-min(visible.height / 2, max(60, frame.maxY - visible.maxY + 10)), holding: true)
        }
        XCTAssertLessThanOrEqual(message.frame.maxY, visible.maxY, "End of \(message.identifier) is not reachable")
        return lines.sorted { $0.frame.minY < $1.frame.minY }
    }
    #endif

    /// Compact song cards paint the whole percentile below the title, and scale it at AX5.
    @MainActor
    func testCompactBandSongPercentilesStayBelowTheTitleAndScale() throws {
        continueAfterFailure = false
        var baseline: [String: CGFloat] = [:]
        for size in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
            let app = openBandDetail(contentSize: size)
            defer { app.terminate() }
            let window = app.windows.firstMatch
            try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone && window.frame.width < 600,
                              "Checks the iPhone and Duo cover's compact layout")
            let visible = window.frame.inset(by: UIEdgeInsets(top: 100, left: 0, bottom: 28, right: 0))
            let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.55))
            for probe in Self.songRowProbes {
                let row = app.descendants(matching: .any)[probe.id]
                for _ in 0..<16 where !row.exists || !visible.contains(row.frame) {
                    guard row.exists, row.frame.minY < window.frame.maxY + 160 else {
                        app.swipeUp()
                        continue
                    }
                    let delta = visible.midY - row.frame.midY
                    let end = start.withOffset(CGVector(dx: 0, dy: max(-200, min(200, delta))))
                    start.press(forDuration: 0.05, thenDragTo: end)
                }
                XCTAssertTrue(row.exists && visible.contains(row.frame), "\(probe.id): \(row.frame) outside \(visible)")
                assertSongRowAccessibility(probe, in: app)
                let shot = row.screenshot()
                let capture = XCTAttachment(screenshot: shot)
                capture.name = "band-\(probe.id)-\(size == .large ? "large" : "ax5")"
                capture.lifetime = .keepAlways
                add(capture)
                let lines = RecognizedText.lines(in: shot)
                let pill = try XCTUnwrap(lines.first { RecognizedText.showsWhole(probe.percentile, in: $0.text) },
                                         "Expected the whole percentile in \(lines)")
                let title = lines.filter { $0.frame.maxY < pill.frame.minY }.map(\.text).joined(separator: " ")
                XCTAssertTrue(RecognizedText.showsWhole(probe.title, in: title), "Expected the whole title above the pill")
                XCTAssertLessThan(shot.image.size.width - pill.frame.maxX, 38, "The pill is trailing")
                if size == .large {
                    baseline[probe.id] = pill.frame.height
                } else {
                    let height = try XCTUnwrap(baseline[probe.id])
                    XCTAssertGreaterThan(pill.frame.height, height * RecognizedText.minimumGrowth)
                }
            }
        }
    }

    #if compiler(>=6.4.4) && targetEnvironment(simulator)
    /// Both descriptions wrap before the physical fold, and the wide rows keep their trailing pills.
    @MainActor
    func testDuoBandSongDescriptionsReflowAtTheBookHinge() throws {
        let environment = ProcessInfo.processInfo.environment
        try XCTSkipUnless(environment["FST_DUO_SPLIT_TEST"] == "1"
            && (environment["SIMULATOR_DEVICE_NAME"] ?? "").contains("Duo"),
            "Opt in on a dedicated iPhone Duo with the loopback fixture")
        guard #available(iOS 27.3, *) else { throw XCTSkip("Needs the iOS 27.3 hinge runtime") }
        let origin = URLComponents(string: environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:18790")
        try XCTSkipUnless(origin?.scheme == "http" && origin?.host == "127.0.0.1" && origin?.port != nil,
                          "This journey requires a loopback fixture")
        continueAfterFailure = false
        let device = XCUIDevice.shared
        let hinge = try XCTUnwrap(device.hinge)
        let originalAngle = hinge.angle
        let originalOrientation = device.orientation
        defer {
            device.orientation = originalOrientation
            hinge.angle = originalAngle
        }
        device.orientation = .portrait
        hinge.angle = .pi
        let app = openBandDetail(contentSize: .large)
        defer { app.terminate() }

        let landscape = CGSize(width: 951, height: 669)
        let window = app.windows.firstMatch
        let scrollPoint = window.coordinate(withNormalizedOffset: CGVector(dx: 0.28, dy: 0.55))
        let name = "Band 1 Member A + Band 1 Member B"
        let descriptions = ["highest", "lowest"].map { "\(name)'s \($0)-ranked band songs, sorted by percentile." }
        let labels = descriptions.map { app.staticTexts[$0] }
        func descriptionsAreVisible() -> Bool {
            let region = window.frame.insetBy(dx: 0, dy: 88)
            return labels.allSatisfy { $0.exists && $0.isHittable && region.contains($0.frame) }
        }
        for (phase, angle) in [("flat", CGFloat.pi), ("book", .pi / 2), ("flat-return", .pi)] {
            hinge.angle = angle
            XCTAssertTrue(FeedbackJourney.waitUntil(timeout: 15) {
                abs(hinge.angle - angle) < 0.05 && window.frame.size == landscape
            }, "\(phase): expected inner landscape at \(angle), got \(window.frame) at \(hinge.angle)")
            for _ in 0..<12 where !descriptionsAreVisible() {
                let best = labels[0]
                let top = best.exists ? best.frame.minY : landscape.height
                let dy = max(-240, min(240, window.frame.minY + 165 - top))
                scrollPoint.press(forDuration: 0.05, thenDragTo: scrollPoint.withOffset(CGVector(dx: 0, dy: dy)))
            }
            XCTAssertTrue(descriptionsAreVisible(), "\(phase): the two song descriptions should be visible")

            let shot = XCUIScreen.main.screenshot()
            let capture = XCTAttachment(screenshot: shot)
            capture.name = "duo-band-songs-\(phase)"
            capture.lifetime = .keepAlways
            add(capture)
            let image = shot.image
            let bitmap = try XCTUnwrap(image.cgImage)
            XCTAssertEqual(min(bitmap.width, bitmap.height), 2006, "\(phase): inner display")
            XCTAssertEqual(max(bitmap.width, bitmap.height), 2852, "\(phase): inner display")
            let rotated = bitmap.width < bitmap.height
            let lines = RecognizedText.lines(in: shot, orientation: rotated ? .right : .up)
            let sx = (rotated ? image.size.height : image.size.width) / landscape.width
            let sy = (rotated ? image.size.width : image.size.height) / landscape.height
            let book = angle < .pi
            for (description, label) in zip(descriptions, labels) {
                let frame = label.frame
                let painted = lines.filter { (frame.minY...frame.maxY).contains($0.frame.midY / sy) }
                XCTAssertEqual(painted.count, book ? 2 : 1, "\(phase): \(painted)")
                XCTAssertTrue(RecognizedText.showsWhole(description, in: painted.map(\.text).joined(separator: " ")))
                XCTAssertTrue(painted.contains { RecognizedText.showsWhole("sorted by percentile", in: $0.text) })
                if book {
                    XCTAssertLessThanOrEqual(frame.maxX, window.frame.midX - 10)
                    XCTAssertTrue(painted.allSatisfy { $0.frame.maxX / sx < window.frame.midX })
                } else {
                    XCTAssertGreaterThan(try XCTUnwrap(painted.first).frame.maxX / sx, window.frame.midX)
                }
            }
            XCTAssertLessThan(labels[0].frame.maxY, labels[1].frame.minY)
            let pixels = try XCTUnwrap(ButtonFillPixels(image: bitmap, pointWidth: CGFloat(bitmap.width)))
            let px = CGFloat(rotated ? bitmap.height : bitmap.width) / landscape.width
            let py = CGFloat(rotated ? bitmap.width : bitmap.height) / landscape.height
            func pillFill(in rect: CGRect) throws -> Double {
                let upright = rect.applying(CGAffineTransform(scaleX: px, y: py))
                let region = rotated ? CGRect(
                    x: upright.minY, y: CGFloat(bitmap.height) - upright.maxX,
                    width: upright.height, height: upright.width
                ) : upright
                return try XCTUnwrap(pixels.fraction(in: region) { red, green, blue in
                    (30...38).contains(red) && (44...52).contains(green) && (67...75).contains(blue)
                })
            }
            for probe in Self.songRowProbes {
                assertSongRowAccessibility(probe, in: app)
                let frame = app.descendants(matching: .any)[probe.id].frame
                let trailing = CGRect(x: frame.maxX - 86, y: frame.midY - 8, width: 72, height: 16)
                let before = CGRect(x: frame.maxX - 115, y: trailing.minY, width: 20, height: trailing.height)
                XCTAssertGreaterThan(try pillFill(in: trailing), 0.6, "\(phase): \(probe.percentile) fill is missing")
                XCTAssertLessThan(try pillFill(in: before), 0.05, "\(phase): \(probe.percentile) fill stretches left")
            }
        }
    }
    #endif

    /// #555: Band Detail opens with the band name as a large navigation title and the
    /// "type • appearances" line under it, shows the web's sections (Members, Band
    /// Summary, Band Statistics, Band Rank History chart, Five Best / Five Worst Songs)
    /// and passes the accessibility audit (every type but Dynamic Type, which
    /// ``testBandDetailScalesToTheLargestTextSize()`` audits at AX3) at the top and the
    /// bottom of the page. With Settings › Experimental Ranks off (the default) there is
    /// no Rank By and Total Score Rank is the only rank tile (pattern `experimental-ranks`).
    @MainActor
    func testBandDetailShowsLargeTitleSubtitleAndWebSections() throws {
        continueAfterFailure = false
        let app = openBandDetail()

        let title = "Band 1 Member A + Band 1 Member B"
        let bar = app.navigationBars[title]
        XCTAssertTrue(bar.waitForExistence(timeout: 15), "Band Detail has no '\(title)' navigation title")
        let subtitle = app.descendants(matching: .any)["fst.band.subtitle"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 15))
        XCTAssertEqual(subtitle.label, "Duos • 29 appearances")
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertGreaterThan(bar.frame.height, 80, "The band title is not a large title: \(bar.frame)")
        }
        XCTAssertGreaterThanOrEqual(subtitle.frame.minY, bar.frame.maxY - 1, "The subtitle is not under the title")
        XCTAssertFalse(
            app.descendants(matching: .any)[Self.rankByIdentifier].exists,
            "Rank By shows while Experimental Ranks is off"
        )
        SongsUITestSupport.record(app, name: "band-detail-large-title")
        try auditBandDetail(app, for: Self.defaultSizeAudit)

        let member = app.buttons["fst.band.member.fixture-band-1-a"]
        XCTAssertTrue(member.exists, "Member card is not one button")
        XCTAssertEqual(member.label, "View Band 1 Member A, Lead")
        XCTAssertGreaterThanOrEqual(member.frame.height, 44)

        for identifier in [
            "fst.band.summary-section", "fst.band.statistics-section", "fst.band.history-section",
            "fst.band.best-songs", "fst.band.worst-songs",
        ] {
            let section = app.descendants(matching: .any)[identifier]
            for _ in 0..<8 where !(section.exists && section.isHittable) { app.swipeUp() }
            XCTAssertTrue(section.exists, "\(identifier) is missing")
        }
        let tiles = app.descendants(matching: .any)
        XCTAssertTrue(tiles["\(Self.statisticsTile)total-score-rank"].exists, "Total Score Rank tile is missing")
        for experimental in ["adjusted-rank", "weighted-rank", "fc-rate-rank"] {
            XCTAssertFalse(
                tiles["\(Self.statisticsTile)\(experimental)"].exists,
                "\(experimental) tile shows while Experimental Ranks is off"
            )
        }
        XCTAssertTrue(app.staticTexts["Five Best Songs"].exists)
        XCTAssertTrue(app.staticTexts["Five Worst Songs"].exists)
        XCTAssertFalse(bar.frame.height > 80, "The large title did not collapse on scroll")
        SongsUITestSupport.record(app, name: "band-detail-songs")
        try auditBandDetail(app, for: Self.defaultSizeAudit)
    }

    /// Pattern `experimental-ranks` R1/R4 with the setting on: Band Detail offers a
    /// labelled, full-size Rank By reading Adjusted (web `BandPage`'s metric), listing the
    /// band metrics Total Score first, and adds the Adjusted, Weighted and FC Rate rank
    /// tiles; picking Total Score applies it.
    @MainActor
    func testBandDetailRankByFollowsExperimentalRanks() throws {
        continueAfterFailure = false
        let app = openBandDetail(experimentalRanks: true)
        let rankBy = app.descendants(matching: .any)[Self.rankByIdentifier]
        XCTAssertTrue(rankBy.waitForExistence(timeout: 15), "Rank By is missing with Experimental Ranks on")
        XCTAssertTrue(rankBy.label.contains("Adjusted"), "Rank By reads '\(rankBy.label)'")
        XCTAssertGreaterThanOrEqual(rankBy.frame.height, 44, "Rank By target \(rankBy.frame)")
        XCTAssertGreaterThanOrEqual(rankBy.frame.width, 44, "Rank By target \(rankBy.frame)")
        SongsUITestSupport.record(app, name: "band-detail-rank-by-on")

        rankBy.tap()
        let labels = ["Total Score", "Adjusted", "Weighted", "FC Rate"]
        let sheetChoice = app.buttons["fst.band-rankings.rank-by.totalscore"]
        if sheetChoice.waitForExistence(timeout: 5) {
            // iPhone floating page tools: the compact sheet lists the choices.
            let ids = ["totalscore", "adjusted", "weighted", "fcrate"].map { "fst.band-rankings.rank-by.\($0)" }
            let frames = ids.map { app.buttons[$0].frame.minY }
            XCTAssertEqual(frames, frames.sorted(), "Rank By choices are not Total Score first")
            sheetChoice.tap()
        } else {
            for label in labels { XCTAssertTrue(app.buttons[label].exists, "Rank By lacks \(label)") }
            app.buttons["Total Score"].tap()
        }
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "Total Score"), object: rankBy)
        XCTAssertEqual(XCTWaiter.wait(for: [applied], timeout: 10), .completed, "Rank By did not apply Total Score")

        let tiles = app.descendants(matching: .any)
        let adjusted = tiles["\(Self.statisticsTile)adjusted-rank"]
        for _ in 0..<10 where !(adjusted.exists && adjusted.isHittable) { app.swipeUp() }
        for tile in ["adjusted-rank", "weighted-rank", "fc-rate-rank", "total-score-rank"] {
            XCTAssertTrue(tiles["\(Self.statisticsTile)\(tile)"].exists, "\(tile) tile is missing")
        }
        SongsUITestSupport.record(app, name: "band-detail-experimental-tiles")
    }

    /// Accessibility text size (AX3), always launched: the page passes the Dynamic Type,
    /// clipped-text and hit-region audits at the header and at every lower section, and
    /// the subtitle, a member card, Summary and Statistics tiles, the rank-history chart
    /// and Best and Worst song rows are each reachable by scrolling, inside the window,
    /// at least 44 pt where they are targets, and taller than at the default size (their
    /// text scales rather than clips). Texts the default-size Dynamic Type probe flags,
    /// which does not re-run layout, must grow ≥ 1.35× here.
    @MainActor
    func testBandDetailScalesToTheLargestTextSize() throws {
        continueAfterFailure = false
        let regular = openBandDetail()
        XCTAssertTrue(regular.descendants(matching: .any)["fst.band.subtitle"].waitForExistence(timeout: 15))
        var flagged = try auditBandDetail(regular, for: .dynamicType)
        var baseline: [String: CGFloat] = [:]
        for probe in Self.scaledProbes {
            let element = regular.descendants(matching: .any)[probe.id]
            for _ in 0..<10 where !(element.exists && element.isHittable) { regular.swipeUp() }
            XCTAssertTrue(element.exists, "\(probe.id) is missing at the default size")
            baseline[probe.id] = element.frame.height
        }
        flagged.merge(try auditBandDetail(regular, for: .dynamicType)) { first, _ in first }
        regular.terminate()

        let app = openBandDetail(contentSize: .accessibilityExtraExtraExtraLarge)
        let window = app.windows.firstMatch.frame
        XCTAssertTrue(app.descendants(matching: .any)["fst.band.subtitle"].waitForExistence(timeout: 15))
        SongsUITestSupport.record(app, name: "band-detail-ax3-header")
        // Texts the AX3 Dynamic Type probe flags must be ones measured growing below.
        var flaggedAtAX3 = Set(try auditBandDetail(app, for: Self.largeTextAudit).keys)
        var pending = flagged
        func measurePending() {
            for (label, height) in pending {
                let text = Self.labelled(label, in: app)
                guard text.exists, text.isHittable else { continue }
                XCTAssertGreaterThanOrEqual(
                    text.frame.height, height * 1.35,
                    "'\(label)' does not grow with Dynamic Type (\(height) → \(text.frame.height) pt)"
                )
                pending[label] = nil
            }
        }
        measurePending()
        for probe in Self.scaledProbes {
            let element = app.descendants(matching: .any)[probe.id]
            for _ in 0..<24 where !(element.exists && element.isHittable) { app.swipeUp() }
            XCTAssertTrue(element.exists && element.isHittable, "\(probe.id) is not reachable at AX3")
            let frame = element.frame
            XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "\(probe.id) is cut off at AX3: \(frame)")
            XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "\(probe.id) is cut off at AX3: \(frame)")
            if probe.isTarget {
                XCTAssertGreaterThanOrEqual(frame.height, 44, "\(probe.id) target at AX3: \(frame)")
            }
            let regularHeight = baseline[probe.id] ?? 0
            XCTAssertGreaterThan(
                frame.height, regularHeight * probe.growth,
                "\(probe.id) does not scale with text (\(regularHeight) → \(frame.height) pt)"
            )
            SongsUITestSupport.record(app, name: "band-detail-ax3-\(probe.id.split(separator: ".").last ?? "")")
            flaggedAtAX3.formUnion(try auditBandDetail(app, for: Self.largeTextAudit).keys)
            measurePending()
        }
        for _ in 0..<40 where !pending.isEmpty {
            app.swipeDown()
            measurePending()
        }
        XCTAssertTrue(pending.isEmpty, "Flagged texts missing at AX3: \(pending.keys.sorted())")
        let unmeasured = flaggedAtAX3.subtracting(flagged.keys)
        XCTAssertTrue(unmeasured.isEmpty, "AX3 Dynamic Type issues on texts not shown growing: \(unmeasured.sorted())")
        if !flaggedAtAX3.isEmpty {
            XCTContext.runActivity(named: "AX3 Dynamic Type estimates, measured growing: \(flaggedAtAX3.sorted())") { _ in }
        }
    }

    /// Band Detail's Rank By (`BandRankByMenu`).
    private static let rankByIdentifier = "fst.band-rankings.rank-by-menu"
    /// Band Statistics tile identifier prefix (`BandDetailScreen.statIdentifierPrefix`).
    private static let statisticsTile = "fst.band.stat.statistics."
    /// Every audit type except Dynamic Type, which the AX3 journey owns.
    private static let defaultSizeAudit = XCUIAccessibilityAuditType.all.subtracting(.dynamicType)
    /// The audits that catch text that does not scale or clips at accessibility sizes.
    private static let largeTextAudit: XCUIAccessibilityAuditType = [.dynamicType, .textClipped, .hitRegion]

    private struct SongRowProbe {
        let id: String
        let title: String
        let percentile: String
        let rank: Int
        let isLink: Bool
    }

    private static let songRowProbes: [SongRowProbe] = [
        .init(id: "fst.band.song-row.fixture-pulse", title: "Fixture Pulse", percentile: "Top 10%", rank: 1, isLink: true),
        .init(id: "fst.band.song-row.fixture-ghost-song", title: "Unknown Song", percentile: "Top 80%", rank: 8, isLink: false),
    ]

    /// The pill is part of the row's name, not a separate action.
    @MainActor
    private func assertSongRowAccessibility(_ probe: SongRowProbe, in app: XCUIApplication) {
        let query = app.descendants(matching: .any).matching(identifier: probe.id)
        XCTAssertEqual(query.count, 1)
        let row = query.firstMatch
        XCTAssertEqual(row.label, "\(probe.title), \(probe.percentile), rank \(probe.rank) of 10")
        XCTAssertEqual(app.buttons[probe.id].exists, probe.isLink)
        if probe.isLink {
            XCTAssertGreaterThanOrEqual(row.frame.height, 44)
        }
    }

    /// The rebuilt regions checked at AX3, top to bottom: identifier, whether it is a
    /// tap target, and how much taller than at the default size it must be (the chart
    /// keeps its plot height; only its labels scale).
    private static let scaledProbes: [(id: String, isTarget: Bool, growth: CGFloat)] = [
        ("fst.band.subtitle", false, 1.35),
        ("fst.band.member.fixture-band-1-a", true, 1.35),
        ("fst.band.stat.summary.type", false, 1.35),
        ("\(statisticsTile)total-score-rank", true, 1.35),
        ("fst.band.rank-history.chart", false, 0.99),
        ("fst.band.song-row.fixture-pulse", true, 1.2),
        ("fst.band.song-row.fixture-ghost-song", true, 1.2),
    ]

    /// Launch on Band Rankings and open a fixture team's Band Detail.
    ///
    /// - Parameters:
    ///   - contentSize: Preferred text size, or nil for the default.
    ///   - experimentalRanks: Settings › Experimental Ranks.
    ///   - teamKey: The fixture team to open; rank 1 has history and songs.
    ///   - lessTransparency: Settings › Less Transparency.
    ///   - flatBackdrop: Use a neutral surface to measure the scrim independently of the art.
    /// - Returns: The app on Band Detail with its members loaded.
    @MainActor
    private func openBandDetail(
        contentSize: UIContentSizeCategory? = nil, experimentalRanks: Bool = false,
        teamKey: String = "fixture-team-1", lessTransparency: Bool = false, flatBackdrop: Bool = false
    ) -> XCUIApplication {
        let app = fixtureApp(
            route: "bandRankings:Band_Duets", contentSize: contentSize, experimentalRanks: experimentalRanks
        )
        if lessTransparency {
            app.launchArguments += ["-fst.accessibility.lessTransparency", "YES"]
        }
        if flatBackdrop {
            app.launchEnvironment["FST_DEBUG_FLAT_BACKDROP"] = "1"
        }
        app.launch()
        let row = app.descendants(matching: .any)
            .matching(identifier: "fst.band-rankings.row.\(teamKey)").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        for _ in 0..<6 where !row.isHittable { app.swipeUp() }
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fst.band.members-section"].waitForExistence(timeout: 15))
        return app
    }

    /// The element a flagged text belongs to: the text itself, or the stat tile that
    /// combines it (the audit names a tile by its uppercase caption node, the tile reads
    /// its Title Case label).
    @MainActor
    private static func labelled(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
    }

    /// Audit Band Detail, failing on every issue except heuristic estimates that are then
    /// checked against the real app: content under the bottom chrome's scroll-edge fade
    /// and page-tools text (as on Songs), contrast estimates on labelled text, measured
    /// on the rendered screenshot instead (the audit misjudges the system large title
    /// and white stat captions over the gradient; the pixels are white on near-black),
    /// Dynamic Type estimates on texts, which the caller re-measures at AX3, and contrast
    /// issues with no element, accepted only when every text in the content band renders
    /// ≥ 4.5:1 (`unattributed-contrast-page-floor`).
    ///
    /// - Parameters:
    ///   - app: Foreground app on Band Detail.
    ///   - types: The audits to run.
    /// - Throws: An audit failure or unreadable rendered text.
    /// - Returns: Heights of texts the Dynamic Type probe flagged, by label, which
    ///   ``testBandDetailScalesToTheLargestTextSize()`` re-measures at AX3.
    @MainActor
    @discardableResult
    private func auditBandDetail(_ app: XCUIApplication, for types: XCUIAccessibilityAuditType) throws -> [String: CGFloat] {
        var contrast: [(label: String, frame: CGRect)] = []
        var dynamicType: [String: CGFloat] = [:]
        var unattributed: [String] = []
        var floorFailures: [String] = []
        let window = app.windows.firstMatch.frame
        let tabs = app.tabBars.firstMatch
        let tools = app.descendants(matching: .any).matching(identifier: "fst.page-tools").firstMatch
        let accessory = tools.exists && tools.frame.minY > window.midY ? tools.frame : .null
        let chromeTop = min(tabs.exists ? tabs.frame.minY : window.maxY, accessory.isNull ? .infinity : accessory.minY)
        // Once the large title collapses, content scrolls under the bar's 40 pt top ramp
        // (`scroll-edge` R2/R3), as Songs waives with `rampEnd`.
        let bar = app.navigationBars.firstMatch
        let rampEnd = bar.exists && bar.frame.height <= 80 ? bar.frame.maxY + 40 : -CGFloat.infinity
        try app.performAccessibilityAudit(for: types) { issue in
            guard let element = issue.element, !element.frame.isEmpty else {
                // No element to measure (a node the audit cannot resolve, e.g. inside the
                // rank chart): accepted only when every text in the content band renders
                // ≥ 4.5:1 now, as the audit reports it (`unattributed-contrast-page-floor`).
                guard issue.auditType == .contrast else { return false }
                if unattributed.isEmpty {
                    floorFailures = try Self.pageContrastFloorFailures(
                        in: app, top: max(rampEnd, bar.frame.maxY), bottom: chromeTop, window: window
                    )
                }
                unattributed.append(issue.compactDescription)
                return true
            }
            let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
            // Content scrolled under the bottom chrome's scroll-edge fade, and page-tools
            // text capped at `FloatingPageToolsBar.maxTypeSize`, as on Songs
            // (`SongsChromeJourneyTests`, `page-tools-and-nav-chrome`).
            if issue.auditType == .contrast, element.frame.maxY > chromeTop { return true }
            if issue.auditType == .contrast, element.frame.minY < rampEnd,
               !bar.frame.contains(element.frame) { return true }
            if issue.auditType == .dynamicType, accessory.contains(center) { return true }
            // A long band name is truncated by the system navigation title; no public API
            // wraps it, and VoiceOver reads the element's full label (band-detail ios.md).
            if issue.auditType == .textClipped, element.elementType == .staticText,
               bar.frame.contains(center), element.label.hasPrefix("Band 1 Member A") { return true }
            guard !element.label.isEmpty else {
                print("Unwaived audit issue: \(issue.compactDescription) on an unlabelled \(element.elementType) \(element.frame)")
                return false
            }
            switch issue.auditType {
            case .dynamicType:
                print("Dynamic Type estimate on '\(element.label)' \(element.frame), re-measured at AX3")
                dynamicType[element.label] = element.frame.height
                return true
            case .contrast:
                // The audit misreads white text over the gradient and glass (the system
                // large title, stat captions); the rendered pixels are checked below.
                contrast.append((element.label, element.frame))
                return true
            default:
                print("Unwaived audit issue: \(issue.compactDescription) on '\(element.label)' \(element.frame)")
                return false
            }
        }
        XCTAssertTrue(
            floorFailures.isEmpty,
            "Unattributed \(unattributed) with weak page text \(floorFailures)"
        )
        if !unattributed.isEmpty {
            XCTContext.runActivity(named: "Page floor ≥ 4.5:1 accepted \(unattributed)") { _ in }
        }
        for label in dynamicType.keys {
            let element = Self.labelled(label, in: app)
            if element.exists { dynamicType[label] = element.frame.height }
        }
        if !contrast.isEmpty {
            let image = try XCTUnwrap(app.screenshot().image.cgImage)
            let scaleX = Double(image.width) / window.width
            let scaleY = Double(image.height) / window.height
            for (label, frame) in contrast {
                let rect = CGRect(
                    x: (frame.minX - window.minX) * scaleX, y: (frame.minY - window.minY) * scaleY,
                    width: frame.width * scaleX, height: frame.height * scaleY
                ).integral
                let crop = try XCTUnwrap(image.cropping(to: rect), "\(label) is off screen")
                let measured = try SongsUITestSupport.measuredTextContrast(
                    in: SongsUITestSupport.bitmapPixels(crop)
                )
                XCTAssertGreaterThan(measured.brightPixels, 20, "\(label) has no rendered text")
                XCTAssertGreaterThanOrEqual(
                    measured.ratio, 4.5,
                    "\(label) lacks rendered contrast (background \(measured.background), text \(measured.text))"
                )
            }
        }
        return dynamicType
    }

    /// Static texts between the top ramp and the bottom chrome that do not render
    /// ≥ 4.5:1 with ≥ 20 text pixels (`unattributed-contrast-page-floor`, as
    /// `SongsChromeJourneyTests` measures it).
    ///
    /// - Parameters:
    ///   - app: Band Detail as the audit left it.
    ///   - top: Where the content band starts (below the bar and its ramp).
    ///   - bottom: The top of the bottom chrome.
    ///   - window: The app window's frame.
    /// - Returns: A description of each weak text, or "no text measured".
    /// - Throws: A missing screenshot.
    @MainActor
    private static func pageContrastFloorFailures(
        in app: XCUIApplication, top: CGFloat, bottom: CGFloat, window: CGRect
    ) throws -> [String] {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let scaleX = Double(image.width) / window.width
        let scaleY = Double(image.height) / window.height
        var weak: [String] = []
        var measured = 0
        for text in app.staticTexts.allElementsBoundByIndex {
            let frame = text.frame
            guard !frame.isEmpty, window.contains(frame), frame.minY >= top, frame.maxY <= bottom else { continue }
            let rect = CGRect(
                x: (frame.minX - window.minX) * scaleX, y: (frame.minY - window.minY) * scaleY,
                width: frame.width * scaleX, height: frame.height * scaleY
            ).integral.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            measured += 1
            let reading = try image.cropping(to: rect).map {
                try SongsUITestSupport.measuredTextContrast(in: SongsUITestSupport.bitmapPixels($0))
            }
            if let reading, reading.ratio >= 4.5, reading.brightPixels >= 20 { continue }
            weak.append("'\(text.label)' \(frame) \(String(describing: reading))")
        }
        if measured == 0 { weak.append("no text measured") }
        return weak
    }

    /// `fixture-player-1`'s synthetic 30-entry "All" group needs a second page.
    @MainActor
    func testPlayerBandsPagesPastTheFirstPage() throws {
        continueAfterFailure = false
        let app = fixtureApp(route: "playerBands:fixture-player-1")
        app.launch()

        let pageInfo = app.descendants(matching: .any)
            .matching(identifier: "fst.player-bands.page-info").firstMatch
        XCTAssertTrue(pageInfo.waitForExistence(timeout: 15))
        XCTAssertEqual(pageInfo.label, "Page")
        XCTAssertEqual(pageInfo.value as? String, "1 of 2")
        let first = app.buttons["fst.player-bands.page-first"]
        let previous = app.buttons["fst.player-bands.page-previous"]
        let next = app.buttons["fst.player-bands.page-next"]
        let last = app.buttons["fst.player-bands.page-last"]
        let controls = [first, previous, pageInfo, next, last]
        for control in controls {
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44 - 1)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44 - 1)
        }
        XCTAssertFalse(first.isEnabled)
        XCTAssertFalse(previous.isEnabled)
        XCTAssertLessThan(pageInfo.frame.width, 80, "The single-digit page badge hugs its label")
        for (left, right) in zip(controls, controls.dropFirst()) {
            XCTAssertEqual(right.frame.minX - left.frame.maxX, 10, accuracy: 1)
        }
        SongsUITestSupport.record(app, name: "player-bands-page-1")

        XCTAssertTrue(next.exists && next.isEnabled)
        next.tap()
        let onPageTwo = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "2 of 2"), object: pageInfo
        )
        XCTAssertEqual(XCTWaiter.wait(for: [onPageTwo], timeout: 10), .completed)
        SongsUITestSupport.record(app, name: "player-bands-page-2")

        XCTAssertTrue(previous.exists && previous.isEnabled)
        previous.tap()
        let backOnPageOne = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1 of 2"), object: pageInfo
        )
        XCTAssertEqual(XCTWaiter.wait(for: [backOnPageOne], timeout: 10), .completed)
    }
}
