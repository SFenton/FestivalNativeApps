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

    /// True when `FST_DEBUG_KEEP_FADES=1` (Debug only): keep the finite load-in fades
    /// on while the background is still, so a `drive --record` can show which content
    /// fades (issue #30) without `--animate`'s never-idle carousel. Release: false.
    static let keepFades: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FST_DEBUG_KEEP_FADES"] == "1"
        #else
        false
        #endif
    }()

    /// True when `FST_DEBUG_NO_BACKDROP=1` (Debug only): pages draw the plain brand
    /// surface instead of mirroring the shared backdrop, to bisect frame-pacing costs.
    static let noBackdrop: Bool = {
        #if DEBUG
        ProcessInfo.processInfo.environment["FST_DEBUG_NO_BACKDROP"] == "1"
        #else
        false
        #endif
    }()
}
