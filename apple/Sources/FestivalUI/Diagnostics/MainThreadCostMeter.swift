import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Main-thread cost

/// What a stretch of time cost the process and its main thread, measured identically in the SwiftUI app and its UIKit
/// port (`tools/uikit_perf.py`, [uikit-perf.md](../../../../../.agents/testing/apple/uikit-perf.md)).
///
/// **Why it exists.** Frame hitch ratios from a simulator mean little, and an XCUITest swipe drags the app's own
/// accessibility snapshots into the number. This measures the app's CPU (which does not move with other work on the Mac)
/// and, per run-loop turn, how long the main thread computed: a turn longer than a frame's budget is a hitch whatever the
/// display link says.
///
/// Usage: ``begin()`` then ``finish()``. Main thread only.
@MainActor
final class MainThreadCostMeter {
    /// One turn of the main run loop, from waking to going back to sleep.
    struct Turn: Sendable, Equatable {
        /// CPU time the main thread spent in the turn, in milliseconds.
        var cpuMs: Double
    }

    /// The result of a measured stretch.
    struct Report: Sendable, Equatable {
        /// Wall seconds measured.
        var seconds: Double
        /// CPU instructions the whole process retired, in millions (0 where the system does not report them).
        var megaInstructions: Double
        /// CPU seconds the whole process used.
        var processCPUSeconds: Double
        /// CPU seconds the main thread used.
        var mainCPUSeconds: Double
        /// Run-loop turns the main thread ran.
        var turns: Int
        /// Turns that computed for more than 4, 8 and 16 ms (half a frame at 120 Hz, a frame at 120 Hz, a frame at 60 Hz).
        var turnsOver4: Int
        var turnsOver8: Int
        var turnsOver16: Int
        /// The longest turn's CPU time and the 95th percentile, in milliseconds.
        var worstTurnMs: Double
        var p95TurnMs: Double
        /// How far a driver scrolled during the run, in points (set by the caller; 0 for an idle run).
        var travelledPoints = 0.0
        /// Extra `key=value` pairs a caller appends.
        var note = ""

        /// `key=value` pairs on one line (the format `tools/uikit_perf_report.py` parses).
        var summary: String {
            [
                "seconds=\(PerfFormat.number(seconds))", "minstr=\(PerfFormat.number(megaInstructions))",
                "cpu_ms=\(PerfFormat.number(processCPUSeconds * 1000))", "main_ms=\(PerfFormat.number(mainCPUSeconds * 1000))",
                "turns=\(turns)", "over4=\(turnsOver4)", "over8=\(turnsOver8)", "over16=\(turnsOver16)",
                "worst_ms=\(PerfFormat.number(worstTurnMs))", "p95_ms=\(PerfFormat.number(p95TurnMs))",
                "travelled=\(Int(travelledPoints))",
            ].joined(separator: " ") + (note.isEmpty ? "" : " " + note)
        }
    }

    private var startWall: ContinuousClock.Instant?
    private var startProcess = ProcessCPU.Snapshot.zero
    private var startMain = 0.0
    private var turns: [Turn] = []
    private var observer: CFRunLoopObserver?
    private var turnStart: Double?

    /// Starts measuring: the process's counters now, and every main run-loop turn from here.
    func begin() {
        guard startWall == nil else { return }
        turns.removeAll(keepingCapacity: true)
        startWall = .now
        startProcess = ProcessCPU.snapshot()
        startMain = ProcessCPU.currentThreadSeconds()
        // After waking a turn starts, before sleeping it ends; in the common modes so scrolling's tracking mode counts.
        let activities = CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue
        let observer = CFRunLoopObserverCreateWithHandler(kCFAllocatorDefault, activities, true, Int.max) { [weak self] _, activity in
            MainActor.assumeIsolated { self?.record(activity) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    /// Stops measuring.
    ///
    /// - Returns: What the stretch cost.
    func finish() -> Report {
        if let observer {
            CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = nil
        }
        let wall = startWall.map { (ContinuousClock.now - $0).seconds } ?? 0
        let process = ProcessCPU.snapshot()
        let main = ProcessCPU.currentThreadSeconds() - startMain
        startWall = nil
        return Self.report(seconds: wall, process: process - startProcess, mainSeconds: main, turns: turns)
    }

    private func record(_ activity: CFRunLoopActivity) {
        if activity.contains(.afterWaiting) {
            turnStart = ProcessCPU.currentThreadSeconds()
        } else if activity.contains(.beforeWaiting), let start = turnStart {
            turns.append(Turn(cpuMs: (ProcessCPU.currentThreadSeconds() - start) * 1000))
            turnStart = nil
        }
    }

    /// The report for measured numbers (separate from the clocks so it can be tested).
    ///
    /// - Parameters:
    ///   - seconds: Wall seconds measured.
    ///   - process: The process counters' difference over the stretch.
    ///   - mainSeconds: Main-thread CPU seconds over the stretch.
    ///   - turns: Every run-loop turn of the stretch.
    /// - Returns: The report.
    static func report(seconds: Double, process: ProcessCPU.Snapshot, mainSeconds: Double, turns: [Turn]) -> Report {
        let sorted = turns.map(\.cpuMs).sorted()
        return Report(
            seconds: seconds,
            megaInstructions: Double(process.instructions) / 1_000_000,
            processCPUSeconds: process.cpuSeconds,
            mainCPUSeconds: mainSeconds,
            turns: turns.count,
            turnsOver4: turns.filter { $0.cpuMs > 4 }.count,
            turnsOver8: turns.filter { $0.cpuMs > 8 }.count,
            turnsOver16: turns.filter { $0.cpuMs > 16 }.count,
            worstTurnMs: sorted.last ?? 0,
            p95TurnMs: PerfStats.percentile(sorted, 0.95)
        )
    }
}

// MARK: - Statistics and formatting

/// Pure helpers shared by the probes (unit-tested in `PerfProbeTests`).
enum PerfStats {
    /// A percentile of an ascending list (nearest rank, like the HASS meter).
    ///
    /// - Parameters:
    ///   - sorted: Values in ascending order.
    ///   - fraction: 0...1.
    /// - Returns: The value at that rank, 0 for an empty list.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        return sorted[min(sorted.count - 1, max(0, Int(Double(sorted.count) * fraction)))]
    }

    /// The median of an unsorted list (0 when empty).
    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Number formatting for the `key=value` result lines.
enum PerfFormat {
    /// Two decimals, no locale.
    static func number(_ value: Double) -> String { String(format: "%.2f", value) }
    /// One decimal, no locale.
    static func oneDecimal(_ value: Double) -> String { String(format: "%.1f", value) }
}

private extension Duration {
    var seconds: Double { Double(components.seconds) + Double(components.attoseconds) / 1e18 }
}

// MARK: - Process counters

#if canImport(Darwin)
// libproc's `proc_pid_rusage` is in every iOS system, but its header is not part of the Swift Darwin module.
@_silgen_name("proc_pid_rusage")
private func fst_proc_pid_rusage(_ pid: Int32, _ flavor: Int32, _ buffer: UnsafeMutableRawPointer) -> Int32
#endif

/// The process's and the current thread's CPU counters.
enum ProcessCPU {
    /// A reading of the process's counters.
    struct Snapshot: Sendable, Equatable {
        /// Instructions retired by the process (0 where the system does not report them).
        var instructions: UInt64
        /// User plus system CPU seconds.
        var cpuSeconds: Double

        static let zero = Snapshot(instructions: 0, cpuSeconds: 0)

        static func - (lhs: Snapshot, rhs: Snapshot) -> Snapshot {
            Snapshot(instructions: lhs.instructions &- rhs.instructions, cpuSeconds: lhs.cpuSeconds - rhs.cpuSeconds)
        }
    }

    /// The process's counters now (`proc_pid_rusage`).
    static func snapshot() -> Snapshot {
        #if canImport(Darwin)
        var info = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &info) { fst_proc_pid_rusage(getpid(), RUSAGE_INFO_V4, UnsafeMutableRawPointer($0)) }
        guard status == 0 else { return .zero }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let nanoseconds = Double(info.ri_user_time &+ info.ri_system_time) * Double(timebase.numer) / Double(timebase.denom)
        return Snapshot(instructions: info.ri_instructions, cpuSeconds: nanoseconds / 1_000_000_000)
        #else
        return .zero
        #endif
    }

    /// Seconds since this process started (`sysctl` `kern.proc.pid`), 0 where the system does not say.
    static func secondsSinceProcessStart() -> Double {
        #if canImport(Darwin)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0 else { return 0 }
        let start = info.kp_proc.p_un.__p_starttime
        return max(0, Date().timeIntervalSince1970 - (Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000))
        #else
        return 0
        #endif
    }

    /// CPU seconds (user plus system) the calling thread has used.
    static func currentThreadSeconds() -> Double {
        #if canImport(Darwin)
        var info = thread_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { return 0 }
        func seconds(_ value: time_value_t) -> Double { Double(value.seconds) + Double(value.microseconds) / 1_000_000 }
        return seconds(info.user_time) + seconds(info.system_time)
        #else
        return 0
        #endif
    }
}
