import XCTest

/// Quick Links instrument icons on device (#303, tests backfilled by #460).
///
/// #303 drew the chooser's instrument artwork at its 144 pt intrinsic size: on Profile
/// the Lead row's icon covered its title in the iPhone tool sheet and the iPad and
/// iPhone Duo menus. `QuickLinkLabel` now pre-sizes the artwork to the visual weight of
/// the neighbouring SF Symbols and scales it with Dynamic Type. Each journey opens the
/// real chooser on the fixture Profile and checks the Lead row against its symbol
/// neighbour, Lead Rank History: one button named "Lead" (the icon is not read as a
/// file name), at least 44 pt in the app's sheet (a native menu sizes its own rows: 42 pt
/// on iOS 26, above the HIG's 28 pt minimum) and no taller than the symbol row, an icon whose
/// rendered height matches the symbol's and stops before the title, and a chooser that
/// passes the Dynamic Type, clipped-text, hit-region and description audits. A native
/// menu draws no item images at accessibility text sizes; there the Lead row must draw
/// no artwork either, its title starting in the symbol row's text column. The icon is
/// part of the row's label, so it has no element of its own: its size is read from the
/// row's pixels, as `SongBarCaptionIconJourneyTests` does.
///
/// iOS 27 menus drop their rows' identifiers and read only the row's title `Text`
/// (`QuickLinkLabel` names that Text, #626): there a row is the one unidentified button
/// whose VoiceOver label is exactly its section's spoken title, and the audit covers every
/// unidentified element inside the menu.
///
/// Forms, each at the default size and AX5: the iPhone tool sheet, the folded
/// iPhone Duo's menu (simulated on the iPhone, `FST_DEBUG_DUO_WINDOW`) and the iPad
/// navigation-bar menu. Hosted macOS twins: `QuickLinksInstrumentIconAccessibilityTests`.
///
/// Runs against the CI fixture (`tools/mock_service.py --large-catalogue`, port 8765;
/// set `TEST_RUNNER_FST_FIXTURE_URL` to use another mock).
final class QuickLinksIconAccessibilityJourneyTests: XCTestCase {
    private static let itemPrefix = "fst.quick-links.item."
    private static let lead = itemPrefix + "instrument:Solo_Guitar"
    private static let symbol = itemPrefix + "rank-history:Solo_Guitar"
    private static let largest = "UICTContentSizeCategoryAccessibilityXXXL"

    /// What one chooser row rendered, in points.
    struct RowGlyphs: CustomStringConvertible {
        /// Leading edge of the first line's ink, and that run's height.
        let firstInkX: CGFloat
        let firstRunHeight: CGFloat
        /// Leading edge of any ink in the row: a wrapped title's text column.
        let leftmostInkX: CGFloat
        /// Width, height and horizontal centre of the row's icon (the squarer end run).
        let iconMidX: CGFloat
        let iconWidth: CGFloat
        let iconHeight: CGFloat
        /// Gap between the icon and the title's first glyph.
        let gap: CGFloat
        /// Height of the title's first word.
        let textHeight: CGFloat

        var description: String {
            String(format: "icon %.1f×%.1f at x %.1f, gap %.1f, text %.1f, first ink x %.1f h %.1f, leftmost x %.1f",
                   iconWidth, iconHeight, iconMidX, gap, textHeight, firstInkX, firstRunHeight, leftmostInkX)
        }
    }

    // MARK: - iPhone sheet

    /// iPhone tool sheet at the default text size.
    @MainActor
    func testSheetInstrumentIconMatchesSymbolRow() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The tool sheet is the iPhone chooser")
        try assertInstrumentRow(category: nil, duoWindow: nil, menu: false, name: "quick-links-icon-sheet")
    }

    /// iPhone tool sheet at the largest accessibility size: the icon grows with the
    /// symbols and the title.
    @MainActor
    func testSheetInstrumentIconMatchesSymbolRowAtAX5() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The tool sheet is the iPhone chooser")
        try assertInstrumentRow(category: Self.largest, duoWindow: nil, menu: false, name: "quick-links-icon-sheet-ax5")
    }

    // MARK: - iPhone Duo menu

    /// Folded iPhone Duo (outer display) menu at the default text size.
    @MainActor
    func testDuoMenuInstrumentIconMatchesSymbolRow() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertInstrumentRow(category: nil, duoWindow: "folded", menu: true, name: "quick-links-icon-duo")
    }

    /// Folded iPhone Duo menu at the largest accessibility size.
    @MainActor
    func testDuoMenuInstrumentIconMatchesSymbolRowAtAX5() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .phone, "The Duo window is simulated on an iPhone")
        try assertInstrumentRow(category: Self.largest, duoWindow: "folded", menu: true, name: "quick-links-icon-duo-ax5")
    }

    // MARK: - iPad menu

    /// iPad navigation-bar menu at the default text size.
    @MainActor
    func testMenuInstrumentIconMatchesSymbolRow() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "The navigation-bar menu is the iPad chooser")
        try assertInstrumentRow(category: nil, duoWindow: nil, menu: true, name: "quick-links-icon-menu")
    }

    /// iPad navigation-bar menu at the largest accessibility size.
    @MainActor
    func testMenuInstrumentIconMatchesSymbolRowAtAX5() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "The navigation-bar menu is the iPad chooser")
        try assertInstrumentRow(category: Self.largest, duoWindow: nil, menu: true, name: "quick-links-icon-menu-ax5")
    }

    // MARK: - Check

    /// Open Profile's Quick Links and check the Lead row against Lead Rank History.
    ///
    /// - Parameters:
    ///   - category: `UIPreferredContentSizeCategoryName`, or nil for the default size.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    ///   - menu: The chooser is a native menu, which drops item images at accessibility sizes.
    ///   - name: Screenshot attachment name.
    @MainActor
    private func assertInstrumentRow(category: String?, duoWindow: String?, menu: Bool, name: String) throws {
        continueAfterFailure = false
        let app = try launchProfile(category: category, duoWindow: duoWindow)
        let open = app.buttons["fst.quick-links.open"]
        XCTAssertTrue(open.waitForExistence(timeout: FestivalApp.budget(20)), "No Quick Links button")
        open.tap()
        let leadQuery = rows(app, id: Self.lead, label: "Lead")
        let symbolQuery = rows(app, id: Self.symbol, label: "Lead Rank History")
        let lead = leadQuery.firstMatch
        let symbol = symbolQuery.firstMatch
        XCTAssertTrue(lead.waitForExistence(timeout: FestivalApp.budget(10)), "The chooser did not open")
        // At AX5 the rows are tall: scroll the chooser until both rows are on screen.
        let list = app.collectionViews.containing(Self.rowPredicate(id: Self.lead, label: "Lead")).firstMatch
        for _ in 0..<4 where !(lead.isHittable && symbol.exists && symbol.isHittable) && list.exists {
            list.swipeUp(velocity: .slow)
        }
        sleep(UInt32(FestivalApp.budget(1)))
        SongsUITestSupport.record(app, name: name)

        // Name and role: one button named by the instrument, not by its artwork.
        XCTAssertEqual(leadQuery.count, 1, "One chooser row reads 'Lead'")
        XCTAssertEqual(symbolQuery.count, 1, "One chooser row reads 'Lead Rank History'")
        XCTAssertEqual(lead.label, "Lead")
        XCTAssertEqual(symbol.label, "Lead Rank History")
        XCTAssertTrue(lead.isHittable, "Lead row unreachable: \(lead.frame)")
        XCTAssertTrue(symbol.isHittable, "Rank History row unreachable: \(symbol.frame)")
        let artworkNames = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "instrument_"))
        XCTAssertEqual(artworkNames.count, 0, "An artwork file name is spoken")

        // Target size (HIG Accessibility, Mobility: iOS 44×44 pt default, 28×28 pt minimum).
        // The sheet's rows are the app's, so they meet the default. A native menu sizes its
        // own rows (iOS 26: 42 pt, full width, symbol rows included), so there the row must
        // clear the minimum and match the system-drawn symbol row. Either way it is no taller
        // than the symbol row (#303's artwork made it several times taller). Only the symbol
        // row's title wraps at AX5, so the rows match only at the default size.
        XCTAssertGreaterThanOrEqual(lead.frame.height, menu ? 28 : 44, "\(lead.frame)")
        XCTAssertGreaterThanOrEqual(lead.frame.width, 44, "\(lead.frame)")
        if category == nil {
            XCTAssertEqual(lead.frame.height, symbol.frame.height, accuracy: 2, "Lead \(lead.frame), symbol \(symbol.frame)")
        } else {
            XCTAssertLessThanOrEqual(lead.frame.height, symbol.frame.height + 2, "Lead \(lead.frame), symbol \(symbol.frame)")
        }

        let leadGlyphs = try measure(lead, name: "\(name)-lead")
        let symbolGlyphs = try measure(symbol, name: "\(name)-symbol")
        let context = "Lead \(leadGlyphs); symbol \(symbolGlyphs)"
        if menu && category != nil {
            // No artwork at all: the title starts in the symbol row's text column (where its
            // wrapped line returns) and its leading glyph is a capital, as tall as "Rank"'s R.
            XCTAssertEqual(leadGlyphs.firstInkX, symbolGlyphs.leftmostInkX, accuracy: 4, "Text column moved: \(context)")
            XCTAssertLessThanOrEqual(leadGlyphs.firstRunHeight, symbolGlyphs.firstRunHeight * 1.1, "Artwork drawn in a text-only menu: \(context)")
        } else {
            // Rendered icon: in the symbol's column, the same height as the symbol beside
            // the same text, and clear of the title.
            XCTAssertEqual(leadGlyphs.iconMidX, symbolGlyphs.iconMidX, accuracy: 3, "Icon column moved: \(context)")
            XCTAssertGreaterThanOrEqual(leadGlyphs.iconHeight, symbolGlyphs.iconHeight * 0.8, context)
            XCTAssertLessThanOrEqual(leadGlyphs.iconHeight, symbolGlyphs.iconHeight * 1.35, context)
            XCTAssertEqual(leadGlyphs.iconWidth, leadGlyphs.iconHeight, accuracy: max(2, leadGlyphs.iconHeight * 0.15), context)
            XCTAssertGreaterThanOrEqual(leadGlyphs.gap, 2, "The icon touches or covers the title: \(context)")
            XCTAssertEqual(leadGlyphs.textHeight, symbolGlyphs.textHeight, accuracy: max(2, symbolGlyphs.textHeight * 0.2), context)
            if category == Self.largest {
                // The symbols are 20 pt at Large and 38 pt at AX5; the disc follows them.
                XCTAssertGreaterThan(leadGlyphs.iconHeight, 24, "The icon did not grow at AX5: \(context)")
            }
        }

        // The chooser's rows: identified rows, and in a native menu that drops identifiers
        // (iOS 27) every unidentified element inside the menu's list.
        let chooser = list.exists ? list.frame : lead.frame.union(symbol.frame)
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, [.dynamicType, .textClipped, .hitRegion, .sufficientElementDescription], name: name,
            reset: { issues = [] }
        ) { issue in
            let id = issue.element?.identifier ?? ""
            let frame = issue.element?.frame ?? .null
            let inMenu = menu && id.isEmpty && chooser.contains(CGPoint(x: frame.midX, y: frame.midY))
            guard id.hasPrefix(Self.itemPrefix) || inMenu else { return true }
            issues.append("\(id.isEmpty ? "'\(issue.element?.label ?? "")'" : id): \(issue.compactDescription)")
            return true
        }
        XCTAssertEqual(issues, [], "Quick Links chooser audit issues")
    }

    // MARK: - Helpers

    /// A chooser row: its identifier, or in a native menu that drops its rows' identifiers
    /// (iOS 27, #626) an unidentified button whose VoiceOver label is exactly `label`.
    ///
    /// - Parameters:
    ///   - id: The row's `fst.quick-links.item.*` identifier.
    ///   - label: The row's full VoiceOver label.
    /// - Returns: The matching predicate.
    private static func rowPredicate(id: String, label: String) -> NSPredicate {
        NSPredicate(format: "identifier == %@ OR (identifier == '' AND label == %@)", id, label)
    }

    /// The buttons matching ``rowPredicate(id:label:)``; the journey requires exactly one.
    ///
    /// - Parameters:
    ///   - app: The running app with the chooser open.
    ///   - id: The row's identifier.
    ///   - label: The row's full VoiceOver label.
    /// - Returns: The query.
    @MainActor
    private func rows(_ app: XCUIApplication, id: String, label: String) -> XCUIElementQuery {
        app.buttons.matching(Self.rowPredicate(id: id, label: label))
    }

    /// Launch the fixture player's profile with nested sections.
    ///
    /// - Parameters:
    ///   - category: `UIPreferredContentSizeCategoryName`, or nil for the default size.
    ///   - duoWindow: `DebugDuoWindow` to simulate, or nil for the device itself.
    /// - Returns: The app showing the profile.
    /// - Throws: A skip when the fixture profile never loads.
    @MainActor
    private func launchProfile(category: String?, duoWindow: String?) throws -> XCUIApplication {
        var environment = [
            "FST_API_BASE_URL": SongsUITestSupport.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_TAB": "settings",
            "FST_DEBUG_ROUTE": "player:fixture-player-1",
        ]
        if let duoWindow {
            environment["FST_DEBUG_DUO_WINDOW_REMOTE"] = "1"
            environment["FST_DEBUG_DUO_WINDOW"] = duoWindow
        }
        let app = FestivalApp.makeApp(environment)
        if let category { app.launchArguments += ["-UIPreferredContentSizeCategoryName", category] }
        app.launch()
        let history = app.descendants(matching: .any)["fst.player.rank-history.Solo_Guitar"]
        guard history.waitForExistence(timeout: FestivalApp.budget(30)) else {
            throw XCTSkip("The fixture profile never loaded; run tools/mock_service.py on \(SongsUITestSupport.fixtureURL).")
        }
        if let duoWindow {
            let readout = app.staticTexts["fst.shell.debug.duo-window"]
            let reached = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label BEGINSWITH %@", "\(duoWindow) "), object: readout
            )
            XCTAssertEqual(XCTWaiter().wait(for: [reached], timeout: FestivalApp.budget(10)), .completed,
                           "The app never simulated \(duoWindow)")
        }
        return app
    }

    /// Measure a chooser row's icon and title from its screenshot.
    ///
    /// - Parameters:
    ///   - row: The row's button.
    ///   - name: Attachment name for the captured row.
    /// - Returns: The row's glyph measurements.
    @MainActor
    private func measure(_ row: XCUIElement, name: String) throws -> RowGlyphs {
        let shot = row.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let image = try XCTUnwrap(shot.image.cgImage)
        let scale = CGFloat(image.width) / max(row.frame.width, 1)
        let pixels = try SongsUITestSupport.bitmapPixels(image)
        let glyphs = try XCTUnwrap(
            Self.rowGlyphs(pixels, width: image.width, height: image.height, scale: scale), "No glyphs in \(name)"
        )
        XCTContext.runActivity(named: "\(name): \(glyphs)") { _ in }
        return glyphs
    }

    /// Find a row's icon and the title word beside it.
    ///
    /// Ink is any pixel that differs clearly from the row's background (sampled at its
    /// vertical middle, just inside the leading edge), so a coloured disc, a tinted symbol
    /// and the title all count whatever the chooser's material. Only the first line of ink
    /// counts (rows separated by more than 2 pt end it): at AX5 a wrapped title's second
    /// line starts under the icon. Columns of ink are grouped
    /// into runs separated by more than half a point, so a letter's antialiasing never
    /// splits a word and a word space never joins two. The icon is the squarer of the two
    /// end runs (leading in the sheet; a menu may draw it trailing), and the title word is
    /// the run next to it.
    ///
    /// - Parameters:
    ///   - pixels: RGBA bytes, row-major from the top.
    ///   - width: Image width in pixels.
    ///   - height: Image height in pixels.
    ///   - scale: Pixels per point.
    /// - Returns: The measurements in points, or nil when the row has fewer than two runs.
    static func rowGlyphs(_ pixels: [UInt8], width: Int, height: Int, scale: CGFloat) -> RowGlyphs? {
        let sampleX = min(width - 1, Int(scale * 3))
        let background = (0..<3).map { Int(pixels[((height / 2) * width + sampleX) * 4 + $0]) }
        func ink(_ x: Int, _ y: Int) -> Bool {
            let offset = (y * width + x) * 4
            return (0..<3).contains { abs(Int(pixels[offset + $0]) - background[$0]) > 60 }
        }
        // Skip the outer 2 pt: a grouped row's rounded corners and separators are not ink.
        let inset = Int(scale * 2)
        let inner = inset..<max(inset + 1, height - inset)
        let inkRows = inner.filter { y in (inset..<max(inset + 1, width - inset)).contains { ink($0, y) } }
        guard let top = inkRows.first else { return nil }
        var bottom = top
        for y in inkRows where y - bottom <= Int(scale * 2) { bottom = y }
        let ys = top..<(bottom + 1)
        let columns = (0..<width).map { x in x >= inset && x < width - inset && ys.contains { ink(x, $0) } }
        let tolerance = max(1, Int((scale * 0.7).rounded()))
        var runs: [ClosedRange<Int>] = []
        var x = 0
        while x < width {
            guard columns[x] else { x += 1; continue }
            var end = x
            var cursor = x + 1
            while cursor < width, cursor - end <= tolerance {
                if columns[cursor] { end = cursor }
                cursor += 1
            }
            runs.append(x...end)
            x = end + 1
        }
        guard runs.count >= 2 else { return nil }
        let leftmost = (inset..<max(inset + 1, width - inset)).first { x in inner.contains { ink(x, $0) } } ?? runs[0].lowerBound
        func extent(_ xs: ClosedRange<Int>) -> Int {
            let rows = ys.filter { y in xs.contains { ink($0, y) } }
            return (rows.max() ?? 0) - (rows.min() ?? 0) + 1
        }
        func squareness(_ xs: ClosedRange<Int>) -> CGFloat {
            let w = CGFloat(xs.count), h = CGFloat(extent(xs))
            return abs(w - h) / max(w, h)
        }
        let leading = squareness(runs[0]) <= squareness(runs[runs.count - 1])
        let icon = leading ? runs[0] : runs[runs.count - 1]
        let text = leading ? runs[1] : runs[runs.count - 2]
        let gap = leading ? text.lowerBound - icon.upperBound - 1 : icon.lowerBound - text.upperBound - 1
        return RowGlyphs(
            firstInkX: CGFloat(runs[0].lowerBound) / scale,
            firstRunHeight: CGFloat(extent(runs[0])) / scale,
            leftmostInkX: CGFloat(leftmost) / scale,
            iconMidX: CGFloat(icon.lowerBound + icon.upperBound) / 2 / scale,
            iconWidth: CGFloat(icon.count) / scale,
            iconHeight: CGFloat(extent(icon)) / scale,
            gap: CGFloat(gap) / scale,
            textHeight: CGFloat(extent(text)) / scale
        )
    }
}
