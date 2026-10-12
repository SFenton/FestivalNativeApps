import XCTest

// MARK: - iPhone Duo bottom Filter Songs field (issue #333, backfilled by #474)

/// The Songs Filter field #333 moved to the bottom of the page on iPhone Duo
/// (`BottomSearchField`), in production chrome: the folded iPhone Duo with its vertical
/// bar, at the standard and the largest accessibility text size. (The simulated Duo window
/// on a plain iPhone keeps the iPhone's tab bar over the field, so it cannot measure it.)
///
/// Each run checks:
/// - name, role and state: one search field named "Filter Songs" (no second, system
///   field in the navigation bar); typing shows one "Clear Search" button that empties
///   the field;
/// - placement and reading order: the field lies in the bottom of the window, inside it,
///   and reads after the navigation bar and the song rows drawn above it;
/// - target size: the field's element spans its capsule (at least 44 pt tall), a tap on
///   the magnifier (the capsule's padding, not the text) focuses it, Clear Search is at
///   least 44 × 44 pt, both are hittable, and the field stays above the keyboard;
/// - text scaling: at AX5 the field grows taller than at the standard size, its text
///   stays whole and Clear Search keeps its target;
/// - a `performAccessibilityAudit` (hit region, element description, Dynamic Type,
///   clipped text) scoped to the field and Clear Search reports nothing.
///
/// The hosted `SongsBottomFilterFieldAccessibilityTests` cover the book pose's right page,
/// AXPress on Clear and the order of field and Clear; `BottomSearchFieldSurfaceRenderTests`
/// cover Reduce Transparency and Increase Contrast.
///
/// Needs `tools/mock_service.py` and the folded Duo:
/// `python3 tools/ios_sim.py uitest --device duo --pose folded --only SongsBottomFilterFieldJourneyTests`
/// (`apple-ci`'s `songs-filter-journeys` duo-folded leg, fixture on the default port 8765;
/// `FST_FIXTURE_URL` points a local run at another port). Elsewhere it skips.
///
/// HIG Search fields: "Place search at the bottom if there's room; this keeps priority
/// search easy to reach"; HIG Text fields: "Display a trailing Clear button"; HIG
/// Accessibility: iOS default control size 44×44 pt.
final class SongsBottomFilterFieldJourneyTests: XCTestCase {
    private static let fieldID = "fst.songs.filter-field"
    private static let clearID = "fst.songs.filter-clear"
    /// `UIContentSizeCategory.accessibilityExtraExtraExtraLarge`.
    private static let ax5 = "UICTContentSizeCategoryAccessibilityXXXL"
    private static let standard = "UICTContentSizeCategoryL"
    /// Typed into the field: matches fixture titles, so the list stays populated.
    private static let query = "Fixture"

    /// The field at the standard text size on the folded Duo.
    @MainActor
    func testBottomFilterFieldIsAccessibleDuoFolded() throws {
        continueAfterFailure = false
        _ = try checkField(typeSize: Self.standard, name: "standard")
    }

    /// The field at AX5 on the folded Duo: it grows past its standard-size height and
    /// keeps every check.
    @MainActor
    func testBottomFilterFieldGrowsAtAX5DuoFolded() throws {
        continueAfterFailure = false
        let standard = try checkField(typeSize: Self.standard, name: "standard")
        let largest = try checkField(typeSize: Self.ax5, name: "ax5")
        XCTAssertGreaterThan(largest.height, standard.height + 4,
                             "the AX5 field \(largest) did not grow past the standard field \(standard)")
    }

    // MARK: - Checks

    /// Launch Songs in the folded Duo window at `typeSize` and check the bottom field.
    ///
    /// - Parameters:
    ///   - typeSize: A `UIContentSizeCategory` raw value.
    ///   - name: Attachment suffix.
    /// - Returns: The empty field's frame.
    @MainActor
    private func checkField(typeSize: String, name: String) throws -> CGRect {
        let app = try launchSongs(typeSize: typeSize)
        defer { app.terminate() }
        let window = app.windows.firstMatch.frame
        let fieldElement = app.descendants(matching: .any)[Self.fieldID]

        // Name, role and order, empty.
        let (entries, dump) = try walk(app, name: "songs-duo-filter-\(name)")
        let fields = entries.indices.filter { entries[$0].identifier == Self.fieldID }
        XCTAssertEqual(fields.count, 1, "Filter Songs fields\n\(dump)")
        let index = try XCTUnwrap(fields.first)
        let field = entries[index]
        XCTAssertEqual(field.elementType, .searchField, "role\n\(dump)")
        XCTAssertEqual(field.label, "Filter Songs", "name\n\(dump)")
        XCTAssertEqual(entries.filter { $0.elementType == .searchField }.count, 1,
                       "a second search field (the system drawer?)\n\(dump)")
        XCTAssertFalse(entries.contains { $0.identifier == Self.clearID }, "Clear shown while empty\n\(dump)")

        // At the bottom, inside the window, read after the bar and the rows above it.
        let frame = field.frame
        XCTAssertGreaterThan(frame.midY, window.midY, "the field \(frame) is not in the bottom half of \(window)")
        XCTAssertLessThanOrEqual(frame.maxY, window.maxY + 0.5, "the field \(frame) leaves \(window)")
        XCTAssertGreaterThanOrEqual(frame.minX, window.minX - 0.5, "the field \(frame) leaves \(window)")
        XCTAssertLessThanOrEqual(frame.maxX, window.maxX + 0.5, "the field \(frame) leaves \(window)")
        if let bar = entries.firstIndex(where: { $0.elementType == .navigationBar }) {
            XCTAssertLessThan(bar, index, "the field reads before the navigation bar\n\(dump)")
        }
        let rowsAbove = entries.indices.filter { row in
            entries[row].elementType == .button && entries[row].identifier.hasPrefix("fst.songs.row.")
                && entries[row].frame.maxY <= frame.minY
        }
        XCTAssertFalse(rowsAbove.isEmpty, "no song row drawn above the field\n\(dump)")
        XCTAssertTrue(rowsAbove.allSatisfy { $0 < index }, "the field reads before a row above it\n\(dump)")

        // Target: the field's element spans its capsule (at least 44 pt tall, hittable),
        // and a tap on the magnifier, the capsule's padding rather than the text, focuses it.
        XCTAssertGreaterThanOrEqual(frame.height, 44, "field \(frame)")
        XCTAssertTrue(fieldElement.isHittable, "the field is not hittable")
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.minX + 14, dy: frame.midY)).tap()
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasKeyboardFocus == true"),
                                                object: fieldElement)
        XCTAssertEqual(XCTWaiter.wait(for: [focused], timeout: FestivalApp.budget(5)), .completed,
                       "a tap on the field's magnifier (\(frame.minX + 14), \(frame.midY)) did not focus it")

        // Editing: above the keyboard, Clear Search appears, named, 44 pt, and empties it.
        fieldElement.typeText(Self.query)
        let clear = app.buttons[Self.clearID]
        XCTAssertTrue(clear.waitForExistence(timeout: FestivalApp.budget(10)), "no Clear Search after typing")
        let keyboard = app.keyboards.firstMatch
        if keyboard.waitForExistence(timeout: FestivalApp.budget(5)) {
            XCTAssertLessThanOrEqual(fieldElement.frame.maxY, keyboard.frame.minY + 0.5,
                                     "the field \(fieldElement.frame) is under the keyboard \(keyboard.frame)")
        }
        let (typed, typedDump) = try walk(app, name: "songs-duo-filter-\(name)-typed")
        let clears = typed.indices.filter { typed[$0].identifier == Self.clearID }
        XCTAssertEqual(clears.count, 1, "Clear Search buttons\n\(typedDump)")
        let clearIndex = try XCTUnwrap(clears.first)
        let clearNode = typed[clearIndex]
        XCTAssertEqual(clearNode.elementType, .button, "Clear role\n\(typedDump)")
        XCTAssertEqual(clearNode.label, "Clear Search", "Clear name\n\(typedDump)")
        XCTAssertGreaterThanOrEqual(clearNode.frame.width, 44, "Clear Search \(clearNode.frame)")
        XCTAssertGreaterThanOrEqual(clearNode.frame.height, 44, "Clear Search \(clearNode.frame)")
        let typedField = try XCTUnwrap(typed.firstIndex { $0.identifier == Self.fieldID })
        XCTAssertGreaterThan(clearIndex, typedField, "Clear Search reads before the field\n\(typedDump)")
        // VoiceOver skips unnamed containers; nothing it reads may come between. Images are
        // left out: the iOS snapshot also lists views marked `accessibilityHidden(true)`,
        // such as the decorative magnifier at AX5 (testing/apple/accessibility.md), and the
        // hosted `SongsBottomFilterFieldAccessibilityTests` prove the field exposes no image.
        let between = typed[(typedField + 1)..<max(clearIndex, typedField + 1)].filter { node in
            node.elementType != .image && (!node.label.isEmpty || !node.identifier.isEmpty)
        }
        let betweenDump = between.map { node in
            "\(node.elementType.rawValue) id='\(node.identifier)' label='\(node.label)' \(node.frame)"
        }.joined(separator: "\n")
        XCTAssertTrue(between.isEmpty, "between the field and Clear Search:\n\(betweenDump)")
        XCTAssertEqual(typed[typedField].value as? String, Self.query, "the field's value")
        XCTAssertTrue(clear.isHittable, "Clear Search is not hittable")

        try audit(app, name: name)

        clear.tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: clear)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: FestivalApp.budget(10)), .completed,
                       "Clear Search stayed after clearing")
        let value = (fieldElement.value as? String) ?? ""
        XCTAssertTrue(value.isEmpty || value == "Filter Songs", "the field kept '\(value)'")
        return frame
    }

    /// The scoped audit: only the field and Clear Search (other regions have their own
    /// journeys).
    @MainActor
    private func audit(_ app: XCUIApplication, name: String) throws {
        let types: XCUIAccessibilityAuditType = [.hitRegion, .sufficientElementDescription, .dynamicType, .textClipped]
        var issues: [String] = []
        try SongsUITestSupport.performAuditRetryingTimeout(app, types, name: name, reset: { issues = [] }) { issue in
            guard let element = issue.element,
                  [Self.fieldID, Self.clearID].contains(element.identifier) else { return true }
            issues.append("\(element.identifier): \(issue.compactDescription)")
            return true
        }
        XCTAssertTrue(issues.isEmpty, "audit \(name):\n\(issues.joined(separator: "\n"))")
    }

    // MARK: - Launch and walk

    /// Launch Songs with no selected player on the folded Duo.
    ///
    /// - Parameter typeSize: A `UIContentSizeCategory` raw value.
    /// - Returns: The app, with the bottom field and the first rows on screen.
    /// - Throws: A skip without the Duo's vertical bar or when the fixture serves no rows.
    @MainActor
    private func launchSongs(typeSize: String) throws -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": SongsUITestSupport.fixtureURL,
            "FST_UI_TEST_CLEAR_PROFILE": "1",
        ])
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", typeSize]
        app.launch()
        guard isVerticalBar(app) else {
            app.terminate()
            throw XCTSkip("Needs the iPhone Duo vertical bar: ios_sim.py uitest --device duo --pose folded")
        }
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "fst.songs.row.")).firstMatch
        guard row.waitForExistence(timeout: FestivalApp.budget(20)) else {
            app.terminate()
            throw XCTSkip("Songs showed no rows; run tools/mock_service.py on \(SongsUITestSupport.fixtureURL).")
        }
        XCTAssertTrue(app.descendants(matching: .any)[Self.fieldID].waitForExistence(timeout: FestivalApp.budget(10)),
                      "no bottom Filter Songs field on the folded Duo")
        return app
    }

    /// Whether the sections stand in a vertical bar (as `DuoSongTitleJourneyTests`).
    @MainActor
    private func isVerticalBar(_ app: XCUIApplication) -> Bool {
        func section(_ label: String) -> XCUIElement? {
            let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
            _ = matches.firstMatch.waitForExistence(timeout: FestivalApp.budget(15))
            return matches.allElementsBoundByIndex.first { $0.frame.width > 0 && $0.frame.height > 0 }
        }
        guard let songs = section("Songs"), let settings = section("Settings") else { return false }
        return abs(songs.frame.midX - settings.frame.midX) < 4
            && abs(songs.frame.midY - settings.frame.midY) > 20
    }

    /// The app's accessibility hierarchy in depth-first order (VoiceOver's order), with
    /// a dump attached for review.
    @MainActor
    private func walk(_ app: XCUIApplication, name: String) throws -> ([XCUIElementSnapshot], String) {
        let nodes = try FestivalApp.snapshotNodes(in: app) { _ in true }
        let dump = nodes.filter { node in
            ([.navigationBar, .button, .searchField, .textField] as [XCUIElement.ElementType]).contains(node.elementType)
                || node.identifier.hasPrefix("fst.songs.filter")
        }.map { "\($0.elementType.rawValue) id='\($0.identifier)' label='\($0.label)' \($0.frame)" }
            .joined(separator: "\n")
        let attachment = XCTAttachment(string: dump)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
        return (nodes, dump)
    }
}
