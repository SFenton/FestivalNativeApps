import Foundation
import QuartzCore

// MARK: - Main-thread stall monitor (Debug)

/// Debug-only main run loop stall recorder for UI stress tests (issue #8).
///
/// Started at launch when `FST_DEBUG_STALL_LOG=<absolute path>` is set (Debug builds
/// only; Release never compiles it in). A run loop observer timestamps every main run
/// loop activity; the time between two consecutive activities, other than the sleep
/// between `beforeWaiting` and `afterWaiting`, is one uninterrupted unit of main-thread
/// work during which touches and frames cannot be processed. Apple's Instruments counts
/// such a unit longer than 250 ms as a hang.
///
/// The awake span (from wake-up to the next sleep) is also tracked: a feedback loop that
/// keeps re-scheduling short work (issue #5's toolbar loop) never sleeps even though each
/// unit is short.
///
/// Each update rewrites the log file with one JSON object
/// (``MainThreadStallReport``), so a UI test can read the worst stall after a stress pass.
/// The simulator shares the host file system, so the test runner can read the same path.
public enum MainThreadStallMonitor {
    /// Environment key naming the report file.
    public static let environmentKey = "FST_DEBUG_STALL_LOG"

    /// Units of work at least this long are listed individually in the report.
    static let reportThreshold: CFTimeInterval = 0.1

    /// Start observing the main run loop when the environment asks for it.
    ///
    /// Call once from the app's initializer; later calls do nothing.
    @MainActor
    public static func startIfRequested() {
        #if DEBUG
        guard observer == nil,
              let path = ProcessInfo.processInfo.environment[environmentKey],
              path.hasPrefix("/") else { return }
        let recorder = MainThreadStallRecorder(url: URL(fileURLWithPath: path))
        recorder.write()
        let created = CFRunLoopObserverCreateWithHandler(
            kCFAllocatorDefault, CFRunLoopActivity.allActivities.rawValue, true, 0
        ) { _, activity in
            recorder.record(activity, at: CACurrentMediaTime())
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), created, .commonModes)
        observer = created
        self.recorder = recorder
        #endif
    }

    /// Count one occurrence of a named event (for example a view body evaluation)
    /// while monitoring; does nothing otherwise and in Release builds.
    ///
    /// - Parameter name: The counter key in ``MainThreadStallReport/counters``.
    @MainActor
    public static func count(_ name: String) {
        #if DEBUG
        recorder?.count(name)
        #endif
    }

    /// Record a sampled value while monitoring, keeping the largest seen per name (for
    /// example the Songs List's top content inset, issue #383); does nothing otherwise
    /// and in Release builds.
    ///
    /// - Parameters:
    ///   - name: The key in ``MainThreadStallReport/peaks``.
    ///   - value: The sample; non-finite samples are ignored.
    @MainActor
    public static func peak(_ name: String, _ value: Double) {
        #if DEBUG
        recorder?.peak(name, value)
        #endif
    }

    #if DEBUG
    @MainActor private static var observer: CFRunLoopObserver?
    @MainActor private static var recorder: MainThreadStallRecorder?
    #endif
}

/// The JSON written by ``MainThreadStallMonitor``.
public struct MainThreadStallReport: Codable, Equatable, Sendable {
    /// Longest uninterrupted unit of main-thread work, in milliseconds.
    public var maxStallMs: Double = 0
    /// Longest span the main run loop stayed awake without sleeping, in milliseconds.
    public var maxAwakeMs: Double = 0
    /// Every unit of work of at least 100 ms, oldest first (at most 200).
    public var stalls: [Stall] = []
    /// Named event counts from ``MainThreadStallMonitor/count(_:)``.
    public var counters: [String: Int] = [:]
    /// Seconds since monitoring started when each counter was first counted, so a
    /// reader can keep only the stalls between two marks (e.g. a stress pass's start
    /// and end, excluding launch work). Optional for reports written before it existed.
    public var marks: [String: Double]? = nil
    /// Main-thread CPU seconds (`CLOCK_THREAD_CPUTIME_ID`) when each counter was first
    /// counted. The CPU spent between a pass's marks barely moves when other processes
    /// load the host, unlike the wall-clock stall units. Optional for older reports.
    public var cpuMarks: [String: Double]? = nil
    /// The largest sample per name from ``MainThreadStallMonitor/peak(_:_:)``, rounded to
    /// 0.5. Optional for older reports.
    public var peaks: [String: Double]? = nil

    /// One long unit of main-thread work.
    public struct Stall: Codable, Equatable, Sendable {
        /// Seconds since monitoring started when the unit ended.
        public var at: Double
        /// The unit's length in milliseconds.
        public var ms: Double
        /// Named events counted during the unit (``MainThreadStallMonitor/count(_:)``,
        /// e.g. row bodies built), so a stress report shows what the unit did. Nil
        /// when none were counted.
        public var counts: [String: Int]? = nil
    }

    /// An empty report.
    public init() {}
}

#if DEBUG
/// Folds run loop activity timestamps into a ``MainThreadStallReport``.
///
/// Only touched from the main run loop's observer callback.
final class MainThreadStallRecorder: @unchecked Sendable {
    private let url: URL
    private let startedAt: CFTimeInterval
    private let clock: () -> CFTimeInterval
    private(set) var report = MainThreadStallReport()
    private var lastActivityAt: CFTimeInterval?
    private var awakeSince: CFTimeInterval?
    private var sleeping = false
    private var countersDirty = false
    private var lastWriteAt: CFTimeInterval = 0
    /// Events counted since the last run loop activity (the unit in progress).
    private var unitCounts: [String: Int] = [:]

    /// - Parameters:
    ///   - url: The report file, rewritten on every change.
    ///   - startedAt: Origin for ``MainThreadStallReport/Stall/at``.
    ///   - clock: Times the recorder's own file writes (tests pass a fixed clock).
    init(
        url: URL, startedAt: CFTimeInterval = CACurrentMediaTime(),
        clock: @escaping () -> CFTimeInterval = CACurrentMediaTime
    ) {
        self.url = url
        self.startedAt = startedAt
        self.clock = clock
    }

    /// Fold one run loop activity into the report.
    ///
    /// - Parameters:
    ///   - activity: The run loop activity being entered.
    ///   - now: Its timestamp (`CACurrentMediaTime`).
    /// - Returns: True when the report changed.
    @discardableResult
    func record(_ activity: CFRunLoopActivity, at now: CFTimeInterval) -> Bool {
        var changed = false
        if let last = lastActivityAt, !sleeping {
            let unit = now - last
            if unit * 1000 > report.maxStallMs {
                report.maxStallMs = (unit * 1000).rounded()
                changed = true
            }
            if unit >= MainThreadStallMonitor.reportThreshold, report.stalls.count < 200 {
                report.stalls.append(.init(
                    at: ((now - startedAt) * 10).rounded() / 10, ms: (unit * 1000).rounded(),
                    counts: unitCounts.isEmpty ? nil : unitCounts
                ))
                changed = true
            }
        }
        unitCounts.removeAll(keepingCapacity: true)
        switch activity {
        case .beforeWaiting:
            if let awakeSince, (now - awakeSince) * 1000 > report.maxAwakeMs {
                report.maxAwakeMs = ((now - awakeSince) * 1000).rounded()
                changed = true
            }
            awakeSince = nil
            sleeping = true
            if countersDirty, now - lastWriteAt >= 0.5 { changed = true }
        default:
            awakeSince = awakeSince ?? now
            sleeping = false
        }
        lastActivityAt = now
        if changed {
            // Writing is main-thread work too; never charge it to the next unit.
            let writeStart = clock()
            write()
            lastActivityAt = now + (clock() - writeStart)
        }
        return changed
    }

    /// Count one named event; flushed to disk at the next idle, at most twice a second.
    func count(_ name: String) {
        report.counters[name, default: 0] += 1
        unitCounts[name, default: 0] += 1
        if report.marks?[name] == nil {
            report.marks = report.marks ?? [:]
            report.marks?[name] = ((clock() - startedAt) * 10).rounded() / 10
            report.cpuMarks = report.cpuMarks ?? [:]
            report.cpuMarks?[name] = (threadCPU() * 1000).rounded() / 1000
        }
        countersDirty = true
    }

    /// Keep the largest sample of `name`; flushed like the counters.
    func peak(_ name: String, _ value: Double) {
        guard value.isFinite else { return }
        let rounded = (value * 2).rounded() / 2
        if let current = report.peaks?[name], current >= rounded { return }
        report.peaks = report.peaks ?? [:]
        report.peaks?[name] = rounded
        countersDirty = true
    }

    /// CPU seconds used by the calling thread (the main thread for counters).
    private func threadCPU() -> Double {
        var time = timespec()
        guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time) == 0 else { return 0 }
        return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
    }

    /// Rewrite the report file (best effort; a failed write keeps the old report).
    func write() {
        guard let data = try? JSONEncoder().encode(report) else { return }
        try? data.write(to: url, options: .atomic)
        countersDirty = false
        lastWriteAt = clock()
    }
}
#endif
