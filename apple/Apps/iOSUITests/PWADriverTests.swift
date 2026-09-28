import XCTest
import UIKit

// MARK: - PWA step vocabulary

/// One scripted interaction for the installed-PWA reference lab.
///
/// ``PWADriverTests`` drives *other* apps on the simulator: Mobile Safari (open a
/// URL, Share > Add to Home Screen), SpringBoard (tap the installed web-app icon)
/// and the standalone web-app host (`com.apple.webapp`). Every ``DriverStep`` verb
/// (`tap`, `tapText`, `tapXY`, `swipe`, `scrollTo`, `type`, `wait`, `waitFor`,
/// `shot`, `tree`, `rotate`) also works and runs against the current target app.
///
/// PWA-only verbs:
/// - `target:<safari|springboard|webapp|bundle-id>` — switch the app later steps act on.
/// - `activate` / `launch` / `terminate` — bring forward, (re)launch or kill the target.
/// - `openURL:<url>` — open a URL through the system (lands in Safari for http/https).
/// - `home` — press the Home button (SpringBoard comes forward).
/// - `launchIcon:<label>` — tap a SpringBoard icon and target `com.apple.webapp`.
/// - `tapContains:<text>` — tap the first element whose label contains `text` (case-insensitive).
/// - `waitText:<text>` — wait up to 20s for an element whose label contains `text`.
/// - `tapIfExists:<label>` — tap an exact-label element if it appears within 3s, else continue
///   (optional modals such as the What's New changelog).
/// - `stopIfExists:<label>` — end the script successfully if an exact label exists
///   (e.g. skip Add to Home Screen when the icon is already installed).
/// - `edgeBack` — drag from the leading screen edge (the standalone PWA's back gesture).
/// - `drag:<x1>,<y1>,<x2>,<y2>[,<hold>]` — press at a normalized point, drag, release.
/// - `scroll:<down|up>[,<fraction>]` — a moderate one-finger scroll (finger travels
///   `fraction` of the height, default 0.45) that reveals content further down/up.
/// - `clearType:<text>` — delete the focused field's text (up to 40 characters), then type `text`.
/// - `mark:<label>` — append `<unix-seconds> <label>` to `FST_PWA_MARKS_FILE` so a
///   screen recording can be frame-stepped against named moments.
enum PWAStep {
    case driver(DriverStep)
    case target(String)
    case activate
    case launch
    case terminate
    case openURL(URL)
    case home
    case launchIcon(String)
    case tapContains(String)
    case waitText(String)
    case stopIfExists(String)
    case tapIfExists(String)
    case edgeBack
    case drag(CGVector, CGVector, hold: TimeInterval)
    case scroll(down: Bool, fraction: Double)
    case mark(String)
    case clearType(String)

    /// Bundle identifiers behind the `target:` aliases.
    static let aliases = [
        "safari": "com.apple.mobilesafari",
        "springboard": "com.apple.springboard",
        "webapp": "com.apple.webapp",
    ]

    /// Parse one `verb:argument` line, deferring unknown verbs to ``DriverStep``.
    ///
    /// - Parameter raw: A single trimmed step.
    /// - Returns: The parsed step.
    /// - Throws: ``DriverStep/ParseError`` for unknown or malformed steps.
    static func parse(_ raw: String) throws -> PWAStep {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        let verb = parts.first ?? ""
        let arg = parts.count > 1 ? parts[1] : ""
        func numbers() -> [Double] {
            arg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        switch verb {
        case "target":
            guard !arg.isEmpty else { throw DriverStep.ParseError.malformed(raw) }
            return .target(aliases[arg] ?? arg)
        case "activate": return .activate
        case "launch": return .launch
        case "terminate": return .terminate
        case "home": return .home
        case "clearType": return .clearType(arg)
        case "edgeBack": return .edgeBack
        case "openURL":
            guard let url = URL(string: arg), url.scheme != nil else { throw DriverStep.ParseError.malformed(raw) }
            return .openURL(url)
        case "launchIcon", "tapContains", "waitText", "stopIfExists", "tapIfExists", "mark":
            guard !arg.isEmpty else { throw DriverStep.ParseError.malformed(raw) }
            switch verb {
            case "launchIcon": return .launchIcon(arg)
            case "tapContains": return .tapContains(arg)
            case "waitText": return .waitText(arg)
            case "stopIfExists": return .stopIfExists(arg)
            case "tapIfExists": return .tapIfExists(arg)
            default: return .mark(arg)
            }
        case "drag":
            let values = numbers()
            guard values.count == 4 || values.count == 5 else { throw DriverStep.ParseError.malformed(raw) }
            return .drag(CGVector(dx: values[0], dy: values[1]), CGVector(dx: values[2], dy: values[3]),
                         hold: values.count == 5 ? values[4] : 0.05)
        case "scroll":
            let bits = arg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let direction = bits.first, direction == "down" || direction == "up" else {
                throw DriverStep.ParseError.malformed(raw)
            }
            let fraction = bits.count > 1 ? Double(bits[1]) ?? 0.45 : 0.45
            return .scroll(down: direction == "down", fraction: min(max(fraction, 0.05), 0.85))
        default:
            return .driver(try DriverStep.parse(raw))
        }
    }
}

// MARK: - PWA driver test

/// Executes a PWA step script (`FST_PWA_STEPS_FILE`) against Safari, SpringBoard
/// and the installed standalone web app. Run only through `python3 tools/pwa_ios.py`
/// (same simulator lock, build cache and recording as `ios_sim.py drive`).
final class PWADriverTests: XCTestCase {
    /// Signals that `stopIfExists:` ended the script early on purpose.
    private struct Stop: Error {}

    /// Current target app; `target:` and `launchIcon:` change it.
    private var app: XCUIApplication!

    /// Run every step in order against the current target app.
    ///
    /// - Throws: Never directly; the first failing step fails the test after writing
    ///   `/tmp/fst-pwa-failure-<n>.{png,tree.txt}`.
    @MainActor
    func testPWADrive() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let path = environment["FST_PWA_STEPS_FILE"] ?? ""
        let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let steps = raw.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        XCTAssertFalse(steps.isEmpty, "FST_PWA_STEPS_FILE was empty or missing")
        let initial = environment["FST_PWA_TARGET"] ?? "safari"
        app = XCUIApplication(bundleIdentifier: PWAStep.aliases[initial] ?? initial)
        let marks = environment["FST_PWA_MARKS_FILE"]
        for (offset, line) in steps.enumerated() {
            do {
                try perform(try PWAStep.parse(line), marks: marks)
            } catch is Stop {
                return
            } catch {
                let base = "/tmp/fst-pwa-failure-\(offset + 1)"
                try? DriverTests.writeScreenshot(to: base + ".png")
                try? app.debugDescription.write(toFile: base + ".tree.txt", atomically: true, encoding: .utf8)
                XCTFail("PWA step \(offset + 1) '\(line)' failed: \(error)")
                return
            }
        }
    }

    /// Execute one step.
    ///
    /// - Parameters:
    ///   - step: Parsed step.
    ///   - marks: Optional marks file for `mark:`.
    /// - Throws: ``DriverTests/DriverError`` when an element never appears, or ``Stop``.
    @MainActor
    private func perform(_ step: PWAStep, marks: String?) throws {
        switch step {
        case let .driver(.tap(label)), let .driver(.tapText(label)):
            // Web content: an element far outside the viewport still "exists", and XCUITest
            // taps its clamped frame centre, which lands on whatever is on screen there
            // (2026-09-28: a "View full leaderboard" link 7000pt down opened a player row).
            let match = app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == %@ OR label == %@", label, label)).firstMatch
            try safeTap(match, named: label)
        case let .driver(inner):
            try DriverTests.perform(inner, app: app)
        case let .target(bundle):
            app = XCUIApplication(bundleIdentifier: bundle)
        case .activate:
            app.activate()
        case .launch:
            app.launch()
        case .terminate:
            app.terminate()
        case let .openURL(url):
            XCUIDevice.shared.system.open(url)
        case .home:
            XCUIDevice.shared.press(.home)
        case let .launchIcon(label):
            let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
            let icons = springboard.icons.matching(identifier: label)
            guard icons.firstMatch.waitForExistence(timeout: 10) else {
                throw DriverTests.DriverError.elementNotFound(label)
            }
            // A new web clip lands on the first page with room, often not the first page.
            // iPhone Duo's SpringBoard reports visible icons as not hittable, so pick the
            // match whose frame is on screen and tap its centre by coordinate.
            let screen = springboard.windows.firstMatch.frame
            func visibleIcon() -> XCUIElement? {
                icons.allElementsBoundByIndex.first { icon in
                    let frame = icon.frame
                    return !frame.isEmpty && screen.contains(CGPoint(x: frame.midX, y: frame.midY))
                }
            }
            let settle = Date().addingTimeInterval(3)
            while visibleIcon() == nil && Date() < settle { Thread.sleep(forTimeInterval: 0.25) }
            var pages = 0
            while visibleIcon() == nil && pages < 3 {
                springboard.swipeLeft()
                pages += 1
            }
            guard let icon = visibleIcon() else { throw DriverTests.DriverError.elementNotFound(label) }
            icon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
            app = XCUIApplication(bundleIdentifier: "com.apple.webapp")
        case let .tapContains(text):
            try safeTap(element(containing: text), named: text)
        case let .waitText(text):
            guard element(containing: text).waitForExistence(timeout: 20) else {
                throw DriverTests.DriverError.elementNotFound(text)
            }
        case let .stopIfExists(label):
            let match = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            if match.waitForExistence(timeout: 3) { throw Stop() }
        case let .tapIfExists(label):
            let match = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
            if match.waitForExistence(timeout: 3) && onScreen(match) { match.tap() }
        case .edgeBack:
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
            start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        case let .drag(from, to, hold):
            app.coordinate(withNormalizedOffset: from)
                .press(forDuration: hold, thenDragTo: app.coordinate(withNormalizedOffset: to))
        case let .scroll(down, fraction):
            // Centred above the PWA's bottom dock (search pill, FAB) and tab bar so the
            // drag starts on scrollable content, not on a fixed overlay.
            let top = 0.42 - fraction / 2, bottom = 0.42 + fraction / 2
            let from = CGVector(dx: 0.5, dy: down ? bottom : top), to = CGVector(dx: 0.5, dy: down ? top : bottom)
            app.coordinate(withNormalizedOffset: from).press(
                forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: to),
                withVelocity: .default, thenHoldForDuration: 0)
        case let .clearType(text):
            app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40) + text)
        case let .mark(label):
            guard let marks else { return }
            let line = String(format: "%.3f %@\n", Date().timeIntervalSince1970, label)
            if let handle = FileHandle(forWritingAtPath: marks) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try line.write(toFile: marks, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Whether an element's centre lies inside the target app's window.
    ///
    /// - Parameter element: An existing element.
    /// - Returns: True when a tap would land on the element itself.
    @MainActor
    private func onScreen(_ element: XCUIElement) -> Bool {
        // iPhone Duo hosts more than one window (outer and inner panels), and
        // `windows.firstMatch` need not be the lit one, so accept any of them.
        let frame = element.frame
        guard !frame.isEmpty else { return false }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        return app.windows.allElementsBoundByIndex.contains { !$0.frame.isEmpty && $0.frame.contains(centre) }
    }

    /// Tap only an element that is on screen; never a clamped off-screen coordinate.
    ///
    /// - Parameters:
    ///   - element: Candidate element.
    ///   - name: Label used in the error.
    /// - Throws: ``DriverTests/DriverError/elementNotFound(_:)`` when it never appears on screen.
    @MainActor
    private func safeTap(_ element: XCUIElement, named name: String) throws {
        guard element.waitForExistence(timeout: 10) else { throw DriverTests.DriverError.elementNotFound(name) }
        guard onScreen(element) else { throw DriverTests.DriverError.elementNotFound(name + " (exists but off screen)") }
        element.tap()
    }

    /// First element in the current target whose label contains `text` (case-insensitive).
    ///
    /// - Parameter text: Substring to find.
    /// - Returns: A (possibly non-existent) element query result.
    @MainActor
    private func element(containing text: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }
}
