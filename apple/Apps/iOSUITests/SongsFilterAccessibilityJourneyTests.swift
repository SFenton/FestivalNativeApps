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

    // MARK: - Snapshot reads

    /// An element ``reveal(_:in:hittable:file:line:)`` scrolls to: the live element a caller
    /// acts on afterwards, and the same element found in an app snapshot.
    ///
    /// `find` mirrors the live query (element type, `identifier` or `label` key, scope) and
    /// returns its first match in depth-first order, the node `firstMatch` binds.
    private struct Target {
        /// The live element, for the caller's tap or read after the reveal.
        let element: XCUIElement
        /// Names the element in a failure.
        let name: String
        /// The element's node in an app snapshot, or nil when it is not in the tree.
        let find: (XCUIElementSnapshot) -> XCUIElementSnapshot?
    }

    /// The first node of `root`, depth first, of `type` (any type when nil) whose identifier
    /// or label is `key`: the node `query[key].firstMatch` binds.
    ///
    /// - Parameters:
    ///   - type: Element type to match, or nil for any.
    ///   - key: Identifier or label.
    ///   - root: The snapshot to walk.
    /// - Returns: The first matching node, or nil.
    @MainActor
    private static func first(
        _ type: XCUIElement.ElementType?, keyed key: String, in root: XCUIElementSnapshot
    ) -> XCUIElementSnapshot? {
        FestivalApp.nodes(in: root) { node in
            (type == nil || node.elementType == type) && (node.identifier == key || node.label == key)
        }.first
    }

    /// Whether a node is one of Year's decade switches.
    private static func isDecade(_ node: XCUIElementSnapshot) -> Bool {
        node.elementType == .switch && node.identifier.hasPrefix(prefix + "year.")
    }

    /// A General element by identifier suffix, as ``element(_:in:)``.
    @MainActor
    private func target(_ id: String, in app: XCUIApplication) -> Target {
        Target(element: element(id, in: app), name: Self.prefix + id) { Self.first(nil, keyed: Self.prefix + id, in: $0) }
    }

    /// A sheet button by identifier suffix (`app.buttons[…]`).
    @MainActor
    private func button(_ id: String, in app: XCUIApplication) -> Target {
        Target(element: app.buttons[Self.prefix + id], name: Self.prefix + id) {
            Self.first(.button, keyed: Self.prefix + id, in: $0)
        }
    }

    /// A switch by identifier or label (`app.switches[…].firstMatch`).
    @MainActor
    private func toggle(_ key: String, in app: XCUIApplication) -> Target {
        Target(element: app.switches[key].firstMatch, name: "switch \(key)") { Self.first(.switch, keyed: key, in: $0) }
    }

    /// A static text by identifier or label (`app.staticTexts[…].firstMatch`).
    @MainActor
    private func text(_ key: String, in app: XCUIApplication) -> Target {
        Target(element: app.staticTexts[key].firstMatch, name: "text \(key)") { Self.first(.staticText, keyed: key, in: $0) }
    }

    /// Year's first decade switch, or the one labelled `label`.
    @MainActor
    private func decade(_ label: String? = nil, in app: XCUIApplication) -> Target {
        let format = label == nil ? "identifier BEGINSWITH %@" : "identifier BEGINSWITH %@ AND label == %@"
        let arguments: [Any] = [Self.prefix + "year."] + (label.map { [$0] } ?? [])
        return Target(
            element: app.switches.matching(NSPredicate(format: format, argumentArray: arguments)).firstMatch,
            name: "decade \(label ?? "first")"
        ) { root in
            FestivalApp.nodes(in: root) { Self.isDecade($0) && (label == nil || $0.label == label) }.first
        }
    }

    /// One app snapshot, retried when it throws (``FestivalApp/snapshot(of:within:until:)``).
    /// A snapshot that still fails fails the test, as the live query it replaces did.
    ///
    /// - Parameters:
    ///   - app: Launched fixture Songs.
    ///   - timeout: How long to wait for `ready`, before ``FestivalApp/budget(_:inVirtualMachine:)``.
    ///   - ready: Whether a snapshot shows what the caller waits for.
    /// - Returns: The first ready snapshot (the last one taken when none was ready in time),
    ///   or nil when every attempt threw.
    @MainActor
    private func appSnapshot(
        _ app: XCUIApplication, within timeout: TimeInterval = 3,
        until ready: (XCUIElementSnapshot) -> Bool = { _ in true },
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElementSnapshot? {
        do {
            return try FestivalApp.snapshot(of: app, within: FestivalApp.budget(timeout), until: ready)
        } catch {
            XCTFail("No snapshot of the Filter sheet: \(error.localizedDescription)", file: file, line: line)
            return nil
        }
    }

    /// Where the sheet's content starts: below its title bar, and below Close (✕) when
    /// Close sits above the Form. On the folded iPhone Duo Close is in the sheet's
    /// vertical bar beside the Form, so only the title bar counts.
    ///
    /// - Parameters:
    ///   - target: Row being revealed, or nil when it is not in the tree.
    ///   - root: An app snapshot with the sheet open.
    /// - Returns: The y coordinate the row must start at to be fully visible.
    @MainActor
    private func sheetContentTop(for target: XCUIElementSnapshot?, in root: XCUIElementSnapshot) -> CGFloat {
        let done = Self.first(.button, keyed: Self.prefix + "done", in: root)?.frame ?? .zero
        let barBottom = Self.first(.navigationBar, keyed: "Filter Songs", in: root)?.frame.maxY ?? 0
        let besideRows = target.map { done.minX >= $0.frame.maxX } ?? false
        return besideRows ? barBottom : max(barBottom, done.maxY)
    }

    /// Scroll the sheet's Form either way until an element is wholly between the sheet's
    /// top bar and the screen bottom (at AX5 Year sits far above Reset).
    ///
    /// - Parameters:
    ///   - target: Element inside the Filter Form.
    ///   - app: Launched fixture Songs with the sheet open.
    ///   - hittable: Also require it to be hittable; pass false only where the caller proves
    ///     it with a real tap instead (``assertYearGroup(_:file:line:)``).
    /// - Returns: The revealed element.
    @MainActor
    @discardableResult
    private func reveal(
        _ target: Target, in app: XCUIApplication, hittable: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) -> XCUIElement {
        revealNode(target, in: app, hittable: hittable, file: file, line: line)
        return target.element
    }

    /// ``reveal(_:in:hittable:file:line:)``, returning the revealed node.
    ///
    /// Each step reads the target, the Form, the bar, Close and the window from one app
    /// snapshot, retried when it throws, and drags at points rooted at the app: on the
    /// folded iPhone Duo's starved runner a live `exists`, `isHittable` or `frame` read here,
    /// after the sheet's first audit, hung past XCTest's retries and failed the test
    /// outright (#695, the stall class of #693/#694). Hittable is read from the snapshots
    /// too: wholly in the sheet's content, as below, and at rest (the same frame in two
    /// snapshots in a row), since a settling bounce is what kept the hit test off a row
    /// already in place; the caller's tap then proves the hit test itself.
    ///
    /// - Parameters: As ``reveal(_:in:hittable:file:line:)``.
    /// - Returns: The revealed node and the snapshot it was read from, or nil when no
    ///   snapshot showed it (the failure is recorded).
    @MainActor
    @discardableResult
    private func revealNode(
        _ target: Target, in app: XCUIApplication, hittable: Bool = true,
        file: StaticString = #filePath, line: UInt = #line
    ) -> (node: XCUIElementSnapshot, root: XCUIElementSnapshot)? {
        guard var root = appSnapshot(app, file: file, line: line) else { return nil }
        guard var form = FestivalApp.node(Self.prefix + "form", in: root)?.frame,
              let windowBottom = SongsUITestSupport.sheetVisibleBottom(in: root) else {
            XCTFail("No Filter Form or window to reveal \(target.name) in", file: file, line: line)
            return nil
        }
        // The iPad form sheet ends above the window's bottom.
        let bottom = min(windowBottom, form.maxY - 8)
        var node = target.find(root)
        // Whether the target's frame matched the previous snapshot's: at rest.
        var still = false
        func refresh() -> Bool {
            let previous = node?.frame
            guard let next = appSnapshot(app, file: file, line: line) else { return false }
            root = next
            node = target.find(next)
            form = FestivalApp.node(Self.prefix + "form", in: next)?.frame ?? form
            still = node != nil && node?.frame == previous
            return true
        }
        // A row taller than the space (Item Shop at AX5 on the folded Duo) only has to
        // start below the bar; the last rows, where the Form ends at the window edge (the
        // folded Duo), only have to end inside the Form once dragging no longer moves them.
        var atEnd = false
        func visible() -> Bool {
            guard let frame = node?.frame else { return false }
            let top = sheetContentTop(for: node, in: root)
            let fits = frame.height <= bottom - top
            let inForm = atEnd && frame.maxY <= form.maxY
            let placed = frame.minY >= top && (frame.maxY <= bottom || !fits || inForm)
            return placed && (!hittable || (still && !frame.isEmpty))
        }
        // Drag by the measured distance (fixed swipes overshot a tall row both ways);
        // down only as far as the row is hidden, since dragging the Form down past its
        // top would dismiss the sheet.
        func drag(by distance: CGFloat) {
            let top = sheetContentTop(for: node, in: root)
            let span = max(bottom - top - 48, 40)
            // The scroll view's touch slop eats the first ≈ 10 pt of a drag.
            let step = min(abs(distance) + 12, span)
            let x = form.minX + 32
            let startY = distance < 0 ? bottom - 24 : top + 24
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: x, dy: startY))
                .press(forDuration: 0.05,
                       thenDragTo: origin.withOffset(CGVector(dx: x, dy: startY + (distance < 0 ? -step : step))),
                       withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        var attempt = 0
        var moved = false
        while !visible() && attempt < 30 {
            defer { attempt += 1 }
            guard let frame = node?.frame else {
                // Not loaded: the Form is lazy. Page down without momentum (a swipe carried
                // past a single row); back up with a slow swipe, whose momentum bounces at the
                // top, where a held drag would pull the sheet and dismiss it.
                if attempt < 12 {
                    drag(by: -(bottom - sheetContentTop(for: nil, in: root)) / 2)
                } else {
                    element("form", in: app).swipeDown(velocity: .slow)
                }
                moved = true
                guard refresh() else { return nil }
                continue
            }
            let top = sheetContentTop(for: node, in: root)
            if frame.minY >= top, frame.maxY <= bottom {
                // In place but still moving (a bounce settling): wait rather than drag,
                // since a drag at the Form's top pulls the sheet and keeps it unsettled.
                Thread.sleep(forTimeInterval: 0.5)
                guard refresh() else { return nil }
                continue
            }
            let distance: CGFloat
            if frame.minY < top {
                distance = top - frame.minY + 8
            } else if frame.height > bottom - top {
                distance = -(frame.minY - top - 8)
            } else {
                distance = -(frame.maxY - bottom + 8)
            }
            guard abs(distance) >= 4 else { break }
            moved = true
            if distance > (bottom - top) / 2 {
                // Far above: an offscreen row's frame can be stale, and a held drag past the
                // top would pull the sheet down; a slow swipe's momentum bounces there instead.
                element("form", in: app).swipeDown(velocity: .slow)
                guard refresh() else { return nil }
                continue
            }
            drag(by: distance)
            guard refresh() else { return nil }
            atEnd = distance < 0 && node.map { abs($0.frame.minY - frame.minY) < 1 } ?? false
        }
        // Let a drag that met the Form's top or end bounce back before anything is audited.
        if moved {
            for _ in 0..<10 {
                Thread.sleep(forTimeInterval: 0.2)
                guard refresh(), node != nil, !still else { break }
            }
        }
        XCTAssertTrue(
            visible(),
            "\(target.name) not reachable in the sheet: frame \(node.map { "\($0.frame)" } ?? "none"), "
                + "top \(sheetContentTop(for: node, in: root)), bottom \(bottom)"
                + (hittable && !still ? ", still moving" : ""),
            file: file, line: line
        )
        return node.map { ($0, root) }
    }

    /// Open Filter from the floating tools: the Filter Songs button, or at large text the
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
        revealAndTap(button("reset", in: app), in: app, file: file, line: line)
        app.buttons[Self.prefix + "done"].tap()
        openSheet(app, file: file, line: line)
    }

    /// What VoiceOver reads for a toolbar tool: its label, then its value. iOS system
    /// navigation bars (the iPhone Duo vertical bar, the iPad on iOS 27) drop values, so
    /// there the state is in the label (`BarItemSpokenState`).
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
            // The CI runner's Duo takes several seconds to settle the dismissal.
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: done)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 20), .completed,
                           "Filter did not close after the near-miss tap at (\(Int(offset.dx)), \(Int(offset.dy))) pt")
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        }
    }

    /// Assert an element is a target of at least 44x44 pt.
    @MainActor
    private func assertTarget(
        _ element: XCUIElement, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        assertTarget(element.frame, name, file: file, line: line)
    }

    /// Assert a frame, read from a snapshot, is a target of at least 44x44 pt.
    private func assertTarget(
        _ frame: CGRect, _ name: String, file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(frame.height, 44, "\(name) target height \(frame)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.width, 44, "\(name) target width \(frame)", file: file, line: line)
    }

    /// Tap a revealed node where `XCUIElement.tap()` would, the middle of its part inside
    /// the sheet's content, at a point rooted at the app rather than through a live query
    /// (#695).
    ///
    /// - Parameters:
    ///   - revealed: A node and its snapshot, from ``revealNode(_:in:hittable:file:line:)``.
    ///   - app: Launched fixture Songs with the sheet open.
    @MainActor
    private func tap(_ revealed: (node: XCUIElementSnapshot, root: XCUIElementSnapshot), in app: XCUIApplication) {
        let frame = revealed.node.frame
        let top = sheetContentTop(for: revealed.node, in: revealed.root)
        let bottom = SongsUITestSupport.sheetVisibleBottom(in: revealed.root) ?? frame.maxY
        let shown = frame.intersection(CGRect(x: frame.minX, y: top, width: frame.width, height: max(bottom - top, 0)))
        let point = shown.isNull || shown.isEmpty
            ? CGPoint(x: frame.midX, y: frame.midY) : CGPoint(x: shown.midX, y: shown.midY)
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: point.x, dy: point.y)).tap()
    }

    /// Reveal an element and tap it from the reveal's snapshot (``tap(_:in:)``).
    ///
    /// - Parameters:
    ///   - target: Element inside the Filter Form.
    ///   - app: Launched fixture Songs with the sheet open.
    @MainActor
    private func revealAndTap(
        _ target: Target, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) {
        guard let shown = revealNode(target, in: app, file: file, line: line) else { return }
        tap(shown, in: app)
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
        var previous = Self.prefix + "general"
        for group in Self.groups {
            guard let shown = revealNode(target(group.id, in: app), in: app, file: file, line: line) else { return }
            let label = shown.node
            XCTAssertTrue(label.label.hasPrefix(group.title), "\(group.id) named \(label.label)", file: file, line: line)
            XCTAssertGreaterThan(label.label.count, group.title.count + 10, "\(group.id) reads its hint",
                                 file: file, line: line)
            // Compared in one snapshot; a group scrolled out of the tree is above.
            if let above = FestivalApp.node(previous, in: shown.root) {
                XCTAssertLessThan(above.frame.minY, label.frame.minY, "\(group.id) follows \(previous)",
                                  file: file, line: line)
            }
            previous = label.identifier
        }
    }

    /// Expand Year and check its header actions and decade switches: named, reporting
    /// their state, and 44 pt targets. Clear All and Select All are pressed for real and
    /// the decades must report the change.
    ///
    /// Opened while its header sits under the sheet's bar (AX5), the header's actions can
    /// stay missing from the accessibility hit test after they fade in (iOS 27 beta; real
    /// touches land, and the next state change restores it; an open finding in
    /// `.agents/patterns/accordion.md`), so they are revealed without that check and proved
    /// by a coordinate tap.
    ///
    /// It follows the sheet's first audit, where the folded iPhone Duo's runner is slow
    /// enough that a live query stalls past XCTest's retries, so everything is read from
    /// retried snapshots and tapped at points rooted at the app (#695).
    ///
    /// - Returns: The decade switches, as first read (all on).
    @MainActor
    private func assertYearGroup(
        _ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line
    ) -> [XCUIElementSnapshot] {
        let selectAllID = Self.prefix + "year.select-all"
        let isSelectAll: (XCUIElementSnapshot) -> Bool = { Self.first(.button, keyed: selectAllID, in: $0) != nil }
        guard let before = appSnapshot(app, file: file, line: line) else { return [] }
        if !isSelectAll(before) {
            guard let year = revealNode(target("year", in: app), in: app, file: file, line: line) else { return [] }
            tap(year, in: app)
        }
        guard let expanded = appSnapshot(app, within: 10, until: isSelectAll, file: file, line: line) else { return [] }
        XCTAssertTrue(isSelectAll(expanded), "Year did not expand", file: file, line: line)
        XCTAssertEqual(Self.first(.button, keyed: selectAllID, in: expanded)?.label, "Select All, Year",
                       file: file, line: line)
        XCTAssertEqual(Self.first(.button, keyed: Self.prefix + "year.clear-all", in: expanded)?.label,
                       "Clear All, Year", file: file, line: line)
        let hasDecades: (XCUIElementSnapshot) -> Bool = { !FestivalApp.nodes(in: $0, where: Self.isDecade).isEmpty }
        guard var listed = appSnapshot(app, until: hasDecades, file: file, line: line) else { return [] }
        // The Form is lazy: rows below its end load once scrolled to.
        if !hasDecades(listed) {
            guard let shown = revealNode(decade(in: app), in: app, file: file, line: line) else { return [] }
            listed = shown.root
        }
        let decades = FestivalApp.nodes(in: listed, where: Self.isDecade)
        XCTAssertFalse(decades.isEmpty, "No decades", file: file, line: line)
        for decade in decades {
            XCTAssertTrue(decade.label.hasSuffix("s"), "\(decade.identifier) named \(decade.label)",
                          file: file, line: line)
            XCTAssertEqual(decade.value as? String, "1", "\(decade.identifier) starts on", file: file, line: line)
        }
        guard let firstID = decades.first?.identifier,
              let first = revealNode(toggle(firstID, in: app), in: app, file: file, line: line) else { return decades }
        assertTarget(first.node.frame, firstID, file: file, line: line)
        for (id, name, value) in [("year.clear-all", "Clear All, Year", "0"), ("year.select-all", "Select All, Year", "1")] {
            guard let shown = revealNode(button(id, in: app), in: app, hittable: false, file: file, line: line) else {
                return decades
            }
            let frame = shown.node.frame
            assertTarget(frame, name, file: file, line: line)
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            let applied = appSnapshot(app, within: 5, until: { FestivalApp.node(firstID, in: $0)?.value as? String == value },
                                      file: file, line: line)
            XCTAssertEqual(applied.flatMap { FestivalApp.node(firstID, in: $0)?.value as? String }, value,
                           "\(name) sets \(firstID) to \(value)", file: file, line: line)
        }
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
    /// - Returns: Whether `proof` deferred any issue.
    @MainActor
    @discardableResult
    private func audit(
        _ app: XCUIApplication, for types: XCUIAccessibilityAuditType,
        deferring proof: ((XCUIAccessibilityAuditIssue) -> Bool)? = nil
    ) throws -> Bool {
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        // Read from one retried snapshot: a live `exists`/`frame` here hung on the folded
        // Duo's starved runner and failed the test outright (#694).
        let root = try FestivalApp.snapshot(of: app, within: FestivalApp.budget(5)) {
            FestivalApp.node(Self.prefix + "form", in: $0) != nil
        }
        let window = root.children.first { $0.elementType == .window }?.frame
        let edge = FestivalApp.node(Self.prefix + "form", in: root).map { form in
            (top: form.frame.minY, bottom: min(form.frame.maxY, window?.maxY ?? form.frame.maxY))
        }
        var cut: [String] = []
        var anyDeferred = false
        // The runner's simulator can miss XCTest's audit deadline (#636, the folded Duo):
        // run once more after clearing what the first pass collected.
        try SongsUITestSupport.performAuditRetryingTimeout(
            app, types, name: "songs-filter",
            reset: { cut.removeAll(); anyDeferred = false }
        ) { issue in
            let deferred = proof?(issue) ?? false
            anyDeferred = anyDeferred || deferred
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
                    + (deferred ? " (deferred to measured text growth)" : "")
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
            reveal(Target(element: text, name: "label \(label)") { root in
                FestivalApp.nodes(in: root) { $0.label == label }.first
            }, in: app)
            // Everything else was judged whole in the first pass.
            try SongsUITestSupport.performAuditRetryingTimeout(
                app, .contrast, name: "songs-filter-revealed", reset: {}
            ) { issue in
                guard issue.element?.label == label else { return true }
                let attachment = XCTAttachment(string: "Contrast, revealed whole: \(label)")
                attachment.name = "songs-filter-audit-issue"
                attachment.lifetime = .keepAlways
                self.add(attachment)
                return false
            }
        }
        return anyDeferred
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
    ///   - proof: As ``audit(_:for:deferring:)``.
    ///   - deferredAt: Called at rest at an end whose audit deferred an issue, so the caller
    ///     can record what was on screen.
    @MainActor
    private func auditAtEnds(
        _ app: XCUIApplication, for types: XCUIAccessibilityAuditType,
        deferring proof: ((XCUIAccessibilityAuditIssue) -> Bool)? = nil,
        deferredAt: (() -> Void)? = nil
    ) throws {
        let general = target("general", in: app)
        revealNode(general, in: app)
        let form = element("form", in: app)
        // Short held drags down until General stops moving: the Form rests at its very top
        // (a pull this small springs back rather than dismissing the sheet).
        for _ in 0..<4 {
            guard let root = appSnapshot(app), let before = general.find(root),
                  let formFrame = FestivalApp.node(Self.prefix + "form", in: root)?.frame else {
                XCTFail("General or the Form left the sheet while resting at its top")
                break
            }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(
                dx: formFrame.minX + 32, dy: sheetContentTop(for: before, in: root) + 24
            ))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 40)),
                        withVelocity: .slow, thenHoldForDuration: 0.3)
            Thread.sleep(forTimeInterval: 0.8)
            guard let after = appSnapshot(app).flatMap(general.find) else {
                XCTFail("General left the sheet while resting at its top")
                break
            }
            if abs(after.frame.minY - before.frame.minY) < 1 { break }
        }
        XCTAssertTrue(app.navigationBars["Filter Songs"].exists, "Filter sheet dismissed while resting at its top")
        if try audit(app, for: types, deferring: proof) { deferredAt?() }
        let reset = app.buttons[Self.prefix + "reset"]
        // Swiping up past the end only bounces; down at the top would dismiss the sheet.
        var swipes = 0
        while !(reset.exists && reset.isHittable) && swipes < 12 {
            form.swipeUp()
            swipes += 1
        }
        form.swipeUp()
        XCTAssertTrue(reset.isHittable, "Reset Filters not reached at the end of the sheet")
        if try audit(app, for: types, deferring: proof) { deferredAt?() }
    }

    /// At the largest text size every group's hint wraps onto several lines (at least 1.5x
    /// its one-line title) instead of truncating to one.
    @MainActor
    private func assertHintsWrap(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for group in Self.hints {
            let title = revealNode(text(group.title, in: app), in: app, file: file, line: line)?.node.frame.height ?? 0
            let hint = revealNode(text(group.hint, in: app), in: app, file: file, line: line)?.node.frame.height ?? 0
            XCTAssertGreaterThanOrEqual(hint, title * 1.5, "\(group.title) hint wraps: title \(title), hint \(hint)",
                                        file: file, line: line)
        }
    }

    /// Heights of the Item Shop group's title and hint, each scrolled wholly on screen.
    ///
    /// - Returns: Frame heights in ``shopTexts`` order.
    @MainActor
    private func shopTextHeights(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) -> [CGFloat] {
        Self.shopTexts.map { shopText in
            revealNode(text(shopText, in: app), in: app, file: file, line: line)?.node.frame.height ?? 0
        }
    }

    /// The height of a Year decade switch's label text (the switch's own frame when it
    /// has no text child), revealed first and read from the reveal's snapshot (#695).
    ///
    /// - Parameters:
    ///   - label: Decade label, e.g. "2020s".
    ///   - app: Launched fixture Songs with Year open.
    /// - Returns: Height in points (0 when the decade was not revealed, a recorded failure).
    @MainActor
    private func decadeTextHeight(_ label: String, in app: XCUIApplication) -> CGFloat {
        guard let row = revealNode(decade(label, in: app), in: app)?.node else { return 0 }
        let text = FestivalApp.nodes(in: row) { node in
            node.elementType == .staticText && (node.identifier == label || node.label == label)
        }.first
        return (text ?? row).frame.height
    }

    /// The texts wholly visible in the sheet's Form now, by label, with their heights: each
    /// static text, and a switch's own frame when it has no static text of its label (as
    /// ``decadeTextHeight(_:in:)``). The navigation bar's title is outside the Form (a
    /// system bar caps its text size: `system-bar-title-size`).
    ///
    /// - Parameter app: Launched fixture Songs with the sheet open, at rest.
    /// - Returns: Height in points by label.
    @MainActor
    private func visibleFormTexts(_ app: XCUIApplication) -> [String: CGFloat] {
        let form = element("form", in: app)
        let bar = app.navigationBars["Filter Songs"]
        let top = max(form.frame.minY, bar.exists ? bar.frame.maxY : 0)
        let bottom = min(SongsUITestSupport.sheetVisibleBottom(in: app), form.frame.maxY)
        var texts: [String: CGFloat] = [:]
        func record(_ label: String, _ frame: CGRect) {
            guard !label.isEmpty, frame.minY >= top - 1, frame.maxY <= bottom + 1 else { return }
            texts[label] = max(texts[label] ?? 0, frame.height)
        }
        func walk(_ node: XCUIElementSnapshot) {
            if node.elementType == .staticText {
                record(node.label, node.frame)
            } else if node.elementType == .switch,
                      !node.children.contains(where: { $0.elementType == .staticText && $0.label == node.label }) {
                record(node.label, node.frame)
            }
            node.children.forEach(walk)
        }
        if let snapshot = try? form.snapshot() {
            walk(snapshot)
        }
        if texts.isEmpty {
            // A snapshot can stop short of the rows (the iPhone Duo's); query them instead.
            for text in form.staticTexts.allElementsBoundByIndex where text.exists {
                record(text.label, text.frame)
            }
        }
        return texts
    }

    /// The page-level evidence for an element-less Dynamic Type issue in an AX5 audit
    /// (`unattributed-dynamic-type-page-growth`, `.agents/testing/apple/accessibility.md`):
    /// with no element to measure, every text the sheet showed at that moment must be at
    /// least 1.35x taller at AX5 than in a default-size launch of the same sheet.
    ///
    /// - Parameters:
    ///   - texts: ``visibleFormTexts(_:)`` recorded at AX5 where the issue was reported.
    ///   - showShop: Whether Settings showed the Item Shop in the audited launch.
    @MainActor
    private func assertGrowthFromDefault(_ texts: [String: CGFloat], showShop: Bool) {
        XCTAssertFalse(texts.isEmpty, "No text measured where the element-less Dynamic Type issue was reported")
        let app = launchSongs(showShop: showShop)
        openCleanSheet(app)
        _ = assertYearGroup(app)
        let form = element("form", in: app)
        var evidence: [String] = []
        for (label, large) in texts.sorted(by: { $0.key < $1.key }) {
            let text = form.staticTexts.matching(NSPredicate(format: "label == %@", label)).firstMatch
            // A switch recorded by its own frame (no text of its label) is measured the same way.
            let isSwitch = !text.waitForExistence(timeout: 2) && app.switches[label].exists
            let formText = Target(element: text, name: "form text \(label)") { root in
                FestivalApp.node(Self.prefix + "form", in: root).flatMap { form in
                    FestivalApp.nodes(in: form) { $0.elementType == .staticText && $0.label == label }.first
                }
            }
            let regular = revealNode(isSwitch ? toggle(label, in: app) : formText, in: app)?.node.frame.height ?? 0
            evidence.append("\(label): \(regular) → \(large)")
            XCTAssertGreaterThanOrEqual(large, regular * 1.35, "\(label) grows at AX5: \(regular) → \(large)")
        }
        let attachment = XCTAttachment(string: "unattributed-dynamic-type-page-growth\n" + evidence.joined(separator: "\n"))
        attachment.name = "songs-filter-audit-evidence"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.terminate()
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

        // Past two sheet audits the runner is at its slowest: flip and wait through retried
        // snapshots, not live queries (#694).
        let decadeID = decades.first?.identifier ?? ""
        reveal(toggle(decadeID, in: app), in: app)
        try SongsUITestSupport.setSwitch(decadeID, to: "0", in: app)
        revealAndTap(button("year.select-all", in: app), in: app)
        let reselected = try FestivalApp.snapshot(of: app, within: FestivalApp.budget(5)) {
            FestivalApp.node(decadeID, in: $0)?.value as? String == "1"
        }
        XCTAssertEqual(FestivalApp.node(decadeID, in: reselected)?.value as? String, "1", "Select All, Year reselects")

        revealAndTap(target("double-bass", in: app), in: app)
        let noDoubleBassID = Self.prefix + "double-bass.unsupported"
        // Expanded at the Form's end (the folded Duo), its choices load once scrolled to.
        _ = appSnapshot(app, until: { Self.first(.switch, keyed: noDoubleBassID, in: $0) != nil })
        let noDoubleBass = revealNode(toggle(noDoubleBassID, in: app), in: app)?.node
        XCTAssertEqual(noDoubleBass?.label, "No Double Bass Support")
        try SongsUITestSupport.setSwitch(noDoubleBassID, to: "0", in: app)
        app.buttons[Self.prefix + "done"].tap()
        let named = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@ OR label CONTAINS %@",
                                   "Double Bass filter", "Double Bass filter"), object: filter
        )
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 10), .completed,
                       "Filter Songs names the active filter: \(Self.spoken(filter))")

        openSheet(app)
        revealAndTap(button("reset", in: app), in: app)
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
    /// measured instead); an element-less Dynamic Type issue there (iOS 27) passes only on
    /// page-level growth: every text on screen at that end is at least 1.35x taller than in a
    /// default-size launch (``assertGrowthFromDefault(_:showShop:)``). Text clipped is audited
    /// at the default size only: at AX5 iOS 26.5
    /// intermittently reports an element-less Text clipped issue on a state that passes on
    /// rerun (an open finding, like the Songs and Item Shop lists'), so wrapping is asserted.
    @MainActor
    func testGeneralFiltersAtLargestText() throws {
        continueAfterFailure = false
        let largest = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue
        let regular = launchSongs()
        openCleanSheet(regular)
        let regularHeight = revealNode(target("double-bass", in: regular), in: regular)?.node.frame.height ?? 0
        let regularShop = shopTextHeights(regular)
        regular.terminate()

        let app = launchSongs(contentSize: largest)
        openCleanSheet(app)
        assertGeneralOnly(app)
        let largeHeight = revealNode(target("double-bass", in: app), in: app)?.node.frame.height ?? 0
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
        XCTAssertTrue(reveal(button("reset", in: app), in: app).isHittable)
        app.terminate()

        let hidden = launchSongs(contentSize: largest, showShop: false)
        openCleanSheet(hidden)
        // iOS 27 reports an element-less "Dynamic Type font sizes are unsupported" here; with
        // nothing to measure, the texts on screen are measured against a default-size launch.
        var shown: [String: CGFloat] = [:]
        let unattributed: (XCUIAccessibilityAuditIssue) -> Bool = {
            $0.auditType == .dynamicType && $0.element == nil
        }
        let recordShown = { shown.merge(self.visibleFormTexts(hidden)) { max($0, $1) } }
        try auditAtEnds(hidden, for: .dynamicType, deferring: unattributed, deferredAt: recordShown)
        _ = assertYearGroup(hidden)
        try auditAtEnds(hidden, for: .dynamicType, deferring: unattributed, deferredAt: recordShown)
        guard !shown.isEmpty else { return }
        hidden.terminate()
        assertGrowthFromDefault(shown, showShop: false)
    }
}
