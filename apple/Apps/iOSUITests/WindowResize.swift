import XCTest

/// Resizes the app's window on an iPad in windowed multitasking (iPadOS 26 windows,
/// Stage Manager) by dragging its resize corner, the way a person makes a
/// Split View ½ or ⅓ window. Used by `DriverTests` (`resize:`/`fill` steps) and the iPad
/// journeys. iPadOS remembers each app's window size, so every resize must end with
/// ``fill(_:)``.
enum WindowResize {
    /// SpringBoard, which owns the window chrome.
    @MainActor
    private static var springboard: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.springboard")
    }

    /// Screen width in the current interface orientation (SpringBoard's own frame stays
    /// in portrait points).
    @MainActor
    private static var screenWidth: CGFloat {
        let frame = springboard.frame
        return XCUIDevice.shared.orientation.isLandscape
            ? max(frame.width, frame.height) : min(frame.width, frame.height)
    }

    /// Drag the window's bottom-trailing resize corner towards `fraction` of the screen
    /// width (keeping its leading edge).
    ///
    /// iPadOS re-centres a full-screen window as it leaves full screen and clamps to a
    /// ~375 pt minimum, so from full screen any fraction below ~0.6 lands on the
    /// compact minimum (a ⅓ / Slide Over-like window); growing a small window again
    /// gives an intermediate regular width (measured 829 pt for `0.5`). Exact tiling
    /// (½, ⅓) uses the window-controls menu instead: ``tile(_:_:)``.
    ///
    /// - Parameters:
    ///   - app: The running app under test.
    ///   - fraction: Target width as a fraction of the screen width (0.2…1).
    /// - Returns: True when the window width changed.
    @MainActor
    @discardableResult
    static func resize(_ app: XCUIApplication, toScreenFraction fraction: CGFloat) -> Bool {
        let window = app.windows.firstMatch.frame
        guard window.width > 0 else { return false }
        let origin = springboard.coordinate(withNormalizedOffset: .zero)
        // The resize corner sits just inside the window's bottom-trailing rounded corner.
        let start = origin.withOffset(CGVector(dx: window.maxX - 6, dy: window.maxY - 6))
        let targetX = window.minX + screenWidth * min(1, max(0.2, fraction))
        let end = origin.withOffset(CGVector(dx: targetX - 6, dy: window.maxY - 6))
        start.press(forDuration: 0.4, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.6)
        Thread.sleep(forTimeInterval: 1.5)
        return abs(app.windows.firstMatch.frame.width - window.width) > 1
    }

    /// A window-controls tiling choice (iPadOS 26: long-press the window's green Zoom
    /// button). The raw value is the menu button's accessibility label. "Fill" is left
    /// out on purpose: it enters full screen, where the window controls leave the
    /// accessibility tree and the next SpringBoard query hung XCUITest; ``fill(_:)``
    /// (Zoom) restores a full-width window that keeps its controls.
    enum Tile: String, CaseIterable {
        /// Left half of the screen ("Move & Resize › Left").
        case left = "Left"
        /// Right half of the screen.
        case right = "Right"
        /// Arrange the frontmost windows in thirds.
        case thirds = "Arrange thirds"
        /// Arrange the two frontmost windows left and right.
        case leftAndRight = "Left and Right"
    }

    /// Tile the app window exactly through the window-controls menu (expand the controls
    /// when the window fills the screen, long-press Zoom, choose the tile).
    ///
    /// - Parameters:
    ///   - app: The running app under test.
    ///   - tile: The menu choice.
    /// - Returns: True when the menu item was found and tapped.
    @MainActor
    @discardableResult
    static func tile(_ app: XCUIApplication, _ tile: Tile) -> Bool {
        let controls = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'window-controls'")
        ).firstMatch
        let zoom = springboard.buttons["Zoom-button"]
        let item = springboard.buttons[tile.rawValue]
        // A full-width window hides its controls a moment after it fills (they leave
        // the accessibility tree); a drag-resized window keeps them, so shrink first
        // when they are gone or a try found no menu. The collapsed controls keep a
        // hittable-looking Zoom button in the tree, so always tap the controls first.
        for attempt in 0..<3 {
            if attempt > 0 || !controls.waitForExistence(timeout: 2) {
                resize(app, toScreenFraction: 0.7)
            }
            guard controls.waitForExistence(timeout: 3) else { continue }
            controls.tap()
            guard zoom.waitForExistence(timeout: 3) else { continue }
            Thread.sleep(forTimeInterval: 0.5)
            zoom.press(forDuration: 1.2)
            if item.waitForExistence(timeout: 3) {
                item.tap()
                Thread.sleep(forTimeInterval: 2)
                return true
            }
        }
        return false
    }

    /// Close the front app window with its window controls' Close button (resizing a
    /// full-width window first so its controls show). Journeys that open a second window
    /// must close it: iPadOS reconnects every open window on the next launch.
    ///
    /// - Parameter app: The running app under test.
    /// - Returns: True when the Close button was found and tapped.
    @MainActor
    @discardableResult
    static func closeFrontWindow(_ app: XCUIApplication) -> Bool {
        let controls = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'window-controls'")
        ).firstMatch
        let close = springboard.buttons["Close-button"]
        for attempt in 0..<2 {
            if attempt > 0 || !controls.waitForExistence(timeout: 2) {
                resize(app, toScreenFraction: 0.7)
            }
            guard controls.waitForExistence(timeout: 3) else { continue }
            controls.tap()
            if close.waitForExistence(timeout: 3) {
                Thread.sleep(forTimeInterval: 0.5)
                close.tap()
                Thread.sleep(forTimeInterval: 2)
                return true
            }
        }
        return false
    }

    /// The app window's current width in points.
    ///
    /// - Parameter app: The running app under test.
    /// - Returns: The width, or 0 without a window.
    @MainActor
    static func windowWidth(_ app: XCUIApplication) -> CGFloat {
        app.windows.firstMatch.frame.width
    }

    /// The screen width in the current orientation (for tiling assertions).
    @MainActor
    static var currentScreenWidth: CGFloat { screenWidth }

    /// Make the app window fill the screen again: the window-controls button, then
    /// **Zoom** (iPadOS 26 window controls).
    ///
    /// - Parameter app: The running app under test.
    /// - Returns: True when the window spans the screen width afterwards.
    @MainActor
    @discardableResult
    static func fill(_ app: XCUIApplication) -> Bool {
        func filled() -> Bool { abs(app.windows.firstMatch.frame.width - screenWidth) <= 1 }
        if filled() { return true }
        let controls = springboard.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'window-controls'")
        ).firstMatch
        guard controls.waitForExistence(timeout: 3) else { return false }
        controls.tap()
        let zoom = springboard.buttons["Zoom-button"]
        guard zoom.waitForExistence(timeout: 3) else { return false }
        zoom.tap()
        Thread.sleep(forTimeInterval: 1.5)
        return filled()
    }
}
