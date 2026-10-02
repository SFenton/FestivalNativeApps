#if os(macOS)
import AppKit
import Foundation

// MARK: - Debug window hooks

/// Debug-only hooks that let `tools/mac_app.py` size and quit the app without Apple
/// Events or Accessibility permission (the Mac app cannot be driven by XCUITest here).
///
/// - `FST_DEBUG_WINDOW_SIZE=<w>x<h>` sets the main window's content size at launch.
/// - Distributed notification `…mac.debug.resize` (`width`, `height`) resizes it later.
/// - Distributed notification `…mac.debug.quit` calls `NSApp.terminate`, so AppKit quits
///   normally and never records an unexpected exit.
///
/// Release builds compile this to a no-op.
public enum MacDebugHooks {
    /// Notification posted by `tools/mac_window.swift quit`.
    static let quitName = Notification.Name("com.sfenton.festivalscoretracker.mac.debug.quit")
    /// Notification posted by `tools/mac_window.swift command`.
    static let commandName = Notification.Name("com.sfenton.festivalscoretracker.mac.debug.command")
    /// In-process notification carrying a parsed ``MacDebugCommand`` to the window.
    static let localCommandName = Notification.Name("FSTMacDebugCommand")
    /// Notification posted by `tools/mac_window.swift resize`.
    static let resizeName = Notification.Name("com.sfenton.festivalscoretracker.mac.debug.resize")

    /// Install the observers and apply any launch window size. Call once at launch.
    @MainActor public static func install() {
        #if DEBUG
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: quitName, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { NSApplication.shared.terminate(nil) }
        }
        center.addObserver(forName: commandName, object: nil, queue: .main) { note in
            guard let raw = note.userInfo?["command"] as? String,
                  let command = MacDebugCommand(raw) else { return }
            MainActor.assumeIsolated {
                NotificationCenter.default.post(name: localCommandName, object: command)
            }
        }
        center.addObserver(forName: resizeName, object: nil, queue: .main) { note in
            let width = (note.userInfo?["width"] as? NSNumber)?.doubleValue
            let height = (note.userInfo?["height"] as? NSNumber)?.doubleValue
            guard let width, let height else { return }
            MainActor.assumeIsolated { resizeMainWindow(to: CGSize(width: width, height: height)) }
        }
        if let size = ProcessInfo.processInfo.environment["FST_DEBUG_WINDOW_SIZE"]
            .flatMap(parseSize) {
            // `App.init` runs before AppKit has created the application object.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { applyWhenWindowAppears(size, attemptsLeft: 100) }
            }
        }
        #endif
    }

    /// Parse `WIDTHxHEIGHT` points.
    ///
    /// - Parameter raw: Text such as `1280x800`.
    /// - Returns: The size, or nil when malformed or not positive.
    static func parseSize(_ raw: String) -> CGSize? {
        let parts = raw.lowercased().split(separator: "x")
        guard parts.count == 2, let width = Double(parts[0]), let height = Double(parts[1]),
              width > 0, height > 0 else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Frame for a new content size that keeps the window's top-left corner fixed.
    ///
    /// - Parameters:
    ///   - frame: Current window frame (AppKit coordinates, origin bottom-left).
    ///   - newFrameSize: Window frame size for the requested content size.
    /// - Returns: The new frame.
    static func topAnchoredFrame(_ frame: CGRect, newFrameSize: CGSize) -> CGRect {
        CGRect(
            x: frame.minX, y: frame.maxY - newFrameSize.height,
            width: newFrameSize.width, height: newFrameSize.height
        )
    }

    #if DEBUG
    @MainActor private static func applyWhenWindowAppears(_ size: CGSize, attemptsLeft: Int) {
        if mainWindow != nil {
            resizeMainWindow(to: size)
            return
        }
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            MainActor.assumeIsolated { applyWhenWindowAppears(size, attemptsLeft: attemptsLeft - 1) }
        }
    }
    #endif

    /// The app's main content window (largest visible titled window).
    @MainActor private static var mainWindow: NSWindow? {
        NSApplication.shared.windows
            .filter { $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel) }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
    }

    @MainActor private static func resizeMainWindow(to size: CGSize) {
        guard let window = mainWindow else { return }
        let target = window.frameRect(forContentRect: CGRect(origin: .zero, size: size)).size
        window.setFrame(topAnchoredFrame(window.frame, newFrameSize: target), display: true)
    }
}

// MARK: - Debug commands

/// A shell command sent by `tools/mac_app.py command` (Debug only), so one launch can
/// visit pages and sheets for evidence without Accessibility permission.
enum MacDebugCommand: Equatable {
    /// `select:<n>` (⌘n) or `select:<destination>`.
    case select(MacDestination?, number: Int?)
    /// `route:<FST_DEBUG_ROUTE syntax>`: push (or select) a route.
    case route(String)
    case back, refresh, search, profile, notifications, whatsNew, sort, filter, dismiss

    /// Parse command text.
    ///
    /// - Parameter raw: e.g. `select:2`, `select:shop`, `route:player:abc`, `back`.
    init?(_ raw: String) {
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first, parts.count) {
        case ("select", 2):
            if let number = Int(parts[1]) {
                self = .select(nil, number: number)
            } else if let destination = MacDestination(rawValue: parts[1]) {
                self = .select(destination, number: nil)
            } else {
                return nil
            }
        case ("route", 2): self = .route(parts[1])
        case ("back", 1): self = .back
        case ("refresh", 1): self = .refresh
        case ("search", 1): self = .search
        case ("profile", 1): self = .profile
        case ("notifications", 1): self = .notifications
        case ("whatsnew", 1): self = .whatsNew
        case ("sort", 1): self = .sort
        case ("filter", 1): self = .filter
        case ("dismiss", 1): self = .dismiss
        default: return nil
        }
    }
}
#endif
