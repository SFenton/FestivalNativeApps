import UIKit
import Vision
import XCTest

/// Rival Detail while the service publishes (#95), on iPhone, iPad and iPhone Duo (#444).
///
/// #95 made a rival open during a publish: the detail read answers the freeze's 503 and
/// the comparison is rebuilt from `/rivals/all`; when that has no samples the page keeps
/// the auto-retry state. These journeys open that page on a device against
/// `tools/mock_service.py` (`fixture-riv-frozen`: detail reads 503, `/rivals/all`
/// answers; `fixture-riv-503`: every Rivals read 503) through the Lead+Bass combo scope
/// the Rivals hub uses, and check what only a device shows: the iOS accessibility tree's
/// names and reading order, hit regions at 44 pt (HIG Accessibility: "Strive for the
/// platform's recommended minimum control size", 44x44 pt on iOS and iPadOS), Dynamic
/// Type at the largest accessibility size, and `performAccessibilityAudit`. The macOS
/// hosted `RivalDetailAccessibilityTests` pin roles (headings, buttons) and the loading
/// state in `swift test`.
///
/// The same class runs on each device class, so its assertions hold at every width:
/// compact (iPhone, the folded iPhone Duo) and regular (iPad full screen).
/// `apple-ci` runs it on an iPhone 17 Pro, an iPad Pro 11-inch and an iPhone Duo
/// (folded) simulator ([CI journeys](../../../.agents/testing/apple/xcuitest.md#ci-journeys)).
/// Locally: `python3 tools/mock_service.py` (port 8765, or `TEST_RUNNER_FST_FIXTURE_URL`), then
/// `python3 tools/ios_sim.py uitest --device iphone|ipad|duo --app phone --fail-on-skip --only RivalDetailFrozenAccessibilityJourneyTests`
/// (`--pose folded` on the Duo).
final class RivalDetailFrozenAccessibilityJourneyTests: XCTestCase {
    // MARK: - Fixture

    /// The rival `/rivals/all` describes for `fixture-riv-frozen` (`mock_service.FROZEN_RIVAL_ID`).
    private static let rivalId = "frozenrival9"

    /// Every comparison row the fallback builds, by spoken name. Fixture Pulse is shared
    /// on Lead and Bass, so only the instrument tells its two rows apart. A row can appear
    /// in more than one card (Closest Battles and Almost Passed, say).
    private static let rowNames: Set<String> = [
        "Fixture Pulse, Lead, you rank 10, Rival Nine ranks 11",
        "Fixture Pulse, Bass, you rank 12, Rival Nine ranks 10",
        "Fixture Orbit, Lead, you rank 3, Rival Nine ranks 20",
    ]

    /// The row the growth check measures (first row of Closest Battles).
    private static let firstRow = "Fixture Pulse, Lead, you rank 10, Rival Nine ranks 11"

    /// The largest accessibility text size (AX5).
    private static let ax5 = UIContentSizeCategory.accessibilityExtraExtraExtraLarge.rawValue

    /// Launch straight onto Rival Detail with the hub's Lead+Bass combo scope.
    ///
    /// - Parameters:
    ///   - player: The selected fixture player, whose suffix picks the Rivals scenario.
    ///   - contentSize: A `UIContentSizeCategory` raw value, or nil for the default.
    /// - Returns: The launched app.
    @MainActor
    private func launch(player: String, contentSize: String? = nil) -> XCUIApplication {
        let app = FestivalApp.makeApp([
            "FST_API_BASE_URL": ProcessInfo.processInfo.environment["FST_FIXTURE_URL"] ?? "http://127.0.0.1:8765",
            "FST_UI_TEST_CLEAR_PROFILE": "1",
            "FST_DEBUG_PROFILE": "\(player):Fixture Riv",
            "FST_DEBUG_ROUTE": "rivalDetail:\(Self.rivalId):combo:03:Solo_Guitar,Solo_Bass",
        ])
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    // MARK: - Tree helpers

    /// One accessibility element, in the order the tree lists it.
    private struct Node {
        let type: XCUIElement.ElementType
        let identifier: String
        let label: String
        let frame: CGRect
    }

    /// The app's accessibility tree depth first, as VoiceOver stops on it (reading order).
    ///
    /// A button is one stop: XCUITest lists the views inside its label (a row's instrument
    /// icon and texts) as its children, but VoiceOver reads the button's own name and never
    /// visits them, so the walk does not descend into buttons.
    @MainActor
    private func readingOrder(_ app: XCUIApplication) throws -> [Node] {
        var nodes: [Node] = []
        func walk(_ snapshot: any XCUIElementSnapshot) {
            nodes.append(Node(
                type: snapshot.elementType, identifier: snapshot.identifier,
                label: snapshot.label, frame: snapshot.frame
            ))
            guard snapshot.elementType != .button else { return }
            snapshot.children.forEach(walk)
        }
        walk(try app.snapshot())
        return nodes
    }

    /// The comparison rows: buttons whose name carries both ranks.
    private func rows(_ nodes: [Node]) -> [Node] {
        nodes.filter { $0.type == .button && $0.label.contains(", you rank ") }
    }

    /// The category "View All" buttons.
    private func viewAlls(_ nodes: [Node]) -> [Node] {
        nodes.filter {
            $0.identifier.hasPrefix("fst.rival-detail.category.") && $0.identifier.hasSuffix(".view-all")
        }
    }

    /// Wait until the rebuilt comparison shows its first row and has settled: the cards
    /// stagger in (`load-transition`), and on the CI runner a row that already exists can
    /// still be fading in, not yet hittable, with its card's frames still moving.
    @MainActor
    private func waitForRows(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) throws {
        let first = app.buttons[Self.firstRow].firstMatch
        XCTAssertTrue(
            first.waitForExistence(timeout: FestivalApp.budget(30)),
            "the frozen detail was not rebuilt from /rivals/all", file: file, line: line
        )
        XCTAssertTrue(
            waitUntilHittable(first, timeout: FestivalApp.budget(10)), "the first row never took a tap", file: file, line: line
        )
        // Settled once two snapshots in a row agree on every row and View All frame.
        var previous = ""
        for _ in 0..<10 {
            let nodes = try readingOrder(app)
            let signature = (rows(nodes) + viewAlls(nodes)).map { "\($0.label)\($0.frame)" }.joined()
            if signature == previous { return }
            previous = signature
            Thread.sleep(forTimeInterval: FestivalApp.budget(0.25))
        }
        XCTFail("the rows never settled", file: file, line: line)
    }

    /// Wait until `element` exists and takes a tap (`SongDetailJourneyTests`' `waitHittable`).
    ///
    /// - Parameters:
    ///   - element: The element to wait for.
    ///   - timeout: The wait's budget.
    /// - Returns: Whether it became hittable in time.
    @MainActor
    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let hittable = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND isHittable == true"), object: element
        )
        return XCTWaiter().wait(for: [hittable], timeout: timeout) == .completed
    }

    /// Attach a named screenshot that the result bundle keeps.
    @MainActor
    private func record(_ app: XCUIApplication, name: String) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Audit evidence

    /// One static text on screen, and whether it belongs to the bars (navigation bar, tab
    /// bar, page tools) rather than the scrolling page.
    private struct ScreenText {
        let identifier: String
        let label: String
        let frame: CGRect
        let chrome: Bool
    }

    /// Every static text the tree holds (inside buttons too), once each, and the clear band
    /// between the bars where page text is drawn without their scroll-edge dimming.
    ///
    /// - Parameter app: The app on the audited page.
    /// - Returns: The texts and the band's top and bottom, in window points.
    @MainActor
    private func screenTexts(_ app: XCUIApplication) throws -> (texts: [ScreenText], top: CGFloat, bottom: CGFloat) {
        let window = app.windows.firstMatch.frame
        var top = window.minY, bottom = window.maxY
        var seen: Set<String> = []
        var texts: [ScreenText] = []
        func walk(_ node: any XCUIElementSnapshot, inChrome: Bool) {
            let isChrome = [.navigationBar, .tabBar].contains(node.elementType) || node.identifier == "fst.page-tools"
            // On iPad the tab bar moves to the top and its element can span the whole window
            // or none of it; only a real strip bounds the clear band.
            let isStrip = !node.frame.isEmpty && node.frame.height < window.height / 3
            if isChrome, isStrip {
                if node.frame.midY < window.midY { top = max(top, node.frame.maxY) } else { bottom = min(bottom, node.frame.minY) }
            }
            if node.elementType == .staticText, !node.label.isEmpty, seen.insert("\(node.label)|\(node.frame)").inserted {
                texts.append(ScreenText(identifier: node.identifier, label: node.label, frame: node.frame, chrome: inChrome || isChrome))
            }
            node.children.forEach { walk($0, inChrome: inChrome || isChrome) }
        }
        walk(try app.snapshot(), inChrome: false)
        return (texts, top, bottom)
    }

    /// Rendered contrast of one frame in a screenshot (`SongsUITestSupport.measuredTextContrast`:
    /// median pixel = surface, 99th percentile = glyphs), or nil without 100 glyph pixels.
    @MainActor
    private func renderedContrast(of frame: CGRect, in image: CGImage, window: CGRect) throws -> Double? {
        let visible = frame.intersection(window)
        guard !visible.isEmpty else { return nil }
        let scaleX = Double(image.width) / window.width
        let scaleY = Double(image.height) / window.height
        let cropRect = CGRect(
            x: (visible.minX - window.minX) * scaleX, y: (visible.minY - window.minY) * scaleY,
            width: visible.width * scaleX, height: visible.height * scaleY
        ).integral
        guard let crop = image.cropping(to: cropRect) else { return nil }
        let measured = try SongsUITestSupport.measuredTextContrast(in: SongsUITestSupport.bitmapPixels(crop))
        // A single 6-pt digit on a 2x iPad covers far fewer than 100 pixels, so the minimum
        // glyph coverage scales with the crop instead of being a fixed count.
        let minimumGlyph = max(24, crop.width * crop.height / 50)
        return measured.brightPixels >= minimumGlyph ? measured.ratio : nil
    }

    /// `unattributed-contrast-page-floor`: every static text renders at least 4.5:1. The bars'
    /// own texts are measured in place; page texts are measured in the clear band, scrolling
    /// the page by half the band until it stops, so each passes through it. A page text still
    /// under a bar at the end is reported unmeasured.
    ///
    /// - Parameter app: The audited app, at the top of its page.
    /// - Returns: Texts below 4.5:1 or never measured; empty when the floor holds.
    @MainActor
    private func pageContrastFloor(_ app: XCUIApplication) throws -> [String] {
        let window = app.windows.firstMatch.frame
        var problems: [String] = []
        var measured = 0
        var previous = ""
        for step in 0..<24 {
            let image = try XCTUnwrap(app.screenshot().image.cgImage)
            let (texts, top, bottom) = try screenTexts(app)
            let signature = texts.map { "\($0.label)\($0.frame)" }.joined()
            let atEnd = signature == previous
            for text in texts where text.frame.intersects(window) {
                let clear = text.chrome ? step == 0 : (text.frame.minY >= top - 0.5 && text.frame.maxY <= bottom + 0.5)
                if clear {
                    let ratio = try renderedContrast(of: text.frame, in: image, window: window)
                    if (ratio ?? 0) < 4.5 {
                        problems.append("'\(text.label)' \(text.frame) rendered \(ratio.map { String(format: "%.2f", $0) } ?? "unmeasured")")
                    }
                    measured += 1
                } else if atEnd, !text.chrome, text.frame.maxY > bottom + 0.5 {
                    problems.append("'\(text.label)' \(text.frame) stays under the bars, unmeasured")
                }
            }
            if atEnd { break }
            previous = signature
            // 40 pt inside the band: with no bottom bar (iPad) the band reaches the window edge,
            // where an upward drag is the system's home gesture.
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: window.midX, dy: bottom - 40))
            let finish = start.withOffset(CGVector(dx: 0, dy: -(bottom - top - 40) / 2))
            start.press(forDuration: 0.05, thenDragTo: finish, withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        if measured == 0 { problems.append("no text to measure") }
        return problems
    }

    /// Run `performAccessibilityAudit` with the iPad lane's per-issue evidence rules
    /// (testing/apple/accessibility.md#ipad-audit-waivers), proved in this run:
    /// - contrast on an element in the clear band between the bars (`contrast-rendered`): its
    ///   text renders ≥ 4.5:1 in the screenshot taken before the audit (the audit misjudges
    ///   light text on the page's gradient backdrop);
    /// - contrast without an element, or on page text under a bar's scroll-edge dimming
    ///   (`unattributed-contrast-page-floor`): every static text of the page renders ≥ 4.5:1
    ///   once scrolled into the clear band (`pageContrastFloor`);
    /// - "partially unsupported" Dynamic Type on an element (`dynamic-type-grows`): the same
    ///   text is ≥ 1.35× taller at AX5 than at the default size, measured against
    ///   `baseline` (this audit is at AX5) or, for a default-size audit, returned as a
    ///   pending `Growth` that `resolveGrowth` checks on the test's own AX5 launch (no
    ///   extra launch: each one costs minutes on the CI runner).
    /// Every accepted issue is attached with its measurement; anything else fails.
    ///
    /// - Parameters:
    ///   - app: The app on the audited page.
    ///   - types: The audit types to run.
    ///   - baseline: Text heights at the default size (`textHeights`), for an AX5 audit;
    ///     nil for a default-size audit.
    /// - Returns: Dynamic Type and clipping flags of a default-size audit, still to grow at AX5.
    /// - Throws: An unaccepted audit issue or a missing screenshot.
    @MainActor
    @discardableResult
    private func audit(
        _ app: XCUIApplication, for types: XCUIAccessibilityAuditType, baseline: [String: CGFloat]? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) throws -> [Growth] {
        let image = try XCTUnwrap(app.screenshot().image.cgImage)
        let window = app.windows.firstMatch.frame
        let band = try screenTexts(app)
        var evidence: [String] = []
        var open: [String] = []
        var unattributedContrast = 0
        var pending: [Growth] = []
        try app.performAccessibilityAudit(for: types) { issue in
            let element = issue.element
            let summary = "\(issue.compactDescription): '\(element?.label ?? "")' \(element?.frame ?? .zero)"
            switch (issue.auditType, element) {
            case (.contrast, nil):
                unattributedContrast += 1
                return true
            case (.contrast, let element?) where element.frame.minY < band.top - 0.5 || element.frame.maxY > band.bottom + 0.5:
                // Under a bar its pixels are the bar's dimming, not the text's: the floor scrolls it clear.
                unattributedContrast += 1
                evidence.append("under a bar, measured by the page floor: \(summary)")
                return true
            case (.contrast, let element?):
                let ratio = try self.renderedContrast(of: element.frame, in: image, window: window)
                guard let ratio, ratio >= 4.5 else {
                    open.append("\(summary), rendered \(ratio.map { String(format: "%.2f", $0) } ?? "unmeasured")")
                    return true
                }
                evidence.append("contrast-rendered: \(summary), rendered \(String(format: "%.2f", ratio)):1")
                return true
            case (.textClipped, let element?), (.dynamicType, let element?):
                var summary = summary
                if issue.auditType == .textClipped {
                    // `text-clipped-whole`: the flagged text is drawn whole in this capture (read
                    // back, no ellipsis) and still grows at AX5, like a Dynamic Type flag.
                    let drawn = self.recognizedText(in: element.frame, image: image, window: window)
                    guard Self.showsWhole(element.label, in: drawn) else {
                        open.append("\(summary), drawn '\(drawn ?? "")'")
                        return true
                    }
                    summary += ", drawn '\(drawn ?? "")'"
                }
                let rule = issue.auditType == .textClipped ? "text-clipped-whole" : "dynamic-type-grows"
                guard let baseline else {
                    pending.append(Growth(
                        key: element.identifier.isEmpty ? element.label : element.identifier,
                        height: element.frame.height, summary: summary, rule: rule
                    ))
                    return true
                }
                let regular = baseline[element.identifier] ?? baseline[element.label]
                guard let regular, element.frame.height >= regular * 1.35 else {
                    open.append("\(summary), default height \(regular.map { "\($0)" } ?? "unknown")")
                    return true
                }
                evidence.append("\(rule): \(summary), \(regular) → \(element.frame.height) pt")
                return true
            default:
                open.append(summary)
                return true
            }
        }
        if unattributedContrast > 0 {
            let floor = try pageContrastFloor(app)
            open += floor.map { "unattributed contrast (\(unattributedContrast)): \($0)" }
            if floor.isEmpty { evidence.append("unattributed-contrast-page-floor: \(unattributedContrast) flags, every text ≥ 4.5:1") }
        }
        attach(evidence, name: "audit-evidence")
        XCTAssertEqual(open, [], "open audit issues", file: file, line: line)
        return pending
    }

    /// A default-size Dynamic Type or clipping flag, accepted once the same text is ≥ 1.35×
    /// taller at AX5.
    private struct Growth {
        let key: String
        let height: CGFloat
        let summary: String
        let rule: String
    }

    /// Check a default-size audit's pending flags against the AX5 launch's text heights.
    ///
    /// - Parameters:
    ///   - pending: The flags `audit` returned at the default size.
    ///   - large: `textHeights` of the same page at AX5, at the top of the page.
    @MainActor
    private func resolveGrowth(
        _ pending: [Growth], at large: [String: CGFloat], file: StaticString = #filePath, line: UInt = #line
    ) {
        guard !pending.isEmpty else { return }
        var evidence: [String] = []
        var open: [String] = []
        for text in pending {
            guard let height = large[text.key], height >= text.height * 1.35 else {
                open.append("\(text.summary), AX5 height \(large[text.key].map { "\($0)" } ?? "unknown")")
                continue
            }
            evidence.append("\(text.rule): \(text.summary) → \(height) pt at AX5")
        }
        attach(evidence, name: "audit-evidence-ax5-growth")
        XCTAssertEqual(open, [], "default-size audit issues that do not grow at AX5", file: file, line: line)
    }

    /// Keep audit evidence lines in the result bundle.
    private func attach(_ evidence: [String], name: String) {
        let note = XCTAttachment(string: evidence.joined(separator: "\n"))
        note.name = name
        note.lifetime = .keepAlways
        add(note)
    }

    /// Text Vision reads inside `frame` of a capture (padded by a few points), lines joined
    /// by spaces, or nil when the frame is off the capture.
    @MainActor
    private func recognizedText(in frame: CGRect, image: CGImage, window: CGRect) -> String? {
        let padded = frame.insetBy(dx: -4, dy: -3).intersection(window)
        guard !padded.isNull, padded.width >= 4, padded.height >= 4 else { return nil }
        let scaleX = Double(image.width) / window.width
        let scaleY = Double(image.height) / window.height
        let rect = CGRect(
            x: (padded.minX - window.minX) * scaleX, y: (padded.minY - window.minY) * scaleY,
            width: padded.width * scaleX, height: padded.height * scaleY
        ).integral
        guard let crop = image.cropping(to: rect) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        guard (try? VNImageRequestHandler(cgImage: crop, options: [:]).perform([request])) != nil else { return nil }
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    /// Whether recognized text shows the whole label without an ellipsis: lowercased letters
    /// and digits only, one recognition error per ten characters (at least one) tolerated
    /// (`IPadAuditTextEvidence.showsWhole`'s rule).
    ///
    /// - Parameters:
    ///   - label: The element's label (its full text).
    ///   - recognized: Text read back from the capture.
    /// - Returns: True when the label is drawn in full.
    static func showsWhole(_ label: String, in recognized: String?) -> Bool {
        guard let recognized, !recognized.contains("…"), !recognized.contains("...") else { return false }
        func letters(_ text: String) -> [Character] { Array(text.lowercased().filter { $0.isLetter || $0.isNumber }) }
        let wanted = letters(label), seen = letters(recognized)
        guard !wanted.isEmpty else { return false }
        // Sellers' approximate substring match: the fewest edits to find `wanted` anywhere in `seen`.
        var previous = Array(0...wanted.count)
        var best = wanted.count
        for character in seen {
            var current = [0]
            for (index, target) in wanted.enumerated() {
                current.append(min(previous[index + 1] + 1, current[index] + 1, previous[index] + (character == target ? 0 : 1)))
            }
            best = min(best, current[wanted.count])
            previous = current
        }
        return best <= max(1, wanted.count / 10)
    }

    /// Text heights by identifier, or by label without one (the smallest of repeats), for
    /// `audit`'s Dynamic Type baseline; the countdown's label changes every second.
    @MainActor
    private func textHeights(_ app: XCUIApplication) throws -> [String: CGFloat] {
        try screenTexts(app).texts.reduce(into: [:]) { heights, text in
            let key = text.identifier.isEmpty ? text.label : text.identifier
            heights[key] = min(heights[key] ?? .infinity, text.frame.height)
        }
    }

    // MARK: - Rebuilt comparison

    /// Default text size: the rebuilt comparison reads like a normal one. Every song row is
    /// one button naming its song, instrument and both ranks (no separate instrument image,
    /// no leftover spinner or error); each card reads title → rows → "View All, <title>";
    /// rows and View All are at least 44 pt, inside the window and hittable; the page
    /// passes the full system audit. Then the largest accessibility size: rows keep their
    /// full names, grow with their text (the rank comparison stacks one part per line),
    /// stay inside the window and 44 pt; the page passes the Dynamic Type, clipping and
    /// hit-region audits. One launch per size (each costs minutes on the CI runner).
    @MainActor
    func testFrozenRivalDetailNamesOrdersSizesAndGrowsItsRows() throws {
        continueAfterFailure = false
        let app = launch(player: "fixture-riv-frozen")
        try waitForRows(app)
        let baseline = try textHeights(app)
        let regularHeight = app.buttons[Self.firstRow].firstMatch.frame.height
        let window = app.windows.firstMatch.frame
        let nodes = try readingOrder(app)

        XCTAssertFalse(nodes.contains { $0.label == "Loading rival detail" }, "no spinner left")
        XCTAssertFalse(nodes.contains { $0.identifier.hasPrefix("fst.service-status") }, "no error state")
        let found = rows(nodes)
        XCTAssertEqual(Set(found.map(\.label)), Self.rowNames, "rows named with their instrument")
        XCTAssertFalse(
            nodes.contains { $0.type == .image && ["Lead", "Bass"].contains($0.label) },
            "the instrument icon belongs to its row, not a separate stop"
        )
        XCTAssertFalse(
            nodes.contains { $0.type != .button && Self.rowNames.contains($0.label) },
            "each row is one stop"
        )

        // Reading order: each card's title, then its rows, then its View All; cards top to bottom.
        let links = viewAlls(nodes)
        XCTAssertFalse(links.isEmpty, "every card ends with View All")
        var cardStart = 0
        var previousTop = -CGFloat.infinity
        for link in links {
            XCTAssertTrue(link.label.hasPrefix("View All, "), "View All names its card: \(link.label)")
            let title = String(link.label.dropFirst("View All, ".count))
            let linkIndex = try XCTUnwrap(nodes.firstIndex { $0.identifier == link.identifier })
            let titleIndex = try XCTUnwrap(
                nodes[cardStart..<linkIndex].firstIndex { $0.type == .staticText && $0.label == title },
                "\(title) reads before its rows and View All"
            )
            let cardRows = rows(Array(nodes[titleIndex..<linkIndex]))
            XCTAssertFalse(cardRows.isEmpty, "\(title): rows between its title and View All")
            XCTAssertEqual(
                Set(cardRows.map(\.label)).count, cardRows.count, "\(title): each row reads once: \(cardRows.map(\.label))"
            )
            let titleFrame = nodes[titleIndex].frame
            XCTAssertGreaterThan(titleFrame.minY, previousTop, "\(title): cards read top to bottom")
            for row in cardRows {
                XCTAssertGreaterThanOrEqual(row.frame.minY, titleFrame.maxY - 0.5, "\(row.label) sits below \(title)")
                XCTAssertLessThanOrEqual(row.frame.maxY, link.frame.minY + 0.5, "\(row.label) sits above View All")
            }
            previousTop = titleFrame.minY
            cardStart = linkIndex + 1
        }
        XCTAssertEqual(
            found.count, links.isEmpty ? 0 : rows(Array(nodes[0..<cardStart])).count, "every row belongs to a card"
        )

        // Target size: 44 pt rows and View All, wholly inside the window.
        for target in found + links {
            XCTAssertGreaterThanOrEqual(target.frame.height, 44 - 0.5, "\(target.label) target height")
            XCTAssertGreaterThanOrEqual(target.frame.width, 44, "\(target.label) target width")
            XCTAssertGreaterThanOrEqual(target.frame.minX, window.minX - 0.5, "\(target.label) inside the window")
            XCTAssertLessThanOrEqual(target.frame.maxX, window.maxX + 0.5, "\(target.label) inside the window")
        }
        XCTAssertTrue(app.buttons[Self.firstRow].firstMatch.isHittable, "the first row takes a tap")

        record(app, name: "rival-detail-frozen-a11y-default")
        let pending = try audit(app, for: .all)
        app.terminate()

        let large = launch(player: "fixture-riv-frozen", contentSize: Self.ax5)
        try waitForRows(large)
        try growsAtTheLargestTextSize(large, regularHeight: regularHeight, baseline: baseline, pending: pending)
    }

    /// The AX5 half of the rows journey, on the page relaunched at AX5.
    ///
    /// - Parameters:
    ///   - app: Rival Detail launched at AX5, its rows shown.
    ///   - regularHeight: The first row's height at the default size.
    ///   - baseline: Text heights at the default size.
    ///   - pending: The default-size audit's flags still to grow.
    @MainActor
    private func growsAtTheLargestTextSize(
        _ app: XCUIApplication, regularHeight: CGFloat, baseline: [String: CGFloat], pending: [Growth]
    ) throws {
        resolveGrowth(pending, at: try textHeights(app))
        let window = app.windows.firstMatch.frame
        let row = app.buttons[Self.firstRow].firstMatch
        XCTAssertGreaterThan(
            row.frame.height, regularHeight * 1.35, "the row grows with its text: \(regularHeight) → \(row.frame.height)"
        )
        XCTAssertGreaterThanOrEqual(row.frame.minX, window.minX - 0.5)
        XCTAssertLessThanOrEqual(row.frame.maxX, window.maxX + 0.5)
        XCTAssertTrue(row.isHittable, "the AX5 row takes a tap")
        let found = rows(try readingOrder(app))
        XCTAssertTrue(Set(found.map(\.label)).isSubset(of: Self.rowNames), "AX5 rows keep their names: \(found.map(\.label))")
        for target in found {
            XCTAssertGreaterThanOrEqual(target.frame.height, 44 - 0.5, "\(target.label) target height")
        }

        record(app, name: "rival-detail-frozen-a11y-ax5")
        try audit(app, for: [.dynamicType, .textClipped, .hitRegion], baseline: baseline)
    }

    // MARK: - No snapshot: auto-retry state

    /// Without `/rivals/all` samples the page keeps the freeze's retry state: heading
    /// "Scores are updating", then the countdown sentence, then a 44 pt "Retry Now", at the
    /// default and the largest text size; the page passes the full audit.
    @MainActor
    func testFrozenRivalDetailWithoutSnapshotOffersRetry() throws {
        continueAfterFailure = false
        var retryHeights: [CGFloat] = []
        var baseline: [String: CGFloat] = [:]
        var pending: [Growth] = []
        for contentSize in [nil, Self.ax5] {
            let app = launch(player: "fixture-riv-503", contentSize: contentSize)
            let title = app.staticTexts["fst.service-status.title"]
            XCTAssertTrue(title.waitForExistence(timeout: FestivalApp.budget(30)), "the retry state shows")
            XCTAssertEqual(title.label, "Scores are updating")
            let countdown = app.staticTexts["fst.service-status.countdown"]
            XCTAssertTrue(countdown.waitForExistence(timeout: FestivalApp.budget(10)), "the freeze counts down")
            XCTAssertTrue(
                countdown.label.hasPrefix("Trying again automatically in "), "countdown reads as a sentence: \(countdown.label)"
            )
            let retry = app.buttons["fst.service-status.retry"]
            XCTAssertTrue(retry.waitForExistence(timeout: FestivalApp.budget(10)))
            let heights = try textHeights(app)
            XCTAssertEqual(retry.label, "Retry Now")
            XCTAssertGreaterThanOrEqual(retry.frame.height, 44 - 0.5, "Retry Now target height")
            XCTAssertGreaterThanOrEqual(retry.frame.width, 44, "Retry Now target width")
            // At AX5 the state is taller than the screen: Retry Now must scroll clear of the bars.
            // At the default size it only has to finish fading in.
            if contentSize == nil { _ = waitUntilHittable(retry, timeout: FestivalApp.budget(5)) }
            for _ in 0..<4 where !retry.isHittable { app.swipeUp() }
            XCTAssertTrue(retry.isHittable, "Retry Now takes a tap")

            let nodes = try readingOrder(app)
            let order = ["fst.service-status.title", "fst.service-status.countdown", "fst.service-status.retry"]
                .compactMap { id in nodes.firstIndex { $0.identifier == id } }
            XCTAssertEqual(order.count, 3)
            XCTAssertEqual(order, order.sorted(), "heading → countdown → Retry Now")
            XCTAssertFalse(nodes.contains { $0.label.contains(", you rank ") }, "no rows without a snapshot")
            retryHeights.append(retry.frame.height)

            record(app, name: "rival-detail-frozen-retry-a11y-\(contentSize == nil ? "default" : "ax5")")
            if contentSize == nil {
                baseline = heights
                pending = try audit(app, for: .all)
            } else {
                resolveGrowth(pending, at: heights)
                try audit(app, for: [.dynamicType, .textClipped, .hitRegion], baseline: baseline)
            }
            app.terminate()
        }
        XCTAssertGreaterThan(retryHeights[1], retryHeights[0], "Retry Now grows with its text: \(retryHeights)")
    }
}
