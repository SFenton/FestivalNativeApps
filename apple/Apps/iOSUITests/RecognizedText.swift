import UIKit
import Vision
import XCTest

// MARK: - Recognized text (AX5 journeys)

/// Text read back from an element's own capture with Vision, for the AX5 journeys
/// (`WhatsNewAccessibilityJourneyTests`, `CompeteAccessibilityJourneyTests`): whether a label
/// is drawn whole (no ellipsis, no clipped words) and how tall its glyphs render, so a journey
/// can compare a default-size launch with an AX5 launch (`testing/apple/accessibility.md`:
/// AX5 glyphs over 1.35× their Large height).
enum RecognizedText {
    /// Minimum growth of a text's glyphs from the default size to AX5 (project rule).
    static let minimumGrowth: CGFloat = 1.35

    /// Text recognized from the element's own capture and its median line height in points.
    struct Reading {
        let text: String?
        let lineHeight: CGFloat?
    }

    /// Recognize the element's text (upright, or turned when the capture arrives in the
    /// framebuffer's orientation) and measure its recognized line heights.
    ///
    /// - Parameters:
    ///   - element: An element on screen.
    ///   - label: The text it should show (the expected text).
    ///   - frame: Its frame, in points, at the capture.
    /// - Returns: The best reading (the one that shows the label whole, else the longest);
    ///   a capture taken while the last drag settled is retried.
    @MainActor
    static func recognize(_ element: XCUIElement, label: String, frame: CGRect) -> Reading {
        var reading = recognizeOnce(element, label: label, frame: frame)
        for _ in 0..<2 where !showsWhole(label, in: reading.text) || (reading.lineHeight ?? 0) <= 4 {
            RunLoop.current.run(until: Date().addingTimeInterval(FestivalApp.budget(0.5)))
            reading = recognizeOnce(element, label: label, frame: frame)
        }
        return reading
    }

    @MainActor
    private static func recognizeOnce(_ element: XCUIElement, label: String, frame: CGRect) -> Reading {
        guard let image = element.screenshot().image.cgImage else { return Reading(text: nil, lineHeight: nil) }
        var best = Reading(text: nil, lineHeight: nil)
        // A capture in the framebuffer's orientation (iPad landscape) is turned: try that first.
        let turned = (image.width > image.height) != (frame.width > frame.height)
        let orientations: [CGImagePropertyOrientation] = turned ? [.right, .left, .up] : [.up, .right, .left]
        for orientation in orientations {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.minimumTextHeight = 0
            guard (try? VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])) != nil
            else { continue }
            let lines = (request.results ?? []).sorted { $0.boundingBox.maxY > $1.boundingBox.maxY }
            guard !lines.isEmpty else { continue }
            let text = lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            let heights = lines.map { $0.boundingBox.height * frame.height }.sorted()
            let reading = Reading(text: text, lineHeight: heights[heights.count / 2])
            if showsWhole(label, in: text) { return reading }
            if (best.text?.count ?? -1) < text.count { best = reading }
        }
        return best
    }

    /// True when the recognized text shows the whole label without an ellipsis (letters and
    /// digits, one recognition error per ten characters tolerated; same rule as the iPad
    /// audit's `IPadAuditTextEvidence.showsWhole`).
    ///
    /// - Parameters:
    ///   - label: The expected text.
    ///   - recognized: What Vision read.
    /// - Returns: Whether `recognized` contains the whole label.
    static func showsWhole(_ label: String, in recognized: String?) -> Bool {
        guard let recognized, !recognized.contains("…"), !recognized.hasSuffix("...") else { return false }
        let wanted = normalized(label), seen = normalized(recognized)
        guard !wanted.isEmpty else { return false }
        return distance(wanted, in: seen) <= max(1, wanted.count / 10)
    }

    private static func normalized(_ text: String) -> [Character] {
        Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// Smallest edit distance between `pattern` and any substring of `text`.
    private static func distance(_ pattern: [Character], in text: [Character]) -> Int {
        var previous = Array(repeating: 0, count: text.count + 1)
        for (row, character) in pattern.enumerated() {
            var current = [row + 1] + Array(repeating: 0, count: text.count)
            for column in stride(from: 1, through: text.count, by: 1) {
                let cost = text[column - 1] == character ? 0 : 1
                current[column] = min(previous[column - 1] + cost, previous[column] + 1, current[column - 1] + 1)
            }
            previous = current
        }
        return previous.min() ?? pattern.count
    }
}
