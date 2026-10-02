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
    /// (½, ⅓) is the window-controls menu, which is not scripted yet.
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
