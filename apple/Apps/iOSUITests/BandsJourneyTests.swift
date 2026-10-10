import UIKit
import XCTest

/// Fixture-backed native journeys for Bands: a Band Rankings row pushing into Band
/// Detail and then into a catalog-linked song, and Player Bands paging past the
/// first page. Both rely on `tools/mock_service.py` fixture data this lane added
/// (`_band_ranking_entry`/`_band_detail`/`_player_band_entry`/
/// `_song_band_leaderboard_entry` — see `.agents/testing/fixtures.md`).
final class BandsJourneyTests: XCTestCase {
    @MainActor
    private func fixtureApp(route: String, contentSize: UIContentSizeCategory? = nil) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_API_BASE_URL": "http://127.0.0.1:18790",
            "FST_DEBUG_ROUTE": route,
        ])
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize.rawValue]
        }
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

    /// #555: Band Detail opens with the band name as a large navigation title and the
    /// "type • appearances" line under it, shows the web's sections (Members, Band
    /// Summary, Band Statistics, Band Rank History chart, Five Best / Five Worst Songs)
    /// and passes the accessibility audit.
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
        SongsUITestSupport.record(app, name: "band-detail-large-title")
        var unscaled = try auditBandDetail(app)

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
        XCTAssertTrue(app.staticTexts["Five Best Songs"].exists)
        XCTAssertTrue(app.staticTexts["Five Worst Songs"].exists)
        XCTAssertFalse(bar.frame.height > 80, "The large title did not collapse on scroll")
        SongsUITestSupport.record(app, name: "band-detail-songs")
        unscaled.merge(try auditBandDetail(app)) { first, _ in first }
        app.terminate()
        try assertGrowsAtAccessibilitySize(unscaled)
    }

    /// Launch on Band Rankings and open rank 1's Band Detail.
    ///
    /// - Parameter contentSize: Preferred text size, or nil for the default.
    /// - Returns: The app on Band Detail with its members loaded.
    @MainActor
    private func openBandDetail(contentSize: UIContentSizeCategory? = nil) -> XCUIApplication {
        let app = fixtureApp(route: "bandRankings:Band_Duets", contentSize: contentSize)
        app.launch()
        let row = app.descendants(matching: .any)
            .matching(identifier: "fst.band-rankings.row.fixture-team-1").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["fst.band.members-section"].waitForExistence(timeout: 15))
        return app
    }

    /// The audit's "Dynamic Type font sizes are partially unsupported" probe does not
    /// re-run SwiftUI layout (the iPad `dynamic-type-grows` waiver,
    /// `.agents/testing/apple/accessibility.md`): each flagged text must be at least
    /// 1.35× taller in an AX3 launch of the same page.
    ///
    /// - Parameter heights: Default-size heights of the flagged texts, by label.
    /// - Throws: A flagged text that is missing or does not grow at AX3.
    @MainActor
    private func assertGrowsAtAccessibilitySize(_ heights: [String: CGFloat]) throws {
        guard !heights.isEmpty else { return }
        let app = openBandDetail(contentSize: .accessibilityExtraExtraExtraLarge)
        for (label, height) in heights.sorted(by: { $0.key < $1.key }) {
            let text = Self.labelled(label, in: app)
            for _ in 0..<12 where !text.exists { app.swipeUp() }
            XCTAssertTrue(text.exists, "'\(label)' is missing at AX3")
            XCTAssertGreaterThanOrEqual(
                text.frame.height, height * 1.35,
                "'\(label)' does not grow with Dynamic Type (\(height) → \(text.frame.height) pt)"
            )
        }
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
    /// - Parameter app: Foreground app on Band Detail.
    /// - Throws: An audit failure or unreadable rendered text.
    /// - Returns: Default-size heights of texts the Dynamic Type probe flagged, by label,
    ///   for ``assertGrowsAtAccessibilitySize(_:)``.
    @MainActor
    private func auditBandDetail(_ app: XCUIApplication) throws -> [String: CGFloat] {
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
        try app.performAccessibilityAudit(for: .all) { issue in
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
            // text capped at `PageToolsAccessoryBar.maxTypeSize`, as on Songs
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
        SongsUITestSupport.record(app, name: "player-bands-page-1")

        let next = app.buttons["fst.player-bands.page-next"]
        XCTAssertTrue(next.exists && next.isEnabled)
        next.tap()
        let onPageTwo = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "2 of 2"), object: pageInfo
        )
        XCTAssertEqual(XCTWaiter.wait(for: [onPageTwo], timeout: 10), .completed)
        SongsUITestSupport.record(app, name: "player-bands-page-2")

        let previous = app.buttons["fst.player-bands.page-previous"]
        XCTAssertTrue(previous.exists && previous.isEnabled)
        previous.tap()
        let backOnPageOne = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "1 of 2"), object: pageInfo
        )
        XCTAssertEqual(XCTWaiter.wait(for: [backOnPageOne], timeout: 10), .completed)
    }
}
