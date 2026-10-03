import XCTest
import UIKit

// MARK: - Step vocabulary

/// One scripted interaction against the app under test.
///
/// A step is one `verb:argument` line. `tools/ios_sim.py drive` accepts a
/// `;`-separated `--steps` string and/or a newline-separated `--steps-file`,
/// concatenates them, and hands the result to ``DriverTests`` as a temp file
/// path (`FST_DRIVER_STEPS_FILE`, arriving via xcodebuild's `TEST_RUNNER_`
/// environment passthrough — the simulator shares the host filesystem, so a
/// plain absolute path works both for reading the script and for `shot`/
/// `tree` outputs).
///
/// Supported verbs:
/// - `tap:<identifier-or-label>` — tap the first element whose
///   accessibility identifier matches; falls back to an exact label match.
/// - `tapText:<label>` — tap the first element with an exact label match.
/// - `tapXY:<x>,<y>` — tap a point. Both components `<= 1.0` are treated as
///   a normalized fraction of the app's window; otherwise as device points.
/// - `swipe:<up|down|left|right>[@identifier]` — swipe the whole app, or one
///   element when `@identifier` is given.
/// - `drag:<x1>,<y1>,<x2>,<y2>` — press, drag slowly between two normalized
///   window points and hold before release, so the scroll lands exactly
///   without momentum (a repeatable partial scroll for screenshots).
/// - `scrollTo:<identifier>` — swipe up on the app (up to 12 times) until the
///   element exists and is hittable.
/// - `type:<text>` — type into the current first responder.
/// - `wait:<seconds>` — sleep.
/// - `waitFor:<identifier>` — wait up to 20s for an element to exist.
/// - `back` — tap the leading navigation bar button.
/// - `shot:<path>` — write a full-screen PNG to an absolute host path.
/// - `tree:<path>` — write `app.debugDescription` (the accessibility
///   hierarchy — the fastest way for an agent to discover identifiers) to
///   an absolute host path.
/// - `rotate:<portrait|portraitUpsideDown|landscapeLeft|landscapeRight|faceUp|faceDown>`.
/// - `home[:<icon label>]` — press Home; with a label, page the Home Screen until an
///   icon with that label is on screen (Home Screen captures of the just-installed app).
/// - `resize:<fraction>` — iPad windowed multitasking: drag the app window's resize
///   corner so it spans that fraction of the screen width (e.g. `0.5`, `0.33`).
/// - `systemTree:<path>` — like `tree`, for SpringBoard (window controls, multitasking).
/// - `systemTap:<identifier-prefix-or-label>` — tap a SpringBoard element (e.g.
///   `window-controls`, then a window-controls menu item by label).
/// - `systemHold:<identifier-prefix-or-label>` — long-press a SpringBoard element (e.g.
///   `Zoom-button` for the window tiling menu).
/// - `fill` — iPad windowed multitasking: make the window fill the screen again
///   (always end a script that resized with it: iPadOS remembers window sizes).
/// - `tile:<Left|Right|Arrange thirds|Left and Right>` — iPad: exact tiling from the
///   window-controls menu (long-press Zoom); end with `fill`.
/// - `windowFrame:<path>` — append the app window's frame (points) to a host file.
/// - `key:<[cmd+][shift+][alt+][ctrl+]key>` — hardware-keyboard key press, e.g.
///   `key:cmd+2`, `key:tab`, `key:down`, `key:return`, `key:escape`, `key:space`.
enum DriverStep {
    case tap(String)
    case tapText(String)
    case tapXY(Double, Double)
    case swipe(Direction, identifier: String?)
    case drag(CGVector, CGVector)
    case scrollTo(String)
    case type(String)
    case wait(TimeInterval)
    case waitFor(String)
    case back
    case shot(String)
    case tree(String)
    case rotate(UIDeviceOrientation)
    case home(String?)
    case resize(Double)
    case fill
    case systemTree(String)
    case systemTap(String)
    case systemHold(String)
    case tile(WindowResize.Tile)
    case windowFrame(String)
    case key(String, XCUIElement.KeyModifierFlags)

    /// A cardinal swipe direction.
    enum Direction: String {
        case up, down, left, right
    }

    /// A step line that could not be parsed.
    enum ParseError: Error, CustomStringConvertible {
        case unknownVerb(String)
        case malformed(String)

        var description: String {
            switch self {
            case let .unknownVerb(verb): return "unknown driver step verb '\(verb)'"
            case let .malformed(raw): return "malformed driver step '\(raw)'"
            }
        }
    }

    /// Parse one `verb:argument` line.
    ///
    /// - Parameter raw: A single trimmed step, e.g. `"tap:fst.nav.settings"`.
    /// - Returns: The parsed step.
    /// - Throws: ``ParseError`` for an unknown verb or a malformed argument.
    static func parse(_ raw: String) throws -> DriverStep {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        let verb = parts.first ?? ""
        let arg = parts.count > 1 ? parts[1] : ""
        switch verb {
        case "tap":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .tap(arg)
        case "tapText":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .tapText(arg)
        case "tapXY":
            let coordinates = arg.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard coordinates.count == 2,
                  let x = Double(coordinates[0]), let y = Double(coordinates[1])
            else { throw ParseError.malformed(raw) }
            return .tapXY(x, y)
        case "swipe":
            let bits = arg.split(separator: "@", maxSplits: 1).map(String.init)
            guard let direction = Direction(rawValue: bits[0]) else { throw ParseError.malformed(raw) }
            return .swipe(direction, identifier: bits.count > 1 ? bits[1] : nil)
        case "drag":
            let values = arg.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard values.count == 4, values.allSatisfy({ (0...1).contains($0) }) else {
                throw ParseError.malformed(raw)
            }
            return .drag(CGVector(dx: values[0], dy: values[1]), CGVector(dx: values[2], dy: values[3]))
        case "scrollTo":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .scrollTo(arg)
        case "type":
            return .type(arg)
        case "wait":
            guard let seconds = TimeInterval(arg) else { throw ParseError.malformed(raw) }
            return .wait(seconds)
        case "waitFor":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .waitFor(arg)
        case "back":
            return .back
        case "shot":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .shot(arg)
        case "tree":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .tree(arg)
        case "fill":
            return .fill
        case "systemHold":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .systemHold(arg)
        case "systemTap":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .systemTap(arg)
        case "systemTree":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .systemTree(arg)
        case "resize":
            guard let fraction = Double(arg), (0.2...1).contains(fraction) else { throw ParseError.malformed(raw) }
            return .resize(fraction)
        case "rotate":
            guard let orientation = orientation(named: arg) else { throw ParseError.malformed(raw) }
            return .rotate(orientation)
        case "home":
            return .home(arg.isEmpty ? nil : arg)
        case "tile":
            guard let tile = WindowResize.Tile(rawValue: arg) else { throw ParseError.malformed(raw) }
            return .tile(tile)
        case "windowFrame":
            guard !arg.isEmpty else { throw ParseError.malformed(raw) }
            return .windowFrame(arg)
        case "key":
            guard let (key, flags) = keyPress(arg) else { throw ParseError.malformed(raw) }
            return .key(key, flags)
        default:
            throw ParseError.unknownVerb(verb)
        }
    }

    /// Parse a `key:` argument: `+`-joined modifiers, then a key name or character.
    ///
    /// - Parameter spec: For example `cmd+shift+p`, `tab`, `down`.
    /// - Returns: The XCUITest key and modifiers, or nil when malformed.
    static func keyPress(_ spec: String) -> (String, XCUIElement.KeyModifierFlags)? {
        var parts = spec.split(separator: "+").map(String.init)
        guard let last = parts.popLast(), !last.isEmpty else { return nil }
        var flags: XCUIElement.KeyModifierFlags = []
        for modifier in parts {
            switch modifier.lowercased() {
            case "cmd", "command": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "alt", "option": flags.insert(.option)
            case "ctrl", "control": flags.insert(.control)
            default: return nil
            }
        }
        let named: [String: String] = [
            "tab": XCUIKeyboardKey.tab.rawValue, "return": XCUIKeyboardKey.return.rawValue,
            "escape": XCUIKeyboardKey.escape.rawValue, "space": XCUIKeyboardKey.space.rawValue,
            "up": XCUIKeyboardKey.upArrow.rawValue, "down": XCUIKeyboardKey.downArrow.rawValue,
            "left": XCUIKeyboardKey.leftArrow.rawValue, "right": XCUIKeyboardKey.rightArrow.rawValue,
            "home": XCUIKeyboardKey.home.rawValue, "end": XCUIKeyboardKey.end.rawValue,
            "delete": XCUIKeyboardKey.delete.rawValue,
        ]
        if let key = named[last.lowercased()] { return (key, flags) }
        return last.count == 1 ? (last, flags) : nil
    }

    /// Map a step's orientation name to `UIDeviceOrientation`.
    ///
    /// - Parameter name: One of the names documented on ``DriverStep``.
    private static func orientation(named name: String) -> UIDeviceOrientation? {
        switch name {
        case "portrait": return .portrait
        case "portraitUpsideDown": return .portraitUpsideDown
        case "landscapeLeft": return .landscapeLeft
        case "landscapeRight": return .landscapeRight
        case "faceUp": return .faceUp
        case "faceDown": return .faceDown
        default: return nil
        }
    }
}

// MARK: - Driver test

/// Executes a step script (`FST_DRIVER_STEPS` or `FST_DRIVER_STEPS_FILE`)
/// against a freshly launched app, so any lane can script taps, swipes,
/// scrolling, sheets and screenshots that `tools/ios_sim.py shot` cannot
/// reach on its own.
///
/// Run via `python3 tools/ios_sim.py drive --steps "..."` (see that file's
/// docstring), never directly with plain `xcodebuild test` — the driver
/// script builds this target once with `build-for-testing`, then repeatedly
/// re-runs `testDrive` with `test-without-building` under the shared
/// simulator lock. `FST_DRIVER_CONTENT_SIZE` (a `UIContentSizeCategory` raw
/// value) launches the app at that Dynamic Type size.
final class DriverTests: XCTestCase {
    /// Environment keys the driver itself consumes rather than forwarding to the app.
    private static let controlKeys: Set<String> = [
        "FST_DRIVER_STEPS", "FST_DRIVER_STEPS_FILE", "FST_DRIVER_CONTENT_SIZE",
    ]

    /// A step script was neither inline nor found at the given file path.
    enum DriverError: Error, CustomStringConvertible {
        case noSteps
        case elementNotFound(String)

        var description: String {
            switch self {
            case .noSteps:
                return "FST_DRIVER_STEPS(_FILE) was empty or missing"
            case let .elementNotFound(identifier):
                return "no element matched '\(identifier)'"
            }
        }
    }

    /// Launch the app with passthrough `FST_*` environment, then run every step in order.
    ///
    /// - Throws: The first step's failure. Before failing, writes a screenshot
    ///   and an accessibility-tree dump to `/tmp/fst-driver-failure-<n>.{png,tree.txt}`
    ///   so the caller can see exactly what was on screen.
    @MainActor
    func testDrive() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let steps = try Self.loadSteps(environment: environment)

        var launchEnvironment: [String: String] = [:]
        for (key, value) in environment
        where key.hasPrefix("FST_") && !Self.controlKeys.contains(key) {
            launchEnvironment[key] = value
        }
        // FestivalApp.makeApp defaults FST_DEBUG_STILL_BACKGROUND=1, but
        // `ios_sim.py drive --animate` opts out by omitting that key entirely
        // from its passthrough environment, not by setting it to something
        // falsy — make that override explicit so the shared default doesn't
        // silently win and re-enable animation `--animate` asked to keep.
        if launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] == nil {
            launchEnvironment["FST_DEBUG_STILL_BACKGROUND"] = "0"
        }
        let app = FestivalApp.makeApp(launchEnvironment)
        // `--env FST_DRIVER_CONTENT_SIZE=UICTContentSizeCategoryAccessibilityXL` launches at that
        // Dynamic Type size (a `UIContentSizeCategory` raw value) without touching device settings.
        if let contentSize = environment["FST_DRIVER_CONTENT_SIZE"], !contentSize.isEmpty {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()

        for (offset, raw) in steps.enumerated() {
            let index = offset + 1
            let step: DriverStep
            do {
                step = try DriverStep.parse(raw)
            } catch {
                XCTFail("Driver step \(index) '\(raw)' did not parse: \(error)")
                return
            }
            do {
                try Self.perform(step, app: app)
            } catch {
                Self.captureFailure(app: app, stepIndex: index)
                XCTFail("Driver step \(index) '\(raw)' failed: \(error)")
                return
            }
        }
    }

    // MARK: Step script loading

    /// Read the step script named by the environment.
    ///
    /// - Parameter environment: The test process's environment (populated
    ///   from `xcodebuild`'s `TEST_RUNNER_FST_DRIVER_STEPS[_FILE]`).
    /// - Returns: Ordered, non-empty, comment-stripped step strings.
    /// - Throws: ``DriverError/noSteps`` when neither source is present or
    ///   both are empty after stripping.
    private static func loadSteps(environment: [String: String]) throws -> [String] {
        var raw = ""
        if let path = environment["FST_DRIVER_STEPS_FILE"] {
            raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        } else if let inline = environment["FST_DRIVER_STEPS"] {
            raw = inline.replacingOccurrences(of: ";", with: "\n")
        }
        let steps = raw
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !steps.isEmpty else { throw DriverError.noSteps }
        return steps
    }

    // MARK: Step execution

    /// Execute one parsed step against the launched app.
    ///
    /// - Parameters:
    ///   - step: Parsed instruction.
    ///   - app: The running application under test.
    /// - Throws: ``DriverError/elementNotFound(_:)`` when a targeted element
    ///   never appears (or never becomes hittable, for `scrollTo`).
    @MainActor
    static func perform(_ step: DriverStep, app: XCUIApplication) throws {
        switch step {
        case let .tap(target):
            let candidate = try element(identifierOrLabel: target, in: app)
            if candidate.elementType == .switch {
                // A dead-center tap on a SwiftUI Form `Toggle` row doesn't reliably land on
                // the switch's own hit target; its trailing edge (the knob) does.
                candidate.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            } else {
                candidate.tap()
            }
        case let .tapText(label):
            let candidate = app.descendants(matching: .any)
                .matching(NSPredicate(format: "label == %@", label)).firstMatch
            guard candidate.waitForExistence(timeout: 10) else {
                throw DriverError.elementNotFound(label)
            }
            candidate.tap()
        case let .tapXY(x, y):
            let normalized = (x <= 1.0 && y <= 1.0)
                ? CGVector(dx: x, dy: y)
                : normalizedVector(devicePoints: CGPoint(x: x, y: y), in: app)
            app.coordinate(withNormalizedOffset: normalized).tap()
        case let .swipe(direction, identifier):
            let target: XCUIElement
            if let identifier {
                target = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
                guard target.waitForExistence(timeout: 10) else {
                    throw DriverError.elementNotFound(identifier)
                }
            } else {
                target = app
            }
            switch direction {
            case .up: target.swipeUp()
            case .down: target.swipeDown()
            case .left: target.swipeLeft()
            case .right: target.swipeRight()
            }
        case let .drag(from, to):
            app.coordinate(withNormalizedOffset: from).press(
                forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: to),
                withVelocity: .slow, thenHoldForDuration: 0.5)
        case let .scrollTo(identifier):
            let candidate = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            var attempts = 0
            while !(candidate.exists && candidate.isHittable) && attempts < 12 {
                app.swipeUp()
                attempts += 1
            }
            guard candidate.exists && candidate.isHittable else {
                throw DriverError.elementNotFound(identifier)
            }
        case let .type(text):
            app.typeText(text)
        case let .wait(seconds):
            Thread.sleep(forTimeInterval: seconds)
        case let .waitFor(identifier):
            let candidate = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            guard candidate.waitForExistence(timeout: 20) else {
                throw DriverError.elementNotFound(identifier)
            }
        case .back:
            // iPhone Duo puts Back in the system vertical bar, outside any navigation bar.
            let system = app.buttons["BackButton"]
            let button = system.waitForExistence(timeout: 2) && system.isHittable
                ? system : app.navigationBars.buttons.firstMatch
            guard button.waitForExistence(timeout: 10) else {
                throw DriverError.elementNotFound("navigationBars.buttons.firstMatch")
            }
            button.tap()
        case let .shot(path):
            try writeScreenshot(to: path)
        case let .tree(path):
            try app.debugDescription.write(toFile: path, atomically: true, encoding: .utf8)
        case let .systemTap(identifier), let .systemHold(identifier):
            let target = XCUIApplication(bundleIdentifier: "com.apple.springboard")
                .descendants(matching: .any).matching(
                    NSPredicate(format: "identifier BEGINSWITH %@ OR label == %@", identifier, identifier)
                ).firstMatch
            guard target.waitForExistence(timeout: 5) else { throw DriverError.elementNotFound(identifier) }
            if case .systemHold = step { target.press(forDuration: 1.2) } else { target.tap() }
        case let .systemTree(path):
            try XCUIApplication(bundleIdentifier: "com.apple.springboard").debugDescription
                .write(toFile: path, atomically: true, encoding: .utf8)
        case let .rotate(orientation):
            XCUIDevice.shared.orientation = orientation
        case let .home(label):
            XCUIDevice.shared.press(.home)
            if let label { _ = try visibleHomeScreenIcon(label) }
        case let .resize(fraction):
            WindowResize.resize(app, toScreenFraction: CGFloat(fraction))
        case .fill:
            WindowResize.fill(app)
        case let .tile(tile):
            guard WindowResize.tile(app, tile) else { throw DriverError.elementNotFound(tile.rawValue) }
        case let .windowFrame(path):
            let line = "\(NSCoder.string(for: app.windows.firstMatch.frame))\n"
            let url = URL(fileURLWithPath: path)
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try handle.close()
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        case let .key(key, flags):
            app.typeKey(key, modifierFlags: flags)
        }
    }

    /// Page the Home Screen until an icon with this label is on screen.
    ///
    /// A newly installed app or web clip lands on the first page with room, often not the
    /// first page. iPhone Duo's SpringBoard reports visible icons as not hittable, so an
    /// icon counts as visible when its frame's centre lies inside the SpringBoard window.
    ///
    /// - Parameter label: The icon's Home Screen label (its `CFBundleDisplayName`).
    /// - Returns: The first on-screen icon with that label.
    /// - Throws: ``DriverError/elementNotFound(_:)`` when no such icon exists or none is
    ///   on screen within three page swipes.
    @MainActor
    static func visibleHomeScreenIcon(_ label: String) throws -> XCUIElement {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let icons = springboard.icons.matching(identifier: label)
        guard icons.firstMatch.waitForExistence(timeout: 10) else {
            throw DriverError.elementNotFound(label)
        }
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
        guard let icon = visibleIcon() else { throw DriverError.elementNotFound(label) }
        return icon
    }

    /// Resolve `tap:`'s target: try an accessibility-identifier match first,
    /// then fall back to an exact label match.
    ///
    /// - Parameters:
    ///   - target: Identifier or label from the step argument.
    ///   - app: The running application under test.
    /// - Returns: The first matching, existing element.
    /// - Throws: ``DriverError/elementNotFound(_:)`` if neither matches in time.
    @MainActor
    static func element(identifierOrLabel target: String, in app: XCUIApplication) throws -> XCUIElement {
        // Prefer the concrete `XCUIElementTypeSwitch` over a generic descendant match: a
        // `Form` `Toggle` row's identifier can resolve to a non-hittable container node via
        // `.any`, which silently no-ops on tap (see `.tap`'s trailing-edge-coordinate handling).
        let bySwitch = app.switches[target]
        if bySwitch.waitForExistence(timeout: 1) { return bySwitch }
        let byIdentifier = app.descendants(matching: .any).matching(identifier: target).firstMatch
        if byIdentifier.waitForExistence(timeout: 6) { return byIdentifier }
        let byLabel = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", target)).firstMatch
        guard byLabel.waitForExistence(timeout: 6) else { throw DriverError.elementNotFound(target) }
        return byLabel
    }

    /// Convert raw device points into a normalized offset for
    /// `coordinate(withNormalizedOffset:)`, using the app's frontmost window frame.
    ///
    /// - Parameters:
    ///   - devicePoints: Point coordinates in the window's own point space.
    ///   - app: The running application under test.
    private static func normalizedVector(devicePoints: CGPoint, in app: XCUIApplication) -> CGVector {
        let frame = app.windows.firstMatch.frame
        guard frame.width > 0, frame.height > 0 else { return .zero }
        return CGVector(dx: devicePoints.x / frame.width, dy: devicePoints.y / frame.height)
    }

    /// Write a full-screen PNG to an absolute host path.
    ///
    /// - Parameter path: Destination file path (the simulator shares the host filesystem).
    @MainActor
    static func writeScreenshot(to path: String) throws {
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try data.write(to: URL(fileURLWithPath: path))
    }

    /// Capture a screenshot and an accessibility-tree dump beside the step that failed.
    ///
    /// - Parameters:
    ///   - app: The running application under test.
    ///   - stepIndex: 1-based index of the failing step, used to name the files.
    @MainActor
    private static func captureFailure(app: XCUIApplication, stepIndex: Int) {
        let base = "/tmp/fst-driver-failure-\(stepIndex)"
        try? writeScreenshot(to: base + ".png")
        try? app.debugDescription.write(toFile: base + ".tree.txt", atomically: true, encoding: .utf8)
    }
}
