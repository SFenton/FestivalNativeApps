import Foundation

// MARK: - Launch configuration

/// What the perf autorun (``ScrollCostAutorun``) was asked to do, parsed from the launch environment so the SwiftUI app
/// and the UIKit port read it identically.
///
/// | Key | Meaning |
/// |---|---|
/// | `FST_PERF_AUTORUN=<s>` | Enables the run; seconds to settle after launch before measuring |
/// | `FST_PERF_FILE` | Result file (tab-separated `FSTPERF` lines) |
/// | `FST_PERF_NAME` | Surface name written on each line |
/// | `FST_PERF_SECONDS` | Length of the idle run and of each scroll run (default 8) |
/// | `FST_PERF_SPEED` | Scroll speed in points per second (default 900) |
/// | `FST_PERF_AXIS=horizontal` | Drive the widest sideways scroller instead of the page |
/// | `FST_PERF_NAV=<routes>` | `;`-separated `FST_DEBUG_ROUTE` tokens: measure push and pop of each instead of scrolling |
/// | `FST_PERF_NAV_CYCLES` | Push/pop cycles per route (default 6: one cold, five warm) |
struct PerfConfig: Equatable {
    /// Seconds to wait after launch before the first measurement.
    var settle: Double
    /// Result file path.
    var file: String?
    /// Surface name.
    var name: String
    /// Seconds per idle or scroll run.
    var seconds: Double
    /// Scroll speed in points per second.
    var speed: Double
    /// Scroll sideways instead of up and down.
    var horizontal: Bool
    /// `FST_DEBUG_ROUTE` tokens to push and pop; empty for a scroll run.
    var navRoutes: [String]
    /// Push/pop cycles per route.
    var navCycles: Int

    /// Parses the environment.
    ///
    /// - Parameter environment: Process environment.
    /// - Returns: The configuration, or nil unless `FST_PERF_AUTORUN` is a number.
    init?(environment: [String: String]) {
        guard let settle = environment["FST_PERF_AUTORUN"].flatMap(Double.init), settle >= 0 else { return nil }
        self.settle = settle
        file = environment["FST_PERF_FILE"].flatMap { $0.isEmpty ? nil : $0 }
        name = environment["FST_PERF_NAME"].flatMap { $0.isEmpty ? nil : $0 } ?? "surface"
        seconds = environment["FST_PERF_SECONDS"].flatMap(Double.init).map { max($0, 0.5) } ?? 8
        speed = environment["FST_PERF_SPEED"].flatMap(Double.init) ?? 900
        horizontal = environment["FST_PERF_AXIS"] == "horizontal"
        navRoutes = (environment["FST_PERF_NAV"] ?? "").split(separator: ";").map { String($0) }
        navCycles = environment["FST_PERF_NAV_CYCLES"].flatMap(Int.init).map { max($0, 1) } ?? 6
    }
}

/// One line of the result file.
enum PerfLine {
    /// Marker that opens every data line.
    static let tag = "FSTPERF"
    /// Marker of the last line (the host stops waiting on it).
    static let done = "FSTPERF_DONE"

    /// A data line.
    ///
    /// - Parameters:
    ///   - name: Surface name.
    ///   - kind: `launch`, `idle`, `scroll`, `push` or `pop`.
    ///   - summary: `key=value` pairs (or an error text).
    /// - Returns: `FSTPERF<TAB>name<TAB>kind<TAB>summary<NL>`.
    static func row(name: String, kind: String, summary: String) -> String {
        "\(tag)\t\(name)\t\(kind)\t\(summary.replacingOccurrences(of: "\t", with: " ").replacingOccurrences(of: "\n", with: " "))\n"
    }
}

// MARK: - Frame pacing arithmetic

/// Dropped frames and hitch time from display-link timestamps (pure; ``FramePacer`` feeds it).
struct HitchTally: Equatable {
    /// Frames delivered.
    private(set) var frames = 0
    /// Refreshes the main thread missed.
    private(set) var dropped = 0
    /// Seconds beyond the expected interval, summed over late frames.
    private(set) var hitchSeconds = 0.0
    private var last: Double?

    /// Records one display-link callback.
    ///
    /// - Parameters:
    ///   - timestamp: The callback's timestamp, seconds.
    ///   - expected: The display's frame interval, seconds (0 when unknown).
    mutating func record(timestamp: Double, expected: Double) {
        defer { last = timestamp }
        frames += 1
        guard let last, expected > 0 else { return }
        let interval = timestamp - last
        // A frame that arrives one or more refresh intervals late: the missed refreshes are dropped frames, and the time
        // past the expected interval is hitch time.
        let missed = Int((interval / expected).rounded()) - 1
        if missed > 0 {
            dropped += missed
            hitchSeconds += interval - expected
        }
    }
}
