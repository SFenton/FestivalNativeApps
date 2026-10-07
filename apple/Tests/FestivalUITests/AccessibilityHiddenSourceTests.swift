import Foundation
import Testing

// MARK: - `.accessibilityHidden(someBool)` guard

/// `.accessibilityHidden(false)` on a view **un-hides** every descendant marked hidden
/// (Lane A11Y2: Leaderboards' instrument icons; Lane A11Y4: the publication-refresh
/// boundary exposed Song Detail's full-screen cover backdrop as an unlabelled Image on
/// every pushed page). Views use `.accessibilityHidden(true)` or
/// `.accessibilityHidden(while:)` only.
@Test("No view passes a computed Bool to accessibilityHidden(_:)")
func noComputedAccessibilityHiddenOnViews() throws {
    let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/FestivalUI")
    let pattern = try NSRegularExpression(pattern: #"\.accessibilityHidden\((?!true\)|true,|while:)"#)
    var offenders: [String] = []
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
    while let url = files?.nextObject() as? URL {
        guard url.pathExtension == "swift" else { continue }
        let relative = String(url.path.dropFirst(sources.path.count + 1))
        let text = try String(contentsOf: url, encoding: .utf8)
        for (number, line) in text.components(separatedBy: "\n").enumerated() {
            let code = line.components(separatedBy: "//").first ?? ""
            let range = NSRange(code.startIndex..., in: code)
            if pattern.firstMatch(in: code, range: range) != nil {
                offenders.append("\(relative):\(number + 1)")
            }
        }
    }
    #expect(offenders.isEmpty, "Use .accessibilityHidden(while:) instead: \(offenders)")
}
