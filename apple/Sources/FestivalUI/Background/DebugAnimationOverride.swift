import Foundation

// MARK: - Debug animation override

/// Launch-time switches that make UI automation deterministic.
enum DebugAnimationOverride {
    /// True when `FST_DEBUG_STILL_BACKGROUND=1` (Debug only).
    ///
    /// XCUITest waits for the app to go idle before every action; the
    /// continuously animating album carousel never idles, so each step would
    /// hit XCTest's idle timeout. `tools/ios_sim.py drive` sets this by default
    /// (`--animate` opts out). Release builds always return false.
    static let stillBackground: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FST_DEBUG_STILL_BACKGROUND"] == "1"
        #else
        false
        #endif
    }()
}
