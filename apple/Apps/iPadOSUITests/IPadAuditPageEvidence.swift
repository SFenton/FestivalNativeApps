import Vision
import XCTest

/// Page-level evidence for audit issues reported **without an element**
/// (`.agents/testing/apple/accessibility.md`, "iPad audit waivers").
///
/// On iPadOS 26.5 the audit names some SwiftUI text nodes ("Contrast failed for
/// SwiftUI.AccessibilityNode") without an `XCUIElement`, so the issue cannot be measured
/// directly. These checks cover every candidate instead:
///
/// - **Contrast floor:** every static text in the audited region is measured in the
///   page's capture (``IPadAuditRenderedContrast``). When the lowest reading is still
///   ≥ 4.5:1, no text the audit could mean fails, so its unattributed contrast verdicts
///   are false. One text below the floor keeps them all open and is listed.
/// - **Text outside the tree:** the capture is read with on-device text recognition; every
///   recognized line inside the audited region must match an element's label, value or
///   placeholder. Over a sheet, the region is the sheet: the page behind it is visible
///   through the dimming but correctly outside the tree while the sheet is modal, which
///   is what "Potentially inaccessible text" without an element reports there.
enum IPadAuditPageEvidence {
    // MARK: - Evidence

    /// What was measured for one page.
    struct Evidence: Codable, Equatable {
        /// The audited region (the sheet over a sheet page, else the app window).
        var region: String
        /// True when the region is a presented sheet.
        var isSheet: Bool
        /// Static texts measured (on screen, or scrolled clear of the bars).
        var textsMeasured = 0
        /// Static texts partly under the bars or the screen edge that could not be scrolled
        /// clear and measured.
        var textsUnmeasured = 0
        /// Lowest rendered contrast among them.
        var contrastFloor: Double?
        /// Texts below 4.5:1 (label and reading), if any.
        var belowFloor: [String] = []
        /// Recognized lines inside the region that match no element.
        var textOutsideTree: [String] = []
        /// Recognized lines inside the region.
        var linesRecognized = 0
        /// Static texts compared between the default size and AX5 (growth).
        var growthChecked = 0
        /// Texts less than 1.35× taller at AX5, or not found there.
        var notGrowing: [String] = []
        /// Static texts read back at AX5.
        var wholeChecked = 0
        /// Texts not read back whole at AX5.
        var notWhole: [String] = []

        /// Record one contrast reading.
        mutating func add(label: String, ratio: Double) {
            textsMeasured += 1
            contrastFloor = min(contrastFloor ?? ratio, ratio)
            if ratio < 4.5 { belowFloor.append("\(label.prefix(40)) \(ratio)") }
        }
    }

    /// A page measurement plus the texts still to measure by scrolling, and every visible
    /// text (for the Dynamic Type comparison).
    struct Visible {
        var evidence: Evidence
        /// Texts partly hidden by the bars or the screen edge (scroll them clear).
        var obscured: [IPadAuditTextEvidence.Locator]
        /// Visible static texts with their frames at the audited size.
        var texts: [(locator: IPadAuditTextEvidence.Locator, frame: CGRect)]
    }

    // MARK: - Measuring

    /// Measure what is on screen.
    ///
    /// - Parameters:
    ///   - app: The running app, settled on the audited page.
    ///   - capture: The page's full-screen capture.
    ///   - lines: Text recognized in the capture (``recognizedLines(in:)``).
    ///   - content: The part of the window not covered by bottom bars.
    ///   - sheetProof: An element identifier inside the presented sheet, for sheet pages.
    ///   - systemRegions: System decorations covered by their own waivers (the toolbar
    ///     badge), left out of the contrast floor.
    /// - Returns: The evidence and the texts still to measure.
    @MainActor
    static func measure(
        _ app: XCUIApplication, capture: IPadAuditRenderedContrast.Capture, lines: [Line], content: ContentArea,
        sheetProof: String?, systemRegions: [CGRect] = []
    ) -> Visible? {
        guard let root = try? app.snapshot() else { return nil }
        let window = app.windows.firstMatch.frame
        let sheet = sheetProof.flatMap { sheetFrame(around: $0, in: root, window: window) }
        let region = sheet ?? window
        let nodes = flatten(root)
        var visible = Visible(
            evidence: Evidence(region: NSCoder.string(for: region), isSheet: sheetProof != nil),
            obscured: [], texts: []
        )

        // Contrast floor over every static text in the region; texts the bars or the
        // screen edge cut are measured later, scrolled clear.
        let texts = nodes.filter { $0.elementType == .staticText && !$0.label.isEmpty }
        for node in texts {
            let frame = node.frame
            let centre = CGPoint(x: frame.midX, y: frame.midY)
            guard frame.width >= 4, frame.height >= 8, region.intersects(frame), window.intersects(frame),
                  !systemRegions.contains(where: { $0.contains(centre) }) else { continue }
            let locator = IPadAuditTextEvidence.Locator.make(node, among: texts)
            guard content.contains(frame) else {
                visible.obscured.append(locator)
                continue
            }
            visible.texts.append((locator, frame))
            guard let measurement = reading(for: frame, label: node.label, lines: lines, capture: capture),
                  measurement.glyphPixels >= 40 else { continue }
            visible.evidence.add(label: node.label, ratio: measurement.ratio)
        }

        // Recognized text inside the region that no element names.
        let names = nodes.flatMap { node -> [String] in
            [node.label, (node.value as? String) ?? "", node.placeholderValue ?? "", node.title]
        }.map(IPadAuditTextEvidence.normalized).filter { !$0.isEmpty }
        let inside = lines.filter { region.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        visible.evidence.linesRecognized = inside.count
        visible.evidence.textOutsideTree = inside.filter { line in
            let seen = IPadAuditTextEvidence.normalized(line.text)
            guard seen.count >= 3 else { return false } // glyphs and single symbols
            return !names.contains { name in
                IPadAuditTextEvidence.approximateSubstringDistance(seen, in: name) <= max(1, seen.count / 8)
                    || IPadAuditTextEvidence.approximateSubstringDistance(name, in: seen) <= max(1, name.count / 8)
            }
        }.map { String($0.text.prefix(60)) }
        return visible
    }

    /// Every static text wholly inside `content`, read back from `capture`: the labels
    /// not shown whole.
    ///
    /// - Returns: Checked count and the labels not read back whole.
    @MainActor
    static func notWhole(
        in app: XCUIApplication, capture: IPadAuditRenderedContrast.Capture, content: ContentArea
    ) -> (checked: Int, failing: [String]) {
        guard let root = try? app.snapshot() else { return (0, []) }
        var checked = 0
        var failing: [String] = []
        // Leaf texts only: a combined element's label also carries text that is spoken but
        // not drawn (a Songs row's per-instrument status), so its children are read instead.
        // Navigation-bar titles are UIKit's (a large title truncates by design) and are
        // reported apart.
        func walk(_ node: XCUIElementSnapshot, inBar: Bool) {
            let bar = inBar || node.elementType == .navigationBar
            if node.elementType == .staticText, !node.label.isEmpty, content.contains(node.frame),
               node.frame.height >= 8, !node.children.contains(where: { $0.elementType == .staticText }) {
                checked += 1
                let seen = IPadAuditTextEvidence.recognizedText(in: node.frame, capture: capture)
                if !IPadAuditTextEvidence.readsUntruncated(node.label, in: seen) {
                    failing.append((bar ? "[system bar] " : "") + "\(node.label.prefix(40)) → \((seen ?? "").prefix(40))")
                }
            }
            node.children.forEach { walk($0, inBar: bar) }
        }
        walk(root, inBar: false)
        return (checked, failing)
    }

    /// Depth-first nodes of a snapshot.
    @MainActor
    static func flatten(_ root: XCUIElementSnapshot) -> [XCUIElementSnapshot] {
        var nodes: [XCUIElementSnapshot] = []
        func walk(_ node: XCUIElementSnapshot) {
            nodes.append(node)
            node.children.forEach(walk)
        }
        walk(root)
        return nodes
    }

    /// Where page text can be measured: the window minus the bars over its bottom (tab
    /// bar, floating page tools), and, per column, below each top navigation bar and above
    /// each pager's scroll-edge fade. A split has a bar and edges per pane: Song Detail's
    /// card header scrolled under the leading bar read 1.84:1 and the board's last rows
    /// under its pager fade 2.6–3.7:1 (Lane A11Y3); text there is scrolled clear first.
    struct ContentArea {
        /// The window minus the bottom bars.
        let rect: CGRect
        /// Top navigation bars (their own titles and buttons count as clear).
        var topBars: [CGRect] = []
        /// Frames of elements inside the top bars.
        var barElements: Set<String> = []
        /// Pagers at the bottom of a pane.
        var pagers: [CGRect] = []

        /// Scroll-edge fade under a top bar, and above a pager.
        static let topFade: CGFloat = 8
        static let pagerFade: CGFloat = 44

        private func overlapsColumn(_ bar: CGRect, _ frame: CGRect) -> Bool {
            bar.minX < frame.maxX && frame.minX < bar.maxX
        }

        /// The effective top edge for an element's column.
        func top(for frame: CGRect) -> CGFloat {
            topBars.filter { overlapsColumn($0, frame) }.map { $0.maxY + Self.topFade }.max()
                .map { max($0, rect.minY) } ?? rect.minY
        }

        /// The effective bottom edge for an element's column.
        func bottom(for frame: CGRect) -> CGFloat {
            pagers.filter { overlapsColumn($0, frame) }.map { $0.minY - Self.pagerFade }.min()
                .map { min($0, rect.maxY) } ?? rect.maxY
        }

        /// Whether `frame` is wholly where it can be measured (a bar's own element is).
        func contains(_ frame: CGRect) -> Bool {
            guard rect.contains(frame) else { return false }
            if barElements.contains(NSCoder.string(for: frame)) { return true }
            return frame.minY >= top(for: frame) && frame.maxY <= bottom(for: frame)
        }
    }

    /// The page's ``ContentArea``.
    @MainActor
    static func contentRect(_ app: XCUIApplication) -> ContentArea {
        let window = app.windows.firstMatch.frame
        var bottom = window.maxY
        // Only bars on screen: a sheet covering the tab bar leaves it in the tree but not hittable.
        for element in [app.tabBars.firstMatch, app.descendants(matching: .any)["fst.page-tools"]]
            where element.exists && element.isHittable {
            let frame = element.frame
            if frame.minY > window.midY { bottom = min(bottom, frame.minY) }
        }
        var area = ContentArea(rect: CGRect(x: window.minX, y: window.minY, width: window.width, height: bottom - window.minY))
        guard let root = try? app.snapshot() else { return area }
        func walk(_ node: XCUIElementSnapshot, inBar: Bool) {
            let isBar = node.elementType == .navigationBar && node.frame.maxY < window.midY && node.frame.height > 0
            if isBar { area.topBars.append(node.frame) }
            if inBar || isBar { area.barElements.insert(NSCoder.string(for: node.frame)) }
            if node.identifier.hasSuffix(".pager"), node.frame.minY > window.midY { area.pagers.append(node.frame) }
            node.children.forEach { walk($0, inBar: inBar || isBar) }
        }
        walk(root, inBar: false)
        return area
    }

    /// The presented sheet: the largest ancestor of `proof` smaller than the window.
    @MainActor
    static func sheetFrame(around proof: String, in root: XCUIElementSnapshot, window: CGRect) -> CGRect? {
        var path: [XCUIElementSnapshot] = []
        func find(_ node: XCUIElementSnapshot, _ trail: [XCUIElementSnapshot]) -> Bool {
            if node.identifier == proof { path = trail; return true }
            return node.children.contains { find($0, trail + [node]) }
        }
        guard find(root, []) else { return nil }
        let limit = window.width * window.height * 0.9
        return path.map { $0.frame }
            .filter { $0.width * $0.height < limit && window.intersects($0) && $0.width > 200 }
            .max { $0.width * $0.height < $1.width * $1.height }
    }

    /// One recognized line of text, its frame and its words' frames, in screen points.
    struct Line {
        let text: String
        let frame: CGRect
        let words: [(text: String, frame: CGRect)]
    }

    /// Rendered contrast of the text inside `frame`.
    ///
    /// Each recognized word whose centre lies in the frame is measured on its own tight
    /// box (2 pt of surface around it), and the weakest word is the reading; when the
    /// element has a label, only words of that label count. Element
    /// frames and whole lines mislead: a selected sidebar row's blue symbol read the
    /// row's white text at 3.8:1 instead of 13.4:1, and one recognized line can span two
    /// adjacent pills of different colours. Single-character words are left out when
    /// longer words are present (symbols recognized as "Q" or "Ó"). Without a recognized
    /// word the whole frame is measured.
    ///
    /// - Parameters:
    ///   - frame: Element frame in screen points.
    ///   - label: The element's label, when known.
    ///   - lines: Recognized lines of the same capture.
    ///   - capture: The capture.
    /// - Returns: The reading, or nil when nothing measurable is inside the frame.
    static func reading(
        for frame: CGRect, label: String = "", lines: [Line], capture: IPadAuditRenderedContrast.Capture
    ) -> IPadAuditRenderedContrast.Measurement? {
        let bounds = frame.insetBy(dx: -2, dy: -2)
        let inside = lines.flatMap(\.words).filter { bounds.contains(CGPoint(x: $0.frame.midX, y: $0.frame.midY)) }
        let alphanumerics: (String) -> Int = { $0.filter { $0.isLetter || $0.isNumber }.count }
        var words = inside.contains { alphanumerics($0.text) >= 2 } ? inside.filter { alphanumerics($0.text) >= 2 } : inside
        // Words of the element's own label: a symbol recognized as letters ("ooo" for
        // chart bars) is not the text being judged.
        let wanted = IPadAuditTextEvidence.normalized(label)
        let ofLabel = words.filter { word in
            let seen = IPadAuditTextEvidence.normalized(word.text)
            return !seen.isEmpty && IPadAuditTextEvidence.approximateSubstringDistance(seen, in: wanted) <= max(1, seen.count / 4)
        }
        if !wanted.isEmpty, !ofLabel.isEmpty { words = ofLabel }
        let readings = words.compactMap { IPadAuditRenderedContrast.measure($0.frame.insetBy(dx: -2, dy: -2), in: capture) }
        guard let weakest = readings.min(by: { $0.ratio < $1.ratio }) else {
            return IPadAuditRenderedContrast.measure(frame, in: capture)
        }
        return IPadAuditRenderedContrast.Measurement(
            ratio: weakest.ratio, glyphPixels: readings.reduce(0) { $0 + $1.glyphPixels }
        )
    }

    /// Height of the drawn text inside `frame`: the tallest recognized word of the label.
    ///
    /// Growth measured on glyphs, not frames: a 44 pt minimum row height kept a sidebar
    /// row's frame the same at AX1 while its text grew 1.65×.
    ///
    /// - Returns: The height in points, or nil when no word of the label is recognized.
    static func textHeight(in frame: CGRect, label: String, lines: [Line]) -> CGFloat? {
        let bounds = frame.insetBy(dx: -2, dy: -2)
        let wanted = IPadAuditTextEvidence.normalized(label)
        let words = lines.flatMap(\.words).filter { word in
            guard bounds.contains(CGPoint(x: word.frame.midX, y: word.frame.midY)) else { return false }
            let seen = IPadAuditTextEvidence.normalized(word.text)
            return seen.count >= 2
                && IPadAuditTextEvidence.approximateSubstringDistance(seen, in: wanted) <= max(1, seen.count / 4)
        }
        return words.map(\.frame.height).max()
    }

    /// Recognized text lines (and their words) with frames in screen points.
    static func recognizedLines(in capture: IPadAuditRenderedContrast.Capture) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: capture.image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        func screenRect(_ box: CGRect) -> CGRect { // normalized, origin bottom-left
            CGRect(x: box.minX * capture.screen.width, y: (1 - box.maxY) * capture.screen.height,
                   width: box.width * capture.screen.width, height: box.height * capture.screen.height)
        }
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            var words: [(text: String, frame: CGRect)] = []
            var start: String.Index?
            for index in text.indices + [text.endIndex] {
                let isSpace = index == text.endIndex || text[index].isWhitespace
                if !isSpace, start == nil { start = index }
                if isSpace, let begin = start {
                    if let box = try? candidate.boundingBox(for: begin..<index)?.boundingBox {
                        words.append((String(text[begin..<index]), screenRect(box)))
                    }
                    start = nil
                }
            }
            return Line(text: text, frame: screenRect(observation.boundingBox), words: words)
        }
    }
}
