import XCTest

// MARK: - Evidence collection for one audited page

extension IPadAccessibilityAuditTests {
    /// Measure everything the waivers need for one audited page, then terminate `app`
    /// (`.agents/testing/apple/accessibility.md`, "iPad audit waivers").
    ///
    /// In order, while the page is as audited: the capture and element tree are written;
    /// contrast issues on visible elements are measured (``IPadAuditPageEvidence/reading(for:lines:capture:)``);
    /// for issues without an element the page evidence is measured; every element still
    /// to find again is located. Then elements the bars or the screen edge cut are
    /// scrolled clear and measured. Last, the page is launched again at AX5 (or at the
    /// default size when the audit ran at AX5) for growth and AX5 read-back.
    ///
    /// - Parameters:
    ///   - findings: The page's findings (updated in place).
    ///   - types: Each finding's audit type.
    ///   - page: The page.
    ///   - mode: The audit mode.
    ///   - app: The running app, as audited.
    ///   - proof: The identifier that proved the page.
    /// - Returns: Frames of ``IPadAuditWaivers/containerIdentifiers`` on the page.
    @MainActor
    func collectEvidence(
        _ findings: inout [Finding], types: [XCUIAccessibilityAuditType], page: Page, mode: Mode,
        app: XCUIApplication, proof: String
    ) throws -> [String: CGRect] {
        let name = "\(mode.rawValue)-\(page.name)"
        let capture = IPadAuditRenderedContrast.Capture.screen()
        write(capture, tree: app, name: name)
        var containers: [String: CGRect] = [:]
        for id in IPadAuditWaivers.containerIdentifiers {
            let element = Self.anyElement(app, id)
            if element.exists { containers[id] = element.frame }
        }
        // The system keyboard plus its QuickType bar ("Typing Predictions", drawn just
        // above the keyboard's own frame).
        if app.keyboards.firstMatch.exists {
            var frame = app.keyboards.firstMatch.frame
            let predictions = app.otherElements["Typing Predictions"]
            if predictions.exists { frame = frame.union(predictions.frame) }
            containers[IPadAuditWaivers.keyboardContainer] = frame
        }
        let content = IPadAuditPageEvidence.contentRect(app)
        // The comparison launch is AX5 (the claims are about larger sizes), or the default
        // size when the audit itself ran at AX5.
        let auditedIsAX5 = mode.contentSize == .accessibilityExtraExtraExtraLarge
        let isContrast = { (index: Int) in types[index] == .contrast }
        let isDynamicType = { (index: Int) in types[index] == .dynamicType }
        let isClipped = { (index: Int) in types[index] == .textClipped }
        let frames = findings.map { NSCoder.cgRect(for: $0.frame) }
        let unattributed = findings.indices.filter { findings[$0].frame.isEmpty }

        // 1. Visible contrast issues and page evidence.
        let lines = capture.map(IPadAuditPageEvidence.recognizedLines(in:)) ?? []
        for index in findings.indices where isContrast(index) && !findings[index].frame.isEmpty
            && content.contains(frames[index]) {
            if let capture {
                findings[index].rendered = IPadAuditPageEvidence.reading(
                    for: frames[index], label: findings[index].label, lines: lines, capture: capture
                )
            }
        }
        var visible: IPadAuditPageEvidence.Visible?
        if !unattributed.isEmpty, let capture {
            visible = IPadAuditPageEvidence.measure(
                app, capture: capture, lines: lines, content: content,
                sheetProof: page.sheet ? proof : nil, systemRegions: Array(containers.values)
            )
        }

        // 2. Locate every element to find again, before anything scrolls.
        let heuristic = findings.indices.filter {
            (isDynamicType($0) || isClipped($0)) && !findings[$0].label.isEmpty && !findings[$0].frame.isEmpty
        }
        let cutContrast = findings.indices.filter {
            isContrast($0) && !findings[$0].frame.isEmpty && !content.contains(frames[$0])
        }
        var locators: [Int: IPadAuditTextEvidence.Locator] = [:]
        for index in heuristic + cutContrast {
            let finding = findings[index]
            locators[index] = .make(identifier: finding.identifier, label: finding.label,
                                    elementType: finding.elementType, frame: frames[index], in: app)
        }
        for index in heuristic {
            var evidence = IPadAuditTextEvidence.Evidence()
            if let capture, content.contains(frames[index]) {
                let seen = IPadAuditTextEvidence.recognizedText(in: frames[index], capture: capture)
                evidence.wholeAtAuditedSize = IPadAuditTextEvidence.readsUntruncated(findings[index].label, in: seen)
                if auditedIsAX5 {
                    evidence.wholeAtLargest = evidence.wholeAtAuditedSize
                    evidence.recognizedAtLargest = seen.map { String($0.prefix(80)) }
                }
            }
            findings[index].text = evidence
        }
        let pageClipped = unattributed.contains(where: isClipped)
        let pageDynamicType = unattributed.contains(where: isDynamicType)
        if pageClipped, auditedIsAX5, let capture {
            let (checked, failing) = IPadAuditPageEvidence.notWhole(in: app, capture: capture, content: content)
            visible?.evidence.wholeChecked = checked
            visible?.evidence.notWhole = failing
        }

        // 3. Scroll cut elements clear of the bars and measure them there.
        for index in cutContrast + heuristic.filter({ isClipped($0) && findings[$0].text?.wholeAtAuditedSize == nil }) {
            guard let locator = locators[index], let element = locator.resolve(in: app, within: content) else { continue }
            Thread.sleep(forTimeInterval: 0.6)
            guard let shot = IPadAuditRenderedContrast.Capture.screen() else { continue }
            if isContrast(index) {
                let shotLines = IPadAuditPageEvidence.recognizedLines(in: shot)
                findings[index].rendered = IPadAuditPageEvidence.reading(
                    for: element.frame, label: locator.label, lines: shotLines, capture: shot
                )
            } else {
                let seen = IPadAuditTextEvidence.recognizedText(in: element.frame, capture: shot)
                let whole = IPadAuditTextEvidence.readsUntruncated(locator.label, in: seen)
                findings[index].text?.wholeAtAuditedSize = whole
                if auditedIsAX5 {
                    findings[index].text?.wholeAtLargest = whole
                    findings[index].text?.recognizedAtLargest = seen.map { String($0.prefix(80)) }
                }
            }
        }
        if let obscured = visible?.obscured, unattributed.contains(where: isContrast) {
            for locator in obscured.prefix(16) {
                guard let element = locator.resolve(in: app, within: content),
                      let shot = IPadAuditRenderedContrast.Capture.screen() else {
                    visible?.evidence.textsUnmeasured += 1
                    continue
                }
                let shotLines = IPadAuditPageEvidence.recognizedLines(in: shot)
                if let reading = IPadAuditPageEvidence.reading(
                    for: element.frame, label: locator.label, lines: shotLines, capture: shot
                ),
                   reading.glyphPixels >= 40 {
                    visible?.evidence.add(label: locator.label, ratio: reading.ratio)
                } else {
                    visible?.evidence.textsUnmeasured += 1
                }
            }
            visible?.evidence.textsUnmeasured += max(0, obscured.count - 16)
        }
        app.terminate()

        // 4. The other end of the size range.
        if !heuristic.isEmpty || pageDynamicType || (pageClipped && !auditedIsAX5) {
            let comparisonSize: UIContentSizeCategory? = auditedIsAX5 ? nil : .accessibilityExtraExtraExtraLarge
            if let other = try reach(page, mode: mode, contentSize: comparisonSize) {
                defer { other.terminate() }
                let otherContent = IPadAuditPageEvidence.contentRect(other)
                let otherShot = IPadAuditRenderedContrast.Capture.screen()
                write(otherShot, tree: other, name: "\(name)-compare")
                let growth = { (audited: CGFloat, compared: CGFloat) -> Double in
                    ((auditedIsAX5 ? audited / compared : compared / audited) * 100).rounded() / 100
                }
                // Glyph heights from both captures when the label's words are recognized in
                // both; otherwise frame heights (never one of each).
                let otherLines = otherShot.map(IPadAuditPageEvidence.recognizedLines(in:)) ?? []
                let sizeRatio = { (audited: CGRect, compared: CGRect, label: String) -> Double? in
                    if let a = IPadAuditPageEvidence.textHeight(in: audited, label: label, lines: lines),
                       let c = IPadAuditPageEvidence.textHeight(in: compared, label: label, lines: otherLines), a > 0 {
                        return growth(a, c)
                    }
                    guard audited.height > 0, compared.height > 0 else { return nil }
                    return growth(audited.height, compared.height)
                }
                // Page-level: every visible text, compared without scrolling.
                if pageDynamicType, let texts = visible?.texts {
                    for (locator, frame) in texts {
                        let found = locator.matches(in: other)
                        visible?.evidence.growthChecked += 1
                        guard locator.ordinal < found.count,
                              let ratio = sizeRatio(frame, found[locator.ordinal].frame, locator.label), ratio >= 1.35 else {
                            visible?.evidence.notGrowing.append(String(locator.label.prefix(40)))
                            continue
                        }
                    }
                }
                if pageClipped, !auditedIsAX5, let otherShot {
                    let (checked, failing) = IPadAuditPageEvidence.notWhole(in: other, capture: otherShot, content: otherContent)
                    visible?.evidence.wholeChecked = checked
                    visible?.evidence.notWhole = failing
                }
                // Per element: growth without scrolling first (an eager stack reports
                // offscreen frames), then on screen for the AX5 read-back.
                for index in heuristic {
                    guard let locator = locators[index] else { continue }
                    let found = locator.matches(in: other)
                    guard locator.ordinal < found.count else { continue }
                    findings[index].text?.growth = sizeRatio(frames[index], found[locator.ordinal].frame, locator.label)
                }
                for index in heuristic where findings[index].text?.growth == nil
                    || (comparisonSize == .accessibilityExtraExtraExtraLarge && isClipped(index)) {
                    guard let locator = locators[index],
                          let element = locator.resolve(in: other, within: otherContent, fallbackX: frames[index].midX) else {
                        findings[index].text?.missing = "element not found in the comparison launch"
                        continue
                    }
                    if findings[index].text?.growth == nil, frames[index].height > 0, element.frame.height > 0 {
                        findings[index].text?.growth = growth(frames[index].height, element.frame.height)
                    }
                    if comparisonSize == .accessibilityExtraExtraExtraLarge, isClipped(index) {
                        Thread.sleep(forTimeInterval: 0.6)
                        if let large = IPadAuditRenderedContrast.Capture.screen() {
                            let seen = IPadAuditTextEvidence.recognizedText(in: element.frame, capture: large)
                            findings[index].text?.wholeAtLargest = IPadAuditTextEvidence.readsUntruncated(locator.label, in: seen)
                            findings[index].text?.recognizedAtLargest = seen.map { String($0.prefix(80)) }
                        }
                    }
                }
            } else {
                for index in heuristic { findings[index].text?.missing = "comparison launch did not reach the page" }
            }
        }
        for index in unattributed { findings[index].pageEvidence = visible?.evidence }
        return containers
    }
}
