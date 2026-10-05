import Vision
import XCTest

/// Rendered evidence for the audit's Dynamic Type heuristics on iPad
/// (`.agents/testing/apple/accessibility.md`, "iPad audit waivers").
///
/// The audit reports "Dynamic Type font sizes are partially unsupported" and "Text
/// clipped … may be clipped at larger Dynamic Type sizes" from a probe that does not
/// re-run the app's accessibility-size layouts (wrapping marquees, stacked rows). This
/// checks the real app instead: the same element is found again in a launch at the other
/// end of the size range, its frame height compared (growth), and its rendered text read
/// back with on-device text recognition (Vision) from each capture, so a waiver needs the
/// whole label to be visible, not merely an element whose label is complete.
enum IPadAuditTextEvidence {
    // MARK: - Evidence

    /// What was measured for one issue.
    struct Evidence: Codable, Equatable {
        /// Larger-size height ÷ default-size height of the same element.
        var growth: Double?
        /// The whole label was read back from the audited run's capture.
        var wholeAtAuditedSize: Bool?
        /// The whole label was read back from the AX5 capture (audited or comparison).
        var wholeAtLargest: Bool?
        /// Recognized text at the largest size (for the JSON; truncated).
        var recognizedAtLargest: String?
        /// Why evidence is missing, if it is.
        var missing: String?
    }

    // MARK: - Locating the same element

    /// A query for a flagged element: identifier and label when both exist, else label
    /// and element type; `ordinal` picks among repeats in reading order.
    struct Locator: Codable, Equatable {
        let identifier: String
        let label: String
        let elementType: Int
        let ordinal: Int

        /// Matching elements in reading order (top to bottom, leading to trailing).
        @MainActor
        func matches(in app: XCUIApplication) -> [XCUIElement] {
            // Case-insensitive: an uppercased caption (`textCase(.uppercase)`) is exposed
            // as "SONGS PLAYED" at the default size but "Songs Played" at AX5.
            let predicate = identifier.isEmpty
                ? NSPredicate(format: "label ==[c] %@", label)
                : NSPredicate(format: "identifier == %@ AND label ==[c] %@", identifier, label)
            let type = XCUIElement.ElementType(rawValue: UInt(max(0, elementType))) ?? .any
            let query = app.descendants(matching: elementType < 0 ? .any : type).matching(predicate)
            return query.allElementsBoundByIndex
                .filter { $0.exists && !$0.frame.isEmpty }
                .sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
        }

        /// The element at ``ordinal``, scrolled inside `content` (default: the window) if
        /// needed, at most six swipes.
        @MainActor
        func resolve(in app: XCUIApplication, within content: CGRect? = nil) -> XCUIElement? {
            let window = content ?? app.windows.firstMatch.frame
            for _ in 0..<6 {
                let found = matches(in: app)
                if ordinal < found.count {
                    let element = found[ordinal]
                    let frame = element.frame
                    if window.contains(frame) { return element }
                    if frame.minY < window.minY { app.swipeDown() } else { app.swipeUp() }
                } else {
                    app.swipeUp()
                }
                Thread.sleep(forTimeInterval: 0.8)
            }
            return nil
        }

        /// The locator for a snapshot node, its ordinal counted among `nodes` (same tree,
        /// same reading order as ``matches(in:)``) without another query.
        @MainActor
        static func make(_ node: XCUIElementSnapshot, among nodes: [XCUIElementSnapshot]) -> Locator {
            let same = nodes.filter {
                $0.label.caseInsensitiveCompare(node.label) == .orderedSame && $0.elementType == node.elementType
                    && !$0.frame.isEmpty
            }.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
            let ordinal = same.firstIndex { $0.frame == node.frame } ?? 0
            return Locator(identifier: "", label: node.label, elementType: Int(node.elementType.rawValue), ordinal: ordinal)
        }

        /// The locator for `element` as found among its repeats in `app`.
        @MainActor
        static func make(identifier: String, label: String, elementType: Int, frame: CGRect,
                         in app: XCUIApplication) -> Locator {
            let probe = Locator(identifier: identifier, label: label, elementType: elementType, ordinal: 0)
            let ordinal = probe.matches(in: app).firstIndex { $0.frame == frame } ?? 0
            return Locator(identifier: identifier, label: label, elementType: elementType, ordinal: ordinal)
        }
    }

    // MARK: - Text recognition

    /// Recognized text inside `frame` (screen points) of a capture, lines joined by spaces.
    ///
    /// - Parameters:
    ///   - frame: Element frame.
    ///   - capture: Full-screen capture in the interface orientation.
    /// - Returns: The text, or nil when the frame is outside the capture.
    static func recognizedText(in frame: CGRect, capture: IPadAuditRenderedContrast.Capture) -> String? {
        let screen = CGRect(origin: .zero, size: capture.screen)
        let padded = frame.insetBy(dx: -4, dy: -3).intersection(screen)
        guard !padded.isNull, padded.width >= 4, padded.height >= 4 else { return nil }
        let scaleX = Double(capture.width) / capture.screen.width
        let scaleY = Double(capture.height) / capture.screen.height
        let rect = CGRect(x: padded.minX * scaleX, y: padded.minY * scaleY,
                          width: padded.width * scaleX, height: padded.height * scaleY).integral
        guard let crop = capture.image.cropping(to: rect) else { return nil }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        let handler = VNImageRequestHandler(cgImage: crop, options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }
        let observations = (request.results ?? []).sorted {
            ($0.boundingBox.maxY, $1.boundingBox.minX) > ($1.boundingBox.maxY, $0.boundingBox.minX)
        }
        return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }

    /// True when the recognized text shows the whole label and no truncation ellipsis.
    ///
    /// Comparison is on lowercased letters and digits only; one recognition error per ten
    /// characters (at least one) is tolerated anywhere in the label.
    ///
    /// - Parameters:
    ///   - label: The element's accessibility label (its full text).
    ///   - recognized: Text recognized from the rendered element.
    /// - Returns: Whether the label is visible in full.
    static func showsWhole(_ label: String, in recognized: String?) -> Bool {
        guard let recognized, !recognized.contains("…"), !recognized.hasSuffix("...") else { return false }
        let wanted = normalized(label), seen = normalized(recognized)
        guard !wanted.isEmpty else { return false }
        return approximateSubstringDistance(wanted, in: seen) <= max(1, wanted.count / 10)
    }

    /// Lowercased letters and digits.
    static func normalized(_ text: String) -> [Character] {
        Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Smallest edit distance between `pattern` and any substring of `text` (Sellers).
    static func approximateSubstringDistance(_ pattern: [Character], in text: [Character]) -> Int {
        guard !pattern.isEmpty else { return 0 }
        var previous = Array(repeating: 0, count: text.count + 1)
        for (row, character) in pattern.enumerated() {
            var current = [row + 1] + Array(repeating: 0, count: text.count)
            for column in 1...max(1, text.count) where column <= text.count {
                let cost = text[column - 1] == character ? 0 : 1
                current[column] = min(previous[column - 1] + cost, previous[column] + 1, current[column - 1] + 1)
            }
            previous = current
        }
        return previous.min() ?? pattern.count
    }
}
